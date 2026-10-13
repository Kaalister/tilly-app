import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../../controllers/app_controller.dart';
import '../../domain/models.dart';
import '../../exports/pdf_exports.dart';
import '../../platform/backup_and_links.dart';
import '../../services/app_update_service.dart';
import '../../services/firebase_bootstrap.dart';
import '../../services/firebase_sync_service.dart';
import '../../services/license/license_service.dart';
import '../dialogs.dart';
import '../theme.dart';
import '../widgets/app_update_dialog.dart';
import '../widgets/common_widgets.dart';
import '../widgets/tiko_tutorial.dart';

class ArticlesPricePage extends StatelessWidget {
  const ArticlesPricePage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final categories = controller.allArticleCategories;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const SectionTitle('Articles & Prix'),
        ConfigSection(
          title: 'Catégories',
          trailing: OutlinedButton.icon(
            onPressed: () => showCategoryDialog(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('Ajouter'),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  ActionChip(
                    avatar: const Icon(Icons.edit, size: 16),
                    label: Text(category),
                    onPressed: () => showCategoryDialog(context, controller,
                        category: category),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ConfigSection(
          title: 'Articles & prix',
          trailing: Wrap(
            spacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () =>
                    showAssociationConsumptionDialog(context, controller),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('Sortie asso'),
              ),
              OutlinedButton.icon(
                onPressed: () => showArticleDialog(context, controller),
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final category in categories) ...[
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 5),
                  color: AppColors.bg,
                  child: Text(
                    category,
                    style: const TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: 2),
                  ),
                ),
                for (final article
                    in controller.articles.where((a) => a.category == category))
                  ConfigArticleRow(
                    article: article,
                    onEdit: () => showArticleDialog(context, controller,
                        article: article),
                    onDelete: () async {
                      if (await confirm(
                          context, 'Supprimer ${article.name} ?')) {
                        try {
                          await controller.deleteArticle(article);
                        } catch (error) {
                          if (context.mounted) {
                            final message = '$error'
                                .replaceFirst('Bad state: ', '')
                                .replaceFirst('Exception: ', '');
                            snack(context, message);
                          }
                        }
                      }
                    },
                  ),
                if (!controller.articles.any((a) => a.category == category))
                  const Padding(
                    padding: EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Text('Aucun article dans cette catégorie',
                        style: TextStyle(color: AppColors.muted)),
                  ),
              ],
              if (controller.articles.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Aucun article configuré')),
            ],
          ),
        ),
      ],
    );
  }
}

class ConfigPage extends StatefulWidget {
  const ConfigPage({
    required this.controller,
    required this.licenseService,
    required this.updateResult,
    required this.checkingUpdate,
    required this.onCheckUpdate,
    super.key,
  });

