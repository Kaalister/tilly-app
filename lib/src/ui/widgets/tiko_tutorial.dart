import 'package:flutter/material.dart';

import '../../domain/models.dart';
import '../theme.dart';

const String kTikoHeaderAsset =
    'assets/branding/tilli-tutorial-transparent.png';
const String kTikoWelcomeAsset =
    'assets/branding/expressions/tilli-welcome-transparent.png';

const _tikoTipAsset = 'assets/branding/expressions/tilli-tip-transparent.png';
const _tikoThinkingAsset =
    'assets/branding/expressions/tilli-thinking-transparent.png';
const _tikoSuccessAsset =
    'assets/branding/expressions/tilli-success-transparent.png';
const _tikoSurprisedAsset =
    'assets/branding/expressions/tilli-surprised-transparent.png';

class TikoTutorialContent {
  const TikoTutorialContent({
    required this.title,
    required this.asset,
    required this.messages,
    this.expressionAssets = const [],
  });

  final String title;
  final String asset;
  final List<String> messages;
  final List<String> expressionAssets;

  String assetForStep(int index) =>
      index < expressionAssets.length ? expressionAssets[index] : asset;
}

TikoTutorialContent tikoWelcomeTutorial() => const TikoTutorialContent(
      title: 'Bienvenue dans Tilly',
      asset: kTikoWelcomeAsset,
      expressionAssets: [
        kTikoWelcomeAsset,
        _tikoTipAsset,
        _tikoSuccessAsset,
        _tikoThinkingAsset,
      ],
      messages: [
        'Bienvenue dans Tilly, et merci d\'avoir choisi l\'application pour gérer tes ventes et tes événements.',
        'Moi, c\'est Tiko. Je vais te faire découvrir les différentes pages de Tilly et t\'aider à préparer ta première vente.',
        'Tu me retrouveras toujours en haut à droite de l\'entête. Clique sur moi à tout moment pour revoir l\'aide détaillée de la page affichée.',
        'Commençons par un tour rapide de l\'application. À la fin, je te conduirai dans Articles pour créer tes premiers produits.',
      ],
    );

TikoTutorialContent tikoFirebaseHelpTutorial() => const TikoTutorialContent(
      title: 'Synchronisation',
      asset: _tikoThinkingAsset,
      expressionAssets: [
        _tikoThinkingAsset,
        _tikoTipAsset,
        _tikoSuccessAsset,
        _tikoSurprisedAsset,
        _tikoTipAsset,
        _tikoThinkingAsset,
      ],
      messages: [
        'La synchronisation est optionnelle : sans elle, Tilly fonctionne normalement sur cet appareil.',
        'Elle sert à retrouver les mêmes données sur un autre appareil, par exemple un deuxième téléphone ou un ordinateur.',
        'Tilly ne fait rien tout seul : tu appuies sur Synchroniser quand tu veux envoyer ou récupérer des données.',
        'Si les données de cet appareil sont les plus récentes, elles sont envoyées pour être disponibles sur tes autres appareils.',
        'Si un autre appareil a des données plus récentes, Tilly te prévient, crée une copie de sécurité, puis te propose de les récupérer.',
        'Ne travaille pas sur deux appareils en même temps : synchronise avant de changer d\'appareil, puis une fois que tu as terminé.',
      ],
    );

TikoTutorialContent tikoHelloAssoHelpTutorial({bool mealsEnabled = true}) =>
    TikoTutorialContent(
      title: 'HelloAsso',
      asset: _tikoTipAsset,
      expressionAssets: const [
        _tikoTipAsset,
        _tikoSuccessAsset,
        _tikoThinkingAsset,
      ],
      messages: [
        mealsEnabled
            ? 'HelloAsso est facultatif. Sans connexion, tu peux toujours saisir manuellement les participants et les repas.'
            : 'HelloAsso est facultatif. Sans connexion, tu peux toujours saisir manuellement les participants.',
        'Une fois connecté, Tilly retrouve les événements publiés par ton association et importe les participants qui ont réglé leur inscription.',
        mealsEnabled
            ? 'Tilly peut aussi récupérer les informations utiles à la préparation des repas. Le guide t\'indique où trouver le nom de l\'association, le Client ID et le Client secret.'
            : 'Le guide t\'indique où trouver le nom de l\'association, le Client ID et le Client secret nécessaires à la connexion.',
      ],
    );

