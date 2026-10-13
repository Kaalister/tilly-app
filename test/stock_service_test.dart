import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  late StockService service;

  setUp(() {
    service = StockService();
  });

  group('shortages', () {
    test('reports only insufficient articles', () {
      final low = testArticle(id: 'low', name: 'Eau', stock: 1);
      final ok = testArticle(id: 'ok', name: 'Soda', stock: 5);
      final shortages = service.shortages({low: 2, ok: 5});
      expect(shortages, hasLength(1));
      expect(shortages.single.article.id, 'low');
      expect(shortages.single.requiredQuantity, 2);
      expect(shortages.single.availableQuantity, 1);
    });

    test('is empty when everything is available', () {
      final article = testArticle(stock: 5);
      expect(service.shortages({article: 5}), isEmpty);
    });
  });

  group('cartRequirements', () {
    test('merges duplicate lines and ignores unknown articles', () {
      final soda = testArticle(id: 'soda', stock: 10);
      final requirements = service.cartRequirements([
        CartItem(articleId: 'soda', quantity: 2, price: 2),
        CartItem(articleId: 'soda', quantity: 1, price: 2),
        CartItem(articleId: 'inconnu', quantity: 5, price: 1),
      ], [soda]);
      expect(requirements, {soda: 3});
    });

    test('skips location and threshold-zero articles', () {
      final location =
          testArticle(id: 'location', type: 'location', threshold: 5);
      final freebie = testArticle(id: 'free', threshold: 0);
      final requirements = service.cartRequirements([
        CartItem(articleId: 'location', quantity: 1, price: 10),
        CartItem(articleId: 'free', quantity: 2, price: 0),
      ], [location, freebie]);
      expect(requirements, isEmpty);
    });
  });

  group('saleRequirements', () {
    test('matches by id first and falls back to the name', () {
      final soda = testArticle(id: 'soda', name: 'Soda', stock: 10);
      final requirements = service.saleRequirements(
        testSale(items: [
          testSaleItem(articleId: 'soda', name: 'Soda', quantity: 2),
          testSaleItem(articleId: 'ancien-id', name: 'Soda', quantity: 1),
        ]),
        [soda],
      );
      expect(requirements, {soda: 3});
    });
  });

  group('articleConsumption', () {
    test('returns the tracked quantity', () {
      final article = testArticle(stock: 10);
      expect(service.articleConsumption(article, 3), {article: 3});
    });

    test('is empty for untracked articles', () {
      final article = testArticle(threshold: 0);
      expect(service.articleConsumption(article, 3), isEmpty);
    });
  });

  group('applyDelta', () {
    test('a zero delta changes nothing and returns null', () {
      final article = testArticle(stock: 10);
      final movement = service.applyDelta(article, 0,
          sessionId: 'session-test', movementType: 'test', reason: 'test');
      expect(movement, isNull);
      expect(article.stock, 10);
    });

    test('refuses to go negative without mutating the stock', () {
      final article = testArticle(name: 'Bière', stock: 1);
      expect(
          () => service.applyDelta(article, -2,
              sessionId: 'session-test',
              movementType: 'sale',
              reason: 'Vente'),
          throwsA(isA<StateError>()
              .having((error) => error.message, 'message', contains('Bière'))));
      expect(article.stock, 1);
    });

    test('mutates the stock without a session and records nothing', () {
      final article = testArticle(stock: 10);
      final movement = service.applyDelta(article, -4, sessionId: null,
          movementType: 'sale', reason: 'Vente');
      expect(movement, isNull);
      expect(article.stock, 6);
    });

    test('records a complete movement with a session', () {
      final article = testArticle(id: 'soda', stock: 10);
      final movement = service.applyDelta(article, -3,
          sessionId: 'session-9',
          movementType: 'sale',
          reason: 'Vente',
          saleId: 'sale-9');
      expect(movement, isNotNull);
      expect(movement!.sessionId, 'session-9');
      expect(movement.articleId, 'soda');
      expect(movement.saleId, 'sale-9');
      expect(movement.movementType, 'sale');
      expect(movement.quantityDelta, -3);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 7);
      expect(movement.reason, 'Vente');
      expect(movement.id, startsWith('stock-'));
      expect(article.stock, 7);
    });

    test('allows restocking with positive deltas', () {
      final article = testArticle(stock: 1);
      final movement = service.applyDelta(article, 5,
          sessionId: 'session-test',
          movementType: 'restock',
          reason: 'Réassort');
      expect(movement!.quantityDelta, 5);
      expect(article.stock, 6);
    });
  });
}
