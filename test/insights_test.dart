import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/preferences.dart';
import 'package:macromatrix/nutrition/targets.dart';

void main() {
  final targets = targetsFor(const Profile(), year: 2026);

  group('status', () {
    test('tekort, op doel en boven de bovengrens', () {
      const t = Target(goal: 15, upper: 100);
      expect(levelOf(5, t), Level.low);
      expect(levelOf(15, t), Level.ok);
      expect(levelOf(120, t), Level.high);
      expect(levelOf(1500, const Target(upper: 2000)), Level.ok);
      expect(levelOf(2500, const Target(upper: 2000)), Level.high);
      expect(fractionOf(1000, const Target(upper: 2000)), 0.5);
      expect(fractionOf(1, null), isNull);
    });
  });

  group('volledigheidsscore', () {
    test('alles op doel = 100, niets = 0', () {
      final full = {for (final k in stripKeys) k: (targets[k]!.goal ?? 0) * 1.0};
      full['sodium'] = 1500;
      expect(completenessScore(full, targets), 100);
      expect(completenessScore({}, targets), 0); // niets gegeten: geen punten, ook niet voor 'binnen de limiet'
    });

    test('boven een limiet daalt de score', () {
      final full = {for (final k in stripKeys) k: (targets[k]!.goal ?? 0) * 1.0};
      full['sodium'] = 4000; // dubbel het maximum: telt voor 50%
      expect(completenessScore(full, targets), ((stripKeys.length - 0.5) / stripKeys.length * 100).round());
    });
  });

  group('aandacht', () {
    test('grootste tekorten eerst, hooguit één "te veel"', () {
      final v = {for (final k in stripKeys) k: (targets[k]!.goal ?? 0) * 1.2};
      v['vit_d'] = 3; // 20%
      v['iodine'] = 60; // 40%
      v['magnesium'] = 300; // 86%
      v['sodium'] = 2600; // boven max
      final a = attentionList(v, targets);
      expect(a.map((x) => x.$1.key), ['vit_d', 'iodine', 'sodium']);
      expect(a.last.$3, Level.high);
    });
  });

  group('macroverdeling', () {
    test('in delen van de energie', () {
      final s = macroSplit({'protein': 25, 'carbs': 50, 'fat': 11.11})!;
      expect(s.$1 + s.$2 + s.$3, closeTo(1, 1e-9));
      expect(s.$1, closeTo(100 / 400, 1e-3));
      expect(macroSplit({}), isNull);
    });
  });

  group('gewicht en verbruik', () {
    List<String> days(int n) => [for (var i = 0; i < n; i++) 'd${i.toString().padLeft(2, '0')}'];

    test('trendgewicht neemt de vorige waarde over op dagen zonder weging', () {
      final d = days(4);
      final t = weightTrend({'d00': 80, 'd02': 79}, d);
      expect(t[0], 80);
      expect(t[1], 80);
      expect(t[2], closeTo(79.9, 1e-9));
      expect(t[3], t[2]);
    });

    test('stabiel gewicht: verbruik = gemiddelde inname', () {
      final d = days(28);
      final kcal = {for (final k in d) k: 2400.0};
      final w = {for (var i = 0; i < 28; i += 3) d[i]: 75.0};
      final e = estimateEnergy(kcal, w, d)!;
      expect(e.tdee, closeTo(2400, 1e-6));
      expect(e.trendChange, closeTo(0, 1e-9));
    });

    test('0,5 kg per week afvallen bij 2000 kcal: verbruik ± 2550', () {
      final d = days(28);
      final kcal = {for (final k in d) k: 2000.0};
      final w = {for (var i = 0; i < 28; i += 2) d[i]: 80 - i * 0.5 / 7};
      final e = estimateEnergy(kcal, w, d)!;
      expect(e.tdee, closeTo(2000 + 0.5 / 7 * 7700, 1));
    });

    test('te weinig gegevens: geen schatting', () {
      final d = days(28);
      expect(estimateEnergy({for (final k in d.take(5)) k: 2000.0}, {d[0]: 80, d[20]: 79}, d), isNull);
      expect(estimateEnergy({}, {}, days(10)), isNull);
      // Onvolledig gelogde dagen (< 800 kcal) tellen niet
      expect(estimateEnergy({for (final k in d) k: 500.0}, {for (var i = 0; i < 28; i += 2) d[i]: 80}, d), isNull);
    });
  });

  group('voorkeuren', () {
    Food f(String name, {Map<String, double> v = const {}, String? local}) =>
        Food(ref: 'x:$name', name: name, source: FoodSource.usda, per100g: v, localName: local);

    test('vlees, vis en zuivel herkennen', () {
      expect(fitsPreferences(f('Chicken, breast, roasted'), {DietPref.vegetarian}), isFalse);
      expect(fitsPreferences(f('Fish, salmon, raw'), {DietPref.pescatarian}), isTrue);
      expect(fitsPreferences(f('Fish, salmon, raw'), {DietPref.vegetarian}), isFalse);
      expect(fitsPreferences(f('Beans, kidney, red, boiled'), {DietPref.vegan}), isTrue);
      expect(fitsPreferences(f('Yogurt, Greek, plain'), {DietPref.vegan}), isFalse);
      expect(fitsPreferences(f('Peanut butter, smooth'), {DietPref.vegan}), isTrue);
      expect(fitsPreferences(f('Peanut butter, smooth'), {DietPref.noNuts}), isFalse);
      expect(fitsPreferences(f('Almond milk, unsweetened'), {DietPref.lactoseFree}), isTrue);
      expect(fitsPreferences(f('Milk, lactose-free, semi-skimmed'), {DietPref.lactoseFree}), isTrue);
      expect(fitsPreferences(f('Milk, whole'), {DietPref.lactoseFree}), isFalse);
      // Ook in de taal van de bron
      expect(fitsPreferences(f('Ham, cooked', local: 'Jambon cuit'), {DietPref.noPork}), isFalse);
    });

    test('carnivore en animal-based', () {
      const c = {DietPref.carnivore}, a = {DietPref.animalBased};
      expect(fitsPreferences(f('Beef, ground, 85% lean, cooked'), c), isTrue);
      expect(fitsPreferences(f('Beef, variety meats and by-products, liver, raw'), c), isTrue);
      expect(fitsPreferences(f('Egg, whole, hard-boiled'), c), isTrue);
      expect(fitsPreferences(f('Cheese, cheddar'), c), isTrue);
      expect(fitsPreferences(f('Chicken salad with vegetables'), c), isFalse);
      expect(fitsPreferences(f('Apple, raw'), c), isFalse);
      expect(fitsPreferences(f('Beans, kidney, red, boiled'), c), isFalse);
      expect(fitsPreferences(f('Apple, raw'), a), isTrue, reason: 'fruit mag bij animal-based');
      expect(fitsPreferences(f('Honey'), a), isTrue);
      expect(fitsPreferences(f('Beef, ground, 85% lean, cooked'), a), isTrue);
      expect(fitsPreferences(f('Oats, rolled'), a), isFalse);
      expect(fitsPreferences(f('Beans, kidney, red, boiled'), a), isFalse);
      expect(fitsPreferences(f('Almonds, raw'), a), isFalse);
      expect(fitsPreferences(f('Oil, sunflower'), a), isFalse);
      expect(fitsPreferences(f('Broccoli, raw'), a), isFalse);
      expect(fitsPreferences(f('Squash, butternut, baked'), a), isTrue);
    });

    test('suiker en alcohol op de voedingswaarden', () {
      expect(fitsPreferences(f('Cookie', v: {'sugars': 30}), {DietPref.lowSugar}), isFalse);
      expect(fitsPreferences(f('Apple', v: {'sugars': 10}), {DietPref.lowSugar}), isTrue);
      expect(fitsPreferences(f('Drink', v: {'alcohol': 5}), {DietPref.noAlcohol}), isFalse);
      expect(fitsPreferences(f('Ginger, raw'), {DietPref.noAlcohol}), isTrue);
    });
  });

  group('tempo', () {
    test('afvallen standaard 0,5 kg per week, behouden altijd 0', () {
      const lose = Profile(goal: Goal.lose);
      expect(lose.rate, -0.5);
      expect(lose.goalKcal, closeTo(-550, 1e-9));
      expect(const Profile(goal: Goal.maintain, rateKgPerWeek: -1).goalKcal, 0);
      expect(const Profile(goal: Goal.gain, rateKgPerWeek: 0.1).goalKcal, closeTo(110, 1e-9));
    });

    test('adaptief verbruik vervangt de formule', () {
      const p = Profile(goal: Goal.lose, rateKgPerWeek: -0.25);
      expect(energyTarget(p, 2026, tdee: 2500), (2500 - 275).roundToDouble());
      expect(Profile.fromJson(p.toJson()).rateKgPerWeek, -0.25);
    });
  });
}
