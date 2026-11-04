import 'package:flutter/foundation.dart';
import '../db.dart';
import 'api_client.dart';
import 'token_storage.dart';

class AuthUser {
  final String id;
  final String email;
  final String? displayName;

  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
  });

  String get presentationName {
    if (displayName != null && displayName!.trim().isNotEmpty) {
      return displayName!.trim();
    }
    return email.split('@').first;
  }
}

class AuthService extends ChangeNotifier {
  static final AuthService instance = AuthService._();
  AuthService._() {
    _apiClient = ApiClient(
      tokenStorage: _tokenStorage,
      onSessionExpired: _handleSessionExpired,
    );
  }

  /// Factory constructor for tests
  factory AuthService.forTest({
    required TokenStorage tokenStorage,
    required ApiClient apiClient,
    AppDb? appDb,
  }) {
    final service = AuthService._test(tokenStorage, apiClient, appDb);
    apiClient.onSessionExpired = service._handleSessionExpired;
    return service;
  }

  AuthService._test(this._tokenStorage, this._apiClient, this._appDb);

  TokenStorage _tokenStorage = SecureTokenStorage();
  late ApiClient _apiClient;
  AppDb? _appDb;

  AppDb get _db => _appDb ?? AppDb.instance;
  ApiClient get apiClient => _apiClient;
  TokenStorage get tokenStorage => _tokenStorage;

  AuthUser? _user;
  AuthUser? get user => _user;
  bool get isAuthenticated => _user != null;
  bool get isGuest => _user == null;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  void _handleSessionExpired() {
    _user = null;
    _db.switchToUser(null);
    notifyListeners();
  }

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();
    try {
      await _apiClient.init();
      final refreshToken = await _tokenStorage.getRefreshToken();
      final userId = await _tokenStorage.getUserId();
      final email = await _tokenStorage.getUserEmail();
      final displayName = await _tokenStorage.getUserDisplayName();

      if (refreshToken != null && userId != null && email != null) {
        _user = AuthUser(id: userId, email: email, displayName: displayName);
        await _db.switchToUser(userId);
      } else {
        _user = null;
        await _db.switchToUser(null);
      }
    } catch (_) {
      _user = null;
      await _db.switchToUser(null);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiClient.request(
        method: 'POST',
        endpoint: '/api/auth/register',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
        retryOn401: false,
      );
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiClient.request(
        method: 'POST',
        endpoint: '/api/auth/login',
        body: {
          'email': email.trim().toLowerCase(),
          'password': password,
        },
        retryOn401: false,
      ) as Map<String, dynamic>;

      final accessToken = res['accessToken'] as String? ?? res['token'] as String;
      final refreshToken = res['refreshToken'] as String?;
      final userId = res['userId'] as String? ?? '';
      final userEmail = res['email'] as String? ?? email.trim().toLowerCase();
      final displayName = res['displayName'] as String?;

      await _tokenStorage.setAccessToken(accessToken);
      if (refreshToken != null) {
        await _tokenStorage.setRefreshToken(refreshToken);
      }
      await _tokenStorage.setUserId(userId);
      await _tokenStorage.setUserEmail(userEmail);
      await _tokenStorage.setUserDisplayName(displayName);

      _user = AuthUser(id: userId, email: userEmail, displayName: displayName);

      // Switch active database to this user's isolated database
      await _db.switchToUser(userId);
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      final refreshToken = await _tokenStorage.getRefreshToken();
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _apiClient.request(
          method: 'POST',
          endpoint: '/api/auth/logout',
          body: {'refreshToken': refreshToken},
          retryOn401: false,
        );
      }
    } catch (_) {
      // Allow offline logout even if network request fails
    } finally {
      await _tokenStorage.clearAll();
      _user = null;
      await _db.switchToUser(null);
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logoutAll() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _apiClient.request(
        method: 'POST',
        endpoint: '/api/auth/logout-all',
        retryOn401: true,
      );
    } catch (_) {}

    await _tokenStorage.clearAll();
    _user = null;
    await _db.switchToUser(null);
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateDisplayName(String newName) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final res = await _apiClient.request(
        method: 'PATCH',
        endpoint: '/api/user/profile',
        body: {'displayName': newName.trim()},
      ) as Map<String, dynamic>;

      final updatedName = res['displayName'] as String?;
      await _tokenStorage.setUserDisplayName(updatedName);
      if (_user != null) {
        _user = AuthUser(id: _user!.id, email: _user!.email, displayName: updatedName);
      }
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> changePassword(String currentPassword, String newPassword) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _apiClient.request(
        method: 'POST',
        endpoint: '/api/user/change-password',
        body: {
          'currentPassword': currentPassword,
          'newPassword': newPassword,
        },
      );

      // Server revokes all refresh sessions on password change
      await _tokenStorage.clearAll();
      _user = null;
      await _db.switchToUser(null);
    } catch (e) {
      _errorMessage = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<int> copyGuestDataToAccount() async {
    if (isGuest) {
      throw StateError('Сначала войдите в аккаунт');
    }
    return await _db.copyGuestDataToCurrentAccount();
  }
}
