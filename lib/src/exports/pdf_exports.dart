import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../controllers/app_controller.dart';
import '../domain/models.dart';
import '../platform/backup_and_links.dart';
import '../services/kpi_service.dart';

Future<void> exportBilanPdf(BuildContext context, AppController controller,
    SessionRecord session) async {
  try {
    final sales = controller.salesForSession(session.id);
    if (sales.isEmpty) {
      snack(context, 'Aucune vente à exporter pour cette session');
      return;
    }

    final bytes = await _buildBilanPdf(session, sales);
    final now = DateTime.now();
    final fileName =
        'tilly_${_pdfFileDate(session.eventDate)}_${_pdfCompactTimestamp(now)}.pdf';
    final savedFile = await _savePdfFile(fileName, bytes);
    final name = savedFile['name'] ?? fileName;
    if (context.mounted) {
      snack(context, 'PDF bilan enregistré dans Downloads : $name');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(
          context, 'Export bilan impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) snack(context, 'Export bilan impossible : $error');
  }
}

Future<Uint8List> _buildBilanPdf(
    SessionRecord session, List<Sale> sales) async {
  final document = pw.Document();
  final paymentTotals = _bilanPaymentTotals(sales);
  final total =
      sales.fold<double>(0, (runningTotal, sale) => runningTotal + sale.total);
  final paymentCounts = _bilanPaymentCounts(sales);
  final stockRows = _bilanStockRows(sales);
  final playerRows = _bilanPlayerRows(sales);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      footer: (context) => _pdfFooter(
          session.eventDate, context.pageNumber, context.pagesCount, ''),
      build: (context) => [
        _pdfBilanHeader(session),
        pw.SizedBox(height: 16),
        _pdfSectionHeader('BILAN DE LA JOURNEE'),
        pw.Row(
          children: [
            _pdfBilanMetric(
              'ESPECES',
              _pdfBilanMoney(paymentTotals['ESP'] ?? 0),
              '${paymentCounts['ESP'] ?? 0} transaction(s)',
            ),
            pw.SizedBox(width: 6),
            _pdfBilanMetric(
              'PAYPAL',
              _pdfBilanMoney(paymentTotals['PayPal'] ?? 0),
              '${paymentCounts['PayPal'] ?? 0} transaction(s)',
            ),
            pw.SizedBox(width: 6),
            _pdfBilanMetric(
              'SUMUP',
              _pdfBilanMoney(paymentTotals['SumUp'] ?? 0),
              '${paymentCounts['SumUp'] ?? 0} transaction(s)',
            ),
            pw.SizedBox(width: 6),
            _pdfBilanMetric(
              'TOTAL - ${sales.length} vente(s)',
              _pdfBilanMoney(total),
              '',
            ),
          ],
        ),
        pw.SizedBox(height: 26),
        _pdfSectionHeader('STOCK VENDU'),
        if (stockRows.isEmpty)
          pw.Text('Aucun article vendu',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))
        else
          pw.Table(
            border: pw.TableBorder(
              horizontalInside:
                  const pw.BorderSide(color: PdfColors.grey600, width: 0.35),
              bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(2.7),
              1: pw.FlexColumnWidth(0.7),
              2: pw.FlexColumnWidth(1.3),
              3: pw.FlexColumnWidth(1.3),
              4: pw.FlexColumnWidth(1.3),
              5: pw.FlexColumnWidth(1.3),
            },
            children: [
              _pdfBilanTableRow(
                  ['ARTICLE', 'QTE', 'ESP', 'PAYPAL', 'SUMUP', 'TOTAL'],
                  header: true, alignRightFrom: 1),
              for (var i = 0; i < stockRows.length; i++)
                _pdfBilanTableRow(
                  [
                    stockRows[i].name,
                    '${stockRows[i].quantity}',
                    _pdfBilanMoneyOrDash(stockRows[i].cashTotal),
                    _pdfBilanMoneyOrDash(stockRows[i].paypalTotal),
                    _pdfBilanMoneyOrDash(stockRows[i].sumupTotal),
                    _pdfBilanMoneyOrDash(stockRows[i].total),
                  ],
                  shaded: i.isEven,
                  alignRightFrom: 1,
                ),
            ],
          ),
        pw.SizedBox(height: 26),
        _pdfSectionHeader('PAR PARTICIPANT'),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside:
                const pw.BorderSide(color: PdfColors.grey600, width: 0.35),
            bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.5),
            1: pw.FlexColumnWidth(0.7),
            2: pw.FlexColumnWidth(0.4),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(0.8),
            7: pw.FlexColumnWidth(1.1),
          },
          children: [
            _pdfBilanTableRow([
              'PARTICIPANT',
              'TYPE',
              'N',
              'ESP',
              'PAYPAL',
              'SUMUP',
              'DONS',
              'TOTAL'
            ], header: true, alignRightFrom: 2),
            for (var i = 0; i < playerRows.length; i++)
              _pdfBilanTableRow(
                [
                  playerRows[i].playerName,
                  _pdfPlayerType(playerRows[i].playerType),
                  '${playerRows[i].saleCount}',
                  _pdfBilanNumberOrDash(playerRows[i].cashTotal),
                  _pdfBilanNumberOrDash(playerRows[i].paypalTotal),
                  _pdfBilanNumberOrDash(playerRows[i].sumupTotal),
                  _pdfBilanNumberOrDash(playerRows[i].donationTotal),
                  _pdfBilanNumberOrDash(playerRows[i].total),
                ],
                shaded: i.isEven,
                alignRightFrom: 2,
              ),
          ],
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _pdfBilanHeader(SessionRecord session) {
  return pw.Column(
    children: [
      pw.Center(
        child: pw.Text(
          'TILLY',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Center(
        child: pw.Text(
          '${dateLabel(session.eventDate)} - ${session.name}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      pw.Divider(color: PdfColors.grey500),
    ],
  );
}

pw.Widget _pdfBilanMetric(String label, String value, String caption) {
  return pw.Expanded(
    child: pw.Container(
      height: 62,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          pw.Text(value,
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.Text(caption,
              style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey700)),
        ],
      ),
    ),
  );
}

pw.TableRow _pdfBilanTableRow(List<String> cells,
    {bool header = false, bool shaded = false, int alignRightFrom = 0}) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(
      color: header
          ? PdfColors.white
          : shaded
              ? PdfColors.grey100
              : PdfColors.white,
    ),
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            cells[i],
            maxLines: i == 0 ? 2 : 1,
            overflow: pw.TextOverflow.clip,
            textAlign:
                i >= alignRightFrom ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: header ? 7.5 : 7.5,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
    ],
  );
}

