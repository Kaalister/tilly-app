import 'dart:convert';
import 'dart:io';

import 'package:tilly/tilly.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/testing.dart';
import 'package:tilly/src/config/app_config.dart';
import 'package:tilly/src/services/license/license_api.dart';
import 'package:tilly/src/services/license/license_models.dart';
import 'package:tilly/src/services/license/license_service.dart';
import 'package:tilly/src/services/license/license_store.dart';
import 'package:tilly/src/services/license/license_verifier.dart';
import 'package:tilly/src/services/license/machine_id.dart';
import 'package:tilly/src/ui/pages/activation_page.dart';
import 'package:tilly/src/ui/pages/license_blocked_page.dart';

class _MemoryAppController extends AppController {
  _MemoryAppController() {
    loading = false;
    activeSession = SessionRecord(
      id: 'session-test',
      name: 'Session test',
      eventDate: DateTime(2026, 7, 16),
    );
  }

  @override
  Future<void> setAssociationName(String value) async {
    appSettings = appSettings.copyWith(associationName: value.trim());
    notifyListeners();
  }

  @override
  Future<void> setPrimaryColor(Color value) async {
    appSettings = appSettings.copyWith(primaryColorValue: value.toARGB32());
    notifyListeners();
  }

  @override
  Future<void> setMainTabVisible(String id, bool visible) async {
    final visibility = <String, bool>{...appSettings.mainTabVisibility};
    visibility[id] = visible;
    appSettings = appSettings.copyWith(mainTabVisibility: visibility);
    notifyListeners();
  }

  @override
  Future<void> load() async {
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> markTutorialWelcomeSeen() async {
    tutorialWelcomeSeen = true;
    notifyListeners();
  }

  @override
  Future<void> markTutorialPageSeen(String pageId) async {
    tutorialPagesSeen = {...tutorialPagesSeen, pageId};
    notifyListeners();
  }

  @override
  Future<void> addPlayer({
    required String firstName,
    required String lastName,
    required String email,
    required String type,
  }) async {
    final cleanFirstName = firstName.trim();
    final cleanLastName = lastName.trim();
    final cleanEmail = email.trim().toLowerCase();
    final player = Player(
      id: 'player-${allPlayers.length + 1}',
      name: playerNameFromParts(cleanFirstName, cleanLastName,
          cleanEmail.isEmpty ? 'Participant' : cleanEmail),
      type: type,
      firstName: cleanFirstName,
      lastName: cleanLastName,
      email: cleanEmail,
    );
    allPlayers.add(player);
    players.add(player);
    notifyListeners();
  }

  @override
  Future<void> addArticleCategory(String category) async {
    final normalized = normalizedCategoryName(category);
    if (normalized.isEmpty || containsArticleCategory(normalized)) return;
    articleCategories.add(normalized);
    articleCategories.sort();
    notifyListeners();
  }

  @override
  Future<void> upsertArticle(Article article, {Article? replacing}) async {
    final category = normalizedCategoryName(article.category).isEmpty
        ? 'DIVERS'
        : normalizedCategoryName(article.category);
    article.category = category;
    if (!articleCategories.contains(category)) {
      articleCategories.add(category);
      articleCategories.sort();
    }
    if (replacing == null) {
      articles.add(article);
    } else {
      final index = articles.indexOf(replacing);
      if (index >= 0) articles[index] = article;
    }
    notifyListeners();
  }
}

class _MemoryTutorialStore extends TutorialStore {
  bool? welcome;
  Set<String>? pages;

  @override
  Future<bool?> loadWelcomeSeen() async => welcome;

  @override
  Future<void> saveWelcomeSeen() async => welcome = true;

  @override
  Future<Set<String>?> loadPagesSeen() async => pages;

  @override
  Future<void> savePagesSeen(Set<String> pageIds) async =>
      pages = {...pageIds};
}

class _FailingDatabase extends LocalDatabase {
  @override
  Future<void> saveAll(PersistableAppState state,
      {bool markUpdated = true}) async {
    throw StateError('Écriture simulée impossible');
  }
}

class _MockLicenseService extends LicenseService {
  _MockLicenseService({LicenseState state = LicenseState.licenseValid})
      : _state = state,
        super(secureStorage: _MockSecureStorage());

  final LicenseState _state;

  @override
  LicenseState get currentState => _state;

  @override
  bool get isLicensed =>
      _state == LicenseState.licenseValid ||
      _state == LicenseState.offlineGracePeriod;

  @override
  bool get requiresOnlineValidation =>
      _state == LicenseState.serverValidationRequired ||
      _state == LicenseState.clockTampered;

  @override
  bool get isReadOnly =>
      requiresOnlineValidation ||
      _state == LicenseState.versionNotCovered;

  @override
  String? get coveredVersion => '2.1';

  @override
  bool get isBlocked =>
      _state == LicenseState.machineRevoked ||
      _state == LicenseState.machineLimitReached ||
      _state == LicenseState.licenseExpired ||
      _state == LicenseState.invalidSignature ||
      _state == LicenseState.invalidMachine;

  @override
  String? get userEmail => 'contact@tilly.orceus.fr';

  @override
  String getStateMessage() {
    switch (_state) {
      case LicenseState.serverValidationRequired:
        return 'Connexion Internet nécessaire pour vérifier votre licence';
      case LicenseState.machineRevoked:
        return "Cet appareil n'est plus autorisé";
      case LicenseState.noSubscription:
        return 'Aucun abonnement en cours trouvé';
      default:
        return 'Tilly est activé';
    }
  }

  @override
  Future<({LicenseState state, String? error})> loginAndActivate({
    required String email,
    required String password,
  }) async => (state: LicenseState.licenseValid, error: null);

  @override
  Future<({LicenseState state, String? error})> validateOnline() async =>
      (state: _state, error: null);

  bool loggedOut = false;

  @override
  Future<void> logout() async {
    loggedOut = true;
  }

  @override
  Future<void> refreshLicense() async {}
}

class _MemorySecureStorage extends SecureSettingsService {
  final Map<String, String> values = {};

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<HelloAssoSettings> loadHelloAssoSettings(
    HelloAssoSettings storedSettings, {
    String? scope,
  }) async =>
      storedSettings;

  @override
  Future<void> saveHelloAssoSecret(String value, {String? scope}) async {}
}

class _MockSecureStorage extends SecureSettingsService {
  @override
  Future<String?> read({required String key}) async => null;

  @override
  Future<void> write({required String key, required String value}) async {}

  @override
  Future<void> delete({required String key}) async {}

  @override
  Future<FirebaseSettings?> loadFirebaseSettings() async => null;

  @override
  Future<void> saveFirebaseSettings(FirebaseSettings settings) async {}

  @override
  Future<void> clearFirebaseSettings() async {}

  @override
  Future<HelloAssoSettings> loadHelloAssoSettings(
    HelloAssoSettings storedSettings, {
    String? scope,
  }) async =>
      storedSettings;

