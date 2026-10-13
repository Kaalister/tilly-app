import '../domain/models.dart';
import 'meal_service.dart';

final _mealService = MealService();

class DemoDay {
  const DemoDay({
    required this.session,
    required this.players,
    required this.sales,
    required this.meals,
    required this.cashStart,
    required this.cashEnd,
    required this.stockMovements,
  });

  final SessionRecord session;
  final List<Player> players;
  final List<Sale> sales;
  final List<MealOrder> meals;
  final Map<String, int> cashStart;
  final Map<String, int> cashEnd;
  final List<StockMovement> stockMovements;
}

class DemoDataset {
  const DemoDataset({
    required this.categories,
    required this.articles,
    required this.players,
    required this.days,
  });

  final List<String> categories;
  final List<Article> articles;
  final List<Player> players;
  final List<DemoDay> days;
}

DemoDataset buildDemoDataset({DateTime? now}) {
  final reference = now ?? DateTime.now();
  final articles = _demoArticles();
  final players = _demoPlayers();
  final days = [
    _buildDay(
      reference: reference,
      dayOffset: -2,
      name: 'Journée 1',
      articles: articles,
      dayPlayers: players.sublist(0, 6),
      specs: _dayOneSales,
      mealSpecs: _dayOneMeals,
      cashStart: _cashStart,
      cashEnd: const {
        '50': 1,
        '20': 6,
        '10': 12,
        '5': 12,
        '2': 24,
        '1': 34,
      },
    ),
    _buildDay(
      reference: reference,
      dayOffset: -1,
      name: 'Journée 2',
      articles: articles,
      dayPlayers: players.sublist(2, 8),
      specs: _dayTwoSales,
      mealSpecs: _dayTwoMeals,
      cashStart: _cashStart,
      cashEnd: const {
        '50': 1,
        '20': 7,
        '10': 14,
        '5': 13,
        '2': 26,
        '1': 38,
      },
    ),
    _buildDay(
      reference: reference,
      dayOffset: 0,
      name: 'Journée 3',
      articles: articles,
      dayPlayers: players.sublist(4, 10),
      specs: _dayThreeSales,
      mealSpecs: _dayThreeMeals,
      cashStart: _cashStart,
      cashEnd: const {
        '50': 1,
        '20': 6,
        '10': 13,
        '5': 12,
        '2': 25,
        '1': 36,
      },
    ),
  ];
  return DemoDataset(
    categories: const ['BOISSONS', 'REPAS', 'SNACKING', 'GOODIES', 'LOCATION'],
    articles: articles,
    players: players,
    days: days,
  );
}

const _cashStart = <String, int>{
  '50': 0,
  '20': 5,
  '10': 10,
  '5': 10,
  '2': 20,
  '1': 30,
};

List<Article> _demoArticles() => [
      Article(
        id: makeId('article'),
        category: 'BOISSONS',
        type: 'standard',
        icon: '🥤',
        name: 'Eau 50cl',
        price: 1.5,
        memberPrice: 1,
        stock: 60,
        threshold: 12,
      ),
      Article(
        id: makeId('article'),
        category: 'BOISSONS',
        type: 'standard',
        icon: '🥤',
        name: 'Soda 33cl',
        price: 2.5,
        memberPrice: 2,
        stock: 48,
        threshold: 12,
      ),
      Article(
        id: makeId('article'),
        category: 'BOISSONS',
        type: 'standard',
        icon: '🍺',
        name: 'Bière pression',
        price: 3.5,
        memberPrice: 3,
        stock: 36,
        threshold: 10,
      ),
      Article(
        id: makeId('article'),
        category: 'SNACKING',
        type: 'standard',
        icon: '🍟',
        name: 'Chips',
        price: 2,
        memberPrice: 1.5,
        stock: 30,
        threshold: 8,
      ),
      Article(
        id: makeId('article'),
        category: 'SNACKING',
        type: 'standard',
        icon: '🍫',
        name: 'Barre chocolatée',
        price: 1.5,
        memberPrice: 1,
        stock: 40,
        threshold: 10,
      ),
      Article(
        id: makeId('article'),
        category: 'GOODIES',
        type: 'standard',
        icon: '🏷️',
        name: 'Patch association',
        price: 5,
        memberPrice: 4,
        stock: 25,
        threshold: 5,
      ),
      Article(
        id: makeId('article'),
        category: 'GOODIES',
        type: 'standard',
        icon: '👕',
        name: 'T-shirt association',
        price: 15,
        memberPrice: 12,
        stock: 12,
        threshold: 3,
      ),
      Article(
        id: makeId('article'),
        category: 'LOCATION',
        type: 'location',
        icon: '🔫',
        name: 'Location réplique',
        price: 10,
        memberPrice: 8,
        stock: 0,
        threshold: 0,
      ),
      Article(
        id: makeId('article'),
        category: 'LOCATION',
        type: 'standard',
        icon: '⚪',
        name: 'Billes 100g',
        price: 5,
        memberPrice: 4,
        stock: 30,
        threshold: 8,
      ),
      Article(
        id: makeId('article'),
        category: 'REPAS',
        type: 'standard',
        icon: '🍽️',
        name: 'Repas Standard',
        price: 8,
        memberPrice: 7,
        stock: 40,
        threshold: 10,
      ),
      Article(
        id: makeId('article'),
        category: 'REPAS',
        type: 'standard',
        icon: '🥗',
        name: 'Repas végétarien',
        price: 8,
        memberPrice: 7,
        stock: 15,
        threshold: 4,
      ),
    ];

