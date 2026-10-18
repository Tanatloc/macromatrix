import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/fdc_client.dart';
import 'package:macromatrix/data/off_client.dart';
import 'package:macromatrix/data/product_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('herkomst: productieplaats gaat voor barcodeland', () {
    expect(const ProductInfo(code: '5449000000996', name: 'x', madeIn: ['en:belgium']).origin.region, Region.eu);
    expect(const ProductInfo(code: '5449000000996', name: 'x', madeIn: ['en:united-states']).origin.region, Region.us);
    final bc = const ProductInfo(code: '5449000000996', name: 'x').origin;
    expect((bc.region, bc.basis), (Region.eu, 'barcode'));
    expect(const ProductInfo(code: '016000275287', name: 'x').origin.region, Region.us);
    expect(const ProductInfo(code: '4901234567894', name: 'x').origin.region, Region.other);
    expect(const ProductInfo(code: '2000000000008', name: 'x').origin.region, Region.unknown);
    expect(const ProductInfo(code: '00016000275287', name: 'x', source: 'usda').origin.region, Region.us);
  });

  test('productscore: Nutri-Score, additieven, hoog risico max 49', () async {
    final c = await AdditiveCatalog.load();
    expect(c.lookup('en:e330')!.level, AdditiveLevel.free);
    expect(c.lookup('en:e172')!.level, AdditiveLevel.limited);
    expect(const ProductInfo(code: '1', name: 'x', nutriscore: 'a').score(c), 90);
    expect(const ProductInfo(code: '1', name: 'x', nutriscore: 'a', organic: true).score(c), 100);
    expect(const ProductInfo(code: '1', name: 'x').score(c), isNull);
    expect(const ProductInfo(code: '1', name: 'x', additiveTags: ['en:e322', 'en:e322i', 'en:e150d']).additives(c).map((a) => a.code), [
      'e322',
      'e150d',
    ]);
    final high = c.lookup('en:e250')!;
    expect(high.risk, AdditiveRisk.high);
    expect(const ProductInfo(code: '1', name: 'x', nutriscore: 'a', additiveTags: ['en:e250']).score(c)! <= 49, isTrue);
  });

  test('USDA: voedingswaarden per 100 g, koolhydraten zonder vezels', () {
    final p = productFromFdc({
      'found': true,
      'code': '00016000275287',
      'name': 'CHEERIOS CEREAL',
      'brand': 'General Mills',
      'serving': 28.0,
      'servingUnit': 'GRM',
      'household': '1 cup',
      'nutrients': [
        [1008, 'KCAL', 359],
        [1003, 'G', 12.8],
        [1005, 'G', 74.4],
        [1079, 'G', 10.3],
        [1093, 'MG', 487],
        [1106, 'UG', 193],
        [1110, 'IU', 400],
      ],
    })!;
    expect(p.name, 'Cheerios cereal');
    expect(p.source, 'usda');
    final f = p.food!;
    expect(f.ref, 'fdc:00016000275287');
    expect(f.per100g['energy'], 359);
    expect(f.per100g['carbs'], closeTo(64.1, 0.01));
    expect(f.per100g['vit_d'], 10);
    expect(f.portions.single.grams, 28);
    expect(productFromFdc({'found': false}), isNull);
  });

  test('energie: kJ in het kcal-veld wordt verbeterd', () {
    expect(checkEnergy(947, protein: 20, carbs: 0.9, fat: 16)!, closeTo(226, 1));
    expect(checkEnergy(226, protein: 20, carbs: 0.9, fat: 16), isNull);
    expect(checkEnergy(42, protein: 0, carbs: 10.6, fat: 0), isNull);
  });
}
