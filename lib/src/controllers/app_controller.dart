import 'dart:math';

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../data/local_database.dart';
import '../data/persistable_app_state.dart';
import '../domain/models.dart';
import '../services/firebase_bootstrap.dart';
import '../services/firebase_monitoring_service.dart';
import '../services/demo_data_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/hello_asso_import_service.dart';
import '../services/meal_service.dart';
import '../services/secure_settings_service.dart';
import '../services/stock_service.dart';
import '../services/tutorial_store.dart';
import '../utils/iterable_extensions.dart';

class AppController extends ChangeNotifier implements PersistableAppState {
  AppController({
    LocalDatabase? database,
    SecureSettingsService? secureSettings,
    TutorialStore? tutorialStore,
  })  : _database = database ?? LocalDatabase(),
        _secureSettings = secureSettings ?? SecureSettingsService(),
        _tutorialStore = tutorialStore ?? TutorialStore();

  final LocalDatabase _database;
  final FirebaseSyncService _syncService = FirebaseSyncService();
  final SecureSettingsService _secureSettings;
  final TutorialStore _tutorialStore;
  final HelloAssoImportService _helloAssoImport = HelloAssoImportService();
  final MealService _mealService = MealService();
  final StockService _stockService = StockService();

  bool loading = true;
  bool syncing = false;
  bool readOnly = false;
  String syncStatus = FirebaseBootstrap.initialized
      ? 'Firebase prêt'
      : (FirebaseBootstrap.error ?? 'Firebase non configuré');
  DateTime? lastSyncedAt;
  int tab = 0;
  @override
  SessionRecord? activeSession;
  @override
  AppSettings appSettings = const AppSettings();
  List<SessionRecord> sessions = [];
  String categoryFilter = 'TOUS';
  bool forceMemberTariff = false;
  double donation = 0;
  String? selectedPlayerId;
  HelloAssoSettings helloAssoSettings = const HelloAssoSettings();
  FirebaseSettings firebaseSettings =
      FirebaseBootstrap.settings ?? const FirebaseSettings();
  @override
  List<Player> allPlayers = [];
  @override
  List<Player> players = [];
  @override
  List<Article> articles = defaultArticles();
  @override
  List<String> articleCategories = defaultArticleCategories();
  @override
  List<Sale> sales = [];
  Map<String, List<Sale>> salesBySession = {};
  @override
  List<MealOrder> meals = [];
  List<StockMovement> stockMovements = [];
  List<CartItem> cart = [];
  @override
  List<StockMovement> pendingStockMovements = [];
  @override
  Map<String, int> cashStart = {};
  @override
  Map<String, int> cashEnd = {};
  bool tutorialWelcomeSeen = false;
  Set<String> tutorialPagesSeen = {};

  String get session => activeSession?.name ?? '';
  String get associationName => appSettings.associationName;
  String get appIconPath => appSettings.appIconPath;
  Color get primaryColor => appSettings.primaryColor;
  bool get mealsEnabled => appSettings.mealsEnabled;
  String get firebaseUserLabel =>
      FirebaseBootstrap.currentUser?.email ??
      FirebaseBootstrap.currentUser?.uid ??
      '';
  bool get firebaseAvailable => _syncService.isAvailable;
  Player? get selectedPlayer =>
      players.where((p) => p.id == selectedPlayerId).firstOrNull;
  bool get memberTariff =>
      forceMemberTariff || (selectedPlayer?.isMember ?? false);
  double get cartArticlesTotal =>
      cart.fold(0, (total, item) => total + item.price * item.quantity);
  double get cartTotal => cartArticlesTotal + donation;
  int get cartCount => cart.fold(0, (total, item) => total + item.quantity);
  bool get hasPendingPayment => cart.isNotEmpty || donation > 0;
  bool get canCheckout =>
      selectedPlayer != null && hasPendingPayment && cartStockShortages.isEmpty;
  List<StockShortage> get cartStockShortages =>
      _stockService.shortages(_stockService.cartRequirements(cart, articles));
List<String> get activeArticleCategories => articleCategories
      .where((category) => category != 'REPAS')
      .toList();
  List<String> get managedArticleCategories =>
      mealsEnabled ? articleCategories : activeArticleCategories;
  bool isProtectedArticleCategory(String category) =>
      normalizedCategoryName(category) == 'REPAS';
List<String> get categories => ['TOUS', ...activeArticleCategories];
List<String> get mealCategories => ['REPAS'];
List<String> get allArticleCategories => articleCategories;
  List<Article> get activeArticles =>
      articles.where((article) => article.category != 'REPAS').toList();

  List<Article> get trackedArticles =>
      articles.where((article) => article.type == 'standard' && article.threshold > 0).toList();
  List<Sale> get activeSales =>
      sales.where((sale) => sale.isActive).toList(growable: false);
  List<Article> get visibleArticles => categoryFilter == 'TOUS'
      ? activeArticles
      : activeArticles.where((a) => a.category == categoryFilter).toList();
  List<Article> get mealArticles => mealsEnabled
      ? articles.where((article) => article.category == 'REPAS').toList()
      : const <Article>[];
  List<Article> get drinkArticles =>
      articles.where((article) => article.category == 'BOISSONS').toList();
  List<Article> get snackArticles => articles
      .where((article) =>
          article.category == 'SNACS' || article.category == 'SNACKING')
      .toList();
  bool isMainTabVisible(String id) => appSettings.isMainTabVisible(id);

  // Local dataset identifier: one SQLite file per licence account, so two
  // associations using the same device never share their data.
  String? _dataScope;
  String? get dataScope => _dataScope;
  Future<void> _scopeTask = Future<void>.value();

  /// Sets the dataset without loading it (used before the first [load]).
  /// Later calls switch and reload the dataset (login / logout).
  Future<void> switchDataScope(String? scope) {
    if (_dataScope == scope && _database.isScopedTo(scope)) {
      return Future<void>.value();
    }
    _dataScope = scope;
    if (loading) return Future<void>.value();
    _scopeTask = _scopeTask.then((_) async {
      await _database.adoptLegacyDataIfNeeded(scope);
      await _database.setUserScope(scope);
      await _loadLocalState();
      notifyListeners();
    });
    return _scopeTask;
  }

