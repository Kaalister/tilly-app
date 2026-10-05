import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../config/app_config.dart';
import 'license_models.dart';

const _clockTolerance = Duration(hours: 24);
const _offlineGraceBuffer = Duration(hours: 1);

class LicenseVerifier {
  LicenseVerifier({Map<String, String>? publicKeys})
      : _publicKeys = publicKeys ?? licenseSupportedKids;

  final Map<String, String> _publicKeys;

  Future<LicenseState> verify({
    required LicenseEnvelope envelope,
    required String localMachineId,
    required String appVersion,
    required DateTime now,
    DateTime? lastServerTime,
    DateTime? lastValidatedAt,
  }) async {
    final publicKeyBase64 = _publicKeys[envelope.kid];
    if (publicKeyBase64 == null) {
      return LicenseState.invalidSignature;
    }

    final payloadBytes = _tryDecode(envelope.payload);
    final signatureBytes = _tryDecode(envelope.signature);
    final publicKeyBytes = _tryDecode(publicKeyBase64);
    if (payloadBytes == null ||
        signatureBytes == null ||
        publicKeyBytes == null) {
      return LicenseState.invalidSignature;
    }

    try {
      final signature = Signature(
        signatureBytes,
        publicKey: SimplePublicKey(
          publicKeyBytes,
          type: KeyPairType.ed25519,
        ),
      );
      final valid = await Ed25519().verify(payloadBytes, signature: signature);
      if (!valid) return LicenseState.invalidSignature;
    } catch (_) {
      return LicenseState.invalidSignature;
    }

    LicensePayload payload;
    try {
      payload = LicensePayload.fromJson(
          jsonDecode(utf8.decode(payloadBytes)) as Map<String, dynamic>);
    } catch (_) {
      return LicenseState.invalidSignature;
    }

    if (payload.machineId != localMachineId) {
      return LicenseState.invalidMachine;
    }

    if (lastServerTime != null &&
        now.isBefore(lastServerTime.subtract(_clockTolerance))) {
      return LicenseState.clockTampered;
    }

    // Lifetime licences only cover the purchased version range.
    if (payload.licenseType == LicenseType.lifetime &&
        !versionIsCovered(appVersion, payload.coveredVersion)) {
      return LicenseState.versionNotCovered;
    }

    if (payload.licenseType == LicenseType.lifetime) {
      return LicenseState.licenseValid;
    }

    final offlineUntil = payload.offlineValidUntil;
    if (offlineUntil == null) {
      return LicenseState.licenseExpired;
    }
    if (!now.isAfter(offlineUntil)) {
      return LicenseState.licenseValid;
    }
    if (!now.isAfter(offlineUntil.add(_offlineGraceBuffer))) {
      return LicenseState.offlineGracePeriod;
    }
    return LicenseState.serverValidationRequired;
  }

  List<int>? _tryDecode(String value) {
    try {
      return base64UrlDecodeBytes(value);
    } catch (_) {
      return null;
    }
  }
}
