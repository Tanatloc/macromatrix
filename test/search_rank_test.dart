import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/state/app_state.dart';

/// Zoekvak en Snel loggen rangschikken hetzelfde (P152): het gewone, bereide product bovenaan.
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  Food box(String q) => groupFoods(s.searchLocal(q)).first.main;
  Food quick(String q) => s.resolveQuick(QuickItem(q)).first.$1;

  test('rijst, pasta en linzen: gekookt, in het zoekvak en bij Snel loggen', () {
    for (final q in ['rice', 'rijst', 'gekookte rijst', 'pasta', 'lentils']) {
      for (final f in [box(q), quick(q)]) {
        expect(f.name.toLowerCase(), matches(RegExp(r'cooked|boiled')), reason: '$q: ${f.name}');
      }
    }
  });

  test('geen gehakt, diepvries, lactosevrij of energiedrank tenzij gevraagd', () {
    expect(box('chicken').name.toLowerCase(), isNot(contains('mince')));
    expect(box('kip').name.toLowerCase(), isNot(contains('raw')));
    expect(box('halfvolle melk').name.toLowerCase(), allOf(contains('semi-skimmed'), isNot(contains('lactose'))));
    expect(quick('halfvolle melk').name.toLowerCase(), allOf(contains('semi-skimmed'), isNot(contains('lactose'))));
    for (final f in [...s.searchLocal('cola zero'), ...s.resolveQuick(const QuickItem('cola zero')).map((o) => o.$1)]) {
      expect(f.name.toLowerCase(), isNot(contains('energy drink')));
    }
    expect(box('cola zero').name.toLowerCase(), contains('cola'));
  });

  test('Coca-Cola of coke: gewone cola met suiker, geen zoetstof of pina colada', () {
    for (final q in ['Coca-Cola', 'coca cola', 'coke', 'pepsi']) {
      for (final f in [box(q), quick(q)]) {
        final n = f.name.toLowerCase();
        expect(n, contains('cola'), reason: '$q: ${f.name}');
        expect(n, isNot(matches(RegExp(r'sweetener|diet|colada|without added'))), reason: '$q: ${f.name}');
        expect(f.per100g['energy']!, greaterThan(30), reason: '$q: ${f.name}');
      }
    }
  });

  test('griekse yoghurt: gewone Griekse yoghurt, geen smaakje of merk', () {
    for (final f in [box('griekse yoghurt'), quick('griekse yoghurt')]) {
      expect(f.name, contains('Greek'), reason: f.name);
      expect(f.name.toLowerCase(), isNot(matches(RegExp(r'strawberry|fruit|chobani'))), reason: f.name);
    }
  });

  test('Snel loggen: geen dubbele naam uit dezelfde bron', () {
    for (final q in ['banana', 'milk', 'egg']) {
      final keys = [for (final o in s.resolveQuick(QuickItem(q))) '${o.$1.name.toLowerCase()}|${o.$1.source}'];
      expect(keys.toSet().length, keys.length, reason: q);
    }
  });

  test('groep: de gewone vorm vooraan, geen diepvries-ei', () {
    for (final g in groupFoods(s.searchLocal('egg'))) {
      if (g.others.any((f) => !f.name.toLowerCase().contains('frozen'))) {
        expect(g.main.name.toLowerCase(), isNot(contains('frozen')), reason: g.main.name);
      }
    }
  });

  test('recent: ook met de enige regel gewist blijft het product terug te vinden (P64)', () {
    final db = UserDb(sqlite3.openInMemory());
    const food = Food(ref: 'ciqual:1', name: 'Test', source: FoodSource.ciqual, per100g: {'energy': 200});
    final id = db.addEntry(day: '2026-10-14', meal: Meal.breakfast, food: food, grams: 80, quantity: 80);
    db.deleteEntry(id);
    expect(db.recent(), isEmpty);
    expect(db.recent(withDeleted: true).single.grams, 80);
  });
}
