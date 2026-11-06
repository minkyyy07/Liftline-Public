import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'token_storage.dart';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? details;

  ApiException({required this.statusCode, required this.message, this.details});

  @override
  String toString() => message;
}

class SessionAbortedException implements Exception {
  final String message;
  SessionAbortedException([
    this.message = 'Операция отменена из-за смены сессии пользователя.',
  ]);
  @override
  String toString() => message;
}

class ApiClient {
  static const String _kBaseUrlPrefKey = 'liftspire_api_base_url';
  static const String defaultEmulatorUrl = 'http://10.0.2.2:8080';
  static const String defaultLocalhostUrl = 'http://127.0.0.1:8080';

  String _baseUrl;
  final TokenStorage tokenStorage;
  final http.Client _client;
  void Function()? onSessionExpired;

  int _sessionGeneration = 0;
  String? _sessionAccountId;
  bool _sessionTransitionPending = false;
  Future<void> _tokenOperationQueue = Future<void>.value();

  int get sessionGeneration => _sessionGeneration;
  String? get sessionAccountId => _sessionAccountId;

  /// Updates the active session generation and account ID.
  /// Cancels in-flight refreshes and prevents stale requests from mutating state.
  void switchSession(String? newAccountId) {
    _sessionGeneration++;
    _sessionAccountId = newAccountId;
    _sessionTransitionPending = false;
    _refreshCompleter = null;
  }

  int reserveSessionChange() {
    _sessionGeneration++;
    _sessionTransitionPending = true;
    _refreshCompleter = null;
    return _sessionGeneration;
  }

  void cancelSessionChange(int expectedGeneration) {
    if (_sessionGeneration == expectedGeneration) {
      _sessionTransitionPending = false;
    }
  }

  bool isCurrentSession(String? expectedAccountId, int expectedGeneration) {
    return _sessionAccountId == expectedAccountId &&
        _sessionGeneration == expectedGeneration;
  }

