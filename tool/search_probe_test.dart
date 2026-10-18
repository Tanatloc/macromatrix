// ignore_for_file: avoid_print
// Toont de eerste zoekresultaten voor een paar woorden: flutter test tool/search_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';

void main() {
  test('zoekresultaten', () {
    final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    for (final q in ['banaan', 'zalm', 'spinazie', 'ei', 'havermout', 'melk', 'kipfilet', 'brood', 'appel', 'linzen']) {
      print('── $q');
      for (final f in db.search(q, limit: 6)) {
        print('   ${f.source.label.padRight(16)} ${f.name}  [${f.per100g.length}]');
      }
    }
  });
}
