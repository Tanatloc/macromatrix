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
import 'package:macromatrix/sync/friends.dart' show mondayOf;
import 'package:macromatrix/ui/screens/body_screen.dart';
import 'package:macromatrix/ui/screens/nutrient_detail_screen.dart';
import 'package:macromatrix/ui/screens/trends_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/charts.dart';
import 'package:macromatrix/ui/widgets/day_charts.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

/// Gebruikerstest ronde 8 en 9: trendlijn en gewicht bovenaan (N44), soort en tweede gewicht bij een nieuwe meting
/// (N78), streefzone bij bloedsuiker (N79), grote periodeknoppen (N94) en een 90-dagengrafiek vanaf je eerste dag (N95).
void main() {
  late AppState s;
  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  setUpAll(() async {
    await initializeDateFormatting('nl');
    await initializeDateFormatting('en');
  });
  setUp(() {
    setAppLang(AppLang.en);
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });
  tearDown(() => setAppLang(AppLang.nl));

  Future<void> pump(WidgetTester tester, Widget home, {double height = 1400}) async {
    tester.view.physicalSize = Size(412, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ),
    );
    await tester.pump();
  }

  String daysAgo(int n) {
    final now = logicalNow();
    return dayKey(DateTime(now.year, now.month, now.day - n));
  }

  testWidgets('N78: tweede gewicht op dezelfde dag: vervangen of erbij, met het uur', (tester) async {
    s.addBiometric('weight', 80);
    expect(s.biometrics.single.time, matches(RegExp(r'^\d\d:\d\d$')));
    await pump(tester, const BodyScreen());

    await tester.tap(find.text('Measurement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '80.6');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Replace or add?'), findsOneWidget);
    expect(find.textContaining('You already weighed 80.0 kg on this day at '), findsOneWidget);
    await tester.tap(find.text('Replace'));
    await tester.pumpAndSettle();
    expect(s.biometrics.single.value, 80.6);

    await tester.tap(find.text('Measurement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '81');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep both'));
    await tester.pumpAndSettle();
    expect([for (final b in s.biometrics) b.value], [80.6, 81]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N44/N94: Lichaam toont 30 dagen met trendlijn, ingezoomd op je metingen, en grote periodeknoppen', (tester) async {
    for (final (i, w) in [(9, 81.0), (6, 80.4), (3, 80.8), (1, 80.1)]) {
      s.user.addBiometric(day: daysAgo(i), type: 'weight', value: w);
    }
    await pump(tester, const BodyScreen());
    expect(tester.widget<Segmented<int>>(find.byType(Segmented<int>)).selected, 30);
    expect(tester.getSize(find.byType(Segmented<int>)).height, greaterThanOrEqualTo(44));

    final chart = tester.widget<TimeSeriesChart>(find.byType(TimeSeriesChart));
    expect(chart.trend, isNotNull);
    expect(chart.trend!.length, 9); // van de eerste tot de laatste weging
    expect(chart.band, isNull);
    // De as begint een dag voor de eerste weging, niet 30 dagen terug
    expect(dayKey(chart.from), daysAgo(10));
    expect(find.text('trend weight'), findsOneWidget);
    expect(find.textContaining('Measurements since '), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N78/N79: bloedsuiker: streefzone in je eenheid, en + Meting staat op bloedsuiker', (tester) async {
    s.user.addBiometric(day: daysAgo(2), type: 'glucose', value: 8.4);
    s.user.addBiometric(day: daysAgo(1), type: 'glucose', value: 9.1);
    await pump(tester, const BodyScreen());
    await tester.tap(find.widgetWithText(PillChip, 'Blood glucose'));
    await tester.pumpAndSettle();
    var chart = tester.widget<TimeSeriesChart>(find.byType(TimeSeriesChart));
    expect(chart.band, (4.0, 7.0));
    expect(chart.trend, isNull);
    expect(find.text('target 4–7 mmol/L before meals'), findsOneWidget);
    // Een week breed, niet drie punten tegen de rechterrand
    expect(dayKey(chart.from), daysAgo(7));

    s.user.setSetting('glucose', {'unit': 'mg/dL'});
    s.goToToday();
    await tester.pumpAndSettle();
    chart = tester.widget<TimeSeriesChart>(find.byType(TimeSeriesChart));
    expect(chart.band, (72.0, 126.0));

    await tester.tap(find.text('Measurement'));
    await tester.pumpAndSettle();
    expect(find.text('Blood glucose (mg/dL)'), findsOneWidget);
    expect(find.text('Weight (kg)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N95/N94: 90 dagen begint bij je eerste gelogde dag; legende met gestippeld doel en vandaag', (tester) async {
    final oats = s.foods.search('oats', limit: 1).first;
    s.shiftDay(-3);
    s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    s.goToToday();
    s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
    await pump(tester, NutrientDetailScreen(nutrient: nutrientByKey['protein']!), height: 2600);
    expect(tester.getSize(find.byType(Segmented<int>)).height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('90d'));
    await tester.pumpAndSettle();
    expect(find.text('Last 90 days'), findsOneWidget);
    expect(find.textContaining('Data since '), findsOneWidget);
    expect(find.textContaining('average since '), findsOneWidget);
    expect(find.text('90-day average'), findsNothing);
    expect(find.text('today'), findsWidgets);
    // Een week breed: de eerste dag ligt 3 dagen terug, dus de as begint 6 dagen terug
    final bars = tester.widget<DayBarsChart>(find.byType(DayBarsChart));
    expect(bars.values.length, 7);
    expect(tester.takeException(), isNull);
  });

  testWidgets('N44: op Week staat gewicht meteen na energie, voor de macroverdeling', (tester) async {
    final oats = s.foods.search('oats', limit: 1).first;
    s.addFood(oats, meal: Meal.breakfast, grams: 80, quantity: 80);
    s.addBiometric('weight', 80);
    final now = logicalNow();
    final monday = mondayOf(now);
    await pump(
      tester,
      Scaffold(
        body: SingleChildScrollView(
          child: PeriodTrends(from: monday, to: DateTime(monday.year, monday.month, monday.day + 6)),
        ),
      ),
      height: 6000,
    );
    final weight = tester.getTopLeft(find.text('Weight').first).dy;
    final macros = tester.getTopLeft(find.text('Macro split')).dy;
    expect(weight, lessThan(macros));
    expect(tester.takeException(), isNull);
  });
}