Map<String, double> _bilanPaymentTotals(List<Sale> sales) {
  final totals = {'ESP': 0.0, 'PayPal': 0.0, 'SumUp': 0.0};
  for (final sale in sales) {
    totals[sale.payment] = (totals[sale.payment] ?? 0) + sale.total;
  }
  return totals;
}

Map<String, int> _bilanPaymentCounts(List<Sale> sales) {
  final counts = {'ESP': 0, 'PayPal': 0, 'SumUp': 0};
  for (final sale in sales) {
    counts[sale.payment] = (counts[sale.payment] ?? 0) + 1;
  }
  return counts;
}

List<
    ({
      String name,
      int quantity,
      double cashTotal,
      double paypalTotal,
      double sumupTotal,
      double total
    })> _bilanStockRows(List<Sale> sales) {
  final grouped = <String,
      ({
    String name,
    int quantity,
    double cashTotal,
    double paypalTotal,
    double sumupTotal,
    double total
  })>{};
  var donationCount = 0;
  var donationCash = 0.0;
  var donationPaypal = 0.0;
  var donationSumup = 0.0;

  for (final sale in sales) {
    for (final item in sale.items) {
      final current = grouped[item.name] ??
          (
            name: item.name,
            quantity: 0,
            cashTotal: 0.0,
            paypalTotal: 0.0,
            sumupTotal: 0.0,
            total: 0.0,
          );
      final lineTotal = item.price * item.quantity;
      grouped[item.name] = (
        name: current.name,
        quantity: current.quantity + item.quantity,
        cashTotal: current.cashTotal + (sale.payment == 'ESP' ? lineTotal : 0),
        paypalTotal:
            current.paypalTotal + (sale.payment == 'PayPal' ? lineTotal : 0),
        sumupTotal:
            current.sumupTotal + (sale.payment == 'SumUp' ? lineTotal : 0),
        total: current.total + lineTotal,
      );
    }
    if (sale.donation > 0) {
      donationCount += 1;
      donationCash += sale.payment == 'ESP' ? sale.donation : 0;
      donationPaypal += sale.payment == 'PayPal' ? sale.donation : 0;
      donationSumup += sale.payment == 'SumUp' ? sale.donation : 0;
    }
  }

  final rows = grouped.values.toList();
  final donationTotal = donationCash + donationPaypal + donationSumup;
  if (donationTotal > 0) {
    rows.add((
      name: 'Dons',
      quantity: donationCount,
      cashTotal: donationCash,
      paypalTotal: donationPaypal,
      sumupTotal: donationSumup,
      total: donationTotal,
    ));
  }
  rows.sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

List<
    ({
      String playerName,
      String playerType,
      int saleCount,
      double cashTotal,
      double paypalTotal,
      double sumupTotal,
      double donationTotal,
      double total
    })> _bilanPlayerRows(List<Sale> sales) {
  final grouped = <String,
      ({
    String playerName,
    String playerType,
    int saleCount,
    double cashTotal,
    double paypalTotal,
    double sumupTotal,
    double donationTotal,
    double total
  })>{};
  for (final sale in sales) {
    final key = sale.playerId.isEmpty ? sale.playerName : sale.playerId;
    final current = grouped[key] ??
        (
          playerName: sale.playerName,
          playerType: sale.playerType,
          saleCount: 0,
          cashTotal: 0.0,
          paypalTotal: 0.0,
          sumupTotal: 0.0,
          donationTotal: 0.0,
          total: 0.0,
        );
    grouped[key] = (
      playerName: current.playerName,
      playerType: current.playerType,
      saleCount: current.saleCount + 1,
      cashTotal: current.cashTotal + (sale.payment == 'ESP' ? sale.total : 0),
      paypalTotal:
          current.paypalTotal + (sale.payment == 'PayPal' ? sale.total : 0),
      sumupTotal:
          current.sumupTotal + (sale.payment == 'SumUp' ? sale.total : 0),
      donationTotal: current.donationTotal + sale.donation,
      total: current.total + sale.total,
    );
  }
  final rows = grouped.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

String _pdfBilanMoney(num value) => '${value.toStringAsFixed(2)} EUR';

String _pdfBilanMoneyOrDash(num value) =>
    value.abs() < 0.005 ? '-' : _pdfBilanMoney(value);

String _pdfBilanNumberOrDash(num value) =>
    value.abs() < 0.005 ? '-' : value.toStringAsFixed(2);

class PlayerPdfRow {
  const PlayerPdfRow({
    required this.playerName,
    required this.playerType,
    required this.saleCount,
    required this.items,
    required this.cashTotal,
    required this.paypalTotal,
    required this.sumupTotal,
    required this.donationTotal,
    required this.total,
  });

  final String playerName;
  final String playerType;
  final int saleCount;
  final List<PlayerPdfItemRow> items;
  final double cashTotal;
  final double paypalTotal;
  final double sumupTotal;
  final double donationTotal;
  final double total;
}

class PlayerPdfItemRow {
  const PlayerPdfItemRow({
    required this.name,
    required this.unitPrice,
    required this.tariff,
    required this.quantity,
    required this.cashTotal,
    required this.paypalTotal,
    required this.sumupTotal,
    required this.total,
  });

  final String name;
  final double unitPrice;
  final String tariff;
  final int quantity;
  final double cashTotal;
  final double paypalTotal;
  final double sumupTotal;
  final double total;
}

Future<void> exportPlayersPdf(
    BuildContext context, AppController controller) async {
  try {
    final rows = _playerPdfRows(controller);
    if (rows.isEmpty) {
      snack(context, 'Aucune vente à exporter');
      return;
    }

    final bytes = await _buildPlayersPdf(controller, rows);
    final date = DateTime.now();
    final fileName =
        'tilly_participants_${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}.pdf';
    final savedFile = await _savePdfFile(fileName, bytes);
    final name = savedFile['name'] ?? fileName;
    if (context.mounted) {
      snack(context, 'PDF enregistré dans Downloads : $name');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(context, 'Export PDF impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) snack(context, 'Export PDF impossible : $error');
  }
}

List<PlayerPdfRow> _playerPdfRows(AppController controller) {
  final grouped = <String, List<Sale>>{};
  for (final sale in controller.activeSales) {
    grouped.putIfAbsent(sale.playerId, () => []).add(sale);
  }

  final rows = grouped.values.map((sales) {
    final items = <String,
        ({
      String name,
      double unitPrice,
      String tariff,
      int quantity,
      double cash,
      double paypal,
      double sumup,
      double total
    })>{};
    var cashTotal = 0.0;
    var paypalTotal = 0.0;
    var sumupTotal = 0.0;
    var donationTotal = 0.0;
    var total = 0.0;

    for (final sale in sales) {
      total += sale.total;
      donationTotal += sale.donation;
      switch (sale.payment) {
        case 'ESP':
          cashTotal += sale.total;
        case 'PayPal':
          paypalTotal += sale.total;
        case 'SumUp':
          sumupTotal += sale.total;
      }
      for (final item in sale.items) {
        final tariff = _pdfSaleTariff(sale);
        final itemKey = '${item.name}|${item.price.toStringAsFixed(2)}|$tariff';
        final current = items[itemKey] ??
            (
              name: item.name,
              unitPrice: item.price,
              tariff: tariff,
              quantity: 0,
              cash: 0.0,
              paypal: 0.0,
              sumup: 0.0,
              total: 0.0
            );
        final lineTotal = item.price * item.quantity;
        items[itemKey] = (
          name: current.name,
          unitPrice: current.unitPrice,
          tariff: current.tariff,
          quantity: current.quantity + item.quantity,
          cash: current.cash + (sale.payment == 'ESP' ? lineTotal : 0),
          paypal: current.paypal + (sale.payment == 'PayPal' ? lineTotal : 0),
          sumup: current.sumup + (sale.payment == 'SumUp' ? lineTotal : 0),
          total: current.total + lineTotal,
        );
      }
    }

    final itemRows = items.entries
        .map((entry) => PlayerPdfItemRow(
              name: entry.value.name,
              unitPrice: entry.value.unitPrice,
              tariff: entry.value.tariff,
              quantity: entry.value.quantity,
              cashTotal: entry.value.cash,
              paypalTotal: entry.value.paypal,
              sumupTotal: entry.value.sumup,
              total: entry.value.total,
            ))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    return PlayerPdfRow(
      playerName: sales.first.playerName,
      playerType: sales.first.playerType,
      saleCount: sales.length,
      items: itemRows,
      cashTotal: cashTotal,
      paypalTotal: paypalTotal,
      sumupTotal: sumupTotal,
      donationTotal: donationTotal,
      total: total,
    );
  }).toList();

  rows.sort((a, b) => b.total.compareTo(a.total));
  return rows;
}

Future<Uint8List> _buildPlayersPdf(
    AppController controller, List<PlayerPdfRow> rows) async {
  final document = pw.Document();
  final date = DateTime.now();
  final total = rows.fold<double>(0, (total, row) => total + row.total);
  final donations =
      rows.fold<double>(0, (total, row) => total + row.donationTotal);
  final saleCount = rows.fold<int>(0, (total, row) => total + row.saleCount);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      build: (context) => [
        pw.Center(
          child: pw.Text(
            'TILLY',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            dateLabel(date),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        pw.Divider(color: PdfColors.grey500),
        pw.SizedBox(height: 8),
        pw.Text(
          'HISTORIQUE PAR PARTICIPANT',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.Container(height: 1.2, color: PdfColors.grey900),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            _pdfMetric('PARTICIPANTS', '${rows.length}'),
            pw.SizedBox(width: 6),
            _pdfMetric('VENTES', '$saleCount'),
            pw.SizedBox(width: 6),
            _pdfMetric('TOTAL', _pdfMoney(total)),
            pw.SizedBox(width: 6),
            _pdfMetric('DONS', _pdfMoney(donations)),
          ],
        ),
        pw.SizedBox(height: 28),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside:
                const pw.BorderSide(color: PdfColors.grey600, width: 0.35),
            bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.6),
            1: pw.FlexColumnWidth(0.8),
            2: pw.FlexColumnWidth(0.5),
            3: pw.FlexColumnWidth(3.0),
            4: pw.FlexColumnWidth(1.0),
            5: pw.FlexColumnWidth(0.9),
            6: pw.FlexColumnWidth(0.9),
            7: pw.FlexColumnWidth(0.8),
            8: pw.FlexColumnWidth(1.1),
          },
          children: [
            _pdfTableRow(
              [
                'PARTICIPANT',
                'TYPE',
                'N',
                'DETAIL ACHATS',
                'ESP',
                'PP',
                'SUM',
                'DONS',
                'TOTAL'
              ],
              header: true,
            ),
            for (var i = 0; i < rows.length; i++) ..._pdfPlayerRows(rows[i]),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            controller.session.isEmpty ? '' : 'Session : ${controller.session}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
      ],
    ),
  );

  return document.save();
}

List<pw.TableRow> _pdfPlayerRows(PlayerPdfRow row) {
  return [
    _pdfTableRow(
      [
        row.playerName,
        _pdfPlayerType(row.playerType),
        '${row.saleCount}',
        '',
        _pdfMoney(row.cashTotal),
        _pdfMoney(row.paypalTotal),
        _pdfMoney(row.sumupTotal),
        _pdfMoney(row.donationTotal),
        _pdfMoney(row.total),
      ],
      player: true,
    ),
    for (final item in row.items)
      _pdfTableRow(
        [
          '',
          '',
          '${item.quantity}',
          '${item.name} (${_pdfPrice(item.unitPrice)}) [${item.tariff}]',
          _pdfMoney(item.cashTotal),
          _pdfMoney(item.paypalTotal),
          _pdfMoney(item.sumupTotal),
          '',
          _pdfMoney(item.total),
        ],
        item: true,
      ),
  ];
}

pw.Widget _pdfMetric(String label, String value, {PdfColor? valueColor}) {
  return pw.Expanded(
    child: pw.Container(
      height: 52,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style:
                  const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 12,
                  color: valueColor ?? PdfColors.black,
                  fontWeight: pw.FontWeight.bold)),
        ],
      ),
    ),
  );
}

