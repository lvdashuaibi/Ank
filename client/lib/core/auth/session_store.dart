import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore {
  static const String _tokenKey = 'access_token';
  static const String _emailKey = 'user_email';
  static const String _nameKey = 'display_name';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveSession({
    required String accessToken,
    required String email,
    required String displayName,
  }) async {
    try {
      await _storage.write(key: _tokenKey, value: accessToken);
      await _storage.write(key: _emailKey, value: email);
      await _storage.write(key: _nameKey, value: displayName);
    } catch (_) {
      return;
    }
  }

  Future<StoredSession?> readSession() async {
    try {
      final String? token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) {
        return null;
      }
      return StoredSession(
        accessToken: token,
        email: await _storage.read(key: _emailKey) ?? '',
        displayName: await _storage.read(key: _nameKey) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _nameKey);
    } catch (_) {
      return;
    }
  }
}

class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.email,
    required this.displayName,
  });

  final String accessToken;
  final String email;
  final String displayName;
}
