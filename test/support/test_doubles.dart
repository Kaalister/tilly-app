import 'package:tilly/tilly.dart';

class NoopDatabase extends LocalDatabase {
  @override
  Future<void> saveAll(PersistableAppState state,
      {bool markUpdated = true}) async {}

  @override
  Future<String?> findArticleReference(String articleId) async => null;

  @override
  Future<void> resetBusinessData() async {}
}

class NoopSecureSettings extends SecureSettingsService {
  @override
  Future<void> saveHelloAssoSecret(String value, {String? scope}) async {}

  @override
  Future<HelloAssoSettings> loadHelloAssoSettings(
          HelloAssoSettings storedSettings, {String? scope}) async =>
      storedSettings;
}

class TestAppController extends AppController {
  TestAppController({LocalDatabase? database})
      : super(
          database: database ?? NoopDatabase(),
          secureSettings: NoopSecureSettings(),
        ) {
    loading = false;
    activeSession = SessionRecord(
      id: 'session-test',
      name: 'Session test',
      eventDate: DateTime(2026, 7, 16),
    );
  }

  int persistCalls = 0;

  @override
  Future<void> load() async {
    loading = false;
    notifyListeners();
  }

  @override
  Future<void> persist({bool markUpdated = true}) async {
    persistCalls += 1;
  }
}

Article testArticle({
  String id = 'article-1',
  String category = 'BOISSONS',
  String type = 'standard',
  String icon = '🥤',
  String name = 'Soda',
  double price = 2.5,
  double memberPrice = 2,
  int stock = 10,
  int threshold = 2,
}) =>
    Article(
      id: id,
      category: category,
      type: type,
      icon: icon,
      name: name,
      price: price,
      memberPrice: memberPrice,
      stock: stock,
      threshold: threshold,
    );

Player testPlayer({
  String id = 'player-1',
  String name = 'Alice Martin',
  String type = 'membre',
  String firstName = 'Alice',
  String lastName = 'Martin',
  String email = 'alice@exemple.fr',
}) =>
    Player(
      id: id,
      name: name,
      type: type,
      firstName: firstName,
      lastName: lastName,
      email: email,
    );

SaleItem testSaleItem({
  String articleId = 'article-1',
  String name = 'Soda',
  int quantity = 1,
  double price = 2.5,
}) =>
    SaleItem(
      articleId: articleId,
      name: name,
      icon: '🥤',
      type: 'standard',
      quantity: quantity,
      price: price,
      publicPrice: 2.5,
      memberPrice: 2,
    );

Sale testSale({
  String id = 'sale-1',
  String playerId = 'player-1',
  String playerName = 'Alice Martin',
  String playerType = 'membre',
  String tariff = 'adherent',
  List<SaleItem>? items,
  double totalArticles = 2.5,
  double donation = 0,
  String payment = 'ESP',
  String session = 'session-test',
  DateTime? createdAt,
  String status = 'active',
}) =>
    Sale(
      id: id,
      playerId: playerId,
      playerName: playerName,
      playerType: playerType,
      tariff: tariff,
      items: items ?? [testSaleItem()],
      totalArticles: totalArticles,
      donation: donation,
      payment: payment,
      session: session,
      createdAt: createdAt ?? DateTime(2026, 7, 16, 12),
      status: status,
    );

MealOrder testMeal({
  String id = 'meal-1',
  String playerId = 'player-1',
  String playerName = 'Alice Martin',
  String playerType = 'membre',
  String source = 'helloasso',
  String status = 'planned',
  String saleId = '',
  String payment = '',
  String mealArticleId = 'repas-1',
  String drinkArticleId = '',
  String snackArticleId = '',
  String formula = 'Standard',
  List<String> options = const [],
  String note = '',
  DateTime? createdAt,
  DateTime? preparedAt,
  DateTime? servedAt,
}) =>
    MealOrder(
      id: id,
      playerId: playerId,
      playerName: playerName,
      playerType: playerType,
      source: source,
      status: status,
      saleId: saleId,
      payment: payment,
      mealArticleId: mealArticleId,
      drinkArticleId: drinkArticleId,
      snackArticleId: snackArticleId,
      formula: formula,
      options: List<String>.of(options),
      note: note,
      createdAt: createdAt ?? DateTime(2026, 7, 16, 12),
      preparedAt: preparedAt,
      servedAt: servedAt,
    );

StockMovement testStockMovement({
  String id = 'movement-1',
  String sessionId = 'session-test',
  String articleId = 'article-1',
  String? saleId,
  String movementType = 'sale',
  int quantityDelta = -1,
  int stockBefore = 10,
  int stockAfter = 9,
  String reason = 'Vente',
  DateTime? createdAt,
}) =>
    StockMovement(
      id: id,
      sessionId: sessionId,
      articleId: articleId,
      saleId: saleId,
      movementType: movementType,
      quantityDelta: quantityDelta,
      stockBefore: stockBefore,
      stockAfter: stockAfter,
      reason: reason,
      createdAt: createdAt ?? DateTime(2026, 7, 16, 12),
    );