pw.TableRow _pdfTableRow(List<String> cells,
    {bool header = false,
    bool player = false,
    bool item = false,
    Map<int, PdfColor> textColors = const {},
    Set<int> boldColumns = const {}}) {
  final background = header
      ? PdfColors.white
      : player
          ? PdfColors.grey300
          : PdfColors.white;
  final textColor = PdfColors.black;
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: background),
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(
            i == 3 && item ? 12 : 5,
            player ? 7 : 6,
            5,
            player ? 7 : 6,
          ),
          child: pw.Text(
            cells[i],
            maxLines: i == 3 ? 2 : 1,
            overflow: pw.TextOverflow.clip,
            textAlign: i >= 4 ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: header ? 7 : 7.5,
              color: textColors[i] ?? textColor,
              fontWeight: header || player || boldColumns.contains(i)
                  ? pw.FontWeight.bold
                  : pw.FontWeight.normal,
            ),
          ),
        ),
    ],
  );
}

String _pdfMoney(num value) =>
    value.abs() < 0.005 ? '-' : value.toStringAsFixed(2);

String _pdfPrice(num value) => value.toStringAsFixed(2);

String _pdfPlayerType(String value) {
  return value == 'membre' ? 'ADH' : 'PUB';
}

String _pdfSaleTariff(Sale sale) {
  return sale.tariff == 'adherent' || sale.playerType == 'membre'
      ? 'ADH'
      : 'PUB';
}

