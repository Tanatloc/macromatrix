import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/state/app_state.dart';

/// Rijkste bronnen bij een voedingsstof: per portie en alleen gewone voedingsmiddelen, met de echte databank. Per 100 g
/// stonden gistextract, vleesextract, gedroogde paddenstoelen en Amerikaanse drankpoeders bovenaan.
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  final odd = RegExp(r'extract|marmite|powder|dried|drink|beverage|fortified|spice', caseSensitive: false);

  test('B3 per portie: geen extracten, poeders, gedroogde paddenstoelen of verrijkte dranken', () {
    final top = s.oracle('b3', rank: OracleRank.perPortion, limit: 12, everyday: true);
    expect(top, isNotEmpty);
    for (final (f, _) in top) {
      expect(odd.hasMatch(f.name), isFalse, reason: f.name);
    }
  });

  test('geroosterde sojabonen of kikkererwten: een knabbelportie zoals noten, geen 120 g', () {
    final roasted = s.foods
        .search('soybeans roasted', limit: 20)
        .where((f) => f.label?.group == 'legume' && f.name.toLowerCase().contains('roasted'));
    expect(roasted, isNotEmpty);
    for (final f in roasted) {
      expect(adviceServing(f).$1, 30, reason: f.name);
    }
  });
}
