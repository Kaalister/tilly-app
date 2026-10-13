import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/src/services/license/license_models.dart';

void main() {
  group('versionIsCovered', () {
    test('a legacy licence without covered version covers everything', () {
      expect(versionIsCovered('2.1.0', null), isTrue);
      expect(versionIsCovered('9.9.9', ''), isTrue);
    });

    test('the covered version itself and its patches are covered', () {
      expect(versionIsCovered('2.1', '2.1'), isTrue);
      expect(versionIsCovered('2.1.0', '2.1'), isTrue);
      expect(versionIsCovered('2.1.7', '2.1'), isTrue);
      expect(versionIsCovered('v2.1.3', '2.1'), isTrue);
      expect(versionIsCovered('2.1.3', 'v2.1.4'), isTrue);
    });

    test('a newer minor or major version is not covered', () {
      expect(versionIsCovered('2.2', '2.1'), isFalse);
      expect(versionIsCovered('2.2.0', '2.1.9'), isFalse);
      expect(versionIsCovered('3.0', '2.1'), isFalse);
      expect(versionIsCovered('2.1.5', '2.1.4'), isFalse);
    });

    test('a pre-release suffix only keeps the numeric prefix', () {
      expect(versionIsCovered('2.1.0-beta.3', '2.1'), isTrue);
      expect(versionIsCovered('2.2.0-beta.1', '2.1'), isFalse);
      expect(versionIsCovered('2.1.3', '2.1.4-rc1'), isTrue);
    });

    test('missing parts compare as zero', () {
      expect(versionIsCovered('2.1', '2.1.1'), isTrue);
      expect(versionIsCovered('2.1.0', '2.1'), isTrue);
    });
  });

  group('base64url helpers', () {
    test('round-trips UTF-8 text', () {
      final bytes = Uint8List.fromList(utf8.encode('Bonjour éàü'));
      final encoded = base64UrlEncode(bytes);
      expect(base64UrlDecode(encoded), 'Bonjour éàü');
      expect(base64UrlDecodeBytes(encoded), bytes);
    });

    test('accepts unpadded base64url input', () {
      final encoded = base64UrlEncode(Uint8List.fromList(utf8.encode('f')));
      final unpadded = encoded.replaceAll('=', '');
      expect(base64UrlDecode(unpadded), 'f');
    });

    test('uses url safe characters', () {
      final bytes = Uint8List.fromList([251, 239, 190]);
      final encoded = base64UrlEncode(bytes);
      expect(encoded, isNot(contains('+')));
      expect(encoded, isNot(contains('/')));
      expect(base64UrlDecodeBytes(encoded), bytes);
    });

    test('rejects invalid lengths', () {
      expect(() => base64UrlDecode('A'), throwsFormatException);
      expect(() => base64UrlDecodeBytes('A'), throwsFormatException);
    });
  });
}