List<Player> _demoPlayers() {
  const people = [
    ('Lucas', 'Martin', 'membre'),
    ('Emma', 'Bernard', 'public'),
    ('Hugo', 'Dubois', 'membre'),
    ('Léa', 'Thomas', 'public'),
    ('Nathan', 'Robert', 'public'),
    ('Chloé', 'Petit', 'membre'),
    ('Tom', 'Durand', 'public'),
    ('Manon', 'Leroy', 'public'),
    ('Théo', 'Moreau', 'membre'),
    ('Camille', 'Simon', 'public'),
  ];
  return [
    for (final (firstName, lastName, type) in people)
      Player(
        id: makeId('player'),
        name: playerNameFromParts(firstName, lastName, 'Participant'),
        type: type,
        firstName: firstName,
        lastName: lastName,
        email: '${firstName.toLowerCase()}.${lastName.toLowerCase()}@exemple.fr',
      ),
  ];
}

class _DemoSaleSpec {
  const _DemoSaleSpec({
    required this.player,
    required this.hour,
    required this.minute,
    required this.items,
    this.donation = 0,
    this.payment = 'ESP',
    this.cancelled = false,
  });

  final int player;
  final int hour;
  final int minute;
  final List<(int, int)> items;
  final double donation;
  final String payment;
  final bool cancelled;
}

const _dayOneSales = <_DemoSaleSpec>[
  _DemoSaleSpec(player: 0, hour: 10, minute: 45, items: [(0, 1), (3, 1)]),
  _DemoSaleSpec(player: 1, hour: 12, minute: 10, items: [(1, 2)], payment: 'SumUp'),
  _DemoSaleSpec(
      player: 2,
      hour: 12,
      minute: 30,
      items: [(3, 1)],
      cancelled: true),
  _DemoSaleSpec(player: 3, hour: 13, minute: 5, items: [(5, 1)], donation: 1),
  _DemoSaleSpec(player: 4, hour: 14, minute: 20, items: [(2, 1), (4, 1)]),
  _DemoSaleSpec(player: 5, hour: 15, minute: 40, items: [(6, 1)], payment: 'PayPal'),
  _DemoSaleSpec(player: 0, hour: 16, minute: 30, items: [(7, 1)]),
];

const _dayTwoSales = <_DemoSaleSpec>[
  _DemoSaleSpec(player: 1, hour: 11, minute: 15, items: [(1, 1), (4, 1)]),
  _DemoSaleSpec(player: 2, hour: 12, minute: 40, items: [(8, 1)], payment: 'SumUp'),
  _DemoSaleSpec(player: 3, hour: 13, minute: 25, items: [(2, 2)]),
  _DemoSaleSpec(player: 4, hour: 14, minute: 50, items: [(0, 2), (3, 1)], donation: 2),
  _DemoSaleSpec(player: 5, hour: 16, minute: 5, items: [(5, 1), (4, 1)], payment: 'PayPal'),
  _DemoSaleSpec(player: 1, hour: 17, minute: 10, items: [(6, 1)]),
  _DemoSaleSpec(player: 2, hour: 17, minute: 30, items: [(7, 1)], payment: 'SumUp'),
];

