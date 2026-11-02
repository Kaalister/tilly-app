import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../exports/pdf_exports.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/page_refresh.dart';

class CashAnalysisPage extends StatelessWidget {
  const CashAnalysisPage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) => PageRefresh(
        controller: controller,
        builder: _buildPage,
      );

  Widget _buildPage(BuildContext context) {
    final start = controller.cashTotal('start');
    final end = controller.cashTotal('end');
    final cashSales = controller.paymentTotals()['ESP'] ?? 0;
    final theoretical = start + cashSales;
    final gap = end - theoretical;
    final analysisCard = TacticalCard(
      borderColor: AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('ANALYSE',
              style: TextStyle(
                  color: AppColors.muted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          AnalysisRow(label: 'Fond début', value: money(start)),
          AnalysisRow(
              label: '+ Ventes ESP',
              value: money(cashSales),
              color: AppColors.cash),
          AnalysisRow(label: '= Théorique', value: money(theoretical)),
          AnalysisRow(label: 'Fond fin réel', value: money(end)),
          const Divider(color: AppColors.border),
          AnalysisRow(
              label: 'Écart',
              value: money(gap),
              color: gap.abs() < .01 ? AppColors.cash : AppColors.danger,
              large: true),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        final contentWidth = constraints.maxWidth - 24;
        final cashTabs = SizedBox(
          height: _cashTabsHeight(contentWidth, wide: wide),
          child: CashCountTabs(
            startTotal: start,
            endTotal: end,
            controller: controller,
          ),
        );
        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            SectionTitle(
              'Caisse espèces',
              trailing: FilledButton.tonalIcon(
                onPressed: () => exportCashPdf(context, controller),
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('PDF'),
              ),
            ),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cashTabs),
                  const SizedBox(width: 10),
                  SizedBox(width: 330, child: analysisCard),
                ],
              )
            else ...[
              analysisCard,
              const SizedBox(height: 10),
              cashTabs,
            ],
          ],
        );
      },
    );
  }
}

class CashCountTabs extends StatelessWidget {
  const CashCountTabs(
      {required this.startTotal,
      required this.endTotal,
      required this.controller,
      super.key});

  final double startTotal;
  final double endTotal;
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.muted,
              indicator: const BoxDecoration(color: AppColors.surface2),
              tabs: [
                Tab(
                  child: _CashTabLabel(
                    title: 'Fond début',
                    total: startTotal,
                  ),
                ),
                Tab(
                  child: _CashTabLabel(
                    title: 'Fond fin',
                    total: endTotal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                CashCountCard(
                    title: 'Fond début',
                    kind: 'start',
                    total: startTotal,
                    controller: controller,
                    showHeader: false),
                CashCountCard(
                    title: 'Fond fin',
                    kind: 'end',
                    total: endTotal,
                    controller: controller,
                    showHeader: false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CashTabLabel extends StatelessWidget {
  const _CashTabLabel({required this.title, required this.total});

  final String title;
  final double total;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text(money(total),
              style: const TextStyle(
                  color: AppColors.accent, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class AnalysisRow extends StatelessWidget {
  const AnalysisRow(
      {required this.label,
      required this.value,
      this.color,
      this.large = false,
      super.key});

  final String label;
  final String value;
  final Color? color;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: color ?? AppColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: large ? 22 : 15)),
        ],
      ),
    );
  }
}

class CashCountCard extends StatelessWidget {
  const CashCountCard(
      {required this.title,
      required this.kind,
      required this.total,
      required this.controller,
      this.showHeader = true,
      super.key});

  final String title;
  final String kind;
  final double total;
  final AppController controller;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final map = kind == 'start' ? controller.cashStart : controller.cashEnd;
    return TacticalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Text(title.toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.muted,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(money(total),
                    style: const TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 520
                    ? 3
                    : constraints.maxWidth >= 340
                        ? 2
                        : 1;
                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  primary: false,
                  itemCount: denominations.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 78,
                    crossAxisSpacing: 6,
                    mainAxisSpacing: 6,
                  ),
                  itemBuilder: (context, index) {
                    final value = denominations[index];
                    final key = value.toString();
                    final qty = map[key] ?? 0;
                    final label = value >= 1
                        ? '${value.round()} €'
                        : '${(value * 100).round()} cts';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                          color: AppColors.surface2,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(6)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800))),
                              Text(qty > 0 ? money(value * qty) : '-',
                                  style: const TextStyle(
                                      color: AppColors.accent,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800)),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              SizedBox.square(
                                dimension: 30,
                                child: IconButton.filledTonal(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => controller.updateCash(
                                      kind, value, qty - 1),
                                  icon: const Icon(Icons.remove, size: 16),
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: FittedBox(
                                    child: Text('$qty',
                                        style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                ),
                              ),
                              SizedBox.square(
                                dimension: 30,
                                child: IconButton.filledTonal(
                                  padding: EdgeInsets.zero,
                                  onPressed: () => controller.updateCash(
                                      kind, value, qty + 1),
                                  icon: const Icon(Icons.add, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

double _cashTabsHeight(double width, {required bool wide}) {
  if (wide) return 620;

  const tabBarHeight = 48.0;
  const tabSpacing = 10.0;
  const cardVerticalPadding = 24.0;
  const itemHeight = 78.0;
  const itemSpacing = 6.0;

  final gridWidth = width - cardVerticalPadding;
  final columns = gridWidth >= 520
      ? 3
      : gridWidth >= 340
          ? 2
          : 1;
  final rows = (denominations.length / columns).ceil();
  final gridHeight = rows * itemHeight + (rows - 1) * itemSpacing;

  return tabBarHeight + tabSpacing + cardVerticalPadding + gridHeight;
}
