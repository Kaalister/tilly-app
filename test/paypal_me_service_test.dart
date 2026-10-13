import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tilly/tilly.dart';

void main() {
  test('reports an existing PayPal.Me link as valid', () async {
    final client = MockClient((request) async {
      expect(request.url.toString(), 'https://paypal.me/fragaddict');
      return http.Response('', 200);
    });
    expect(
        await PaypalMeService(client: client)
            .linkExists('https://paypal.me/fragaddict'),
        isTrue);
  });

  test('reports a 404 as an unknown account', () async {
    final client = MockClient((_) async => http.Response('', 404));
    expect(
        await PaypalMeService(client: client)
            .linkExists('https://paypal.me/inconnu'),
        isFalse);
  });

  test('returns null on an unexpected status', () async {
    final client = MockClient((_) async => http.Response('', 500));
    expect(
        await PaypalMeService(client: client)
            .linkExists('https://paypal.me/fragaddict'),
        isNull);
  });

  test('returns null on network errors', () async {
    final client =
        MockClient((_) async => throw http.ClientException('offline'));
    expect(
        await PaypalMeService(client: client)
            .linkExists('https://paypal.me/fragaddict'),
        isNull);
  });

  test('returns null on timeout', () async {
    final client = MockClient((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return http.Response('', 200);
    });
    expect(
        await PaypalMeService(client: client).linkExists(
            'https://paypal.me/fragaddict',
            timeout: const Duration(milliseconds: 10)),
        isNull);
  });
}