Future<void> exportCashPdf(
    BuildContext context, AppController controller) async {
  try {
    final bytes = await _buildCashPdf(controller);
    final date = DateTime.now();
    final fileName =
        'tilly_analyse_caisse_${_pdfFileDate(date)}_${_pdfCompactTimestamp(date)}.pdf';
    final savedFile = await _savePdfFile(fileName, bytes);
    final name = savedFile['name'] ?? fileName;
    if (context.mounted) {
      snack(context, 'PDF caisse enregistré dans Downloads : $name');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(
          context, 'Export caisse impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) {
      snack(context, 'Export caisse impossible : $error');
    }
  }
}

Future<Uint8List> _buildCashPdf(AppController controller) async {
  final document = pw.Document();
  final date = DateTime.now();
  final start = controller.cashTotal('start');
  final end = controller.cashTotal('end');
  final cashSales = controller.paymentTotals()['ESP'] ?? 0;
  final theoretical = start + cashSales;
  final gap = end - theoretical;
  final gapOk = gap.abs() < .01;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      footer: (context) => _pdfCashFooter(
        date,
        context.pageNumber,
        context.pagesCount,
      ),
      build: (context) => [
        _pdfCashHeader(date, controller),
        pw.SizedBox(height: 16),
        _pdfSectionHeader('ANALYSE CAISSE ESPECES'),
        pw.Row(
          children: [
            _pdfMetric('FOND DEBUT', _pdfCashMoney(start)),
            pw.SizedBox(width: 6),
            _pdfMetric('+ VENTES ESP', _pdfCashMoney(cashSales)),
            pw.SizedBox(width: 6),
            _pdfMetric('= THEORIQUE', _pdfCashMoney(theoretical)),
            pw.SizedBox(width: 6),
            _pdfMetric('FOND FIN REEL', _pdfCashMoney(end)),
          ],
        ),
        pw.SizedBox(height: 12),
        _pdfCashGapBox(gap, gapOk),
        pw.SizedBox(height: 24),
        _pdfCashCountSection('FOND DEBUT', start, controller.cashStart),
        pw.SizedBox(height: 22),
        _pdfCashCountSection('FOND FIN', end, controller.cashEnd),
      ],
    ),
  );

  return document.save();
}

