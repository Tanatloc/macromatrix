import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/portions.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';

/// Ronde 11: standaardporties (NW-12), realistisch advies bij "Wat moet ik nog eten?" (NW-10, NW-11, NF-5) en
/// energieadvies naar de grootte van het tekort (SP-6).
void main() {
  final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  AppState newState() => AppState(foods: db, user: UserDb(sqlite3.openInMemory()));
  Food byRef(String ref) => db.byRef(ref)!;

  group('NW-12: standaardportie bij het toevoegen', () {
    ({Portion? portion, double quantity}) start(Food f) => defaultServing(f);
    double grams(Food f) {
      final d = start(f);
      return d.portion == null ? d.quantity : d.portion!.grams * d.quantity;
    }

    test('havermout: een kom, geen eetlepel', () {
      // "Oatmeal" uit de Noorse tabel (havermeel, met eetlepel en deciliter) en gewone havervlokken
      for (final ref in ['mvt:05.004', 'mvt:05.003']) {
        final f = byRef(ref);
        final d = start(f);
        expect(d.portion?.label, contains('bowl'), reason: f.name);
        expect(grams(f), inInclusiveRange(30, 80), reason: f.name);
      }
    });

    test('spaghetti bolognese: een bord, niet 100 g', () {
      final f = byRef('cofid:19-628');
      expect(start(f).portion?.label, contains('plate'));
      expect(grams(f), inInclusiveRange(300, 450));
    });

    test('appel 1 stuk, brood 1 sneetje, noten een handvol, melk een glas', () {
      final apple = byRef('mvt:06.757');
      expect(start(apple).portion?.label, '1 pcs (medium)');
      final bread = byRef('frida:861');
      expect(start(bread).portion?.label, contains('slice'));
      expect(grams(bread), inInclusiveRange(20, 60));
      final almonds = db.search('almonds toasted', limit: 5).firstWhere((f) => f.label?.group == 'nut/seed');
      expect(start(almonds).portion?.label, contains('handful'));
      expect(grams(almonds), 30);
      final milk = byRef('ciqual:19041');
      expect(start(milk).portion?.label, contains('glass'));
      expect(grams(milk), inInclusiveRange(150, 350));
    });

    test('nooit een eetlepel voor gewoon eten, wel voor olie', () {
      const flakes = Food(
        ref: 'x:flakes',
        name: 'Wheat flakes',
        source: FoodSource.ciqual,
        per100g: {'energy': 350},
        portions: [Portion('1 tablespoon', 6)],
        label: FoodLabel(food: 'wheat flakes', group: 'cereal', part: 'product', kind: 'plant', state: 'raw'),
      );
      expect(start(flakes).portion, isNull);
      expect(start(flakes).quantity, 100);
      const oil = Food(
        ref: 'x:oil',
        name: 'Rapeseed oil',
        source: FoodSource.ciqual,
        per100g: {'energy': 900},
        portions: [Portion('1 tablespoon', 14)],
        label: FoodLabel(food: 'rapeseed oil', group: 'oil/fat', part: 'oil', kind: 'plant', state: 'raw'),
      );
      expect(start(oil).portion?.label, '1 tablespoon');
    });

    test('de laatste hoeveelheid van een product gaat voor', () {
      final s = newState();
      final oats = byRef('mvt:05.004');
      expect(s.startServing(oats).portion?.label, contains('bowl'));
      s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
      expect(s.startServing(oats).portion, isNull);
      expect(s.startServing(oats).quantity, 60);
      final apple = byRef('mvt:06.757');
      s.addFood(apple, meal: Meal.snacks, grams: 330, quantity: 2, portionLabel: '1 pcs (large)');
      expect(s.startServing(apple).portion?.label, '1 pcs (large)');
      expect(s.startServing(apple).quantity, 2);
    });
  });

  group('NW-10, NW-11: geen chilipeper, rauwe paddenstoelen of schaal', () {
    final odd = RegExp(r'chill?i|jalape|weighed with|with shells?|\bgarlic\b|venison|reindeer|\bhare\b|protein shake', caseSensitive: false);
    bool rawMushroom(Food f) => f.label?.group == 'mushroom' && f.label?.state == 'raw';

    test('geen advies voor zulke producten', () {
      for (final q in [
        'chilli red raw',
        'chili pepper raw',
        'chanterelle raw',
        'crab weighed with shell',
        'almonds weighed with shells',
        'mushroom raw',
      ]) {
        for (final f in db.search(q, limit: 20)) {
          if (odd.hasMatch(f.name) || rawMushroom(f)) expect(isAdviceFood(f), isFalse, reason: f.name);
        }
      }
    });

    test('een gewone dag van een nieuwkomer: gewone producten in gewone porties', () {
      final s = newState();
      void add(String ref, double g, Meal m) => s.addFood(byRef(ref), meal: m, grams: g, quantity: g);
      add('mvt:05.004', 7, Meal.breakfast);
      add('frida:861', 70, Meal.lunch);
      add('cofid:19-628', 100, Meal.dinner);
      add('mvt:06.757', 150, Meal.snacks);
      add('mvt:06.107', 30, Meal.snacks);
      final plan = s.gapPlan()!;
      for (final i in plan.items) {
        expect(odd.hasMatch(i.food.name) || rawMushroom(i.food), isFalse, reason: i.food.name);
        final (_, cap) = adviceServing(i.food);
        expect(i.grams, lessThanOrEqualTo(cap), reason: i.food.name);
      }
      final sg = s.suggestion;
      if (sg != null) {
        expect(odd.hasMatch(sg.food.name) || rawMushroom(sg.food), isFalse, reason: sg.food.name);
      }
      for (final k in ['vit_c', 'vit_d', 'vit_a', 'b12', 'zinc']) {
        for (final (f, _) in s.oracle(k, rank: OracleRank.perPortion, limit: 15, everyday: true)) {
          expect(odd.hasMatch(f.name) || rawMushroom(f), isFalse, reason: '$k: ${f.name}');
        }
      }
    });
  });

  group('NF-5: het plan pakt de grootste tekorten aan', () {
    Food f(String name, Map<String, double> v, {String group = 'vegetable', String food = '', String part = 'product', String state = 'cooked'}) =>
        Food(
          ref: 'x:$name',
          name: name,
          source: FoodSource.ciqual,
          per100g: v,
          label: FoodLabel(food: food.isEmpty ? name.toLowerCase() : food, group: group, part: part, kind: 'plant', state: state, spread: 6),
        );

    test('calcium als grootste tekort: zuivel, niet alleen spinazie en paprika', () {
      final targets = {for (final k in stripKeys) k: const Target(goal: 100)};
      // Calcium op 41%, vitamine K en A wat lager dan de rest
      final totals = {for (final k in stripKeys) k: 90.0}..addAll({'calcium': 41.0, 'vit_k': 60.0, 'vit_a': 65.0});
      final plan = planGaps(
        totals: totals,
        targets: targets,
        kcalLeft: 665,
        candidates: [
          f('Spinach, raw', {'energy': 23, 'calcium': 99, 'vit_k': 400, 'vit_a': 50}, food: 'spinach', part: 'leaf', state: 'raw'),
          f('Pepper, red, raw', {'energy': 26, 'vit_a': 15, 'vit_c': 120}, food: 'sweet pepper', state: 'raw'),
          f('Mussels, canned', {'energy': 70, 'b12': 200}, group: 'shellfish', food: 'mussel', state: 'canned'),
          f('Yoghurt, plain', {'energy': 60, 'calcium': 15, 'b2': 15, 'b12': 10}, group: 'dairy', food: 'yoghurt'),
          f('Cheese, gouda', {'energy': 360, 'calcium': 80, 'b12': 50}, group: 'dairy', food: 'gouda cheese'),
        ],
      )!;
      final names = plan.items.map((i) => i.food.name).toList();
      expect(names.any((n) => n.contains('Yoghurt') || n.contains('Cheese')), isTrue, reason: '$names');
      final calcium = plan.items.expand((i) => i.fills).where((x) => x.$1.key == 'calcium').toList();
      expect(calcium, isNotEmpty, reason: 'calcium staat in het plan');
      // Spinazie telt niet als calciumbron (oxalaat)
      for (final i in plan.items.where((i) => i.food.name.startsWith('Spinach'))) {
        expect(i.fills.map((x) => x.$1.key), isNot(contains('calcium')));
      }
      // Met wat energie, maar niet meer dan er over is
      expect(plan.kcal, greaterThan(150));
      expect(plan.kcal, lessThanOrEqualTo(665));
    });
  });

  group('maaltijd volgens het uur (NW-10, NW-11)', () {
    DateTime at(int h) => DateTime(2026, 10, 25, h, 30);
    test('de volgende maaltijd, niet het ontbijt s avonds', () {
      expect(AppState.nextMealFor(at(8), {}), Meal.breakfast);
      expect(AppState.nextMealFor(at(10), {Meal.breakfast}), Meal.lunch);
      expect(AppState.nextMealFor(at(13), {}), Meal.lunch);
      expect(AppState.nextMealFor(at(19), {}), Meal.dinner);
      expect(AppState.nextMealFor(at(19), {Meal.breakfast, Meal.lunch, Meal.dinner}), Meal.snacks);
      expect(AppState.nextMealFor(at(22), {}), Meal.snacks);
      // Na middernacht, vóór het begin van de dag (standaard 3 uur): nog gisteren, dus een tussendoortje
      expect(AppState.nextMealFor(at(1), {}), Meal.snacks);
    });
  });

  group('SP-6: advies naar de grootte van het tekort', () {
    test('tussendoortje, extra maaltijd, of eerst nakijken of alles gelogd is', () {
      expect(eatMoreAdvice(300), contains('extra snack'));
      expect(eatMoreAdvice(300), isNot(contains('extra meal')));
      expect(eatMoreAdvice(700), contains('extra meal'));
      expect(eatMoreAdvice(700), isNot(contains('check')));
      final big = eatMoreAdvice(1517);
      expect(big, contains('check that every meal'));
      expect(big, contains('1,500'));
      expect(big, isNot(contains('an extra snack or')));
      expect(eatMoreAdvice(300, ifLogged: true), startsWith('If you logged everything'));
    });

    test('in het weekrapport: 1500 kcal te weinig is geen tussendoortje', () {
      final m = energyMessage(EnergyCase.under, eaten: 1841, goal: 3358);
      expect(m.advice, contains('check that every meal'));
      expect(m.advice, isNot(contains('an extra snack or a bigger portion')));
    });
  });
}
