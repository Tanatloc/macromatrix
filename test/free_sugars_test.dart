import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/free_sugars.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/dashboard_screen.dart';
import 'package:macromatrix/ui/screens/nutrients_screen.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  Food food(String ref) => foods.byRef(ref)!;
  double free(Food f) => freeSugarsPer100g(f.per100g, label: f.label, name: f.name)!;

  group('vrije suikers (P183)', () {
    test('een appel telt niet mee, cola volledig, sinaasappelsap ook', () {
      final apple = food('mvt:06.758'), cola = food('ciqual:18018'), juice = food('ciqual:2070');
      expect(apple.per100g['sugars'], greaterThan(5));
      expect(free(apple), 0);
      expect(free(cola), cola.per100g['sugars']);
      expect(free(juice), juice.per100g['sugars']);
    });

    test('gewone melk telt niet, aardbeienyoghurt alleen de toegevoegde suiker', () {
      expect(free(food('ciqual:19033')), 0);
      final yog = food('usda_sr:171300');
      expect(free(yog), greaterThan(0));
      expect(free(yog), lessThan(yog.per100g['sugars']!));
    });

    test('eigen producten zonder label: de naam beslist', () {
      double own(String name) => freeSugarsPer100g(const {'sugars': 10}, name: name)!;
      expect(own('Appel'), 0);
      expect(own('Banaan'), 0);
      expect(own('Griekse yoghurt'), 0);
      expect(own('Appelsap'), 10);
      expect(own('Honing'), 10);
      expect(own('Mijn granola'), 10);
      expect(own('Apple pie'), 10);
      expect(freeSugarsPer100g(const {'energy': 50}, name: 'Appel'), isNull);
    });

    test('maximum 10% van de energie; alle suikers samen hebben geen maximum', () {
      final t = targetsFor(const Profile(), year: 2026);
      expect(t['free_sugars']!.upper, closeTo(t['energy']!.goal! * 0.10 / 4, 0.01));
      expect(t['sugars']?.upper, isNull);
      expect(nutrientByKey['free_sugars']!.name, 'Vrije suikers');
      expect(nutrientNote('free_sugars'), isNotNull);
    });

    test('dagtotaal: appel 0, cola en sap wel', () {
      final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
      s.addFood(food('mvt:06.758'), meal: Meal.snacks, grams: 180, quantity: 180);
      expect(s.totals['free_sugars'], 0);
      expect(s.totals['sugars'], greaterThan(10));
      s.addFood(food('ciqual:18018'), meal: Meal.snacks, grams: 330, quantity: 330);
      s.addFood(food('ciqual:2070'), meal: Meal.breakfast, grams: 200, quantity: 200);
      final cola = food('ciqual:18018').per100g['sugars']! * 3.3, juice = food('ciqual:2070').per100g['sugars']! * 2;
      expect(s.totals['free_sugars'], closeTo(cola + juice, 0.01));
      expect(s.dailyTotals(s.date, s.date).values.single['free_sugars'], closeTo(cola + juice, 0.01));
    });
  });

  group('let op suiker (P41, P184)', () {
    Future<void> pump(WidgetTester tester, AppState s, Widget home) async {
      tester.view.physicalSize = const Size(390, 4000);
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

    testWidgets('Vandaag: koolhydraten en suikers bovenaan als het aanstaat', (tester) async {
      final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
      s.addFood(food('ciqual:18018'), meal: Meal.snacks, grams: 330, quantity: 330);
      expect(s.sugarFocus, isFalse);
      s.setSugarFocus(true);
      expect(s.sugarFocus, isTrue);
      await pump(
        tester,
        s,
        Scaffold(body: SingleChildScrollView(child: KeyNutrients(values: s.totals.values, targets: s.targets))),
      );
      expect(find.text('Vrije suikers'), findsOneWidget);
      expect(find.textContaining('je let op suiker'), findsOneWidget);
      // Volgorde: koolhydraten en suikers vóór eiwit
      final y = {for (final n in ['Koolhydraten', 'Suikers', 'Vrije suikers', 'Eiwit']) n: tester.getTopLeft(find.text(n)).dy};
      expect(y['Koolhydraten']!, lessThan(y['Suikers']!));
      expect(y['Vrije suikers']!, lessThan(y['Eiwit']!));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Week: suiker per dag, met de bloedsuiker van die dag', (tester) async {
      final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
      s.setSugarFocus(true);
      s.addFood(food('mvt:06.758'), meal: Meal.snacks, grams: 180, quantity: 180);
      s.addFood(food('ciqual:18018'), meal: Meal.snacks, grams: 330, quantity: 330);
      s.addBiometric('glucose', 6.2);
      await pump(tester, s, const DashboardScreen());
      await tester.tap(find.text('Week'));
      await tester.pump();
      expect(find.text('Suiker per dag'), findsOneWidget);
      expect(find.textContaining('bloedsuiker 6,2 mmol/L'), findsOneWidget);
      final free = fmtTest(s.totals['free_sugars']), all = fmtTest(s.totals['sugars']);
      expect(find.text('$free / $all'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

String fmtTest(double v) => v.round().toString();
