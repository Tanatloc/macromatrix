import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/nutrition/processing.dart';

void main() {
  final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  Nova? first(String q) => novaOf(db.search(q, limit: 1).first);

  test('database foods get a sensible NOVA group', () {
    expect(first('banana'), Nova.unprocessed);
    expect(first('oats'), Nova.unprocessed);
    expect(first('butter'), Nova.culinary);
    expect(first('gouda'), Nova.processed);
    expect(first('cola'), Nova.ultra);
    expect(first('sausage'), Nova.ultra);
    expect(first('fish fingers'), Nova.ultra);
    expect(first('margarine'), Nova.ultra);
  });

  test('label from Open Food Facts wins, unknown stays unknown', () {
    const f = Food(ref: 'off:1', name: 'Granola', source: FoodSource.off, per100g: {}, nova: 4);
    expect(novaOf(f), Nova.ultra);
    expect(novaOf(const Food(ref: 'off:2', name: 'Something', source: FoodSource.off, per100g: {})), isNull);
  });

  test('recipe takes the heaviest group that matters', () {
    expect(novaOfRecipe([(Nova.unprocessed, 400), (Nova.culinary, 200), (Nova.ultra, 30)]), Nova.unprocessed);
    expect(novaOfRecipe([(Nova.unprocessed, 300), (Nova.ultra, 300)]), Nova.ultra);
    expect(novaOfRecipe([(null, 500), (Nova.unprocessed, 100)]), isNull);
  });

  test('share of energy', () {
    final s = ProcessingShare.of([(Nova.unprocessed, 600), (Nova.ultra, 400), (null, 50)]);
    expect(s.share(Nova.ultra), closeTo(0.4, 1e-9));
    expect(s.meaningful, isTrue);
    expect(ProcessingShare.of([(Nova.ultra, 50)]).meaningful, isFalse);
  });
}
