/// Zoekresultaten bundelen: hetzelfde voedingsmiddel uit verschillende landen (CIQUAL, Frida, CoFID, ...) wordt één
/// resultaat, met de beste bron vooraan en de andere onder "Andere bronnen".
library;

import '../data/food.dart';

class FoodGroup {
  const FoodGroup(this.main, this.others);

  /// Wat je ziet: een Europese bron met zo veel mogelijk gemeten waarden.
  final Food main;

  /// Hetzelfde voedingsmiddel uit andere bronnen.
  final List<Food> others;
}

/// Gewogen mét afval (schil, pitten, graat, been): de waarden gelden per 100 g zoals gekocht, niet per 100 g die je
/// eet. Correct, maar een valkuil: zo'n banaan heeft 51 kcal per 100 g in plaats van 89.
final _weighedWith = RegExp(r'weighed with|as purchased|including (skin|bones?|pips|shell)', caseSensitive: false);

bool weighedWithWaste(Food f) => _weighedWith.hasMatch(f.name) || (f.label?.flags.contains('with bone') ?? false);

/// Kenmerken die niets aan de voedingswaarden veranderen en dus niet apart hoeven.
const _sameFlags = {'organic', 'brand'};

String _key(Food f) {
  final l = f.label;
  if (l == null) return f.ref;
  final flags = [
    for (final x in l.flags)
      if (!_sameFlags.contains(x)) x,
  ]..sort();
  return [l.food, l.group, l.part, l.state, l.dish ? 'dish' : '', ...flags].join('|');
}

/// Groepeert in de volgorde van [foods] (de zoekvolgorde): een groep staat waar zijn eerste lid stond.
List<FoodGroup> groupFoods(List<Food> foods) {
  final groups = <String, List<Food>>{};
  for (final f in foods) {
    groups.putIfAbsent(_key(f), () => []).add(f);
  }
  return [
    for (final members in groups.values)
      () {
        // Bij gelijke stand de zoekvolgorde (sort is niet stabiel)
        final best = [...members]..sort((a, b) => _better(a, b) != 0 ? _better(a, b) : members.indexOf(a) - members.indexOf(b));
        return FoodGroup(best.first, [...best.skip(1)]);
      }(),
  ];
}

/// Beter = niet gewogen met afval, Europees, meer gemeten (niet geschatte) waarden; anders de zoekvolgorde.
int _better(Food a, Food b) {
  int score(Food f) => (weighedWithWaste(f) ? 0 : 1000) + (f.source.european ? 500 : 0) + (f.per100g.length - f.estimated.length).clamp(0, 499);
  return score(b).compareTo(score(a));
}
