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

  test('gewone keuze: wit brood met sneetje, halfvolle melk, gewone kaas, geen fastfoodkip', () {
    expect(box('bread').name.toLowerCase(), isNot(matches(RegExp(r'pitt?a|bagel|panini'))));
    expect(quick('bread').name.toLowerCase(), contains('bread'));
    expect(quick('milk').name.toLowerCase(), contains('semi-skimmed'));
    expect(quick('cheese').name.toLowerCase(), matches(RegExp(r'gouda|cheddar|edam|emmenta')));
    for (final f in [box('chicken'), quick('chicken')]) {
      expect(f.name.toLowerCase(), isNot(contains('fast food')));
    }
  });

  test('crisps zijn chips, geen knäckebröd', () {
    for (final f in [box('crisps'), quick('crisps')]) {
      expect(f.name.toLowerCase(), contains('crisps'), reason: f.name);
      expect(f.name.toLowerCase(), isNot(contains('crispbread')));
    }
  });

  test('gewone Engelse woorden: het basisproduct, in het zoekvak en bij Snel loggen (N15)', () {
    final want = {
      'fries': RegExp(r'^french fries'),
      'spaghetti': RegExp(r'spaghetti.*(boiled|cooked)'),
      'baked beans': RegExp(r'baked beans|beans, baked'),
      'protein bar': RegExp(r'protein.*bar|bar.*protein'),
      'flour': RegExp(r'wheat.*flour|flour.*wheat'),
      // Eén tikfout
      'porrige': RegExp(r'porridge'),
      'spagetti': RegExp(r'spaghetti.*(boiled|cooked)'),
    };
    final other = RegExp(r'\b(egg|fish|cod|spinach|squash|bolognese|pork|sausages?|beef|franks|rye|corn|fast food)\b');
    for (final MapEntry(key: q, value: re) in want.entries) {
      for (final f in [box(q), quick(q)]) {
        expect(f.name.toLowerCase(), allOf(matches(re), isNot(matches(other))), reason: '$q: ${f.name}');
      }
    }
    // "fries" vindt geen gebakken ei of vis vóór de frietjes, "protein bar" geen pap "milk protein free"
    expect(groupFoods(s.searchLocal('fries')).take(3).map((g) => g.main.name.toLowerCase()), everyElement(contains('french fries')));
    expect(s.searchLocal('protein bar').map((f) => f.name.toLowerCase()), everyElement(isNot(contains('protein free'))));
    // Een Nederlands woord blijft gewoon vertaald, geen "tikfout"
    expect(box('appel').name.toLowerCase(), contains('apple'));
  });
}
