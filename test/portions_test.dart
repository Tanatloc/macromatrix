import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/nutrition/portions.dart';

Food _food(String name, {String? group, String part = 'product', List<Portion> portions = const []}) => Food(
  ref: 'ciqual:${name.hashCode}',
  name: name,
  source: FoodSource.ciqual,
  per100g: const {'energy': 100},
  portions: portions,
  label: group == null ? null : FoodLabel(food: name, group: group, part: part, kind: 'plant', state: 'not applicable'),
);

List<String> _labels(Food f) => [for (final p in everydayPortions(f)) p.label];

void main() {
  group('gewone porties (P19)', () {
    test('brood krijgt een sneetje, als schatting', () {
      final p = everydayPortions(_food('Bread, wholemeal', group: 'bread'));
      expect(p.single.short, '1 slice');
      expect(p.single.label, '1 slice (≈35 g)');
      expect(p.single.grams, 35);
      // Ook zonder label, op naam
      expect(_labels(_food('Sourdough bread')), ['1 slice (≈35 g)']);
      // Een broodje is een stuk, geen sneetje
      expect(_labels(_food('Bread roll, white')), ['1 piece (≈60 g)']);
    });

    test('dranken: glas, wijn kleiner, koffie een mok', () {
      expect(_labels(_food('Milk, semi-skimmed', group: 'dairy', part: 'drink')), ['1 glass (≈200 ml)']);
      expect(_labels(_food('Milk, semi-skimmed')), ['1 glass (≈200 ml)']);
      expect(_labels(_food('Orange juice', group: 'beverage', part: 'juice')), ['1 glass (≈200 ml)']);
      expect(everydayPortions(_food('Red wine', group: 'alcohol', part: 'drink')).single.grams, 150);
      expect(_labels(_food('Coffee, brewed', group: 'beverage', part: 'drink')), ['1 mug (≈250 ml)']);
      // Melkpoeder en melkchocolade zijn geen drank
      expect(_labels(_food('Milk powder', group: 'dairy', part: 'powder')), isEmpty);
      expect(_labels(_food('Milk chocolate')), isEmpty);
    });

    test('kom, stuk, schep en lepels', () {
      expect(_labels(_food('Yoghurt, plain', group: 'dairy')), ['1 bowl (≈150 g)']);
      expect(everydayPortions(_food('Muesli', group: 'breakfast cereal')).single.grams, 40);
      expect(everydayPortions(_food('Banana, raw', group: 'fruit')).single.grams, 120);
      expect(everydayPortions(_food('Egg, whole, raw', group: 'egg')).single.short, '1 piece');
      expect(_labels(_food('Whey protein powder', group: 'supplement', part: 'powder')), ['1 scoop (≈30 g)']);
      expect([for (final p in everydayPortions(_food('Butter', group: 'oil/fat'))) p.grams], [10, 5, 15]);
      // Olie smeer je niet op een boterham
      expect([for (final p in everydayPortions(_food('Olive oil', group: 'oil/fat', part: 'oil'))) p.grams], [5, 15]);
      // Eiernoedels zijn geen ei, appelmoes geen appel
      expect(_labels(_food('Egg noodles, cooked', group: 'pasta')), isEmpty);
      expect(_labels(_food('Apple puree', group: 'fruit', part: 'puree')), isEmpty);
    });

    test('geen dubbele portie als de databank er al een heeft', () {
      final bread = _food('Bread, white', group: 'bread', portions: const [Portion('1 slice', 28)]);
      expect(everydayPortions(bread), isEmpty);
      expect(portionOptions(bread).map((p) => p.label), ['1 slice']);
      final milk = _food('Milk, whole', group: 'dairy', part: 'drink', portions: const [Portion('1 cup', 244)]);
      expect(everydayPortions(milk), isEmpty);
      final butter = _food('Butter', group: 'oil/fat', portions: const [Portion('1 tbsp', 14)]);
      expect(_labels(butter), ['on 1 slice (≈10 g)', '1 teaspoon (≈5 g)']);
    });

    test('hoogstens 6 knoppen, schattingen na de databankporties', () {
      final many = _food('Butter', group: 'oil/fat', portions: [for (var i = 1; i <= 8; i++) Portion('$i pat', i * 5.0)]);
      final options = portionOptions(many);
      expect(options, hasLength(6));
      expect(options.take(3).map((p) => p.label), ['1 pat', '2 pat', '3 pat']);
      expect(options.skip(3).every((p) => p is EverydayPortion), isTrue);
    });

    test('chips en andere snacks: een zakje, nooit een stuk van 150 g (N11)', () {
      expect(_labels(_food('Potato crisps', group: 'snack')), ['1 small bag (≈25 g)', '1 bag (≈32 g)']);
      expect(everydayPortions(_food('Tortilla chips fried in sunflower oil', group: 'snack')).first.grams, 25);
      expect(everydayPortions(_food('Popcorn, salted, retail', group: 'snack')).first.short, '1 small bag');
      expect(everydayPortions(_food('Ready salted crisps')).first.grams, 25);
      // Rijstwafels en crackers blijven per stuk; Britse "chips" zijn friet, geen zakje
      expect(everydayPortions(_food('Rice cake', group: 'snack')).first.short, isNot(contains('bag')));
      expect(_labels(_food('Chips, oven, frozen')), isEmpty);
    });

    test('soep een kom, taart een stuk, havermout een kom en een eetlepel (N33, N43)', () {
      expect(_labels(_food('Soup, lentil, homemade', group: 'soup')), ['1 bowl (≈250 g)']);
      expect(_labels(_food('Soup, tomato, dried', group: 'soup', part: 'powder')), isEmpty);
      expect(_labels(_food('Cake, carrot, iced, retail', group: 'bakery')), ['1 slice (≈75 g)']);
      expect(_labels(_food('Pancakes', group: 'bakery')), isNot(contains('1 slice (≈75 g)')));
      expect(_labels(_food('Oats, rolled, average values', group: 'cereal')), ['1 bowl (≈40 g)', '1 tablespoon (≈10 g)']);
      expect(_labels(_food('Oat flakes, boiled/cooked in water', group: 'cereal')), ['1 bowl (≈250 g)']);
    });

    test('bloem een eetlepel, kokosmelk een lepel of blik, bier ook een pint, pizza een punt (N84, N48)', () {
      expect(_labels(_food('Wheat flour', group: 'cereal', part: 'flour')), ['1 tablespoon (≈10 g)']);
      expect(_labels(_food('Plain flour')), ['1 tablespoon (≈10 g)']);
      expect(_labels(_food('Coconut milk', group: 'beverage', part: 'drink')), ['1 tablespoon (≈15 ml)', '1 can (≈400 ml)']);
      expect(_labels(_food('Lager, standard', group: 'alcohol', part: 'drink')), ['1 glass (≈250 ml)', '1 pint (≈568 ml)']);
      expect(_labels(_food('Pizza, cheese and tomato, retail', group: 'dish')), ['1 slice (≈100 g)', '1 pizza (≈400 g)']);
      expect(_labels(_food('Pizza sauce')), isEmpty);
    });

    test('dranken in ml, de rest in gram (N85)', () {
      expect(isDrink(_food('Milk, whole', group: 'dairy', part: 'drink')), isTrue);
      expect(isDrink(_food('Water, tap water', group: 'beverage', part: 'drink')), isTrue);
      expect(isDrink(_food('Orange juice')), isTrue);
      expect(isDrink(_food('Milk powder', group: 'dairy', part: 'powder')), isFalse);
      expect(isDrink(_food('Yoghurt, plain', group: 'dairy')), isFalse);
    });

    test('stukgewicht blijft hetzelfde voor Snel loggen', () {
      expect(typicalPieceGrams('apple'), 150);
      expect(typicalPieceGrams('protein powder'), 30);
      expect(typicalPieceGrams('lasagne'), isNull);
    });
  });

  group('stappen van plus en min (P19)', () {
    double up(double q, {bool portion = false}) => stepQuantity(q, up: true, portion: portion);
    double down(double q, {bool portion = false}) => stepQuantity(q, up: false, portion: portion);

    test('gram: per 10 onder 100, daarboven per 25, altijd rond', () {
      expect(up(40), 50);
      expect(up(95), 100);
      expect(up(100), 125);
      expect(up(110), 125);
      expect(up(125), 150);
      expect(down(150), 125);
      expect(down(110), 100);
      expect(down(100), 90);
      expect(down(37), 30);
      expect(down(5), 0);
      expect(down(0), 0);
    });

    test('porties (stuks, recepten): per 1, alleen onder 1 per halve (N32)', () {
      expect(up(1, portion: true), 2);
      expect(up(1.5, portion: true), 2);
      expect(up(2, portion: true), 3);
      expect(up(2.5, portion: true), 3);
      expect(down(3, portion: true), 2);
      expect(down(2, portion: true), 1);
      expect(down(1.5, portion: true), 1);
      expect(down(1, portion: true), 0.5);
      expect(up(0.5, portion: true), 1);
      expect(down(0.5, portion: true), 0);
      expect(up(0.3, portion: true), 0.5);
    });
  });
}
