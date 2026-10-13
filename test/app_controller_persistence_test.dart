import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<(Directory, String)> tempDatabase() async {
    final directory = await Directory.systemTemp.createTemp('tilly-test-');
    final databasePath = path.join(directory.path, 'tilly.db');
    return (directory, databasePath);
  }

  Future<void> cleanup(Directory directory, List<LocalDatabase> databases) async {
    for (final database in databases) {
      await database.close();
    }
    await directory.delete(recursive: true);
  }

  test('load creates a default session and catalog', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());

    await controller.load();

    expect(controller.sessions, hasLength(1));
    expect(controller.activeSession, isNotNull);
    expect(controller.articles, isEmpty);
    expect(controller.articleCategories..sort(),
        defaultArticleCategories()..sort());
    expect(controller.meals, isEmpty);
    expect(controller.sales, isEmpty);
  });

  test('saveAll/load round-trips the business data', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    final reloadDatabase = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database, reloadDatabase]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final sessionId = controller.activeSession!.id;
    final mealCreatedAt = DateTime(2026, 7, 16, 12);
    final mealPreparedAt = DateTime(2026, 7, 16, 12, 15);

    controller.articles = [testArticle(id: 'a1', stock: 8)];
    controller.articleCategories = ['BOISSONS', 'REPAS'];
    controller.allPlayers = [testPlayer()];
    controller.players = [testPlayer()];
    controller.sales = [
      testSale(
          id: 'sale-a1',
          session: sessionId,
          createdAt: DateTime(2026, 7, 16, 11)),
    ];
    controller.meals = [
      testMeal(
        id: 'meal-a1',
        status: 'prepared',
        mealArticleId: 'repas-1',
        drinkArticleId: 'a1',
        options: ['Ketchup'],
        note: 'Sans porc',
        createdAt: mealCreatedAt,
        preparedAt: mealPreparedAt,
      ),
    ];
    controller.cashStart = {'50.0': 2};
    controller.cashEnd = {'2.0': 3};
    controller.appSettings =
        controller.appSettings.copyWith(associationName: 'Frag Addict');
    await controller.persist();

    final reloaded =
        AppController(database: reloadDatabase, secureSettings: NoopSecureSettings());
    await reloaded.load();

    expect(reloaded.articles.single.id, 'a1');
    expect(reloaded.articles.single.stock, 8);
    expect(reloaded.articleCategories, ['BOISSONS', 'REPAS']);
    expect(reloaded.players.single.name, 'Alice Martin');
    expect(reloaded.allPlayers.single.id, 'player-1');
    expect(reloaded.sales.single.id, 'sale-a1');
    expect(reloaded.sales.single.createdAt, DateTime(2026, 7, 16, 11));
    final meal = reloaded.meals.single;
    expect(meal.id, 'meal-a1');
    expect(meal.status, 'prepared');
    expect(meal.options, ['Ketchup']);
    expect(meal.note, 'Sans porc');
    expect(meal.createdAt, mealCreatedAt);
    expect(meal.preparedAt, mealPreparedAt);
    expect(reloaded.cashTotal('start'), 100);
    expect(reloaded.cashTotal('end'), 6);
    expect(reloaded.associationName, 'Frag Addict');
  });

  test('the demo dataset persists meals for every session', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    final reloadDatabase = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database, reloadDatabase]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();

    final dataset = buildDemoDataset(now: DateTime(2026, 7, 18, 12));
    controller.articles = dataset.articles;
    controller.articleCategories = dataset.categories;
    controller.allPlayers = dataset.players;
    for (final day in dataset.days) {
      controller.activeSession = day.session;
      controller.players = day.players;
      controller.sales = day.sales;
      controller.meals = day.meals;
      controller.cashStart = day.cashStart;
      controller.cashEnd = day.cashEnd;
      controller.pendingStockMovements.addAll(day.stockMovements);
      await controller.persist(markUpdated: false);
    }

    for (final day in dataset.days) {
      final meals = await database.loadMeals(day.session.id);
      expect(meals, hasLength(day.meals.length),
          reason: 'repas persistés pour ${day.session.name}');
      final sales = await database.loadSales(day.session.id);
      expect(sales, hasLength(day.sales.length));
    }

    final reloaded =
        AppController(database: reloadDatabase, secureSettings: NoopSecureSettings());
    await reloaded.load();
    expect(reloaded.activeSession?.id, dataset.days.last.session.id);
    expect(reloaded.meals, hasLength(dataset.days.last.meals.length));
    expect(reloaded.sales, hasLength(dataset.days.last.sales.length));
    expect(reloaded.cashTotal('end'), 446);
    expect(reloaded.stockMovements, isNotEmpty);
  });

  test('createSession starts a clean session and keeps the catalog', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final firstSessionId = controller.activeSession!.id;
    controller.articles = [testArticle()];
    controller.players = [testPlayer()];
    controller.sales = [testSale(session: firstSessionId)];
    controller.meals = [testMeal()];
    await controller.persist();

    await controller.createSession('Jour 2');

    expect(controller.sessions, hasLength(2));
    expect(controller.activeSession?.name, 'Jour 2');
    expect(controller.sales, isEmpty);
    expect(controller.meals, isEmpty);
    expect(controller.players, isEmpty);
    expect(controller.cashStart, isEmpty);
    expect(controller.articles, hasLength(1));
    expect(await database.loadSales(firstSessionId), hasLength(1));
  });

  test('switchSession reloads the sales and meals of the target session',
      () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final firstSessionId = controller.activeSession!.id;
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.sales = [testSale(id: 'sale-a', session: firstSessionId)];
    controller.meals = [testMeal(id: 'meal-a')];
    await controller.persist();

    await controller.createSession('Jour 2');
    final secondSessionId = controller.activeSession!.id;
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.sales = [testSale(id: 'sale-b', session: secondSessionId)];
    controller.meals = [testMeal(id: 'meal-b')];
    await controller.persist();

    await controller.switchSession(firstSessionId);

    expect(controller.activeSession?.id, firstSessionId);
    expect(controller.sales.map((sale) => sale.id), ['sale-a']);
    expect(controller.meals.map((meal) => meal.id), ['meal-a']);
  });

  test('resetAll clears the data but keeps the settings', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    final reloadDatabase = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database, reloadDatabase]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    controller.appSettings =
        controller.appSettings.copyWith(associationName: 'Frag Addict');
    controller.articles = [testArticle()];
    controller.players = [testPlayer()];
    controller.sales = [testSale()];
    await controller.persist();

    await controller.resetAll();

    expect(controller.articles, isEmpty);
    expect(controller.players, isEmpty);
    expect(controller.sales, isEmpty);
    expect(controller.articleCategories, defaultArticleCategories());
    expect(controller.activeSession?.name, 'Nouvel événement');

    final reloaded =
        AppController(database: reloadDatabase, secureSettings: NoopSecureSettings());
    await reloaded.load();
    expect(reloaded.articles, isEmpty);
    expect(reloaded.articleCategories..sort(), defaultArticleCategories()..sort());
    expect(reloaded.associationName, 'Frag Addict');
    expect(reloaded.activeSession?.name, 'Nouvel événement');
  });

  test('fullBackupPayload exports valid data including meals', () async {
    final (directory, databasePath) = await tempDatabase();
    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    controller.articles = [testArticle(id: 'a1')];
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.meals = [
      testMeal(
          id: 'meal-export',
          status: 'served',
          mealArticleId: 'repas-1',
          options: ['Mayonnaise']),
    ];
    await controller.persist();

    final payload = await controller.fullBackupPayload();

    expect(() => validateBackupPayload(payload), returnsNormally);
    final data = Map<String, dynamic>.from(payload['data'] as Map);
    final mealRows = data['mealOrders'] as List;
    expect(mealRows, hasLength(1));
    expect('${mealRows.single['id']}', 'meal-export');
  });
}
