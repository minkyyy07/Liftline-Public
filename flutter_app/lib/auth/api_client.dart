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

  ApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

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

  ApiClient({
    String? baseUrl,
    TokenStorage? tokenStorage,
    http.Client? client,
    this.onSessionExpired,
  })  : _baseUrl = baseUrl ?? (Platform.isAndroid ? defaultEmulatorUrl : defaultLocalhostUrl),
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

  Future<bool> _refreshAccessToken() async {
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }
    final completer = Completer<bool>();
    _refreshCompleter = completer;

    try {
      final refreshToken = await tokenStorage.getRefreshToken();
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

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        final newAccess = data['accessToken'] as String?;
        final newRefresh = data['refreshToken'] as String?;
        if (newAccess != null) {
          await tokenStorage.setAccessToken(newAccess);
        }
        if (newRefresh != null) {
          await tokenStorage.setRefreshToken(newRefresh);
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
      _refreshCompleter = null;
    }
  }

  Future<dynamic> request({
    required String method,
    required String endpoint,
    Map<String, String>? headers,
    Object? body,
    bool retryOn401 = true,
  }) async {
    final uri = Uri.parse('$_baseUrl$endpoint');
    final allHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?headers,
    };

    final token = await tokenStorage.getAccessToken();
    if (token != null && token.isNotEmpty && !allHeaders.containsKey('Authorization')) {
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
          res = await _client.patch(uri, headers: allHeaders, body: encodedBody);
          break;
        case 'DELETE':
          res = await _client.delete(uri, headers: allHeaders, body: encodedBody);
          break;
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }
    } on SocketException {
      throw ApiException(
        statusCode: 0,
        message: 'Не удалось подключиться к серверу ($_baseUrl). Проверьте интернет или адрес сервера.',
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        statusCode: 0,
        message: 'Ошибка сети: $e',
      );
    }

    if (res.statusCode == 401 && retryOn401) {
      final refreshed = await _refreshAccessToken();
      if (refreshed) {
        // Retry once with new token
        return request(
          method: method,
          endpoint: endpoint,
          headers: headers,
          body: body,
          retryOn401: false,
        );
      } else {
        await tokenStorage.clearAll();
        onSessionExpired?.call();
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
      final errorJson = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
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
