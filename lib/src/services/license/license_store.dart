import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../secure_settings_service.dart';
import 'license_models.dart';

const _envelopeKey = 'tilly_license_envelope';
const _stateKey = 'tilly_license_state';
const _deviceSecretKey = 'tilly_license_device_secret';

class LicenseStateData {
  const LicenseStateData({
    this.lastValidatedAt,
    this.lastServerTime,
    this.lastMachineId,
    this.hmac,
  });

  final DateTime? lastValidatedAt;
  final DateTime? lastServerTime;
  final String? lastMachineId;
  final String? hmac;

  Map<String, dynamic> toJson() {
    return {
      if (lastValidatedAt != null)
        'lastValidatedAt': lastValidatedAt!.toIso8601String(),
      if (lastServerTime != null)
        'lastServerTime': lastServerTime!.toIso8601String(),
      if (lastMachineId != null) 'lastMachineId': lastMachineId,
      if (hmac != null) 'hmac': hmac,
    };
  }

  factory LicenseStateData.fromJson(Map<String, dynamic> json) {
    return LicenseStateData(
      lastValidatedAt: json['lastValidatedAt'] != null
          ? DateTime.parse(json['lastValidatedAt'] as String)
          : null,
      lastServerTime: json['lastServerTime'] != null
          ? DateTime.parse(json['lastServerTime'] as String)
          : null,
      lastMachineId: json['lastMachineId'] as String?,
      hmac: json['hmac'] as String?,
    );
  }
}

class LicenseStore {
  LicenseStore(this._secureStorage);

  final SecureSettingsService _secureStorage;

  Future<LicenseEnvelope?> loadEnvelope() async {
    try {
      final value = await _secureStorage.read(key: _envelopeKey);
      if (value == null || value.trim().isEmpty) return null;
      return LicenseEnvelope.fromJson(
          jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEnvelope(LicenseEnvelope envelope) async {
    await _secureStorage.write(
        key: _envelopeKey, value: jsonEncode(envelope.toJson()));
  }

  Future<void> clearEnvelope() async {
    await _secureStorage.delete(key: _envelopeKey);
  }

  Future<LicenseStateData?> loadState() async {
    try {
      final value = await _secureStorage.read(key: _stateKey);
      if (value == null || value.trim().isEmpty) return null;
      return LicenseStateData.fromJson(
          jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveState(LicenseStateData state) async {
    await _secureStorage.write(
        key: _stateKey, value: jsonEncode(state.toJson()));
  }

  Future<void> clearState() async {
    await _secureStorage.delete(key: _stateKey);
  }

  Future<String> getOrCreateDeviceSecret() async {
    try {
      final value = await _secureStorage.read(key: _deviceSecretKey);
      if (value != null && value.trim().isNotEmpty) {
        return value;
      }
    } catch (_) {}
    final random = Random.secure();
    final bytes =
        Uint8List.fromList(List<int>.generate(32, (_) => random.nextInt(256)));
    final secret = base64UrlEncode(bytes);
    await _secureStorage.write(key: _deviceSecretKey, value: secret);
    return secret;
  }

  Future<void> clearDeviceSecret() async {
    await _secureStorage.delete(key: _deviceSecretKey);
  }

  Future<bool> verifyStateHmac(
      LicenseStateData state, String deviceSecret) async {
    if (state.hmac == null ||
        state.lastValidatedAt == null ||
        state.lastServerTime == null) {
      return false;
    }
    final key = SecretKey(base64UrlDecodeBytes(deviceSecret));
    final mac = await Hmac.sha256()
        .calculateMac(utf8.encode(_signatureInput(state)), secretKey: key);
    final expected = base64UrlDecodeBytes(state.hmac!);
    return _bytesEqual(mac.bytes, expected);
  }

  Future<LicenseStateData> signState({
    required DateTime lastValidatedAt,
    required DateTime lastServerTime,
    required String machineId,
    required String deviceSecret,
  }) async {
    final unsigned = LicenseStateData(
      lastValidatedAt: lastValidatedAt,
      lastServerTime: lastServerTime,
      lastMachineId: machineId,
    );
    final key = SecretKey(base64UrlDecodeBytes(deviceSecret));
    final mac = await Hmac.sha256()
        .calculateMac(utf8.encode(_signatureInput(unsigned)), secretKey: key);
    return LicenseStateData(
      lastValidatedAt: lastValidatedAt,
      lastServerTime: lastServerTime,
      lastMachineId: machineId,
      hmac: base64UrlEncode(Uint8List.fromList(mac.bytes)),
    );
  }

  String _signatureInput(LicenseStateData state) {
    return '${state.lastValidatedAt!.toIso8601String()}|'
        '${state.lastServerTime!.toIso8601String()}|'
        '${state.lastMachineId ?? ''}';
  }

  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> clearAll() async {
    await Future.wait([
      clearEnvelope(),
      clearState(),
      clearDeviceSecret(),
    ]);
  }
}