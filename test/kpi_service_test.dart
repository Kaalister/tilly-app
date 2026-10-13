import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  late TestAppController controller;

  setUp(() {
    controller = TestAppController();
  });

  KpiRow rowFor(
    List<KpiRow> rows,
    String articleId,
  ) =>
      rows.firstWhere((row) => row.article.id == articleId);

  group('compareKpiRows', () {
    KpiRow row({required Article article, double rotation = 0}) => KpiRow(
        article, 0, 0, 0, 0, 0, article.stock, article.stock, rotation, 0);

    test('orders ruptures before alerts before healthy stock', () {
      final rupture = row(article: testArticle(id: 'r', stock: 0, threshold: 2));
      final alert = row(article: testArticle(id: 'a', stock: 2, threshold: 2));
      final healthy = row(article: testArticle(id: 'h', stock: 9, threshold: 2));
      final rows = [healthy, alert, rupture]..sort(compareKpiRows);
      expect(rows.map((entry) => entry.article.id), ['r', 'a', 'h']);
    });

    test('breaks ties by rotation descending', () {
      final slow =
          row(article: testArticle(id: 'slow', stock: 5, threshold: 2), rotation: 0.1);
      final fast =
          row(article: testArticle(id: 'fast', stock: 5, threshold: 2), rotation: 0.9);
      final rows = [slow, fast]..sort(compareKpiRows);
      expect(rows.first.article.id, 'fast');
    });
  });

  test('aggregates sold quantities and revenue per article', () {
    final soda = testArticle(id: 'soda', stock: 6, threshold: 2);
    controller.articles = [soda];
    controller.sales = [
      testSale(items: [testSaleItem(articleId: 'soda', quantity: 2, price: 2.5)]),
      testSale(
          id: 'sale-2',
          items: [testSaleItem(articleId: 'soda', quantity: 1, price: 2.5)]),
    ];
    final row = rowFor(kpiRows(controller), 'soda');
    expect(row.sold, 3);
    expect(row.ca, 7.5);
    expect(row.outgoing, 3);
    expect(row.stockRest, 6);
    expect(row.stockInitial, 9);
    expect(row.rotation, closeTo(3 / 9, 1e-9));
  });

  test('ignores cancelled sales unless explicitly passed', () {
    final soda = testArticle(id: 'soda', stock: 6, threshold: 2);
    controller.articles = [soda];
    final cancelled = testSale(
      items: [testSaleItem(articleId: 'soda', quantity: 5, price: 2.5)],
      status: 'cancelled',
    );
    controller.sales = [cancelled];
    expect(rowFor(kpiRows(controller), 'soda').sold, 0);

    final explicit = kpiRows(controller, sales: [cancelled]);
    expect(rowFor(explicit, 'soda').sold, 5);
  });

  test('only tracked articles produce rows', () {
    controller.articles = [
      testArticle(id: 'soda', stock: 5, threshold: 2),
      testArticle(id: 'libre', stock: 5, threshold: 0),
      testArticle(id: 'location', type: 'location', stock: 0, threshold: 0),
      testArticle(id: 'repas', category: 'REPAS', stock: 5, threshold: 2),
    ];
    final ids = kpiRows(controller).map((row) => row.article.id).toList();
    expect(ids, ['soda', 'repas']);
  });

  test('meal consumption is counted when the module is enabled', () {
    final repas = testArticle(id: 'repas', stock: 8, threshold: 2);
    final drink = testArticle(id: 'drink', stock: 5, threshold: 2);
    controller.articles = [repas, drink];
    controller.meals = [
      testMeal(status: 'served', mealArticleId: 'repas', drinkArticleId: 'drink'),
      testMeal(id: 'meal-2', status: 'prepared', mealArticleId: 'repas'),
      testMeal(id: 'meal-3', status: 'planned', mealArticleId: 'repas'),
    ];
    final rows = kpiRows(controller);
    final repasRow = rowFor(rows, 'repas');
    expect(repasRow.mealUsed, 2);
    expect(repasRow.outgoing, 2);
    expect(repasRow.stockInitial, 10);
    expect(rowFor(rows, 'drink').mealUsed, 1);
  });

  test('meal consumption is ignored when the module is disabled', () {
    final repas = testArticle(id: 'repas', stock: 8, threshold: 2);
    controller.articles = [repas];
    controller.appSettings = controller.appSettings.copyWith(mealsEnabled: false);
    controller.meals = [
      testMeal(status: 'served', mealArticleId: 'repas'),
    ];
    final row = rowFor(kpiRows(controller), 'repas');
    expect(row.mealUsed, 0);
    expect(row.outgoing, 0);
  });

  test('onsite meal sales do not double count the meal article', () {
    final repas = testArticle(id: 'repas', stock: 8, threshold: 2);
    controller.articles = [repas];
    controller.meals = [
      testMeal(
          status: 'served', source: 'onsite', saleId: 'sale-meal',
          mealArticleId: 'repas'),
    ];
    controller.sales = [
      testSale(
        id: 'sale-meal',
        items: [testSaleItem(articleId: 'repas', quantity: 1, price: 7)],
        totalArticles: 7,
      ),
    ];
    final row = rowFor(kpiRows(controller), 'repas');
    expect(row.sold, 1);
    expect(row.ca, 7);
    expect(row.mealUsed, 1);
    expect(row.outgoing, 1);
    expect(row.stockInitial, 9);
  });

  test('association consumption is counted, restocks are not', () {
    final soda = testArticle(id: 'soda', stock: 6, threshold: 2);
    controller.articles = [soda];
    controller.stockMovements = [
      testStockMovement(
          id: 'm1',
          articleId: 'soda',
          movementType: 'association',
          quantityDelta: -3,
          stockBefore: 9,
          stockAfter: 6),
      testStockMovement(
          id: 'm2',
          articleId: 'soda',
          movementType: 'association',
          quantityDelta: 5,
          stockBefore: 6,
          stockAfter: 11),
    ];
    final row = rowFor(kpiRows(controller), 'soda');
    expect(row.associationUsed, 3);
    expect(row.outgoing, 3);
    expect(row.stockInitial, 9);
  });

  test('stock initial comes from the first movement chronologically', () {
    final soda = testArticle(id: 'soda', stock: 6, threshold: 2);
    controller.articles = [soda];
    controller.stockMovements = [
      testStockMovement(
          id: 'later',
          articleId: 'soda',
          quantityDelta: -2,
          stockBefore: 8,
          stockAfter: 6,
          createdAt: DateTime(2026, 7, 17, 10)),
      testStockMovement(
          id: 'first',
          articleId: 'soda',
          quantityDelta: -2,
          stockBefore: 10,
          stockAfter: 8,
          createdAt: DateTime(2026, 7, 16, 10)),
    ];
    expect(rowFor(kpiRows(controller), 'soda').stockInitial, 10);
  });

  test('suggestion scales with the number of active days', () {
    final soda = testArticle(id: 'soda', stock: 6, threshold: 2);
    controller.articles = [soda];
    controller.sales = [
      testSale(
          items: [testSaleItem(articleId: 'soda', quantity: 2, price: 2.5)],
          createdAt: DateTime(2026, 7, 16, 10)),
      testSale(
          id: 'sale-2',
          items: [testSaleItem(articleId: 'soda', quantity: 2, price: 2.5)],
          createdAt: DateTime(2026, 7, 17, 10)),
    ];
    final row = rowFor(kpiRows(controller), 'soda');
    expect(row.outgoing, 4);
    expect(row.stockInitial, 10);
    expect(row.suggestion, 3);

    controller.sales = [controller.sales.first];
    expect(rowFor(kpiRows(controller), 'soda').suggestion, 3);
  });

  test('a zero initial stock avoids a division by zero', () {
    final soda = testArticle(id: 'soda', stock: 0, threshold: 2);
    controller.articles = [soda];
    final row = rowFor(kpiRows(controller), 'soda');
    expect(row.stockInitial, 0);
    expect(row.rotation, 0);
    expect(row.suggestion, 0);
  });
}
