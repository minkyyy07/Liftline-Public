import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class TokenStorage {
  Future<String?> getAccessToken();
  Future<void> setAccessToken(String? token);

  Future<String?> getRefreshToken();
  Future<void> setRefreshToken(String? token);

  Future<String?> getUserId();
  Future<void> setUserId(String? userId);

  Future<String?> getUserEmail();
  Future<void> setUserEmail(String? email);

  Future<String?> getUserDisplayName();
  Future<void> setUserDisplayName(String? name);

  Future<void> clearAll();
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;
  final Map<String, String> _memoryFallback = {};

  SecureTokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
              iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
            );

  static const _kAccess = 'liftspire_access_token';
  static const _kRefresh = 'liftspire_refresh_token';
  static const _kUserId = 'liftspire_user_id';
  static const _kEmail = 'liftspire_user_email';
  static const _kDisplayName = 'liftspire_user_display_name';

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key) ?? _memoryFallback[key];
    } catch (_) {
      return _memoryFallback[key];
    }
  }

  Future<void> _write(String key, String? value) async {
    if (value == null) {
      _memoryFallback.remove(key);
      try {
        await _storage.delete(key: key);
      } catch (_) {}
    } else {
      _memoryFallback[key] = value;
      try {
        await _storage.write(key: key, value: value);
      } catch (_) {}
    }
  }

  @override
  Future<String?> getAccessToken() => _read(_kAccess);

  @override
  Future<void> setAccessToken(String? token) => _write(_kAccess, token);

  @override
  Future<String?> getRefreshToken() => _read(_kRefresh);

  @override
  Future<void> setRefreshToken(String? token) => _write(_kRefresh, token);

  @override
  Future<String?> getUserId() => _read(_kUserId);

  @override
  Future<void> setUserId(String? userId) => _write(_kUserId, userId);

  @override
  Future<String?> getUserEmail() => _read(_kEmail);

  @override
  Future<void> setUserEmail(String? email) => _write(_kEmail, email);

  @override
  Future<String?> getUserDisplayName() => _read(_kDisplayName);

  @override
  Future<void> setUserDisplayName(String? name) => _write(_kDisplayName, name);

  @override
  Future<void> clearAll() async {
    _memoryFallback.clear();
    try {
      await _storage.deleteAll();
    } catch (_) {}
  }
}

class InMemoryTokenStorage implements TokenStorage {
  final Map<String, String?> _values = {};

  @override
  Future<String?> getAccessToken() async => _values['access'];

  @override
  Future<void> setAccessToken(String? token) async => _values['access'] = token;

  @override
  Future<String?> getRefreshToken() async => _values['refresh'];

  @override
  Future<void> setRefreshToken(String? token) async => _values['refresh'] = token;

  @override
  Future<String?> getUserId() async => _values['userId'];

  @override
  Future<void> setUserId(String? userId) async => _values['userId'] = userId;

  @override
  Future<String?> getUserEmail() async => _values['email'];

  @override
  Future<void> setUserEmail(String? email) async => _values['email'] = email;

  @override
  Future<String?> getUserDisplayName() async => _values['displayName'];

  @override
  Future<void> setUserDisplayName(String? name) async => _values['displayName'] = name;

  @override
  Future<void> clearAll() async => _values.clear();
}