pw.Widget _pdfCashHeader(DateTime date, AppController controller) {
  final session = controller.session.isEmpty ? 'Événement' : controller.session;
  return pw.Column(
    children: [
      pw.Center(
        child: pw.Text(
          'TILLY',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Center(
        child: pw.Text(
          '${dateLabel(date)} - $session',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      pw.Divider(color: PdfColors.grey500),
    ],
  );
}

pw.Widget _pdfCashGapBox(double gap, bool gapOk) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey600, width: 0.9),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'ECART',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          '${_pdfCashMoney(gap, decimalComma: true)} - ${gapOk ? 'OK' : 'A CONTROLER'}',
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: gapOk ? PdfColors.black : PdfColors.red700,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _pdfCashCountSection(
    String title, double total, Map<String, int> cashMap) {
  final rows = _cashPdfRows(cashMap);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _pdfSectionHeader('$title - ${_pdfCashMoney(total)}'),
      if (rows.isEmpty)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Text(
            'Aucun comptage saisi',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        )
      else
        pw.Table(
          border: pw.TableBorder(
            horizontalInside:
                const pw.BorderSide(color: PdfColors.grey600, width: 0.35),
            bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.7),
            1: pw.FlexColumnWidth(1.1),
            2: pw.FlexColumnWidth(0.75),
            3: pw.FlexColumnWidth(2.1),
          },
          children: [
            _pdfCashTableRow(
              ['COUPURE', 'TYPE', 'NB', 'SOUS-TOTAL'],
              header: true,
            ),
            for (var i = 0; i < rows.length; i++)
              _pdfCashTableRow(
                [
                  rows[i].label,
                  rows[i].type,
                  '${rows[i].quantity}',
                  _pdfCashMoney(rows[i].subtotal),
                ],
                shaded: i.isEven,
              ),
          ],
        ),
    ],
  );
}

List<({String label, String type, int quantity, double subtotal})> _cashPdfRows(
    Map<String, int> cashMap) {
  return [
    for (final value in denominations)
      if ((cashMap[value.toString()] ?? 0) > 0)
        (
          label: _cashDenominationLabel(value),
          type: value >= 5 ? 'Billet' : 'Piece',
          quantity: cashMap[value.toString()]!,
          subtotal: value * cashMap[value.toString()]!,
        ),
  ];
}

pw.TableRow _pdfCashTableRow(List<String> cells,
    {bool header = false, bool shaded = false}) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(
      color: header
          ? PdfColors.white
          : shaded
              ? PdfColors.grey100
              : PdfColors.white,
    ),
    children: [
      for (var i = 0; i < cells.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: pw.Text(
            cells[i],
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            textAlign: i >= 2 ? pw.TextAlign.right : pw.TextAlign.left,
            style: pw.TextStyle(
              fontSize: header ? 7.5 : 7.5,
              fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ),
    ],
  );
}

pw.Widget _pdfCashFooter(DateTime date, int pageNumber, int pageCount) {
  return pw.Align(
    alignment: pw.Alignment.center,
    child: pw.Text(
      'Tilly - ${dateLabel(date)} - Page $pageNumber/$pageCount',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
    ),
  );
}

String _cashDenominationLabel(double value) {
  if (value >= 1) return '${value.round()} EUR';
  return '${(value * 100).round()} cts';
}

String _pdfCashMoney(num value, {bool decimalComma = false}) {
  final amount = value.toStringAsFixed(2);
  return '${decimalComma ? amount.replaceAll('.', ',') : amount} EUR';
}

String _pdfFileDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day-$month-${date.year}';
}

String _pdfCompactTimestamp(DateTime date) {
  final year = (date.year % 100).toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '$year$month${day}_$hour$minute$second';
}