TikoTutorialContent tikoOnboardingForTab(String tabId) {
  switch (tabId) {
    case AppTabIds.meals:
      return const TikoTutorialContent(
        title: 'Repas',
        asset: _tikoTipAsset,
        messages: [
          'La page Repas permet d\'organiser les commandes des participants et de suivre leur préparation sans perdre le contrôle du stock.',
        ],
      );
    case AppTabIds.players:
      return const TikoTutorialContent(
        title: 'Participants',
        asset: _tikoSuccessAsset,
        messages: [
          'Dans Participants, tu ajoutes les joueurs de la session et tu définis leur tarif Public ou Adhérent avant de les sélectionner dans une vente.',
        ],
      );
    case AppTabIds.cash:
      return const TikoTutorialContent(
        title: 'Caisse espèces',
        asset: _tikoThinkingAsset,
        messages: [
          'La page Caisse espèces sert à compter le fond de caisse au début et à la fin de la journée, puis à contrôler les éventuels écarts.',
        ],
      );
    case AppTabIds.stats:
      return const TikoTutorialContent(
        title: 'Stats',
        asset: _tikoSurprisedAsset,
        messages: [
          'La page Stats rassemble les ventes, les mouvements de stock et les alertes afin de suivre l\'activité pendant l\'événement.',
        ],
      );
    case AppTabIds.bilan:
      return const TikoTutorialContent(
        title: 'Bilan',
        asset: _tikoSuccessAsset,
        messages: [
          'Dans Bilan, tu retrouves les totaux de la session par moyen de paiement et tu peux générer un récapitulatif en PDF.',
        ],
      );
    case AppTabIds.history:
      return const TikoTutorialContent(
        title: 'Historique',
        asset: _tikoThinkingAsset,
        messages: [
          'La page Historique te permet de créer une nouvelle session, de rouvrir un ancien événement et de consulter ses résultats.',
        ],
      );
    case AppTabIds.articles:
      return const TikoTutorialContent(
        title: 'Articles',
        asset: _tikoTipAsset,
        expressionAssets: [_tikoTipAsset, _tikoSuccessAsset],
        messages: [
          'Nous terminons dans Articles, car les produits doivent être créés avant de pouvoir les ajouter à une vente.',
          'Ajoute maintenant tes premiers articles avec leur nom, leur catégorie, leurs prix et leur stock. Tilly sera ensuite prête pour ton premier encaissement.',
        ],
      );
    case AppTabIds.config:
      return const TikoTutorialContent(
        title: 'Config',
        asset: _tikoThinkingAsset,
        messages: [
          'Dans Config, tu personnalises Tilly, choisis les pages visibles et règles les sauvegardes ainsi que les services connectés.',
        ],
      );
    case AppTabIds.sales:
    default:
      return const TikoTutorialContent(
        title: 'Vente',
        asset: _tikoTipAsset,
        messages: [
          'La page Vente est le cœur de la caisse. Tu y sélectionnes un participant, ajoutes ses articles au panier et choisis son moyen de paiement.',
        ],
      );
  }
}

