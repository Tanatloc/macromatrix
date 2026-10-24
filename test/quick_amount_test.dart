import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/state/app_state.dart';

/// Snel loggen: gewone hoeveelheden in plaats van 100 g per stuk (N10, N65).
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  List<(String, double)> log(String text) => [
    for (final q in parseQuick(text))
      if (s.resolveQuick(q).firstOrNull case final o?) (o.$1.name.toLowerCase(), o.$2),
  ];

  test('pint 568 ml, halve pint 284, rasher 25 g', () {
    expect(log('a pint of lager').single.$2, 568);
    expect(log('half a pint of cider').single.$2, 284);
    expect(log('2 rashers of bacon').single.$2, 50);
  });

  test('pizza: een punt 100 g, een halve 200 g', () {
    expect(log('a slice of pizza').single.$2, 100);
    expect(log('half a pizza').single.$2, 200);
    expect(log('een halve pizza').single.$2, 200);
  });

  test('kroketten zijn aardappelkroketten van ≈35 g', () {
    final (name, grams) = log('6 kroketten').single;
    expect(name, contains('potato'));
    expect(grams, 210);
  });

  test('beleg op een boterham en melk in de koffie', () {
    final r = log('two slices of bread with ham');
    expect(r[0].$2, 70);
    expect(r[1].$2, 40);
    expect(log('a slice of ham').single.$2, 20);
    expect(log('coffee with milk')[1].$2, 30);
  });

  test('melk blijft halfvolle melk, koffie een mok', () {
    expect(log('a glass of milk').single.$1, contains('semi-skimmed'));
    expect(log('coffee').single.$2, 250);
  });

  test('zelfde basisproduct als het zoekvak', () {
    for (final q in ['egg', 'banana', 'pasta', 'beer']) {
      expect(s.resolveQuick(QuickItem(q)).first.$1.ref, groupFoods(s.searchLocal(q)).first.main.ref, reason: q);
    }
  });
}
