import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  SessionRecord session() => SessionRecord(
        id: 'session-test',
        name: 'Session test',
        eventDate: DateTime(2026, 7, 16),
      );

  void expectPdf(List<int> bytes) {
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  }

  test('bilan PDF is built on a worker isolate', () async {
    final bytes = await buildBilanPdfBytes(session(), [
      testSale(),
      testSale(id: 'sale-2', payment: 'PayPal', donation: 2),
    ]);
    expectPdf(bytes);
  });

  test('players PDF is built on a worker isolate', () async {
    final bytes = await buildPlayersPdfBytes('Session test', [
      PlayerPdfRow(
        playerName: 'Alice Martin',
        playerType: 'membre',
        saleCount: 1,
        items: const [
          PlayerPdfItemRow(
            name: 'Soda',
            unitPrice: 2.5,
            tariff: 'Adhérent',
            quantity: 1,
            cashTotal: 2.5,
            paypalTotal: 0,
            sumupTotal: 0,
            total: 2.5,
          ),
        ],
        cashTotal: 2.5,
        paypalTotal: 0,
        sumupTotal: 0,
        donationTotal: 0,
        total: 2.5,
      ),
    ]);
    expectPdf(bytes);
  });

  test('cash PDF is built on a worker isolate', () async {
    final bytes = await buildCashPdfBytes(
      start: 50,
      end: 62.5,
      cashSales: 12.5,
      cashStart: const {'50.0': 1},
      cashEnd: const {'2.0': 1},
      sessionLabel: 'Session test',
    );
    expectPdf(bytes);
  });

  test('KPI PDF is built on a worker isolate', () async {
    final bytes = await buildKpiPdfBytes(
      rows: [KpiRow(testArticle(), 2, 0, 0, 2, 5, 8, 10, .2, 0)],
      sessionCa: [(session: session(), ca: 5.0)],
      mealsEnabled: true,
      sessionLabel: 'Session test',
    );
    expectPdf(bytes);
  });
}