Future<void> exportKpiPdf(
    BuildContext context, AppController controller) async {
  try {
    final rows = kpiRows(controller)..sort(compareKpiRows);
    if (rows.isEmpty) {
      snack(context, 'Aucune statistique à exporter');
      return;
    }

    final bytes = await _buildKpiPdf(controller, rows);
    final date = DateTime.now();
    final fileName =
        'tilly_kpi_${date.day.toString().padLeft(2, '0')}-${date.month.toString().padLeft(2, '0')}-${date.year}_${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}${date.second.toString().padLeft(2, '0')}.pdf';
    final savedFile = await _savePdfFile(fileName, bytes);
    final name = savedFile['name'] ?? fileName;
    if (context.mounted) {
      snack(context, 'PDF KPI enregistré dans Downloads : $name');
    }
  } on PlatformException catch (error) {
    if (context.mounted) {
      snack(context, 'Export KPI impossible : ${error.message ?? error.code}');
    }
  } catch (error) {
    if (context.mounted) {
      snack(context, 'Export KPI impossible : $error');
    }
  }
}

Future<Uint8List> _buildKpiPdf(
    AppController controller, List<KpiRow> rows) async {
  final document = pw.Document();
  final date = DateTime.now();
  final totalCA = rows.fold<double>(0, (total, row) => total + row.ca);
  final ruptures = rows.where((row) => row.article.stock == 0).length;
  final alertes = rows
      .where((row) =>
          row.article.stock > 0 && row.article.stock <= row.article.threshold)
      .length;
  final reappro = rows.where((row) => row.suggestion > 0).length;
  final topCa = [...rows]..sort((a, b) => b.ca.compareTo(a.ca));
  final topSold = [...rows]..sort((a, b) => b.outgoing.compareTo(a.outgoing));
  final categoryCa = _kpiCategoryCa(rows);
  final sessionCa = _kpiSessionCa(controller);
  final mealsEnabled = controller.mealsEnabled;

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      footer: (context) => _pdfFooter(
          date, context.pageNumber, context.pagesCount, controller.session),
      build: (context) => [
        _pdfKpiHeader(date, controller),
        pw.SizedBox(height: 16),
        pw.Row(
          children: [
            _pdfMetric('RUPTURES', '$ruptures',
                valueColor:
                    ruptures == 0 ? PdfColors.green700 : PdfColors.red700),
            pw.SizedBox(width: 6),
            _pdfMetric('EN ALERTE', '$alertes',
                valueColor:
                    alertes == 0 ? PdfColors.green700 : PdfColors.orange700),
            pw.SizedBox(width: 6),
            _pdfMetric('CA TOTAL', _pdfMoney(totalCA),
                valueColor: PdfColors.green700),
            pw.SizedBox(width: 6),
            _pdfMetric('A REAPPRO', '$reappro'),
          ],
        ),
        pw.SizedBox(height: 26),
        _pdfSectionHeader('DETAIL PAR ARTICLE'),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside:
                const pw.BorderSide(color: PdfColors.grey600, width: 0.35),
            bottom: const pw.BorderSide(color: PdfColors.grey600, width: 0.5),
          ),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.5),
            1: pw.FlexColumnWidth(0.7),
            2: pw.FlexColumnWidth(0.7),
            3: pw.FlexColumnWidth(0.7),
            4: pw.FlexColumnWidth(1.0),
            5: pw.FlexColumnWidth(0.9),
            6: pw.FlexColumnWidth(0.8),
            7: pw.FlexColumnWidth(0.9),
          },
          children: [
            _pdfTableRow(
              [
                'ARTICLE',
                'VENDU',
                mealsEnabled ? 'REP./ASSO' : 'ASSO',
                'SORTI',
                'CA',
                'STOCK',
                'SUGG.',
                'STATUT'
              ],
              header: true,
            ),
            for (final row in rows)
              _pdfTableRow(
                [
                  row.article.name,
                  row.sold == 0 ? '-' : '${row.sold}',
                  mealsEnabled
                      ? row.mealUsed == 0 && row.associationUsed == 0
                          ? '-'
                          : '${row.mealUsed}/${row.associationUsed}'
                      : row.associationUsed == 0
                          ? '-'
                          : '${row.associationUsed}',
                  row.outgoing == 0 ? '-' : '${row.outgoing}',
                  _pdfMoney(row.ca),
                  '${row.stockRest}/${row.stockInitial}',
                  row.suggestion == 0 ? '-' : '>= ${row.suggestion}',
                  _kpiStatus(row),
                ],
                textColors: {7: _kpiStatusColor(row)},
                boldColumns: const {7},
              ),
          ],
        ),
      ],
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      footer: (context) => _pdfFooter(
          date, context.pageNumber, context.pagesCount, controller.session),
      build: (context) => [
        _pdfSectionHeader('1. CA PAR ARTICLE (TOP 10)'),
        _pdfBarChart(
          topCa.take(10).map((row) {
            return (
              label: row.article.name,
              value: row.ca,
              display: _pdfMoney(row.ca)
            );
          }).toList(),
          PdfColors.blue700,
        ),
        pw.SizedBox(height: 28),
        _pdfSectionHeader(mealsEnabled
            ? '2. SORTIES STOCK (VENTES ET REPAS, TOP 10)'
            : '2. SORTIES STOCK (VENTES, TOP 10)'),
        _pdfBarChart(
          topSold.take(10).map((row) {
            return (
              label: row.article.name,
              value: row.outgoing.toDouble(),
              display: '${row.outgoing} unités'
            );
          }).toList(),
          PdfColors.green700,
        ),
        pw.SizedBox(height: 28),
        _pdfSectionHeader('3. STOCK RESTANT VS VENDU'),
        _pdfStockChart(rows.take(12).toList()),
      ],
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 34),
      footer: (context) => _pdfFooter(
          date, context.pageNumber, context.pagesCount, controller.session),
      build: (context) => [
        _pdfSectionHeader('4. REPARTITION CA PAR CATEGORIE'),
        _pdfPieChart(categoryCa, totalCA),
        pw.SizedBox(height: 32),
        _pdfSectionHeader('5. EVOLUTION CA PAR EVENEMENT'),
        _pdfSessionLineChart(sessionCa),
      ],
    ),
  );

  return document.save();
}

