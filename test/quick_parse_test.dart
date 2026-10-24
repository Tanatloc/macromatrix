import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';

void main() {
  test('Engels: gram, kom, stuks', () {
    final r = parseQuick('200 g chicken and a bowl of rice, 2 eggs');
    expect(r.map((x) => x.query), ['chicken', 'rice', 'eggs']);
    expect(r[0].grams, 200);
    expect((r[1].count, r[1].unitGrams), (1, 250));
    expect(r[2].count, 2);
  });

  test('Nederlands: eenheden en getallen in woorden', () {
    final r = parseQuick('twee sneetjes volkoren brood met 30 gram kaas en een glas melk.');
    expect(r.map((x) => x.query), ['volkoren brood', 'kaas', 'melk']);
    expect((r[0].count, r[0].unitGrams), (2, 35));
    expect(r[1].grams, 30);
    expect((r[2].count, r[2].unitGrams), (1, 200));
  });

  test('kg, decimale komma en alleen een naam', () {
    final r = parseQuick('0,5 kg potatoes; banana');
    expect(r[0].grams, 500);
    expect(r[1].query, 'banana');
    expect(r[1].grams, isNull);
    expect(r[1].count, isNull);
  });

  test('ingesproken zonder komma\'s: splitsen bij elke hoeveelheid', () {
    final r = parseQuick('100 gram chicken 100 g bacon two pieces of breads a apple a pineapple and a glass of milk');
    expect(r.map((x) => x.query), ['chicken', 'bacon', 'breads', 'apple', 'pineapple', 'milk']);
    expect(r[0].grams, 100);
    expect(r[1].grams, 100);
    expect(r[2].count, 2);
    expect((r[5].count, r[5].unitGrams), (1, 200));
    final nl = parseQuick('200 gram kip twee eieren een kom yoghurt');
    expect(nl.map((x) => x.query), ['kip', 'eieren', 'yoghurt']);
    expect(parseQuick('half a banana').single.count, 0.5);
  });

  test('pint, rasher, halve pizza en een eenheid zonder product (N65)', () {
    final pint = parseQuick('a pint of lager').single;
    expect((pint.query, pint.unitGrams, pint.unit), ('lager', 568, 'pint'));
    final half = parseQuick('half a pint of cider').single;
    expect((half.query, half.count! * half.unitGrams!), ('cider', 284));
    expect(parseQuick('een pint').single.query, 'beer');
    final bacon = parseQuick('2 rashers of bacon').single;
    expect((bacon.query, bacon.count, bacon.unitGrams), ('bacon', 2, 25));
    final pizza = parseQuick('een halve pizza').single;
    expect((pizza.query, pizza.count), ('pizza', 0.5));
  });

  test('0 eieren geeft geen regel; "met" onthoudt het product ervoor', () {
    expect(parseQuick('0 eggs and 0 g butter'), isEmpty);
    final r = parseQuick('two slices of bread with ham, coffee met melk');
    expect(r.map((x) => x.query), ['bread', 'ham', 'coffee', 'melk']);
    expect((r[1].after, r[1].afterCount), ('bread', 2));
    expect(r[2].after, isNull);
    expect(r[3].after, 'coffee');
  });
}
