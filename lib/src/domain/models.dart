import 'dart:convert';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

class Article {
  Article({
    required this.id,
    required this.category,
    required this.type,
    required this.icon,
    required this.name,
    required this.price,
    required this.memberPrice,
    required this.stock,
    required this.threshold,
    this.bbAuto = 0,
    this.gasAuto = 0,
  });

  final String id;
  String category;
  String type;
  String icon;
  String name;
  double price;
  double memberPrice;
  int stock;
  int threshold;
  double bbAuto;
  double gasAuto;

  bool get isLocation => type == 'location';
  bool get tracksStock => !isLocation && threshold > 0;

  double priceFor(bool member) =>
      member && memberPrice > 0 ? memberPrice : price;

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'type': type,
        'icon': icon,
        'name': name,
        'price': price,
        'memberPrice': memberPrice,
        'stock': stock,
        'threshold': threshold,
        'bbAuto': bbAuto,
        'gasAuto': gasAuto,
      };

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: '${json['id'] ?? DateTime.now().microsecondsSinceEpoch}',
        category: '${json['category'] ?? json['cat'] ?? 'DIVERS'}',
        type: '${json['type'] ?? 'standard'}',
        icon: '${json['icon'] ?? '📦'}',
        name: '${json['name'] ?? json['nom'] ?? 'Article'}',
        price: (json['price'] ?? json['prix'] ?? 0).toDouble(),
        memberPrice: (json['memberPrice'] ?? json['prixM'] ?? 0).toDouble(),
        stock: (json['stock'] ?? 0).round(),
        threshold: (json['threshold'] ?? json['seuil'] ?? 0).round(),
        bbAuto: (json['bbAuto'] ?? 0).toDouble(),
        gasAuto: (json['gasAuto'] ?? 0).toDouble(),
      );
}

String makeId([String prefix = 'id']) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';

String stableCategoryId(String category) {
  final normalized = category
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return normalized.isEmpty ? 'divers' : normalized;
}

String normalizedCategoryName(String category) => category.trim().toUpperCase();

List<String> defaultArticleCategories() => [
      'BOISSONS',
      'REPAS',
      'SNACKING',
      'GOODIES',
      'LOCATION',
    ];

class AppTabIds {
  static const sales = 'sales';
  static const meals = 'meals';
  static const players = 'players';
  static const cash = 'cash';
  static const stats = 'stats';
  static const bilan = 'bilan';
  static const history = 'history';
  static const articles = 'articles';
  static const config = 'config';

  static const configurable = <String>[
    meals,
    players,
    cash,
    stats,
    bilan,
    articles,
  ];

  static const all = <String>[
    sales,
    meals,
    players,
    cash,
    stats,
    bilan,
    history,
    articles,
    config,
  ];
}

const _defaultMainTabVisibility = <String, bool>{
  AppTabIds.meals: true,
  AppTabIds.players: true,
  AppTabIds.cash: true,
  AppTabIds.stats: true,
  AppTabIds.bilan: true,
  AppTabIds.articles: true,
};

class AppSettings {
  const AppSettings({
    this.associationName = 'TILLY',
    this.appIconPath = '',
    this.primaryColorValue = 0xFFC8F135,
    this.mealsEnabled = true,
    this.mainTabVisibility = _defaultMainTabVisibility,
  });

  final String associationName;
  final String appIconPath;
  final int primaryColorValue;
  final bool mealsEnabled;
  final Map<String, bool> mainTabVisibility;

  bool isMainTabVisible(String id) => mainTabVisibility[id] ?? true;
  Color get primaryColor => Color(primaryColorValue);

  AppSettings copyWith({
    String? associationName,
    String? appIconPath,
    int? primaryColorValue,
    bool? mealsEnabled,
    Map<String, bool>? mainTabVisibility,
  }) {
    return AppSettings(
      associationName: associationName ?? this.associationName,
      appIconPath: appIconPath ?? this.appIconPath,
      primaryColorValue: primaryColorValue ?? this.primaryColorValue,
      mealsEnabled: mealsEnabled ?? this.mealsEnabled,
      mainTabVisibility: mainTabVisibility ?? this.mainTabVisibility,
    );
  }

