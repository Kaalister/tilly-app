import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  late TestAppController controller;

  setUp(() {
    controller = TestAppController();
  });

  group('cart', () {
    test('addToCart is ignored without a selected player', () {
      controller.addToCart(testArticle());
      expect(controller.cart, isEmpty);
    });

    test('addToCart increments lines and applies the member price', () {
      final player = testPlayer(type: 'membre');
      controller.players = [player];
      controller.selectPlayer(player);
      final article = testArticle(price: 2.5, memberPrice: 2);
      controller.addToCart(article);
      controller.addToCart(article);
      expect(controller.cart, hasLength(1));
      expect(controller.cart.single.quantity, 2);
      expect(controller.cart.single.price, 2);
      expect(controller.cartCount, 2);
      expect(controller.cartArticlesTotal, 4);
    });

    test('toggleMemberTariff reprices the cart for public players', () {
      final player = testPlayer(type: 'public');
      controller.players = [player];
      final article = testArticle(price: 2.5, memberPrice: 2);
      controller.articles = [article];
      controller.selectPlayer(player);
      controller.addToCart(article);
      expect(controller.cart.single.price, 2.5);
      controller.toggleMemberTariff();
      expect(controller.memberTariff, isTrue);
      expect(controller.cart.single.price, 2);
    });

    test('changeCartQuantity removes lines at zero and ignores unknowns', () {
      final player = testPlayer();
      controller.players = [player];
      controller.selectPlayer(player);
      controller.addToCart(testArticle());
      controller.changeCartQuantity('inconnu', -1);
      expect(controller.cart, hasLength(1));
      controller.changeCartQuantity('article-1', -1);
      expect(controller.cart, isEmpty);
    });

    test('clearCart also resets the donation', () {
      controller.setDonation(5);
      controller.cart.add(CartItem(articleId: 'article-1', quantity: 1, price: 2));
      controller.clearCart();
      expect(controller.cart, isEmpty);
      expect(controller.donation, 0);
    });

    test('setDonation clamps negative values', () {
      controller.setDonation(-4);
      expect(controller.donation, 0);
      controller.setDonation(3.5);
      expect(controller.donation, 3.5);
      expect(controller.cartTotal, 3.5);
    });

    test('canCheckout requires a player, a cart and enough stock', () {
      expect(controller.canCheckout, isFalse);
      final player = testPlayer();
      controller.players = [player];
      controller.selectPlayer(player);
      expect(controller.canCheckout, isFalse);
      final article = testArticle(stock: 0);
      controller.articles = [article];
      controller.addToCart(article);
      expect(controller.cartStockShortages, hasLength(1));
      expect(controller.canCheckout, isFalse);
      article.stock = 5;
      expect(controller.canCheckout, isTrue);
    });
  });

  group('checkout', () {
    test('creates a sale, consumes stock and clears the cart', () async {
      final player = testPlayer(type: 'membre');
      final article = testArticle(stock: 10);
      controller.players = [player];
      controller.articles = [article];
      controller.selectPlayer(player);
      controller.addToCart(article);
      controller.setDonation(1);

      await controller.checkout('SumUp');

      expect(controller.sales, hasLength(1));
      final sale = controller.sales.single;
      expect(sale.playerId, player.id);
      expect(sale.tariff, 'adherent');
      expect(sale.payment, 'SumUp');
      expect(sale.donation, 1);
      expect(sale.session, 'session-test');
      expect(sale.items.single.quantity, 1);
      expect(sale.items.single.price, 2);
      expect(article.stock, 9);
      expect(controller.stockMovements, hasLength(1));
      expect(controller.stockMovements.single.movementType, 'sale');
      expect(controller.stockMovements.single.saleId, sale.id);
      expect(controller.cart, isEmpty);
      expect(controller.donation, 0);
      expect(controller.persistCalls, greaterThan(0));
    });

    test('refuses a checkout when stock is insufficient', () async {
      final player = testPlayer();
      final article = testArticle(stock: 0);
      controller.players = [player];
      controller.articles = [article];
      controller.selectPlayer(player);
      controller.addToCart(article);

      await expectLater(
          controller.checkout('ESP'),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('Stock insuffisant'))));
      expect(controller.sales, isEmpty);
      expect(controller.cart, hasLength(1));
    });

    test('refuses any mutation in read-only mode', () async {
      controller.readOnly = true;
      final player = testPlayer();
      controller.players = [player];
      controller.articles = [testArticle()];
      controller.selectPlayer(player);
      controller.addToCart(testArticle());

      await expectLater(
          controller.checkout('ESP'),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('Licence à vérifier'))));
      expect(controller.sales, isEmpty);
    });
  });

  group('meals', () {
    late Player player;
    late Article repas;
    late Article drink;
    late Article snack;

    setUp(() {
      player = testPlayer();
      repas = testArticle(id: 'repas-1', category: 'REPAS', stock: 10, threshold: 2);
      drink = testArticle(id: 'drink-1', stock: 10);
      snack = testArticle(id: 'snack-1', stock: 10);
      controller.articles = [repas, drink, snack];
      controller.players = [player];
    });

    test('createMeal is rejected when the module is disabled', () async {
      controller.appSettings =
          controller.appSettings.copyWith(mealsEnabled: false);
      await expectLater(
          controller.createMeal(
            player: player,
            source: 'helloasso',
            status: 'planned',
            mealArticleId: 'repas-1',
            drinkArticleId: 'drink-1',
            snackArticleId: 'snack-1',
            formula: 'Standard',
            options: const [],
            note: '',
          ),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('module repas'))));
      expect(controller.meals, isEmpty);
    });

    test('a planned HelloAsso meal does not touch stock or sales', () async {
      await controller.createMeal(
        player: player,
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas-1',
        drinkArticleId: 'drink-1',
        snackArticleId: 'snack-1',
        formula: 'Standard',
        options: const [],
        note: '',
      );
      expect(controller.meals, hasLength(1));
      expect(controller.meals.single.saleId, isEmpty);
      expect(controller.sales, isEmpty);
      expect(controller.stockMovements, isEmpty);
      expect([repas.stock, drink.stock, snack.stock], [10, 10, 10]);
    });

    test('an onsite served meal consumes stock and creates its sale', () async {
      await controller.createMeal(
        player: player,
        source: 'onsite',
        status: 'served',
        mealArticleId: 'repas-1',
        drinkArticleId: 'drink-1',
        snackArticleId: 'snack-1',
        formula: 'Standard',
        options: const [],
        note: '',
        payment: 'PayPal',
      );
      final meal = controller.meals.single;
      expect(meal.isOnsite, isTrue);
      expect(meal.saleId, isNotEmpty);
      expect(controller.sales, hasLength(1));
      final sale = controller.sales.single;
      expect(sale.id, meal.saleId);
      expect(sale.payment, 'PayPal');
      expect(sale.tariff, 'adherent');
      expect(sale.items.single.articleId, 'repas-1');
      expect([repas.stock, drink.stock, snack.stock], [9, 9, 9]);
      expect(controller.stockMovements, hasLength(3));
      expect(controller.stockMovements.first.movementType, 'meal');
    });

    test('insufficient stock rolls the meal creation back', () async {
      repas.stock = 0;
      await expectLater(
          controller.createMeal(
            player: player,
            source: 'helloasso',
            status: 'served',
            mealArticleId: 'repas-1',
            drinkArticleId: 'drink-1',
            snackArticleId: 'snack-1',
            formula: 'Standard',
            options: const [],
            note: '',
          ),
          throwsA(isA<StateError>()));
      expect(controller.meals, isEmpty);
      expect([repas.stock, drink.stock, snack.stock], [0, 10, 10]);
    });

    test('preparing consumes stock and unpreparing restores it', () async {
      await controller.createMeal(
        player: player,
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas-1',
        drinkArticleId: 'drink-1',
        snackArticleId: 'snack-1',
        formula: 'Standard',
        options: const [],
        note: '',
      );
      final planned = controller.meals.single;
      await controller.prepareMeal(planned);
      var current = controller.meals.single;
      expect(current.status, 'prepared');
      expect(current.preparedAt, isNotNull);
      expect([repas.stock, drink.stock, snack.stock], [9, 9, 9]);

      await controller.unprepareMeal(current);
      current = controller.meals.single;
      expect(current.status, 'planned');
      expect([repas.stock, drink.stock, snack.stock], [10, 10, 10]);
    });

    test('serving a planned meal sets both timestamps', () async {
      await controller.createMeal(
        player: player,
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas-1',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Boisson seule',
        options: const [],
        note: '',
      );
      await controller.serveMeal(controller.meals.single);
      final served = controller.meals.single;
      expect(served.status, 'served');
      expect(served.preparedAt, isNotNull);
      expect(served.servedAt, isNotNull);
    });

    test('serving a cancelled meal is a no-op', () async {
      await controller.createMeal(
        player: player,
        source: 'helloasso',
        status: 'planned',
        mealArticleId: 'repas-1',
        drinkArticleId: '',
        snackArticleId: '',
        formula: 'Standard',
        options: const [],
        note: '',
      );
      await controller.cancelMeal(controller.meals.single);
      await controller.serveMeal(controller.meals.single);
      expect(controller.meals.single.status, 'cancelled');
    });

    test('cancelling restores stock and cancels the linked sale', () async {
      await controller.createMeal(
        player: player,
        source: 'onsite',
        status: 'served',
        mealArticleId: 'repas-1',
        drinkArticleId: 'drink-1',
        snackArticleId: 'snack-1',
        formula: 'Standard',
        options: const [],
        note: '',
        payment: 'ESP',
      );
      final meal = controller.meals.single;
      expect([repas.stock, drink.stock, snack.stock], [9, 9, 9]);

      await controller.cancelMeal(meal);

      expect(controller.meals.single.status, 'cancelled');
      expect([repas.stock, drink.stock, snack.stock], [10, 10, 10]);
      expect(controller.sales.single.status, 'cancelled');
      expect(controller.sales.single.cancellationReason,
          contains('Annulation du repas'));

      final movementsBefore = controller.stockMovements.length;
      await controller.cancelMeal(controller.meals.single);
      expect(controller.stockMovements.length, movementsBefore);
    });

    test('updating a meal moves the stock and reprices the sale', () async {
      final repasDeux = testArticle(
          id: 'repas-2', category: 'REPAS', stock: 5, threshold: 2, price: 9,
          memberPrice: 8);
      controller.articles = [repas, repasDeux, drink, snack];
      await controller.createMeal(
        player: player,
        source: 'onsite',
        status: 'served',
        mealArticleId: 'repas-1',
        drinkArticleId: 'drink-1',
        snackArticleId: 'snack-1',
        formula: 'Standard',
        options: const [],
        note: '',
        payment: 'ESP',
      );
      final meal = controller.meals.single;
      expect([repas.stock, repasDeux.stock], [9, 5]);

      await controller.updateMeal(meal, meal.copyWith(mealArticleId: 'repas-2'));

      expect([repas.stock, repasDeux.stock], [10, 4]);
      expect(controller.sales.single.items.single.articleId, 'repas-2');
      expect(controller.sales.single.totalArticles, 8);
    });
  });

  group('articles', () {
    test('upsertArticle normalizes the category and creates it', () async {
      final article = testArticle(category: '  nouvelle cat ');
      await controller.upsertArticle(article);
      expect(article.category, 'NOUVELLE CAT');
      expect(controller.articles, [article]);
      expect(controller.articleCategories, contains('NOUVELLE CAT'));
      expect(controller.persistCalls, 1);
    });

    test('upsertArticle replacing adjusts the stock', () async {
      final original = testArticle(stock: 10, threshold: 2);
      controller.articles = [original];
      final replacement = testArticle(stock: 15, name: 'Soda XL');
      await controller.upsertArticle(replacement, replacing: original);
      expect(controller.articles.single, replacement);
      expect(replacement.stock, 15);
      expect(controller.stockMovements.single.movementType, 'adjustment');
      expect(controller.stockMovements.single.quantityDelta, 5);
    });

    test('upsertArticle zeroes location stock fields', () async {
      final location = testArticle(
          type: 'location', stock: 5, threshold: 3);
      location.bbAuto = 2;
      location.gasAuto = 3;
      await controller.upsertArticle(location);
      expect(location.stock, 0);
      expect(location.threshold, 0);
      expect(location.bbAuto, 0);
      expect(location.gasAuto, 0);
    });

    test('deleteArticle is blocked by the cart', () async {
      final article = testArticle();
      controller.cart.add(
          CartItem(articleId: article.id, quantity: 1, price: article.price));
      await expectLater(
          controller.deleteArticle(article),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('panier courant'))));
    });

    test('deleteArticle is blocked by the session sales', () async {
      final article = testArticle();
      controller.sales = [
        testSale(items: [testSaleItem(articleId: article.id)]),
      ];
      await expectLater(
          controller.deleteArticle(article),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('ventes de la session'))));
    });

    test('deleteArticle is blocked by the sales history', () async {
      final article = testArticle();
      controller.salesBySession = {
        'autre-session': [
          testSale(
              id: 'ancienne',
              items: [testSaleItem(articleId: article.id)],
              session: 'autre-session'),
        ],
      };
      await expectLater(
          controller.deleteArticle(article),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('historique des ventes'))));
    });

    test('deleteArticle is blocked by meals', () async {
      final article = testArticle();
      controller.meals = [testMeal(mealArticleId: article.id)];
      await expectLater(
          controller.deleteArticle(article),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('repas de la session'))));
    });

    test('deleteArticle is blocked by stock movements', () async {
      final article = testArticle();
      controller.stockMovements = [testStockMovement(articleId: article.id)];
      await expectLater(
          controller.deleteArticle(article),
          throwsA(isA<StateError>().having((error) => error.message, 'message',
              contains('mouvements de stock'))));
    });

    test('deleteArticle removes the article', () async {
      final article = testArticle();
      controller.articles = [article];
      await controller.deleteArticle(article);
      expect(controller.articles, isEmpty);
    });
  });

  group('categories', () {
    test('addArticleCategory normalizes and deduplicates', () async {
      await controller.addArticleCategory('  snacking ');
      expect(controller.articleCategories.length,
          defaultArticleCategories().length);
      await controller.addArticleCategory('Menu');
      expect(controller.articleCategories, contains('MENU'));
      await controller.addArticleCategory('menu');
      expect(
          controller.articleCategories.where((c) => c == 'MENU'), hasLength(1));
    });

    test('containsArticleCategory matches the stable id', () {
      expect(controller.containsArticleCategory('bar-a-jus'), isFalse);
      controller.articleCategories = [...controller.articleCategories, 'BAR A JUS'];
      expect(controller.containsArticleCategory('bar-a-jus'), isTrue);
    });

    test('renameArticleCategory moves the articles and the filter', () async {
      final article = testArticle(category: 'SNACKING');
      controller.articles = [article];
      controller.setCategory('SNACKING');
      await controller.renameArticleCategory('SNACKING', 'Encas');
      expect(article.category, 'ENCAS');
      expect(controller.articleCategories, contains('ENCAS'));
      expect(controller.articleCategories, isNot(contains('SNACKING')));
      expect(controller.categoryFilter, 'ENCAS');
    });

    test('renameArticleCategory refuses duplicates', () async {
      await controller.renameArticleCategory('SNACKING', 'BOISSONS');
      expect(controller.articleCategories, contains('SNACKING'));
    });

    test('setCategory falls back to TOUS for unknown categories', () {
      controller.setCategory('INCONNUE');
      expect(controller.categoryFilter, 'TOUS');
    });
  });

  group('players', () {
    test('addPlayer deduplicates by email and updates the existing entry',
        () async {
      await controller.addPlayer(
          firstName: 'Alice', lastName: 'Martin', email: 'Alice@Exemple.fr', type: 'public');
      await controller.addPlayer(
          firstName: 'Alicia', lastName: 'Martin', email: 'alice@exemple.fr', type: 'membre');
      expect(controller.players, hasLength(1));
      expect(controller.players.single.name, 'Alicia Martin');
      expect(controller.players.single.type, 'membre');
      expect(controller.allPlayers, hasLength(1));
    });

    test('addPlayer deduplicates by name when there is no email', () async {
      await controller.addPlayer(
          firstName: 'Alice', lastName: 'Martin', email: '', type: 'public');
      await controller.addPlayer(
          firstName: 'Alice', lastName: 'Martin', email: '', type: 'membre');
      expect(controller.players, hasLength(1));
      expect(controller.players.single.type, 'membre');
    });

    test('addPlayer keeps the list sorted', () async {
      await controller.addPlayer(
          firstName: 'Zoe', lastName: 'Zaza', email: 'zoe@exemple.fr', type: 'public');
      await controller.addPlayer(
          firstName: 'Alice', lastName: 'Martin', email: 'alice@exemple.fr', type: 'public');
      expect(controller.players.map((player) => player.name),
          ['Alice Martin', 'Zoe Zaza']);
    });

    test('updatePlayer renames the sale and meal snapshots', () async {
      final player = testPlayer();
      controller.allPlayers = [player];
      controller.players = [player];
      controller.sales = [testSale(playerId: player.id)];
      controller.meals = [testMeal(playerId: player.id)];
      await controller.updatePlayer(player,
          firstName: 'Alicia', lastName: 'Martin', email: player.email, type: 'membre');
      expect(player.name, 'Alicia Martin');
      expect(controller.sales.single.playerName, 'Alicia Martin');
      expect(controller.meals.single.playerName, 'Alicia Martin');
    });

    test('removePlayer clears the selection', () async {
      final player = testPlayer();
      controller.players = [player];
      controller.selectPlayer(player);
      expect(controller.selectedPlayerId, player.id);
      await controller.removePlayer(player);
      expect(controller.players, isEmpty);
      expect(controller.selectedPlayerId, isNull);
    });
  });

  group('cash', () {
    test('updateCash clamps negatives and stores the key', () async {
      await controller.updateCash('start', 50, 2);
      await controller.updateCash('start', 20, -3);
      expect(controller.cashStart['50.0'], 2);
      expect(controller.cashStart['20.0'], 0);
    });

    test('cashTotal sums the denominations', () async {
      await controller.updateCash('start', 50, 2);
      await controller.updateCash('start', 2, 1);
      expect(controller.cashTotal('start'), 102);
      expect(controller.cashTotal('end'), 0);
    });

    test('paymentTotals aggregates active sales including donations', () {
      controller.sales = [
        testSale(
            id: 's1',
            payment: 'ESP',
            totalArticles: 5,
            donation: 1),
        testSale(
            id: 's2',
            payment: 'PayPal',
            totalArticles: 3,
            items: [testSaleItem(price: 3)]),
        testSale(id: 's3', payment: 'SumUp', status: 'cancelled'),
      ];
      final totals = controller.paymentTotals();
      expect(totals['ESP'], 6);
      expect(totals['PayPal'], 3);
      expect(totals['SumUp'], 0);
    });
  });

  group('resets', () {
    test('resetSales cancels the sales without restoring stock', () async {
      final article = testArticle(stock: 9);
      controller.articles = [article];
      final sale = testSale();
      controller.sales = [sale];
      controller.meals = [testMeal(saleId: sale.id)];
      await controller.resetSales();
      expect(controller.sales.single.status, 'cancelled');
      expect(controller.sales.single.cancellationReason,
          'Réinitialisation des ventes');
      expect(controller.meals.single.saleId, isEmpty);
      expect(article.stock, 9);
    });

    test('resetStock zeroes every article with an adjustment', () async {
      final tracked = testArticle(id: 'a1', stock: 10, threshold: 2);
      final empty = testArticle(id: 'a2', stock: 0, threshold: 2);
      controller.articles = [tracked, empty];
      await controller.resetStock();
      expect(tracked.stock, 0);
      expect(empty.stock, 0);
      expect(controller.stockMovements, hasLength(1));
      expect(controller.stockMovements.single.reason, 'Remise a zero du stock');
    });

    test('resetAll clears the business data but keeps the settings', () async {
      controller.appSettings =
          controller.appSettings.copyWith(associationName: 'Frag Addict');
      controller.articles = [testArticle()];
      controller.players = [testPlayer()];
      controller.sales = [testSale()];
      controller.meals = [testMeal()];
      await controller.resetAll();
      expect(controller.articles, isEmpty);
      expect(controller.players, isEmpty);
      expect(controller.sales, isEmpty);
      expect(controller.meals, isEmpty);
      expect(controller.articleCategories, defaultArticleCategories());
      expect(controller.activeSession?.name, 'Nouvel événement');
      expect(controller.sessions, hasLength(1));
      expect(controller.appSettings.associationName, 'Frag Addict');
    });

    test('consumeStockForAssociation validates its input', () async {
      final untracked = testArticle(threshold: 0, stock: 5);
      final tracked = testArticle(stock: 5, threshold: 2);
      await expectLater(
          controller.consumeStockForAssociation(untracked, 1),
          throwsA(isA<StateError>()));
      await expectLater(
          controller.consumeStockForAssociation(tracked, 0),
          throwsA(isA<StateError>()));
      await expectLater(
          controller.consumeStockForAssociation(tracked, 6),
          throwsA(isA<StateError>()));
    });

    test('consumeStockForAssociation records an association movement',
        () async {
      final article = testArticle(stock: 10, threshold: 2);
      controller.articles = [article];
      await controller.consumeStockForAssociation(article, 3, note: ' Perte ');
      expect(article.stock, 7);
      final movement = controller.stockMovements.single;
      expect(movement.movementType, 'association');
      expect(movement.quantityDelta, -3);
      expect(movement.reason, 'Consommation association : Perte');
      expect(controller.pendingStockMovements, hasLength(1));
    });
  });

  group('settings & sessions', () {
    test('setAssociationName falls back to TILLY', () async {
      controller.appSettings =
          controller.appSettings.copyWith(associationName: 'Autre');
      await controller.setAssociationName('   ');
      expect(controller.associationName, 'TILLY');
    });

    test('setMainTabVisible ignores non configurable tabs', () async {
      await controller.setMainTabVisible(AppTabIds.sales, false);
      expect(controller.isMainTabVisible(AppTabIds.sales), isTrue);
      await controller.setMainTabVisible(AppTabIds.stats, false);
      expect(controller.isMainTabVisible(AppTabIds.stats), isFalse);
    });

    test('setMealsEnabled leaves the meals tab', () async {
      controller.tab = 1;
      await controller.setMealsEnabled(false);
      expect(controller.mealsEnabled, isFalse);
      expect(controller.tab, 0);
    });

    test('setSession falls back to Événement', () async {
      controller.sessions = [controller.activeSession!];
      await controller.setSession('  ');
      expect(controller.activeSession?.name, 'Événement');
    });

    test('salesForSession only returns active sales', () {
      final active = testSale(id: 'active');
      final cancelled = testSale(id: 'cancelled', status: 'cancelled');
      controller.salesBySession = {
        'session-test': [active, cancelled],
      };
      expect(controller.salesForSession('session-test').map((sale) => sale.id),
          ['active']);
    });

    test('salesForSession falls back to the active session sales', () {
      controller.sales = [
        testSale(id: 'active'),
        testSale(id: 'cancelled', status: 'cancelled'),
      ];
      expect(controller.salesForSession('session-test').map((sale) => sale.id),
          ['active']);
    });
  });

  group('legacy backup import', () {
    test('rejects a backup without articles', () async {
      await expectLater(
          controller.importBackup({
            'state': {'articles': []},
          }),
          throwsA(isA<FormatException>().having((error) => error.message,
              'message', 'Aucun article trouvé dans la sauvegarde')));
    });

    test('imports articles, players and sales into a fresh session', () async {
      await controller.importBackup({
        'state': {
          'session': 'Jour importé',
          'articles': [
            {
              'id': 'legacy-article',
              'name': 'Eau',
              'category': 'BOISSONS',
              'price': 1.5,
              'memberPrice': 1,
              'stock': 20,
              'threshold': 5,
            }
          ],
          'players': [
            {'id': 'legacy-player', 'name': 'Alice Martin', 'type': 'membre'}
          ],
          'sales': [
            {
              'id': 'legacy-sale',
              'playerName': 'Alice Martin',
              'totalArticles': 1.5,
              'payment': 'ESP',
            }
          ],
        },
      });
      expect(controller.activeSession?.name, 'Jour importé');
      expect(controller.articles.single.id, 'legacy-article');
      expect(controller.articleCategories, contains('BOISSONS'));
      expect(controller.players.single.id, 'legacy-player');
      expect(controller.sales.single.id, 'legacy-sale');
      expect(controller.sales.single.session, controller.activeSession?.id);
      expect(controller.meals, isEmpty);
      expect(controller.stockMovements, isEmpty);
      expect(controller.persistCalls, greaterThan(0));
    });
  });
}
