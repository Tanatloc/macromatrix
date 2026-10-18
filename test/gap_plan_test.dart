import 'package:flutter_test/flutter_test.dart';
import 'package:voedingsapp/data/food.dart';
import 'package:voedingsapp/nutrition/gap_plan.dart';
import 'package:voedingsapp/nutrition/insights.dart';
import 'package:voedingsapp/nutrition/targets.dart';

Food f(String name, Map<String, double> v) => Food(ref: 'x:$name', name: name, source: FoodSource.ciqual, per100g: v);

void main() {
  final targets = {for (final k in stripKeys) k: const Target(goal: 100)};
  test('kiest producten die de grootste tekorten vullen, binnen de energie', () {
    final totals = {for (final k in stripKeys) k: 90.0}..addAll({'vit_d': 10.0, 'calcium': 20.0});
    final plan = planGaps(
      totals: totals,
      targets: targets,
      kcalLeft: 600,
      candidates: [
        f('Sardines', {'energy': 200, 'vit_d': 50, 'calcium': 40}),
        f('Spinach', {'energy': 25, 'calcium': 20}),
        f('Cake', {'energy': 450, 'calcium': 5}),
        f('Fish oil', {'energy': 900, 'vit_d': 100}),
      ],
    )!;
    expect(plan.items.first.food.name, 'Sardines');
    expect(plan.items.map((i) => i.food.name), isNot(contains('Fish oil')), reason: 'olie is geen voedingsmiddel');
    expect(plan.after, greaterThan(plan.before));
    expect(plan.kcal, lessThanOrEqualTo(600));
    expect(plan.items.first.fills.first.$1.key, 'vit_d');
  });

  test('geen plan als alles op doel zit', () {
    final totals = {for (final k in stripKeys) k: 100.0};
    expect(
      planGaps(
        totals: totals,
        targets: targets,
        kcalLeft: 500,
        candidates: [
          f('Apple', {'energy': 50, 'vit_c': 5}),
        ],
      ),
      isNull,
    );
  });

  test('bovengrens wordt niet overschreden', () {
    final t = {...targets, 'vit_d': const Target(goal: 100, upper: 120)};
    final totals = {for (final k in stripKeys) k: 100.0}..['vit_d'] = 30.0;
    final plan = planGaps(
      totals: totals,
      targets: t,
      kcalLeft: 500,
      candidates: [
        f('Megadose', {'energy': 10, 'vit_d': 200}),
      ],
    );
    expect(plan, isNull);
  });

  test('geen kruiden of extreme hoeveelheden', () {
    final totals = {for (final k in stripKeys) k: 90.0}..addAll({'vit_k': 10.0, 'vit_a': 30.0});
    final plan = planGaps(
      totals: totals,
      targets: targets,
      kcalLeft: 600,
      candidates: [
        f('Basil, dried', {'energy': 230, 'vit_k': 1700}),
        f('Liver, poultry, cooked', {'energy': 160, 'vit_a': 4000}),
        f('Kale, raw', {'energy': 50, 'vit_k': 150, 'vit_a': 50}),
      ],
    )!;
    expect(plan.items.map((i) => i.food.name), ['Kale, raw']);
  });
}
