import 'dart:io';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../controllers/app_controller.dart';
import '../domain/models.dart';
import '../platform/backup_and_links.dart';
import '../services/app_update_service.dart';
import '../services/license/license_service.dart';
import 'pages/activation_page.dart';
import 'pages/bilan_page.dart';
import 'pages/license_blocked_page.dart';
import 'pages/cash_analysis_page.dart';
import 'pages/configuration_page.dart';
import 'pages/kpi_page.dart';
import 'pages/meals_page.dart';
import 'pages/players_page.dart';
import 'pages/sales_page.dart';
import 'theme.dart';
import 'widgets/app_update_dialog.dart';
import 'widgets/common_widgets.dart';
import 'widgets/license_banner.dart';
import 'widgets/tiko_tutorial.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    required this.controller,
    required this.licenseService,
    super.key,
  });

  final AppController controller;
  final LicenseService licenseService;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppUpdateResult? updateResult;
  bool checkingUpdate = false;
  bool _tutorialTourQueued = false;
  bool _tutorialTourRunning = false;
  bool _welcomeDialogShown = false;
  bool _forceActivation = false;
  final Set<String> _queuedTutorialTabs = {};
  String? _tutorialTabAwaitingReentry;

  AppController get controller => widget.controller;
  LicenseService get licenseService => widget.licenseService;

  @override
  void initState() {
    super.initState();
    controller.load();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (!updateCheckEnabled || !AppUpdateService.supportedPlatform) {
      return;
    }
    setState(() => checkingUpdate = true);
    final result =
        await AppUpdateService.check(authToken: licenseService.authToken);
    if (!mounted) return;
    setState(() {
      updateResult = result;
      checkingUpdate = false;
    });
  }

  Future<void> _reconnectLicense() async {
    final result = await licenseService.validateOnline();
    if (!mounted) return;
    final needsLogin = licenseService.authToken == null ||
        (!licenseService.isLicensed && !licenseService.isReadOnly);
    if (needsLogin) setState(() => _forceActivation = true);
    if (result.error != null) snack(context, result.error!);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([controller, licenseService]),
      builder: (context, _) {
        if (controller.loading) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (licenseService.isBlocked) {
          return LicenseBlockedPage(
            key: ValueKey(licenseService.currentState),
            licenseService: licenseService,
          );
        }
        final readOnly = licenseService.isReadOnly;
        if (licenseService.isLicensed) _forceActivation = false;
        if (!licenseService.isLicensed && (!readOnly || _forceActivation)) {
          return ActivationPage(
            key: ValueKey(licenseService.currentState),
            licenseService: licenseService,
            controller: controller,
          );
        }
        controller.readOnly = readOnly;
        final allDestinations = _shellDestinations(controller,
            licenseService: licenseService,
            updateResult: updateResult,
            checkingUpdate: checkingUpdate,
            onCheckUpdate: _checkForUpdate);
        final destinations = allDestinations
            .where((destination) => _isShellDestinationVisible(
                controller, destination))
            .toList();
        var selectedIndex = destinations.indexWhere(
            (destination) => destination.tabIndex == controller.tab);
        if (selectedIndex < 0) {
          selectedIndex = 0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) controller.setTab(destinations.first.tabIndex);
          });
        }
        final selectedDestination = destinations[selectedIndex];
        final stackIndex = allDestinations.indexOf(selectedDestination);
        _queueAutomaticTutorial(destinations, selectedDestination.id);
        return _buildLayout(allDestinations, destinations, stackIndex,
            selectedIndex, selectedDestination);
      },
    );
  }

  Widget _buildLayout(
      List<_ShellDestination> allDestinations,
      List<_ShellDestination> destinations,
      int stackIndex,
      int selectedIndex,
      _ShellDestination selectedDestination) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tablet = constraints.maxWidth >= 900;
        final body = IndexedStack(
          index: stackIndex,
          children: [
            for (final destination in allDestinations) destination.page,
          ],
        );
        final readOnly = licenseService.isReadOnly;
        final pageBody =
            readOnly ? AbsorbPointer(child: body) : body;
        final Widget scaffoldBody;
        if (tablet) {
          scaffoldBody = _buildTabletBody(
              destinations, selectedIndex, pageBody, context);
        } else {
          scaffoldBody = _buildMobileBody(pageBody, context);
        }
        final Widget? bottomNavBar;
        if (tablet) {
          bottomNavBar = null;
        } else {
          bottomNavBar = _CompactBottomNavigation(
            destinations: destinations,
            selectedIndex: selectedIndex,
            onDestinationSelected: controller.setTab,
          );
        }
        return Scaffold(
          appBar: _buildAppBar(context, selectedDestination),
          body: scaffoldBody,
          bottomNavigationBar: bottomNavBar,
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, _ShellDestination selectedDestination) {
    return AppBar(
      backgroundColor: AppColors.surface,
      titleSpacing: 12,
      title: Row(
        children: [
          _AppTitleIcon(controller: controller),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              controller.associationName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
          ),
          const SizedBox(width: 8),
          ActionChip(
            avatar: const Icon(Icons.flag, size: 16),
            label: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                  controller.session.isEmpty
                      ? 'ÉVÉNEMENT'
                      : controller.session,
                  overflow: TextOverflow.ellipsis),
            ),
            onPressed:
                licenseService.isReadOnly ? null : () => _editSession(context),
          ),
        ],
      ),
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(2),
        child: _PrimaryAccentBar(),
      ),
      actions: [
        TikoTutorialButton(
          onPressed: () => _showPageTutorial(selectedDestination.id),
        ),
      ],
    );
  }

  Widget _buildTabletBody(
      List<_ShellDestination> destinations,
      int selectedIndex,
      Widget body,
      BuildContext context) {
    return Column(
      children: [
        _buildLicenseBanner(context),
        _buildUpdateBanner(context),
        Expanded(
          child: Row(
            children: [
              NavigationRail(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) =>
                    controller.setTab(destinations[index].tabIndex),
                backgroundColor: AppColors.surface,
                indicatorColor: context.primaryAccent,
                labelType: NavigationRailLabelType.all,
                destinations: [
                  for (final destination in destinations)
                    NavigationRailDestination(
                        icon: Icon(destination.icon),
                        label: Text(destination.label)),
                ],
              ),
              const VerticalDivider(
                  width: 1, color: AppColors.border),
              Expanded(child: body),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileBody(Widget body, BuildContext context) {
    return Column(
      children: [
        _buildLicenseBanner(context),
        _buildUpdateBanner(context),
        Expanded(child: body),
      ],
    );
  }

  Widget _buildUpdateBanner(BuildContext context) {
    final update = updateResult?.update;
    if (update == null) return const SizedBox.shrink();
    return Material(
      color: AppColors.surface2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.system_update,
                color: AppColors.accent, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Mise à jour ${update.latestVersion} disponible. '
                'Tes données et ta connexion sont conservées.',
                style: const TextStyle(fontSize: 13, height: 1.3),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () => showAppUpdateDialog(
                context,
                update: update,
                controller: controller,
                authToken: licenseService.authToken,
              ),
              child: const Text('Mettre à jour'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseBanner(BuildContext context) {
    return LicenseBanner(
      licenseService: licenseService,
      onReconnect: _reconnectLicense,
      onExport: () => copyBackup(context, controller),
    );
  }

  void _queueAutomaticTutorial(
    List<_ShellDestination> destinations,
    String tabId,
  ) {
    if (_tutorialTourQueued || _tutorialTourRunning) return;
    if (!controller.tutorialWelcomeSeen && !_welcomeDialogShown) {
      _tutorialTourQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _runFirstLaunchTutorialTour(destinations);
      });
      return;
    }
    if (_tutorialTabAwaitingReentry == tabId) return;
    if (_tutorialTabAwaitingReentry != null) {
      _tutorialTabAwaitingReentry = null;
    }
    if (controller.tutorialPagesSeen.contains(tabId) ||
        _queuedTutorialTabs.contains(tabId)) {
      return;
    }
    _queuedTutorialTabs.add(tabId);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await controller.markTutorialPageSeen(tabId);
      if (!mounted) return;
      await _showPageTutorial(tabId);
      _queuedTutorialTabs.remove(tabId);
    });
  }

  Future<void> _runFirstLaunchTutorialTour(
      List<_ShellDestination> destinations) async {
    if (_tutorialTourRunning) return;
    _tutorialTourRunning = true;
    _welcomeDialogShown = true;

    final wantsTour = await _showTikoDialog(tikoWelcomeTutorial(),
        primaryActionLabel: 'C\'est parti');
    if (!mounted) return;
    await controller.markTutorialWelcomeSeen();
    if (!wantsTour || !mounted) {
      setState(() {
        _tutorialTourRunning = false;
        _tutorialTourQueued = false;
      });
      return;
    }

    final tourDestinations = _firstLaunchTourDestinations(destinations);
    for (final destination in tourDestinations) {
      if (!mounted) return;
      if (controller.tab != destination.tabIndex) {
        controller.setTab(destination.tabIndex);
        await Future<void>.delayed(kThemeAnimationDuration);
      }
      if (!mounted) return;
      final completed = await _showTikoDialog(
        tikoOnboardingForTab(destination.id),
        primaryActionLabel: destination.id == AppTabIds.articles
            ? 'Créer mon premier article'
            : 'Continuer',
      );
      if (!completed || !mounted) break;
    }

    if (mounted) {
      setState(() {
        if (controller.tab == 7) {
          _tutorialTabAwaitingReentry = AppTabIds.articles;
        }
        _tutorialTourRunning = false;
        _tutorialTourQueued = false;
      });
    }
  }

  List<_ShellDestination> _firstLaunchTourDestinations(
      List<_ShellDestination> destinations) {
    final articleDestinations = destinations
        .where((destination) => destination.id == AppTabIds.articles)
        .toList();
    return [
      for (final destination in destinations)
        if (destination.id != AppTabIds.articles) destination,
      ...articleDestinations,
    ];
  }

  Future<bool> _showPageTutorial(String tabId) {
    return _showTikoDialog(tikoTutorialForTab(tabId));
  }

  Future<bool> _showTikoDialog(
    TikoTutorialContent content, {
    String primaryActionLabel = 'Compris',
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => TikoTutorialDialog(
            content: content,
            primaryActionLabel: primaryActionLabel,
          ),
        ) ??
        false;
  }

  Future<void> _editSession(BuildContext context) async {
    var draftName = controller.session;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nom de l\'événement'),
        content: TextFormField(
          initialValue: draftName,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Ex: Fête de l\'association'),
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
      await controller.setSession(value);
    }
  }
}

class _CompactBottomNavigation extends StatelessWidget {
  const _CompactBottomNavigation({
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final List<_ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const _primaryDestinationIds = {
    AppTabIds.sales,
    AppTabIds.meals,
    AppTabIds.players,
    AppTabIds.cash,
  };

  @override
  Widget build(BuildContext context) {
    final primaryDestinations = destinations
        .where((destination) => _primaryDestinationIds.contains(destination.id))
        .toList();
    final secondaryDestinations = destinations
        .where(
            (destination) => !_primaryDestinationIds.contains(destination.id))
        .toList();
    final selectedDestination = destinations[selectedIndex];
    final primarySelectedIndex = primaryDestinations
        .indexWhere((destination) => destination.id == selectedDestination.id);
    final moreSelected =
        primarySelectedIndex < 0 && secondaryDestinations.isNotEmpty;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: NavigationBar(
        height: 72,
        selectedIndex:
            moreSelected ? primaryDestinations.length : primarySelectedIndex,
        onDestinationSelected: (index) {
          if (index < primaryDestinations.length) {
            onDestinationSelected(primaryDestinations[index].tabIndex);
            return;
          }
          _showSecondaryDestinations(context, secondaryDestinations);
        },
        backgroundColor: AppColors.surface,
        indicatorColor: context.primaryAccent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: [
          for (final destination in primaryDestinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
              tooltip: destination.label,
            ),
          if (secondaryDestinations.isNotEmpty)
            const NavigationDestination(
              icon: Icon(Icons.grid_view_rounded),
              label: 'Plus',
              tooltip: 'Plus de rubriques',
            ),
        ],
      ),
    );
  }

  Future<void> _showSecondaryDestinations(
    BuildContext context,
    List<_ShellDestination> secondaryDestinations,
  ) async {
    final selectedTab = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'PLUS DE RUBRIQUES',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.6,
                    ),
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 64,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: secondaryDestinations.length,
                  itemBuilder: (context, index) {
                    final destination = secondaryDestinations[index];
                    final selected =
                        destinations[selectedIndex].id == destination.id;
                    return InkWell(
                      borderRadius:
                          BorderRadius.circular(VisualIdentity.radius),
                      onTap: () =>
                          Navigator.pop(sheetContext, destination.tabIndex),
                      child: TacticalCard(
                        borderColor:
                            selected ? context.primaryAccent : AppColors.border,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Icon(
                              destination.icon,
                              color: selected
                                  ? context.primaryAccent
                                  : AppColors.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                destination.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: context.primaryAccent,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selectedTab != null) onDestinationSelected(selectedTab);
  }
}

class _PrimaryAccentBar extends StatelessWidget {
  const _PrimaryAccentBar();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.primaryAccent,
      child: const SizedBox(height: 2, width: double.infinity),
    );
  }
}

class _ShellDestination {
  const _ShellDestination({
    required this.id,
    required this.tabIndex,
    required this.icon,
    required this.label,
    required this.page,
  });

  final String id;
  final int tabIndex;
  final IconData icon;
  final String label;
  final Widget page;
}

bool _isShellDestinationVisible(
  AppController controller,
  _ShellDestination destination,
) {
  if (destination.id == AppTabIds.meals && !controller.mealsEnabled) {
    return false;
  }
  if (AppTabIds.configurable.contains(destination.id)) {
    return controller.isMainTabVisible(destination.id);
  }
  return true;
}

List<_ShellDestination> _shellDestinations(
  AppController controller, {
  required LicenseService licenseService,
  required AppUpdateResult? updateResult,
  required bool checkingUpdate,
  required VoidCallback onCheckUpdate,
}) {
  return [
    _ShellDestination(
      id: AppTabIds.sales,
      tabIndex: 0,
      icon: Icons.point_of_sale,
      label: 'Vente',
      page: CaissePage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.meals,
      tabIndex: 1,
      icon: Icons.restaurant,
      label: 'Repas',
      page: MealsPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.players,
      tabIndex: 2,
      icon: Icons.groups,
      label: 'Participants',
      page: PlayersPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.cash,
      tabIndex: 3,
      icon: Icons.payments,
      label: 'Caisse',
      page: CashAnalysisPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.stats,
      tabIndex: 4,
      icon: Icons.trending_up,
      label: 'Stats',
      page: KpiPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.bilan,
      tabIndex: 5,
      icon: Icons.bar_chart,
      label: 'Bilan',
      page: BilanPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.history,
      tabIndex: 6,
      icon: Icons.history,
      label: 'Historique',
      page: HistoryPage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.articles,
      tabIndex: 7,
      icon: Icons.inventory_2,
      label: 'Articles',
      page: ArticlesPricePage(controller: controller),
    ),
    _ShellDestination(
      id: AppTabIds.config,
      tabIndex: 8,
      icon: Icons.settings,
      label: 'Config',
      page: ConfigPage(
        controller: controller,
        licenseService: licenseService,
        updateResult: updateResult,
        checkingUpdate: checkingUpdate,
        onCheckUpdate: onCheckUpdate,
      ),
    ),
  ];
}

class _AppTitleIcon extends StatelessWidget {
  const _AppTitleIcon({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final iconPath = controller.appIconPath;
    if (iconPath.isNotEmpty && File(iconPath).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          File(iconPath),
          width: 28,
          height: 28,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.bolt, color: context.primaryAccent),
        ),
      );
    }
    return Icon(Icons.bolt, color: context.primaryAccent);
  }
}
