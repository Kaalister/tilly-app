import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  late MealService service;
  late StockService stockService;
  final now = DateTime(2026, 7, 16, 12);

  setUp(() {
    service = MealService();
    stockService = StockService();
  });

  group('createMealOrder', () {
    test('a planned HelloAsso meal has no timestamps or sale id', () {
      final meal = service.createMealOrder(
        player: testPlayer(),
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas',
        drinkArticleId: 'boisson',
        snackArticleId: 'snack',
        formula: 'Standard',
        options: ['Ketchup'],
        note: '  note  ',
        now: now,
      );
      expect(meal.id, startsWith('meal-'));
      expect(meal.saleId, isEmpty);
      expect(meal.payment, isEmpty);
      expect(meal.note, 'note');
      expect(meal.preparedAt, isNull);
      expect(meal.servedAt, isNull);
      expect(meal.createdAt, now);
      expect(meal.updatedAt, now);
      expect(meal.playerName, 'Alice Martin');
      expect(meal.playerType, 'membre');
    });

    test('an onsite order receives a sale id and keeps the payment', () {
      final meal = service.createMealOrder(
        player: testPlayer(type: 'public'),
        source: 'onsite',
        status: 'served',
        mealArticleId: 'repas',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Boisson seule',
        options: const [],
        note: '',
        payment: 'SumUp',
        now: now,
      );
      expect(meal.saleId, startsWith('sale-'));
      expect(meal.payment, 'SumUp');
      expect(meal.isOnsite, isTrue);
      expect(meal.playerType, 'public');
    });

    test('prepared and served statuses drive the timestamps', () {
      final prepared = service.createMealOrder(
        player: testPlayer(),
        source: 'helloasso',
        status: 'prepared',
        mealArticleId: 'repas',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Standard',
        options: const [],
        note: '',
        now: now,
      );
      expect(prepared.preparedAt, now);
      expect(prepared.servedAt, isNull);

      final served = service.createMealOrder(
        player: testPlayer(),
        source: 'helloasso',
        status: 'served',
        mealArticleId: 'repas',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Standard',
        options: const [],
        note: '',
        now: now,
      );
      expect(served.preparedAt, now);
      expect(served.servedAt, now);
    });

    test('options are copied defensively', () {
      final source = <String>['Ketchup'];
      final meal = service.createMealOrder(
        player: testPlayer(),
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Standard',
        options: source,
        note: '',
        now: now,
      );
      source.add('Mayonnaise');
      expect(meal.options, ['Ketchup']);
    });
  });

  group('helloAssoMeal', () {
    test('prepends the meal label and stays planned', () {
      final meal = service.helloAssoMeal(
        player: testPlayer(),
        registrant: const HelloAssoRegistrant(
            firstName: 'Léa',
            lastName: 'Thomas',
            email: 'lea@exemple.fr',
            hasMeal: true,
            mealLabel: '  Menu enfant  '),
        mealArticle: testArticle(id: 'repas'),
        drinkArticle: testArticle(id: 'boisson'),
        snackArticle: testArticle(id: 'snack'),
      );
      expect(meal.source, 'helloasso');
      expect(meal.status, 'planned');
      expect(meal.note, 'HelloAsso : Menu enfant');
      expect(meal.formula, 'Standard');
      expect(meal.options, isEmpty);
      expect(meal.drinkArticleId, 'boisson');
      expect(meal.snackArticleId, 'snack');
      expect(meal.preparedAt, isNull);
      expect(meal.servedAt, isNull);
    });

    test('handles missing label and optional articles', () {
      final meal = service.helloAssoMeal(
        player: testPlayer(),
        registrant: const HelloAssoRegistrant(
            firstName: 'Léa', lastName: 'Thomas', email: 'lea@exemple.fr'),
        mealArticle: testArticle(id: 'repas'),
      );
      expect(meal.note, isEmpty);
      expect(meal.drinkArticleId, isEmpty);
      expect(meal.snackArticleId, isEmpty);
    });
  });

  group('saleForMeal', () {
    test('bills the member price with the adherent tariff', () {
      final meal = testMeal(saleId: 'sale-9', payment: 'ESP');
      final sale = service.saleForMeal(
        meal,
        testPlayer(type: 'membre'),
        [testArticle(id: 'repas-1', name: 'Repas', price: 8, memberPrice: 7)],
        sessionId: 'session-9',
        createdAt: now,
      );
      expect(sale.id, 'sale-9');
      expect(sale.tariff, 'adherent');
      expect(sale.payment, 'ESP');
      expect(sale.session, 'session-9');
      expect(sale.createdAt, now);
      expect(sale.donation, 0);
      expect(sale.totalArticles, 7);
      expect(sale.items.single.quantity, 1);
      expect(sale.items.single.price, 7);
      expect(sale.items.single.publicPrice, 8);
      expect(sale.items.single.memberPrice, 7);
    });

    test('bills the public price for non members', () {
      final sale = service.saleForMeal(
        testMeal(),
        testPlayer(type: 'public'),
        [testArticle(id: 'repas-1', price: 8, memberPrice: 7)],
      );
      expect(sale.tariff, 'public');
      expect(sale.totalArticles, 8);
      expect(sale.session, isEmpty);
    });

    test('throws when the meal article is unknown', () {
      expect(
          () => service.saleForMeal(testMeal(), testPlayer(), const []),
          throwsA(isA<StateError>().having(
              (error) => error.message, 'message', 'Article repas introuvable')));
    });
  });

  group('stockTransition', () {
    Article repas() => testArticle(id: 'repas-1', stock: 10);
    Article drink() => testArticle(id: 'drink-1', stock: 10);
    Article snack() => testArticle(id: 'snack-1', stock: 10);

    test('a planned meal consumes nothing', () {
      final articles = [repas(), drink(), snack()];
      final movements = service.stockTransition(
        null,
        testMeal(status: 'planned', drinkArticleId: 'drink-1'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, isEmpty);
      expect(articles.map((article) => article.stock), [10, 10, 10]);
    });

    test('preparing a meal consumes meal, drink and snack once', () {
      final articles = [repas(), drink(), snack()];
      final movements = service.stockTransition(
        null,
        testMeal(
            id: 'meal-9',
            status: 'prepared',
            drinkArticleId: 'drink-1',
            snackArticleId: 'snack-1'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, hasLength(3));
      expect(articles.map((article) => article.stock), [9, 9, 9]);
      expect(movements.map((movement) => movement.quantityDelta),
          everyElement(-1));
      expect(movements.first.movementType, 'meal');
      expect(movements.first.reason, 'Repas meal-9');
    });

    test('a duplicated article is consumed twice', () {
      final articles = [repas()];
      final movements = service.stockTransition(
        null,
        testMeal(status: 'served', drinkArticleId: 'repas-1'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, hasLength(1));
      expect(movements.single.quantityDelta, -2);
      expect(articles.single.stock, 8);
    });

    test('going back to planned restores the stock', () {
      final articles = [repas(), drink()];
      final previous = testMeal(status: 'served', drinkArticleId: 'drink-1');
      final movements = service.stockTransition(
        previous,
        testMeal(status: 'planned', drinkArticleId: 'drink-1'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, hasLength(2));
      expect(articles.map((article) => article.stock), [11, 11]);
    });

    test('cancelling a served meal restores the stock', () {
      final articles = [repas()];
      final movements = service.stockTransition(
        testMeal(status: 'served'),
        testMeal(status: 'cancelled'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements.single.quantityDelta, 1);
      expect(articles.single.stock, 11);
    });

    test('an unchanged status records no movement', () {
      final articles = [repas()];
      final movements = service.stockTransition(
        testMeal(status: 'prepared'),
        testMeal(status: 'prepared'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, isEmpty);
      expect(articles.single.stock, 10);
    });

    test('insufficient stock aborts before any mutation', () {
      final mealArticle = testArticle(id: 'repas-1', stock: 1);
      final drink = testArticle(id: 'drink-1', stock: 10);
      expect(
          () => service.stockTransition(
                null,
                // Same article in meal and drink -> requires 2.
                testMeal(
                    status: 'prepared',
                    mealArticleId: 'repas-1',
                    drinkArticleId: 'repas-1'),
                articles: [mealArticle, drink],
                stockService: stockService,
                sessionId: 'session-test',
              ),
          throwsA(isA<StateError>().having(
              (error) => error.message, 'message', contains('Stock insuffisant'))));
      expect(mealArticle.stock, 1);
      expect(drink.stock, 10);
    });

    test('unknown articles are skipped silently', () {
      final articles = [repas()];
      final movements = service.stockTransition(
        null,
        testMeal(status: 'prepared', drinkArticleId: 'inconnu'),
        articles: articles,
        stockService: stockService,
        sessionId: 'session-test',
      );
      expect(movements, hasLength(1));
      expect(articles.single.stock, 9);
    });

    test('a null session still consumes stock but records nothing', () {
      final articles = [repas()];
      final movements = service.stockTransition(
        null,
        testMeal(status: 'prepared'),
        articles: articles,
        stockService: stockService,
        sessionId: null,
      );
      expect(movements, isEmpty);
      expect(articles.single.stock, 9);
    });
  });
}