const _dayThreeSales = <_DemoSaleSpec>[
  _DemoSaleSpec(player: 0, hour: 10, minute: 30, items: [(0, 1), (4, 1)]),
  _DemoSaleSpec(player: 1, hour: 12, minute: 0, items: [(3, 2), (1, 2)], payment: 'SumUp'),
  _DemoSaleSpec(player: 2, hour: 13, minute: 15, items: [(5, 1)], donation: 1),
  _DemoSaleSpec(player: 3, hour: 14, minute: 35, items: [(8, 1), (0, 1)], payment: 'PayPal'),
  _DemoSaleSpec(player: 4, hour: 15, minute: 20, items: [(2, 1), (3, 1)]),
  _DemoSaleSpec(player: 5, hour: 16, minute: 45, items: [(7, 1)], payment: 'SumUp'),
  _DemoSaleSpec(player: 0, hour: 17, minute: 25, items: [(1, 1), (4, 2)]),
];

class _DemoMealSpec {
  const _DemoMealSpec({
    required this.player,
    required this.hour,
    required this.minute,
    required this.source,
    required this.status,
    required this.meal,
    this.payment = 'ESP',
    this.formula = 'Standard',
    this.options = const [],
    this.note = '',
    this.drink = -1,
    this.snack = -1,
  });

  final int player;
  final int hour;
  final int minute;
  final String source;
  final String status;
  final int meal;
  final String payment;
  final String formula;
  final List<String> options;
  final String note;
  final int drink;
  final int snack;
}

// Index des articles REPAS : 9 = Repas Standard, 10 = Repas végétarien.
const _dayOneMeals = <_DemoMealSpec>[
  _DemoMealSpec(
    player: 0,
    hour: 12,
    minute: 0,
    source: 'helloasso',
    status: 'served',
    meal: 9,
    drink: 0,
    snack: 4,
    options: ['Ketchup'],
  ),
  _DemoMealSpec(
    player: 1,
    hour: 12,
    minute: 20,
    source: 'helloasso',
    status: 'served',
    meal: 10,
    drink: 1,
    snack: 3,
    options: ['Sans porc'],
  ),
  _DemoMealSpec(
    player: 3,
    hour: 13,
    minute: 10,
    source: 'onsite',
    status: 'served',
    meal: 9,
    drink: 2,
    snack: 4,
    note: 'Achat sur place',
  ),
];

const _dayTwoMeals = <_DemoMealSpec>[
  _DemoMealSpec(
    player: 1,
    hour: 12,
    minute: 30,
    source: 'helloasso',
    status: 'served',
    meal: 9,
    drink: 1,
    snack: 4,
    options: ['Sans sauce'],
  ),
  _DemoMealSpec(
    player: 2,
    hour: 13,
    minute: 0,
    source: 'onsite',
    status: 'served',
    meal: 10,
    drink: 0,
    formula: 'Boisson seule',
    note: 'Achat sur place',
  ),
  _DemoMealSpec(
    player: 4,
    hour: 13,
    minute: 45,
    source: 'helloasso',
    status: 'served',
    meal: 9,
    drink: 2,
    snack: 3,
  ),
];

const _dayThreeMeals = <_DemoMealSpec>[
  _DemoMealSpec(
    player: 0,
    hour: 12,
    minute: 15,
    source: 'helloasso',
    status: 'served',
    meal: 9,
    drink: 1,
    snack: 4,
    options: ['Mayonnaise'],
  ),
  _DemoMealSpec(
    player: 2,
    hour: 12,
    minute: 45,
    source: 'helloasso',
    status: 'prepared',
    meal: 10,
    drink: 0,
    snack: 3,
  ),
  _DemoMealSpec(
    player: 4,
    hour: 13,
    minute: 20,
    source: 'onsite',
    status: 'served',
    payment: 'PayPal',
    meal: 9,
    drink: 2,
    snack: 4,
    note: 'Achat sur place',
  ),
  _DemoMealSpec(
    player: 5,
    hour: 14,
    minute: 5,
    source: 'helloasso',
    status: 'planned',
    meal: 9,
    drink: 1,
    snack: 4,
    options: ['Allergie'],
    note: 'HelloAsso : allergie fruits à coque',
  ),
  _DemoMealSpec(
    player: 3,
    hour: 14,
    minute: 30,
    source: 'helloasso',
    status: 'cancelled',
    meal: 10,
    drink: 0,
    formula: 'Boisson seule',
    note: 'Absent',
  ),
];

