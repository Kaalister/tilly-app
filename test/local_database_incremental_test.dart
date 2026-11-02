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

  Future<Directory> tempDirectory() =>
      Directory.systemTemp.createTemp('tilly-perf-test-');

  Future<void> cleanup(Directory directory, List<LocalDatabase> databases) async {
    for (final database in databases) {
      await database.close();
    }
    await directory.delete(recursive: true);
  }

  test('re-saving an unchanged state writes no business rows', () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final sessionId = controller.activeSession!.id;
    controller.articles = [testArticle(id: 'a1', stock: 8)];
    controller.articleCategories = ['BOISSONS', 'REPAS'];
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.sales = [
      testSale(id: 'sale-a1', session: sessionId, createdAt: DateTime(2026, 7, 16, 11)),
    ];
    controller.meals = [
      testMeal(id: 'meal-a1', mealArticleId: 'repas-1', options: ['Ketchup']),
    ];
    controller.cashStart = {'50.0': 2};
    await controller.persist();
    expect(database.debugBusinessWrites, greaterThan(0));

    final firstItems = await _saleItemIds(database, 'sale-a1');
    await controller.persist();

    expect(database.debugBusinessWrites, 0,
        reason: 'unchanged rows must not be rewritten');
    expect(await _saleItemIds(database, 'sale-a1'), firstItems,
        reason: 'sale items keep their ids when the sale is untouched');
  });

  test('incremental saves apply updates and removals', () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final sessionId = controller.activeSession!.id;
    final article = testArticle(id: 'a1', stock: 8);
    controller.articles = [article];
    controller.articleCategories = ['BOISSONS'];
    final playerA = testPlayer(id: 'player-a');
    final playerB = testPlayer(id: 'player-b', name: 'Bob Durand');
    controller.players = [playerA, playerB];
    controller.allPlayers = [playerA, playerB];
    final sale = testSale(id: 'sale-1', session: sessionId, playerId: 'player-a');
    controller.sales = [sale];
    final meal =
        testMeal(id: 'meal-1', mealArticleId: 'repas-1', playerId: 'player-a');
    controller.meals = [meal];
    await controller.persist();

    await controller.cancelSale(sale);
    expect(database.debugBusinessWrites, greaterThan(0));
    expect(
        (await database.loadSales(sessionId)).single.status, 'cancelled',
        reason: 'the cancelled sale is persisted incrementally');

    await controller.persist();
    expect(database.debugBusinessWrites, 0);

    await controller.removePlayer(playerB);
    expect((await database.loadPlayers(sessionId)).map((player) => player.id),
        ['player-a']);

    await controller.cancelMeal(meal);
    expect((await database.loadMeals(sessionId)).single.status, 'cancelled');

    article.stock = 2;
    await controller.persist();
    expect((await database.loadArticles()).single.stock, 2);

    await controller.renameArticleCategory('BOISSONS', 'DRINKS');
    expect(await database.loadArticleCategories(), ['DRINKS']);
    expect((await database.loadArticles()).single.category, 'DRINKS');

    controller.cashStart = {'20.0': 3};
    await controller.persist();
    expect(await database.loadCash(sessionId, 'start'), {'20.0': 3});
    expect(database.debugBusinessWrites, 1,
        reason: 'a cash update rewrites only the cash counting');

    await controller.persist();
    expect(database.debugBusinessWrites, 0);
  });

  test('deleted articles are deactivated without rewriting the catalog',
      () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final kept = testArticle(id: 'a1');
    final removed = testArticle(id: 'a2', name: 'Eau');
    controller.articles = [kept, removed];
    controller.articleCategories = ['BOISSONS'];
    await controller.persist();

    controller.articles = [kept];
    await controller.persist();

    expect((await database.loadArticles()).map((article) => article.id), ['a1']);
    final raw = await (await database.database).query('articles',
        columns: ['id', 'is_active'], where: 'id = ?', whereArgs: ['a2']);
    expect(raw.single['is_active'], 0);
  });

  test('switching the data scope resets the incremental snapshot', () async {
    final directory = await tempDirectory();
    final database =
        LocalDatabase(databaseDirectoryOverride: directory.path);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());

    await controller.switchDataScope('account-a');
    await controller.load();
    controller.articles = [testArticle(id: 'a1')];
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    await controller.persist();

    await controller.switchDataScope('account-b');
    controller.articles = [testArticle(id: 'a1')];
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    await controller.persist();

    expect((await database.loadArticles()).map((article) => article.id), ['a1'],
        reason: 'the second dataset must receive the same rows from scratch');
    expect(
        (await database.loadPlayers(controller.activeSession!.id))
            .map((player) => player.id),
        ['player-1']);
  });

  test('fresh databases create the query indexes', () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final db = await database.database;

    final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'");
    final names = rows.map((row) => '${row['name']}').toSet();
    expect(
        names,
        containsAll([
          'idx_session_players_session',
          'idx_session_players_player',
          'idx_sales_session',
          'idx_sale_items_sale',
          'idx_meal_orders_session',
          'idx_stock_movements_session',
          'idx_stock_movements_article',
          'idx_cash_counts_session',
          'idx_cash_count_lines_count',
          'idx_players_email',
        ]));
  });

  test('upgrading a v10 database recreates the missing indexes', () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final db = await database.database;
    final indexRows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'");
    for (final row in indexRows) {
      await db.execute('DROP INDEX IF EXISTS ${row['name']}');
    }
    await db.execute('PRAGMA user_version = 10');
    await database.close();

    final reopened = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => reopened.close());
    final upgraded = await reopened.database;
    final names = (await upgraded.rawQuery(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'"))
        .map((row) => '${row['name']}')
        .toSet();
    expect(names, contains('idx_sales_session'));
    expect(names, contains('idx_sale_items_sale'));
  });

  test('removing a participant after a restart deletes the session row',
      () async {
    final directory = await tempDirectory();
    final databasePath = path.join(directory.path, 'tilly.db');
    final database = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final sessionId = controller.activeSession!.id;
    final playerA = testPlayer(id: 'player-a');
    final playerB = testPlayer(id: 'player-b', name: 'Bob Durand');
    controller.players = [playerA, playerB];
    controller.allPlayers = [playerA, playerB];
    await controller.persist();

    // Simulate an app restart: fresh objects, empty in-memory snapshot.
    final reopened = LocalDatabase(databasePathOverride: databasePath);
    addTearDown(() => reopened.close());
    final restarted = AppController(
        database: reopened, secureSettings: NoopSecureSettings());
    addTearDown(restarted.dispose);
    await restarted.load();
    expect(restarted.players, hasLength(2));

    await restarted.removePlayer(
        restarted.players.firstWhere((player) => player.id == 'player-b'));

    expect(
        (await reopened.loadPlayers(sessionId)).map((player) => player.id),
        ['player-a'],
        reason: 'the stale session row must be removed from the database');
  });

  test('removing a participant works after switching back to a session',
      () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final firstSessionId = controller.activeSession!.id;
    final playerA = testPlayer(id: 'player-a');
    final playerB = testPlayer(id: 'player-b', name: 'Bob Durand');
    controller.players = [playerA, playerB];
    controller.allPlayers = [playerA, playerB];
    await controller.persist();

    await controller.createSession('Jour 2');
    await controller.switchSession(firstSessionId);
    expect(controller.players, hasLength(2));

    await controller.removePlayer(
        controller.players.firstWhere((player) => player.id == 'player-b'));

    expect(
        (await database.loadPlayers(firstSessionId)).map((player) => player.id),
        ['player-a']);
  });

  test('startup loads only the active session sales, history loads on demand',
      () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    final reloadDatabase = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database, reloadDatabase]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final firstSessionId = controller.activeSession!.id;
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.articles = [testArticle(id: 'a1')];
    controller.sales = [
      testSale(id: 'sale-1', session: firstSessionId),
      testSale(id: 'sale-2', session: firstSessionId),
    ];
    await controller.persist();

    await controller.createSession('Jour 2');
    final secondSessionId = controller.activeSession!.id;
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.sales = [
      testSale(id: 'sale-3', session: secondSessionId),
    ];
    await controller.persist();

    final reloaded = AppController(
        database: reloadDatabase, secureSettings: NoopSecureSettings());
    await reloaded.load();

    expect(reloaded.activeSession?.id, secondSessionId);
    expect(reloaded.salesBySession.keys, [secondSessionId],
        reason: 'only the active session sales are loaded at startup');
    expect(reloaded.isSessionSalesLoaded(firstSessionId), isFalse);
    expect(reloaded.salesHistoryLoaded, isFalse);

    await reloaded.ensureAllSessionSalesLoaded();

    expect(reloaded.salesHistoryLoaded, isTrue);
    expect(reloaded.salesForSession(firstSessionId).map((sale) => sale.id),
        ['sale-1', 'sale-2']);
    expect(reloaded.salesForSession(secondSessionId).map((sale) => sale.id),
        ['sale-3']);

    final thirdController = AppController(
        database: LocalDatabase(
            databasePathOverride: path.join(directory.path, 'tilly.db')),
        secureSettings: NoopSecureSettings());
    addTearDown(() => thirdController.dispose());
    await thirdController.load();
    expect(thirdController.isSessionSalesLoaded(firstSessionId), isFalse);
    await thirdController.ensureSessionSalesLoaded(firstSessionId);
    expect(thirdController.isSessionSalesLoaded(firstSessionId), isTrue);
    expect(thirdController.salesForSession(firstSessionId), hasLength(2));
    expect(thirdController.salesHistoryLoaded, isFalse,
        reason: 'loading one session must not load the whole history');
  });

  test('loadSales groups the items of every sale', () async {
    final directory = await tempDirectory();
    final database = LocalDatabase(
        databasePathOverride: path.join(directory.path, 'tilly.db'));
    addTearDown(() => cleanup(directory, [database]));
    final controller =
        AppController(database: database, secureSettings: NoopSecureSettings());
    await controller.load();
    final sessionId = controller.activeSession!.id;
    controller.articles = [testArticle(id: 'a1'), testArticle(id: 'a2', name: 'Eau')];
    controller.players = [testPlayer()];
    controller.allPlayers = [testPlayer()];
    controller.sales = [
      testSale(id: 'sale-1', session: sessionId, items: [
        testSaleItem(articleId: 'a1'),
        testSaleItem(articleId: 'a2', name: 'Eau', quantity: 2),
        testSaleItem(articleId: 'a1', quantity: 3),
      ]),
      testSale(id: 'sale-2', session: sessionId, items: [
        testSaleItem(articleId: 'a2', name: 'Eau'),
      ]),
    ];
    await controller.persist();

    final sales = await database.loadSales(sessionId);

    expect(sales.map((sale) => sale.id), ['sale-1', 'sale-2']);
    expect(sales.first.items, hasLength(3));
    expect(sales.first.items.map((item) => item.quantity), [1, 2, 3]);
    expect(sales.last.items, hasLength(1));
  });
}

Future<List<String>> _saleItemIds(LocalDatabase database, String saleId) async {
  final db = await database.database;
  final rows = await db.query('sale_items',
      columns: ['id'], where: 'sale_id = ?', whereArgs: [saleId]);
  return rows.map((row) => '${row['id']}').toList();
}