  Map<String, dynamic> toJson() => {
        'associationName': associationName,
        'appIconPath': appIconPath,
        'primaryColorValue': primaryColorValue,
        'mealsEnabled': mealsEnabled,
        'mainTabVisibility': mainTabVisibility,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final visibility = <String, bool>{..._defaultMainTabVisibility};
    final storedVisibility = json['mainTabVisibility'];
    if (storedVisibility is Map) {
      for (final entry in storedVisibility.entries) {
        if (AppTabIds.configurable.contains('${entry.key}')) {
          visibility['${entry.key}'] = entry.value == true;
        }
      }
    }
    final rawName = '${json['associationName'] ?? ''}'.trim();
    return AppSettings(
      associationName: rawName.isEmpty ? 'TILLY' : rawName,
      appIconPath: '${json['appIconPath'] ?? ''}'.trim(),
      primaryColorValue:
          parseColorValue(json['primaryColorValue']) ?? 0xFFC8F135,
      mealsEnabled: json['mealsEnabled'] != false,
      mainTabVisibility: visibility,
    );
  }
}

int? parseColorValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  final text = '$value'.trim();
  if (text.isEmpty) return null;
  final normalized = text
      .replaceFirst('#', '')
      .replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (hex.length != 8) return null;
  return int.tryParse(hex, radix: 16);
}

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.name,
    required this.eventDate,
    this.status = 'open',
    this.notes = '',
    this.helloassoFormSlug = '',
    this.helloassoFormType = '',
    this.helloassoEventName = '',
    this.helloassoEventUrl = '',
    this.helloassoEventId = '',
    this.helloassoSyncedAt,
    DateTime? createdAt,
    this.closedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  DateTime eventDate;
  String status;
  String notes;
  String helloassoFormSlug;
  String helloassoFormType;
  String helloassoEventName;
  String helloassoEventUrl;
  String helloassoEventId;
  DateTime? helloassoSyncedAt;
  DateTime createdAt;
  DateTime? closedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'eventDate': eventDate.toIso8601String(),
        'status': status,
        'notes': notes,
        'helloassoFormSlug': helloassoFormSlug,
        'helloassoFormType': helloassoFormType,
        'helloassoEventName': helloassoEventName,
        'helloassoEventUrl': helloassoEventUrl,
        'helloassoEventId': helloassoEventId,
        'helloassoSyncedAt': helloassoSyncedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'closedAt': closedAt?.toIso8601String(),
      };

  factory SessionRecord.fromJson(Map<String, dynamic> json) => SessionRecord(
        id: '${json['id'] ?? makeId('session')}',
        name: '${json['name'] ?? json['session'] ?? 'Événement'}',
        eventDate: DateTime.tryParse(
                '${json['eventDate'] ?? json['event_date'] ?? ''}') ??
            DateTime.now(),
        status: '${json['status'] ?? 'open'}',
        notes: '${json['notes'] ?? ''}',
        helloassoFormSlug:
            '${json['helloassoFormSlug'] ?? json['helloasso_form_slug'] ?? ''}',
        helloassoFormType:
            '${json['helloassoFormType'] ?? json['helloasso_form_type'] ?? ''}',
        helloassoEventName:
            '${json['helloassoEventName'] ?? json['helloasso_event_name'] ?? ''}',
        helloassoEventUrl:
            '${json['helloassoEventUrl'] ?? json['helloasso_event_url'] ?? ''}',
        helloassoEventId:
            '${json['helloassoEventId'] ?? json['helloasso_event_id'] ?? ''}',
        helloassoSyncedAt: DateTime.tryParse(
            '${json['helloassoSyncedAt'] ?? json['helloasso_synced_at'] ?? ''}'),
        createdAt: DateTime.tryParse(
                '${json['createdAt'] ?? json['created_at'] ?? ''}') ??
            DateTime.now(),
        closedAt:
            DateTime.tryParse('${json['closedAt'] ?? json['closed_at'] ?? ''}'),
      );
}

class Player {
  Player({
    required this.id,
    required this.name,
    required this.type,
    this.firstName = '',
    this.lastName = '',
    this.email = '',
    this.helloassoUserId = '',
  });

  final String id;
  String name;
  String type;
  String firstName;
  String lastName;
  String email;
  String helloassoUserId;

