import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../config/app_config.dart';
import '../domain/models.dart';
import '../ui/theme.dart';
import '../utils/iterable_extensions.dart';
import 'persistable_app_state.dart';

class LocalDatabase {
  LocalDatabase({
    String? databasePathOverride,
    String? databaseDirectoryOverride,
  })  : _databasePathOverride = databasePathOverride,
        _databaseDirectoryOverride = databaseDirectoryOverride;

  Database? _db;
  String? _userScopeId;
  final String? _databasePathOverride;
  final String? _databaseDirectoryOverride;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await _databasePath();
    _db = await openDatabase(
      dbPath,
      version: 8,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
      onUpgrade: _upgrade,
    );
    return _db!;
  }

  bool isScopedTo(String? userId) => _userScopeId == _safeUserScope(userId);

  Future<void> setUserScope(String? userId) async {
    final nextScope = _safeUserScope(userId);
    if (_userScopeId == nextScope) return;
    await _db?.close();
    _db = null;
    _userScopeId = nextScope;
  }

  Future<String> _databasePath() => _pathForScope(_userScopeId);

  Future<String> _pathForScope(String? scopeId) async {
    if (_databasePathOverride != null) return _databasePathOverride;
    final fileName = databaseFileName(scopeId);
    if (_databaseDirectoryOverride != null) {
      final directory = Directory(_databaseDirectoryOverride);
      await directory.create(recursive: true);
      return path.join(directory.path, fileName);
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final supportDirectory = await getApplicationSupportDirectory();
      final directory = Directory(path.join(supportDirectory.path, 'Tilly'));
      await directory.create(recursive: true);
      return path.join(directory.path, fileName);
    }

    final directory = Directory(await getDatabasesPath());
    await directory.create(recursive: true);
    return path.join(directory.path, fileName);
  }

  // One-time adoption: the first licence account receives the pre-scope local
  // data so nothing looks lost after the multi-account update. The legacy file
  // is renamed (never deleted) so a second account cannot adopt it too.
  Future<void> adoptLegacyDataIfNeeded(String? scopeId) async {
    if (scopeId == null || scopeId.trim().isEmpty) return;
    if (_databasePathOverride != null) return;
    final targetPath = await _pathForScope(scopeId);
    if (await File(targetPath).exists()) return;
    final legacyPath = await _pathForScope(null);
    final legacyFile = File(legacyPath);
    if (!await legacyFile.exists()) return;
    await legacyFile.copy(targetPath);
    await legacyFile.rename('$legacyPath.adopted');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  String? _safeUserScope(String? userId) {
    final value = userId
        ?.trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-')
        .replaceAll(RegExp(r'^[-._]+|[-._]+$'), '');
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE players (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        first_name TEXT,
        last_name TEXT,
        email TEXT,
        helloasso_user_id TEXT,
        type TEXT NOT NULL DEFAULT 'public',
        created_at TEXT NOT NULL,
        updated_at TEXT,
        deleted_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE session_players (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        player_id TEXT,
        name_snapshot TEXT NOT NULL,
        type_snapshot TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(session_id, player_id),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE article_categories (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        category_id TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'standard',
        icon TEXT,
        price_public REAL NOT NULL DEFAULT 0,
        price_member REAL NOT NULL DEFAULT 0,
        stock_current INTEGER NOT NULL DEFAULT 0,
        stock_alert_threshold INTEGER NOT NULL DEFAULT 0,
        bb_auto_quantity REAL NOT NULL DEFAULT 0,
        gas_auto_quantity REAL NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        FOREIGN KEY (category_id) REFERENCES article_categories(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        session_player_id TEXT,
        player_id TEXT,
        player_name_snapshot TEXT NOT NULL,
        player_type_snapshot TEXT NOT NULL,
        tariff_applied TEXT NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active',
        total_articles REAL NOT NULL DEFAULT 0,
        donation_amount REAL NOT NULL DEFAULT 0,
        total_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        cancelled_at TEXT,
        cancellation_reason TEXT,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (session_player_id) REFERENCES session_players(id) ON DELETE SET NULL,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        article_id TEXT,
        article_name_snapshot TEXT NOT NULL,
        article_category_snapshot TEXT,
        article_type_snapshot TEXT NOT NULL,
        icon_snapshot TEXT,
        quantity INTEGER NOT NULL,
        unit_price REAL NOT NULL,
        price_public_snapshot REAL NOT NULL,
        price_member_snapshot REAL NOT NULL,
        line_total REAL NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE meal_orders (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        player_id TEXT,
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
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE stock_movements (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        article_id TEXT NOT NULL,
        sale_id TEXT,
        movement_type TEXT NOT NULL,
        quantity_delta REAL NOT NULL,
        stock_before REAL NOT NULL,
        stock_after REAL NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (article_id) REFERENCES articles(id) ON DELETE CASCADE,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_counts (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        total_amount REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        UNIQUE(session_id, kind),
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE cash_count_lines (
        id TEXT PRIMARY KEY,
        cash_count_id TEXT NOT NULL,
        denomination REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        line_total REAL NOT NULL DEFAULT 0,
        UNIQUE(cash_count_id, denomination),
        FOREIGN KEY (cash_count_id) REFERENCES cash_counts(id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion >= 2) {
      if (oldVersion < 3) await _upgradeToV3(db);
      if (oldVersion < 4) await _upgradeToV4(db);
      if (oldVersion < 5) await _upgradeToV5(db);
      if (oldVersion < 6) await _upgradeToV6(db);
      if (oldVersion < 7) await _upgradeToV7(db);
      if (oldVersion < 8) await _upgradeToV8(db);
      return;
    }
    final now = DateTime.now().toIso8601String();
    final sessionId = makeId('session');
    var sessionName = 'Partie migrée';
    final oldPlayers = <Map<String, Object?>>[];
    final oldArticles = <Map<String, Object?>>[];
    final oldSales = <Map<String, Object?>>[];
    final oldSaleItems = <Map<String, Object?>>[];
    final oldCashLines = <Map<String, Object?>>[];

    Future<List<Map<String, Object?>>> readLegacyRows(
      String table, {
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? orderBy,
      int? limit,
    }) async {
      try {
        return await db.query(table,
            columns: columns,
            where: where,
            whereArgs: whereArgs,
            orderBy: orderBy,
            limit: limit);
      } catch (_) {
        return const [];
      }
    }

    final setting = await readLegacyRows('app_settings',
        columns: ['value'], where: 'key = ?', whereArgs: ['session'], limit: 1);
    if (setting.isNotEmpty &&
        '${setting.first['value'] ?? ''}'.trim().isNotEmpty) {
      sessionName = '${setting.first['value']}';
    }
    oldPlayers
        .addAll(await readLegacyRows('players', where: 'deleted_at IS NULL'));
    oldArticles.addAll(await readLegacyRows('articles',
        where: 'is_active = 1', orderBy: 'sort_order ASC'));
    oldSales.addAll(await readLegacyRows('sales',
        where: "status = 'active'", orderBy: 'created_at ASC'));
    oldSaleItems.addAll(await readLegacyRows('sale_items', orderBy: 'id ASC'));
    oldCashLines.addAll(await readLegacyRows('cash_count_lines'));

    await _dropAll(db);
    await _create(db, newVersion);

    await db.insert('sessions', {
      'id': sessionId,
      'name': sessionName,
      'event_date': DateTime.now().toIso8601String(),
      'status': 'open',
      'notes': '',
      'created_at': now,
    });
    await db.insert('app_settings',
        {'key': 'active_session_id', 'value': sessionId, 'updated_at': now});

    for (final row in oldPlayers) {
      final playerId = '${row['id'] ?? makeId('player')}';
      await db.insert('players', {
        'id': playerId,
        'name': row['name'],
        'type': row['type'],
        'created_at': row['created_at'] ?? now,
        'updated_at': now,
        'deleted_at': row['deleted_at'],
      });
      await db.insert('session_players', {
        'id': makeId('session-player'),
        'session_id': sessionId,
        'player_id': playerId,
        'name_snapshot': row['name'],
        'type_snapshot': row['type'],
        'created_at': now,
      });
    }

    for (var i = 0; i < oldArticles.length; i++) {
      final row = oldArticles[i];
      final categoryName = '${row['category'] ?? 'DIVERS'}';
      final categoryId = stableCategoryId(categoryName);
      await db.insert('article_categories',
          {'id': categoryId, 'name': categoryName, 'sort_order': i},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await db.insert('articles', {
        'id': row['id'],
        'category_id': categoryId,
        'name': row['name'],
        'type': row['type'],
        'icon': row['icon'],
        'price_public': row['price_public'],
        'price_member': row['price_member'],
        'stock_current': row['stock_current'],
        'stock_alert_threshold': row['stock_alert_threshold'],
        'bb_auto_quantity': row['bb_auto_quantity'],
        'gas_auto_quantity': row['gas_auto_quantity'],
        'is_active': row['is_active'],
        'sort_order': row['sort_order'] ?? i,
        'created_at': row['created_at'] ?? now,
        'updated_at': row['updated_at'] ?? now,
      });
    }

    for (final row in oldSales) {
      final saleId = '${row['id'] ?? makeId('sale')}';
      await db.insert('sales', {
        'id': saleId,
        'session_id': sessionId,
        'player_id': row['player_id'] == null ? null : '${row['player_id']}',
        'player_name_snapshot': row['player_name_snapshot'],
        'player_type_snapshot': row['player_type_snapshot'],
        'tariff_applied': row['tariff_applied'],
        'payment_method': row['payment_method'],
        'status': row['status'] ?? 'active',
        'total_articles': row['total_articles'],
        'donation_amount': row['donation_amount'],
        'total_amount': row['total_amount'],
        'created_at': row['created_at'] ?? now,
        'cancelled_at': row['cancelled_at'],
        'cancellation_reason': row['cancellation_reason'],
      });
    }

    for (final row in oldSaleItems) {
      await db.insert('sale_items', {
        'id': makeId('sale-item'),
        'sale_id': '${row['sale_id']}',
        'article_id': row['article_id'],
        'article_name_snapshot': row['article_name_snapshot'],
        'article_category_snapshot': null,
        'article_type_snapshot': row['article_type_snapshot'],
        'icon_snapshot': row['icon_snapshot'],
        'quantity': row['quantity'],
        'unit_price': row['unit_price'],
        'price_public_snapshot': row['price_public_snapshot'],
        'price_member_snapshot': row['price_member_snapshot'],
        'line_total': row['line_total'],
      });
    }

    await _migrateCashLines(db, sessionId, 'start', oldCashLines, now);
    await _migrateCashLines(db, sessionId, 'end', oldCashLines, now);
    await _upgradeToV7(db);
  }

  Future<void> _upgradeToV3(Database db) async {
    await _safeAddColumn(db, 'players', 'first_name TEXT');
    await _safeAddColumn(db, 'players', 'last_name TEXT');
    await _safeAddColumn(db, 'players', 'email TEXT');
    await _safeAddColumn(db, 'players', 'helloasso_user_id TEXT');
  }

  Future<void> _upgradeToV4(Database db) async {
    await _safeAddColumn(db, 'sessions', 'helloasso_form_slug TEXT');
    await _safeAddColumn(db, 'sessions', 'helloasso_form_type TEXT');
    await _safeAddColumn(db, 'sessions', 'helloasso_event_name TEXT');
    await _safeAddColumn(db, 'sessions', 'helloasso_event_url TEXT');
    await _safeAddColumn(db, 'sessions', 'helloasso_event_id TEXT');
    await _safeAddColumn(db, 'sessions', 'helloasso_synced_at TEXT');
  }

  Future<void> _upgradeToV5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meal_orders (
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
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');
  }

  Future<void> _upgradeToV6(Database db) async {
    await db.update(
      'articles',
      {'bb_auto_quantity': 1, 'gas_auto_quantity': 1},
      where:
          'id = ? AND type = ? AND bb_auto_quantity = ? AND gas_auto_quantity > ? AND gas_auto_quantity < ?',
      whereArgs: ['location', 'location', 700, 0.14, 0.16],
    );
  }

  Future<void> _upgradeToV7(Database db) async {
    await db.update(
      'articles',
      {
        'stock_current': 0,
        'stock_alert_threshold': 0,
        'bb_auto_quantity': 0,
        'gas_auto_quantity': 0,
      },
      where: 'type = ?',
      whereArgs: ['location'],
    );
  }

  Future<void> _upgradeToV8(Database db) async {
    await db.execute('''
      UPDATE stock_movements
      SET sale_id = NULL
      WHERE sale_id IS NOT NULL
        AND sale_id NOT IN (SELECT id FROM sales)
    ''');
    await db.execute('''
      UPDATE meal_orders
      SET sale_id = NULL
      WHERE sale_id IS NOT NULL
        AND sale_id NOT IN (SELECT id FROM sales)
    ''');
    await db.execute('ALTER TABLE meal_orders RENAME TO meal_orders_v7');
    await db.execute('''
      CREATE TABLE meal_orders (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        player_id TEXT,
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
        updated_at TEXT NOT NULL,
        FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
        FOREIGN KEY (player_id) REFERENCES players(id) ON DELETE SET NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      INSERT INTO meal_orders (
        id, session_id, player_id, player_name_snapshot, player_type_snapshot,
        source, status, sale_id, payment_method, meal_article_id,
        drink_article_id, snack_article_id, formula, options_json, note,
        created_at, prepared_at, served_at, updated_at
      )
      SELECT
        id, session_id, player_id, player_name_snapshot, player_type_snapshot,
        source, status, sale_id, payment_method, meal_article_id,
        drink_article_id, snack_article_id, formula, options_json, note,
        created_at, prepared_at, served_at, updated_at
      FROM meal_orders_v7
    ''');
    await db.execute('DROP TABLE meal_orders_v7');
  }

  Future<void> _safeAddColumn(
      Database db, String table, String columnDefinition) async {
    try {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDefinition');
    } catch (_) {
      // Column already exists or table is being recreated by an older migration.
    }
  }

  Future<void> _dropAll(Database db) async {
    for (final table in [
      'cash_count_lines',
      'cash_counts',
      'stock_movements',
      'meal_orders',
      'sale_items',
      'sales',
      'session_players',
      'articles',
      'article_categories',
      'players',
      'sessions',
      'app_settings',
    ]) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  Future<void> _migrateCashLines(Database db, String sessionId, String kind,
      List<Map<String, Object?>> oldCashLines, String now) async {
    final countId = makeId('cash-count');
    var total = 0.0;
    final lines = oldCashLines
        .where((row) => '${row['cash_count_kind']}' == kind)
        .toList();
    for (final line in lines) {
      total += (line['line_total'] as num?)?.toDouble() ?? 0;
    }
    await db.insert('cash_counts', {
      'id': countId,
      'session_id': sessionId,
      'kind': kind,
      'total_amount': total,
      'created_at': now,
      'updated_at': now
    });
    for (final line in lines) {
      final denomination = (line['denomination'] as num?)?.toDouble() ?? 0;
      final quantity = (line['quantity'] as num?)?.round() ?? 0;
      await db.insert('cash_count_lines', {
        'id': makeId('cash-line'),
        'cash_count_id': countId,
        'denomination': denomination,
        'quantity': quantity,
        'line_total': denomination * quantity,
      });
    }
  }

  Future<String?> loadActiveSessionId() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['active_session_id'],
        limit: 1);
    return rows.isEmpty ? null : '${rows.first['value'] ?? ''}';
  }

  Future<HelloAssoSettings> loadHelloAssoSettings() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['helloasso_settings'],
        limit: 1);
    if (rows.isEmpty || rows.first['value'] == null) {
      return const HelloAssoSettings();
    }
    try {
      return HelloAssoSettings.fromJson(Map<String, dynamic>.from(
          jsonDecode('${rows.first['value']}') as Map));
    } catch (_) {
      return const HelloAssoSettings();
    }
  }

  Future<AppSettings> loadAppSettings() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['app_settings'],
        limit: 1);
    if (rows.isEmpty || rows.first['value'] == null) {
      return const AppSettings();
    }
    try {
      return AppSettings.fromJson(Map<String, dynamic>.from(
          jsonDecode('${rows.first['value']}') as Map));
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<bool> loadTutorialWelcomeSeen() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['tutorial_welcome_seen'],
        limit: 1);
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  Future<void> saveTutorialWelcomeSeen() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {
        'key': 'tutorial_welcome_seen',
        'value': 'true',
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Set<String>> loadTutorialPagesSeen() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['tutorial_pages_seen'],
        limit: 1);
    if (rows.isEmpty || rows.first['value'] == null) return {};
    try {
      return (jsonDecode('${rows.first['value']}') as List)
          .map((value) => '$value')
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveTutorialPagesSeen(Set<String> pageIds) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {
        'key': 'tutorial_pages_seen',
        'value': jsonEncode(pageIds.toList()..sort()),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<DateTime?> loadLocalUpdatedAt() async {
    final db = await database;
    final rows = await db.query('app_settings',
        columns: ['value'],
        where: 'key = ?',
        whereArgs: ['local_updated_at'],
        limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.tryParse('${rows.first['value'] ?? ''}');
  }

  Future<void> markLocalUpdated() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert('app_settings',
        {'key': 'local_updated_at', 'value': now, 'updated_at': now},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveSyncMetadata(DateTime syncedAt) async {
    final db = await database;
    final value = syncedAt.toIso8601String();
    await db.insert('app_settings',
        {'key': 'firebase_last_synced_at', 'value': value, 'updated_at': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> saveHelloAssoSettings(HelloAssoSettings settings,
      {bool markUpdated = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'app_settings',
      {
        'key': 'helloasso_settings',
        'value': jsonEncode(settings.toJson(includeSecret: false)),
        'updated_at': now
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (markUpdated) {
      await db.insert('app_settings',
          {'key': 'local_updated_at', 'value': now, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> setActiveSessionId(String sessionId) async {
    final db = await database;
    await db.insert(
        'app_settings',
        {
          'key': 'active_session_id',
          'value': sessionId,
          'updated_at': DateTime.now().toIso8601String()
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SessionRecord>> loadSessions() async {
    final db = await database;
    final rows =
        await db.query('sessions', orderBy: 'event_date DESC, created_at DESC');
    return rows.map(_sessionFromRow).toList();
  }

  SessionRecord _sessionFromRow(Map<String, Object?> row) => SessionRecord(
        id: '${row['id']}',
        name: '${row['name']}',
        eventDate: DateTime.tryParse('${row['event_date']}') ?? DateTime.now(),
        status: '${row['status'] ?? 'open'}',
        notes: '${row['notes'] ?? ''}',
        helloassoFormSlug: '${row['helloasso_form_slug'] ?? ''}',
        helloassoFormType: '${row['helloasso_form_type'] ?? ''}',
        helloassoEventName: '${row['helloasso_event_name'] ?? ''}',
        helloassoEventUrl: '${row['helloasso_event_url'] ?? ''}',
        helloassoEventId: '${row['helloasso_event_id'] ?? ''}',
        helloassoSyncedAt:
            DateTime.tryParse('${row['helloasso_synced_at'] ?? ''}'),
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        closedAt: DateTime.tryParse('${row['closed_at'] ?? ''}'),
      );

  Future<SessionRecord> createSession(String name,
      {HelloAssoEvent? helloassoEvent, DateTime? helloassoSyncedAt}) async {
    final db = await database;
    final now = DateTime.now();
    final session = SessionRecord(
      id: makeId('session'),
      name: name.trim().isEmpty ? 'Nouvelle partie' : name.trim(),
      eventDate: now,
      createdAt: now,
      helloassoFormSlug: helloassoEvent?.formSlug ?? '',
      helloassoFormType: helloassoEvent?.formType ?? '',
      helloassoEventName: helloassoEvent?.name ?? '',
      helloassoEventUrl: helloassoEvent?.url ?? '',
      helloassoEventId: helloassoEvent?.id ?? '',
      helloassoSyncedAt: helloassoSyncedAt,
    );
    await db.insert('sessions', {
      'id': session.id,
      'name': session.name,
      'event_date': session.eventDate.toIso8601String(),
      'status': session.status,
      'notes': session.notes,
      'helloasso_form_slug': session.helloassoFormSlug,
      'helloasso_form_type': session.helloassoFormType,
      'helloasso_event_name': session.helloassoEventName,
      'helloasso_event_url': session.helloassoEventUrl,
      'helloasso_event_id': session.helloassoEventId,
      'helloasso_synced_at': session.helloassoSyncedAt?.toIso8601String(),
      'created_at': session.createdAt.toIso8601String(),
      'closed_at': session.closedAt?.toIso8601String(),
    });
    await setActiveSessionId(session.id);
    return session;
  }

  Future<void> deleteSession(String sessionId) async {
    final db = await database;
    await db.transaction((txn) async {
      final saleRows = await txn.query('sales',
          columns: ['id'], where: 'session_id = ?', whereArgs: [sessionId]);
      for (final saleId in saleRows.map((row) => '${row['id']}')) {
        await txn
            .delete('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
      }
      final cashRows = await txn.query('cash_counts',
          columns: ['id'], where: 'session_id = ?', whereArgs: [sessionId]);
      for (final cashId in cashRows.map((row) => '${row['id']}')) {
        await txn.delete('cash_count_lines',
            where: 'cash_count_id = ?', whereArgs: [cashId]);
      }
      await txn.delete('stock_movements',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('meal_orders',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn
          .delete('sales', where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('session_players',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('cash_counts',
          where: 'session_id = ?', whereArgs: [sessionId]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
      await txn.delete('app_settings',
          where: 'key = ? AND value = ?',
          whereArgs: ['active_session_id', sessionId]);
    });
  }

  Future<void> resetBusinessData() async {
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'cash_count_lines',
        'cash_counts',
        'stock_movements',
        'meal_orders',
        'sale_items',
        'sales',
        'session_players',
        'articles',
        'article_categories',
        'players',
        'sessions',
      ]) {
        await txn.delete(table);
      }
    });
  }

  Future<List<Player>> loadAllPlayers() async {
    final db = await database;
    final rows = await db.query('players',
        where: 'deleted_at IS NULL', orderBy: 'name COLLATE NOCASE ASC');
    return rows.map(_playerFromRow).toList();
  }

  Future<List<Player>> loadPlayers(String sessionId) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT sp.player_id AS id, sp.name_snapshot AS name, sp.type_snapshot AS type
      FROM session_players sp
      WHERE sp.session_id = ?
      ORDER BY sp.name_snapshot COLLATE NOCASE ASC
    ''', [sessionId]);
    return rows.map(_playerFromRow).toList();
  }

  Player _playerFromRow(Map<String, Object?> row) {
    return Player(
      id: '${row['id']}',
      name: '${row['name']}',
      type: '${row['type']}',
      firstName: '${row['first_name'] ?? ''}',
      lastName: '${row['last_name'] ?? ''}',
      email: '${row['email'] ?? ''}'.trim().toLowerCase(),
      helloassoUserId: '${row['helloasso_user_id'] ?? ''}',
    );
  }

  Future<List<Article>> loadArticles() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT a.*, COALESCE(c.name, 'DIVERS') AS category_name
      FROM articles a
      LEFT JOIN article_categories c ON c.id = a.category_id
      WHERE a.is_active = 1
      ORDER BY a.sort_order ASC, c.name ASC, a.name ASC
    ''');
    return rows
        .map((row) => Article(
              id: '${row['id']}',
              category: '${row['category_name']}',
              type: '${row['type']}',
              icon: '${row['icon'] ?? '📦'}',
              name: '${row['name']}',
              price: (row['price_public'] as num).toDouble(),
              memberPrice: (row['price_member'] as num).toDouble(),
              stock: (row['stock_current'] as num).round(),
              threshold: (row['stock_alert_threshold'] as num).round(),
              bbAuto: (row['bb_auto_quantity'] as num).toDouble(),
              gasAuto: (row['gas_auto_quantity'] as num).toDouble(),
            ))
        .toList();
  }

  Future<List<String>> loadArticleCategories() async {
    final db = await database;
    final rows = await db.query('article_categories',
        columns: ['name'], orderBy: 'sort_order ASC, name COLLATE NOCASE ASC');
    return rows.map((row) => '${row['name']}').toList();
  }

  Future<List<Sale>> loadSales(String sessionId) async {
    final db = await database;
    final rows = await db.query('sales',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC');
    final result = <Sale>[];
    for (final row in rows) {
      final saleId = '${row['id']}';
      final itemRows = await db.query('sale_items',
          where: 'sale_id = ?', whereArgs: [saleId], orderBy: 'id ASC');
      result.add(Sale(
        id: saleId,
        playerId: '${row['player_id'] ?? ''}',
        playerName: '${row['player_name_snapshot']}',
        playerType: '${row['player_type_snapshot']}',
        tariff: '${row['tariff_applied']}',
        items: itemRows
            .map((item) => SaleItem(
                  articleId:
                      '${item['article_id'] ?? item['article_name_snapshot']}',
                  name: '${item['article_name_snapshot']}',
                  icon: '${item['icon_snapshot'] ?? '📦'}',
                  type: '${item['article_type_snapshot']}',
                  quantity: (item['quantity'] as num).round(),
                  price: (item['unit_price'] as num).toDouble(),
                  publicPrice:
                      (item['price_public_snapshot'] as num).toDouble(),
                  memberPrice:
                      (item['price_member_snapshot'] as num).toDouble(),
                ))
            .toList(),
        totalArticles: (row['total_articles'] as num).toDouble(),
        donation: (row['donation_amount'] as num).toDouble(),
        payment: '${row['payment_method']}',
        session: sessionId,
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        status: '${row['status'] ?? 'active'}',
        cancelledAt: DateTime.tryParse('${row['cancelled_at'] ?? ''}'),
        cancellationReason: '${row['cancellation_reason'] ?? ''}',
      ));
    }
    return result;
  }

  Future<List<MealOrder>> loadMeals(String sessionId) async {
    final db = await database;
    final rows = await db.query('meal_orders',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC');
    return rows.map((row) {
      List<String> options = [];
      try {
        options = (jsonDecode('${row['options_json'] ?? '[]'}') as List)
            .map((value) => '$value')
            .toList();
      } catch (_) {
        options = [];
      }
      return MealOrder(
        id: '${row['id']}',
        playerId: '${row['player_id'] ?? ''}',
        playerName: '${row['player_name_snapshot']}',
        playerType: '${row['player_type_snapshot']}',
        source: '${row['source']}',
        status: '${row['status']}',
        saleId: '${row['sale_id'] ?? ''}',
        payment: '${row['payment_method'] ?? ''}',
        mealArticleId: '${row['meal_article_id']}',
        drinkArticleId: '${row['drink_article_id'] ?? ''}',
        snackArticleId: '${row['snack_article_id'] ?? ''}',
        formula: '${row['formula'] ?? 'Standard'}',
        options: options,
        note: '${row['note'] ?? ''}',
        createdAt: DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
        preparedAt: DateTime.tryParse('${row['prepared_at'] ?? ''}'),
        servedAt: DateTime.tryParse('${row['served_at'] ?? ''}'),
        updatedAt: DateTime.tryParse('${row['updated_at']}') ?? DateTime.now(),
      );
    }).toList();
  }

  Future<List<StockMovement>> loadStockMovements(String sessionId) async {
    final db = await database;
    final rows = await db.query('stock_movements',
        where: 'session_id = ?',
        whereArgs: [sessionId],
        orderBy: 'created_at ASC');
    return rows
        .map((row) => StockMovement(
              id: '${row['id']}',
              sessionId: '${row['session_id']}',
              articleId: '${row['article_id']}',
              saleId: row['sale_id'] == null ? null : '${row['sale_id']}',
              movementType: '${row['movement_type']}',
              quantityDelta: (row['quantity_delta'] as num).round(),
              stockBefore: (row['stock_before'] as num).round(),
              stockAfter: (row['stock_after'] as num).round(),
              reason: '${row['reason'] ?? ''}',
              createdAt:
                  DateTime.tryParse('${row['created_at']}') ?? DateTime.now(),
            ))
        .toList();
  }

  Future<Map<String, int>> loadCash(String sessionId, String kind) async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT ccl.denomination, ccl.quantity
      FROM cash_count_lines ccl
      INNER JOIN cash_counts cc ON cc.id = ccl.cash_count_id
      WHERE cc.session_id = ? AND cc.kind = ?
    ''', [sessionId, kind]);
    return {
      for (final row in rows)
        (row['denomination'] as num).toDouble().toString():
            (row['quantity'] as num).round(),
    };
  }

  Future<String?> findArticleReference(String articleId) async {
    final db = await database;
    Future<bool> exists(
        String table, String where, List<Object?> whereArgs) async {
      final count = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM $table WHERE $where',
              whereArgs,
            ),
          ) ??
          0;
      return count > 0;
    }

    if (await exists(
        'meal_orders',
        'meal_article_id = ? OR drink_article_id = ? OR snack_article_id = ?',
        [articleId, articleId, articleId])) {
      return 'les repas';
    }
    if (await exists('sale_items', 'article_id = ?', [articleId])) {
      return 'l’historique des ventes';
    }
    if (await exists('stock_movements', 'article_id = ?', [articleId])) {
      return 'les mouvements de stock';
    }
    return null;
  }

  Future<void> saveAll(PersistableAppState state,
      {bool markUpdated = true}) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final session = state.activeSession;
    if (session == null) return;
    await db.transaction((txn) async {
      await _upsert(
        txn,
        'sessions',
        {
          'id': session.id,
          'name': session.name,
          'event_date': session.eventDate.toIso8601String(),
          'status': session.status,
          'notes': session.notes,
          'helloasso_form_slug': session.helloassoFormSlug,
          'helloasso_form_type': session.helloassoFormType,
          'helloasso_event_name': session.helloassoEventName,
          'helloasso_event_url': session.helloassoEventUrl,
          'helloasso_event_id': session.helloassoEventId,
          'helloasso_synced_at': session.helloassoSyncedAt?.toIso8601String(),
          'created_at': session.createdAt.toIso8601String(),
          'closed_at': session.closedAt?.toIso8601String(),
        },
      );
      await txn.insert('app_settings',
          {'key': 'active_session_id', 'value': session.id, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (markUpdated) {
        await txn.insert('app_settings',
            {'key': 'local_updated_at', 'value': now, 'updated_at': now},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert(
        'app_settings',
        {
          'key': 'app_settings',
          'value': jsonEncode(state.appSettings.toJson()),
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      final uniqueAllPlayers = <String, Player>{
        for (final player in [...state.allPlayers, ...state.players])
          if (player.id.trim().isNotEmpty) player.id: player,
      }.values.toList();
      for (final player in uniqueAllPlayers) {
        await _upsert(
          txn,
          'players',
          {
            'id': player.id,
            'name': player.name,
            'first_name': player.firstName,
            'last_name': player.lastName,
            'email': player.email.trim().toLowerCase(),
            'helloasso_user_id': player.helloassoUserId,
            'type': player.type,
            'created_at': now,
            'updated_at': now,
          },
        );
      }

      await txn.delete('session_players',
          where: 'session_id = ?', whereArgs: [session.id]);
      final uniqueSessionPlayers = <String, Player>{
        for (final player in state.players)
          if (player.id.trim().isNotEmpty) player.id: player,
      }.values.toList();
      for (final player in uniqueSessionPlayers) {
        await txn.insert(
            'session_players',
            {
              'id': makeId('session-player'),
              'session_id': session.id,
              'player_id': player.id,
              'name_snapshot': player.name,
              'type_snapshot': player.type,
              'created_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      await txn.update(
          'articles', {'category_id': null, 'is_active': 0, 'updated_at': now});
      await txn.delete('article_categories');
      for (var i = 0; i < state.articleCategories.length; i++) {
        final category = state.articleCategories[i];
        await txn.insert('article_categories', {
          'id': stableCategoryId(category),
          'name': category,
          'sort_order': i,
        });
      }
      for (var i = 0; i < state.articles.length; i++) {
        final article = state.articles[i];
        final categoryId = stableCategoryId(article.category);
        await txn.insert('article_categories',
            {'id': categoryId, 'name': article.category, 'sort_order': i},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await _upsert(
          txn,
          'articles',
          {
            'id': article.id,
            'category_id': categoryId,
            'name': article.name,
            'type': article.type,
            'icon': article.icon,
            'price_public': article.price,
            'price_member': article.memberPrice,
            'stock_current': article.stock,
            'stock_alert_threshold': article.threshold,
            'bb_auto_quantity': article.bbAuto,
            'gas_auto_quantity': article.gasAuto,
            'is_active': 1,
            'sort_order': i,
            'created_at': now,
            'updated_at': now,
          },
        );
      }

      await txn.delete('meal_orders',
          where: 'session_id = ?', whereArgs: [session.id]);

      for (final sale in state.sales) {
        await _upsert(
          txn,
          'sales',
          {
            'id': sale.id,
            'session_id': session.id,
            'player_id': sale.playerId,
            'player_name_snapshot': sale.playerName,
            'player_type_snapshot': sale.playerType,
            'tariff_applied': sale.tariff,
            'payment_method': sale.payment,
            'status': sale.status,
            'total_articles': sale.totalArticles,
            'donation_amount': sale.donation,
            'total_amount': sale.total,
            'created_at': sale.createdAt.toIso8601String(),
            'cancelled_at': sale.cancelledAt?.toIso8601String(),
            'cancellation_reason': sale.cancellationReason.trim().isEmpty
                ? null
                : sale.cancellationReason,
          },
        );
        await txn
            .delete('sale_items', where: 'sale_id = ?', whereArgs: [sale.id]);
        for (final item in sale.items) {
          await txn.insert('sale_items', {
            'id': makeId('sale-item'),
            'sale_id': sale.id,
            'article_id': item.articleId,
            'article_name_snapshot': item.name,
            'article_category_snapshot': state.articles
                .where((a) => a.id == item.articleId)
                .firstOrNull
                ?.category,
            'article_type_snapshot': item.type,
            'icon_snapshot': item.icon,
            'quantity': item.quantity,
            'unit_price': item.price,
            'price_public_snapshot': item.publicPrice,
            'price_member_snapshot': item.memberPrice,
            'line_total': item.price * item.quantity,
          });
        }
      }

      for (final meal in state.meals) {
        await txn.insert('meal_orders', {
          'id': meal.id,
          'session_id': session.id,
          'player_id': meal.playerId,
          'player_name_snapshot': meal.playerName,
          'player_type_snapshot': meal.playerType,
          'source': meal.source,
          'status': meal.status,
          'sale_id': meal.saleId.isEmpty ? null : meal.saleId,
          'payment_method': meal.payment.isEmpty ? null : meal.payment,
          'meal_article_id': meal.mealArticleId,
          'drink_article_id':
              meal.drinkArticleId.isEmpty ? null : meal.drinkArticleId,
          'snack_article_id':
              meal.snackArticleId.isEmpty ? null : meal.snackArticleId,
          'formula': meal.formula,
          'options_json': jsonEncode(meal.options),
          'note': meal.note,
          'created_at': meal.createdAt.toIso8601String(),
          'prepared_at': meal.preparedAt?.toIso8601String(),
          'served_at': meal.servedAt?.toIso8601String(),
          'updated_at': meal.updatedAt.toIso8601String(),
        });
      }

      final cashRows = await txn.query('cash_counts',
          columns: ['id'], where: 'session_id = ?', whereArgs: [session.id]);
      for (final cashId in cashRows.map((row) => '${row['id']}')) {
        await txn.delete('cash_count_lines',
            where: 'cash_count_id = ?', whereArgs: [cashId]);
      }
      await txn.delete('cash_counts',
          where: 'session_id = ?', whereArgs: [session.id]);
      await _insertCash(txn, session.id, 'start', state.cashStart,
          state.cashTotal('start'), now);
      await _insertCash(
          txn, session.id, 'end', state.cashEnd, state.cashTotal('end'), now);
      for (final movement in state.pendingStockMovements) {
        await txn.insert('stock_movements', {
          'id': movement.id,
          'session_id': movement.sessionId,
          'article_id': movement.articleId,
          'sale_id': movement.saleId,
          'movement_type': movement.movementType,
          'quantity_delta': movement.quantityDelta,
          'stock_before': movement.stockBefore,
          'stock_after': movement.stockAfter,
          'reason': movement.reason,
          'created_at': movement.createdAt.toIso8601String(),
        });
      }
    });
    state.pendingStockMovements.clear();
  }

  Future<void> _upsert(
    Transaction txn,
    String table,
    Map<String, Object?> values,
  ) async {
    final id = values['id'];
    final updated =
        await txn.update(table, values, where: 'id = ?', whereArgs: [id]);
    if (updated == 0) await txn.insert(table, values);
  }

  Future<void> _insertCash(Transaction txn, String sessionId, String kind,
      Map<String, int> values, double total, String now) async {
    final cashCountId = makeId('cash-count');
    await txn.insert('cash_counts', {
      'id': cashCountId,
      'session_id': sessionId,
      'kind': kind,
      'total_amount': total,
      'created_at': now,
      'updated_at': now
    });
    for (final entry in values.entries) {
      final denomination = double.tryParse(entry.key) ?? 0;
      await txn.insert('cash_count_lines', {
        'id': makeId('cash-line'),
        'cash_count_id': cashCountId,
        'denomination': denomination,
        'quantity': entry.value,
        'line_total': denomination * entry.value,
      });
    }
  }

  Future<Map<String, dynamic>> exportAll() async {
    final db = await database;
    return sanitizePortableBackupPayload({
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'identity': VisualIdentity.name,
      'data': {
        'sessions': await db.query('sessions'),
        'players': await db.query('players'),
        'sessionPlayers': await db.query('session_players'),
        'articleCategories': await db.query('article_categories'),
        'articles': await db.query('articles'),
        'sales': await db.query('sales'),
        'saleItems': await db.query('sale_items'),
        'mealOrders': await db.query('meal_orders'),
        'stockMovements': await db.query('stock_movements'),
        'cashCounts': await db.query('cash_counts'),
        'cashCountLines': await db.query('cash_count_lines'),
        'appSettings': await _exportAppSettings(db),
      },
    });
  }

  Future<List<Map<String, Object?>>> _exportAppSettings(Database db) async {
    final rows = await db.query('app_settings');
    return rows.map((row) {
      if (row['key'] != 'helloasso_settings') return row;
      try {
        final settings = HelloAssoSettings.fromJson(Map<String, dynamic>.from(
            jsonDecode('${row['value'] ?? '{}'}') as Map));
        return {
          ...row,
          'value': jsonEncode(settings.toJson(includeSecret: false)),
        };
      } catch (_) {
        return {...row, 'value': '{}'};
      }
    }).toList();
  }

  Future<void> replaceFromExport(Map<String, dynamic> payload) async {
    validateBackupPayload(payload);
    final data = Map<String, dynamic>.from(payload['data'] as Map? ?? {});
    final db = await database;
    await db.transaction((txn) async {
      for (final table in [
        'cash_count_lines',
        'cash_counts',
        'stock_movements',
        'meal_orders',
        'sale_items',
        'sales',
        'session_players',
        'articles',
        'article_categories',
        'players',
        'sessions',
        'app_settings'
      ]) {
        await txn.delete(table);
      }
      Future<void> insertRows(String table, String key) async {
        for (final row in (data[key] as List? ?? const [])) {
          final values = Map<String, Object?>.from(row as Map);
          if (table == 'articles' && values['type'] == 'location') {
            values
              ..['stock_current'] = 0
              ..['stock_alert_threshold'] = 0
              ..['bb_auto_quantity'] = 0
              ..['gas_auto_quantity'] = 0;
          }
          if (table == 'app_settings' &&
              values['key'] == 'helloasso_settings') {
            try {
              final settings = HelloAssoSettings.fromJson(
                  Map<String, dynamic>.from(
                      jsonDecode('${values['value'] ?? '{}'}') as Map));
              values['value'] =
                  jsonEncode(settings.toJson(includeSecret: false));
            } catch (_) {
              values['value'] = '{}';
            }
          }
          await txn.insert(table, values,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }

      await insertRows('sessions', 'sessions');
      await insertRows('players', 'players');
      await insertRows('session_players', 'sessionPlayers');
      await insertRows('article_categories', 'articleCategories');
      await insertRows('articles', 'articles');
      await insertRows('sales', 'sales');
      await insertRows('sale_items', 'saleItems');
      await insertRows('meal_orders', 'mealOrders');
      await insertRows('stock_movements', 'stockMovements');
      await insertRows('cash_counts', 'cashCounts');
      await insertRows('cash_count_lines', 'cashCountLines');
      await insertRows('app_settings', 'appSettings');
    });
  }

  Future<bool> hasOnlyBootstrapData() async {
    final db = await database;
    Future<int> count(String table) async =>
        Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $table')) ??
        0;

    final players = await count('players');
    final sessionPlayers = await count('session_players');
    final sales = await count('sales');
    final saleItems = await count('sale_items');
    final mealOrders = await count('meal_orders');
    final stockMovements = await count('stock_movements');
    final cashCounts = await count('cash_counts');
    final cashCountLines = await count('cash_count_lines');
    final sessions = await count('sessions');
    final articles = await count('articles');

    return players == 0 &&
        sessionPlayers == 0 &&
        sales == 0 &&
        saleItems == 0 &&
        mealOrders == 0 &&
        stockMovements == 0 &&
        cashCounts == 0 &&
        cashCountLines == 0 &&
        sessions <= 1 &&
        articles <= defaultArticles().length;
  }
}

void validateBackupPayload(Map<String, dynamic> payload) {
  final version = (payload['version'] as num?)?.round();
  final data = payload['data'];
  if (version == null || version < 2 || version > 3 || data is! Map) {
    throw const FormatException('Version ou format de sauvegarde non supporté');
  }
  final typedData = Map<String, dynamic>.from(data);
  final requiredTables = version >= 3
      ? _backupTableSpecs.keys
      : const ['sessions', 'articles', 'appSettings'];
  for (final key in requiredTables) {
    if (typedData[key] is! List) {
      throw FormatException('Sauvegarde incomplète : données "$key" absentes');
    }
  }
  if ((typedData['sessions'] as List).isEmpty) {
    throw const FormatException('Sauvegarde invalide : aucune session');
  }

  final validatedRows = <String, List<Map<String, Object?>>>{};
  for (final entry in _backupTableSpecs.entries) {
    final rawRows = typedData[entry.key];
    if (rawRows == null) {
      validatedRows[entry.key] = const [];
      continue;
    }
    if (rawRows is! List) {
      throw FormatException(
          'Sauvegarde invalide : données "${entry.key}" illisibles');
    }
    final rows = <Map<String, Object?>>[];
    for (var index = 0; index < rawRows.length; index++) {
      final rawRow = rawRows[index];
      if (rawRow is! Map) {
        throw FormatException(
            'Sauvegarde invalide : ligne ${index + 1} de "${entry.key}" illisible');
      }
      Map<String, Object?> row;
      try {
        row = Map<String, Object?>.from(rawRow);
      } catch (_) {
        throw FormatException(
            'Sauvegarde invalide : colonnes de "${entry.key}" illisibles');
      }
      _validateBackupRow(entry.key, index, row, entry.value);
      rows.add(row);
    }
    _ensureUniqueBackupIds(entry.key, rows);
    validatedRows[entry.key] = rows;
  }

  _validateBackupReferences(validatedRows);
}

class _BackupTableSpec {
  const _BackupTableSpec({
    required this.columns,
    required this.required,
    this.numeric = const {},
  });

  final Set<String> columns;
  final Set<String> required;
  final Set<String> numeric;
}

const _backupTableSpecs = <String, _BackupTableSpec>{
  'sessions': _BackupTableSpec(
    columns: {
      'id',
      'name',
      'event_date',
      'status',
      'notes',
      'helloasso_form_slug',
      'helloasso_form_type',
      'helloasso_event_name',
      'helloasso_event_url',
      'helloasso_event_id',
      'helloasso_synced_at',
      'created_at',
      'closed_at',
    },
    required: {'id', 'name', 'event_date', 'status', 'created_at'},
  ),
  'players': _BackupTableSpec(
    columns: {
      'id',
      'name',
      'first_name',
      'last_name',
      'email',
      'helloasso_user_id',
      'type',
      'created_at',
      'updated_at',
      'deleted_at',
    },
    required: {'id', 'name', 'type', 'created_at'},
  ),
  'sessionPlayers': _BackupTableSpec(
    columns: {
      'id',
      'session_id',
      'player_id',
      'name_snapshot',
      'type_snapshot',
      'created_at',
    },
    required: {
      'id',
      'session_id',
      'name_snapshot',
      'type_snapshot',
      'created_at',
    },
  ),
  'articleCategories': _BackupTableSpec(
    columns: {'id', 'name', 'sort_order'},
    required: {'id', 'name', 'sort_order'},
    numeric: {'sort_order'},
  ),
  'articles': _BackupTableSpec(
    columns: {
      'id',
      'category_id',
      'name',
      'type',
      'icon',
      'price_public',
      'price_member',
      'stock_current',
      'stock_alert_threshold',
      'bb_auto_quantity',
      'gas_auto_quantity',
      'is_active',
      'sort_order',
      'created_at',
      'updated_at',
    },
    required: {
      'id',
      'name',
      'type',
      'price_public',
      'price_member',
      'stock_current',
      'stock_alert_threshold',
      'bb_auto_quantity',
      'gas_auto_quantity',
      'is_active',
      'sort_order',
      'created_at',
    },
    numeric: {
      'price_public',
      'price_member',
      'stock_current',
      'stock_alert_threshold',
      'bb_auto_quantity',
      'gas_auto_quantity',
      'is_active',
      'sort_order',
    },
  ),
  'sales': _BackupTableSpec(
    columns: {
      'id',
      'session_id',
      'session_player_id',
      'player_id',
      'player_name_snapshot',
      'player_type_snapshot',
      'tariff_applied',
      'payment_method',
      'status',
      'total_articles',
      'donation_amount',
      'total_amount',
      'created_at',
      'cancelled_at',
      'cancellation_reason',
    },
    required: {
      'id',
      'session_id',
      'player_name_snapshot',
      'player_type_snapshot',
      'tariff_applied',
      'payment_method',
      'status',
      'total_articles',
      'donation_amount',
      'total_amount',
      'created_at',
    },
    numeric: {'total_articles', 'donation_amount', 'total_amount'},
  ),
  'saleItems': _BackupTableSpec(
    columns: {
      'id',
      'sale_id',
      'article_id',
      'article_name_snapshot',
      'article_category_snapshot',
      'article_type_snapshot',
      'icon_snapshot',
      'quantity',
      'unit_price',
      'price_public_snapshot',
      'price_member_snapshot',
      'line_total',
    },
    required: {
      'id',
      'sale_id',
      'article_name_snapshot',
      'article_type_snapshot',
      'quantity',
      'unit_price',
      'price_public_snapshot',
      'price_member_snapshot',
      'line_total',
    },
    numeric: {
      'quantity',
      'unit_price',
      'price_public_snapshot',
      'price_member_snapshot',
      'line_total',
    },
  ),
  'mealOrders': _BackupTableSpec(
    columns: {
      'id',
      'session_id',
      'player_id',
      'player_name_snapshot',
      'player_type_snapshot',
      'source',
      'status',
      'sale_id',
      'payment_method',
      'meal_article_id',
      'drink_article_id',
      'snack_article_id',
      'formula',
      'options_json',
      'note',
      'created_at',
      'prepared_at',
      'served_at',
      'updated_at',
    },
    required: {
      'id',
      'session_id',
      'player_name_snapshot',
      'player_type_snapshot',
      'source',
      'status',
      'meal_article_id',
      'formula',
      'created_at',
      'updated_at',
    },
  ),
  'stockMovements': _BackupTableSpec(
    columns: {
      'id',
      'session_id',
      'article_id',
      'sale_id',
      'movement_type',
      'quantity_delta',
      'stock_before',
      'stock_after',
      'reason',
      'created_at',
    },
    required: {
      'id',
      'session_id',
      'article_id',
      'movement_type',
      'quantity_delta',
      'stock_before',
      'stock_after',
      'created_at',
    },
    numeric: {'quantity_delta', 'stock_before', 'stock_after'},
  ),
  'cashCounts': _BackupTableSpec(
    columns: {
      'id',
      'session_id',
      'kind',
      'total_amount',
      'created_at',
      'updated_at',
    },
    required: {'id', 'session_id', 'kind', 'total_amount', 'created_at'},
    numeric: {'total_amount'},
  ),
  'cashCountLines': _BackupTableSpec(
    columns: {
      'id',
      'cash_count_id',
      'denomination',
      'quantity',
      'line_total',
    },
    required: {
      'id',
      'cash_count_id',
      'denomination',
      'quantity',
      'line_total',
    },
    numeric: {'denomination', 'quantity', 'line_total'},
  ),
  'appSettings': _BackupTableSpec(
    columns: {'key', 'value', 'updated_at'},
    required: {'key'},
  ),
};

void _validateBackupRow(
  String table,
  int index,
  Map<String, Object?> row,
  _BackupTableSpec spec,
) {
  final unknownColumns = row.keys.where((key) => !spec.columns.contains(key));
  if (unknownColumns.isNotEmpty) {
    throw FormatException(
        'Sauvegarde invalide : colonne "${unknownColumns.first}" inconnue dans "$table"');
  }
  for (final column in spec.required) {
    final value = row[column];
    if (value == null || (value is String && value.trim().isEmpty)) {
      throw FormatException(
          'Sauvegarde invalide : "$table.$column" absent à la ligne ${index + 1}');
    }
  }
  for (final entry in row.entries) {
    final value = entry.value;
    if (value == null) continue;
    final validType =
        spec.numeric.contains(entry.key) ? value is num : value is String;
    if (!validType) {
      throw FormatException(
          'Sauvegarde invalide : type incorrect pour "$table.${entry.key}"');
    }
  }
}

void _ensureUniqueBackupIds(String table, List<Map<String, Object?>> rows) {
  final identityColumn = table == 'appSettings' ? 'key' : 'id';
  final identities = <String>{};
  for (final row in rows) {
    final identity = '${row[identityColumn] ?? ''}';
    if (!identities.add(identity)) {
      throw FormatException(
          'Sauvegarde invalide : identifiant dupliqué dans "$table"');
    }
  }
}

void _validateBackupReferences(
    Map<String, List<Map<String, Object?>>> rowsByTable) {
  Set<String> ids(String table) =>
      rowsByTable[table]!.map((row) => '${row['id']}').toSet();

  final sessions = ids('sessions');
  final players = ids('players');
  final sessionPlayers = ids('sessionPlayers');
  final categories = ids('articleCategories');
  final articles = ids('articles');
  final sales = ids('sales');
  final cashCounts = ids('cashCounts');

  void check(
    String table,
    String column,
    Set<String> targets, {
    required String targetLabel,
  }) {
    for (final row in rowsByTable[table]!) {
      final value = row[column];
      if (value == null || '$value'.isEmpty) continue;
      if (!targets.contains('$value')) {
        throw FormatException(
            'Sauvegarde invalide : "$table.$column" référence $targetLabel absent');
      }
    }
  }

  check('sessionPlayers', 'session_id', sessions, targetLabel: 'une session');
  check('sessionPlayers', 'player_id', players, targetLabel: 'un participant');
  check('articles', 'category_id', categories, targetLabel: 'une catégorie');
  check('sales', 'session_id', sessions, targetLabel: 'une session');
  check('sales', 'session_player_id', sessionPlayers,
      targetLabel: 'un participant de session');
  check('sales', 'player_id', players, targetLabel: 'un participant');
  check('saleItems', 'sale_id', sales, targetLabel: 'une vente');
  check('saleItems', 'article_id', articles, targetLabel: 'un article');
  check('mealOrders', 'session_id', sessions, targetLabel: 'une session');
  check('mealOrders', 'player_id', players, targetLabel: 'un participant');
  check('mealOrders', 'sale_id', sales, targetLabel: 'une vente');
  check('stockMovements', 'session_id', sessions, targetLabel: 'une session');
  check('stockMovements', 'article_id', articles, targetLabel: 'un article');
  check('stockMovements', 'sale_id', sales, targetLabel: 'une vente');
  check('cashCounts', 'session_id', sessions, targetLabel: 'une session');
  check('cashCountLines', 'cash_count_id', cashCounts,
      targetLabel: 'un comptage');

  for (final row in rowsByTable['appSettings']!) {
    if (row['key'] != 'active_session_id') continue;
    final activeSessionId = '${row['value'] ?? ''}';
    if (activeSessionId.isNotEmpty && !sessions.contains(activeSessionId)) {
      throw const FormatException(
          'Sauvegarde invalide : la session active est absente');
    }
  }
}

Map<String, dynamic> sanitizePortableBackupPayload(
    Map<String, dynamic> sourcePayload) {
  final payload =
      Map<String, dynamic>.from(jsonDecode(jsonEncode(sourcePayload)) as Map);
  final data = payload['data'];
  if (data is! Map) return payload;
  final rows = data['appSettings'];
  if (rows is! List) return payload;
  for (final row in rows.whereType<Map>()) {
    if (row['key'] != 'helloasso_settings') continue;
    try {
      final settings = HelloAssoSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode('${row['value']}') as Map));
      row['value'] = jsonEncode(settings.toJson(includeSecret: false));
    } catch (_) {
      row['value'] = '{}';
    }
  }
  return payload;
}