TikoTutorialContent tikoTutorialForTab(String tabId) {
  switch (tabId) {
    case AppTabIds.meals:
      return const TikoTutorialContent(
        title: 'Repas',
        asset: _tikoTipAsset,
        expressionAssets: [
          _tikoTipAsset,
          _tikoThinkingAsset,
          _tikoSuccessAsset
        ],
        messages: [
          'Pour utiliser les repas, il faut que le module Repas soit actif, qu\'un participant existe et qu\'un article soit rangé dans la catégorie REPAS.',
          'Si le bouton Ajouter est bloqué, c\'est qu\'il manque encore un participant ou un article REPAS disponible.',
          'Quand tu crées un repas, choisis le participant, l\'origine de la commande, la formule, la boisson, le snack, les sauces et une note si besoin.',
          'Un repas marqué À préparer ne retire pas encore le stock, alors qu\'un repas marqué Préparé retire les éléments sélectionnés.',
        ],
      );
    case AppTabIds.players:
      return const TikoTutorialContent(
        title: 'Participants',
        asset: _tikoTipAsset,
        expressionAssets: [
          _tikoTipAsset,
          _tikoThinkingAsset,
          _tikoSuccessAsset
        ],
        messages: [
          'Avant de vendre, ajoute ici les joueurs de la session en renseignant au moins un prénom, un nom ou un email.',
          'Si un joueur a déjà été enregistré sur un ancien événement, sélectionne-le dans Participant existant pour éviter les doublons.',
          'Quand tu choisis Adhérent, Tilly applique automatiquement le tarif adhérent dans Vente; quand tu choisis Public, il garde le prix public.',
          'L\'historique par participant te permet de retrouver les ventes de chaque joueur et son total en fin d\'événement.',
        ],
      );
    case AppTabIds.cash:
      return const TikoTutorialContent(
        title: 'Caisse espèces',
        asset: _tikoThinkingAsset,
        expressionAssets: [
          _tikoThinkingAsset,
          _tikoTipAsset,
          _tikoSurprisedAsset
        ],
        messages: [
          'Au début de la journée, compte les billets et les pièces dans Fond début pour poser la base du contrôle espèces.',
          'Pendant la journée, seules les ventes validées en ESP alimentent la ligne Ventes ESP; PayPal et SumUp restent à part.',
          'À la fermeture, remplis Fond fin avec le contenu réel de la caisse après le dernier encaissement.',
          'Si l\'écart entre le théorique et le réel passe en rouge, recompte la caisse avant d\'exporter le bilan.',
        ],
      );
    case AppTabIds.stats:
      return const TikoTutorialContent(
        title: 'Stats',
        asset: _tikoSurprisedAsset,
        expressionAssets: [
          _tikoSurprisedAsset,
          _tikoThinkingAsset,
          _tikoTipAsset
        ],
        messages: [
          'Les statistiques deviennent utiles dès que tu as enregistré des ventes, préparé des repas ou saisi des sorties association.',
          'Les cartes Ruptures et En alerte se basent sur le stock restant et sur le seuil que tu as défini dans Articles.',
          'Chaque ligne d\'article te montre ce qui a été vendu, utilisé dans les repas, sorti pour l\'association, ainsi que le chiffre d\'affaires et le stock restant.',
          'Si une alerte te paraît étrange, commence par vérifier le stock et le seuil de l\'article concerné.',
        ],
      );
    case AppTabIds.bilan:
      return const TikoTutorialContent(
        title: 'Bilan',
        asset: _tikoSuccessAsset,
        expressionAssets: [
          _tikoSuccessAsset,
          _tikoThinkingAsset,
          _tikoTipAsset
        ],
        messages: [
          'Le bilan résume la session active en séparant les espèces, PayPal, SumUp, les dons, le total et le nombre de ventes.',
          'La section Stock vendu regroupe les articles passés en caisse, tandis que les repas préparés se contrôlent plutôt dans les statistiques de stock.',
          'Avant de générer le PDF, vérifie que les ventes annulées sont correctes et que la caisse espèces a bien été comptée.',
          'Quand tout est cohérent, exporte le PDF pour garder une trace propre de la journée.',
        ],
      );
    case AppTabIds.history:
      return const TikoTutorialContent(
        title: 'Historique',
        asset: _tikoThinkingAsset,
        expressionAssets: [
          _tikoThinkingAsset,
          _tikoTipAsset,
          _tikoSuccessAsset
        ],
        messages: [
          'Une session correspond à un événement ou à une journée de vente, et Tilly sépare les ventes, les repas, la caisse et les bilans pour chacune.',
          'Quand tu prépares un nouvel événement, crée une nouvelle session et donne-lui un nom clair avant le premier encaissement.',
          'Lorsque tu ouvres une ancienne session, elle redevient active; les prochains encaissements seront donc enregistrés dedans.',
          'Depuis une session qui contient des ventes, tu peux aussi générer son bilan PDF.',
        ],
      );
    case AppTabIds.articles:
      return const TikoTutorialContent(
        title: 'Articles',
        asset: _tikoTipAsset,
        expressionAssets: [
          _tikoTipAsset,
          _tikoThinkingAsset,
          _tikoSuccessAsset,
          _tikoSurprisedAsset
        ],
        messages: [
          'Commence par cet écran avant d\'ouvrir la caisse, car la page Vente ne peut rien ajouter au panier sans article actif.',
          'Si tes produits ont besoin d\'être rangés autrement, ajoute d\'abord une catégorie, puis crée le produit depuis Ajouter dans Articles & prix.',
          'Quand tu crées un article, le nom est obligatoire, et l\'icône, la catégorie, le type et les prix pilotent l\'affichage et les tarifs.',
          'Si tu choisis Article en stock, Tilly utilise le stock et le seuil; si tu choisis Location, l\'article se facture sans retirer de stock.',
          'Quand tu utilises Sortie asso, Tilly retire du stock sans créer de vente, par exemple pour une conso staff, de la casse ou un ajustement terrain.',
        ],
      );
    case AppTabIds.config:
      return const TikoTutorialContent(
        title: 'Config',
        asset: _tikoThinkingAsset,
        expressionAssets: [
          _tikoThinkingAsset,
          _tikoTipAsset,
          _tikoSuccessAsset,
          _tikoSurprisedAsset
        ],
        messages: [
          'Dans Personnalisation, tu peux changer le nom, l\'image, la couleur et les onglets visibles sans supprimer les données des onglets masqués.',
          'La partie HelloAsso sert à préparer les imports et les événements, tandis que la partie Synchronisation permet de retrouver les données sur un autre appareil.',
          'La partie Sauvegarde exporte toutes les données locales, et je te conseille d\'en faire une avant une mise à jour ou une restauration.',
          'La remise à zéro efface les données métier, donc utilise-la seulement après une sauvegarde et jamais au milieu des encaissements.',
        ],
      );
    case AppTabIds.sales:
    default:
      return const TikoTutorialContent(
        title: 'Vente',
        asset: _tikoTipAsset,
        expressionAssets: [
          _tikoSurprisedAsset,
          _tikoTipAsset,
          _tikoThinkingAsset,
          _tikoSuccessAsset
        ],
        messages: [
          'Pour faire une vente, il faut d\'abord avoir au moins un participant dans Participants et au moins un article actif dans Articles.',
          'Commence par sélectionner le joueur, car son type Public ou Adhérent choisit le tarif appliqué dans le panier.',
          'Ajoute ensuite les produits depuis la grille, puis utilise les boutons plus et moins du panier pour corriger les quantités.',
          'Les boutons ESP, PayPal et SumUp s\'activent seulement lorsqu\'un joueur est sélectionné, que le panier ou le don n\'est pas vide, et que le stock suffit.',
          'Si Tilly affiche Stock insuffisant, retourne dans Articles pour corriger le stock ou retire l\'article concerné du panier.',
        ],
      );
  }
}

