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
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  Future<AppState> pump(WidgetTester tester) async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    );
    final oats = s.foods.search('oats', limit: 1).first;
    final banana = s.foods.search('banana', limit: 1).first;
    s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    s.addFood(banana, meal: Meal.breakfast, grams: 120, quantity: 120);
    tester.view.physicalSize = const Size(412, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const DiaryScreen()),
      ),
    );
    await tester.pump();
    return s;
  }

  testWidgets('entries are visible right away, swipe right opens actions', (tester) async {
    final s = await pump(tester);
    expect(find.text(s.entries.first.name), findsOneWidget);
    await tester.drag(find.text(s.entries.first.name), const Offset(320, 0));
    await tester.pumpAndSettle();
    expect(find.text('Naar andere maaltijd'), findsOneWidget);
    await tester.tap(find.text('Naar andere maaltijd'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Avondeten').last);
    await tester.pumpAndSettle();
    expect(s.entriesFor(Meal.dinner), hasLength(1));
  });

  testWidgets('long press selects, the bar acts on all selected', (tester) async {
    final s = await pump(tester);
    await tester.longPress(find.text(s.entries[0].name));
    await tester.pump();
    await tester.tap(find.text(s.entries[1].name));
    await tester.pump();
    expect(find.textContaining('2 geselecteerd'), findsOneWidget);
    await tester.tap(find.text('Verwijderen'));
    await tester.pumpAndSettle();
    expect(s.entries, isEmpty);
    expect(find.textContaining('geselecteerd'), findsNothing);
  });

  testWidgets('summary pages and macros to go', (tester) async {
    final s = await pump(tester);
    expect(find.text('DOELEN'), findsOneWidget);
    await tester.tap(find.text('GEGETEN'));
    await tester.pump();
    expect(s.macrosRemaining, isTrue);
    expect(find.textContaining('nog '), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Uitgelicht'));
    await tester.pumpAndSettle();
    expect(find.text('Kiezen'), findsOneWidget);
    await tester.tap(find.byTooltip('Volgende'));
    await tester.pumpAndSettle();
    expect(find.text('Voedingsscore'), findsOneWidget);
    await tester.tap(find.byTooltip('Volgende'));
    await tester.pumpAndSettle();
    expect(find.text('DOELEN'), findsOneWidget);
  });
}