  @override
  Future<void> saveHelloAssoSecret(String value, {String? scope}) async {}
}

late SimpleKeyPair _licenseKeyPair;
late String _licensePublicKeyBase64;

LicenseVerifier _testVerifier() =>
    LicenseVerifier(publicKeys: {'k1': _licensePublicKeyBase64});

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    _licenseKeyPair = await Ed25519().newKeyPair();
    final publicKey = await _licenseKeyPair.extractPublicKey();
    _licensePublicKeyBase64 = base64Url.encode(publicKey.bytes);
  });

  test('money formats French euro display', () {
    expect(money(12.5), '12,50 €');
  });

  test('default catalog starts empty with retained categories', () {
    expect(defaultArticles(), isEmpty);
    expect(defaultArticleCategories(), [
      'BOISSONS',
      'REPAS',
      'SNACKING',
      'GOODIES',
      'LOCATION',
    ]);
  });

  test('meal snack articles use the SNACKING category', () {
    final controller = AppController()
      ..articles = [
        Article(
          id: 'snacs',
          category: 'SNACS',
          type: 'standard',
          icon: '',
          name: 'Chips',
          price: 1,
          memberPrice: 1,
          stock: 12,
          threshold: 1,
        ),
        Article(
          id: 'snacking',
          category: 'SNACKING',
          type: 'standard',
          icon: '',
          name: 'Ancien snack',
          price: 1,
          memberPrice: 1,
          stock: 8,
          threshold: 1,
        ),
      ];

    expect(controller.snackArticles.map((article) => article.id), [
      'snacs',
      'snacking',
    ]);
  });

  test('prepared meal inclusions are counted as stock outgoing', () {
    final controller = AppController()
      ..articles = [
        Article(
          id: 'repas',
          category: 'REPAS',
          type: 'standard',
          icon: '',
          name: 'Repas',
          price: 10,
          memberPrice: 9,
          stock: 9,
          threshold: 1,
        ),
        Article(
          id: 'coca',
          category: 'BOISSONS',
          type: 'standard',
          icon: '',
          name: 'Coca',
          price: 2,
          memberPrice: 2,
          stock: 9,
          threshold: 1,
        ),
      ]
      ..meals = [
        MealOrder(
          id: 'meal-1',
          playerId: 'player-1',
          playerName: 'Participant',
          playerType: 'public',
          source: 'helloasso',
          status: 'prepared',
          mealArticleId: 'repas',
          drinkArticleId: 'coca',
          formula: 'Standard',
          createdAt: DateTime(2026, 5, 25),
        ),
      ];

    final rows = kpiRows(controller);
    final drink = rows.firstWhere((row) => row.article.id == 'coca');

    expect(drink.sold, 0);
    expect(drink.mealUsed, 1);
    expect(drink.outgoing, 1);
    expect(drink.stockInitial, 10);
  });

  test('onsite meal sale is not double counted in stock outgoing', () {
    final controller = AppController()
      ..articles = [
        Article(
          id: 'repas',
          category: 'REPAS',
          type: 'standard',
          icon: '',
          name: 'Repas',
          price: 10,
          memberPrice: 9,
          stock: 9,
          threshold: 1,
        ),
      ]
      ..meals = [
        MealOrder(
          id: 'meal-1',
          playerId: 'player-1',
          playerName: 'Participant',
          playerType: 'public',
          source: 'onsite',
          status: 'served',
          saleId: 'sale-1',
          payment: 'ESP',
          mealArticleId: 'repas',
          formula: 'Standard',
          createdAt: DateTime(2026, 5, 25),
        ),
      ]
      ..sales = [
        Sale(
          id: 'sale-1',
          playerId: 'player-1',
          playerName: 'Participant',
          playerType: 'public',
          tariff: 'public',
          items: [
            SaleItem(
              articleId: 'repas',
              name: 'Repas',
              icon: '',
              type: 'standard',
              quantity: 1,
              price: 10,
              publicPrice: 10,
              memberPrice: 9,
            ),
          ],
          totalArticles: 10,
          donation: 0,
          payment: 'ESP',
          session: 'session-1',
          createdAt: DateTime(2026, 5, 25),
        ),
      ];

    final row = kpiRows(controller).single;

    expect(row.sold, 1);
    expect(row.mealUsed, 1);
    expect(row.outgoing, 1);
    expect(row.ca, 10);
    expect(row.stockInitial, 10);
  });

  test('planned HelloAsso meal does not consume stock before preparation', () {
    final controller = AppController()
      ..articles = [
        Article(
          id: 'repas',
          category: 'REPAS',
          type: 'standard',
          icon: '',
          name: 'Repas',
          price: 10,
          memberPrice: 9,
          stock: 9,
          threshold: 1,
        ),
      ]
      ..meals = [
        MealOrder(
          id: 'meal-1',
          playerId: 'player-1',
          playerName: 'Participant',
          playerType: 'public',
          source: 'helloasso',
          status: 'planned',
          mealArticleId: 'repas',
          formula: 'Standard',
          createdAt: DateTime(2026, 5, 25),
        ),
      ];

    final row = kpiRows(controller).single;

    expect(row.mealUsed, 0);
    expect(row.outgoing, 0);
    expect(row.stockInitial, 9);
  });

  test('location checkout never consumes stock', () {
    final player = Player(id: 'player-1', name: 'Participant', type: 'public');
    final controller = AppController()
      ..articles = [
        Article(
          id: 'billes',
          category: 'GOODIES',
          type: 'standard',
          icon: '',
          name: 'Billes',
          price: 3,
          memberPrice: 2.5,
          stock: 0,
          threshold: 0,
        ),
        Article(
          id: 'location',
          category: 'LOCATION',
          type: 'location',
          icon: '',
          name: 'Location réplique',
          price: 15,
          memberPrice: 12,
          stock: 0,
          threshold: 0,
        ),
      ]
      ..players = [player]
      ..allPlayers = [player];

    controller.selectPlayer(player);
    controller.addToCart(
        controller.articles.firstWhere((article) => article.id == 'location'));

    expect(controller.cartStockShortages, isEmpty);
    expect(controller.canCheckout, isTrue);
  });

  test('association consumption is a stock outgoing without revenue', () {
    final article = Article(
      id: 'eau',
      category: 'BOISSONS',
      type: 'standard',
      icon: '',
      name: 'Eau',
      price: 1,
      memberPrice: 1,
      stock: 7,
      threshold: 1,
    );
    final controller = AppController()
      ..articles = [article]
      ..stockMovements = [
        StockMovement(
          id: 'stock-asso',
          sessionId: 'session-1',
          articleId: 'eau',
          movementType: 'association',
          quantityDelta: -3,
          stockBefore: 10,
          stockAfter: 7,
          reason: 'Consommation association',
          createdAt: DateTime(2026, 5, 25),
        ),
      ];

    final row = kpiRows(controller).single;

    expect(row.associationUsed, 3);
    expect(row.outgoing, 3);
    expect(row.ca, 0);
    expect(row.stockInitial, 10);
  });

  test('KPI stock initial comes from the first stock movement', () {
    final article = Article(
      id: 'eau',
      category: 'BOISSONS',
      type: 'standard',
      icon: '',
      name: 'Eau',
      price: 1,
      memberPrice: 1,
      stock: 12,
      threshold: 1,
    );
    final controller = AppController()
      ..articles = [article]
      ..stockMovements = [
        StockMovement(
          id: 'stock-adjustment',
          sessionId: 'session-1',
          articleId: 'eau',
          movementType: 'adjustment',
          quantityDelta: 5,
          stockBefore: 10,
          stockAfter: 15,
          reason: 'Réassort',
          createdAt: DateTime(2026, 5, 25, 9),
        ),
        StockMovement(
          id: 'stock-sale',
          sessionId: 'session-1',
          articleId: 'eau',
          movementType: 'sale',
          quantityDelta: -3,
          stockBefore: 15,
          stockAfter: 12,
          reason: 'Vente',
          createdAt: DateTime(2026, 5, 25, 10),
        ),
      ];

    final row = kpiRows(controller).single;

    expect(row.stockInitial, 10);
  });

  test('cancelled sales stay in audit but not in business totals', () {
    final activeSale = _sale(id: 'sale-active');
    final cancelledSale = _sale(id: 'sale-cancelled').copyWith(
      status: 'cancelled',
      cancelledAt: DateTime(2026, 7, 18),
      cancellationReason: 'Test',
    );
    final controller = AppController()..sales = [activeSale, cancelledSale];

    expect(controller.sales, hasLength(2));
    expect(controller.activeSales, [activeSale]);
    expect(controller.paymentTotals()['ESP'], activeSale.total);

    final restored = Sale.fromJson(cancelledSale.toJson());
    expect(restored.status, 'cancelled');
    expect(restored.cancelledAt, DateTime(2026, 7, 18));
    expect(restored.cancellationReason, 'Test');
  });

  test('checkout rolls memory back when SQLite persistence fails', () async {
    final article = Article(
      id: 'article-1',
      category: 'BOISSONS',
      type: 'standard',
      icon: '',
      name: 'Eau',
      price: 2,
      memberPrice: 1.5,
      stock: 3,
      threshold: 1,
    );
    final player = Player(id: 'player-1', name: 'Participant', type: 'public');
    final controller = AppController(database: _FailingDatabase())
      ..activeSession = SessionRecord(
        id: 'session-1',
        name: 'Session test',
        eventDate: DateTime(2026, 7, 18),
      )
      ..players = [player]
      ..articles = [article];
    controller
      ..selectPlayer(player)
      ..addToCart(article);

    await expectLater(
      controller.checkout('ESP'),
      throwsA(isA<StateError>()),
    );

    expect(article.stock, 3);
    expect(controller.cart, hasLength(1));
    expect(controller.cart.single.quantity, 1);
    expect(controller.sales, isEmpty);
    expect(controller.stockMovements, isEmpty);
    expect(controller.pendingStockMovements, isEmpty);
  });

  test('SQLite keeps cancelled sale items and stock movement links', () async {
    final tempDirectory = await Directory.systemTemp.createTemp('tilly-test-');
    final database = LocalDatabase(
        databasePathOverride: path.join(tempDirectory.path, 'tilly.db'));
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    final article = Article(
      id: 'article-1',
      category: 'BOISSONS',
      type: 'standard',
      icon: '',
      name: 'Eau',
      price: 2,
      memberPrice: 1.5,
      stock: 9,
      threshold: 2,
    );
    final player = Player(id: 'player-1', name: 'Participant', type: 'public');
    final sale = _sale(id: 'sale-1');
    final controller = AppController(database: database)
      ..activeSession = SessionRecord(
        id: 'session-1',
        name: 'Session test',
        eventDate: DateTime(2026, 7, 18),
      )
      ..allPlayers = [player]
      ..players = [player]
      ..articles = [article]
      ..articleCategories = ['BOISSONS']
      ..sales = [sale]
      ..pendingStockMovements = [
        StockMovement(
          id: 'movement-sale',
          sessionId: 'session-1',
          articleId: 'article-1',
          saleId: 'sale-1',
          movementType: 'sale',
          quantityDelta: -1,
          stockBefore: 10,
          stockAfter: 9,
          reason: 'Vente',
          createdAt: DateTime(2026, 7, 18, 10),
        ),
      ];

    await database.saveAll(controller);
    await controller.cancelSale(sale, reason: 'Annulation test');

    final restoredSales = await database.loadSales('session-1');
    final payload = await database.exportAll();
    validateBackupPayload(payload);
    final data = Map<String, dynamic>.from(payload['data'] as Map);
    final movements = (data['stockMovements'] as List).cast<Map>();
    final saleItems = (data['saleItems'] as List).cast<Map>();

    expect(restoredSales, hasLength(1));
    expect(restoredSales.single.status, 'cancelled');
    expect(restoredSales.single.items, hasLength(1));
    expect(saleItems, hasLength(1));
    expect(movements, hasLength(2));
    expect(movements.every((row) => row['sale_id'] == 'sale-1'), isTrue);
  });

  test('SQLite v7 meal schema migrates to nullable player foreign key',
      () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-migration-test-');
    final databasePath = path.join(tempDirectory.path, 'tilly-v7.db');
    final legacyDatabase = await openDatabase(
      databasePath,
      version: 7,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY
          )
        ''');
        await database.execute('''
          CREATE TABLE players (
            id TEXT PRIMARY KEY
          )
        ''');
        await database.execute('''
          CREATE TABLE sales (
            id TEXT PRIMARY KEY
          )
        ''');
        await database.execute('''
          CREATE TABLE stock_movements (
            id TEXT PRIMARY KEY,
            sale_id TEXT
          )
        ''');
        await database.execute('''
          CREATE TABLE meal_orders (
            id TEXT PRIMARY KEY,
            session_id TEXT NOT NULL,
            player_id TEXT NOT NULL,
            player_name_snapshot TEXT NOT NULL,
            player_type_snapshot TEXT NOT NULL,
            source TEXT NOT NULL,
            status TEXT NOT NULL,
            sale_id TEXT,
            payment_method TEXT,
            meal_article_id TEXT NOT NULL,
            drink_article_id TEXT,
            snack_article_id TEXT,
            formula TEXT NOT NULL,
            options_json TEXT,
            note TEXT,
            created_at TEXT NOT NULL,
            prepared_at TEXT,
            served_at TEXT,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    await legacyDatabase.insert('sessions', {'id': 'session-1'});
    await legacyDatabase.insert('players', {'id': 'player-1'});
    await legacyDatabase.insert('meal_orders', {
      'id': 'meal-1',
      'session_id': 'session-1',
      'player_id': 'player-1',
      'player_name_snapshot': 'Participant',
      'player_type_snapshot': 'public',
      'source': 'helloasso',
      'status': 'planned',
      'meal_article_id': 'article-1',
      'formula': 'Standard',
      'created_at': '2026-07-18T10:00:00',
      'updated_at': '2026-07-18T10:00:00',
    });
    await legacyDatabase.close();

    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    final meals = await database.loadMeals('session-1');
    final migratedDatabase = await openDatabase(databasePath);
    final columns =
        await migratedDatabase.rawQuery("PRAGMA table_info('meal_orders')");
    final playerIdColumn =
        columns.firstWhere((column) => column['name'] == 'player_id');
    await migratedDatabase.close();

    expect(meals.single.playerId, 'player-1');
    expect(playerIdColumn['notnull'], 0);
  });

  test('legacy default session names migrate to evenement', () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-rename-test-');
    final databasePath = path.join(tempDirectory.path, 'tilly-v8.db');
    final legacyDatabase = await openDatabase(
      databasePath,
      version: 8,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            event_date TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'open',
            notes TEXT,
            helloasso_form_slug TEXT,
            helloasso_form_type TEXT,
            helloasso_event_name TEXT,
            helloasso_event_url TEXT,
            helloasso_event_id TEXT,
            helloasso_synced_at TEXT,
            created_at TEXT NOT NULL,
            closed_at TEXT
          )
        ''');
      },
    );
    await legacyDatabase.insert('sessions', {
      'id': 'session-1',
      'name': 'Nouvelle partie',
      'event_date': '2026-07-18T00:00:00',
      'status': 'open',
      'created_at': '2026-07-18T00:00:00',
    });
    await legacyDatabase.close();

    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    final sessions = await database.loadSessions();

    expect(sessions.single.name, 'Nouvel événement');
  });

  test('HelloAsso portable settings exclude the client secret', () {
    const settings = HelloAssoSettings(
      organizationSlug: 'tilly',
      clientId: 'client',
      clientSecret: 'private-secret',
    );

    final exported = settings.toJson(includeSecret: false);

    expect(exported.containsKey('clientSecret'), isFalse);
    expect(settings.withoutSecret().clientSecret, isEmpty);
  });

  test('JSON backup payload excludes the HelloAsso client secret', () {
    final payload = _backupPayloadWithHelloAssoSecret('json-private-secret');

    final sanitized = sanitizePortableBackupPayload(payload);
    final exported = const JsonEncoder.withIndent('  ').convert(sanitized);

    expect(exported, isNot(contains('json-private-secret')));
    expect(_helloAssoSettingsFromPayload(sanitized).clientSecret, isEmpty);
    expect(_helloAssoSettingsFromPayload(payload).clientSecret,
        'json-private-secret');
  });

  test('Firebase sync payload excludes the HelloAsso client secret', () {
    final payload =
        _backupPayloadWithHelloAssoSecret('firebase-private-secret');

    final sanitized = FirebaseSyncService.sanitizePayloadForSync(payload);
    final encoded = jsonEncode(sanitized);

    expect(encoded, isNot(contains('firebase-private-secret')));
    expect(_helloAssoSettingsFromPayload(sanitized).clientSecret, isEmpty);
  });

  test('app settings persist the primary color', () {
    const settings = AppSettings(primaryColorValue: 0xFFFF6B35);
    final restored = AppSettings.fromJson(settings.toJson());

    expect(restored.primaryColor.toARGB32(), 0xFFFF6B35);
  });

  test('Tiko tutorial progress persists across account datasets', () async {
    final store = _MemoryTutorialStore();
    final firstDirectory =
        await Directory.systemTemp.createTemp('tilly-tutorial-first-');
    final firstDatabase =
        LocalDatabase(databaseDirectoryOverride: firstDirectory.path);
    final first = AppController(
      database: firstDatabase,
      secureSettings: _MemorySecureStorage(),
      tutorialStore: store,
    );
    addTearDown(() async {
      await firstDatabase.close();
      await firstDirectory.delete(recursive: true);
    });

    await first.load();
    await first.markTutorialWelcomeSeen();
    await first.markTutorialPageSeen(AppTabIds.sales);

    final secondDirectory =
        await Directory.systemTemp.createTemp('tilly-tutorial-second-');
    final secondDatabase =
        LocalDatabase(databaseDirectoryOverride: secondDirectory.path);
    final second = AppController(
      database: secondDatabase,
      secureSettings: _MemorySecureStorage(),
      tutorialStore: store,
    );
    addTearDown(() async {
      await secondDatabase.close();
      await secondDirectory.delete(recursive: true);
    });

    await second.load();

    expect(second.tutorialWelcomeSeen, isTrue);
    expect(second.tutorialPagesSeen, contains(AppTabIds.sales));
  });

  test('Firebase settings round-trip and build runtime options', () {
    const settings = FirebaseSettings(
      apiKey: 'api-key',
      appId: 'app-id',
      messagingSenderId: 'sender-id',
      projectId: 'project-id',
      authDomain: 'project.firebaseapp.com',
      iosBundleId: 'com.tilly.caisse',
    );

    final restored = FirebaseSettings.fromJson(settings.toJson());
    final options = restored.toOptions();

    expect(restored.isConfigured, isTrue);
    expect(options.apiKey, 'api-key');
    expect(options.projectId, 'project-id');
    expect(options.authDomain, 'project.firebaseapp.com');
    expect(options.iosBundleId, 'com.tilly.caisse');
  });

  test('Firebase settings require the four core identifiers', () {
    expect(const FirebaseSettings().isConfigured, isFalse);
    expect(
        const FirebaseSettings(
          apiKey: 'api-key',
          appId: 'app-id',
          messagingSenderId: 'sender-id',
        ).isConfigured,
        isFalse);
  });

  test('Firebase web configuration can be pasted as a single block', () {
    final settings = parseFirebaseSettings('''
      const firebaseConfig = {
        apiKey: "api-key",
        authDomain: "project.firebaseapp.com",
        projectId: "project-id",
        storageBucket: "project.firebasestorage.app",
        messagingSenderId: "sender-id",
        appId: "app-id"
      };
    ''');

    expect(settings.isConfigured, isTrue);
    expect(settings.projectId, 'project-id');
    expect(settings.authDomain, 'project.firebaseapp.com');
  });

  test('Firebase Android google-services JSON can be pasted', () {
    final settings = parseFirebaseSettings(jsonEncode({
      'project_info': {
        'project_number': 'sender-id',
        'project_id': 'project-id',
        'storage_bucket': 'project.firebasestorage.app',
      },
      'client': [
        {
          'client_info': {'mobilesdk_app_id': 'android-app-id'},
          'api_key': [
            {'current_key': 'api-key'}
          ],
        }
      ],
    }));

    expect(settings.isConfigured, isTrue);
    expect(settings.appId, 'android-app-id');
    expect(settings.messagingSenderId, 'sender-id');
  });

  test('Firebase Apple GoogleService-Info plist can be pasted', () {
    final settings = parseFirebaseSettings('''
      <?xml version="1.0" encoding="UTF-8"?>
      <plist version="1.0">
      <dict>
        <key>API_KEY</key>
        <string>api-key</string>
        <key>GCM_SENDER_ID</key>
        <string>sender-id</string>
        <key>PROJECT_ID</key>
        <string>project-id</string>
        <key>STORAGE_BUCKET</key>
        <string>project.firebasestorage.app</string>
        <key>GOOGLE_APP_ID</key>
        <string>apple-app-id</string>
        <key>BUNDLE_ID</key>
        <string>com.tilly.caisse</string>
      </dict>
      </plist>
    ''');

    final options = settings.toOptions();
    expect(settings.isConfigured, isTrue);
    expect(settings.appId, 'apple-app-id');
    expect(options.iosBundleId, 'com.tilly.caisse');
  });

  test('license API URL comes from the compiled default and .env.dev',
      () async {
    expect(dotenv.isInitialized, isFalse);
    expect(licenseApiBaseUrl, 'http://localhost:3000');

    await dotenv.load(fileName: '.env.dev');
    expect(licenseApiBaseUrl, 'http://localhost:3000');

    dotenv.clean();
  });

  test('license login hides connection failure details', () async {
    final api = LicenseApiClient(
      client: MockClient((_) async => throw SocketException('refused')),
    );

    await expectLater(
      api.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<LicenseApiException>()
            .having((e) => e.state, 'state', 'network_error')
            .having(
              (e) => e.message,
              'message',
              'Impossible de joindre le serveur. Vérifie ta connexion Internet.',
            )
            .having(
              (e) => e.message,
              'no technical detail',
              isNot(contains('SocketException')),
            ),
      ),
    );
  });

  test('license login maps server errors to a friendly message', () async {
    final api = LicenseApiClient(
      client: MockClient((_) async => http.Response('{}', 500)),
    );

    await expectLater(
      api.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<LicenseApiException>()
            .having((e) => e.state, 'state', 'server_error')
            .having(
              (e) => e.message,
              'message',
              'Le serveur est momentanément indisponible. Réessaie dans quelques instants.',
            ),
      ),
    );
  });

  test('license login keeps wrong credentials message simple', () async {
    final api = LicenseApiClient(
      client: MockClient(
        (_) async => http.Response('{"state":"invalid_credentials"}', 401),
      ),
    );

    await expectLater(
      api.login(email: 'user@example.com', password: 'secret'),
      throwsA(
        isA<LicenseApiException>().having(
          (e) => e.message,
          'message',
          'E-mail ou mot de passe incorrect.',
        ),
      ),
    );
  });

  test('license activation maps refusals to simple messages', () async {
    final api = LicenseApiClient(
      client: MockClient(
        (_) async => http.Response('{"state":"MACHINE_LIMIT_REACHED"}', 409),
      ),
    );

    await expectLater(
      api.activate(
        token: 'token',
        machineInfo: const MachineInfo(
          machineId: 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b',
          platform: 'MACOS',
          appVersion: '1.0.0',
        ),
      ),
      throwsA(
        isA<LicenseApiException>()
            .having((e) => e.state, 'state', 'MACHINE_LIMIT_REACHED')
            .having(
              (e) => e.message,
              'message',
              'Trop d\'appareils sont associés à cette licence.',
            ),
      ),
    );
  });

  test('machine fingerprint is lowercase sha-256 hex', () async {
    final service = MachineIdService(_MemorySecureStorage());
    final hash = await service.generateFingerprintHash();

    expect(hash, isNotNull);
    expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash!), isTrue);
  });

  test('license activation maps validation errors to a simple message',
      () async {
    final api = LicenseApiClient(
      client: MockClient(
        (_) async => http.Response(
          '{"type":"validation_error","title":"Requête invalide",'
          '"status":422,"errors":{"fingerprintHash":["Format invalide."]}}',
          422,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    await expectLater(
      api.activate(
        token: 'token',
        machineInfo: const MachineInfo(
          machineId: 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b',
          platform: 'ANDROID',
          appVersion: '1.0.0',
        ),
      ),
      throwsA(
        isA<LicenseApiException>()
            .having((e) => e.state, 'state', 'validation_error')
            .having(
              (e) => e.message,
              'message',
              'Vérifie les informations saisies.',
            ),
      ),
    );
  });

  test('lifetime license is valid offline', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(machineId: machineId),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.licenseValid);
  });

  test('lifetime license stays valid 10 years offline', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(machineId: machineId),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: DateTime.now().add(const Duration(days: 3650)),
    );
    expect(state, LicenseState.licenseValid);
  });

  test('lifetime covers patches of the covered version', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: machineId,
        coveredVersion: '2.1',
      ),
      localMachineId: machineId,
      appVersion: '2.1.9',
      now: DateTime.now(),
    );
    expect(state, LicenseState.licenseValid);
  });

  test('lifetime does not cover a newer minor version', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: machineId,
        coveredVersion: '2.1',
      ),
      localMachineId: machineId,
      appVersion: '2.2.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.versionNotCovered);
  });

  test('subscription is valid inside its offline window', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final now = DateTime.now();
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: machineId,
        licenseType: 'SUBSCRIPTION',
        coveredVersion: null,
        offlineValidUntil: now.add(const Duration(days: 5)),
        licenseValidUntil: now.add(const Duration(days: 20)),
      ),
      localMachineId: machineId,
      appVersion: '9.9.9',
      now: now,
    );
    expect(state, LicenseState.licenseValid);
  });

  test('subscription falls into the offline grace period', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final now = DateTime.now();
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: machineId,
        licenseType: 'SUBSCRIPTION',
        coveredVersion: null,
        offlineValidUntil: now.subtract(const Duration(minutes: 30)),
        licenseValidUntil: now.add(const Duration(days: 20)),
      ),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: now,
    );
    expect(state, LicenseState.offlineGracePeriod);
  });

  test('subscription requires online validation after the grace', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final now = DateTime.now();
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: machineId,
        licenseType: 'SUBSCRIPTION',
        coveredVersion: null,
        offlineValidUntil: now.subtract(const Duration(hours: 3)),
        licenseValidUntil: now.add(const Duration(days: 20)),
      ),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: now,
    );
    expect(state, LicenseState.serverValidationRequired);
  });

  test('tampered signature is rejected', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final envelope = await _licenseEnvelope(machineId: machineId);
    final state = await _testVerifier().verify(
      envelope: LicenseEnvelope(
        kid: 'k1',
        payload: envelope.payload,
        signature: base64Url.encode(List<int>.filled(64, 7)),
      ),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.invalidSignature);
  });

  test('tampered payload is rejected', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final envelope = await _licenseEnvelope(machineId: machineId);
    final json = jsonDecode(utf8.decode(base64UrlDecodeBytes(envelope.payload)))
        as Map<String, dynamic>;
    json['offlineValidUntil'] = '2099-01-01T00:00:00.000Z';
    final state = await _testVerifier().verify(
      envelope: LicenseEnvelope(
        kid: 'k1',
        payload: base64Url.encode(utf8.encode(jsonEncode(json))),
        signature: envelope.signature,
      ),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.invalidSignature);
  });

  test('unknown signing key is rejected', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final envelope = await _licenseEnvelope(machineId: machineId);
    final state = await _testVerifier().verify(
      envelope: LicenseEnvelope(
        kid: 'k9',
        payload: envelope.payload,
        signature: envelope.signature,
      ),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.invalidSignature);
  });

  test('license bound to another machine is rejected', () async {
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(
        machineId: 'MCH-bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
      ),
      localMachineId: 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b',
      appVersion: '1.0.0',
      now: DateTime.now(),
    );
    expect(state, LicenseState.invalidMachine);
  });

  test('rewound clock is rejected', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final now = DateTime.now();
    final state = await _testVerifier().verify(
      envelope: await _licenseEnvelope(machineId: machineId),
      localMachineId: machineId,
      appVersion: '1.0.0',
      now: now,
      lastServerTime: now.add(const Duration(days: 2)),
    );
    expect(state, LicenseState.clockTampered);
  });

  test('tutorial override maps debug flag values', () {
    expect(tutorialOverrideFor('on'), 'on');
    expect(tutorialOverrideFor('true'), 'on');
    expect(tutorialOverrideFor('off'), 'off');
    expect(tutorialOverrideFor('false'), 'off');
    expect(tutorialOverrideFor(''), '');
    expect(tutorialOverrideFor('nonsense'), '');
  });

  test('demo dataset provides three days of activity', () {
    final dataset = buildDemoDataset(now: DateTime(2026, 7, 18, 12));

    expect(dataset.days, hasLength(3));
    expect(dataset.players, hasLength(10));
    expect(dataset.articles, isNotEmpty);
    expect(dataset.categories, contains('BOISSONS'));
    expect(dataset.categories, contains('REPAS'));
    expect(dataset.articles.any((article) => article.category == 'REPAS'),
        isTrue);

    for (final day in dataset.days) {
      expect(day.sales, isNotEmpty);
      expect(day.meals, isNotEmpty);
      expect(day.players, isNotEmpty);
      expect(day.cashStart, isNotEmpty);
      expect(day.cashEnd, isNotEmpty);
      expect(day.stockMovements, isNotEmpty);
      for (final meal in day.meals.where((meal) => meal.consumesStock)) {
        expect(
            day.stockMovements.any((movement) =>
                movement.movementType == 'meal' &&
                movement.reason == 'Repas ${meal.id}'),
            isTrue);
      }
    }

    expect(dataset.days.first.session.eventDate, DateTime(2026, 7, 16));
    expect(dataset.days.last.session.eventDate, DateTime(2026, 7, 18));
    expect(dataset.days.first.session.status, 'closed');
    expect(dataset.days.last.session.status, 'open');

    final sales = dataset.days.expand((day) => day.sales).toList();
    expect(sales.any((sale) => sale.status == 'cancelled'), isTrue);
    expect(sales.any((sale) => sale.donation > 0), isTrue);
    expect(sales.any((sale) => sale.tariff == 'membre'), isTrue);
    expect(sales.any((sale) => sale.tariff == 'public'), isTrue);

    final meals = dataset.days.expand((day) => day.meals).toList();
    expect(meals.any((meal) => meal.source == 'helloasso'), isTrue);
    expect(meals.any((meal) => meal.source == 'onsite'), isTrue);
    expect(meals.any((meal) => meal.status == 'planned'), isTrue);
    expect(meals.any((meal) => meal.status == 'prepared'), isTrue);
    expect(meals.any((meal) => meal.status == 'served'), isTrue);
    expect(meals.any((meal) => meal.status == 'cancelled'), isTrue);
    for (final meal in meals.where((meal) => meal.isOnsite)) {
      expect(meal.saleId, isNotEmpty);
      expect(sales.any((sale) => sale.id == meal.saleId), isTrue);
    }
  });

  test('dev license override maps build values to license states', () {
    expect(licenseStateForDevOverride('valid'), LicenseState.licenseValid);
    expect(
        licenseStateForDevOverride('grace'), LicenseState.offlineGracePeriod);
    expect(licenseStateForDevOverride('server'),
        LicenseState.serverValidationRequired);
    expect(licenseStateForDevOverride('blocked'), LicenseState.machineRevoked);
    expect(licenseStateForDevOverride('expired'), LicenseState.licenseExpired);
    expect(licenseStateForDevOverride('none'), LicenseState.noLicense);
    expect(licenseStateForDevOverride(''), isNull);
    expect(licenseStateForDevOverride('nonsense'), isNull);
  });

  test('missing license reports no license', () async {
    final service = LicenseService(
      secureStorage: _MemorySecureStorage(),
      apiClient: LicenseApiClient(
        client: MockClient((_) async => http.Response('{}', 404)),
      ),
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);

    await service.initialize();
    expect(service.currentState, LicenseState.noLicense);
  });

  test('network failure during validation keeps the local state', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: DateTime.now(),
      machineId: machineId,
      deviceSecret: secret,
    ));

    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          throw const SocketException('offline');
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.isLicensed, isTrue);

    final result = await service.validateOnline();
    expect(result.state, LicenseState.licenseValid);
    expect(service.isLicensed, isTrue);
  });

  test('unexpected validation error keeps the local state', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: DateTime.now(),
      machineId: machineId,
      deviceSecret: secret,
    ));

    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          return http.Response('<html>404</html>', 404);
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.currentState, LicenseState.licenseValid);
    expect(service.isLicensed, isTrue);

    final result = await service.validateOnline();
    expect(result.state, LicenseState.licenseValid);
    expect(service.isLicensed, isTrue);
  });

  test('explicit license rejection still updates the state', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: DateTime.now(),
      machineId: machineId,
      deviceSecret: secret,
    ));

    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          return http.Response(
            '{"type":"license_not_found","status":404,"state":"NOT_FOUND"}',
            404,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final result = await service.validateOnline();
    expect(result.state, LicenseState.noSubscription);
    expect(service.isLicensed, isFalse);
  });

  test('update check returns the release accessible to the account', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({
          'data': {
            'version': 'v9.9.9',
            'publishedAt': '2026-10-01T12:00:00.000Z',
            'fileName': 'Tilly-macOS-9.9.9.dmg',
            'size': 2048,
            'sha256': 'ABCDEF',
            'downloadUrl': '/download/macos?version=9.9.9',
          }
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result =
        await AppUpdateService.check(authToken: 'token-1', client: client);

    expect(result.update, isNotNull);
    expect(result.update!.latestVersion, '9.9.9');
    expect(result.update!.sha256, 'abcdef');
    expect(result.update!.formattedSize, '2 Ko');
    expect(result.update!.downloadUrl,
        '$licenseApiBaseUrl/download/macos?version=9.9.9');
    expect(captured.url.queryParameters['platform'],
        AppUpdateService.platformSlug);
    expect(captured.headers['Authorization'], 'Bearer token-1');
  }, skip: !AppUpdateService.supportedPlatform);

  test('update check detects an up-to-date version', () async {
    final client = MockClient((request) async => http.Response(
          jsonEncode({
            'data': {
              'version': appBuildVersion,
              'fileName': 'Tilly-macOS-$appBuildVersion.dmg',
              'downloadUrl': '/download/macos',
            }
          }),
          200,
          headers: {'content-type': 'application/json'},
        ));

    final result =
        await AppUpdateService.check(authToken: 'token-1', client: client);

    expect(result.update, isNull);
    expect(result.latestVersion, appBuildVersion);
  }, skip: !AppUpdateService.supportedPlatform);

  test('update check reports an account without download rights', () async {
    final client = MockClient((request) async => http.Response(
          '{"type":"download_forbidden","status":403,'
          '"detail":"Votre licence à vie couvre Tilly jusqu\'à la version 1.1."}',
          403,
          headers: {'content-type': 'application/json'},
        ));

    final result =
        await AppUpdateService.check(authToken: 'token-1', client: client);

    expect(result.update, isNull);
    expect(result.accessDenied, isTrue);
    expect(result.error, contains('1.1'));
  }, skip: !AppUpdateService.supportedPlatform);

  test('app version resolves from the binary without a compiled define',
      () async {
    final previous = appBuildVersion;
    addTearDown(() => appBuildVersion = previous);
    PackageInfo.setMockInitialValues(
      appName: 'Tilly',
      packageName: 'com.tilly.caisse',
      version: '2.3.4',
      buildNumber: '2003004',
      buildSignature: '',
    );

    await initializeAppVersion();

    expect(appBuildVersion, '2.3.4');
  });

  test('cached update file hash is verified', () async {
    final directory =
        await Directory.systemTemp.createTemp('tilly-update-hash-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File(path.join(directory.path, 'update.apk'))
      ..writeAsBytesSync([1, 2, 3]);
    final digest = crypto.sha256.convert([1, 2, 3]).toString();

    expect(await AppUpdateDownloader.matchesSha256(file, digest), isTrue);
    expect(await AppUpdateDownloader.matchesSha256(file, 'deadbeef'), isFalse);
  });

  test('read-only mode keeps the data exportable', () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-export-');
    final database =
        LocalDatabase(databaseDirectoryOverride: tempDirectory.path);
    final controller = AppController(
      database: database,
      secureSettings: _MemorySecureStorage(),
    );
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    await controller.load();
    await controller.addPlayer(
      firstName: 'Alice',
      lastName: 'Martin',
      email: '',
      type: 'public',
    );

    controller.readOnly = true;
    final payload = await controller.fullBackupPayload();

    expect(jsonEncode(payload), contains('Alice'));
  });

  test('license state hmac round-trips after signing', () async {
    final store = LicenseStore(_MemorySecureStorage());
    final secret = await store.getOrCreateDeviceSecret();
    final signed = await store.signState(
      lastValidatedAt: DateTime(2026, 10, 1, 14, 30),
      lastServerTime: DateTime.utc(2026, 10, 1, 12, 30),
      machineId: 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b',
      deviceSecret: secret,
    );

    expect(await store.verifyStateHmac(signed, secret), isTrue);
    final tampered = LicenseStateData(
      lastValidatedAt: signed.lastValidatedAt!.add(const Duration(hours: 1)),
      lastServerTime: signed.lastServerTime,
      lastMachineId: signed.lastMachineId,
      hmac: signed.hmac,
    );
    expect(await store.verifyStateHmac(tampered, secret), isFalse);
  });

  test('license activation succeeds and stays valid', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId;
    final envelope = await _licenseEnvelope(
      machineId: machineId,
      features: const ['sales', 'stock'],
    );

    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'user': {'id': 'user-1', 'email': 'user@example.com'},
              'token': 'token-1',
              'expiresAt': '2026-10-08T12:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/license/activate')) {
          return http.Response(
            jsonEncode({
              'data': {
                'granted': true,
                'state': 'ACTIVATED',
                'license': envelope.toJson(),
                'machine': {
                  'machineId': machineId,
                  'platform': 'ANDROID',
                  'appVersion': '1.0.0',
                  'firstSeenAt': '2026-10-01T12:00:00.000Z',
                  'lastSeenAt': '2026-10-01T12:00:00.000Z',
                  'revokedAt': null,
                  'revokedReason': null,
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    final result = await service.loginAndActivate(
      email: 'user@example.com',
      password: 'secret-password',
    );

    expect(result.error, isNull);
    expect(result.state, LicenseState.licenseValid);
    expect(service.isLicensed, isTrue);
  });

  test('license activation without subscription returns a typed state',
      () async {
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] =
          'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'user': {'id': 'user-1', 'email': 'user@example.com'},
              'token': 'token-1',
              'expiresAt': '2026-10-08T12:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          '{"type":"license_not_found","title":"Aucune licence","status":404,'
          '"state":"NOT_FOUND","detail":"Aucune licence active pour ce compte."}',
          404,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    final result = await service.loginAndActivate(
      email: 'user@example.com',
      password: 'secret-password',
    );

    expect(result.state, LicenseState.noSubscription);
    expect(
      result.error,
      'Aucun abonnement en cours trouvé. '
      'Vérifie ton compte sur tilly.orceus.fr.',
    );
    expect(service.isLicensed, isFalse);
    expect(service.getStateMessage(), 'Aucun abonnement en cours trouvé');
  });

  test('empty modern backups are rejected before replacement', () {
    expect(
      () => validateBackupPayload({
        'version': 3,
        'data': {
          'sessions': <Object>[],
          'articles': <Object>[],
          'appSettings': <Object>[],
        },
      }),
      throwsFormatException,
    );
  });

  test('modern backups can restore an empty article catalog', () {
    expect(
      () => validateBackupPayload(_validModernBackup()),
      returnsNormally,
    );
  });

  test('modern backups reject unknown columns and broken references', () {
    final unknownColumn = _validModernBackup();
    ((unknownColumn['data'] as Map)['sessions'] as List).first['unexpected'] =
        'value';
    expect(() => validateBackupPayload(unknownColumn), throwsFormatException);

    final brokenReference = _validModernBackup();
    ((brokenReference['data'] as Map)['sales'] as List).add({
      'id': 'sale-1',
      'session_id': 'missing-session',
      'player_name_snapshot': 'Participant',
      'player_type_snapshot': 'public',
      'tariff_applied': 'public',
      'payment_method': 'ESP',
      'status': 'active',
      'total_articles': 2.0,
      'donation_amount': 0.0,
      'total_amount': 2.0,
      'created_at': '2026-07-18T10:00:00',
    });
    expect(() => validateBackupPayload(brokenReference), throwsFormatException);
  });

  test('future backup versions are rejected before replacement', () {
    final payload = _validModernBackup()..['version'] = 99;
    expect(() => validateBackupPayload(payload), throwsFormatException);
  });

  test('.tilly backups validate without configuration', () {
    final payload = _validModernBackup()..['version'] = backupFormatVersion;
    payload['data'] =
        Map<String, Object?>.from(payload['data'] as Map)..remove('appSettings');
    expect(() => validateBackupPayload(payload), returnsNormally);

    final broken = _validModernBackup()..['version'] = backupFormatVersion;
    broken['data'] = Map<String, Object?>.from(broken['data'] as Map)
      ..remove('appSettings')
      ..['activeSessionId'] = 'missing-session';
    expect(() => validateBackupPayload(broken), throwsFormatException);
  });

  test('.tilly export keeps the data and leaves the configuration out',
      () async {
    final tempDirectory = await Directory.systemTemp.createTemp('tilly-export-');
    final database =
        LocalDatabase(databaseDirectoryOverride: tempDirectory.path);
    final controller = AppController(
      database: database,
      secureSettings: _MemorySecureStorage(),
    );
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    await controller.load();
    await controller.addPlayer(
      firstName: 'Alice',
      lastName: 'Martin',
      email: '',
      type: 'public',
    );
    await controller.setAssociationName('Asso Export');

    final payload = await controller.fullBackupPayload();
    final data = Map<String, dynamic>.from(payload['data'] as Map);

    expect(payload['format'], tillyBackupFormat);
    expect(payload['version'], backupFormatVersion);
    expect(payload['configurationIncluded'], isFalse);
    expect(data.containsKey('appSettings'), isFalse);
    expect(data['activeSessionId'], controller.activeSession?.id);
    expect(jsonEncode(data['players']), contains('Alice'));
  });

  test('.tilly restore replaces the data but preserves the configuration',
      () async {
    final sourceDirectory =
        await Directory.systemTemp.createTemp('tilly-restore-source-');
    final targetDirectory =
        await Directory.systemTemp.createTemp('tilly-restore-target-');
    final sourceDatabase =
        LocalDatabase(databaseDirectoryOverride: sourceDirectory.path);
    final targetDatabase =
        LocalDatabase(databaseDirectoryOverride: targetDirectory.path);
    addTearDown(() async {
      await sourceDatabase.close();
      await targetDatabase.close();
      await sourceDirectory.delete(recursive: true);
      await targetDirectory.delete(recursive: true);
    });

    final source = AppController(
      database: sourceDatabase,
      secureSettings: _MemorySecureStorage(),
    );
    await source.load();
    await source.addPlayer(
      firstName: 'Alice',
      lastName: 'Martin',
      email: '',
      type: 'public',
    );
    await source.setAssociationName('Asso Source');
    final sourceSessionId = source.activeSession!.id;
    final payload = await source.fullBackupPayload();

    final target = AppController(
      database: targetDatabase,
      secureSettings: _MemorySecureStorage(),
    );
    await target.load();
    await target.setAssociationName('Asso Cible');

    await target.importBackup(payload);

    expect(target.associationName, 'Asso Cible');
    expect(target.activeSession?.id, sourceSessionId);
    expect(jsonEncode(target.allPlayers), contains('Alice'));
  });

  testWidgets('association rename dialog updates without framework exception',
      (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfigPage(
            controller: controller,
            licenseService: _MockLicenseService(),
            updateResult: null,
            checkingUpdate: false,
            onCheckUpdate: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Renommer'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nouvelle asso');
    await tester.tap(find.text('Valider'));
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();

    expect(controller.associationName, 'Nouvelle asso');
    expect(tester.takeException(), isNull);
  });

  testWidgets('primary color picker applies preset without hex text field',
      (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(
          body: ConfigPage(
            controller: controller,
            licenseService: _MockLicenseService(),
            updateResult: null,
            checkingUpdate: false,
            onCheckUpdate: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Personnalisée'));
    await tester.pumpAndSettle();

    expect(find.text('Couleur hex'), findsNothing);
    expect(find.byType(ColorPicker), findsOneWidget);

    await tester.tap(find.byTooltip('#35C8F1').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();

    expect(controller.primaryColor.toARGB32(), AppColors.accent2.toARGB32());
    expect(tester.takeException(), isNull);
  });

  testWidgets('config scroll position survives a main tab toggle',
      (tester) async {
    final controller = _MemoryAppController()
      ..tutorialWelcomeSeen = true
      ..tutorialPagesSeen = {
        ...AppTabIds.configurable,
        AppTabIds.sales,
        AppTabIds.config,
      };
    tester.view.physicalSize = const Size(1200, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(
          controller: controller,
          licenseService: _MockLicenseService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(NavigationRail),
      matching: find.text('Config'),
    ));
    await tester.pumpAndSettle();

    final listView = find
        .descendant(
            of: find.byType(ConfigPage), matching: find.byType(ListView))
        .first;
    await tester.drag(listView, const Offset(0, -200));
    await tester.pumpAndSettle();

    double scrollOffset() => tester
        .state<ScrollableState>(
            find.descendant(of: listView, matching: find.byType(Scrollable)))
        .position
        .pixels;

    final offsetBefore = scrollOffset();
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.widgetWithText(SwitchListTile, 'Stats'));
    await tester.pumpAndSettle();

    expect(controller.isMainTabVisible(AppTabIds.stats), isFalse);
    expect(scrollOffset(), offsetBefore);
    expect(tester.takeException(), isNull);
  });

  testWidgets('configuration service help is presented by Tiko',
      (tester) async {
    final controller = _MemoryAppController();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(
          body: ConfigPage(
            controller: controller,
            licenseService: _MockLicenseService(),
            updateResult: null,
            checkingUpdate: false,
            onCheckUpdate: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Synchronisation'));
    await tester.pumpAndSettle();

    expect(find.text('À quoi ça sert ?'), findsOneWidget);
    await tester.tap(find.byTooltip('Tiko explique Firebase'));
    await tester.pumpAndSettle();

    expect(find.textContaining('synchronisation est optionnelle'),
        findsOneWidget);

    for (var step = 0; step < 4; step++) {
      await tester.tap(find.text('Suivant'));
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('un autre appareil a des données plus récentes'),
        findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();

    expect(find.textContaining('deux appareils en même temps'), findsOneWidget);
    expect(find.text('Ouvrir le tutoriel'), findsOneWidget);

    await tester.tap(find.byTooltip('Fermer le tuto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HelloAsso'));
    await tester.pumpAndSettle();
    expect(find.text('À quoi ça sert ?'), findsOneWidget);
    await tester.tap(find.byTooltip('Tiko explique HelloAsso'));
    await tester.pumpAndSettle();

    expect(find.textContaining('HelloAsso est facultatif'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('legacy tutorial rows are removed from the account database',
      () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-tutorial-cleanup-');
    final databasePath = path.join(tempDirectory.path, 'tilly-v9.db');
    final legacy = await openDatabase(
      databasePath,
      version: 9,
      onCreate: (database, version) async {
        await database.execute('''
          CREATE TABLE app_settings (
            key TEXT PRIMARY KEY,
            value TEXT,
            updated_at TEXT
          )
        ''');
      },
    );
    final now = DateTime.now().toIso8601String();
    await legacy.insert('app_settings', {
      'key': 'tutorial_welcome_seen',
      'value': 'true',
      'updated_at': now,
    });
    await legacy.insert('app_settings', {
      'key': 'tutorial_pages_seen',
      'value': jsonEncode(['sales']),
      'updated_at': now,
    });
    await legacy.close();

    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    final rows = await (await database.database).query('app_settings');

    expect(rows, isEmpty);
  });

  testWidgets('Tiko first launch tour ends on articles page', (tester) async {
    final controller = _MemoryAppController();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> finishCurrentTutorial(String finalLabel) async {
      var guard = 0;
      while (find.text('Suivant').evaluate().isNotEmpty && guard < 8) {
        await tester.tap(find.text('Suivant'));
        await tester.pumpAndSettle();
        guard += 1;
      }
      await tester.tap(find.text(finalLabel));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(controller: controller, licenseService: _MockLicenseService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('merci d\'avoir choisi'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Moi, c\'est Tiko'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(find.textContaining('en haut à droite'), findsOneWidget);

    await tester.tap(find.text('Suivant'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('tour rapide de l\'application'), findsOneWidget);

    await finishCurrentTutorial('C\'est parti');

    expect(controller.tutorialWelcomeSeen, isTrue);
    expect(find.textContaining('La page Vente est le cœur'), findsOneWidget);

    final visitedTabs = <int>{};
    var guard = 0;
    while (
        find.byTooltip('Fermer le tuto').evaluate().isNotEmpty && guard < 12) {
      visitedTabs.add(controller.tab);
      final finalLabel =
          controller.tab == 7 ? 'Créer mon premier article' : 'Continuer';
      await finishCurrentTutorial(finalLabel);
      guard += 1;
    }

    expect(visitedTabs, containsAll(<int>{0, 1, 2, 3, 4, 5, 6, 7, 8}));
    expect(controller.tab, 7);
    expect(find.text('ARTICLES & PRIX'), findsWidgets);
    expect(controller.tutorialPagesSeen, isEmpty);

    await tester.tap(find.byTooltip('Revoir le tuto de Tiko'));
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Commence par cet écran avant d\'ouvrir la caisse'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Tiko page help appears once and remains manually available',
      (tester) async {
    final controller = _MemoryAppController()..tutorialWelcomeSeen = true;
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Finder railLabel(String label) => find.descendant(
          of: find.byType(NavigationRail),
          matching: find.text(label),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(controller: controller, licenseService: _MockLicenseService()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pour faire une vente'), findsOneWidget);
    expect(controller.tutorialPagesSeen, contains(AppTabIds.sales));

    await tester.tap(find.byTooltip('Fermer le tuto'));
    await tester.pumpAndSettle();
    await tester.tap(railLabel('Participants'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Avant de vendre, ajoute ici les joueurs'),
        findsOneWidget);
    expect(controller.tutorialPagesSeen, contains(AppTabIds.players));

    await tester.tap(find.byTooltip('Fermer le tuto'));
    await tester.pumpAndSettle();
    await tester.tap(railLabel('Vente'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Fermer le tuto'), findsNothing);

    await tester.tap(find.byTooltip('Revoir le tuto de Tiko'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pour faire une vente'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('article dialog adds item without framework exception',
      (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: ArticlesPricePage(controller: controller)),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ajouter').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Patch test');
    await tester.enterText(find.byType(TextField).at(2), '2.50');
    await tester.enterText(find.byType(TextField).at(3), '2.00');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();

    expect(controller.articles.single.name, 'Patch test');
    expect(tester.takeException(), isNull);
  });

  testWidgets('category dialog adds category without framework exception',
      (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: ArticlesPricePage(controller: controller)),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ajouter').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Patch catégorie');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();

    expect(controller.articleCategories, contains('PATCH CATÉGORIE'));
    expect(tester.takeException(), isNull);
  });

  test('REPAS category visibility follows the meals module', () {
    final controller = _MemoryAppController();

    expect(controller.managedArticleCategories, contains('REPAS'));
    expect(controller.isProtectedArticleCategory('REPAS'), isTrue);
    expect(controller.isProtectedArticleCategory('repas'), isTrue);

    controller.appSettings =
        controller.appSettings.copyWith(mealsEnabled: false);

    expect(controller.managedArticleCategories, isNot(contains('REPAS')));
    expect(controller.managedArticleCategories, contains('BOISSONS'));
  });

  test('REPAS category cannot be renamed from the controller', () async {
    final controller = _MemoryAppController();

    await controller.renameArticleCategory('REPAS', 'MENU');
    await controller.renameArticleCategory('BOISSONS', 'REPAS');

    expect(controller.articleCategories, contains('REPAS'));
    expect(controller.articleCategories, isNot(contains('MENU')));
    expect(controller.articleCategories, contains('BOISSONS'));
  });

  testWidgets('REPAS category is locked in Articles & Prix', (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: ArticlesPricePage(controller: controller)),
      ),
    );

    expect(find.text('REPAS'), findsWidgets);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pumpAndSettle();

    expect(find.text('Modifier catégorie'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('REPAS hidden from Articles & Prix when meals disabled',
      (tester) async {
    final controller = _MemoryAppController();
    controller.appSettings =
        controller.appSettings.copyWith(mealsEnabled: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: ArticlesPricePage(controller: controller)),
      ),
    );

    expect(find.text('REPAS'), findsNothing);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(find.text('BOISSONS'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('article dialog hides REPAS when meals disabled',
      (tester) async {
    final controller = _MemoryAppController();
    controller.appSettings =
        controller.appSettings.copyWith(mealsEnabled: false);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: ArticlesPricePage(controller: controller)),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Ajouter').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('REPAS'), findsNothing);
    expect(find.text('BOISSONS'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

testWidgets('player dialog adds participant without email', (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(controller: controller, licenseService: _MockLicenseService()),
      ),
    );

    await tester.tap(find.text('Ajouter un participant'));
    await tester.pumpAndSettle();
    // Use more specific finders to target the dialog's TextFields
    await tester.enterText(find.widgetWithText(TextField, 'Prénom'), 'Alice');
    await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Martin');
    await tester.tap(find.text('Enregistrer'));
    await tester.pump(kThemeAnimationDuration);
    await tester.pumpAndSettle();

    expect(controller.players.single.name, 'Alice Martin');
    expect(controller.players.single.email, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existing participant dropdown fits large text', (tester) async {
    final controller = _MemoryAppController()
      ..allPlayers = [
        Player(
          id: 'known-player',
          name: 'burn out',
          firstName: 'burn',
          lastName: 'out',
          type: 'membre',
        ),
      ];

    tester.view.physicalSize = const Size(674, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.35)),
          child: Scaffold(body: PlayersPage(controller: controller)),
        ),
      ),
    );

    await tester.tap(find.text('Ajouter un participant'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('burn out').last);
    await tester.pumpAndSettle();

    expect(find.text('burn'), findsOneWidget);
    expect(find.text('out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sales page mobile layout does not overflow', (tester) async {
    final controller = _MemoryAppController()
      ..players = [
        Player(id: 'player-1', name: 'Alice Dupont', type: 'public'),
        Player(id: 'player-2', name: 'Bob Martin', type: 'membre'),
      ]
      ..articles = [
        Article(
          id: 'drink-1',
          category: 'BOISSONS',
          type: 'standard',
          icon: 'B',
          name: 'Boisson',
          price: 2,
          memberPrice: 1.5,
          stock: 20,
          threshold: 5,
        ),
        Article(
          id: 'goodie-1',
          category: 'GOODIES',
          type: 'standard',
          icon: 'G',
          name: 'Goodie',
          price: 5,
          memberPrice: 4,
          stock: 10,
          threshold: 3,
        ),
      ];
    controller
      ..selectPlayer(controller.players.first)
      ..addToCart(controller.articles.first);

    tester.view.physicalSize = const Size(393, 783);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: CaissePage(controller: controller)),
      ),
    );

    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    final sheet = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet));
    expect(sheet.maxChildSize, 1);
    expect(find.text('Alice Dupont'), findsOneWidget);
    expect(find.text('Vider'), findsNothing);
    expect(find.text('ESP'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.drag(find.text('PANIER (1)'), const Offset(0, -620));
    await tester.pumpAndSettle();

    expect(find.text('Vider'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed mobile cart fits above Android system inset',
      (tester) async {
    final controller = _MemoryAppController()
      ..players = [
        Player(id: 'player-1', name: 'Alice Dupont', type: 'public'),
      ]
      ..articles = [
        Article(
          id: 'drink-1',
          category: 'BOISSONS',
          type: 'standard',
          icon: 'B',
          name: 'Boisson',
          price: 2,
          memberPrice: 1.5,
          stock: 20,
          threshold: 5,
        ),
      ];
    controller
      ..selectPlayer(controller.players.first)
      ..addToCart(controller.articles.first);

    tester.view.physicalSize = const Size(393, 892);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: MediaQuery(
          data: const MediaQueryData(
            padding: EdgeInsets.only(bottom: 24),
            textScaler: TextScaler.linear(1.1),
          ),
          child: Scaffold(body: CaissePage(controller: controller)),
        ),
      ),
    );

    expect(find.text('PANIER (1)'), findsOneWidget);
    expect(find.text('ESP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed mobile cart does not overflow when keyboard opens',
      (tester) async {
    final controller = _MemoryAppController()
      ..players = [
        Player(id: 'player-1', name: 'Alice Dupont', type: 'public'),
      ]
      ..articles = [
        Article(
          id: 'drink-1',
          category: 'BOISSONS',
          type: 'standard',
          icon: 'B',
          name: 'Boisson',
          price: 2,
          memberPrice: 1.5,
          stock: 20,
          threshold: 5,
        ),
      ];
    controller
      ..selectPlayer(controller.players.first)
      ..addToCart(controller.articles.first);

    tester.view.physicalSize = const Size(393, 783);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: CaissePage(controller: controller)),
      ),
    );

    await tester
        .tap(find.widgetWithText(TextField, 'Rechercher un participant'));
    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('PANIER (1)'), findsOneWidget);
    expect(find.text('ESP'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cart item list scrolls after seven lines', (tester) async {
    final articles = List.generate(
      8,
      (index) => Article(
        id: 'article-$index',
        category: 'BOISSONS',
        type: 'standard',
        icon: 'A',
        name: 'Article $index',
        price: 1,
        memberPrice: 1,
        stock: 20,
        threshold: 5,
      ),
    );
    final controller = _MemoryAppController()
      ..articles = articles
      ..cart = [
        for (final article in articles)
          CartItem(articleId: article.id, quantity: 1, price: article.price),
      ];

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 760,
            child: CartPanel(controller: controller),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('scrollable-cart-items')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile cart keeps checkout controls visible with many items',
      (tester) async {
    final articles = List.generate(
      12,
      (index) => Article(
        id: 'mobile-article-$index',
        category: 'BOISSONS',
        type: 'standard',
        icon: 'A',
        name: 'Article mobile $index',
        price: 1,
        memberPrice: 1,
        stock: 20,
        threshold: 5,
      ),
    );
    final controller = _MemoryAppController()
      ..players = [Player(id: 'player-1', name: 'Alice Dupont', type: 'public')]
      ..articles = articles
      ..cart = [
        for (final article in articles)
          CartItem(articleId: article.id, quantity: 1, price: article.price),
      ];
    controller.selectPlayer(controller.players.first);

    tester.view.physicalSize = const Size(393, 783);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(body: CaissePage(controller: controller)),
      ),
    );

    await tester.drag(find.text('PANIER (12)'), const Offset(0, -620));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('scrollable-cart-items')), findsOneWidget);
    final clearButtonBottom = tester.getRect(find.text('Vider')).bottom;
    expect(clearButtonBottom, lessThanOrEqualTo(783));
    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked device shows only the logout screen', (tester) async {
    final controller = _MemoryAppController()..tutorialWelcomeSeen = true;
    final license =
        _MockLicenseService(state: LicenseState.machineRevoked);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(controller: controller, licenseService: license),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LicenseBlockedPage), findsOneWidget);
    expect(find.byType(ActivationPage), findsNothing);
    expect(find.text('Se déconnecter'), findsOneWidget);
    expect(find.text('Se connecter'), findsNothing);
    expect(find.text("Cet appareil n'est plus autorisé"), findsOneWidget);
    expect(find.text('Ouvrir mon compte'), findsOneWidget);
    expect(find.textContaining('Réactivez-le depuis votre compte Tilly'),
        findsOneWidget);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();

    expect(license.loggedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('config account section shows the connected account',
      (tester) async {
    final controller = _MemoryAppController();
    final license = _MockLicenseService();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: Scaffold(
          body: ConfigPage(
            controller: controller,
            licenseService: license,
            updateResult: null,
            checkingUpdate: false,
            onCheckUpdate: () {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Compte'));
    await tester.pumpAndSettle();

    expect(find.text('contact@tilly.orceus.fr'), findsOneWidget);

    await tester.tap(find.text('Se déconnecter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();

    expect(license.loggedOut, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activation page explains a revoked machine', (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: ActivationPage(
          licenseService:
              _MockLicenseService(state: LicenseState.machineRevoked),
          controller: controller,
        ),
      ),
    );

    expect(find.text("Cet appareil n'est plus autorisé"), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activation page shows Tilly image and simple sign-in button',
      (tester) async {
    final controller = _MemoryAppController();

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: ActivationPage(
          licenseService: _MockLicenseService(),
          controller: controller,
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
    expect(find.text('Se connecter et activer'), findsNothing);
    expect(find.text('Tilli'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('read-only mode blocks business mutations', () async {
    final article = Article(
      id: 'article-1',
      category: 'BOISSONS',
      type: 'standard',
      icon: '',
      name: 'Eau',
      price: 2,
      memberPrice: 1.5,
      stock: 3,
      threshold: 1,
    );
    final player = Player(id: 'player-1', name: 'Participant', type: 'public');
    final controller = AppController()
      ..activeSession = SessionRecord(
        id: 'session-1',
        name: 'Session test',
        eventDate: DateTime(2026, 10, 1),
      )
      ..players = [player]
      ..articles = [article]
      ..readOnly = true;
    controller
      ..selectPlayer(player)
      ..addToCart(article);

    await expectLater(controller.checkout('ESP'), throwsStateError);
    expect(controller.sales, isEmpty);
    expect(article.stock, 3);
  });

  test('license account URL targets the site account page', () {
    expect(licenseAccountUrl, 'https://tilly.orceus.fr/compte');
  });

  test('machine id survives logout and re-login', () async {
    final storage = _MemorySecureStorage();
    final api = LicenseApiClient(
      client: MockClient((_) async => http.Response('{}', 404)),
    );
    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);

    await service.initialize();
    final machineId = storage.values['tilly_license_machine_id'];

    expect(machineId, isNotNull);
    expect(
      RegExp(r'^MCH-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
          .hasMatch(machineId!),
      isTrue,
    );

    await service.logout();
    expect(storage.values['tilly_license_machine_id'], machineId);

    final second = LicenseService(
      secureStorage: storage,
      apiClient: LicenseApiClient(
        client: MockClient((_) async => http.Response('{}', 404)),
      ),
    );
    addTearDown(second.dispose);
    await second.initialize();
    expect(storage.values['tilly_license_machine_id'], machineId);
  });

  test('logout clears locally without any server call', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: DateTime.now(),
      machineId: machineId,
      deviceSecret: secret,
    ));

    var calls = 0;
    var revokeCalled = false;
    final api = LicenseApiClient(
      client: MockClient((request) async {
        calls++;
        if (request.url.path.contains('deactivate')) revokeCalled = true;
        if (request.url.path.endsWith('/license/validate')) {
          return http.Response(
            await _licenseResponseBody(machineId),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    for (var attempt = 0; attempt < 50 && calls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(service.isLicensed, isTrue);
    expect(service.accountId, 'user-1');

    final callsBeforeLogout = calls;
    await service.logout();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(calls, callsBeforeLogout);
    expect(revokeCalled, isFalse);
    expect(service.isLicensed, isFalse);
    expect(service.accountId, isNull);
    expect(storage.values['tilly_license_auth_token'], isNull);
    expect(storage.values['tilly_license_envelope'], isNull);
  });

  test('license accounts use separate local datasets', () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-scope-');
    final database =
        LocalDatabase(databaseDirectoryOverride: tempDirectory.path);
    final controller = AppController(
      database: database,
      secureSettings: _MemorySecureStorage(),
    );
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    await controller.switchDataScope('account-a');
    await controller.load();
    await controller.addPlayer(
      firstName: 'Alice',
      lastName: 'Martin',
      email: '',
      type: 'public',
    );
    expect(controller.players, hasLength(1));

    await controller.switchDataScope('account-b');
    expect(controller.players, isEmpty);

    await controller.switchDataScope('account-a');
    expect(controller.players.single.name, 'Alice Martin');
  });

  test('first license account adopts the pre-scope local data', () async {
    final tempDirectory =
        await Directory.systemTemp.createTemp('tilly-adopt-');
    final legacy = LocalDatabase(databaseDirectoryOverride: tempDirectory.path);
    final legacyController = AppController(
      database: legacy,
      secureSettings: _MemorySecureStorage(),
    );
    await legacyController.load();
    await legacyController.addPlayer(
      firstName: 'Alice',
      lastName: 'Martin',
      email: '',
      type: 'public',
    );
    await legacy.close();

    final database =
        LocalDatabase(databaseDirectoryOverride: tempDirectory.path);
    final controller = AppController(
      database: database,
      secureSettings: _MemorySecureStorage(),
    );
    addTearDown(() async {
      await database.close();
      await tempDirectory.delete(recursive: true);
    });

    await controller.switchDataScope('account-a');
    await controller.load();
    expect(controller.players.single.name, 'Alice Martin');

    await controller.switchDataScope('account-b');
    expect(controller.players, isEmpty);
  });

  test('revoked machine activation is terminal with a single call', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId;

    var loginCalls = 0;
    var activateCalls = 0;
    var reactivateCalls = 0;
    String? activateMachineId;
    final api = LicenseApiClient(
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.contains('reactivate')) reactivateCalls++;
        if (path.endsWith('/auth/login')) {
          loginCalls++;
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'user': {'id': 'user-1', 'email': 'user@example.com'},
              'token': 'token-1',
              'expiresAt': '2026-10-08T12:00:00.000Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (path.endsWith('/license/activate')) {
          activateCalls++;
          activateMachineId =
              (jsonDecode(request.body) as Map)['machineId'] as String?;
          return http.Response(
            '{"type":"machine_revoked","title":"Appareil révoqué","status":403,'
            '"state":"MACHINE_REVOKED","detail":"Cet appareil a été révoqué."}',
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    final result = await service.loginAndActivate(
      email: 'user@example.com',
      password: 'secret-password',
    );

    expect(result.state, LicenseState.machineRevoked);
    expect(result.error, isNotNull);
    expect(loginCalls, 1);
    expect(activateCalls, 1);
    expect(reactivateCalls, 0);
    expect(activateMachineId, machineId);
    expect(service.isBlocked, isTrue);

    await service.validateOnline();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(activateCalls, 1);
    expect(reactivateCalls, 0);
  });

  test('revoked machine stops further network attempts', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now().subtract(const Duration(hours: 7)),
      lastServerTime: DateTime.now().subtract(const Duration(hours: 7)),
      machineId: machineId,
      deviceSecret: secret,
    ));

    var validateCalls = 0;
    var otherCalls = 0;
    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          validateCalls++;
          return http.Response(
            '{"type":"machine_revoked","title":"Appareil révoqué","status":403,'
            '"state":"MACHINE_REVOKED","detail":"Cet appareil a été révoqué."}',
            403,
            headers: {'content-type': 'application/json'},
          );
        }
        otherCalls++;
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    for (var attempt = 0; attempt < 50 && validateCalls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(validateCalls, 1);
    expect(service.currentState, LicenseState.machineRevoked);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(validateCalls, 1);
    expect(otherCalls, 0);

    await service.validateOnline();
    expect(validateCalls, 1);
  });

  test('license validates online at every app startup', () async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
      lastServerTime: DateTime.now().subtract(const Duration(minutes: 5)),
      machineId: machineId,
      deviceSecret: secret,
    ));

    var validateCalls = 0;
    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          validateCalls++;
          return http.Response(
            await _licenseResponseBody(machineId),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();

    for (var attempt = 0; attempt < 50 && validateCalls == 0; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(validateCalls, 1);
    expect(service.isLicensed, isTrue);
  });

  test('license skips startup validation without a session', () async {
    final storage = _MemorySecureStorage();
    var validateCalls = 0;
    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) validateCalls++;
        return http.Response('{}', 404);
      }),
    );

    final service = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    addTearDown(service.dispose);
    await service.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(validateCalls, 0);
    expect(service.isLicensed, isFalse);
  });

  testWidgets('license banner is hidden while the license is valid',
      (tester) async {
    final controller = _MemoryAppController()
      ..tutorialWelcomeSeen = true
      ..tutorialPagesSeen = {...AppTabIds.configurable, AppTabIds.sales};

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(
          controller: controller,
          licenseService: _MockLicenseService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Connexion Internet nécessaire pour vérifier votre licence'),
      findsNothing,
    );
    expect(find.text('Se connecter'), findsNothing);
    expect(find.textContaining('Mode hors ligne'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validation hiccup does not show the login page', (tester) async {
    const machineId = 'MCH-8f14e45f-ceea-467a-9a3c-1b2d3e4f5a6b';
    final storage = _MemorySecureStorage()
      ..values['tilly_license_machine_id'] = machineId
      ..values['tilly_license_auth_token'] = 'token-1';
    final store = LicenseStore(storage);
    final secret = await store.getOrCreateDeviceSecret();
    await store.saveEnvelope(await _licenseEnvelope(machineId: machineId));
    await store.saveState(await store.signState(
      lastValidatedAt: DateTime.now(),
      lastServerTime: DateTime.now(),
      machineId: machineId,
      deviceSecret: secret,
    ));

    final api = LicenseApiClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/license/validate')) {
          return http.Response('<html>404</html>', 404);
        }
        return http.Response('{}', 404);
      }),
    );

    final license = LicenseService(
      secureStorage: storage,
      apiClient: api,
      verifier: _testVerifier(),
    );
    await license.initialize();

    final controller = _MemoryAppController()
      ..tutorialWelcomeSeen = true
      ..tutorialPagesSeen = {...AppTabIds.configurable, AppTabIds.sales};

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(controller: controller, licenseService: license),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActivationPage), findsNothing);
    expect(license.isLicensed, isTrue);
    expect(tester.takeException(), isNull);

    license.dispose();
  });

  testWidgets('version banner appears when the version is not covered',
      (tester) async {
    final controller = _MemoryAppController()
      ..tutorialWelcomeSeen = true
      ..tutorialPagesSeen = {...AppTabIds.configurable, AppTabIds.sales};

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(
          controller: controller,
          licenseService: _MockLicenseService(
            state: LicenseState.versionNotCovered,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActivationPage), findsNothing);
    expect(
      find.textContaining('couvre Tilly jusqu\'à la version 2.1'),
      findsOneWidget,
    );
    expect(find.text('Télécharger la version 2.1'), findsOneWidget);
    expect(controller.readOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('license banner appears when online validation is required',
      (tester) async {
    final controller = _MemoryAppController()
      ..tutorialWelcomeSeen = true
      ..tutorialPagesSeen = {...AppTabIds.configurable, AppTabIds.sales};

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: RootShell(
          controller: controller,
          licenseService: _MockLicenseService(
            state: LicenseState.serverValidationRequired,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActivationPage), findsNothing);
    expect(
      find.text('Connexion Internet nécessaire pour vérifier votre licence'),
      findsOneWidget,
    );
    expect(find.text('Se connecter'), findsOneWidget);
    expect(controller.readOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('activation page does not overflow with keyboard and error',
      (tester) async {
    final controller = _MemoryAppController();

    tester.view.physicalSize = const Size(393, 783);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        theme: caisseTheme(AppColors.accent),
        home: ActivationPage(
          licenseService: _MockLicenseService(),
          controller: controller,
        ),
      ),
    );

    await tester.tap(find.text('Se connecter'));
    await tester.pump();

    expect(find.text('Renseigne ton e-mail et ton mot de passe.'),
        findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 360);
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}

Sale _sale({required String id}) => Sale(
      id: id,
      playerId: 'player-1',
      playerName: 'Participant',
      playerType: 'public',
      tariff: 'public',
      items: [
        SaleItem(
          articleId: 'article-1',
          name: 'Eau',
          icon: '',
          type: 'standard',
          quantity: 1,
          price: 2,
          publicPrice: 2,
          memberPrice: 1.5,
        ),
      ],
      totalArticles: 2,
      donation: 0,
      payment: 'ESP',
      session: 'session-1',
      createdAt: DateTime(2026, 7, 18, 10),
    );

Map<String, dynamic> _validModernBackup() => {
      'version': 3,
      'data': {
        'sessions': [
          {
            'id': 'session-1',
            'name': 'Session test',
            'event_date': '2026-07-18T00:00:00',
            'status': 'open',
            'created_at': '2026-07-18T00:00:00',
          }
        ],
        'players': <Map<String, Object?>>[],
        'sessionPlayers': <Map<String, Object?>>[],
        'articleCategories': <Map<String, Object?>>[],
        'articles': <Map<String, Object?>>[],
        'sales': <Map<String, Object?>>[],
        'saleItems': <Map<String, Object?>>[],
        'mealOrders': <Map<String, Object?>>[],
        'stockMovements': <Map<String, Object?>>[],
        'cashCounts': <Map<String, Object?>>[],
        'cashCountLines': <Map<String, Object?>>[],
        'appSettings': <Map<String, Object?>>[],
      },
    };

Map<String, dynamic> _backupPayloadWithHelloAssoSecret(String secret) {
  final settings = HelloAssoSettings(
    organizationSlug: 'tilly',
    clientId: 'client',
    clientSecret: secret,
    environment: 'sandbox',
  );
  return {
    'version': 3,
    'data': {
      'sessions': [
        {'id': 'session-test'}
      ],
      'articles': <Map<String, Object?>>[],
      'appSettings': [
        {
          'key': 'helloasso_settings',
          'value': jsonEncode(settings.toJson()),
          'updated_at': '2026-07-18T00:00:00',
        },
      ],
    },
  };
}

HelloAssoSettings _helloAssoSettingsFromPayload(Map<String, dynamic> payload) {
  final data = Map<String, dynamic>.from(payload['data'] as Map);
  final rows = data['appSettings'] as List;
  final row = rows.whereType<Map>().firstWhere(
      (entry) => entry['key'] == 'helloasso_settings',
      orElse: () => const {});
  return HelloAssoSettings.fromJson(
      Map<String, dynamic>.from(jsonDecode('${row['value'] ?? '{}'}') as Map));
}

Future<LicenseEnvelope> _licenseEnvelope({
  required String machineId,
  String licenseType = 'LIFETIME',
  String? coveredVersion = '9.9',
  String? userId = 'user-1',
  DateTime? licenseValidUntil,
  DateTime? offlineValidUntil,
  List<String> features = const ['sales'],
  DateTime? issuedAt,
}) async {
  final issued = issuedAt ?? DateTime.utc(2026, 10, 1, 12);
  final payloadBytes = utf8.encode(jsonEncode({
    'version': 1,
    'licenseId': 'license-1',
    'userId': userId,
    'machineId': machineId,
    'product': 'tilly',
    'licenseType': licenseType,
    'coveredVersion': coveredVersion,
    'issuedAt': issued.toIso8601String(),
    'serverTime': issued.toIso8601String(),
    'licenseValidUntil': licenseValidUntil?.toIso8601String(),
    'offlineValidUntil': offlineValidUntil?.toIso8601String(),
    'features': features,
  }));
  final signature =
      await Ed25519().sign(payloadBytes, keyPair: _licenseKeyPair);
  return LicenseEnvelope(
    kid: 'k1',
    payload: base64Url.encode(payloadBytes),
    signature: base64Url.encode(signature.bytes),
  );
}

Future<String> _licenseResponseBody(String machineId) async {
  final envelope = await _licenseEnvelope(machineId: machineId);
  return jsonEncode({
    'data': {
      'granted': true,
      'state': 'VALID',
      'license': envelope.toJson(),
      'machine': {
        'machineId': machineId,
        'platform': 'ANDROID',
        'appVersion': '1.0.0',
        'firstSeenAt': '2026-10-01T12:00:00.000Z',
        'lastSeenAt': '2026-10-01T12:00:00.000Z',
        'revokedAt': null,
        'revokedReason': null,
      },
    },
  });
}
