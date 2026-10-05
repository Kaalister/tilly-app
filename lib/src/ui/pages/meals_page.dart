import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../platform/backup_and_links.dart';
import '../../utils/iterable_extensions.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

class MealsPage extends StatefulWidget {
  const MealsPage({required this.controller, super.key});

  final AppController controller;

  @override
  State<MealsPage> createState() => _MealsPageState();
}

class _MealsPageState extends State<MealsPage> {
  String filter = 'all';
  String query = '';

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prepared =
        controller.meals.where((meal) => meal.status == 'prepared').length;
    final served =
        controller.meals.where((meal) => meal.status == 'served').length;
    final planned =
        controller.meals.where((meal) => meal.status == 'planned').length;
    final onsite = controller.meals
        .where((meal) => meal.source == 'onsite' && meal.status != 'cancelled')
        .length;
    final normalizedQuery = query.trim().toLowerCase();
    final visible = controller.meals.where((meal) {
      if (filter != 'all' && meal.status != filter) {
        return false;
      }
      return normalizedQuery.isEmpty ||
          meal.playerName.toLowerCase().contains(normalizedQuery) ||
          meal.note.toLowerCase().contains(normalizedQuery);
    }).toList()
      ..sort((a, b) {
        final statusOrder = {'prepared': 0, 'planned': 1, 'served': 2};
        final compare =
            (statusOrder[a.status] ?? 3).compareTo(statusOrder[b.status] ?? 3);
        return compare != 0 ? compare : a.playerName.compareTo(b.playerName);
      });

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(
          'Repas',
          trailing: FilledButton.icon(
            onPressed:
                controller.players.isEmpty || controller.mealArticles.isEmpty
                    ? null
                    : () => showMealDialog(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.8,
          children: [
            MetricCard(
                label: 'À préparer', value: '$planned', color: AppColors.warn),
            MetricCard(
                label: 'Préparés',
                value: '$prepared',
                color: AppColors.accent2),
            MetricCard(
                label: 'Servis', value: '$served', color: AppColors.cash),
            MetricCard(
                label: 'Sur place', value: '$onsite', color: AppColors.accent),
          ],
        ),
        const SizedBox(height: 10),
        TacticalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Rechercher un participant ou une note',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _mealFilterChip('Tous', 'all'),
                  _mealFilterChip('À préparer', 'planned'),
                  _mealFilterChip('À remettre', 'prepared'),
                  _mealFilterChip('Servis', 'served'),
                  _mealFilterChip('Annulés', 'cancelled'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (controller.players.isEmpty)
          const TacticalCard(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Ajoutez ou importez des participants avant de créer des repas.'),
            ),
          )
        else if (controller.mealArticles.isEmpty)
          const TacticalCard(
            borderColor: AppColors.warn,
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                  'Ajoutez un article dans la catégorie REPAS pour utiliser ce module.'),
            ),
          )
        else if (visible.isEmpty)
          const TacticalCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: Text('Aucun repas dans cette vue')),
            ),
          ),
        for (final meal in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _mealCard(context, meal),
          ),
      ],
    );
  }

  ChoiceChip _mealFilterChip(String label, String value) => ChoiceChip(
        label: Text(label),
        selected: filter == value,
        onSelected: (_) => setState(() => filter = value),
      );

  Widget _mealCard(BuildContext context, MealOrder meal) {
    final controller = widget.controller;
    final stockLines = [
      controller.articles
          .where((article) => article.id == meal.mealArticleId)
          .firstOrNull
          ?.name,
      controller.articles
          .where((article) => article.id == meal.drinkArticleId)
          .firstOrNull
          ?.name,
      controller.articles
          .where((article) => article.id == meal.snackArticleId)
          .firstOrNull
          ?.name,
    ].whereType<String>().join(' · ');
    final statusColor = meal.status == 'cancelled'
        ? AppColors.danger
        : meal.status == 'served'
            ? AppColors.cash
            : meal.status == 'prepared'
                ? AppColors.accent2
                : AppColors.warn;
    final status = meal.status == 'cancelled'
        ? 'ANNULÉ'
        : meal.status == 'served'
            ? 'SERVI${meal.servedAt == null ? '' : ' ${timeLabel(meal.servedAt!)}'}'
            : meal.status == 'prepared'
                ? 'PRÉPARÉ'
                : 'À PRÉPARER';
    final source = meal.source == 'onsite'
        ? 'Sur place${meal.payment.isEmpty ? '' : ' · ${meal.payment}'}'
        : 'HelloAsso';
    final sauces = meal.options
        .where((option) => _mealSauceOptions.contains(option))
        .toList();
    final indications = meal.options
        .where((option) => _mealIndicationOptions.contains(option))
        .toList();
    final unclassifiedOptions = meal.options
        .where((option) =>
            !_mealSauceOptions.contains(option) &&
            !_mealIndicationOptions.contains(option))
        .toList();
    final details = [
      meal.formula,
      stockLines,
      if (sauces.isNotEmpty) 'Sauces : ${sauces.join(', ')}',
      if (unclassifiedOptions.isNotEmpty) unclassifiedOptions.join(', '),
    ].where((line) => line.isNotEmpty).join(' - ');
    final preparationAlerts = <String>[];
    if (meal.status == 'planned') {
      for (final entry in meal.stockItems.entries) {
        final article = controller.articles
            .where((value) => value.id == entry.key)
            .firstOrNull;
        if (article == null) continue;
        final after = article.stock - entry.value;
        if (after < 0) {
          preparationAlerts.add('${article.name} : stock insuffisant');
        } else if (after == 0) {
          preparationAlerts.add('${article.name} : rupture');
        } else if (article.threshold > 0 && after <= article.threshold) {
          preparationAlerts.add('${article.name} : alerte ($after)');
        }
      }
    }
    return TacticalCard(
      borderColor: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(meal.playerName,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              Text(status,
                  style: TextStyle(
                      color: statusColor, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text(source, style: const TextStyle(color: AppColors.muted)),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(details),
          ],
          if (indications.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Indications : ${indications.join(', ')}',
                style: TextStyle(
                    color: indications.contains('Allergie')
                        ? AppColors.danger
                        : AppColors.warn,
                    fontWeight: FontWeight.w800)),
          ],
          if (meal.note.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Note : ${meal.note}',
                style: TextStyle(
                    color: meal.note.toLowerCase().contains('allerg')
                        ? AppColors.danger
                        : AppColors.accent2,
                    fontWeight: FontWeight.w700)),
          ],
          if (preparationAlerts.isNotEmpty) ...[
            const SizedBox(height: 7),
            Text('Après préparation : ${preparationAlerts.join(' · ')}',
                style: const TextStyle(
                    color: AppColors.warn, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (meal.status == 'planned')
                OutlinedButton.icon(
                  onPressed: () =>
                      _runMealAction(() => controller.prepareMeal(meal)),
                  icon: const Icon(Icons.lunch_dining),
                  label: const Text('Préparer'),
                ),
              if (meal.status == 'prepared') ...[
                FilledButton.icon(
                  onPressed: () =>
                      _runMealAction(() => controller.serveMeal(meal)),
                  icon: const Icon(Icons.check),
                  label: const Text('Servir'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      _runMealAction(() => controller.unprepareMeal(meal)),
                  icon: const Icon(Icons.undo),
                  label: const Text('Remettre à préparer'),
                ),
              ],
              if (meal.status == 'served') ...[
                OutlinedButton.icon(
                  onPressed: () =>
                      _runMealAction(() => controller.unserveMeal(meal)),
                  icon: const Icon(Icons.undo),
                  label: const Text('Remettre en préparé'),
                ),
              ],
              if (meal.status != 'cancelled')
                OutlinedButton.icon(
                  onPressed: () =>
                      showMealDialog(context, controller, meal: meal),
                  icon: const Icon(Icons.edit),
                  label: const Text('Modifier'),
                ),
              if (meal.status != 'cancelled')
                OutlinedButton.icon(
                  onPressed: () async {
                    final message = meal.isOnsite
                        ? 'Annuler ce repas et sa vente associée ? Le stock préparé sera restauré.'
                        : 'Annuler ce repas ? Le stock préparé sera restauré.';
                    if (await confirm(context, message)) {
                      await _runMealAction(() => controller.cancelMeal(meal));
                    }
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('Annuler'),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _runMealAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) snack(context, 'Repas impossible : $error');
    }
  }
}

const _mealSauceOptions = <String>[
  'Ketchup',
  'Mayonnaise',
  'Moutarde',
  'Sans sauce',
];

const _mealIndicationOptions = <String>[
  'Végétarien',
  'Sans porc',
  'Allergie',
];

Future<void> showMealDialog(BuildContext context, AppController controller,
    {MealOrder? meal}) async {
  if (controller.players.isEmpty || controller.mealArticles.isEmpty) return;
  final result = await showDialog<_MealDialogResult>(
    context: context,
    builder: (context) => _MealDialog(controller: controller, meal: meal),
  );
  if (result == null) return;
  await Future<void>.delayed(kThemeAnimationDuration);
  if (!context.mounted) return;
  try {
    if (meal == null) {
      final player = controller.players
          .where((entry) => entry.id == result.playerId)
          .first;
      await controller.createMeal(
        player: player,
        source: result.source,
        status: result.status,
        payment: result.source == 'onsite' ? result.payment : '',
        mealArticleId: result.mealArticleId,
        drinkArticleId: result.drinkArticleId,
        snackArticleId: result.snackArticleId,
        formula: result.formula,
        options: result.options,
        note: result.note,
      );
    } else {
      await controller.updateMeal(
        meal,
        meal.copyWith(
          mealArticleId: result.mealArticleId,
          drinkArticleId: result.drinkArticleId,
          snackArticleId: result.snackArticleId,
          formula: result.formula,
          options: result.options,
          note: result.note.trim(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  } catch (error) {
    if (context.mounted) snack(context, 'Repas impossible : $error');
  }
}

class _MealDialogResult {
  const _MealDialogResult({
    required this.playerId,
    required this.source,
    required this.payment,
    required this.status,
    required this.formula,
    required this.mealArticleId,
    required this.drinkArticleId,
    required this.snackArticleId,
    required this.options,
    required this.note,
  });

  final String playerId;
  final String source;
  final String payment;
  final String status;
  final String formula;
  final String mealArticleId;
  final String drinkArticleId;
  final String snackArticleId;
  final List<String> options;
  final String note;
}

class _MealDialog extends StatefulWidget {
  const _MealDialog({required this.controller, required this.meal});

  final AppController controller;
  final MealOrder? meal;

  @override
  State<_MealDialog> createState() => _MealDialogState();
}

class _MealDialogState extends State<_MealDialog> {
  late String playerId;
  late String source;
  late String payment;
  late String status;
  late String formula;
  late String mealArticleId;
  late String drinkArticleId;
  late String snackArticleId;
  late final Set<String> options;
  late final TextEditingController note;

  AppController get controller => widget.controller;
  MealOrder? get meal => widget.meal;

  @override
  void initState() {
    super.initState();
    final meal = widget.meal;
    playerId = meal?.playerId ?? controller.players.first.id;
    source = meal?.source ?? 'helloasso';
    payment = meal?.payment ?? 'ESP';
    status = meal?.status == 'planned' ? 'planned' : 'prepared';
    formula = meal?.formula ?? 'Standard';
    mealArticleId = meal?.mealArticleId ?? controller.mealArticles.first.id;
    drinkArticleId = meal?.drinkArticleId ??
        (controller.drinkArticles.firstOrNull?.id ?? '');
    snackArticleId = meal?.snackArticleId ??
        (controller.snackArticles.firstOrNull?.id ?? '');
    options = <String>{...?meal?.options};
    note = TextEditingController(text: meal?.note ?? '');
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void applyFormula(String value) {
    formula = value;
    if (value == 'Boisson seule') {
      snackArticleId = '';
      drinkArticleId = controller.drinkArticles.firstOrNull?.id ?? '';
    }
    if (value == 'Standard' && snackArticleId.isEmpty) {
      snackArticleId = controller.snackArticles.firstOrNull?.id ?? '';
    }
  }

  String stockPreview(String articleId) {
    if (articleId.isEmpty) return '';
    final article =
        controller.articles.where((entry) => entry.id == articleId).firstOrNull;
    if (article == null) return '';
    var after = article.stock;
    final meal = widget.meal;
    if (meal?.consumesStock ?? false) {
      after += meal!.stockItems[articleId] ?? 0;
    }
    if (status == 'prepared') {
      final selected = [mealArticleId, drinkArticleId, snackArticleId]
          .where((id) => id == articleId)
          .length;
      after -= selected;
    }
    final alert = after == 0
        ? ' · RUPTURE'
        : article.threshold > 0 && after <= article.threshold
            ? ' · ALERTE'
            : '';
    return 'Stock ${article.stock} → $after$alert';
  }

  @override
  Widget build(BuildContext context) {
    final meal = widget.meal;
    return AlertDialog(
      title: Text(meal == null ? 'Nouveau repas' : 'Modifier le repas'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (meal == null)
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: playerId,
                  decoration: const InputDecoration(labelText: 'Participant'),
                  items: [
                    for (final player in controller.players)
                      DropdownMenuItem(
                          value: player.id,
                          child: Text(player.name,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (value) =>
                      setState(() => playerId = value ?? playerId),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(meal.playerName),
                  subtitle: Text(meal.source == 'onsite'
                      ? 'Repas acheté sur place'
                      : 'Repas prépayé HelloAsso'),
                ),
              if (meal == null) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: source,
                  decoration: const InputDecoration(labelText: 'Origine'),
                  items: const [
                    DropdownMenuItem(
                        value: 'helloasso', child: Text('Prépayé HelloAsso')),
                    DropdownMenuItem(
                        value: 'onsite', child: Text('Achat sur place')),
                  ],
                  onChanged: (value) =>
                      setState(() => source = value ?? source),
                ),
                if (source == 'onsite') ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: payment,
                    decoration: const InputDecoration(labelText: 'Paiement'),
                    items: const [
                      DropdownMenuItem(value: 'ESP', child: Text('Espèces')),
                      DropdownMenuItem(value: 'PayPal', child: Text('PayPal')),
                      DropdownMenuItem(value: 'SumUp', child: Text('SumUp')),
                    ],
                    onChanged: (value) =>
                        setState(() => payment = value ?? payment),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              const Text('Formule rapide',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                children: [
                  for (final value in [
                    'Standard',
                    'Boisson seule'
                  ])
                    ChoiceChip(
                      label: Text(value),
                      selected: formula == value,
                      onSelected: (_) => setState(() => applyFormula(value)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('meal-$mealArticleId'),
                initialValue: mealArticleId,
                decoration: const InputDecoration(labelText: 'Repas'),
                items: [
                  for (final article in controller.mealArticles)
                    DropdownMenuItem(
                        value: article.id,
                        child: Text('${article.name} (${article.stock})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    setState(() => mealArticleId = value ?? mealArticleId),
              ),
              Text(stockPreview(mealArticleId),
                  style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('drink-$drinkArticleId'),
                initialValue: drinkArticleId.isEmpty ? null : drinkArticleId,
                decoration: const InputDecoration(labelText: 'Boisson incluse'),
                items: [
                  const DropdownMenuItem(
                      value: '', child: Text('Aucune boisson')),
                  for (final article in controller.drinkArticles)
                    DropdownMenuItem(
                        value: article.id,
                        child: Text('${article.name} (${article.stock})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    setState(() => drinkArticleId = value ?? ''),
              ),
              if (drinkArticleId.isNotEmpty)
                Text(stockPreview(drinkArticleId),
                    style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                isExpanded: true,
                key: ValueKey('snack-$snackArticleId'),
                initialValue: snackArticleId.isEmpty ? null : snackArticleId,
                decoration: const InputDecoration(labelText: 'Snack inclus'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Aucun snack')),
                  for (final article in controller.snackArticles)
                    DropdownMenuItem(
                        value: article.id,
                        child: Text('${article.name} (${article.stock})',
                            overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) =>
                    setState(() => snackArticleId = value ?? ''),
              ),
              if (snackArticleId.isNotEmpty)
                Text(stockPreview(snackArticleId),
                    style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              const Text('Sauces',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final option in _mealSauceOptions)
                    FilterChip(
                      label: Text(option),
                      selected: options.contains(option),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          if (option == 'Sans sauce') {
                            options.removeAll(_mealSauceOptions);
                          } else {
                            options.remove('Sans sauce');
                          }
                          options.add(option);
                        } else {
                          options.remove(option);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Indications rapides',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final indication in _mealIndicationOptions)
                    FilterChip(
                      label: Text(indication),
                      selected: options.contains(indication),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          options.add(indication);
                        } else {
                          options.remove(indication);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Note rapide',
                    hintText: 'Ex : allergie arachides, à remettre avec Léa'),
              ),
              if (meal == null) ...[
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'planned',
                        icon: Icon(Icons.event_note),
                        label: Text('À préparer')),
                    ButtonSegment(
                        value: 'prepared',
                        icon: Icon(Icons.lunch_dining),
                        label: Text('Préparé')),
                  ],
                  selected: {status},
                  onSelectionChanged: (selected) =>
                      setState(() => status = selected.first),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context);
            },
            child: const Text('Annuler')),
        FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.pop(context, _result());
            },
            child: const Text('Enregistrer')),
      ],
    );
  }

  _MealDialogResult _result() {
    return _MealDialogResult(
      playerId: playerId,
      source: source,
      payment: payment,
      status: status,
      formula: formula,
      mealArticleId: mealArticleId,
      drinkArticleId: drinkArticleId,
      snackArticleId: snackArticleId,
      options: options.toList(),
      note: note.text,
    );
  }
}
