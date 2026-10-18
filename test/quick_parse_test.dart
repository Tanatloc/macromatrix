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
}
