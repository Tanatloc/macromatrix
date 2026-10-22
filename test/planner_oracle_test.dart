import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/oracle_screen.dart';
import 'package:macromatrix/ui/screens/planner_screen.dart';
import 'package:macromatrix/ui/screens/shopping_screen.dart';
import 'package:macromatrix/ui/theme.dart';

AppState newState() => AppState(
  foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
  user: UserDb(sqlite3.openInMemory()),
);

ItemTemplate item(AppState s, String query, double grams) {
  final f = s.foods.search(query, limit: 1).first;
  return ItemTemplate(foodRef: f.ref, name: f.name, grams: grams, quantity: grams, per100g: f.per100g);
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  test('plan: totals, put in diary, then empty', () {
    final s = newState();
    final today = dayKey(logicalNow());
    s.addToPlan(today, Meal.breakfast, item(s, 'oats', 60));
    s.addToPlan(today, Meal.lunch, item(s, 'banana', 120));
    expect(s.planFor(today), hasLength(2));
    expect(s.plannedDays, [today]);
    expect(s.planTotals(today).values['energy'], greaterThan(300));
    s.removeFromPlan(today, 1);
    expect(s.planFor(today).single.meal, Meal.breakfast);
    expect(s.logPlan(today), 1);
    expect(s.planFor(today), isEmpty);
    expect(s.entries.single.meal, Meal.breakfast);
  });

  test('shopping: plan items are added up, typed items merge by name', () {
    final s = newState();
    final d1 = dayKey(logicalNow().add(const Duration(days: 1)));
    final d2 = dayKey(logicalNow().add(const Duration(days: 2)));
    s.addToPlan(d1, Meal.breakfast, item(s, 'oats', 60));
    s.addToPlan(d2, Meal.breakfast, item(s, 'oats', 40));
    expect(s.shoppingFromPlans(s.plannedDays), 1);
    expect(s.shopping.single.grams, 100);
    s.addShopping('Melk');
    s.addShopping('melk');
    expect(s.shopping, hasLength(2));
  });

  test('oracle: ranked, one per food, group filter respected', () {
    final s = newState();
    final all = s.oracle('potassium', limit: 25);
    expect(all, hasLength(25));
    for (var i = 1; i < all.length; i++) {
      expect(all[i - 1].$2, greaterThanOrEqualTo(all[i].$2));
    }
    final veg = s.oracle('vit_c', groups: {'fruit'}, limit: 10, everyday: true);
    expect(veg, isNotEmpty);
    expect(veg.every((r) => r.$1.label?.group == 'fruit'), isTrue);
    final portion = s.oracle('protein', rank: OracleRank.perPortion, limit: 10);
    expect(portion, hasLength(10));
  });

  for (final size in const [Size(1440, 1000), Size(412, 900)]) {
    testWidgets('screens build at ${size.width.round()} px', (tester) async {
      final s = newState();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      s.addToPlan(dayKey(logicalNow().add(const Duration(days: 1))), Meal.lunch, item(s, 'banana', 120));
      for (final screen in const [PlannerScreen(), ShoppingScreen(), OracleScreen()]) {
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: s,
            child: MaterialApp(theme: buildTheme(Brightness.light), home: screen),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: screen.runtimeType.toString());
      }
      expect(find.text('Vraag het Orakel'), findsOneWidget);
    });
  }
}
