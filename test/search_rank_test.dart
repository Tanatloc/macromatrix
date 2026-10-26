import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/free_sugars.dart';
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
  test('muesli is muesli, geen granola, in elke spelling', () {
    for (final q in ['muesli', 'müsli', 'musli', 'Muesli']) {
      for (final f in [box(q), quick(q)]) {
        final n = f.name.toLowerCase();
        expect(n, allOf(matches(RegExp(r'm(ue|ü|u)sli')), isNot(matches(RegExp(r'granola|\bbar\b|bread|yog')))), reason: '$q: ${f.name}');
      }
    }
    // Geen mossel ("musling" in het Deens)
    expect(s.searchLocal('musli').map((f) => f.name.toLowerCase()), everyElement(isNot(contains('mussel'))));
  });

  test('een suikerwens is geen voedingsmiddel: muesli zonder suiker, nooit suiker of kauwgom', () {
    for (final q in [
      'sugar free muesli',
      'sugar-free muesli',
      'muesli no added sugar',
      'muesli no added sugars',
      'muesli without sugar',
      'muesli without added sugar',
      'muesli with no added sugar',
      'unsweetened muesli',
      'muesli zonder suiker',
      'muesli zonder toegevoegde suiker',
      'suikervrije muesli',
      'ongezoete müsli',
    ]) {
      for (final f in [box(q), quick(q)]) {
        expect(f.name.toLowerCase(), matches(RegExp(r'm(ue|ü|u)sli')), reason: '$q: ${f.name}');
        expect(noAddedSugarName.hasMatch(f.name), isTrue, reason: '$q: ${f.name}');
      }
    }
    // Minder suiker: er is geen muesli "reduced sugar", dan die zonder toegevoegde suiker (en nooit granola)
    for (final q in ['low sugar muesli', 'reduced sugar muesli', 'muesli minder suiker']) {
      for (final f in [box(q), quick(q)]) {
        expect(f.name.toLowerCase(), allOf(matches(RegExp(r'm(ue|ü|u)sli')), isNot(contains('granola'))), reason: '$q: ${f.name}');
        expect(noAddedSugarName.hasMatch(f.name) || lowSugarName.hasMatch(f.name), isTrue, reason: '$q: ${f.name}');
      }
    }
    expect(parseQuick('50 g muesli with no added sugar').single.query, 'muesli with no added sugar');
  });

  test('suikerwens bij andere producten: de variant als die bestaat, anders het gewone product', () {
    final want = {
      'sugar free jam': (RegExp(r'\bjam\b'), noAddedSugarName),
      'jam zonder suiker': (RegExp(r'\bjam\b'), noAddedSugarName),
      'reduced sugar jam': (RegExp(r'\bjam\b'), lowSugarName),
      'low sugar ketchup': (RegExp(r'ketchup'), lowSugarName),
      'almond milk unsweetened': (RegExp(r'almond milk'), noAddedSugarName),
      'unsweetened almond milk': (RegExp(r'almond milk'), noAddedSugarName),
      'sugar free cola': (RegExp(r'\bcola\b'), noAddedSugarName),
      'sugar free chewing gum': (RegExp(r'chewing gum'), noAddedSugarName),
    };
    for (final MapEntry(key: q, value: (food, form)) in want.entries) {
      for (final f in [box(q), quick(q)]) {
        expect(f.name.toLowerCase(), matches(food), reason: '$q: ${f.name}');
        expect(form.hasMatch(f.name), isTrue, reason: '$q: ${f.name}');
      }
    }
    // Geen ongezoete gewone yoghurt of pindakaas zonder suiker in de databank: dan de gewone, geen fruityoghurt of koekje
    for (final q in ['unsweetened yoghurt', 'unsweetened yogurt', 'ongezoete yoghurt', 'yoghurt no added sugar']) {
      for (final f in [box(q), quick(q)]) {
        expect(
          f.name.toLowerCase(),
          allOf(matches(RegExp(r'yog(h)?urt.*plain|plain.*yog(h)?urt')), isNot(matches(RegExp(r'fruit|vanilla')))),
          reason: '$q: ${f.name}',
        );
      }
    }
    // Pindakaas: sinds FNDDS (26-10-2026) bestaat er een variant met minder suiker, en die is de dichtste bij de wens
    for (final f in [box('peanut butter no added sugar'), quick('peanut butter no added sugar')]) {
      expect(
        f.name.toLowerCase(),
        allOf(startsWith('peanut butter'), isNot(matches(RegExp(r'cookie'))), anyOf(isNot(contains('sugar')), contains('lower sugar'))),
        reason: f.name,
      );
    }
    // Alleen de suikerwens, of gewoon suiker: geen woorden om weg te laten
    expect(splitSugarAsk('sugar free'), ('sugar free', null));
    expect(splitSugarAsk('brown sugar'), ('brown sugar', null));
    expect(box('sugar').name.toLowerCase(), startsWith('sugar'));
    expect(box('sugar free').name.toLowerCase(), contains('sugar free'));
  });

  test('ml weegt in Snel loggen zoals op het productscherm (melk 1,03 g per ml), en hoofdletters tellen niet', () {
    final (milk, grams, _) = s.resolveQuick(const QuickItem('semi-skimmed milk', grams: 200, ml: 200)).first;
    expect(milk.name.toLowerCase(), contains('milk'));
    expect(grams, closeTo(206, 0.01));
    expect(s.resolveQuick(const QuickItem('Fried ham')).first.$1.name, s.resolveQuick(const QuickItem('fried ham')).first.$1.name);
    expect(s.resolveQuick(const QuickItem('fried sausages')).first.$1.name.toLowerCase(), startsWith('sausage'));
  });

  test('hernoemde voedingsmiddelen zijn vindbaar op hun nieuwe naam', () {
    expect(box('french fries').name.toLowerCase(), contains('french fries'));
    expect(box('oat flour').name.toLowerCase(), contains('oat flour'));
  });
}