  bool get isMember => type == 'membre';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'helloassoUserId': helloassoUserId,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: '${json['id'] ?? makeId('player')}',
        name:
            '${json['name'] ?? json['nom'] ?? playerNameFromParts('${json['firstName'] ?? ''}', '${json['lastName'] ?? ''}', 'Participant')}',
        type: '${json['type'] ?? 'public'}',
        firstName: '${json['firstName'] ?? json['first_name'] ?? ''}',
        lastName: '${json['lastName'] ?? json['last_name'] ?? ''}',
        email: '${json['email'] ?? ''}'.trim().toLowerCase(),
        helloassoUserId:
            '${json['helloassoUserId'] ?? json['helloasso_user_id'] ?? ''}',
      );
}

String playerNameFromParts(String firstName, String lastName, String fallback) {
  final fullName = [firstName.trim(), lastName.trim()]
      .where((part) => part.isNotEmpty)
      .join(' ');
  return fullName.isEmpty ? fallback.trim() : fullName;
}

({String firstName, String lastName}) splitPlayerName(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return (firstName: '', lastName: '');
  if (parts.length == 1) return (firstName: parts.first, lastName: '');
  return (firstName: parts.first, lastName: parts.skip(1).join(' '));
}

class CartItem {
  CartItem(
      {required this.articleId, required this.quantity, required this.price});

  final String articleId;
  int quantity;
  double price;
}

class SaleItem {
  SaleItem({
    required this.articleId,
    required this.name,
    required this.icon,
    required this.type,
    required this.quantity,
    required this.price,
    required this.publicPrice,
    required this.memberPrice,
  });

  final String articleId;
  final String name;
  final String icon;
  final String type;
  final int quantity;
  final double price;
  final double publicPrice;
  final double memberPrice;

  Map<String, dynamic> toJson() => {
        'articleId': articleId,
        'name': name,
        'icon': icon,
        'type': type,
        'quantity': quantity,
        'price': price,
        'publicPrice': publicPrice,
        'memberPrice': memberPrice,
      };

  factory SaleItem.fromJson(Map<String, dynamic> json) => SaleItem(
        articleId: '${json['articleId'] ?? json['nom'] ?? json['name']}',
        name: '${json['name'] ?? json['nom'] ?? 'Article'}',
        icon: '${json['icon'] ?? '📦'}',
        type: '${json['type'] ?? 'standard'}',
        quantity: (json['quantity'] ?? json['qte'] ?? 1).round(),
        price: (json['price'] ?? json['prix'] ?? 0).toDouble(),
        publicPrice:
            (json['publicPrice'] ?? json['prixPublic'] ?? json['price'] ?? 0)
                .toDouble(),
        memberPrice: (json['memberPrice'] ?? json['prixM'] ?? 0).toDouble(),
      );
}

class Sale {
  Sale({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.playerType,
    required this.tariff,
    required this.items,
    required this.totalArticles,
    required this.donation,
    required this.payment,
    required this.session,
    required this.createdAt,
    this.status = 'active',
    this.cancelledAt,
    this.cancellationReason = '',
  });

  final String id;
  final String playerId;
  String playerName;
  final String playerType;
  final String tariff;
  final List<SaleItem> items;
  final double totalArticles;
  final double donation;
  final String payment;
  final String session;
  final DateTime createdAt;
  final String status;
  final DateTime? cancelledAt;
  final String cancellationReason;

  double get total => totalArticles + donation;
  bool get isActive => status == 'active';

  Sale copyWith({
    String? playerName,
    String? status,
    DateTime? cancelledAt,
    String? cancellationReason,
  }) =>
      Sale(
        id: id,
        playerId: playerId,
        playerName: playerName ?? this.playerName,
        playerType: playerType,
        tariff: tariff,
        items: items,
        totalArticles: totalArticles,
        donation: donation,
        payment: payment,
        session: session,
        createdAt: createdAt,
        status: status ?? this.status,
        cancelledAt: cancelledAt ?? this.cancelledAt,
        cancellationReason: cancellationReason ?? this.cancellationReason,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'playerId': playerId,
        'playerName': playerName,
        'playerType': playerType,
        'tariff': tariff,
        'items': items.map((e) => e.toJson()).toList(),
        'totalArticles': totalArticles,
        'donation': donation,
        'payment': payment,
        'session': session,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'cancelledAt': cancelledAt?.toIso8601String(),
        'cancellationReason': cancellationReason,
      };

