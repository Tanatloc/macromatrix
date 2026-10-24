// N88: "Null check operator used on a null value" in _RenderObjectSemantics on the web, at almost every step once
// it started. Removing the last item of the day from the product screen changed the diary list in the same frame
// as the diary route came back on screen; Flutter's semantics pass then left a diary list item without geometry.
// Widget tests run with semantics on, so these flows catch it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  late List<Object> errors;
  late void Function(FlutterErrorDetails)? previous;

  /// A brand-new user (empty diary) logs one banana and opens it from Today.
  Future<AppState> openFirstEntry(WidgetTester tester) async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    errors = [];
    previous = FlutterError.onError;
    FlutterError.onError = (d) {
      // The test font is wider than the real one; overflow stripes are not what this test is about
      if (d.exception.toString().contains('overflowed')) return;
      errors.add(d.exception);
    };
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const DiaryScreen()),
      ),
    );
    await tester.pumpAndSettle();
    s.addFood(s.foods.search('banana', limit: 1).first, meal: Meal.dinner, grams: 120, quantity: 120);
    await tester.pumpAndSettle();
    await tester.tap(find.text(s.entries.single.name));
    await tester.pumpAndSettle();
    return s;
  }

  // Not pumpAndSettle: with a broken semantics tree every frame throws and schedules the next one
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void expectNoErrors() {
    FlutterError.onError = previous;
    expect(errors, isEmpty);
  }

  testWidgets('removing the only entry from the product screen keeps the semantics tree whole', (tester) async {
    final s = await openFirstEntry(tester);
    await tester.tap(find.byTooltip('Remove from diary'));
    await settle(tester);
    expect(s.entries, isEmpty);
    expect(find.text('Banana, raw removed'), findsOneWidget);
    // Later steps (other tabs, scrolling) used to throw again on every frame
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await settle(tester);
    expectNoErrors();
    // A tap in the first half second does not count (double-tap guard)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.entries, hasLength(1));
  });

  testWidgets('saving a changed amount and closing in one go', (tester) async {
    final s = await openFirstEntry(tester);
    final e = s.entries.single;
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    s.updateEntry(e, meal: Meal.breakfast, grams: 240, quantity: 240);
    await settle(tester);
    expectNoErrors();
  });

  testWidgets('adding the first food while a screen closes', (tester) async {
    final s = await openFirstEntry(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.pop();
    await settle(tester);
    s.deleteEntry(s.entries.single);
    await settle(tester);
    nav.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('product'))));
    await settle(tester);
    nav.pop();
    s.addFood(s.foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 120, quantity: 120);
    await settle(tester);
    expectNoErrors();
  });
}
