import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/dashboard_screen.dart';
import 'package:macromatrix/ui/screens/nutrient_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/day_charts.dart';

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

  testWidgets('30 dagen: gemiddelde boven de grafiek, en een aangetikte staaf toont zijn dag en waarde', (tester) async {
    final s = newState();
    final oats = s.foods.search('oats', limit: 1).first;
    s.shiftDay(-1);
    s.addFood(oats, meal: Meal.breakfast, grams: 100, quantity: 100);
    s.shiftDay(-1);
    s.addFood(oats, meal: Meal.breakfast, grams: 50, quantity: 50);
    s.goToToday();
    final n = nutrientByKey['protein']!;
    final today = DateTime(s.date.year, s.date.month, s.date.day);
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final daily = s.dailyTotals(DateTime(today.year, today.month, today.day - 2), yesterday);
    final vals = [for (final t in daily.values) t[n.key]];
    final mean = vals.reduce((a, b) => a + b) / vals.length;
    final dayValue = daily[dayKey(yesterday)]![n.key];

    await pump(tester, s, NutrientDetailScreen(nutrient: n), height: 2400);
    expect(find.text('Laatste 30 dagen'), findsOneWidget);
    expect(find.text('Gemiddeld ${formatAmount(mean, n)} ${n.unit}'), findsOneWidget);

    // Gisteren is de voorlaatste staaf; rechts staat een kolom met waarden. Met pas twee dagen gegevens begint de as
    // een week terug in plaats van 30 dagen (N95)
    final chart = tester.getRect(find.byType(DayBarsChart));
    final bars = tester.widget<DayBarsChart>(find.byType(DayBarsChart)).values.length;
    expect(bars, 7);
    final step = (chart.width - DayBarsChart.axisGutter) / bars;
    await tester.tapAt(Offset(chart.left + step * (bars - 1.5), chart.bottom - 4));
    await tester.pump();
    expect(find.text(DateFormat('E d MMM', appLocale).format(yesterday)), findsOneWidget);
    expect(find.text('${formatAmount(dayValue, n)} ${n.unit}'), findsWidgets);
    expect(find.textContaining('Gemiddeld '), findsNothing);
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

  testWidgets('meeste suikers: geen groene + of "eet je vaker" bij cola, ook zonder maximum (N26)', (tester) async {
    final s = newState();
    s.addFood(s.foods.byRef('ciqual:18018')!, meal: Meal.snacks, grams: 330, quantity: 330);
    await pump(tester, s, NutrientDetailScreen(nutrient: nutrientByKey['sugars']!), height: 3000);
    expect(find.text('Meeste suikers'), findsOneWidget);
    expect(find.text('Rijkste bronnen'), findsNothing);
    expect(find.text('eet je vaker'), findsNothing);
    expect(find.text('in je dagboek'), findsOneWidget);
    expect(find.byTooltip('Toevoegen'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vrije suikers: het doel is WHO-advies, met 5% (VK) als keuze (N21)', (tester) async {
    final s = newState();
    final who = s.defaultTargets['free_sugars']!.upper!;
    await pump(tester, s, NutrientDetailScreen(nutrient: nutrientByKey['free_sugars']!), height: 3000);
    expect(find.text('WHO-advies'), findsOneWidget);
    expect(find.text('EFSA-advies'), findsNothing);
    await tester.tap(find.text('5% gebruiken (VK)'));
    await tester.pump();
    expect(s.targets['free_sugars']!.upper, closeTo(who / 2, 0.001));
    expect(find.text('5% gebruiken (VK)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