class TikoTutorialButton extends StatelessWidget {
  const TikoTutorialButton({
    required this.onPressed,
    this.tooltip = 'Revoir le tuto de Tiko',
    super.key,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Tooltip(
        message: tooltip,
        child: InkResponse(
          radius: 24,
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: context.primaryAccent, width: 1.5),
              color: AppColors.surface2,
            ),
            child: ClipOval(
              child: Image.asset(
                kTikoHeaderAsset,
                width: 40,
                height: 40,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.help_outline,
                  color: context.primaryAccent,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TikoHelpButton extends StatelessWidget {
  const TikoHelpButton({
    required this.onPressed,
    required this.tooltip,
    super.key,
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: ClipOval(
          child: Image.asset(
            kTikoHeaderAsset,
            width: 28,
            height: 28,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              Icons.assistant,
              color: context.primaryAccent,
              size: 22,
            ),
          ),
        ),
        label: const Text('À quoi ça sert ?'),
      ),
    );
  }
}

class TikoTutorialDialog extends StatefulWidget {
  const TikoTutorialDialog({
    required this.content,
    this.primaryActionLabel = 'Compris',
    super.key,
  });

  final TikoTutorialContent content;
  final String primaryActionLabel;

  @override
  State<TikoTutorialDialog> createState() => _TikoTutorialDialogState();
}

class _TikoTutorialDialogState extends State<TikoTutorialDialog> {
  var _step = 0;

  TikoTutorialContent get content => widget.content;
  bool get _isLastStep => _step >= content.messages.length - 1;

  void _advance() {
    if (_isLastStep) {
      Navigator.pop(context, true);
      return;
    }
    setState(() => _step += 1);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            final tikoWidth = compact
                ? (constraints.maxWidth * .52).clamp(170.0, 230.0)
                : (constraints.maxWidth * .24).clamp(230.0, 310.0);
            final bubbleLeft = compact
                ? (constraints.maxWidth * .28).clamp(88.0, 132.0)
                : tikoWidth * .68 + 28;
            final bubbleBottom = compact ? tikoWidth * .54 : tikoWidth * .48;
            final bubbleMaxWidth =
                (constraints.maxWidth - bubbleLeft - 18).clamp(210.0, 440.0);

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: _advance,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: .18),
                    ),
                  ),
                ),
                Positioned(
                  left: compact ? -18 : 18,
                  bottom: compact ? -8 : -18,
                  child: IgnorePointer(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: Image.asset(
                        content.assetForStep(_step),
                        key: ValueKey(content.assetForStep(_step)),
                        width: tikoWidth,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.assistant,
                          size: tikoWidth * .5,
                          color: context.primaryAccent,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: bubbleLeft,
                  right: compact ? 12 : null,
                  bottom: bubbleBottom,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                    child: _TikoSpeechBubble(
                      title: content.title,
                      text: content.messages[_step],
                      step: _step,
                      stepCount: content.messages.length,
                      actionLabel:
                          _isLastStep ? widget.primaryActionLabel : 'Suivant',
                      onPressed: _advance,
                    ),
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton.filledTonal(
                    tooltip: 'Fermer le tuto',
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TikoSpeechBubble extends StatelessWidget {
  const _TikoSpeechBubble({
    required this.title,
    required this.text,
    required this.step,
    required this.stepCount,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final String text;
  final int step;
  final int stepCount;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CustomPaint(
          painter: _BubbleTailPainter(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 14, 28),
            child: DefaultTextStyle(
              style: const TextStyle(color: AppColors.text),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Text(
                      text,
                      key: ValueKey(text),
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _StepDots(current: step, count: stepCount),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              backgroundColor: context.primaryAccent,
                              foregroundColor: context.onPrimaryAccent,
                            ),
                            onPressed: onPressed,
                            child: Text(
                              actionLabel,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 24,
          top: -10,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(
                'TIKO - $title',
                style: TextStyle(
                  color: context.primaryAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.count});

  final int current;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: i == current ? 18 : 7,
            height: 7,
            margin: const EdgeInsets.only(right: 5),
            decoration: BoxDecoration(
              color: i == current ? context.primaryAccent : AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  const _BubbleTailPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = AppColors.surface2
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final shadow = Paint()
      ..color = Colors.black.withValues(alpha: .22)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    final body = RRect.fromLTRBR(
        10, 0, size.width, size.height - 16, Radius.circular(12));
    final path = Path();
    path.addRRect(body);
    path
      ..moveTo(64, size.height - 16)
      ..quadraticBezierTo(48, size.height - 1, 30, size.height)
      ..quadraticBezierTo(38, size.height - 11, 38, size.height - 16)
      ..close();

    canvas.drawPath(path.shift(const Offset(0, 4)), shadow);
    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) => false;
}
