import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../exports/pdf_exports.dart';
import '../../platform/backup_and_links.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class PlayersPage extends StatelessWidget {
  const PlayersPage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final salesByPlayer = <String, List<Sale>>{};
    for (final sale in controller.activeSales) {
      salesByPlayer.putIfAbsent(sale.playerId, () => []).add(sale);
    }
    final historyEntries = salesByPlayer.entries.toList()
      ..sort((a, b) => b.value
          .fold<double>(0, (s, v) => s + v.total)
          .compareTo(a.value.fold<double>(0, (s, v) => s + v.total)));
    final players = [...controller.players]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(
          'Participants de l\'événement (${players.length})',
          trailing: IconButton.filledTonal(
            onPressed: () => showPlayerDialog(context, controller),
            icon: const Icon(Icons.person_add),
            tooltip: 'Nouveau participant',
          ),
        ),
        if (players.isEmpty)
          TacticalCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => showPlayerDialog(context, controller),
                  icon: const Icon(Icons.person_add),
                  label: const Text('Ajouter un participant'),
                ),
              ),
            ),
          )
        else
          for (final player in players)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SessionPlayerCard(
                controller: controller,
                player: player,
                sales: salesByPlayer[player.id] ?? const <Sale>[],
              ),
            ),
        SectionTitle(
          'Historique par participant',
          trailing: historyEntries.isEmpty
              ? null
              : FilledButton.tonalIcon(
                  onPressed: () => exportPlayersPdf(context, controller),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('PDF'),
                ),
        ),
        if (historyEntries.isEmpty)
          const TacticalCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child:
                    Text('Aucune vente enregistrée pour cet événement'),
              ),
            ),
          )
        else
          for (final entry in historyEntries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _PlayerSalesHistoryCard(
                controller: controller,
                sales: entry.value,
              ),
            ),
      ],
    );
  }
}

class _SessionPlayerCard extends StatelessWidget {
  const _SessionPlayerCard({
    required this.controller,
    required this.player,
    required this.sales,
  });

  final AppController controller;
  final Player player;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final total = sales.fold<double>(
        0, (runningTotal, sale) => runningTotal + sale.total);
    return TacticalCard(
      borderColor: player.isMember ? AppColors.accent2 : AppColors.border,
      child: Row(
        children: [
          Icon(
            player.isMember ? Icons.verified_user : Icons.person,
            color: player.isMember ? AppColors.accent2 : AppColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(player.isMember ? 'Adhérent' : 'Public',
                        style: const TextStyle(color: AppColors.muted)),
                    Text('${sales.length} vente(s)',
                        style: const TextStyle(color: AppColors.muted)),
                    Text(money(total),
                        style: TextStyle(
                            color: context.primaryAccent,
                            fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Modifier le participant',
            onPressed: () =>
                showPlayerDialog(context, controller, player: player),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
    );
  }
}

class _PlayerSalesHistoryCard extends StatelessWidget {
  const _PlayerSalesHistoryCard({
    required this.controller,
    required this.sales,
  });

  final AppController controller;
  final List<Sale> sales;

  @override
  Widget build(BuildContext context) {
    final total = sales.fold<double>(
        0, (runningTotal, sale) => runningTotal + sale.total);
    return TacticalCard(
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(sales.first.playerName,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('${sales.length} vente(s)'),
        trailing: Text(money(total),
            style: TextStyle(
                color: context.primaryAccent, fontWeight: FontWeight.w900)),
        children: [
          for (final sale in sales.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                  sale.items.map((i) => '${i.quantity}x ${i.name}').join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${timeLabel(sale.createdAt)} - ${dateLabel(sale.createdAt)} - ${sale.payment}${sale.donation > 0 ? ' - don ${money(sale.donation)}' : ''}'),
              trailing: IconButton(
                tooltip: 'Annuler',
                onPressed: () async {
                  final ok = await confirm(
                      context, 'Annuler cette vente et restaurer le stock ?');
                  if (ok) await controller.cancelSale(sale);
                },
                icon: const Icon(Icons.undo, color: AppColors.danger),
              ),
            ),
        ],
      ),
    );
  }
}