DemoDay _buildDay({
  required DateTime reference,
  required int dayOffset,
  required String name,
  required List<Article> articles,
  required List<Player> dayPlayers,
  required List<_DemoSaleSpec> specs,
  required List<_DemoMealSpec> mealSpecs,
  required Map<String, int> cashStart,
  required Map<String, int> cashEnd,
}) {
  final date = DateTime(reference.year, reference.month, reference.day)
      .add(Duration(days: dayOffset));
  final session = SessionRecord(
    id: makeId('session'),
    name: name,
    eventDate: date,
    status: dayOffset < 0 ? 'closed' : 'open',
    createdAt: date.subtract(const Duration(hours: 2)),
    closedAt: dayOffset < 0 ? date.add(const Duration(hours: 21)) : null,
  );
  final sales = <Sale>[];
  final movements = <StockMovement>[];
  for (final spec in specs) {
    final player = dayPlayers[spec.player];
    final createdAt = DateTime(
        date.year, date.month, date.day, spec.hour, spec.minute);
    final saleId = makeId('sale');
    final items = <SaleItem>[];
    var total = 0.0;
    for (final (articleIndex, quantity) in spec.items) {
      final article = articles[articleIndex];
      final unitPrice = article.priceFor(player.isMember);
      items.add(SaleItem(
        articleId: article.id,
        name: article.name,
        icon: article.icon,
        type: article.type,
        quantity: quantity,
        price: unitPrice,
        publicPrice: article.price,
        memberPrice: article.memberPrice,
      ));
      total += unitPrice * quantity;
      if (!spec.cancelled && article.tracksStock) {
        final before = article.stock;
        article.stock = before - quantity;
        movements.add(StockMovement(
          id: makeId('movement'),
          sessionId: session.id,
          articleId: article.id,
          saleId: saleId,
          movementType: 'sale',
          quantityDelta: -quantity,
          stockBefore: before,
          stockAfter: article.stock,
          reason: 'Vente',
          createdAt: createdAt,
        ));
      }
    }
    sales.add(Sale(
      id: saleId,
      playerId: player.id,
      playerName: player.name,
      playerType: player.type,
      tariff: player.isMember ? 'membre' : 'public',
      items: items,
      totalArticles: total,
      donation: spec.donation,
      payment: spec.payment,
      session: session.id,
      createdAt: createdAt,
      status: spec.cancelled ? 'cancelled' : 'active',
      cancelledAt:
          spec.cancelled ? createdAt.add(const Duration(minutes: 5)) : null,
      cancellationReason: spec.cancelled ? 'Erreur de saisie' : '',
    ));
  }
  final meals = <MealOrder>[];
  for (final spec in mealSpecs) {
    final player = dayPlayers[spec.player];
    final createdAt = DateTime(
        date.year, date.month, date.day, spec.hour, spec.minute);
    final mealArticle = articles[spec.meal];
    final saleId = spec.source == 'onsite' ? makeId('sale') : '';
    final preparedAt = spec.status == 'prepared' || spec.status == 'served'
        ? createdAt.add(const Duration(minutes: 15))
        : null;
    final servedAt = spec.status == 'served'
        ? createdAt.add(const Duration(minutes: 25))
        : null;
    final meal = MealOrder(
      id: makeId('meal'),
      playerId: player.id,
      playerName: player.name,
      playerType: player.type,
      source: spec.source,
      status: spec.status,
      saleId: saleId,
      payment: spec.source == 'onsite' ? spec.payment : '',
      mealArticleId: mealArticle.id,
      drinkArticleId: spec.drink >= 0 ? articles[spec.drink].id : '',
      snackArticleId: spec.snack >= 0 ? articles[spec.snack].id : '',
      formula: spec.formula,
      options: List<String>.of(spec.options),
      note: spec.note,
      createdAt: createdAt,
      preparedAt: preparedAt,
      servedAt: servedAt,
      updatedAt: servedAt ?? preparedAt ?? createdAt,
    );
    if (meal.consumesStock) {
      for (final entry in meal.stockItems.entries) {
        final article =
            articles.where((item) => item.id == entry.key).first;
        final before = article.stock;
        article.stock = before - entry.value;
        movements.add(StockMovement(
          id: makeId('movement'),
          sessionId: session.id,
          articleId: article.id,
          saleId: saleId.isEmpty ? null : saleId,
          movementType: 'meal',
          quantityDelta: -entry.value,
          stockBefore: before,
          stockAfter: article.stock,
          reason: 'Repas ${meal.id}',
          createdAt: preparedAt ?? createdAt,
        ));
      }
    }
    if (meal.isOnsite) {
      sales.add(_mealService.saleForMeal(meal, player, articles,
          sessionId: session.id, createdAt: createdAt));
    }
    meals.add(meal);
  }
  return DemoDay(
    session: session,
    players: dayPlayers,
    sales: sales,
    meals: meals,
    cashStart: cashStart,
    cashEnd: cashEnd,
    stockMovements: movements,
  );
}