  factory Sale.fromJson(Map<String, dynamic> json) => Sale(
        id: '${json['id'] ?? makeId('sale')}',
        playerId: '${json['playerId'] ?? json['joueurId'] ?? ''}',
        playerName:
            '${json['playerName'] ?? json['joueurNom'] ?? 'Participant'}',
        playerType: '${json['playerType'] ?? json['joueurType'] ?? 'public'}',
        tariff: '${json['tariff'] ?? json['tarif'] ?? 'public'}',
        items: ((json['items'] ?? []) as List)
            .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        totalArticles: (json['totalArticles'] ?? 0).toDouble(),
        donation: (json['donation'] ?? json['don'] ?? 0).toDouble(),
        payment: '${json['payment'] ?? json['paiement'] ?? 'ESP'}',
        session: '${json['session'] ?? ''}',
        createdAt:
            DateTime.tryParse('${json['createdAt'] ?? ''}') ?? DateTime.now(),
        status: '${json['status'] ?? 'active'}',
        cancelledAt: DateTime.tryParse('${json['cancelledAt'] ?? ''}'),
        cancellationReason: '${json['cancellationReason'] ?? ''}',
      );
}

class StockMovement {
  StockMovement({
    required this.id,
    required this.sessionId,
    required this.articleId,
    required this.movementType,
    required this.quantityDelta,
    required this.stockBefore,
    required this.stockAfter,
    required this.reason,
    required this.createdAt,
    this.saleId,
  });

  final String id;
  final String sessionId;
  final String articleId;
  final String? saleId;
  final String movementType;
  final int quantityDelta;
  final int stockBefore;
  final int stockAfter;
  final String reason;
  final DateTime createdAt;
}

class StockShortage {
  const StockShortage({
    required this.article,
    required this.requiredQuantity,
    required this.availableQuantity,
  });

  final Article article;
  final int requiredQuantity;
  final int availableQuantity;

  String get message =>
      '${article.name} : $requiredQuantity requis, $availableQuantity disponible(s)';
}

class MealOrder {
  MealOrder({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.playerType,
    required this.source,
    required this.status,
    required this.mealArticleId,
    required this.formula,
    required this.createdAt,
    this.saleId = '',
    this.payment = '',
    this.drinkArticleId = '',
    this.snackArticleId = '',
    List<String>? options,
    this.note = '',
    this.preparedAt,
    this.servedAt,
    DateTime? updatedAt,
  })  : options = options ?? [],
        updatedAt = updatedAt ?? createdAt;

  final String id;
  final String playerId;
  String playerName;
  final String playerType;
  final String source;
  String status;
  String saleId;
  final String payment;
  String mealArticleId;
  String drinkArticleId;
  String snackArticleId;
  String formula;
  List<String> options;
  String note;
  final DateTime createdAt;
  DateTime? preparedAt;
  DateTime? servedAt;
  DateTime updatedAt;

  bool get consumesStock => status == 'prepared' || status == 'served';
  bool get isOnsite => source == 'onsite';
  Map<String, int> get stockItems {
    final result = <String, int>{};
    for (final articleId in [
      mealArticleId,
      drinkArticleId,
      snackArticleId,
    ]) {
      if (articleId.isNotEmpty) {
        result[articleId] = (result[articleId] ?? 0) + 1;
      }
    }
    return result;
  }

