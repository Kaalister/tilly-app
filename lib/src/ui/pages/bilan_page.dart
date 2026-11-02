import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../exports/pdf_exports.dart';
import '../../platform/backup_and_links.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/page_refresh.dart';

class BilanPage extends StatelessWidget {
  const BilanPage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => PageRefresh(
        controller: controller,
        builder: _buildPage,
      );

  Widget _buildPage(BuildContext context) {
    final totals = controller.paymentTotals();
    final donations = controller.activeSales
        .fold<double>(0, (total, sale) => total + sale.donation);
    final total =
        totals.values.fold<double>(0, (total, value) => total + value);
    final sold = <String, ({int quantity, double total})>{};
    for (final sale in controller.activeSales) {
      for (final item in sale.items) {
        final current = sold[item.name] ?? (quantity: 0, total: 0.0);
        sold[item.name] = (
          quantity: current.quantity + item.quantity,
          total: current.total + item.price * item.quantity
        );
      }
    }
    final soldEntries = sold.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle('Bilan de la journée',
            trailing: FilledButton.tonalIcon(
                onPressed: () {
                  final session = controller.activeSession;
                  if (session == null) {
                    snack(context, 'Aucune session active à exporter');
                    return;
                  }
                  exportBilanPdf(context, controller, session);
                },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'))),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.65,
          children: [
            MetricCard(
                label: 'Espèces',
                value: money(totals['ESP'] ?? 0),
                color: AppColors.cash),
            MetricCard(
                label: 'PayPal',
                value: money(totals['PayPal'] ?? 0),
                color: AppColors.paypal),
            MetricCard(
                label: 'SumUp',
                value: money(totals['SumUp'] ?? 0),
                color: AppColors.sumup),
            MetricCard(
                label: 'Total',
                value: money(total),
                color: AppColors.accent,
                caption: '${controller.activeSales.length} vente(s)'),
            MetricCard(
                label: 'Dons',
                value: money(donations),
                color: AppColors.accent2),
          ],
        ),
        const SectionTitle('Stock vendu'),
        TacticalCard(
          child: Column(
            children: [
              for (final entry in soldEntries)
                ListTile(
                  dense: true,
                  title: Text(entry.key),
                  subtitle: Text('${entry.value.quantity} unité(s)'),
                  trailing: Text(money(entry.value.total),
                      style: const TextStyle(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w900)),
                ),
              if (soldEntries.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun article vendu')),
            ],
          ),
        ),
      ],
    );
  }
}
