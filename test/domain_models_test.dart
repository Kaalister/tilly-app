import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/tilly.dart';

import 'support/test_doubles.dart';

void main() {
  group('Article', () {
    test('tracks stock only for standard articles above threshold zero', () {
      expect(testArticle(stock: 1, threshold: 1).tracksStock, isTrue);
      expect(testArticle(stock: 1, threshold: 0).tracksStock, isFalse);
      expect(
          testArticle(type: 'location', stock: 1, threshold: 5).tracksStock,
          isFalse);
    });

    test('priceFor prefers the member price when positive', () {
      final article = testArticle(price: 5, memberPrice: 4);
      expect(article.priceFor(true), 4);
      expect(article.priceFor(false), 5);
    });

    test('priceFor falls back to the public price without member price', () {
      final article = testArticle(price: 5, memberPrice: 0);
      expect(article.priceFor(true), 5);
    });

    test('toJson/fromJson round-trips every field', () {
      final article = testArticle(
          id: 'a-42',
          category: 'SNACKING',
          type: 'standard',
          icon: '🍟',
          name: 'Chips',
          price: 2,
          memberPrice: 1.5,
          stock: 30,
          threshold: 8);
      final restored = Article.fromJson(article.toJson());
      expect(restored.id, 'a-42');
      expect(restored.category, 'SNACKING');
      expect(restored.type, 'standard');
      expect(restored.icon, '🍟');
      expect(restored.name, 'Chips');
      expect(restored.price, 2);
      expect(restored.memberPrice, 1.5);
      expect(restored.stock, 30);
      expect(restored.threshold, 8);
    });

    test('fromJson reads legacy keys and applies defaults', () {
      final restored = Article.fromJson({
        'id': 'legacy',
        'cat': 'DIVERS',
        'nom': 'Pommes',
        'prix': 3,
        'prixM': 2,
        'seuil': 4,
      });
      expect(restored.id, 'legacy');
      expect(restored.category, 'DIVERS');
      expect(restored.name, 'Pommes');
      expect(restored.price, 3);
      expect(restored.memberPrice, 2);
      expect(restored.threshold, 4);
      expect(restored.type, 'standard');
      expect(restored.icon, '📦');
    });

    test('fromJson without id generates a fresh identifier', () {
      final restored = Article.fromJson({});
      expect(restored.id, isNotEmpty);
      expect(restored.category, 'DIVERS');
      expect(restored.name, 'Article');
      expect(restored.stock, 0);
      expect(restored.threshold, 0);
    });
  });

  group('category helpers', () {
    test('makeId uses the requested prefix', () {
      expect(makeId('meal'), startsWith('meal-'));
      expect(makeId(), startsWith('id-'));
    });

    test('normalizedCategoryName uppercases and trims', () {
      expect(normalizedCategoryName('  repas '), 'REPAS');
      expect(normalizedCategoryName('snacking'), 'SNACKING');
    });

    test('stableCategoryId slugs any category name', () {
      expect(stableCategoryId('Snacking'), 'snacking');
      expect(stableCategoryId('Boissons / Fraîches'), 'boissons-fra-ches');
      expect(stableCategoryId('Bar à jus'), 'bar-jus');
      expect(stableCategoryId('  '), 'divers');
      expect(stableCategoryId('!!!'), 'divers');
    });

    test('default catalog is empty with the five reference categories', () {
      expect(defaultArticles(), isEmpty);
      expect(defaultArticleCategories(),
          ['BOISSONS', 'REPAS', 'SNACKING', 'GOODIES', 'LOCATION']);
    });

    test('AppTabIds expose the configurable subsets', () {
      expect(AppTabIds.configurable, isNot(contains(AppTabIds.sales)));
      expect(AppTabIds.configurable, contains(AppTabIds.meals));
      expect(AppTabIds.all, contains(AppTabIds.config));
      expect(AppTabIds.all.length, 9);
    });
  });

  group('AppSettings', () {
    test('defaults favour meals and visible tabs', () {
      const settings = AppSettings();
      expect(settings.associationName, 'TILLY');
      expect(settings.mealsEnabled, isTrue);
      expect(settings.primaryColorValue, 0xFFC8F135);
      expect(settings.isMainTabVisible(AppTabIds.meals), isTrue);
      expect(settings.isMainTabVisible('inconnu'), isTrue);
    });

    test('copyWith only replaces provided values', () {
      const settings = AppSettings();
      final updated = settings.copyWith(mealsEnabled: false);
      expect(updated.mealsEnabled, isFalse);
      expect(updated.associationName, 'TILLY');
      expect(updated.primaryColorValue, settings.primaryColorValue);
    });

    test('toJson/fromJson round-trips', () {
      final settings = AppSettings(
        associationName: 'Frag Addict',
        appIconPath: '/tmp/icon.png',
        primaryColorValue: 0xFF112233,
        mealsEnabled: false,
        mainTabVisibility: {
          ..._defaultVisibility(),
          AppTabIds.meals: false,
        },
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.associationName, 'Frag Addict');
      expect(restored.appIconPath, '/tmp/icon.png');
      expect(restored.primaryColorValue, 0xFF112233);
      expect(restored.mealsEnabled, isFalse);
      expect(restored.isMainTabVisible(AppTabIds.meals), isFalse);
    });

    test('fromJson sanitizes names, unknown tabs and bad colors', () {
      final restored = AppSettings.fromJson({
        'associationName': '   ',
        'primaryColorValue': 'nawak',
        'mainTabVisibility': {
          'stats': false,
          'inconnu': false,
          'sales': false,
        },
      });
      expect(restored.associationName, 'TILLY');
      expect(restored.primaryColorValue, 0xFFC8F135);
      expect(restored.isMainTabVisible(AppTabIds.stats), isFalse);
      expect(restored.isMainTabVisible('inconnu'), isTrue);
      expect(restored.isMainTabVisible(AppTabIds.sales), isTrue);
    });

    test('fromJson only disables meals on an explicit false', () {
      expect(AppSettings.fromJson({'mealsEnabled': false}).mealsEnabled,
          isFalse);
      expect(AppSettings.fromJson({'mealsEnabled': 0}).mealsEnabled, isTrue);
      expect(AppSettings.fromJson(const {}).mealsEnabled, isTrue);
    });
  });

  group('parseColorValue', () {
    test('accepts ints and nums', () {
      expect(parseColorValue(0xFFC8F135), 0xFFC8F135);
      expect(parseColorValue(3.6), 4);
    });

    test('parses hex strings with or without prefixes', () {
      expect(parseColorValue('#C8F135'), 0xFFC8F135);
      expect(parseColorValue('c8f135'), 0xFFC8F135);
      expect(parseColorValue('0xAABBCCDD'), 0xAABBCCDD);
      expect(parseColorValue('#AABBCCDD'), 0xAABBCCDD);
    });

    test('rejects invalid values', () {
      expect(parseColorValue(''), isNull);
      expect(parseColorValue(null), isNull);
      expect(parseColorValue('12345'), isNull);
      expect(parseColorValue('ZZZZZZ'), isNull);
    });
  });

  group('SessionRecord', () {
    test('toJson/fromJson round-trips HelloAsso metadata', () {
      final session = SessionRecord(
        id: 's-1',
        name: 'Journée test',
        eventDate: DateTime(2026, 7, 16),
        status: 'closed',
        notes: 'note',
        helloassoFormSlug: 'slug',
        helloassoFormType: 'Event',
        helloassoEventName: 'Event annuel',
        helloassoEventUrl: 'https://example.org',
        helloassoEventId: '42',
        helloassoSyncedAt: DateTime(2026, 7, 15, 9),
        closedAt: DateTime(2026, 7, 16, 22),
      );
      final restored = SessionRecord.fromJson(session.toJson());
      expect(restored.id, 's-1');
      expect(restored.name, 'Journée test');
      expect(restored.eventDate, DateTime(2026, 7, 16));
      expect(restored.status, 'closed');
      expect(restored.helloassoFormSlug, 'slug');
      expect(restored.helloassoEventId, '42');
      expect(restored.helloassoSyncedAt, DateTime(2026, 7, 15, 9));
      expect(restored.closedAt, DateTime(2026, 7, 16, 22));
    });

    test('fromJson reads snake_case keys and defaults', () {
      final restored = SessionRecord.fromJson({
        'id': 's-2',
        'session': 'Ancienne session',
        'event_date': '2026-01-02T00:00:00.000',
        'helloasso_form_slug': 'legacy-slug',
      });
      expect(restored.name, 'Ancienne session');
      expect(restored.eventDate, DateTime(2026, 1, 2));
      expect(restored.helloassoFormSlug, 'legacy-slug');
      expect(restored.status, 'open');
    });

    test('fromJson falls back to now for missing dates', () {
      final before = DateTime.now();
      final restored = SessionRecord.fromJson(const {});
      expect(restored.name, 'Événement');
      expect(
          restored.eventDate.isAfter(before.subtract(const Duration(minutes: 1))),
          isTrue);
    });
  });

  group('Player', () {
    test('isMember only matches the membre type', () {
      expect(testPlayer(type: 'membre').isMember, isTrue);
      expect(testPlayer(type: 'public').isMember, isFalse);
    });

    test('toJson/fromJson round-trips', () {
      final player = testPlayer(
          id: 'p-7',
          name: 'Léa Thomas',
          type: 'public',
          firstName: 'Léa',
          lastName: 'Thomas',
          email: 'LEA@EXEMPLE.FR');
      final restored = Player.fromJson(player.toJson());
      expect(restored.id, 'p-7');
      expect(restored.name, 'Léa Thomas');
      expect(restored.type, 'public');
      expect(restored.firstName, 'Léa');
      expect(restored.lastName, 'Thomas');
      expect(restored.email, 'lea@exemple.fr');
    });

    test('fromJson builds the name from parts and legacy keys', () {
      final restored = Player.fromJson({
        'first_name': 'Hugo',
        'last_name': 'Dubois',
        'name': 'Hugo Dubois',
      });
      expect(restored.name, 'Hugo Dubois');
      expect(restored.firstName, 'Hugo');
      expect(restored.lastName, 'Dubois');
      expect(restored.type, 'public');
      expect(restored.email, isEmpty);

      final fallback =
          Player.fromJson({'firstName': 'Hugo', 'lastName': 'Dubois'});
      expect(fallback.name, 'Hugo Dubois');
    });

    test('playerNameFromParts joins non-empty parts and trims fallback', () {
      expect(playerNameFromParts(' Alice ', ' Martin ', 'X'), 'Alice Martin');
      expect(playerNameFromParts('', 'Martin', 'X'), 'Martin');
      expect(playerNameFromParts('', '', ' Fallback '), 'Fallback');
    });

    test('splitPlayerName handles empty, simple and compound names', () {
      expect(splitPlayerName('   '), (firstName: '', lastName: ''));
      expect(splitPlayerName('Alice'),
          (firstName: 'Alice', lastName: ''));
      expect(splitPlayerName('Alice  De La  Tour'),
          (firstName: 'Alice', lastName: 'De La Tour'));
    });
  });

  group('SaleItem & Sale', () {
    test('SaleItem toJson/fromJson round-trips', () {
      final item = testSaleItem(articleId: 'a-1', name: 'Bière', quantity: 3);
      final restored = SaleItem.fromJson(item.toJson());
      expect(restored.articleId, 'a-1');
      expect(restored.name, 'Bière');
      expect(restored.quantity, 3);
      expect(restored.price, 2.5);
    });

    test('SaleItem fromJson uses legacy keys and defaults', () {
      final restored = SaleItem.fromJson({'nom': 'Thé', 'qte': 2, 'prix': 1});
      expect(restored.articleId, 'Thé');
      expect(restored.name, 'Thé');
      expect(restored.quantity, 2);
      expect(restored.price, 1);
      expect(restored.icon, '📦');
      expect(restored.type, 'standard');
    });

    test('Sale.total adds the donation and isActive follows status', () {
      final sale = testSale(totalArticles: 10, donation: 2.5);
      expect(sale.total, 12.5);
      expect(sale.isActive, isTrue);
      expect(sale.copyWith(status: 'cancelled').isActive, isFalse);
    });

    test('Sale.copyWith keeps untouched fields when null', () {
      final sale = testSale(donation: 1);
      final updated = sale.copyWith(
          playerName: 'Bob', status: 'cancelled', cancellationReason: 'test');
      expect(updated.id, sale.id);
      expect(updated.playerName, 'Bob');
      expect(updated.status, 'cancelled');
      expect(updated.cancellationReason, 'test');
      expect(updated.donation, 1);
      expect(updated.payment, sale.payment);
    });

    test('Sale toJson/fromJson round-trips', () {
      final sale = testSale(
        id: 's-9',
        donation: 3,
        payment: 'PayPal',
        status: 'cancelled',
        createdAt: DateTime(2026, 3, 4, 18, 30),
      );
      final restored = Sale.fromJson(sale.toJson());
      expect(restored.id, 's-9');
      expect(restored.donation, 3);
      expect(restored.payment, 'PayPal');
      expect(restored.status, 'cancelled');
      expect(restored.createdAt, DateTime(2026, 3, 4, 18, 30));
      expect(restored.items, hasLength(1));
    });

    test('Sale fromJson reads legacy keys with defaults', () {
      final restored = Sale.fromJson({
        'joueurNom': 'Zoe',
        'tarif': 'public',
        'paiement': 'SumUp',
        'don': 2,
      });
      expect(restored.playerName, 'Zoe');
      expect(restored.tariff, 'public');
      expect(restored.payment, 'SumUp');
      expect(restored.donation, 2);
      expect(restored.status, 'active');
    });
  });

  group('StockMovement & StockShortage', () {
    test('StockShortage message is human readable', () {
      final shortage = StockShortage(
        article: testArticle(name: 'Soda'),
        requiredQuantity: 3,
        availableQuantity: 1,
      );
      expect(shortage.message, 'Soda : 3 requis, 1 disponible(s)');
    });
  });

  group('MealOrder', () {
    test('consumes stock only when prepared or served', () {
      expect(testMeal(status: 'planned').consumesStock, isFalse);
      expect(testMeal(status: 'cancelled').consumesStock, isFalse);
      expect(testMeal(status: 'prepared').consumesStock, isTrue);
      expect(testMeal(status: 'served').consumesStock, isTrue);
    });

    test('isOnsite follows the source', () {
      expect(testMeal(source: 'onsite').isOnsite, isTrue);
      expect(testMeal(source: 'helloasso').isOnsite, isFalse);
    });

    test('stockItems counts each included article once', () {
      final meal = testMeal(
          mealArticleId: 'repas',
          drinkArticleId: 'boisson',
          snackArticleId: 'snack');
      expect(meal.stockItems, {'repas': 1, 'boisson': 1, 'snack': 1});
    });

    test('stockItems skips empty ids and accumulates duplicates', () {
      expect(testMeal(mealArticleId: 'repas').stockItems, {'repas': 1});
      expect(
          testMeal(mealArticleId: 'double', drinkArticleId: 'double')
              .stockItems,
          {'double': 2});
    });

    test('copyWith copies options defensively', () {
      final original = testMeal(options: ['Ketchup']);
      final copy = original.copyWith(status: 'prepared');
      copy.options.add('Mayonnaise');
      expect(original.options, ['Ketchup']);
      expect(original.status, 'planned');
      expect(copy.status, 'prepared');
    });
  });

  group('formatting helpers', () {
    test('money uses French decimals', () {
      expect(money(12.5), '12,50 €');
      expect(money(0), '0,00 €');
      expect(money(-3.5), '-3,50 €');
    });

    test('dateLabel and timeLabel zero-pad', () {
      expect(dateLabel(DateTime(2026, 7, 4)), '04/07/2026');
      expect(timeLabel(DateTime(2026, 7, 4, 9, 5)), '09:05');
    });

    test('denominations cover euros and cents', () {
      expect(denominations.first, 500);
      expect(denominations.last, 0.01);
      expect(denominations, containsAll(<double>[50, 20, 2, 1, 0.5]));
    });
  });

  group('HelloAssoSettings', () {
    test('isConfigured requires the three trimmed fields', () {
      expect(
          const HelloAssoSettings(
            organizationSlug: ' slug ',
            clientId: ' id ',
            clientSecret: ' secret ',
          ).isConfigured,
          isTrue);
      expect(
          const HelloAssoSettings(organizationSlug: 'slug').isConfigured,
          isFalse);
    });

    test('base urls follow the environment', () {
      const production = HelloAssoSettings(environment: 'production');
      const sandbox = HelloAssoSettings(environment: 'sandbox');
      expect(production.authBaseUrl, 'https://api.helloasso.com');
      expect(production.apiBaseUrl, 'https://api.helloasso.com/v5');
      expect(sandbox.isSandbox, isTrue);
      expect(sandbox.apiBaseUrl, 'https://api.helloasso-sandbox.com/v5');
    });

    test('secret helpers add and strip the secret', () {
      const settings = HelloAssoSettings(
        organizationSlug: 'slug',
        clientId: 'id',
        clientSecret: 'secret',
      );
      expect(settings.withoutSecret().clientSecret, isEmpty);
      expect(settings.withoutSecret().clientId, 'id');
      expect(settings.withSecret('other').clientSecret, 'other');
    });

    test('toJson excludes the secret on demand', () {
      const settings = HelloAssoSettings(clientSecret: 'secret');
      expect(settings.toJson()['clientSecret'], 'secret');
      expect(settings.toJson(includeSecret: false).containsKey('clientSecret'),
          isFalse);
    });

    test('fromJson normalizes the environment', () {
      expect(
          HelloAssoSettings.fromJson({'environment': 'sandbox'}).environment,
          'sandbox');
      expect(
          HelloAssoSettings.fromJson({'environment': 'autre'}).environment,
          'production');
      expect(HelloAssoSettings.fromJson(const {}).environment, 'production');
    });
  });

  group('FirebaseSettings', () {
    const configured = FirebaseSettings(
      apiKey: 'key',
      appId: 'app',
      messagingSenderId: '123',
      projectId: 'project',
    );

    test('isConfigured requires the four core identifiers', () {
      expect(configured.isConfigured, isTrue);
      expect(
          const FirebaseSettings(apiKey: 'key', appId: 'app').isConfigured,
          isFalse);
    });

    test('toOptions trims values and nulls empty optional fields', () {
      final options = const FirebaseSettings(
        apiKey: ' key ',
        appId: ' app ',
        messagingSenderId: ' 123 ',
        projectId: ' project ',
        authDomain: ' ',
        storageBucket: 'bucket',
      ).toOptions();
      expect(options.apiKey, 'key');
      expect(options.projectId, 'project');
      expect(options.authDomain, isNull);
      expect(options.storageBucket, 'bucket');
    });

    test('toJson/fromJson round-trips', () {
      final restored = FirebaseSettings.fromJson(configured.toJson());
      expect(restored.apiKey, 'key');
      expect(restored.appId, 'app');
      expect(restored.messagingSenderId, '123');
      expect(restored.projectId, 'project');
    });
  });

  group('parseFirebaseSettings', () {
    test('rejects empty input with a friendly message', () {
      expect(
          () => parseFirebaseSettings('  '),
          throwsA(isA<FormatException>().having(
              (error) => error.message, 'message', contains('Colle'))));
    });

    test('parses a plain JSON map', () {
      final settings = parseFirebaseSettings(
          '{"apiKey":"k","appId":"a","messagingSenderId":"s","projectId":"p"}');
      expect(settings.isConfigured, isTrue);
      expect(settings.apiKey, 'k');
    });

    test('parses an Android google-services JSON', () {
      final settings = parseFirebaseSettings('''
{
  "project_info": {
    "project_number": "123456",
    "project_id": "frag-addict",
    "storage_bucket": "frag-addict.appspot.com"
  },
  "client": [
    {
      "client_info": {"mobilesdk_app_id": "1:123:android:abc"},
      "api_key": [{"current_key": "android-key"}]
    }
  ]
}
''');
      expect(settings.isConfigured, isTrue);
      expect(settings.apiKey, 'android-key');
      expect(settings.appId, '1:123:android:abc');
      expect(settings.messagingSenderId, '123456');
      expect(settings.projectId, 'frag-addict');
    });

    test('parses an Apple plist and decodes entities', () {
      final settings = parseFirebaseSettings('''
<plist><dict>
<key>API_KEY</key><string>key&amp;value</string>
<key>GOOGLE_APP_ID</key><string>1:123:ios:abc</string>
<key>GCM_SENDER_ID</key><string>123</string>
<key>PROJECT_ID</key><string>projet</string>
<key>BUNDLE_ID</key><string>fr.frag.addict</string>
</dict></plist>
''');
      expect(settings.apiKey, 'key&value');
      expect(settings.iosBundleId, 'fr.frag.addict');
    });

    test('parses loose key/value text', () {
      final settings = parseFirebaseSettings(
          "apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p'");
      expect(settings.isConfigured, isTrue);
      expect(settings.projectId, 'p');
    });

    test('rejects unrecognized input', () {
      expect(
          () => parseFirebaseSettings('bonjour'),
          throwsA(isA<FormatException>().having((error) => error.message,
              'message', contains('non reconnue'))));
    });
  });

  group('HelloAsso models', () {
    test('event defaults', () {
      const event =
          HelloAssoEvent(name: 'Event', formSlug: 'slug', url: 'url');
      expect(event.formType, 'Event');
      expect(event.id, isEmpty);
    });

    test('registrant defaults', () {
      const registrant =
          HelloAssoRegistrant(firstName: 'A', lastName: 'B', email: 'a@b.fr');
      expect(registrant.hasMeal, isFalse);
      expect(registrant.mealLabel, isEmpty);
      expect(registrant.helloassoUserId, isEmpty);
    });
  });
}

Map<String, bool> _defaultVisibility() => {
      AppTabIds.meals: true,
      AppTabIds.players: true,
      AppTabIds.cash: true,
      AppTabIds.stats: true,
      AppTabIds.bilan: true,
      AppTabIds.articles: true,
    };
