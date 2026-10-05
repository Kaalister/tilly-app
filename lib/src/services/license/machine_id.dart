import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../secure_settings_service.dart';

const _machineIdKey = 'tilly_license_machine_id';

class MachineIdService {
  MachineIdService(this._secureStorage);

  final SecureSettingsService _secureStorage;

  // The machine id identifies this app installation forever. It is generated
  // once and must never be deleted nor regenerated, whatever happens to the
  // licence or the account.
  Future<String> getOrCreateMachineId() async {
    final stored = await _secureStorage.read(key: _machineIdKey);
    if (stored != null && _isValidMachineId(stored)) {
      return stored;
    }
    final newId = _generateMachineId();
    await _secureStorage.write(key: _machineIdKey, value: newId);
    return newId;
  }

  bool _isValidMachineId(String id) {
    return RegExp(r'^MCH-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
        .hasMatch(id);
  }

  String _generateMachineId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final uuidStr = _bytesToUuid(bytes);
    return 'MCH-${uuidStr.toLowerCase()}';
  }

  String _bytesToUuid(List<int> bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  Future<String?> generateFingerprintHash() async {
    // The fingerprint is indicative only: it must never block activation.
    try {
      final hostname = Platform.localHostname;
      final os = Platform.operatingSystem;
      final arch = _getArchitecture();
      final cpuCount = Platform.numberOfProcessors;
      final input = '$hostname|$os|$arch|$cpuCount';
      final digest = await Sha256().hash(utf8.encode(input));
      return digest.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      return null;
    }
  }

  String _getArchitecture() {
    if (Platform.isMacOS) {
      try {
        final result = Process.runSync('uname', ['-m'], runInShell: true);
        return result.stdout.toString().trim();
      } catch (_) {
        return 'unknown';
      }
    }
    return Platform.operatingSystemVersion;
  }
}