  MealOrder copyWith({
    String? status,
    String? saleId,
    String? mealArticleId,
    String? drinkArticleId,
    String? snackArticleId,
    String? formula,
    List<String>? options,
    String? note,
    DateTime? preparedAt,
    DateTime? servedAt,
    DateTime? updatedAt,
  }) =>
      MealOrder(
        id: id,
        playerId: playerId,
        playerName: playerName,
        playerType: playerType,
        source: source,
        status: status ?? this.status,
        saleId: saleId ?? this.saleId,
        payment: payment,
        mealArticleId: mealArticleId ?? this.mealArticleId,
        drinkArticleId: drinkArticleId ?? this.drinkArticleId,
        snackArticleId: snackArticleId ?? this.snackArticleId,
        formula: formula ?? this.formula,
        options: options ?? List<String>.of(this.options),
        note: note ?? this.note,
        createdAt: createdAt,
        preparedAt: preparedAt ?? this.preparedAt,
        servedAt: servedAt ?? this.servedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

const denominations = <double>[
  500,
  200,
  100,
  50,
  20,
  10,
  5,
  2,
  1,
  .5,
  .2,
  .1,
  .05,
  .02,
  .01
];

String money(num value) => '${value.toStringAsFixed(2).replaceAll('.', ',')} €';

String dateLabel(DateTime date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}

String timeLabel(DateTime date) {
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class HelloAssoSettings {
  const HelloAssoSettings({
    this.organizationSlug = '',
    this.clientId = '',
    this.clientSecret = '',
    this.environment = 'production',
  });

  final String organizationSlug;
  final String clientId;
  final String clientSecret;
  final String environment;

  bool get isConfigured =>
      organizationSlug.trim().isNotEmpty &&
      clientId.trim().isNotEmpty &&
      clientSecret.trim().isNotEmpty;
  bool get isSandbox => environment == 'sandbox';
  String get authBaseUrl => isSandbox
      ? 'https://api.helloasso-sandbox.com'
      : 'https://api.helloasso.com';
  String get apiBaseUrl => '$authBaseUrl/v5';

  HelloAssoSettings withoutSecret() => HelloAssoSettings(
        organizationSlug: organizationSlug,
        clientId: clientId,
        environment: environment,
      );

  HelloAssoSettings withSecret(String value) => HelloAssoSettings(
        organizationSlug: organizationSlug,
        clientId: clientId,
        clientSecret: value,
        environment: environment,
      );

  Map<String, dynamic> toJson({bool includeSecret = true}) => {
        'organizationSlug': organizationSlug,
        'clientId': clientId,
        if (includeSecret) 'clientSecret': clientSecret,
        'environment': environment,
      };

  factory HelloAssoSettings.fromJson(Map<String, dynamic> json) =>
      HelloAssoSettings(
        organizationSlug: '${json['organizationSlug'] ?? ''}',
        clientId: '${json['clientId'] ?? ''}',
        clientSecret: '${json['clientSecret'] ?? ''}',
        environment: '${json['environment'] ?? 'production'}' == 'sandbox'
            ? 'sandbox'
            : 'production',
      );
}

class FirebaseSettings {
  const FirebaseSettings({
    this.apiKey = '',
    this.appId = '',
    this.messagingSenderId = '',
    this.projectId = '',
    this.authDomain = '',
    this.storageBucket = '',
    this.measurementId = '',
    this.iosBundleId = '',
  });

  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String authDomain;
  final String storageBucket;
  final String measurementId;
  final String iosBundleId;

  bool get isConfigured =>
      apiKey.trim().isNotEmpty &&
      appId.trim().isNotEmpty &&
      messagingSenderId.trim().isNotEmpty &&
      projectId.trim().isNotEmpty;

  FirebaseOptions toOptions() => FirebaseOptions(
        apiKey: apiKey.trim(),
        appId: appId.trim(),
        messagingSenderId: messagingSenderId.trim(),
        projectId: projectId.trim(),
        authDomain: _optional(authDomain),
        storageBucket: _optional(storageBucket),
        measurementId: _optional(measurementId),
        iosBundleId: _optional(iosBundleId),
      );

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'appId': appId,
        'messagingSenderId': messagingSenderId,
        'projectId': projectId,
        'authDomain': authDomain,
        'storageBucket': storageBucket,
        'measurementId': measurementId,
        'iosBundleId': iosBundleId,
      };

  factory FirebaseSettings.fromJson(Map<String, dynamic> json) =>
      FirebaseSettings(
        apiKey: '${json['apiKey'] ?? ''}',
        appId: '${json['appId'] ?? ''}',
        messagingSenderId: '${json['messagingSenderId'] ?? ''}',
        projectId: '${json['projectId'] ?? ''}',
        authDomain: '${json['authDomain'] ?? ''}',
        storageBucket: '${json['storageBucket'] ?? ''}',
        measurementId: '${json['measurementId'] ?? ''}',
        iosBundleId: '${json['iosBundleId'] ?? ''}',
      );

  static String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

FirebaseSettings parseFirebaseSettings(String source) {
  final value = source.trim();
  if (value.isEmpty) {
    throw const FormatException('Colle la configuration fournie par Firebase');
  }

  try {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      final json = Map<String, dynamic>.from(decoded);
      final googleServices = _firebaseSettingsFromGoogleServices(json);
      if (googleServices != null) return googleServices;
      final settings = FirebaseSettings.fromJson(json);
      if (settings.isConfigured) return settings;
    }
  } catch (_) {}

  final applePlist = _firebaseSettingsFromApplePlist(value);
  if (applePlist != null) return applePlist;

  String field(String name) {
    final match = RegExp(
      '["\']?$name["\']?\\s*:\\s*["\']([^"\']+)["\']',
      caseSensitive: false,
    ).firstMatch(value);
    return match?.group(1)?.trim() ?? '';
  }

  final settings = FirebaseSettings(
    apiKey: field('apiKey'),
    appId: field('appId'),
    messagingSenderId: field('messagingSenderId'),
    projectId: field('projectId'),
    authDomain: field('authDomain'),
    storageBucket: field('storageBucket'),
    measurementId: field('measurementId'),
    iosBundleId: field('iosBundleId'),
  );
  if (!settings.isConfigured) {
    throw const FormatException(
        'Configuration non reconnue. Utilise le bloc fourni par Firebase ou la saisie avancée.');
  }
  return settings;
}

FirebaseSettings? _firebaseSettingsFromApplePlist(String value) {
  String plistField(String key) {
    final match = RegExp(
      '<key>\\s*${RegExp.escape(key)}\\s*</key>\\s*<string>([^<]*)</string>',
      caseSensitive: false,
    ).firstMatch(value);
    return _decodeXmlValue(match?.group(1) ?? '').trim();
  }

  final settings = FirebaseSettings(
    apiKey: plistField('API_KEY'),
    appId: plistField('GOOGLE_APP_ID'),
    messagingSenderId: plistField('GCM_SENDER_ID'),
    projectId: plistField('PROJECT_ID'),
    storageBucket: plistField('STORAGE_BUCKET'),
    iosBundleId: plistField('BUNDLE_ID'),
  );
  return settings.isConfigured ? settings : null;
}

String _decodeXmlValue(String value) => value
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'");

FirebaseSettings? _firebaseSettingsFromGoogleServices(
    Map<String, dynamic> json) {
  final projectInfo = json['project_info'];
  final clients = json['client'];
  if (projectInfo is! Map || clients is! List || clients.isEmpty) return null;
  final client = clients.first;
  if (client is! Map) return null;
  final clientInfo = client['client_info'];
  final apiKeys = client['api_key'];
  if (clientInfo is! Map || apiKeys is! List || apiKeys.isEmpty) return null;
  final apiKey = apiKeys.first;
  if (apiKey is! Map) return null;

  final settings = FirebaseSettings(
    apiKey: '${apiKey['current_key'] ?? ''}',
    appId: '${clientInfo['mobilesdk_app_id'] ?? ''}',
    messagingSenderId: '${projectInfo['project_number'] ?? ''}',
    projectId: '${projectInfo['project_id'] ?? ''}',
    storageBucket: '${projectInfo['storage_bucket'] ?? ''}',
  );
  return settings.isConfigured ? settings : null;
}

class HelloAssoEvent {
  const HelloAssoEvent({
    required this.name,
    required this.formSlug,
    required this.url,
    this.formType = 'Event',
    this.id = '',
  });

  final String name;
  final String formSlug;
  final String formType;
  final String url;
  final String id;
}

class HelloAssoRegistrant {
  const HelloAssoRegistrant({
    required this.firstName,
    required this.lastName,
    required this.email,
    this.helloassoUserId = '',
    this.hasMeal = false,
    this.mealLabel = '',
  });

  final String firstName;
  final String lastName;
  final String email;
  final String helloassoUserId;
  final bool hasMeal;
  final String mealLabel;
}

List<Article> defaultArticles() => [];
