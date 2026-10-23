import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/dashboard_screen.dart';
import 'package:macromatrix/ui/screens/nutrient_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  AppState newState() => AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  Future<void> pump(WidgetTester tester, AppState s, Widget home, {double height = 900}) async {
    tester.view.physicalSize = Size(412, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ),
    );
    await tester.pump();
  }

  testWidgets('een andere dag staat met naam in de kop; macro-doelen komen uit je plan', (tester) async {
    final s = newState();
    s.shiftDay(-3);
    s.addFood(s.foods.search('oats', limit: 1).first, meal: Meal.breakfast, grams: 60, quantity: 60);
    await pump(tester, s, NutrientDetailScreen(nutrient: nutrientByKey['protein']!));
    expect(find.text('VANDAAG'), findsNothing);
    expect(find.textContaining(RegExp(r'^(MAANDAG|DINSDAG|WOENSDAG|DONDERDAG|VRIJDAG|ZATERDAG|ZONDAG) ')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Uit je plan'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Uit je plan'), findsOneWidget);
    expect(find.text('EFSA-advies'), findsNothing);
  });

  testWidgets('micro\'s houden het EFSA-advies, en de kop blijft staan bij scrollen', (tester) async {
    final s = newState();
    await pump(tester, s, NutrientDetailScreen(nutrient: nutrientByKey['vit_c']!));
    expect(find.text('VANDAAG'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('EFSA-advies'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('EFSA-advies'), findsOneWidget);
    expect(find.byTooltip('Terug').hitTestable(), findsOneWidget);
  });

  testWidgets('vanuit een week: daggemiddelde van die periode, met de datums erbij', (tester) async {
    final s = newState();
    final oats = s.foods.search('oats', limit: 1).first;
    s.shiftDay(-1);
    s.addFood(oats, meal: Meal.breakfast, grams: 100, quantity: 100);
    s.shiftDay(-1);
    s.addFood(oats, meal: Meal.breakfast, grams: 50, quantity: 50);
    s.goToToday();
    final to = DateTime(s.date.year, s.date.month, s.date.day - 1);
    final from = DateTime(to.year, to.month, to.day - 6);
    await pump(tester, s, NutrientDetailScreen(nutrient: nutrientByKey['protein']!, from: from, to: to), height: 2400);
    expect(find.textContaining('GEMIDDELD PER DAG ·'), findsOneWidget);
    expect(find.text('2 van 7 dagen gelogd'), findsOneWidget);
    expect(find.text('Waar kwam het vandaan in deze periode'), findsOneWidget);
    expect(find.text('2× gelogd'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard springt terug naar de dagweergave als het dagboek erom vraagt', (tester) async {
    final s = newState();
    final showDay = ValueNotifier(0);
    addTearDown(showDay.dispose);
    await pump(tester, s, DashboardScreen(showDay: showDay));
    await tester.tap(find.text('Week'));
    await tester.pump();
    expect(find.text('DEZE WEEK'), findsOneWidget);
    showDay.value++;
    await tester.pump();
    expect(find.text('DEZE WEEK'), findsNothing);
    expect(find.text('VANDAAG'), findsOneWidget);
  });
}
