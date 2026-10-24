import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/allergens.dart';
import 'package:macromatrix/nutrition/preferences.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/state/week_menu_state.dart';
import 'package:macromatrix/ui/screens/week_menu_screen.dart';
import 'package:macromatrix/ui/theme.dart';

final _foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
AppState newState() => AppState(foods: _foods, user: UserDb(sqlite3.openInMemory()));

DateTime get tomorrow {
  final n = logicalNow();
  return DateTime(n.year, n.month, n.day + 1);
}

ItemTemplate item(AppState s, String query, double grams) {
  final f = s.foods.search(query, limit: 1).first;
  return ItemTemplate(foodRef: f.ref, name: f.name, grams: grams, quantity: grams, per100g: f.per100g);
}

/// Energie binnen ±10%, eiwit in de buurt van het doel, geen dag vol dubbels.
void expectGoodDays(WeekMenu m) {
  for (final d in m.days) {
    final e = d.share('energy')!, p = d.share('protein')!;
    expect(e, inInclusiveRange(0.9, 1.1), reason: '${d.date}: energie ${(e * 100).round()}%');
    expect(p, inInclusiveRange(0.85, 1.6), reason: '${d.date}: eiwit ${(p * 100).round()}%');
    final counts = <String, int>{};
    for (final i in d.items) {
      counts[i.food.key] = (counts[i.food.key] ?? 0) + 1;
    }
    expect(counts.values.every((c) => c <= 2), isTrue, reason: 'hoogstens twee keer hetzelfde per dag: $counts');
    expect(counts.length, greaterThanOrEqualTo(d.items.length * 0.75), reason: 'vooral verschillende producten');
    for (final meal in Meal.values) {
      final inMeal = [
        for (final i in d.items)
          if (i.meal == meal) i.food.key,
      ];
      expect(inMeal.toSet().length, inMeal.length, reason: 'niets twee keer in dezelfde maaltijd');
    }
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  test('zonder geschiedenis: eenvoudige maaltijden die energie en eiwit halen, snel', () {
    final s = newState();
    final sw = Stopwatch()..start();
    final planner = s.weekMenuPlanner();
    final built = sw.elapsedMilliseconds;
    sw.reset();
    final m = s.proposeWeekMenu(planner, start: tomorrow, meals: {...Meal.values});
    expect(sw.elapsedMilliseconds, lessThan(1000), reason: 'voorstellen moet snel gaan');
    expect(built, lessThan(5000));
    expect(m.days, hasLength(7));
    expectGoodDays(m);
    for (final d in m.days) {
      expect({for (final i in d.items) i.meal}, containsAll(Meal.values));
      // Elke dag zegt eerlijk hoe ver hij komt
      final c = planner.check(d);
      expect(c.energyOk, isTrue);
      expect(c.low.length, lessThan(8));
    }
  });

  test('deterministisch voor dezelfde seed; Opnieuw schudden geeft iets anders', () {
    final s = newState();
    final planner = s.weekMenuPlanner();
    List<String> names(WeekMenu m) => [
      for (final d in m.days)
        for (final i in d.items) '${i.meal.name}:${i.food.food.ref}:${i.grams}',
    ];
    final a = s.proposeWeekMenu(planner, start: tomorrow, count: 5, meals: {...Meal.values}, seed: 3);
    final b = s.proposeWeekMenu(s.weekMenuPlanner(), start: tomorrow, count: 5, meals: {...Meal.values}, seed: 3);
    expect(names(a), names(b));
    final c = s.proposeWeekMenu(planner, start: tomorrow, count: 5, meals: {...Meal.values}, seed: 4);
    expect(names(c), isNot(names(a)));
    // Afwisseling over de week: niet elke dag hetzelfde avondeten
    final dinners = {for (final d in a.days) d.items.where((i) => i.meal == Meal.dinner).map((i) => i.food.key).join('+')};
    expect(dinners.length, greaterThan(2));
  });

  test('allergieën, vegan en "Let op suiker" worden gerespecteerd', () {
    final s = newState()
      ..setAllergies({Allergen.milk, Allergen.nuts, Allergen.eggs})
      ..setPreferences({DietPref.vegan})
      ..setSugarFocus(true);
    final planner = s.weekMenuPlanner();
    final m = s.proposeWeekMenu(planner, start: tomorrow, meals: {...Meal.values});
    for (final d in m.days) {
      expect(d.items, isNotEmpty);
      for (final i in d.items) {
        expect(containsAllergen(i.food.food, s.allergies), isFalse, reason: i.food.food.name);
        expect(fitsPreferences(i.food.food, s.preferences), isTrue, reason: i.food.food.name);
        expect(const {'meat', 'poultry', 'fish', 'shellfish', 'egg', 'dairy'}.contains(i.food.food.label?.group), isFalse, reason: i.food.food.name);
      }
      final free = d.totals['free_sugars'] ?? 0;
      final upper = d.targets['free_sugars']?.upper;
      if (upper != null) expect(free, lessThanOrEqualTo(upper));
      expect(d.share('energy')!, inInclusiveRange(0.9, 1.1));
      // Vitamine B12 haal je als veganist niet uit gewoon eten: dat zegt het plan eerlijk
      final c = planner.check(d);
      if (c.low.contains('b12')) expect(c.hard, contains('b12'));
    }
  });

  test('vertrekt van je eigen gewoonten en vult tekorten met adviesproducten', () {
    final s = newState();
    final today = DateTime(logicalNow().year, logicalNow().month, logicalNow().day);
    final oats = item(s, 'rolled oats', 60), milk = item(s, 'semi-skimmed milk', 250), toast = item(s, 'wholemeal bread', 70);
    final pasta = item(s, 'pasta boiled', 250);
    for (var i = 1; i <= 10; i++) {
      final day = dayKey(today.subtract(Duration(days: i)));
      s.user.addTemplate(day, Meal.breakfast, oats);
      s.user.addTemplate(day, Meal.breakfast, milk);
      s.user.addTemplate(day, Meal.lunch, toast);
      s.user.addTemplate(day, Meal.dinner, pasta);
    }
    // Wie geen snacks eet, krijgt standaard ook geen snacks gepland
    expect(s.mealPattern().usual, {Meal.breakfast, Meal.lunch, Meal.dinner});
    // Vaak te weinig: vitaminen en mineralen uit zo'n eentonig menu
    expect(s.usualShortfalls(), isNotEmpty);
    final planner = s.weekMenuPlanner();
    final m = s.proposeWeekMenu(planner, start: tomorrow, meals: s.mealPattern().usual);
    expectGoodDays(m);
    var ownBreakfast = 0, advice = 0;
    for (final d in m.days) {
      expect(d.items.where((i) => i.meal == Meal.snacks), isEmpty);
      if (d.items.any((i) => i.meal == Meal.breakfast && i.food.food.ref == oats.foodRef)) ownBreakfast++;
      advice += d.items.where((i) => i.source == MenuSource.advice).length;
      expect(d.items.where((i) => i.source == MenuSource.advice).length, lessThanOrEqualTo(3));
    }
    expect(ownBreakfast, greaterThanOrEqualTo(4), reason: 'je gewone ontbijt komt meestal terug');
    expect(advice, greaterThan(0), reason: 'een paar adviesproducten voor je tekorten');
  });

  test('omwisselen en weglaten, dan in de planner en op de boodschappenlijst', () {
    final s = newState();
    final planner = s.weekMenuPlanner();
    var m = s.proposeWeekMenu(planner, start: tomorrow, count: 3, meals: {Meal.breakfast, Meal.lunch, Meal.dinner});
    final d = m.days.first;
    final options = planner.alternatives(d, 0, meals: m.meals);
    expect(options, isNotEmpty);
    expect(options.every((o) => o.meal == d.items.first.meal && o.food.key != d.items.first.food.key), isTrue);
    m = m.withDay(0, planner.replace(d, 0, options.first));
    expect(m.days.first.items.first.food.key, options.first.food.key);
    final before = m.days.first.items.length;
    m = m.withDay(0, planner.remove(m.days.first, 1));
    expect(m.days.first.items, hasLength(before - 1));

    // Een snack die al gepland stond, blijft staan; de geplande maaltijden worden vervangen
    final first = dayKey(m.days.first.date);
    s.addToPlan(first, Meal.snacks, item(s, 'apple', 150));
    s.addToPlan(first, Meal.lunch, item(s, 'banana', 120));
    s.useWeekMenu(m);
    for (final day in m.days) {
      expect(s.planFor(dayKey(day.date)), hasLength(day.items.length + (day == m.days.first ? 1 : 0)));
    }
    expect(s.planFor(first).where((x) => x.meal == Meal.snacks), hasLength(1));
    expect(s.planFor(first).any((x) => x.item.name.startsWith('Banana')), isFalse);
    expect(s.planTotals(first).values['energy'], closeTo(m.days.first.kcal + _snackKcal(s, first), 1));

    final n = s.shoppingFromMenu(m);
    final names = {
      for (final d in m.days)
        for (final i in d.items) i.food.food.name,
    };
    expect(n, names.length);
    expect(s.shopping.map((x) => x.name).toSet(), names);
    final grams = {for (final x in s.shopping) x.name: x.grams};
    final first0 = m.days.first.items.first;
    final total = m.days.fold(0.0, (a, d) => a + d.items.where((i) => i.food.food.name == first0.food.food.name).fold(0.0, (b, i) => b + i.grams));
    expect(grams[first0.food.food.name], closeTo(total, 0.01));
  });

  for (final size in const [Size(1440, 1000), Size(412, 900)]) {
    testWidgets('scherm bouwt op ${size.width.round()} px en zet het plan in de planner', (tester) async {
      final s = newState();
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const WeekMenuScreen()),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Plan my week'), findsOneWidget);
      await tester.tap(find.text('3 days'));
      await tester.pump();
      await tester.tap(find.byTooltip('Shuffle'));
      await tester.pump();
      // Een regel omwisselen via het blad met andere keuzes
      // In het midden van het scherm, niet onder de knoppenbalk onderaan
      Scrollable.ensureVisible(tester.element(find.byTooltip('Swap').first), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Swap').first);
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsWidgets);
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Add to shopping list'));
      await tester.pump();
      expect(s.shopping, isNotEmpty);
      await tester.tap(find.text('Use this plan'));
      await tester.pumpAndSettle();
      expect(s.plannedDays, hasLength(3));
      expect(tester.takeException(), isNull);
    });
  }
}

double _snackKcal(AppState s, String day) => s.planFor(day).where((x) => x.meal == Meal.snacks).fold(0.0, (a, x) => a + x.item.kcal);
