import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../exports/pdf_exports.dart';
import '../../services/kpi_service.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/page_refresh.dart';

class KpiPage extends StatelessWidget {
  const KpiPage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => PageRefresh(
        controller: controller,
        builder: _buildPage,
      );

  Widget _buildPage(BuildContext context) {
    final rows = kpiRows(controller);
    final totalCA = rows.fold<double>(0, (total, row) => total + row.ca);
    final ruptures = rows.where((r) => r.article.stock == 0).length;
    final alertes = rows
        .where((r) =>
            r.article.stock > 0 && r.article.stock <= r.article.threshold)
        .length;
    rows.sort(compareKpiRows);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                'Stats achats & stock',
                trailing: rows.isEmpty
                    ? null
                    : FilledButton.tonalIcon(
                        onPressed: () => exportKpiPdf(context, controller),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: const Text('Exporter'),
                      ),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.65,
                children: [
                  MetricCard(
                      label: 'Ruptures',
                      value: '$ruptures',
                      color: ruptures > 0 ? AppColors.danger : AppColors.cash),
                  MetricCard(
                      label: 'En alerte',
                      value: '$alertes',
                      color: alertes > 0 ? AppColors.warn : AppColors.cash),
                  MetricCard(
                      label: 'CA total',
                      value: money(totalCA),
                      color: AppColors.accent),
                  MetricCard(
                      label: 'À réappro',
                      value: '${rows.where((r) => r.suggestion > 0).length}',
                      color: AppColors.accent2),
                ],
              ),
              const SizedBox(height: 10),
            ],
          );
        }
        final row = rows[index - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: TacticalCard(
            borderColor: row.article.stock == 0
                ? AppColors.danger
                : row.article.stock <= row.article.threshold
                    ? AppColors.warn
                    : AppColors.border,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(row.article.icon,
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(row.article.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900))),
                    Text(
                        row.article.stock == 0
                            ? 'RUPTURE'
                            : row.article.stock <= row.article.threshold
                                ? 'ALERTE'
                                : 'OK',
                        style: TextStyle(
                            color: row.article.stock == 0
                                ? AppColors.danger
                                : row.article.stock <= row.article.threshold
                                    ? AppColors.warn
                                    : AppColors.cash,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                    value: row.rotation.clamp(0, 1),
                    color: row.rotation > .7
                        ? AppColors.accent
                        : row.rotation > .4
                            ? AppColors.warn
                            : AppColors.danger,
                    backgroundColor: AppColors.border),
                const SizedBox(height: 8),
                Text([
                  'Vendu ${row.sold}',
                  if (controller.mealsEnabled) 'Dans repas ${row.mealUsed}',
                  'Asso ${row.associationUsed}',
                  'Sorti ${row.outgoing}',
                  'CA ${money(row.ca)}',
                  'stock ${row.stockRest}/${row.stockInitial}',
                  'suggestion achat >= ${row.suggestion}',
                ].join(' · ')),
              ],
            ),
          ),
        );
      },
    );
  }
}
