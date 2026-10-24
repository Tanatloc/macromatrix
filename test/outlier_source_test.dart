import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/state/app_state.dart';

/// Een bron die afwijkt van de andere bronnen van hetzelfde product (Matvaretabellens gebraden eend en gans: bijna
/// dubbel zoveel eiwit, veel minder water) komt niet vooraan, niet in het zoekvak en niet bij Snel loggen.
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  const outliers = {'mvt:03.232', 'mvt:03.233', 'mvt:03.234'};

  test('gebraden eend en gans: de afwijkende bron staat bij "Andere bronnen", gemarkeerd', () {
    for (final q in ['duck roasted', 'roast duck', 'goose roasted', 'roast goose', 'duck']) {
      final groups = groupFoods(s.searchLocal(q));
      for (final g in groups) {
        expect(outliers, isNot(contains(g.main.ref)), reason: '$q: ${g.main.ref} ${g.main.name}');
      }
      expect(groups.first.main.ref, isNot('mvt:03.232'), reason: q);
    }
    final duck = groupFoods(s.searchLocal('roast duck')).firstWhere((g) => g.others.any((o) => o.ref == 'mvt:03.232'));
    expect(duck.disagreeing, contains('mvt:03.232'));
    expect(duck.disagreeing, isNot(contains(duck.main.ref)));
    expect(duck.main.per100g['protein']!, lessThan(30));
  });

  test('Snel loggen kiest de afwijkende bron niet als eerste', () {
    for (final q in ['duck roasted', 'roast duck', 'roasted duck', 'goose roasted', 'roast goose', 'duck']) {
      final first = s.resolveQuick(QuickItem(q)).first.$1;
      expect(outliers, isNot(contains(first.ref)), reason: '$q: ${first.ref} ${first.name}');
    }
  });

  test('regel: afwijkend tegenover de mediaan van minstens twee andere bronnen', () {
    const label = FoodLabel(food: 'duck', group: 'poultry', part: '', kind: '', state: 'roasted', flags: ['without skin']);
    Food f(String ref, double protein, double water) => Food(
      ref: ref,
      name: 'Duck, roasted',
      source: FoodSource.ciqual,
      label: label,
      per100g: {'energy': 200, 'protein': protein, 'fat': 10, 'water': water},
    );
    expect(disagreeingSources([f('a:1', 25, 62), f('b:1', 23, 63), f('c:1', 46.7, 47)]), {'c:1'});
    // Met maar één andere bron is er geen meerderheid
    expect(disagreeingSources([f('a:1', 25, 62), f('c:1', 46.7, 47)]), isEmpty);
    // Kleine verschillen tellen niet
    expect(disagreeingSources([f('a:1', 25, 62), f('b:1', 23, 63), f('c:1', 30, 58)]), isEmpty);
    final g = groupFoods([f('c:1', 46.7, 47), f('a:1', 25, 62), f('b:1', 23, 63)]).single;
    expect(g.main.ref, isNot('c:1'));
    expect(g.disagreeing, {'c:1'});
  });
}
