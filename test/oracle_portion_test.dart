import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/state/app_state.dart';

/// N36: Orakel per portie rekent met gewone porties (gedroogd fruit ±30 g) en toont elk product maar één keer.
void main() {
  late AppState s;
  setUp(() => s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  ));

  test('vitamine C per portie: geen 100 g gedroogd fruit, geen dubbels', () {
    for (final every in [true, false]) {
      final r = s.oracle('vit_c', rank: OracleRank.perPortion, limit: 25, everyday: every);
      expect(r, isNotEmpty);
      final keys = [for (final (f, _) in r) sameProductKey(f)];
      expect(keys.toSet().length, keys.length, reason: 'dubbels: $keys');
      for (final (f, _) in r) {
        final g = AppState.oraclePortion(f);
        if (f.label?.group == 'fruit' && (f.label?.state == 'dried' || f.name.toLowerCase().contains('dried'))) {
          expect(g, lessThanOrEqualTo(40), reason: f.name);
        }
        expect(g, inInclusiveRange(1, 400), reason: f.name);
      }
    }
  });
}