  final AppController controller;
  final LicenseService licenseService;
  final AppUpdateResult? updateResult;
  final bool checkingUpdate;
  final VoidCallback onCheckUpdate;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  AppController get controller => widget.controller;
  LicenseService get licenseService => widget.licenseService;
  AppUpdateResult? get updateResult => widget.updateResult;
  bool get checkingUpdate => widget.checkingUpdate;
  VoidCallback get onCheckUpdate => widget.onCheckUpdate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 0, 12, 0),
          child: SectionTitle('Configuration'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Material(
            color: AppColors.surface,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.muted,
              indicator: const BoxDecoration(color: AppColors.surface2),
              tabs: const [
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.tune, title: 'Personnalisation'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.system_update, title: 'Mises à jour'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.cloud_sync, title: 'Synchronisation'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.event_available, title: 'HelloAsso'),
                ),
                Tab(
                  child:
                      _ConfigTabLabel(icon: Icons.backup, title: 'Sauvegarde'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.account_circle, title: 'Compte'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.warning_amber, title: 'Remise à zéro'),
                ),
                Tab(
                  child: _ConfigTabLabel(
                      icon: Icons.info_outline, title: 'À propos'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _ConfigTabBody(children: _buildPersonalizationSections(context)),
              _ConfigTabBody(
                children: [
                  const SectionTitle('Mises à jour'),
                  _buildUpdateSection(context),
                ],
              ),
              _ConfigTabBody(children: _buildFirebaseSections(context)),
              _ConfigTabBody(
                children: [
                  const SectionTitle('HelloAsso'),
                  _buildHelloAssoSection(context),
                ],
              ),
              _ConfigTabBody(
                children: [
                  const SectionTitle('Sauvegarde & restauration'),
                  _buildExportSection(context),
                  const SizedBox(height: 8),
                  _buildRestoreSection(context),
                ],
              ),
              _ConfigTabBody(children: _buildAccountSections(context)),
              _ConfigTabBody(children: _buildResetSections(context)),
              _ConfigTabBody(children: _buildAboutSections()),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPersonalizationSections(BuildContext context) {
    return [
      const SectionTitle('Personnalisation'),
      ConfigSection(
        title: 'Identité',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _AppIconPreview(controller: controller),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nom de l’association',
                        style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(controller.associationName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _editAssociationName(context),
                    icon: const Icon(Icons.edit),
                    label: const Text('Renommer'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () => _pickAppIcon(context),
                    icon: const Icon(Icons.image),
                    label: const Text('Choisir image'),
                  ),
                  if (controller.appIconPath.isNotEmpty)
                    IconButton.outlined(
                      tooltip: 'Retirer l’image',
                      onPressed: () => controller.setAppIconPath(''),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      ConfigSection(
        title: 'Couleur primaire',
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final color in _themeColorPresets)
                _ThemeColorSwatch(
                  color: color,
                  selected:
                      controller.primaryColor.toARGB32() == color.toARGB32(),
                  onTap: () => controller.setPrimaryColor(color),
                ),
              OutlinedButton.icon(
                onPressed: () => _editPrimaryColor(context),
                icon: const Icon(Icons.palette_outlined),
                label: const Text('Personnalisée'),
              ),
              OutlinedButton.icon(
                onPressed: () => controller.setPrimaryColor(AppColors.accent),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Réinitialiser'),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      ConfigSection(
        title: 'Onglets affichés',
        child: Column(
          children: [
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.meals,
              icon: Icons.restaurant,
              title: 'Repas',
              disabled: !controller.mealsEnabled,
            ),
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.players,
              icon: Icons.groups,
              title: 'Participants',
            ),
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.cash,
              icon: Icons.payments,
              title: 'Caisse',
            ),
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.stats,
              icon: Icons.trending_up,
              title: 'Stats',
            ),
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.bilan,
              icon: Icons.bar_chart,
              title: 'Bilan',
            ),
            _MainTabSwitch(
              controller: controller,
              id: AppTabIds.articles,
              icon: Icons.inventory_2,
              title: 'Articles',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ConfigSection(
        title: 'Modules',
        child: SwitchListTile(
          secondary: const Icon(Icons.restaurant_menu),
          title: const Text('Activer les repas'),
          subtitle: const Text('Masque le module et la catégorie REPAS'),
          value: controller.mealsEnabled,
          onChanged: controller.setMealsEnabled,
        ),
      ),
    ];
  }

  Future<void> _editPrimaryColor(BuildContext context) async {
    final value = await showDialog<Color>(
      context: context,
      builder: (context) =>
          _PrimaryColorPickerDialog(initialColor: controller.primaryColor),
    );
    if (value != null) {
      await Future<void>.delayed(kThemeAnimationDuration);
      if (!context.mounted) return;
      await controller.setPrimaryColor(value);
    }
  }

  Future<void> _editAssociationName(BuildContext context) async {
    var draftName = controller.associationName;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom de l’association'),
        content: TextFormField(
          initialValue: draftName,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom affiché'),
          textInputAction: TextInputAction.done,
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(context, draftName),
              child: const Text('Valider')),
        ],
      ),
    );
    if (value != null) {
      await Future<void>.delayed(kThemeAnimationDuration);
      if (!context.mounted) return;
      await controller.setAssociationName(value);
    }
  }

  Future<void> _pickAppIcon(BuildContext context) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    final selectedPath = result?.files.single.path;
    if (selectedPath == null || selectedPath.trim().isEmpty) return;
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final iconDirectory =
          Directory(path.join(supportDirectory.path, 'Tilly', 'branding'));
      await iconDirectory.create(recursive: true);
      final extension = path.extension(selectedPath).toLowerCase();
      final target = path.join(iconDirectory.path,
          'app-icon${extension.isEmpty ? '.png' : extension}');
      await File(selectedPath).copy(target);
      await controller.setAppIconPath(target);
    } catch (error) {
      if (context.mounted) snack(context, 'Image impossible à enregistrer');
    }
  }

  Widget _buildUpdateSection(BuildContext context) {
    final update = updateResult?.update;
    return ConfigActionZone(
      borderColor: update != null
          ? AppColors.warn
          : updateResult?.accessDenied == true
              ? AppColors.danger
              : AppColors.accent2,
      title: _updateStatusTitle(),
      description: _updateStatusDescription(),
      action: Wrap(
        spacing: 8,
        children: [
          if (update != null)
            FilledButton.tonalIcon(
              onPressed: () => showAppUpdateDialog(
                context,
                update: update,
                controller: controller,
                authToken: licenseService.authToken,
              ),
              icon: const Icon(Icons.system_update),
              label: const Text('Mettre à jour'),
            ),
          OutlinedButton.icon(
            onPressed: checkingUpdate ? null : onCheckUpdate,
            icon: checkingUpdate
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: const Text('Vérifier'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildFirebaseSections(BuildContext context) {
    final configured = controller.firebaseSettings.isConfigured;
    final connected = controller.firebaseAvailable;
    return [
      const SectionTitle('Synchronisation'),
      ConfigActionZone(
        borderColor: connected
            ? AppColors.accent
            : configured
                ? AppColors.accent2
                : AppColors.warn,
        title: connected
            ? 'Synchronisation active'
            : FirebaseBootstrap.initialized
                ? 'Connexion du compte requise'
                : configured
                    ? 'Configuration à corriger'
                    : 'Synchronisation désactivée',
        description: connected
            ? '${controller.firebaseUserLabel} · Projet ${controller.firebaseSettings.projectId}${controller.lastSyncedAt == null ? '' : ' · ${dateLabel(controller.lastSyncedAt!)} ${timeLabel(controller.lastSyncedAt!)}'}'
            : FirebaseBootstrap.initialized
                ? 'Le projet ${controller.firebaseSettings.projectId} est prêt. Connecte le compte utilisateur pour terminer.'
                : configured
                    ? (FirebaseBootstrap.error ??
                        'La configuration Firebase doit être corrigée.')
                    : 'Colle la configuration du projet puis connecte le compte utilisateur dans un seul parcours.',
        action: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!connected)
              FilledButton.icon(
                onPressed: controller.syncing
                    ? null
                    : () => showFirebaseSetupDialog(context, controller,
                        editProject: !FirebaseBootstrap.initialized),
                icon: const Icon(Icons.cloud_done),
                label: Text(FirebaseBootstrap.initialized
                    ? 'Se connecter'
                    : 'Configurer'),
              ),
            TikoHelpButton(
              tooltip: 'Tiko explique Firebase',
              onPressed: () => showFirebaseHelpDialog(context),
            ),
            if (connected)
              FilledButton.tonalIcon(
                onPressed:
                    controller.syncing ? null : () => _syncFirebase(context),
                icon: controller.syncing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Synchroniser'),
              ),
            if (configured)
              IconButton.outlined(
                tooltip: 'Changer de projet Firebase',
                onPressed: controller.syncing
                    ? null
                    : () => showFirebaseSetupDialog(context, controller,
                        editProject: true),
                icon: const Icon(Icons.settings),
              ),
            if (connected)
              IconButton.outlined(
                tooltip: 'Déconnecter le compte',
                onPressed: () async {
                  await controller.disconnectFirebase();
                  if (context.mounted) snack(context, 'Firebase déconnecté');
                },
                icon: const Icon(Icons.logout),
              ),
            if (configured)
              IconButton.outlined(
                tooltip: 'Supprimer la configuration Firebase',
                onPressed: controller.syncing
                    ? null
                    : () async {
                        if (!await confirm(context,
                            'Supprimer la configuration Firebase de cet appareil ?')) {
                          return;
                        }
                        await controller.resetFirebaseSettings();
                        if (context.mounted) {
                          snack(context, 'Configuration Firebase supprimée');
                        }
                      },
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildHelloAssoSection(BuildContext context) {
    return ConfigActionZone(
      borderColor: controller.helloAssoSettings.isConfigured
          ? AppColors.accent
          : AppColors.warn,
      title: controller.helloAssoSettings.isConfigured
          ? 'Connexion configurée'
          : 'Connexion non configurée',
      description: controller.helloAssoSettings.isConfigured
          ? '${controller.helloAssoSettings.organizationSlug} · ${controller.helloAssoSettings.environment == 'sandbox' ? 'Sandbox' : 'Production'}'
          : 'Renseigne les clés API pour importer les événements et les participants inscrits.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: () => showHelloAssoSettingsDialog(context, controller),
            icon: const Icon(Icons.settings),
            label: const Text('Configurer'),
          ),
          TikoHelpButton(
            tooltip: 'Tiko explique HelloAsso',
            onPressed: () => showHelloAssoHelpDialog(context,
                mealsEnabled: controller.mealsEnabled),
          ),
          FilledButton.tonalIcon(
            onPressed: controller.helloAssoSettings.isConfigured
                ? () async {
                    try {
                      await controller.testHelloAssoConnection();
                      if (context.mounted) {
                        snack(context, 'Connexion HelloAsso OK');
                      }
                    } catch (error) {
                      if (context.mounted) {
                        snack(context, helloAssoConnectionFailedMessage);
                      }
                    }
                  }
                : null,
            icon: const Icon(Icons.cloud_sync),
            label: const Text('Tester'),
          ),
        ],
      ),
    );
  }

  Widget _buildExportSection(BuildContext context) {
    return ConfigActionZone(
      borderColor: AppColors.accent2,
      title: 'Exporter mes données',
      description:
          'Enregistre un fichier .tilly dans Downloads avec toutes les sessions, participants, ventes, articles, stocks, repas et fonds de caisse. La configuration (synchronisation, HelloAsso, personnalisation) n\'est pas incluse.',
      action: FilledButton.tonalIcon(
        onPressed: () => copyBackup(context, controller),
        icon: const Icon(Icons.download),
        label: const Text('Exporter'),
      ),
    );
  }

  Widget _buildRestoreSection(BuildContext context) {
    return ConfigActionZone(
      borderColor: AppColors.accent2,
      title: 'Restaurer depuis un fichier',
      description:
          'Importe un fichier .tilly après création automatique d\'une copie locale de sécurité. La configuration de cet appareil reste inchangée.',
      action: OutlinedButton.icon(
        onPressed: () => importBackupFromFile(context, controller),
        icon: const Icon(Icons.upload_file),
        label: const Text('Restaurer'),
      ),
    );
  }

  List<Widget> _buildResetSections(BuildContext context) {
    return [
      const SectionTitle('Remise à zéro'),
      ConfigActionZone(
        borderColor: AppColors.danger,
        title: 'Reset ventes',
        description:
            'Efface les ventes. Participants, articles et stock actuel sont conservés.',
        action: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () async {
            if (await confirm(context, 'Effacer toutes les ventes ?')) {
              await controller.resetSales();
            }
          },
          child: const Text('Reset ventes'),
        ),
      ),
      const SizedBox(height: 8),
      ConfigActionZone(
        borderColor: AppColors.danger,
        title: 'Reset complet',
        description:
            'Efface sessions, participants, ventes, repas, articles, stocks et comptages. Les catégories par défaut restent disponibles.',
        action: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () async {
            if (await confirm(context,
                'Tout effacer et repartir sur une caisse vide ? Cette action est définitive.')) {
              await controller.resetAll();
            }
          },
          child: const Text('Reset complet'),
        ),
      ),
      const SizedBox(height: 8),
      ConfigActionZone(
        borderColor: AppColors.danger,
        title: 'Supprimer session courante',
        description:
            'Efface l\'événement actif avec ses ventes, participants présents et comptages. La session la plus récente restante devient active.',
        action: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () async {
            final name =
                controller.activeSession?.name ?? 'la session courante';
            if (await confirm(
                context, 'Supprimer "$name" ? Cette action est définitive.')) {
              await controller.deleteCurrentSession();
              if (context.mounted) snack(context, 'Session supprimée');
            }
          },
          child: const Text('Supprimer session'),
        ),
      ),
      const SizedBox(height: 8),
      ConfigActionZone(
        borderColor: AppColors.danger,
        title: 'Reset stock',
        description: 'Remet tous les stocks à zéro.',
        action: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: () async {
            if (await confirm(context, 'Remettre tous les stocks à zéro ?')) {
              await controller.resetStock();
            }
          },
          child: const Text('Reset stock'),
        ),
      ),
    ];
  }

  List<Widget> _buildAccountSections(BuildContext context) {
    final email = licenseService.userEmail;
    final connected = email != null && email.isNotEmpty;
    return [
      const SectionTitle('Compte'),
      ConfigSection(
        title: 'Compte Tilly',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading:
                  Icon(Icons.account_circle, color: context.primaryAccent),
              title: Text(
                  connected ? email : 'Aucun compte connecté'),
              subtitle: Text(licenseService.getStateMessage()),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: connected ? () => _logout(context) : null,
                  icon: const Icon(Icons.logout),
                  label: const Text('Se déconnecter'),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const TacticalCard(
        borderColor: AppColors.warn,
        child: Text(
          'Pour retirer cet appareil de votre compte, utilisez '
          'tilly.orceus.fr.',
          style: TextStyle(color: AppColors.muted, height: 1.4),
        ),
      ),
    ];
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await confirm(
      context,
      'Se déconnecter de ce compte ? Tu pourras te reconnecter avec un autre compte.',
    );
    if (!confirmed || !context.mounted) return;
    await licenseService.logout();
  }

  List<Widget> _buildAboutSections() {
    return [
      const SectionTitle('À propos'),
      ConfigSection(
        title: 'Application',
        child: Column(
          children: [
            _AboutInfoRow(
              icon: Icons.local_offer_outlined,
              label: 'Version',
              value: appBuildVersion,
            ),
            const Divider(height: 1, color: AppColors.border),
            const _AboutInfoRow(
              icon: Icons.code,
              label: 'Développé par',
              value: 'Kaalister',
            ),
            const Divider(height: 1, color: AppColors.border),
            const _AboutInfoRow(
              icon: Icons.lightbulb_outline,
              label: "À partir de l'idée originale de",
              value: 'Joël Jean',
            ),
            const Divider(height: 1, color: AppColors.border),
            const _AboutInfoRow(
              icon: Icons.verified_user_outlined,
              label: 'Certification',
              value: 'Aucune certification',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      const TacticalCard(
        borderColor: AppColors.warn,
        child: Text(
          "Cette application est fournie comme outil d'aide au suivi et son utilisation, l'exactitude des données saisies, les contrôles de caisse, les déclarations, les obligations comptables, fiscales ou légales, ainsi que toute décision prise à partir des informations affichées, relèvent exclusivement de la responsabilité de l'utilisateur.",
          style: TextStyle(color: AppColors.muted, height: 1.4),
        ),
      ),
    ];
  }

  String _updateStatusTitle() {
    if (!updateCheckEnabled) return 'Mode développement';
    if (!AppUpdateService.supportedPlatform) return 'Plateforme non suivie';
    if (checkingUpdate && updateResult == null) return 'Vérification en cours';
    if (updateResult?.requiresUpdate == true) return 'Mise à jour disponible';
    if (updateResult?.accessDenied == true) return 'Mise à jour non incluse';
    if (updateResult?.error != null) return 'Vérification impossible';
    return 'Application à jour';
  }

  Future<void> _syncFirebase(BuildContext context) async {
    var result = await controller.syncNow();
    if (result.action == FirebaseSyncAction.remoteNewer && context.mounted) {
      final ok = await confirm(context,
          'Firebase contient des donnees plus recentes. Remplacer les donnees locales apres creation d une copie de securite ?');
      if (!ok) return;
      final recoveryFile = await saveRecoveryBackup(controller, 'firebase');
      result = await controller.syncNow(allowRemotePull: true);
      if (context.mounted && result.action == FirebaseSyncAction.pulled) {
        snack(context,
            '${result.message}. Copie precedente : ${recoveryFile['name']}');
        return;
      }
    }
    if (context.mounted) snack(context, result.message);
  }

  String _updateStatusDescription() {
    if (!updateCheckEnabled) {
      return 'Le contrôle de mise à jour est actif en release ou avec DEV_UPDATE_CHECK=true. Version build : $appBuildVersion.';
    }
    if (!AppUpdateService.supportedPlatform) {
      return 'Le contrôle est prévu pour Android, Windows et macOS.';
    }
    final update = updateResult?.update;
    if (update != null) {
      final size = update.formattedSize;
      return 'Version $appBuildVersion installée, version ${update.latestVersion} disponible'
          '${size.isEmpty ? '' : ' ($size)'}. Téléchargement dans l\'application, '
          'copie de sécurité automatique.';
    }
    if (updateResult?.error != null) {
      return '${updateResult!.error} Version installée : $appBuildVersion.';
    }
    final latest = updateResult?.latestVersion;
    return latest == null
        ? 'Version installée : $appBuildVersion.'
        : 'Version installée : $appBuildVersion. Version accessible : $latest.';
  }
}

class _ConfigTabBody extends StatefulWidget {
  const _ConfigTabBody({required this.children});

  final List<Widget> children;

  @override
  State<_ConfigTabBody> createState() => _ConfigTabBodyState();
}

class _ConfigTabBodyState extends State<_ConfigTabBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: widget.children,
    );
  }
}

class _ConfigTabLabel extends StatelessWidget {
  const _ConfigTabLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(title),
      ],
    );
  }
}

