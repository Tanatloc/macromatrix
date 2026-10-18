import 'package:flutter_test/flutter_test.dart';
import 'package:voedingsapp/data/food.dart';
import 'package:voedingsapp/nutrition/allergens.dart';

Food f(String name) => Food(ref: 'x:$name', name: name, source: FoodSource.ciqual, per100g: const {});

void main() {
  const pinda = {Allergen.peanuts};
  test('pinda op naam, alleen wat je aanduidde', () {
    expect(containsAllergen(f('Peanut butter, smooth'), pinda), isTrue);
    expect(containsAllergen(f('Pindakaas'), pinda), isTrue);
    expect(containsAllergen(f('Almonds, raw'), pinda), isFalse, reason: 'noten zijn een ander allergeen');
    expect(containsAllergen(f('Almonds, raw'), {Allergen.nuts}), isTrue);
    expect(containsAllergen(f('Nutmeg, ground'), {Allergen.nuts}), isFalse);
    expect(containsAllergen(f('Almond milk'), {Allergen.milk}), isFalse, reason: 'plantaardige melk is geen zuivel');
  });

  test('etiket: bevat, sporen en ingrediënten', () {
    final bar = allergenHits(
      pinda,
      name: 'Chocolate bar',
      label: const LabelInfo(allergens: ['en:milk'], traces: ['en:peanuts']),
    );
    expect(bar.single.level, AllergenLevel.traces);
    final cookie = allergenHits(
      pinda,
      name: 'Koekjes',
      label: const LabelInfo(ingredients: 'tarwebloem, suiker, 12% pinda\'s, zout'),
    );
    expect(cookie.single.level, AllergenLevel.contains);
    expect(
      allergenHits(
        pinda,
        name: 'Rijstwafels',
        label: const LabelInfo(ingredients: 'volkoren rijst, zout'),
      ),
      isEmpty,
    );
    expect(allergenHits(const {}, name: 'Peanuts'), isEmpty);
  });
}
