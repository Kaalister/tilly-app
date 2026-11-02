import 'dart:async';

import 'package:http/http.dart' as http;

class PaypalMeService {
  PaypalMeService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  /// Returns true when PayPal confirms the PayPal.Me link exists, false when
  /// PayPal explicitly reports an unknown handle, and null when the check
  /// cannot be performed (offline, timeout, unexpected status).
  Future<bool?> linkExists(String link,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final response = await _client.get(
        Uri.parse(link),
        headers: const {
          'User-Agent':
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko)'
        },
      ).timeout(timeout);
      if (response.statusCode == 200) return true;
      if (response.statusCode == 404) return false;
      return null;
    } catch (_) {
      return null;
    }
  }
}
