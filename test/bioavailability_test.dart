import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/bioavailability.dart';
import 'package:macromatrix/nutrition/targets.dart';

DiaryEntry e(String name, Meal meal, Map<String, double> per100, {double grams = 100}) =>
    DiaryEntry(id: name, day: '2026-10-17', meal: meal, foodRef: 'x:$name', name: name, grams: grams, quantity: grams, per100g: per100);

void main() {
  const targets = {'zinc': Target(goal: 10)};
  test('plantaardig ijzer zonder vitamine C, en koffie erbij', () {
    final tips = bioTips([
      e('Lentils, boiled', Meal.lunch, {'iron': 3.3, 'zinc': 1.3, 'vit_c': 1.5}),
    ], targets);
    expect(tips.first.title, contains('vitamin C'));
    final coffee = bioTips([
      e('Lentils, boiled', Meal.lunch, {'iron': 3.3}),
      e('Coffee, brewed', Meal.lunch, {'caffeine': 40}),
    ], targets);
    expect(coffee.map((t) => t.title), contains('Coffee or tea with iron'));
    expect(coffee.map((t) => t.title), isNot(contains('Add vitamin C for iron')));
  });

  test('pluim voor ijzer met vitamine C; vlees telt niet als plantaardig', () {
    final good = bioTips([
      e('Lentils, boiled', Meal.dinner, {'iron': 3.3}),
      e('Peppers, sweet, red, raw', Meal.dinner, {'vit_c': 128}),
    ], targets);
    expect(good.any((t) => t.kind == TipKind.good), isTrue);
    expect(
      bioTips([
        e('Beef, steak, grilled', Meal.dinner, {'iron': 3}),
      ], targets),
      isEmpty,
    );
  });

  test('vetoplosbare vitamines zonder vet, calcium uit spinazie, zink en fytaat', () {
    final tips = bioTips([
      e('Spinach, raw', Meal.lunch, {'vit_k': 480, 'calcium': 99, 'fat': 0.4}),
      e('Oats, rolled', Meal.breakfast, {'zinc': 3.6, 'fat': 6.5}),
    ], targets);
    final titles = tips.map((t) => t.title).toList();
    expect(titles, contains('Add a little fat'));
    expect(titles, contains('Calcium from spinach'));
    expect(titles, contains('Zinc and phytate'));
  });

  test('supplementen alleen tellen geen tips', () {
    expect(
      bioTips([
        e('Vitamin D3', Meal.breakfast, {'vit_d': 25}).copyWithRef('supp:vitd25'),
      ], targets),
      isEmpty,
    );
  });
}

extension on DiaryEntry {
  DiaryEntry copyWithRef(String ref) =>
      DiaryEntry(id: id, day: day, meal: meal, foodRef: ref, name: name, grams: grams, quantity: quantity, per100g: per100g);
}