class _AboutInfoRow extends StatelessWidget {
  const _AboutInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: context.primaryAccent),
      title: Text(label),
      subtitle: Text(
        value,
        style: const TextStyle(
          color: AppColors.text,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _AppIconPreview extends StatelessWidget {
  const _AppIconPreview({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final iconPath = controller.appIconPath;
    final hasIcon = iconPath.isNotEmpty && File(iconPath).existsSync();
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasIcon
          ? Image.file(
              File(iconPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.bolt, color: context.primaryAccent, size: 34),
            )
          : Icon(Icons.bolt, color: context.primaryAccent, size: 34),
    );
  }
}

class _MainTabSwitch extends StatelessWidget {
  const _MainTabSwitch({
    required this.controller,
    required this.id,
    required this.icon,
    required this.title,
    this.disabled = false,
  });

  final AppController controller;
  final String id;
  final IconData icon;
  final String title;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: disabled ? const Text('Module désactivé') : null,
      value: !disabled && controller.isMainTabVisible(id),
      onChanged:
          disabled ? null : (value) => controller.setMainTabVisible(id, value),
    );
  }
}

const _themeColorPresets = <Color>[
  AppColors.accent,
  AppColors.accent2,
  Color(0xFFFFD33D),
  Color(0xFFFF6B35),
  Color(0xFFE83F6F),
  Color(0xFF9B5DE5),
  Color(0xFF00F5D4),
  Color(0xFF4CAF50),
];

