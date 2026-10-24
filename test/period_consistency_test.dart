import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/friends.dart' show mondayOf;
import 'package:macromatrix/ui/screens/dashboard_screen.dart';
import 'package:macromatrix/ui/screens/recap_screen.dart';
import 'package:macromatrix/ui/screens/trends_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/day_charts.dart';

/// Dashboard Week/Maand: één basis voor tellers en gemiddelden, één score, één kleurregel voor energie, geen
/// schatting in een lege maand, suikerbalken met de grens op de juiste balk (N13, N18, N64, N69, N73, N74).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  final now = logicalNow();
  final monday = DateTime(mondayOf(now).year, mondayOf(now).month, mondayOf(now).day - 7);
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);

  /// Vorige week: vijf volledige dagen op het energiedoel, één dag met te weinig gelogd, zondag niets.
  AppState stateWithWeek() {
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    final bread = foods.search('bread', limit: 1).first;
    final grams = s.targets['energy']!.goal! / (bread.per100g['energy']! / 100);
    for (var i = 0; i < 5; i++) {
      s.setDate(DateTime(monday.year, monday.month, monday.day + i));
      s.addFood(bread, meal: Meal.lunch, grams: grams, quantity: 1);
    }
    s.setDate(DateTime(monday.year, monday.month, monday.day + 5));
    s.addFood(bread, meal: Meal.lunch, grams: 50, quantity: 1);
    return s;
  }

  Future<void> pump(WidgetTester tester, AppState s, Widget home) async {
    tester.view.physicalSize = const Size(390, 5000);
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

  Widget trends(DateTime from, DateTime to) => Scaffold(
    body: SingleChildScrollView(
      child: PeriodTrends(from: from, to: to),
    ),
  );

  test('energie: dezelfde marge van ±10% op elk scherm (107% is binnen de marge)', () {
    const p = Palette.light;
    expect(withinEnergyMargin(2269, 2120), isTrue);
    expect(energyColor(p, 2269, 2120), p.okFill);
    expect(withinEnergyMargin(2400, 2120), isFalse);
    expect(energyColor(p, 2400, 2120), p.highFill);
  });

  test('geschat verbruik zegt hoe betrouwbaar het is', () {
    final days = [for (var i = 0; i < 28; i++) dayKey(DateTime(2026, 9, 1 + i))];
    final rough = estimateEnergy(
      {for (final d in days.take(12)) d: 2000},
      {for (final d in days.where((d) => days.indexOf(d) % 4 == 0)) d: 80},
      days,
    )!;
    expect(rough.loggedDays, 12);
    expect(rough.weighIns, 7);
    expect(rough.reliable, isFalse);
    final solid = estimateEnergy({for (final d in days) d: 2000}, {for (final d in days.where((d) => days.indexOf(d) % 3 == 0)) d: 80}, days)!;
    expect(solid.reliable, isTrue);
  });

  testWidgets('Week: één basis bovenaan, de score van het weekrapport, tellers over volledige dagen', (tester) async {
    final s = stateWithWeek();
    final report = s.weeklyReport(monday)!;
    expect(report.days, 5);
    await pump(tester, s, trends(monday, sunday));
    expect(find.text('Op basis van 5 volledig gelogde dagen · 1 dag met te weinig gelogd'), findsOneWidget);
    expect(find.text('Voedingsscore'), findsOneWidget);
    expect(find.textContaining('Nutrient score'), findsNothing);
    expect(find.text('${report.score}'), findsWidgets);
    // Volledige dagen en "binnen ±10%" over dezelfde vijf dagen
    expect(find.text('Volledige dagen'), findsOneWidget);
    expect(find.text('5 / 5'), findsWidgets);
    expect(find.text('over 5 volledige dagen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Suiker per dag: (i) opent bij een gewone tik een onderblad', (tester) async {
    final s = stateWithWeek();
    await pump(tester, s, trends(monday, sunday));
    await tester.tap(find.byTooltip('Over suiker per dag'));
    await tester.pumpAndSettle();
    expect(find.textContaining('dikke balk'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('lege maand: geen geschat verbruik, geen knop Maandoverzicht, nette lege kaart', (tester) async {
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    final old = DateTime(now.year, now.month - 4, 1);
    await pump(tester, s, trends(old, DateTime(old.year, old.month + 1, 0)));
    expect(find.text('Geschat verbruik'), findsNothing);

    await pump(tester, s, const DashboardScreen());
    await tester.tap(find.text('Maand'));
    await tester.pump();
    expect(find.text('Maandoverzicht'), findsNothing);
    expect(find.text('Jaar ${now.year}'), findsOneWidget);

    await pump(tester, s, RecapScreen(from: old, year: false));
    expect(find.text('Niets gelogd deze maand'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('weekrapport: een stof met één uitschieter staat niet bij je sterkste', () {
    final s = stateWithWeek();
    final seeds = foods.search('pumpkin seeds', limit: 5).firstWhere((f) => (f.per100g['magnesium'] ?? 0) > 300);
    // Eén dag veel pompoenpitten: hoog gemiddelde aan magnesium, maar maar één dag op doel
    s.setDate(monday);
    s.addFood(seeds, meal: Meal.snacks, grams: 400, quantity: 1);
    final r = s.weeklyReport(monday)!;
    expect(r.avg['magnesium'], greaterThan(1));
    expect(r.best.map((b) => b.$1.key), isNot(contains('magnesium')));
  });
}
