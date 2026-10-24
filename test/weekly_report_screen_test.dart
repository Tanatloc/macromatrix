import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/weekly_report_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Weekrapport met echte gegevens: stabiel gewicht bij een groot "tekort" en "Let op suiker" aan (N07, N08, N09, N13).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  final now = logicalNow();
  final monday = DateTime(mondayOf(now).year, mondayOf(now).month, mondayOf(now).day - 7);

  AppState stateWithWeek() {
    final user = UserDb(sqlite3.openInMemory());
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: user);
    final bread = foods.search('bread', limit: 1).first;
    // Ongeveer 65% van het energiedoel, elke dag van vorige week
    final grams = s.targets['energy']!.goal! * 0.65 / (bread.per100g['energy']! / 100);
    for (var i = 0; i < 7; i++) {
      s.setDate(DateTime(monday.year, monday.month, monday.day + i));
      s.addFood(bread, meal: Meal.lunch, grams: grams, quantity: 1);
    }
    // Twee weken lang stabiel gewicht, en wat bloedsuikermetingen
    for (var i = -7; i < 7; i++) {
      final day = dayKey(DateTime(monday.year, monday.month, monday.day + i));
      user.addBiometric(day: day, type: 'weight', value: 80 + (i.isEven ? 0.1 : -0.1));
      if (i >= 0 && i < 3) user.addBiometric(day: day, type: 'glucose', value: 7);
    }
    s.setSugarFocus(true);
    return s;
  }

  test('stabiel gewicht: geen "eet meer", wel je doel in vraag', () {
    final r = stateWithWeek().weeklyReport(monday)!;
    expect(r.weightTrend!.stable, isTrue);
    expect(r.energyCase, EnergyCase.goalOff);
    expect(WeeklyReportScreen.energyTip(r), contains('stabiel'));
    expect(r.health!.factors.firstWhere((f) => f.key == 'energy').effect, contains('stabiel'));
    expect(r.sugar!.glucoseCount, 3);
    expect(r.goals['magnesium'], greaterThan(0));
  });

  testWidgets('scherm past op een smalle telefoon, suiker bovenaan, Nederlandse scorenaam', (tester) async {
    final s = stateWithWeek();
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider(create: (_) => Friends(s, account)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: WeeklyReportScreen(monday: monday),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Koolhydraten en suiker'), findsOneWidget);
    expect(find.text('Voedingsscore'), findsOneWidget);
    expect(find.textContaining('Nutrient score'), findsNothing);
    expect(find.text('Je energiedoel aanpassen'), findsOneWidget);
    expect(find.textContaining('Slecht'), findsNothing);
    // Koolhydraten staan boven de score
    expect(tester.getTopLeft(find.text('Koolhydraten en suiker')).dy, lessThan(tester.getTopLeft(find.text('Voedingsscore')).dy));
    expect(tester.takeException(), isNull);
  });
}