class _PrimaryColorPickerDialog extends StatefulWidget {
  const _PrimaryColorPickerDialog({required this.initialColor});

  final Color initialColor;

  @override
  State<_PrimaryColorPickerDialog> createState() =>
      _PrimaryColorPickerDialogState();
}

class _PrimaryColorPickerDialogState extends State<_PrimaryColorPickerDialog> {
  late Color _draftColor;

  Color get _color => _draftColor.withAlpha(0xFF);

  @override
  void initState() {
    super.initState();
    _draftColor = widget.initialColor.withAlpha(0xFF);
  }

  @override
  Widget build(BuildContext context) {
    final previewTextColor =
        _color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    return AlertDialog(
      title: const Text('Couleur primaire'),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _hexColor(_color),
                  style: TextStyle(
                    color: previewTextColor,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ColorPicker(
                pickerColor: _color,
                onColorChanged: (color) =>
                    setState(() => _draftColor = color.withAlpha(0xFF)),
                paletteType: PaletteType.hsvWithHue,
                enableAlpha: false,
                labelTypes: const [],
                displayThumbColor: true,
                portraitOnly: true,
                colorPickerWidth: 280,
                pickerAreaHeightPercent: 0.62,
                pickerAreaBorderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final color in _themeColorPresets)
                    _ThemeColorSwatch(
                      color: color,
                      selected: _color.toARGB32() == color.toARGB32(),
                      onTap: () => setState(() => _draftColor = color),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        OutlinedButton.icon(
          onPressed: () => setState(() => _draftColor = AppColors.accent),
          icon: const Icon(Icons.restart_alt),
          label: const Text('Réinitialiser'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _color),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}

class _ThemeColorSwatch extends StatelessWidget {
  const _ThemeColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final checkColor =
        color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
    return Tooltip(
      message: _hexColor(color),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.text : AppColors.border,
              width: selected ? 3 : 1,
            ),
          ),
          child:
              selected ? Icon(Icons.check, color: checkColor, size: 22) : null,
        ),
      ),
    );
  }
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0xFFFFFF;
  return '#${value.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.controller, super.key});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final activeId = controller.activeSession?.id;
    final sessions = [...controller.sessions]
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SectionTitle(
          'Historique des événements',
          trailing: FilledButton.icon(
            onPressed: () => showCreateSessionDialog(context, controller),
            icon: const Icon(Icons.add),
            label: const Text('Nouvelle session'),
          ),
        ),
        if (sessions.isEmpty)
          const TacticalCard(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aucune session enregistrée'),
              ),
            ),
          ),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TacticalCard(
              borderColor: session.id == activeId
                  ? context.primaryAccent
                  : AppColors.border,
              child: Builder(
                builder: (context) {
                  final sessionSales = controller.salesForSession(session.id);
                  final total = sessionSales.fold<double>(
                      0, (total, sale) => total + sale.total);
                  return ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 4),
                    leading: Icon(
                      session.id == activeId
                          ? Icons.radio_button_checked
                          : Icons.history,
                      color: session.id == activeId
                          ? context.primaryAccent
                          : AppColors.muted,
                    ),
                    title: Row(
                      children: [
                        Expanded(
                            child: Text(session.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900))),
                        if (session.id == activeId)
                          const Chip(
                              label: Text('Active'),
                              visualDensity: VisualDensity.compact),
                      ],
                    ),
                    subtitle: Text(
                        '${dateLabel(session.eventDate)} · ${sessionSales.length} vente(s) · ${money(total)}'),
                    trailing: session.id == activeId
                        ? null
                        : OutlinedButton.icon(
                            onPressed: () async {
                              await controller.switchSession(session.id);
                              if (context.mounted) {
                                snack(context, 'Session chargée');
                              }
                            },
                            icon: const Icon(Icons.login),
                            label: const Text('Ouvrir'),
                          ),
                    children: [
                      if (sessionSales.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: () =>
                                  exportBilanPdf(context, controller, session),
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text('Bilan PDF'),
                            ),
                          ),
                        ),
                      if (session.helloassoEventUrl.isNotEmpty)
                        ListTile(
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading:
                              const Icon(Icons.link, color: AppColors.accent2),
                          title: Text(session.helloassoEventName.isEmpty
                              ? 'Événement HelloAsso'
                              : session.helloassoEventName),
                          subtitle: Text(session.helloassoEventUrl,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      if (sessionSales.isEmpty)
                        const Padding(
                          padding: EdgeInsets.fromLTRB(8, 0, 8, 10),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text('Aucune vente sur cette session',
                                style: TextStyle(color: AppColors.muted)),
                          ),
                        )
                      else
                        for (final sale in sessionSales.reversed)
                          ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            title: Text(
                              sale.items
                                  .map((item) =>
                                      '${item.quantity}x ${item.name}')
                                  .join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                                '${sale.playerName} · ${timeLabel(sale.createdAt)} · ${sale.payment}${sale.donation > 0 ? ' · don ${money(sale.donation)}' : ''}'),
                            trailing: Text(money(sale.total),
                                style: TextStyle(
                                    color: context.primaryAccent,
                                    fontWeight: FontWeight.w900)),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class ConfigSection extends StatelessWidget {
  const ConfigSection(
      {required this.title, required this.child, this.trailing, super.key});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            color: AppColors.surface2,
            child: Row(
              children: [
                Expanded(
                    child: Text(title.toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2,
                            fontSize: 12))),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class ConfigArticleRow extends StatelessWidget {
  const ConfigArticleRow(
      {required this.article,
      required this.onEdit,
      required this.onDelete,
      super.key});

  final Article article;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final stockColor = article.isLocation
        ? AppColors.muted
        : article.stock == 0 && article.threshold > 0
            ? AppColors.danger
            : article.stock <= article.threshold && article.threshold > 0
                ? AppColors.warn
                : AppColors.text;
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final nameWidth = wide
            ? max(260.0, constraints.maxWidth * 0.34)
            : constraints.maxWidth - 20;
        final categoryWidth = wide
            ? max(190.0, constraints.maxWidth * 0.24)
            : constraints.maxWidth - 20;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.border))),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConfigCell(
                  width: 48,
                  onTap: onEdit,
                  child: Center(
                      child: Text(article.icon,
                          style: const TextStyle(fontSize: 18)))),
              ConfigCell(
                width: nameWidth,
                onTap: onEdit,
                child: Text(article.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              ConfigCell(
                width: categoryWidth,
                onTap: onEdit,
                child: Text(article.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        const TextStyle(color: AppColors.muted, fontSize: 12)),
              ),
              ConfigCell(
                width: 76,
                onTap: onEdit,
                child: Text(article.isLocation ? 'LOC' : 'STD',
                    style: const TextStyle(
                        color: AppColors.accent2,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
              ConfigCell(
                width: 82,
                onTap: onEdit,
                alignment: Alignment.centerRight,
                child: Text(article.price > 0 ? money(article.price) : 'Libre',
                    style: const TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
              ConfigCell(
                width: 82,
                onTap: onEdit,
                alignment: Alignment.centerRight,
                child: Text(
                    article.memberPrice > 0 ? money(article.memberPrice) : '-',
                    style: const TextStyle(
                        color: AppColors.accent2,
                        fontWeight: FontWeight.w900,
                        fontSize: 12)),
              ),
              ConfigCell(
                width: 64,
                onTap: onEdit,
                alignment: Alignment.center,
                child: Text(article.isLocation ? '∞' : '${article.stock}',
                    style: TextStyle(
                        color: stockColor, fontWeight: FontWeight.w900)),
              ),
              SizedBox.square(
                dimension: 34,
                child: OutlinedButton(
                  onPressed: onDelete,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                  ),
                  child: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ConfigCell extends StatelessWidget {
  const ConfigCell(
      {required this.width,
      required this.child,
      this.onTap,
      this.alignment = Alignment.centerLeft,
      super.key});

  final double width;
  final Widget child;
  final VoidCallback? onTap;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 34,
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(4),
        child: InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onTap,
          child: Container(
            alignment: alignment,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(4)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ConfigActionZone extends StatelessWidget {
  const ConfigActionZone(
      {required this.borderColor,
      required this.title,
      required this.description,
      required this.action,
      super.key});

  final Color borderColor;
  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 620;
        final descriptionText = Text(
          description,
          style: const TextStyle(
              color: AppColors.muted, fontSize: 13, height: 1.35),
        );
        final textColumn = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 3),
            descriptionText,
          ],
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(10),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    textColumn,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerLeft, child: action),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: textColumn),
                    const SizedBox(width: 12),
                    Flexible(
                      flex: 0,
                      child: Align(
                          alignment: Alignment.centerRight, child: action),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