pw.Widget _pdfKpiHeader(DateTime date, AppController controller) {
  final session = controller.session.isEmpty ? 'Événement' : controller.session;
  return pw.Column(
    children: [
      pw.Center(
        child: pw.Text(
          'TILLY - KPI ACHATS & STOCK',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Center(
        child: pw.Text(
          '${dateLabel(date)} - $session',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ),
      pw.Divider(color: PdfColors.grey500),
    ],
  );
}

pw.Widget _pdfSectionHeader(String title) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        title,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.Container(height: 1.2, color: PdfColors.grey900),
      pw.SizedBox(height: 14),
    ],
  );
}

pw.Widget _pdfFooter(
    DateTime date, int pageNumber, int pageCount, String session) {
  final sessionLabel = session.isEmpty ? '' : ' - $session';
  return pw.Align(
    alignment: pw.Alignment.center,
    child: pw.Text(
      'Tilly - ${dateLabel(date)}$sessionLabel - Page $pageNumber/$pageCount',
      style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
    ),
  );
}

pw.Widget _pdfBarChart(
  List<({String label, double value, String display})> entries,
  PdfColor color,
) {
  if (entries.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text('Aucune donnée',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    );
  }

  final maxValue = max(1.0, entries.fold<double>(0, (m, e) => max(m, e.value)));
  return pw.Column(
    children: [
      for (final entry in entries)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(
                width: 150,
                child: pw.Text(entry.label,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey800)),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: max(2, 250 * entry.value / maxValue).toDouble(),
                height: 9,
                color: color,
              ),
              pw.SizedBox(width: 8),
              pw.Text(entry.display,
                  style: pw.TextStyle(
                      fontSize: 7, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _pdfPieChart(Map<String, double> categoryCa, double totalCA) {
  final entries = categoryCa.entries.where((entry) => entry.value > 0).toList();
  if (entries.isEmpty || totalCA <= 0) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text('Aucune donnée',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.SizedBox(
        width: 230,
        height: 210,
        child: pw.Chart(
          grid: pw.PieGrid(startAngle: -pi / 2),
          datasets: [
            for (var i = 0; i < entries.length; i++)
              pw.PieDataSet(
                value: entries[i].value,
                color: _kpiChartColor(i),
                borderColor: PdfColors.white,
              ),
          ],
        ),
      ),
      pw.SizedBox(width: 22),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < entries.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Container(
                      width: 10,
                      height: 10,
                      color: _kpiChartColor(i),
                    ),
                    pw.SizedBox(width: 7),
                    pw.Expanded(
                      child: pw.Text(
                        entries[i].key,
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: const pw.TextStyle(fontSize: 7.5),
                      ),
                    ),
                    pw.SizedBox(width: 8),
                    pw.Text(
                      '${_pdfMoney(entries[i].value)} - ${(entries[i].value / totalCA * 100).round()}%',
                      style: pw.TextStyle(
                          fontSize: 7.5, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _pdfSessionLineChart(
    List<({SessionRecord session, double ca})> entries) {
  if (entries.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text('Aucune donnée',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    );
  }

  final maxValue = max(1.0, entries.fold<double>(0, (m, e) => max(m, e.ca)));
  final yMax = _niceChartMax(maxValue);
  final xAxisValues = entries.length == 1
      ? const [0, 1]
      : List<int>.generate(entries.length, (i) => i);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.SizedBox(
        height: 210,
        child: pw.Chart(
          grid: pw.CartesianGrid(
            xAxis: pw.FixedAxis<int>(
              xAxisValues,
              format: (value) {
                final index = value.round();
                if (index < 0 || index >= entries.length) return '';
                return dateLabel(entries[index].session.eventDate)
                    .substring(0, 5);
              },
              textStyle:
                  const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              ticks: true,
            ),
            yAxis: pw.FixedAxis<double>(
              [0, yMax / 2, yMax],
              format: (value) => value == 0 ? '0' : value.round().toString(),
              textStyle:
                  const pw.TextStyle(fontSize: 6, color: PdfColors.grey700),
              divisions: true,
              divisionsColor: PdfColors.grey300,
            ),
          ),
          datasets: [
            pw.LineDataSet<pw.PointChartValue>(
              data: [
                for (var i = 0; i < entries.length; i++)
                  pw.PointChartValue(i.toDouble(), entries[i].ca),
              ],
              color: PdfColors.cyan700,
              lineColor: PdfColors.cyan700,
              lineWidth: 2.2,
              pointSize: 3.5,
              drawSurface: true,
              surfaceColor: PdfColors.cyan100,
              surfaceOpacity: 0.35,
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Wrap(
        spacing: 12,
        runSpacing: 6,
        children: [
          for (final entry in entries)
            pw.Text(
              '${dateLabel(entry.session.eventDate)} ${entry.session.name}: ${_pdfMoney(entry.ca)}',
              style:
                  const pw.TextStyle(fontSize: 6.5, color: PdfColors.grey700),
            ),
        ],
      ),
    ],
  );
}

pw.Widget _pdfStockChart(List<KpiRow> rows) {
  if (rows.isEmpty) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      child: pw.Text('Aucune donnée',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
    );
  }

  final maxStock = max(
      1, rows.fold<int>(0, (m, row) => max(m, row.outgoing + row.stockRest)));
  return pw.Column(
    children: [
      for (final row in rows)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 10),
          child: pw.Row(
            children: [
              pw.SizedBox(
                width: 150,
                child: pw.Text(row.article.name,
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                    style: const pw.TextStyle(
                        fontSize: 7, color: PdfColors.grey800)),
              ),
              pw.SizedBox(width: 10),
              pw.Container(
                width: max(2, 250 * row.outgoing / maxStock).toDouble(),
                height: 9,
                color: PdfColors.blue700,
              ),
              pw.Container(
                width: max(2, 250 * row.stockRest / maxStock).toDouble(),
                height: 9,
                color: PdfColors.grey400,
              ),
              pw.SizedBox(width: 8),
              pw.Text('S:${row.outgoing} R:${row.stockRest}',
                  style: const pw.TextStyle(
                      fontSize: 6.5, color: PdfColors.grey700)),
            ],
          ),
        ),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          pw.Container(width: 12, height: 7, color: PdfColors.blue700),
          pw.SizedBox(width: 5),
          pw.Text('Sorti', style: const pw.TextStyle(fontSize: 6.5)),
          pw.SizedBox(width: 22),
          pw.Container(width: 12, height: 7, color: PdfColors.grey400),
          pw.SizedBox(width: 5),
          pw.Text('Restant', style: const pw.TextStyle(fontSize: 6.5)),
        ],
      ),
    ],
  );
}

Map<String, double> _kpiCategoryCa(List<KpiRow> rows) {
  final result = <String, double>{};
  for (final row in rows) {
    result[row.article.category] = (result[row.article.category] ?? 0) + row.ca;
  }
  final entries = result.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return Map.fromEntries(entries);
}

List<({SessionRecord session, double ca})> _kpiSessionCa(
    AppController controller) {
  final sessions = [...controller.sessions]..sort((a, b) {
      final dateCompare = a.eventDate.compareTo(b.eventDate);
      if (dateCompare != 0) return dateCompare;
      return a.createdAt.compareTo(b.createdAt);
    });
  return [
    for (final session in sessions)
      (
        session: session,
        ca: controller
            .salesForSession(session.id)
            .fold<double>(0, (total, sale) => total + sale.totalArticles)
      ),
  ];
}

String _kpiStatus(KpiRow row) {
  if (row.article.stock == 0) return 'RUPTURE';
  if (row.article.stock <= row.article.threshold) return 'ALERTE';
  return 'OK';
}

PdfColor _kpiStatusColor(KpiRow row) {
  if (row.article.stock == 0) return PdfColors.red700;
  if (row.article.stock <= row.article.threshold) return PdfColors.orange700;
  return PdfColors.green700;
}

PdfColor _kpiChartColor(int index) {
  const colors = [
    PdfColors.blue700,
    PdfColors.orange700,
    PdfColors.green700,
    PdfColors.purple700,
    PdfColors.cyan700,
    PdfColors.red700,
    PdfColors.indigo700,
    PdfColors.lime700,
  ];
  return colors[index % colors.length];
}

double _niceChartMax(double value) {
  if (value <= 10) return 10;
  final magnitude = pow(10, value.floor().toString().length - 1).toDouble();
  return (value / magnitude).ceil() * magnitude;
}

Future<Map<String, String>> _savePdfFile(
    String fileName, Uint8List bytes) async {
  if (Platform.isAndroid) {
    final savedFile = await fileImportChannel.invokeMapMethod<String, String>(
      'savePdf',
      {'name': fileName, 'bytes': bytes},
    );
    return savedFile ?? {'name': fileName};
  }

  final downloads = await getDownloadsDirectory();
  final directory = downloads ?? Directory.current;
  final safeName = _safePdfFileName(fileName);
  final file = File(path.join(directory.path, safeName));
  await file.writeAsBytes(bytes, flush: true);
  return {'name': safeName, 'path': file.path};
}

String _safePdfFileName(String name) {
  final baseName = name
      .trim()
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
  final safe = baseName.isEmpty ? 'tilly_participants.pdf' : baseName;
  return safe.toLowerCase().endsWith('.pdf') ? safe : '$safe.pdf';
}
