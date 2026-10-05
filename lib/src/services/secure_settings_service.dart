import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/models.dart';

class SecureSettingsService {
  static const _helloAssoSecretPrefix = 'helloasso_client_secret';
  static const _firebaseSettingsKey = 'firebase_settings';
  // The legacy macOS keychain works with Flutter's ad-hoc local signing.
  // The data-protection keychain requires a Developer ID entitlement.
  static const _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  String _helloAssoSecretKey(String? scope) =>
      '${_helloAssoSecretPrefix}_${scope ?? 'local'}';

  Future<FirebaseSettings?> loadFirebaseSettings() async {
    try {
      final value = await _storage.read(key: _firebaseSettingsKey);
      if (value == null || value.trim().isEmpty) return null;
      return FirebaseSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(value) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFirebaseSettings(FirebaseSettings settings) =>
      _storage.write(key: _firebaseSettingsKey, value: jsonEncode(settings));

  Future<void> clearFirebaseSettings() =>
      _storage.delete(key: _firebaseSettingsKey);

  Future<HelloAssoSettings> loadHelloAssoSettings(
    HelloAssoSettings storedSettings, {
    String? scope,
  }) async {
    final legacySecret = storedSettings.clientSecret.trim();
    if (legacySecret.isNotEmpty) {
      await _storage.write(
          key: _helloAssoSecretKey(scope), value: legacySecret);
      return storedSettings;
    }
    final scoped = await _storage.read(key: _helloAssoSecretKey(scope)) ?? '';
    if (scoped.isNotEmpty) return storedSettings.withSecret(scoped);
    if (scope != null) {
      // One-time adoption of the pre-scope secret by the first licence account.
      final fallback =
          await _storage.read(key: _helloAssoSecretKey(null)) ?? '';
      if (fallback.isNotEmpty) {
        await _storage.write(key: _helloAssoSecretKey(scope), value: fallback);
        await _storage.delete(key: _helloAssoSecretKey(null));
        return storedSettings.withSecret(fallback);
      }
    }
    return storedSettings.withSecret('');
  }

  Future<void> saveHelloAssoSecret(String value, {String? scope}) async {
    final secret = value.trim();
    if (secret.isEmpty) {
      await _storage.delete(key: _helloAssoSecretKey(scope));
    } else {
      await _storage.write(key: _helloAssoSecretKey(scope), value: secret);
    }
  }

  // Generic read/write/delete for license service
  Future<String?> read({required String key}) => _storage.read(key: key);
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);
  Future<void> delete({required String key}) => _storage.delete(key: key);
}