  Future<void> load() async {
    try {
      await _database.adoptLegacyDataIfNeeded(_dataScope);
      await _database.setUserScope(_dataScope);
      await _loadLocalState();
      if (await _seedDemoDataIfNeeded()) {
        await _loadLocalState();
      }
      FirebaseMonitoringService.setContextKey('current_tab', _tabId(tab));
      FirebaseMonitoringService.logAction('app_loaded', context: {
        'tab': _tabId(tab),
        'firebase_sync': _syncService.isAvailable ? 'connected' : 'offline',
        'meals': mealsEnabled ? 'enabled' : 'disabled',
      });
    } catch (_) {
      articles = defaultArticles();
      articleCategories = defaultArticleCategories();
      syncStatus = 'Chargement local en mode dégradé';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> _loadLocalState() async {
    sessions = await _database.loadSessions();
    var activeSessionId = await _database.loadActiveSessionId();
    if (sessions.isEmpty) {
      final created = await _database.createSession('Nouvel événement');
      sessions = [created];
      activeSessionId = created.id;
    }
    activeSession =
        sessions.where((s) => s.id == activeSessionId).firstOrNull ??
            sessions.first;
    if (activeSessionId != activeSession!.id) {
      await _database.setActiveSessionId(activeSession!.id);
    }
    final storedHelloAssoSettings = await _database.loadHelloAssoSettings();
    appSettings = await _database.loadAppSettings();
    await _loadTutorialState();
    helloAssoSettings = await _secureSettings
        .loadHelloAssoSettings(storedHelloAssoSettings, scope: _dataScope);
    if (storedHelloAssoSettings.clientSecret.trim().isNotEmpty) {
      await _database.saveHelloAssoSettings(
          storedHelloAssoSettings.withoutSecret(),
          markUpdated: false);
    }
    allPlayers = await _database.loadAllPlayers();
    players = await _database.loadPlayers(activeSession!.id);
    final storedArticles = await _database.loadArticles();
    articles = storedArticles.isEmpty ? defaultArticles() : storedArticles;
    final storedCategories = await _database.loadArticleCategories();
    _setArticleCategories(storedCategories.isEmpty
        ? defaultArticleCategories()
        : storedCategories);
    sales = await _database.loadSales(activeSession!.id);
    meals = await _database.loadMeals(activeSession!.id);
    stockMovements = await _database.loadStockMovements(activeSession!.id);
    await refreshSessionSales();
    cashStart = await _database.loadCash(activeSession!.id, 'start');
    cashEnd = await _database.loadCash(activeSession!.id, 'end');
    cart.clear();
    donation = 0;
    selectedPlayerId = null;
    forceMemberTariff = false;
    _normalizeCategoryFilter();
    if (storedArticles.isEmpty) {
      await persist(markUpdated: false);
    }
  }

  Future<bool> _seedDemoDataIfNeeded() async {
    if (!demoDataEnabled) return false;
    if (!await _database.hasOnlyBootstrapData()) {
      if (await _database.hasBusinessActivity()) return false;
      await _database.resetBusinessData();
    }
    final dataset = buildDemoDataset();
    articles = dataset.articles;
    _setArticleCategories(dataset.categories);
    allPlayers = dataset.players;
    for (final day in dataset.days) {
      activeSession = day.session;
      players = day.players;
      sales = day.sales;
      meals = day.meals;
      cashStart = day.cashStart;
      cashEnd = day.cashEnd;
      pendingStockMovements.addAll(day.stockMovements);
      await persist(markUpdated: false);
    }
    return true;
  }

  Future<void> _loadTutorialState() async {
    final override = devTutorialOverride;
    if (override == 'off') {
      tutorialWelcomeSeen = true;
      tutorialPagesSeen = AppTabIds.all.toSet();
      return;
    }
    if (override == 'on') {
      tutorialWelcomeSeen = false;
      tutorialPagesSeen = {};
      return;
    }
    tutorialWelcomeSeen = await _tutorialStore.loadWelcomeSeen() ?? false;
    tutorialPagesSeen = await _tutorialStore.loadPagesSeen() ?? const {};
  }

  Future<void> persist({bool markUpdated = true}) async {
    await _database.saveAll(this, markUpdated: markUpdated);
    _cacheActiveSessionSales();
    if (markUpdated && _syncService.isAvailable) {
      syncStatus = 'Modifications locales non synchronisees';
    }
  }

  Future<void> markTutorialWelcomeSeen() async {
    if (tutorialWelcomeSeen) return;
    tutorialWelcomeSeen = true;
    notifyListeners();
    await _tutorialStore.saveWelcomeSeen();
  }

  Future<void> markTutorialPageSeen(String pageId) async {
    if (tutorialPagesSeen.contains(pageId)) return;
    tutorialPagesSeen = {...tutorialPagesSeen, pageId};
    notifyListeners();
    await _tutorialStore.savePagesSeen(tutorialPagesSeen);
  }

  Future<FirebaseSyncResult> syncNow({
    bool reloadAfterPull = true,
    bool allowRemotePull = false,
  }) async {
    FirebaseMonitoringService.logAction('firebase_sync_requested', context: {
      'tab': _tabId(tab),
      'allow_pull': allowRemotePull,
    });
    if (!_syncService.isAvailable) {
      final result = FirebaseSyncResult(FirebaseSyncAction.disabled,
          FirebaseBootstrap.error ?? 'Connexion Firebase requise');
      FirebaseMonitoringService.logAction('firebase_sync_unavailable',
          context: {'reason': result.action.name});
      _applySyncResult(result);
      notifyListeners();
      return result;
    }
    syncing = true;
    syncStatus = 'Synchronisation en cours';
    notifyListeners();
    try {
      final result =
          await _syncService.synchronize(_database, allowPull: allowRemotePull);
      FirebaseMonitoringService.logAction('firebase_sync_finished', context: {
        'action': result.action.name,
        'pulled': result.action == FirebaseSyncAction.pulled,
      });
      _applySyncResult(result);
      if (reloadAfterPull && result.action == FirebaseSyncAction.pulled) {
        sessions = await _database.loadSessions();
        final activeSessionId = await _database.loadActiveSessionId();
        activeSession =
            sessions.where((s) => s.id == activeSessionId).firstOrNull ??
                sessions.firstOrNull;
        allPlayers = await _database.loadAllPlayers();
        final storedArticles = await _database.loadArticles();
        articles = storedArticles.isEmpty ? defaultArticles() : storedArticles;
        final storedCategories = await _database.loadArticleCategories();
        _setArticleCategories(storedCategories.isEmpty
            ? defaultArticleCategories()
            : storedCategories);
        final storedHelloAssoSettings = await _database.loadHelloAssoSettings();
        helloAssoSettings = await _secureSettings
            .loadHelloAssoSettings(storedHelloAssoSettings, scope: _dataScope);
        await _loadActiveSessionState();
        await refreshSessionSales();
      }
      return result;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<FirebaseSyncResult> connectFirebaseUser() async {
    FirebaseMonitoringService.logAction('firebase_user_connect_requested',
        context: {'tab': _tabId(tab)});
    if (!FirebaseBootstrap.initialized) {
      final result = FirebaseSyncResult(FirebaseSyncAction.disabled,
          FirebaseBootstrap.error ?? 'Firebase non configuré');
      _applySyncResult(result);
      notifyListeners();
      return result;
    }
    final user = FirebaseBootstrap.currentUser;
    if (user == null) {
      const result = FirebaseSyncResult(
          FirebaseSyncAction.noUser, 'Connexion Firebase requise');
      _applySyncResult(result);
      notifyListeners();
      return result;
    }

    syncing = true;
    syncStatus = 'Chargement du compte Firebase';
    notifyListeners();

    try {
      // The Firebase account is only used as a sync backend for the current
      // licence dataset: it never changes the local data scope.
      var remoteExists = true;
      try {
        remoteExists = await _syncService.hasRemoteSnapshot();
      } catch (_) {
        remoteExists = true;
      }
      final result = FirebaseSyncResult(FirebaseSyncAction.unchanged,
          'Compte connecte. Utilise Synchroniser pour transferer les donnees.');
      FirebaseMonitoringService.logAction('firebase_user_connected',
          context: {'remote_exists': remoteExists});
      _applySyncResult(result);
      return result;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void _applySyncResult(FirebaseSyncResult result) {
    syncStatus = result.message;
    if (result.syncedAt != null) lastSyncedAt = result.syncedAt;
  }

  Future<void> disconnectFirebase() async {
    FirebaseMonitoringService.logAction('firebase_user_disconnect_requested',
        context: {'tab': _tabId(tab)});
    if (FirebaseBootstrap.initialized) {
      await FirebaseBootstrap.auth.signOut();
    }
    lastSyncedAt = null;
    syncStatus = 'Connexion Firebase requise';
    notifyListeners();
  }

  Future<void> saveFirebaseSettings(FirebaseSettings settings) async {
    FirebaseMonitoringService.logAction('firebase_settings_save_requested',
        context: {'configured': settings.isConfigured});
    if (!settings.isConfigured) {
      throw const FormatException('Les quatre champs obligatoires sont requis');
    }
    syncing = true;
    syncStatus = 'Configuration de Firebase';
    notifyListeners();
    try {
      await _secureSettings.saveFirebaseSettings(settings);
      await FirebaseBootstrap.reconfigure(settings);
      firebaseSettings = settings;
      if (!FirebaseBootstrap.initialized) {
        throw StateError(FirebaseBootstrap.error ??
            'Impossible d initialiser Firebase avec cette configuration');
      }
      FirebaseMonitoringService.logAction('firebase_settings_saved');
      syncStatus = 'Firebase configuré, connexion utilisateur requise';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> resetFirebaseSettings() async {
    FirebaseMonitoringService.logAction('firebase_settings_reset_requested',
        context: {'tab': _tabId(tab)});
    syncing = true;
    notifyListeners();
    try {
      await FirebaseBootstrap.reset();
      await _secureSettings.clearFirebaseSettings();
      firebaseSettings = const FirebaseSettings();
      lastSyncedAt = null;
      syncStatus = 'Firebase non configuré';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> refreshSessionSales() async {
    salesBySession = {
      for (final session in sessions)
        session.id: await _database.loadSales(session.id),
    };
    _cacheActiveSessionSales();
  }

  List<Sale> salesForSession(String sessionId) {
    final sessionSales = salesBySession[sessionId] ??
        (activeSession?.id == sessionId ? sales : const <Sale>[]);
    return sessionSales.where((sale) => sale.isActive).toList(growable: false);
  }

  void _cacheActiveSessionSales() {
    final sessionId = activeSession?.id;
    if (sessionId == null) return;
    salesBySession[sessionId] = List<Sale>.of(sales);
  }

  Future<void> importBackup(Map<String, dynamic> payload) async {
    FirebaseMonitoringService.logAction('backup_import_started',
        context: {'tab': _tabId(tab)});
    final version = (payload['version'] as num?)?.round();
    if (version != null && version >= 2 && payload['data'] is Map) {
      await _database.replaceFromExport(payload);
      await load();
      FirebaseMonitoringService.logAction('backup_import_finished',
          context: {'version': version, 'format': 'modern'});
      return;
    }
    final state =
        Map<String, dynamic>.from(payload['state'] as Map? ?? payload);
    final importedArticles = ((state['articles'] ?? []) as List)
        .map((entry) =>
            Article.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    if (importedArticles.isEmpty) {
      throw const FormatException('Aucun article trouvé dans la sauvegarde');
    }
    final importedSession = SessionRecord(
      id: makeId('session'),
      name: '${state['session'] ?? 'Événement importé'}',
      eventDate: DateTime.now(),
    );
    activeSession = importedSession;
    sessions = [importedSession];
    players = ((state['players'] ?? []) as List)
        .map(
            (entry) => Player.fromJson(Map<String, dynamic>.from(entry as Map)))
        .toList();
    allPlayers = [...players];
    articles = importedArticles;
    _setArticleCategories(((state['articleCategories'] as List?) ?? const [])
        .map((category) => '$category'));
    sales = ((state['sales'] ?? []) as List).map((entry) {
      final sale = Sale.fromJson(Map<String, dynamic>.from(entry as Map));
      return Sale(
        id: sale.id,
        playerId: sale.playerId,
        playerName: sale.playerName,
        playerType: sale.playerType,
        tariff: sale.tariff,
        items: sale.items,
        totalArticles: sale.totalArticles,
        donation: sale.donation,
        payment: sale.payment,
        session: importedSession.id,
        createdAt: sale.createdAt,
        status: sale.status,
        cancelledAt: sale.cancelledAt,
        cancellationReason: sale.cancellationReason,
      );
    }).toList();
    meals = [];
    stockMovements = [];
    salesBySession = {importedSession.id: List<Sale>.of(sales)};
    cashStart = _parseCashMap(state['cashStart']);
    cashEnd = _parseCashMap(state['cashEnd']);
    final importedAppSettings = state['appSettings'];
    if (importedAppSettings is Map) {
      appSettings =
          AppSettings.fromJson(Map<String, dynamic>.from(importedAppSettings));
    }
    cart.clear();
    donation = 0;
    selectedPlayerId = null;
    forceMemberTariff = false;
    _normalizeCategoryFilter();
    await persist();
    FirebaseMonitoringService.logAction('backup_import_finished',
        context: {'version': version ?? 'legacy', 'format': 'legacy'});
    notifyListeners();
  }

  Map<String, int> _parseCashMap(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        '${entry.key}': int.tryParse('${entry.value}') ?? 0,
    };
  }

  void _setArticleCategories(Iterable<String> storedCategories) {
    for (final article in articles) {
      final normalized = normalizedCategoryName(article.category);
      article.category = normalized.isEmpty ? 'DIVERS' : normalized;
    }
    final names = <String>{
      for (final category in storedCategories)
        if (normalizedCategoryName(category).isNotEmpty)
          normalizedCategoryName(category),
      for (final article in articles)
        if (normalizedCategoryName(article.category).isNotEmpty)
          normalizedCategoryName(article.category),
    }.toList()
      ..sort();
    articleCategories = names.isEmpty ? defaultArticleCategories() : names;
  }

  void setTab(int value) {
    if (tab == value) return;
    tab = value;
    final tabId = _tabId(value);
    FirebaseMonitoringService.setContextKey('current_tab', tabId);
    FirebaseMonitoringService.logAction('tab_opened', context: {'tab': tabId});
    notifyListeners();
  }

  String _tabId(int value) {
    switch (value) {
      case 0:
        return AppTabIds.sales;
      case 1:
        return AppTabIds.meals;
      case 2:
        return AppTabIds.players;
      case 3:
        return AppTabIds.cash;
      case 4:
        return AppTabIds.stats;
      case 5:
        return AppTabIds.bilan;
      case 6:
        return AppTabIds.history;
      case 7:
        return AppTabIds.articles;
      case 8:
        return AppTabIds.config;
    }
    return 'unknown_$value';
  }

  Future<void> setAssociationName(String value) async {
    final name = value.trim().isEmpty ? 'TILLY' : value.trim();
    appSettings = appSettings.copyWith(associationName: name);
    notifyListeners();
    await persist();
  }

  Future<void> setAppIconPath(String value) async {
    appSettings = appSettings.copyWith(appIconPath: value.trim());
    notifyListeners();
    await persist();
  }

  Future<void> setPrimaryColor(Color value) async {
    appSettings = appSettings.copyWith(primaryColorValue: value.toARGB32());
    notifyListeners();
    await persist();
  }

  Future<void> setMainTabVisible(String id, bool visible) async {
    if (!AppTabIds.configurable.contains(id)) return;
    final visibility = <String, bool>{...appSettings.mainTabVisibility};
    visibility[id] = visible;
    appSettings = appSettings.copyWith(mainTabVisibility: visibility);
    notifyListeners();
    await persist();
  }

  Future<void> setMealsEnabled(bool enabled) async {
    appSettings = appSettings.copyWith(mealsEnabled: enabled);
    _normalizeCategoryFilter();
    if (!enabled && tab == 1) tab = 0;
    notifyListeners();
    await persist();
  }

  Future<void> setSession(String value) async {
    final current = activeSession;
    if (current == null) return;
    current.name = value.trim().isEmpty ? 'Événement' : value.trim();
    sessions = sessions.map((s) => s.id == current.id ? current : s).toList();
    notifyListeners();
    await persist();
  }

  Future<void> saveHelloAssoSettings(HelloAssoSettings settings) async {
    helloAssoSettings = settings;
    notifyListeners();
    await _secureSettings.saveHelloAssoSecret(settings.clientSecret,
        scope: _dataScope);
    await _database.saveHelloAssoSettings(settings.withoutSecret());
    if (_syncService.isAvailable) {
      syncStatus = 'Modifications locales non synchronisees';
      notifyListeners();
    }
  }

  Future<void> testHelloAssoConnection() async {
    if (!helloAssoSettings.isConfigured) {
      throw Exception('Configuration HelloAsso incomplète');
    }
    await _helloAssoImport.fetchEvents(helloAssoSettings);
  }

  Future<List<HelloAssoEvent>> fetchHelloAssoEvents() async {
    FirebaseMonitoringService.logAction('helloasso_events_fetch_started',
        context: {'tab': _tabId(tab)});
    try {
      final events = await _helloAssoImport.fetchEvents(helloAssoSettings);
      FirebaseMonitoringService.logAction('helloasso_events_fetch_finished',
          context: {'count': events.length});
      return events;
    } catch (error, stackTrace) {
      FirebaseMonitoringService.logAction('helloasso_events_fetch_failed',
          context: {'error': error.runtimeType});
      await FirebaseMonitoringService.recordError(error, stackTrace);
      rethrow;
    }
  }

  Future<void> createSession(String name,
      {HelloAssoEvent? helloassoEvent}) async {
    FirebaseMonitoringService.logAction('session_create_started', context: {
      'tab': _tabId(tab),
      'helloasso': helloassoEvent != null,
    });
    await persist();
    final registrants = helloassoEvent == null
        ? const <HelloAssoRegistrant>[]
        : await _helloAssoImport.fetchRegistrants(
            helloAssoSettings, helloassoEvent);
    final syncedAt = helloassoEvent == null ? null : DateTime.now();
    final created = await _database.createSession(
      name.trim().isEmpty ? (helloassoEvent?.name ?? 'Nouvel événement') : name,
      helloassoEvent: helloassoEvent,
      helloassoSyncedAt: syncedAt,
    );
    sessions = await _database.loadSessions();
    activeSession = created;
    players = [];
    meals = [];
    for (final registrant in registrants) {
      final player = _helloAssoImport.attachRegistrant(
        registrant: registrant,
        allPlayers: allPlayers,
        sessionPlayers: players,
      );
      if (mealsEnabled && registrant.hasMeal) {
        final mealArticle = mealArticles.firstOrNull;
        if (mealArticle != null) {
          meals.add(_mealService.helloAssoMeal(
            player: player,
            registrant: registrant,
            mealArticle: mealArticle,
            drinkArticle: drinkArticles.firstOrNull,
            snackArticle: snackArticles.firstOrNull,
          ));
        }
      }
    }
    sales = [];
    stockMovements = [];
    salesBySession[created.id] = [];
    cashStart = {};
    cashEnd = {};
    cart.clear();
    donation = 0;
    selectedPlayerId = null;
    forceMemberTariff = false;
    _normalizeCategoryFilter();
    notifyListeners();
    await persist();
    FirebaseMonitoringService.logAction('session_create_finished', context: {
      'helloasso': helloassoEvent != null,
      'registrants': registrants.length,
    });
  }

  Future<void> switchSession(String sessionId) async {
    await persist();
    await _database.setActiveSessionId(sessionId);
    sessions = await _database.loadSessions();
    activeSession = sessions.where((s) => s.id == sessionId).firstOrNull ??
        sessions.firstOrNull;
    await _loadActiveSessionState();
    notifyListeners();
  }

  Future<void> deleteCurrentSession() async {
    final sessionId = activeSession?.id;
    if (sessionId == null) return;
    await _database.deleteSession(sessionId);
    salesBySession.remove(sessionId);
    sessions = await _database.loadSessions();
    if (sessions.isEmpty) {
      final created = await _database.createSession('Nouvel événement');
      sessions = [created];
      activeSession = created;
    } else {
      activeSession = sessions.first;
      await _database.setActiveSessionId(activeSession!.id);
    }
    await _loadActiveSessionState();
    await _database.markLocalUpdated();
    if (_syncService.isAvailable) {
      syncStatus = 'Modifications locales non synchronisees';
    }
    notifyListeners();
  }

  Future<void> _loadActiveSessionState() async {
    if (activeSession == null) return;
    players = await _database.loadPlayers(activeSession!.id);
    sales = await _database.loadSales(activeSession!.id);
    meals = await _database.loadMeals(activeSession!.id);
    stockMovements = await _database.loadStockMovements(activeSession!.id);
    _cacheActiveSessionSales();
    cashStart = await _database.loadCash(activeSession!.id, 'start');
    cashEnd = await _database.loadCash(activeSession!.id, 'end');
    cart.clear();
    donation = 0;
    selectedPlayerId = null;
    forceMemberTariff = false;
    _normalizeCategoryFilter();
  }

  Future<void> addPlayer(
      {required String firstName,
      required String lastName,
      required String email,
      required String type}) async {
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = playerNameFromParts(cleanFirstName, cleanLastName,
        cleanEmail.isEmpty ? 'Participant' : cleanEmail);
    final existing = cleanEmail.isNotEmpty
        ? allPlayers
            .where((p) => p.email.trim().toLowerCase() == cleanEmail)
            .firstOrNull
        : allPlayers
            .where((p) => p.name.toLowerCase() == cleanName.toLowerCase())
            .firstOrNull;
    final player =
        existing ?? Player(id: makeId('player'), name: cleanName, type: type);
    player.name = cleanName;
    player.firstName = cleanFirstName;
    player.lastName = cleanLastName;
    player.email = cleanEmail;
    player.type = type;
    if (existing == null) allPlayers.add(player);
    if (!players.any((p) => p.id == player.id)) players.add(player);
    players.sort((a, b) => a.name.compareTo(b.name));
    allPlayers.sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    await persist();
  }

  Future<void> updatePlayer(Player player,
      {required String firstName,
      required String lastName,
      required String email,
      required String type}) async {
    player.firstName = firstName.trim();
    player.lastName = lastName.trim();
    player.email = email.trim().toLowerCase();
    player.name = playerNameFromParts(player.firstName, player.lastName,
        player.email.isEmpty ? player.name : player.email);
    player.type = type;
    final global = allPlayers.where((p) => p.id == player.id).firstOrNull;
    if (global != null) {
      global.name = player.name;
      global.firstName = player.firstName;
      global.lastName = player.lastName;
      global.email = player.email;
      global.type = player.type;
    }
    for (final sale in sales.where((s) => s.playerId == player.id)) {
      sale.playerName = player.name;
    }
    for (final meal in meals.where((order) => order.playerId == player.id)) {
      meal.playerName = player.name;
    }
    notifyListeners();
    await persist();
  }

  Future<void> removePlayer(Player player) async {
    players.removeWhere((p) => p.id == player.id);
    if (selectedPlayerId == player.id) selectedPlayerId = null;
    notifyListeners();
    await persist();
  }

  void selectPlayer(Player player) {
    selectedPlayerId = player.id;
    forceMemberTariff = false;
    for (final item in cart) {
      final article = articles.firstWhere((a) => a.id == item.articleId);
      item.price = article.priceFor(memberTariff);
    }
    notifyListeners();
  }

  void toggleMemberTariff() {
    forceMemberTariff = !forceMemberTariff;
    for (final item in cart) {
      final article = articles.firstWhere((a) => a.id == item.articleId);
      item.price = article.priceFor(memberTariff);
    }
    notifyListeners();
  }

  void setCategory(String category) {
    categoryFilter = category;
    _normalizeCategoryFilter();
    notifyListeners();
  }

  void _normalizeCategoryFilter() {
    if (categoryFilter != 'TOUS' && !categories.contains(categoryFilter)) {
      categoryFilter = 'TOUS';
    }
  }

  void addToCart(Article article) {
    if (selectedPlayerId == null) return;
    final price = article.priceFor(memberTariff);
    final existing = cart.where((i) => i.articleId == article.id).firstOrNull;
    if (existing == null) {
      cart.add(CartItem(articleId: article.id, quantity: 1, price: price));
    } else {
      existing.quantity += 1;
      existing.price = price;
    }
    notifyListeners();
  }

  void changeCartQuantity(String articleId, int delta) {
    final item = cart.where((i) => i.articleId == articleId).firstOrNull;
    if (item == null) return;
    item.quantity += delta;
    if (item.quantity <= 0) cart.remove(item);
    notifyListeners();
  }

  void clearCart() {
    cart.clear();
    donation = 0;
    notifyListeners();
  }

  void setDonation(double value) {
    donation = max(0, value);
    notifyListeners();
  }

  Future<void> checkout(String payment) async {
    final player = selectedPlayer;
    if (player == null || !hasPendingPayment) return;
    FirebaseMonitoringService.logAction('checkout_started', context: {
      'tab': _tabId(tab),
      'payment': payment,
      'cart_lines': cart.length,
      'has_donation': donation > 0,
    });
    final shortages = cartStockShortages;
    if (shortages.isNotEmpty) {
      FirebaseMonitoringService.logAction('checkout_blocked', context: {
        'reason': 'stock_shortage',
        'shortages': shortages.length,
      });
      throw StateError(
          'Stock insuffisant : ${shortages.map((item) => item.message).join(' ; ')}');
    }
    final saleItems = <SaleItem>[];
    for (final item in cart) {
      final article = articles.firstWhere((a) => a.id == item.articleId);
      saleItems.add(SaleItem(
        articleId: article.id,
        name: article.name,
        icon: article.icon,
        type: article.type,
        quantity: item.quantity,
        price: item.price,
        publicPrice: article.price,
        memberPrice: article.memberPrice,
      ));
    }
    final sale = Sale(
      id: makeId('sale'),
      playerId: player.id,
      playerName: player.name,
      playerType: player.type,
      tariff: memberTariff ? 'adherent' : 'public',
      items: saleItems,
      totalArticles: cartArticlesTotal,
      donation: donation,
      payment: payment,
      session: activeSession?.id ?? '',
      createdAt: DateTime.now(),
    );
    await _commitMutation(() {
      for (final entry
          in _stockService.cartRequirements(cart, articles).entries) {
        _applyStockDelta(
          entry.key,
          -entry.value,
          movementType: 'sale',
          saleId: sale.id,
          reason: 'Vente ${sale.id}',
        );
      }
      sales.add(sale);
      cart.clear();
      donation = 0;
    });
    FirebaseMonitoringService.logAction('checkout_finished', context: {
      'payment': payment,
      'items': saleItems.length,
    });
  }

  Future<void> createMeal({
    required Player player,
    required String source,
    required String status,
    required String mealArticleId,
    required String drinkArticleId,
    required String snackArticleId,
    required String formula,
    required List<String> options,
    required String note,
    String payment = '',
  }) async {
    if (!mealsEnabled) {
      throw StateError('Le module repas est désactivé');
    }
    final meal = _mealService.createMealOrder(
      player: player,
      source: source,
      status: status,
      mealArticleId: mealArticleId,
      drinkArticleId: drinkArticleId,
      snackArticleId: snackArticleId,
      formula: formula,
      options: options,
      note: note,
      payment: payment,
    );
    await _commitMutation(() {
      _applyMealStockTransition(null, meal);
      if (meal.isOnsite) {
        sales.add(_mealService.saleForMeal(meal, player, articles,
            sessionId: activeSession?.id ?? ''));
      }
      meals.add(meal);
    });
  }

  Future<void> updateMeal(MealOrder current, MealOrder updated) async {
    final index = meals.indexWhere((meal) => meal.id == current.id);
    if (index < 0) return;
    await _commitMutation(() {
      _applyMealStockTransition(meals[index], updated);
      meals[index] = updated;
      if (updated.isOnsite && updated.saleId.isNotEmpty) {
        final saleIndex = sales.indexWhere((sale) => sale.id == updated.saleId);
        final player =
            players.where((entry) => entry.id == updated.playerId).firstOrNull;
        if (saleIndex >= 0 && player != null) {
          sales[saleIndex] = _mealService.saleForMeal(updated, player, articles,
              sessionId: activeSession?.id ?? '',
              createdAt: sales[saleIndex].createdAt);
        }
      }
    });
  }

  Future<void> prepareMeal(MealOrder meal) async {
    if (meal.status != 'planned') return;
    await updateMeal(
        meal,
        meal.copyWith(
          status: 'prepared',
          preparedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
  }

  Future<void> serveMeal(MealOrder meal) async {
    if (meal.status == 'cancelled' || meal.status == 'served') return;
    final now = DateTime.now();
    await updateMeal(
        meal,
        meal.copyWith(
          status: 'served',
          preparedAt: meal.preparedAt ?? now,
          servedAt: now,
          updatedAt: now,
        ));
  }

  Future<void> unserveMeal(MealOrder meal) async {
    if (meal.status != 'served') return;
    await updateMeal(
        meal,
        meal.copyWith(
          status: 'prepared',
          servedAt: null,
          updatedAt: DateTime.now(),
        ));
  }

  Future<void> unprepareMeal(MealOrder meal) async {
    if (meal.status != 'prepared') return;
    await updateMeal(
        meal,
        meal.copyWith(
          status: 'planned',
          preparedAt: null,
          updatedAt: DateTime.now(),
        ));
  }

  Future<void> cancelMeal(MealOrder meal) async {
    final index = meals.indexWhere((entry) => entry.id == meal.id);
    if (index < 0) return;
    final current = meals[index];
    if (current.status == 'cancelled') return;
    final now = DateTime.now();
    final cancelled = current.copyWith(status: 'cancelled', updatedAt: now);
    await _commitMutation(() {
      _applyMealStockTransition(current, cancelled);
      meals[index] = cancelled;
      if (current.saleId.isNotEmpty) {
        _markSaleCancelled(
          current.saleId,
          cancelledAt: now,
          reason: 'Annulation du repas ${current.id}',
        );
      }
    });
  }

  void _applyMealStockTransition(MealOrder? previous, MealOrder next) {
    final movements = _mealService.stockTransition(
      previous,
      next,
      articles: articles,
      stockService: _stockService,
      sessionId: activeSession?.id,
    );
    pendingStockMovements.addAll(movements);
    stockMovements.addAll(movements);
  }

  void _applyStockDelta(
    Article article,
    int delta, {
    required String movementType,
    required String reason,
    String? saleId,
  }) {
    final movement = _stockService.applyDelta(
      article,
      delta,
      sessionId: activeSession?.id,
      movementType: movementType,
      reason: reason,
      saleId: saleId,
    );
    if (movement != null) {
      pendingStockMovements.add(movement);
      stockMovements.add(movement);
    }
  }

  Future<void> consumeStockForAssociation(
    Article article,
    int quantity, {
    String note = '',
  }) async {
    if (!article.tracksStock) {
      throw StateError('Cet article ne gere pas de stock consommable');
    }
    if (quantity <= 0) {
      throw StateError('La quantité doit être supérieure à zéro');
    }
    if (article.stock < quantity) {
      throw StateError(
          'Stock insuffisant : ${article.name} : $quantity requis, ${article.stock} disponible(s)');
    }
    final trimmedNote = note.trim();
    await _commitMutation(() {
      _applyStockDelta(
        article,
        -quantity,
        movementType: 'association',
        reason: trimmedNote.isEmpty
            ? 'Consommation association'
            : 'Consommation association : $trimmedNote',
      );
    });
  }

  void _restoreStock(Sale sale) {
    for (final entry
        in _stockService.saleRequirements(sale, articles).entries) {
      _applyStockDelta(
        entry.key,
        entry.value,
        movementType: 'cancellation',
        saleId: sale.id,
        reason: 'Annulation vente ${sale.id}',
      );
    }
  }

  Future<void> cancelSale(Sale sale, {String reason = ''}) async {
    if (!sale.isActive) return;
    final meal = meals.where((order) => order.saleId == sale.id).firstOrNull;
    if (meal != null) {
      await cancelMeal(meal);
      return;
    }
    final now = DateTime.now();
    await _commitMutation(() {
      _restoreStock(sale);
      _markSaleCancelled(
        sale.id,
        cancelledAt: now,
        reason: reason.trim().isEmpty ? 'Annulation manuelle' : reason.trim(),
      );
    });
  }

  void _markSaleCancelled(
    String saleId, {
    required DateTime cancelledAt,
    required String reason,
  }) {
    final index = sales.indexWhere((sale) => sale.id == saleId);
    if (index < 0 || !sales[index].isActive) return;
    sales[index] = sales[index].copyWith(
      status: 'cancelled',
      cancelledAt: cancelledAt,
      cancellationReason: reason,
    );
  }

  Future<void> upsertArticle(Article article, {Article? replacing}) async {
    final normalized = normalizedCategoryName(article.category);
    final category = normalized.isEmpty ? 'DIVERS' : normalized;
    article.category = category;
    if (article.isLocation) {
      article
        ..stock = 0
        ..threshold = 0
        ..bbAuto = 0
        ..gasAuto = 0;
    }
    await _commitMutation(() {
      if (!articleCategories.contains(category)) {
        articleCategories.add(category);
        articleCategories.sort();
      }
      if (replacing == null) {
        articles.add(article);
      } else {
        final desiredStock = article.stock;
        article.stock = replacing.stock;
        _applyStockDelta(
          article,
          desiredStock - replacing.stock,
          movementType: 'adjustment',
          reason: 'Modification manuelle du stock',
        );
        final index = articles.indexOf(replacing);
        articles[index] = article;
      }
    });
  }

  bool containsArticleCategory(String category, {String? except}) {
    final normalized = normalizedCategoryName(category);
    return articleCategories.any((existing) =>
        existing != except &&
        (normalizedCategoryName(existing) == normalized ||
            stableCategoryId(existing) == stableCategoryId(normalized)));
  }

  Future<void> addArticleCategory(String category) async {
    final normalized = normalizedCategoryName(category);
    if (normalized.isEmpty || containsArticleCategory(normalized)) return;
    articleCategories.add(normalized);
    articleCategories.sort();
    notifyListeners();
    await persist();
  }

  Future<void> renameArticleCategory(String previous, String category) async {
    final normalized = normalizedCategoryName(category);
    if (normalized.isEmpty ||
        isProtectedArticleCategory(previous) ||
        isProtectedArticleCategory(normalized) ||
        containsArticleCategory(normalized, except: previous)) {
      return;
    }
    final index = articleCategories.indexOf(previous);
    if (index < 0) return;
    articleCategories[index] = normalized;
    articleCategories.sort();
    for (final article in articles.where((a) => a.category == previous)) {
      article.category = normalized;
    }
    if (categoryFilter == previous) categoryFilter = normalized;
    notifyListeners();
    await persist();
  }

  Future<void> deleteArticle(Article article) async {
    final reference = _articleDeletionBlocker(article);
    if (reference != null) {
      throw StateError(
          'Impossible de supprimer ${article.name} : article utilisé dans $reference');
    }
    final storedReference = await _database.findArticleReference(article.id);
    if (storedReference != null) {
      throw StateError(
          'Impossible de supprimer ${article.name} : article utilisé dans $storedReference');
    }
    articles.remove(article);
    cart.removeWhere((item) => item.articleId == article.id);
    notifyListeners();
    await persist();
  }

  String? _articleDeletionBlocker(Article article) {
    final articleId = article.id;
    if (cart.any((item) => item.articleId == articleId)) {
      return 'le panier courant';
    }
    if (sales
        .any((sale) => sale.items.any((item) => item.articleId == articleId))) {
      return 'les ventes de la session';
    }
    if (salesBySession.values.any((sessionSales) => sessionSales.any(
        (sale) => sale.items.any((item) => item.articleId == articleId)))) {
      return 'l’historique des ventes';
    }
    if (meals.any((meal) =>
        meal.mealArticleId == articleId ||
        meal.drinkArticleId == articleId ||
        meal.snackArticleId == articleId)) {
      return 'les repas de la session';
    }
    if (stockMovements.any((movement) => movement.articleId == articleId)) {
      return 'les mouvements de stock';
    }
    return null;
  }

  Future<void> resetSales() async {
    final now = DateTime.now();
    await _commitMutation(() {
      for (var index = 0; index < sales.length; index++) {
        final sale = sales[index];
        if (!sale.isActive) continue;
        sales[index] = sale.copyWith(
          status: 'cancelled',
          cancelledAt: now,
          cancellationReason: 'Réinitialisation des ventes',
        );
      }
      for (final meal in meals) {
        meal.saleId = '';
      }
      cart.clear();
      donation = 0;
    });
  }

  Future<void> resetAll() async {
    final created = SessionRecord(
      id: makeId('session'),
      name: 'Nouvel événement',
      eventDate: DateTime.now(),
    );
    await _database.resetBusinessData();
    sessions = [created];
    activeSession = created;
    allPlayers.clear();
    players.clear();
    articles = defaultArticles();
    articleCategories = defaultArticleCategories();
    sales.clear();
    salesBySession = {created.id: []};
    meals.clear();
    stockMovements.clear();
    pendingStockMovements.clear();
    cashStart.clear();
    cashEnd.clear();
    cart.clear();
    donation = 0;
    selectedPlayerId = null;
    forceMemberTariff = false;
    categoryFilter = 'TOUS';
    notifyListeners();
    await persist();
  }

  Future<void> resetStock() async {
    await _commitMutation(() {
      for (final article in articles) {
        _applyStockDelta(
          article,
          -article.stock,
          movementType: 'adjustment',
          reason: 'Remise a zero du stock',
        );
      }
    });
  }

  Future<void> updateCash(String kind, double value, int quantity) async {
    final key = value.toString();
    final map = kind == 'start' ? cashStart : cashEnd;
    map[key] = max(0, quantity);
    notifyListeners();
    await persist();
  }

  @override
  double cashTotal(String kind) {
    final map = kind == 'start' ? cashStart : cashEnd;
    return denominations.fold(
        0, (total, d) => total + d * (map[d.toString()] ?? 0));
  }

  Map<String, double> paymentTotals() {
    final result = {'ESP': 0.0, 'PayPal': 0.0, 'SumUp': 0.0};
    for (final sale in activeSales) {
      result[sale.payment] = (result[sale.payment] ?? 0) + sale.total;
    }
    return result;
  }

  Future<void> _commitMutation(void Function() mutation) async {
    if (readOnly) {
      throw StateError(
          'Licence à vérifier : reconnecte-toi à Internet pour continuer.');
    }
    final snapshot = _AppMutationSnapshot.capture(this);
    try {
      mutation();
      await persist();
    } catch (_) {
      snapshot.restore(this);
      notifyListeners();
      rethrow;
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> fullBackupPayload(
      {bool includeConfiguration = false}) async {
    FirebaseMonitoringService.logAction('backup_export_started',
        context: {'tab': _tabId(tab)});
    await persist(markUpdated: false);
    final payload = await _database.exportAll(
        includeConfiguration: includeConfiguration);
    FirebaseMonitoringService.logAction('backup_export_finished');
    return payload;
  }
}

class _AppMutationSnapshot {
  _AppMutationSnapshot({
    required this.articles,
    required this.articleStocks,
    required this.articleCategories,
    required this.sales,
    required this.meals,
    required this.stockMovements,
    required this.pendingStockMovements,
    required this.cart,
    required this.donation,
  });

  factory _AppMutationSnapshot.capture(AppController controller) =>
      _AppMutationSnapshot(
        articles: List<Article>.of(controller.articles),
        articleStocks: {
          for (final article in controller.articles) article.id: article.stock,
        },
        articleCategories: List<String>.of(controller.articleCategories),
        sales: List<Sale>.of(controller.sales),
        meals: controller.meals.map(_copyMealOrder).toList(),
        stockMovements: List<StockMovement>.of(controller.stockMovements),
        pendingStockMovements:
            List<StockMovement>.of(controller.pendingStockMovements),
        cart: controller.cart
            .map((item) => CartItem(
                  articleId: item.articleId,
                  quantity: item.quantity,
                  price: item.price,
                ))
            .toList(),
        donation: controller.donation,
      );

  final List<Article> articles;
  final Map<String, int> articleStocks;
  final List<String> articleCategories;
  final List<Sale> sales;
  final List<MealOrder> meals;
  final List<StockMovement> stockMovements;
  final List<StockMovement> pendingStockMovements;
  final List<CartItem> cart;
  final double donation;

  void restore(AppController controller) {
    for (final article in articles) {
      final stock = articleStocks[article.id];
      if (stock != null) article.stock = stock;
    }
    controller
      ..articles = List<Article>.of(articles)
      ..articleCategories = List<String>.of(articleCategories)
      ..sales = List<Sale>.of(sales)
      ..meals = meals.map(_copyMealOrder).toList()
      ..stockMovements = List<StockMovement>.of(stockMovements)
      ..pendingStockMovements = List<StockMovement>.of(pendingStockMovements)
      ..cart = cart
          .map((item) => CartItem(
                articleId: item.articleId,
                quantity: item.quantity,
                price: item.price,
              ))
          .toList()
      ..donation = donation;
  }
}

MealOrder _copyMealOrder(MealOrder meal) => MealOrder(
      id: meal.id,
      playerId: meal.playerId,
      playerName: meal.playerName,
      playerType: meal.playerType,
      source: meal.source,
      status: meal.status,
      saleId: meal.saleId,
      payment: meal.payment,
      mealArticleId: meal.mealArticleId,
      drinkArticleId: meal.drinkArticleId,
      snackArticleId: meal.snackArticleId,
      formula: meal.formula,
      options: List<String>.of(meal.options),
      note: meal.note,
      createdAt: meal.createdAt,
      preparedAt: meal.preparedAt,
      servedAt: meal.servedAt,
      updatedAt: meal.updatedAt,
    );