  Future<T> _withTokenOperation<T>(Future<T> Function() operation) async {
    final previous = _tokenOperationQueue;
    final release = Completer<void>();
    _tokenOperationQueue = release.future;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
    }
  }

  Future<String?> getRefreshTokenForSession(String? accountId, int generation) {
    return _withTokenOperation(() async {
      if (!isCurrentSession(accountId, generation)) {
        throw SessionAbortedException();
      }
      final token = await tokenStorage.getRefreshToken();
      if (!isCurrentSession(accountId, generation)) {
        throw SessionAbortedException();
      }
      return token;
    });
  }

  Future<int?> commitLoginSession({
    required int expectedGeneration,
    required String accountId,
    required String accessToken,
    required String? refreshToken,
    required String email,
    required String? displayName,
  }) {
    return _withTokenOperation(() async {
      if (_sessionGeneration != expectedGeneration ||
          !_sessionTransitionPending) {
        return null;
      }

      await tokenStorage.setTokens(accessToken, refreshToken);
      if (_sessionGeneration != expectedGeneration) return null;
      await tokenStorage.setUserId(accountId);
      if (_sessionGeneration != expectedGeneration) return null;
      await tokenStorage.setUserEmail(email);
      if (_sessionGeneration != expectedGeneration) return null;
      await tokenStorage.setUserDisplayName(displayName);
      if (_sessionGeneration != expectedGeneration) return null;

      switchSession(accountId);
      return _sessionGeneration;
    });
  }

  Future<int?> clearSessionIfCurrent({
    required String? accountId,
    required int generation,
    bool notifyExpired = false,
  }) {
    return _withTokenOperation(() async {
      if (!isCurrentSession(accountId, generation)) return null;

      await tokenStorage.clearAll();
      if (!isCurrentSession(accountId, generation)) return null;

      if (notifyExpired) onSessionExpired?.call();
      if (isCurrentSession(accountId, generation)) switchSession(null);
      return _sessionGeneration;
    });
  }

  ApiClient({
    String? baseUrl,
    TokenStorage? tokenStorage,
    http.Client? client,
    this.onSessionExpired,
  }) : _baseUrl =
           baseUrl ??
           (Platform.isAndroid ? defaultEmulatorUrl : defaultLocalhostUrl),
       tokenStorage = tokenStorage ?? SecureTokenStorage(),
       _client = client ?? http.Client();

  String get baseUrl => _baseUrl;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_kBaseUrlPrefKey);
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        _baseUrl = savedUrl.trim();
      }
    } catch (_) {}
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = url.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kBaseUrlPrefKey, _baseUrl);
    } catch (_) {}
  }

  Completer<bool>? _refreshCompleter;
  int _refreshGeneration = -1;
  String? _refreshAccountId;

  Future<bool> _refreshAccessToken(String? accountId, int generation) async {
    if (!isCurrentSession(accountId, generation)) return false;

    if (_refreshCompleter != null &&
        _refreshGeneration == generation &&
        _refreshAccountId == accountId) {
      return _refreshCompleter!.future;
    }

    final completer = Completer<bool>();
    _refreshCompleter = completer;
    _refreshGeneration = generation;
    _refreshAccountId = accountId;

    try {
      if (!isCurrentSession(accountId, generation)) {
        completer.complete(false);
        return false;
      }

      final refreshToken = await _withTokenOperation(() async {
        if (!isCurrentSession(accountId, generation)) return null;
        final token = await tokenStorage.getRefreshToken();
        return isCurrentSession(accountId, generation) ? token : null;
      });
      if (!isCurrentSession(accountId, generation)) {
        completer.complete(false);
        return false;
      }

      if (refreshToken == null || refreshToken.isEmpty) {
        completer.complete(false);
        return false;
      }

      final url = Uri.parse('$_baseUrl/api/auth/refresh');
      final res = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );

      if (!isCurrentSession(accountId, generation)) {
        completer.complete(false);
        return false;
      }

      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess == null ||
            newAccess.isEmpty ||
            newRefresh == null ||
            newRefresh.isEmpty ||
            !isCurrentSession(accountId, generation)) {
          completer.complete(false);
          return false;
        }
        final committed = await _withTokenOperation(() async {
          if (!isCurrentSession(accountId, generation)) return false;
          await tokenStorage.setTokens(newAccess, newRefresh);
          return isCurrentSession(accountId, generation);
        });
        if (!committed) {
          completer.complete(false);
          return false;
        }
        completer.complete(true);
        return true;
      } else {
        completer.complete(false);
        return false;
      }
    } catch (_) {
      completer.complete(false);
      return false;
    } finally {
      if (_refreshGeneration == generation) {
        _refreshCompleter = null;
      }
    }
  }

  Future<dynamic> request({
    required String method,
    required String endpoint,
    Map<String, String>? headers,
    Object? body,
    bool retryOn401 = true,
  }) async {
    final reqAccountId = _sessionAccountId;
    final reqGeneration = _sessionGeneration;

    if (!isCurrentSession(reqAccountId, reqGeneration)) {
      throw SessionAbortedException();
    }

    final uri = Uri.parse('$_baseUrl$endpoint');
    final allHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };

    final isAuthEntryPoint =
        endpoint == '/api/auth/login' || endpoint == '/api/auth/register';
    final token =
        isAuthEntryPoint
            ? null
            : await _withTokenOperation(() async {
              if (!isCurrentSession(reqAccountId, reqGeneration)) {
                throw SessionAbortedException();
              }
              final accessToken = await tokenStorage.getAccessToken();
              if (!isCurrentSession(reqAccountId, reqGeneration)) {
                throw SessionAbortedException();
              }
              return accessToken;
            });
    if (!isCurrentSession(reqAccountId, reqGeneration)) {
      throw SessionAbortedException();
    }

    if (token != null &&
        token.isNotEmpty &&
        !allHeaders.containsKey('Authorization')) {
      allHeaders['Authorization'] = 'Bearer $token';
    }

    if (token != null &&
        token.isNotEmpty &&
        (headers == null || !headers.containsKey('Authorization'))) {
      allHeaders['Authorization'] = 'Bearer $token';
    }

    String? encodedBody;
    if (body != null) {
      encodedBody = body is String ? body : jsonEncode(body);
    }

    http.Response res;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          res = await _client.get(uri, headers: allHeaders);
          break;
        case 'POST':
          res = await _client.post(uri, headers: allHeaders, body: encodedBody);
          break;
        case 'PUT':
          res = await _client.put(uri, headers: allHeaders, body: encodedBody);
          break;
        case 'PATCH':
          res = await _client.patch(
            uri,
            headers: allHeaders,
            body: encodedBody,
          );
          break;
        case 'DELETE':
          res = await _client.delete(
            uri,
            headers: allHeaders,
            body: encodedBody,
          );
          break;
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }
    } on SocketException {
      if (!isCurrentSession(reqAccountId, reqGeneration))
        throw SessionAbortedException();
      throw ApiException(
        statusCode: 0,
        message:
            'Не удалось подключиться к серверу ($_baseUrl). Проверьте интернет или адрес сервера.',
      );
    } catch (e) {
      if (!isCurrentSession(reqAccountId, reqGeneration))
        throw SessionAbortedException();
      if (e is ApiException || e is SessionAbortedException) rethrow;
      throw ApiException(statusCode: 0, message: 'Ошибка сети: $e');
    }

    if (!isCurrentSession(reqAccountId, reqGeneration)) {
      throw SessionAbortedException();
    }

    if (res.statusCode == 401 && retryOn401) {
      final refreshed = await _refreshAccessToken(reqAccountId, reqGeneration);
      if (!isCurrentSession(reqAccountId, reqGeneration)) {
        throw SessionAbortedException();
      }

      if (refreshed) {
        // Retry once with new token within the same generation
        return request(
          method: method,
          endpoint: endpoint,
          headers: headers,
          body: body,
          retryOn401: false,
        );
      } else {
        final endedGeneration = await clearSessionIfCurrent(
          accountId: reqAccountId,
          generation: reqGeneration,
          notifyExpired: true,
        );
        if (endedGeneration == null) throw SessionAbortedException();
        throw ApiException(
          statusCode: 401,
          message: 'Сессия истекла. Пожалуйста, выполните вход снова.',
        );
      }
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      try {
        return jsonDecode(utf8.decode(res.bodyBytes));
      } catch (_) {
        return res.body;
      }
    }

    // Parse error response
    String errorMessage = 'Ошибка сервера (${res.statusCode})';
    Map<String, dynamic>? details;
    try {
      final errorJson =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (errorJson['error'] != null) {
        errorMessage = errorJson['error'].toString();
      } else if (errorJson['message'] != null) {
        errorMessage = errorJson['message'].toString();
      }
      if (errorJson['details'] is Map<String, dynamic>) {
        details = errorJson['details'] as Map<String, dynamic>;
      }
    } catch (_) {}

    throw ApiException(
      statusCode: res.statusCode,
      message: errorMessage,
      details: details,
    );
  }
}
