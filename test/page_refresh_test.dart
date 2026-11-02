import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tilly/src/ui/widgets/page_refresh.dart';

import 'support/test_doubles.dart';

void main() {
  testWidgets('active page rebuilds when the controller notifies',
      (tester) async {
    final controller = TestAppController();
    addTearDown(controller.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ActivePageScope(
          active: true,
          child: PageRefresh(
            controller: controller,
            builder: (context) {
              builds++;
              return Text('articles=${controller.articles.length}',
                  textDirection: TextDirection.ltr);
            },
          ),
        ),
      ),
    );

    expect(builds, 1);

    controller.articles = [testArticle()];
    controller.notifyListeners();
    await tester.pump();

    expect(builds, 2);
    expect(find.text('articles=1'), findsOneWidget);
  });

  testWidgets('hidden page skips rebuilds and refreshes when reactivated',
      (tester) async {
    final controller = TestAppController();
    addTearDown(controller.dispose);
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<bool>(
          valueListenable: active,
          builder: (context, isActive, _) => ActivePageScope(
            active: isActive,
            child: PageRefresh(
              controller: controller,
              builder: (context) {
                builds++;
                return Text('articles=${controller.articles.length}',
                    textDirection: TextDirection.ltr);
              },
            ),
          ),
        ),
      ),
    );

    expect(builds, 1);
    expect(find.text('articles=0'), findsOneWidget);

    active.value = false;
    await tester.pump();

    controller.articles = [testArticle()];
    controller.notifyListeners();
    await tester.pump();

    expect(builds, 2, reason: 'the hidden page is not rebuilt');
    expect(find.text('articles=0'), findsOneWidget,
        reason: 'the hidden page keeps its previous output');

    active.value = true;
    await tester.pump();

    expect(builds, 3, reason: 'the page refreshes once when it becomes active');
    expect(find.text('articles=1'), findsOneWidget);
  });

  testWidgets('pages without an ActivePageScope keep live updates',
      (tester) async {
    final controller = TestAppController();
    addTearDown(controller.dispose);
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: PageRefresh(
          controller: controller,
          builder: (context) {
            builds++;
            return Text('articles=${controller.articles.length}',
                textDirection: TextDirection.ltr);
          },
        ),
      ),
    );

    controller.articles = [testArticle()];
    controller.notifyListeners();
    await tester.pump();

    expect(builds, 2);
    expect(find.text('articles=1'), findsOneWidget);
  });
}
