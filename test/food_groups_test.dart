import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';

void main() {
  final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));

  test('banaan: één resultaat voor de rauwe banaan, met de andere landen eronder', () {
    final groups = groupFoods(db.search('banaan'));
    final raw = groups.firstWhere((g) => g.main.label?.food == 'banana' && g.main.label?.state == 'raw' && g.main.label?.group == 'fruit');
    expect(raw.others.length, greaterThanOrEqualTo(4));
    expect(raw.main.source.european, isTrue);
    expect(weighedWithWaste(raw.main), isFalse);
    expect(raw.others.any(weighedWithWaste), isTrue); // de valkuil van 51 kcal zit bij "Andere bronnen"
    // Gedroogd en chips blijven aparte resultaten
    expect(groups.where((g) => g.main.label?.food == 'banana' && g.main.label?.state != 'raw'), isNotEmpty);
    // Geen enkel voedingsmiddel komt twee keer voor als hoofdresultaat
    final keys = [
      for (final g in groups)
        if (g.main.label case final l?) '${l.food}|${l.group}|${l.part}|${l.state}|${l.flags.join(',')}',
    ];
    expect(keys.toSet().length, keys.length);
  });

  test('de zoekvolgorde blijft: het eerste resultaat blijft eerst', () {
    final results = db.search('zalm');
    final groups = groupFoods(results);
    expect(groups.first.main.label?.food, results.first.label?.food);
    expect(groups.length, lessThan(results.length));
  });

  test('producten zonder label (eigen, merk) worden nooit samengevoegd', () {
    Food own(String id) => Food(ref: 'custom:$id', name: 'Mijn brood', source: FoodSource.custom, per100g: const {'energy': 250});
    expect(groupFoods([own('a'), own('b')]), hasLength(2));
  });
}
