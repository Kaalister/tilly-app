import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/src/services/license/machine_id.dart';
import 'package:tilly/src/services/secure_settings_service.dart';

class _CountingStorage extends SecureSettingsService {
  final values = <String, String>{};
  int reads = 0;
  int writes = 0;

  @override
  Future<String?> read({required String key}) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    writes++;
    values[key] = value;
  }
}

void main() {
  test('the machine id is generated once and served from memory afterwards',
      () async {
    final storage = _CountingStorage();
    final service = MachineIdService(storage);

    final first = await service.getOrCreateMachineId();
    expect(first, startsWith('MCH-'));
    expect(storage.writes, 1);

    final second = await service.getOrCreateMachineId();

    expect(second, first);
    expect(storage.reads, 1,
        reason: 'the secure storage must not be read again');
    expect(storage.writes, 1);
  });
}
