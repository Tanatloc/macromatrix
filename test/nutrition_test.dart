import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/off_client.dart';
import 'package:macromatrix/data/search_terms.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';

void main() {
  group('values', () {
    test('afgeleide totalen', () {
      final n = withDerived({'ala': 1.0, 'epa': 0.2, 'dha': 0.3, 'la': 5.0, 'methionine': 0.5, 'cystine': 0.2});
      expect(n['omega3'], closeTo(1.5, 1e-9));
      expect(n['epa_dha'], closeTo(500, 1e-9)); // mg
      expect(n['omega6'], 5.0);
      expect(n['met_cys'], closeTo(0.7, 1e-9));
      expect(n.containsKey('phe_tyr'), isFalse);
    });

    test('bestaande totalen worden niet overschreven', () {
      expect(withDerived({'omega3': 2.0, 'ala': 1.0})['omega3'], 2.0);
    });

    test('totalen tellen ontbrekende gegevens', () {
      final t = NutrientTotals.sumOf([
        {'energy': 100, 'vit_c': 10},
        {'energy': 50},
      ]);
      expect(t['energy'], 150);
      expect(t['vit_c'], 10);
      expect(t.isComplete('energy'), isTrue);
      expect(t.isComplete('vit_c'), isFalse); // 50 van 150 kcal zonder gegevens
      expect(t.missing['vit_c'], 1);
    });

    test('elke catalogussleutel is uniek', () {
      expect(nutrientByKey.length, nutrients.length);
    });
  });

  group('targets', () {
    test('Mifflin-St Jeor', () {
      // Man, 30 jaar, 80 kg, 180 cm: 10*80 + 6.25*180 - 5*30 + 5 = 1780
      const p = Profile(sex: Sex.male, birthYear: 1996, weightKg: 80, heightCm: 180, activity: Activity.sedentary);
      expect(bmr(p, 30), 1780);
      expect(energyTarget(p, 2026), (1780 * 1.2).roundToDouble());
    });

    test('EFSA-waarden verschillen per geslacht en leeftijd', () {
      final man = targetsFor(const Profile(sex: Sex.male, birthYear: 1990), year: 2026);
      final vrouw = targetsFor(const Profile(sex: Sex.female, birthYear: 1990), year: 2026);
      final vrouw55 = targetsFor(const Profile(sex: Sex.female, birthYear: 1971), year: 2026);
      expect(man['vit_c']!.goal, 110);
      expect(vrouw['vit_c']!.goal, 95);
      expect(vrouw['iron']!.goal, 16);
      expect(vrouw55['iron']!.goal, 11);
      expect(man['sodium']!.isLimit, isTrue);
      expect(man['vit_d']!.upper, 100);
    });

    test('macro\'s volgen de energieverdeling', () {
      const p = Profile(energyOverride: 2000, proteinPct: 25, carbsPct: 45, fatPct: 30);
      final t = targetsFor(p, year: 2026);
      expect(t['protein']!.goal, 125);
      expect(t['carbs']!.goal, 225);
      expect(t['fat']!.goal, closeTo(66.7, 0.1));
    });

    test('profiel heen en terug naar JSON', () {
      const p = Profile(sex: Sex.female, birthYear: 2000, weightKg: 61.5, goal: Goal.lose, energyOverride: 1800);
      final q = Profile.fromJson(p.toJson());
      expect(q.sex, Sex.female);
      expect(q.weightKg, 61.5);
      expect(q.goal, Goal.lose);
      expect(q.energyOverride, 1800);
    });
  });

  group('Open Food Facts', () {
    test('eenheden worden omgerekend (OFF bewaart in gram)', () {
      final n = mapOffNutriments({
        'energy-kcal_100g': 380,
        'proteins_100g': 7.5,
        'iron_100g': 0.0021, // 2,1 mg
        'vitamin-d_100g': 0.0000042, // 4,2 µg
        'vitamin-c_100g': 0.012, // 12 mg
        'salt_100g': 1.0, // 400 mg natrium
      });
      expect(n['energy'], 380);
      expect(n['iron'], closeTo(2.1, 1e-9));
      expect(n['vit_d'], closeTo(4.2, 1e-9));
      expect(n['vit_c'], closeTo(12, 1e-9));
      expect(n['sodium'], closeTo(400, 1e-9));
    });

    test('energie uit kJ als kcal ontbreekt', () {
      expect(mapOffNutriments({'energy-kj_100g': 418.4})['energy'], closeTo(100, 1e-9));
    });

    test('product zonder energie wordt overgeslagen', () {
      expect(
        foodFromOff({
          'code': '123',
          'product_name': 'X',
          'nutriments': {'proteins_100g': 1},
        }),
        isNull,
      );
    });

    test('portie uit serving_quantity', () {
      final f = foodFromOff({
        'code': '5410000000000',
        'product_name': 'Muesli',
        'brands': 'Merk A, Merk B',
        'serving_quantity': 45,
        'serving_size': '45 g',
        'nutriments': {'energy-kcal_100g': 400},
      })!;
      expect(f.ref, 'off:5410000000000');
      expect(f.brand, 'Merk A');
      expect(f.portions.single.grams, 45);
    });

    test('barcodeherkenning', () {
      expect(looksLikeBarcode('5410000000000'), isTrue);
      expect(looksLikeBarcode('96385074'), isTrue);
      expect(looksLikeBarcode('12345'), isFalse);
      expect(looksLikeBarcode('banaan'), isFalse);
    });
  });

  group('zoeken', () {
    test('Nederlandse woorden worden vertaald', () {
      expect(searchTokens('banaan'), ['banana']);
      expect(searchTokens('zoete aardappel gekookt'), containsAll(['sweet', 'potato', 'cooked']));
      expect(searchTokens('quinoa'), ['quinoa']);
    });

    final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    test('de basisvorm komt eerst, uit een Europese bron', () {
      final banaan = db.search('banaan').first;
      expect(banaan.name.toLowerCase(), startsWith('banana'));
      expect(banaan.name, contains('raw'));
      expect(banaan.source.european, isTrue);
      expect(db.search('ei').first.name.toLowerCase(), startsWith('egg'));
      expect(db.search('spinazie').first.name.toLowerCase(), startsWith('spinach'));
    });

    test('verwijzingen blijven geldig na het opnieuw bouwen', () {
      final f = db.search('banaan').first;
      expect(db.byRef(f.ref)?.name, f.name);
      expect(f.ref, matches(RegExp(r'^(ciqual|slv|mvt|usda_sr|usda_fnd):')));
    });

    test('ontbrekende waarden aangevuld uit een andere databank, gemarkeerd als schatting', () {
      final banaan = db.byRef(db.search('banaan').firstWhere((f) => f.source == FoodSource.slv).ref)!;
      expect(banaan.estimated, isNotEmpty);
      for (final MapEntry(:key, value: donor) in banaan.estimated.entries) {
        expect(banaan.per100g.containsKey(key), isTrue);
        expect(donor.startsWith('slv:'), isFalse); // nooit uit dezelfde bron
      }
    });

    test('eiwit krijgt geen waarden van een heel ei', () {
      for (final f in db.search('egg white raw')) {
        for (final donor in f.estimated.values) {
          // "~bron:id" = vergelijkbaar product, "~~groep" = gemiddelde van een groep (die moet ook over eiwit gaan)
          if (donor.startsWith('~~')) {
            expect(donor, contains('white'));
          } else {
            expect(db.byRef(donor.replaceFirst(RegExp(r'^~'), ''))!.name.toLowerCase(), contains('white'));
          }
        }
      }
    });

    test('Oracle: rijkste bronnen van een voedingsstof', () {
      final mg = db.richestIn('magnesium', limit: 10);
      expect(mg, hasLength(10));
      expect(mg.first.$2, greaterThanOrEqualTo(mg.last.$2));
      final perKcal = db.richestIn('vit_c', perKcal: true, limit: 5);
      expect(perKcal.first.$1.per100g['energy'], greaterThanOrEqualTo(15));
      expect(db.richestIn('epa_dha', limit: 3).first.$2, greaterThan(1000)); // vette vis of visolie
      expect(db.richestIn("x'; DROP TABLE foods; --"), isEmpty);
    });

    test('elk ei heeft choline, selenium en B12 (ontbreken kan niet)', () {
      final eggs = db.search('egg').where(
        (f) => RegExp(r'^eggs?\b', caseSensitive: false).hasMatch(f.name) &&
            !RegExp(r'white|roll|noodle|salad|sauce|nog|flip|custard', caseSensitive: false).hasMatch(f.name),
      );
      expect(eggs.length, greaterThan(10));
      for (final e in eggs) {
        for (final k in ['choline', 'selenium', 'b12']) {
          expect(e.per100g[k], greaterThan(0), reason: '${e.name} ($k)');
        }
      }
    });

    test('plantaardig heeft geen B12 of cholesterol, haring wel B12', () {
      for (final q in ['lentils boiled', 'broccoli raw', 'apple raw']) {
        final f = db.search(q).first;
        expect(f.per100g['b12'] ?? 0, 0, reason: f.name);
        expect(f.per100g['cholesterol'] ?? 0, 0, reason: f.name);
      }
      for (final f in db.search('herring raw')) {
        expect(f.per100g['b12'], greaterThan(3), reason: f.name);
      }
    });

    test('USDA-producten hebben micronutriënten en porties', () {
      final banaan = db.search('banana raw').where((f) => f.source == FoodSource.usda).first;
      expect(banaan.per100g['potassium'], greaterThan(300));
      expect(banaan.per100g['b6'], greaterThan(0.15));
      expect(banaan.portions, isNotEmpty);
    });
  });

  group('dagboek', () {
    const food = Food(ref: 'ciqual:1', name: 'Test', source: FoodSource.ciqual, per100g: {'energy': 200, 'protein': 10});

    test('toevoegen, wijzigen, verwijderen en herstellen', () {
      final db = UserDb(sqlite3.openInMemory());
      final id = db.addEntry(day: '2026-10-15', meal: Meal.lunch, food: food, grams: 150, quantity: 150);
      var e = db.entriesFor('2026-10-15').single;
      expect(e.kcal, 300);
      db.updateEntry(id, meal: Meal.dinner, grams: 50, quantity: 50);
      e = db.entriesFor('2026-10-15').single;
      expect(e.meal, Meal.dinner);
      expect(e.amounts['protein'], 5);
      db.deleteEntry(id);
      expect(db.entriesFor('2026-10-15'), isEmpty);
      db.restoreEntry(id);
      expect(db.entriesFor('2026-10-15'), hasLength(1));
    });

    test('maaltijd kopiëren en recent', () {
      final db = UserDb(sqlite3.openInMemory());
      db.addEntry(day: '2026-10-14', meal: Meal.breakfast, food: food, grams: 100, quantity: 100);
      expect(db.copyMeal(fromDay: '2026-10-14', meal: Meal.breakfast, toDay: '2026-10-15'), 1);
      expect(db.entriesFor('2026-10-15').single.meal, Meal.breakfast);
      expect(db.recent(), hasLength(1));
    });

    test('eigen product terugvinden op barcode', () {
      final db = UserDb(sqlite3.openInMemory());
      db.saveFood(const Food(ref: 'custom:a', name: 'Proteïnereep', barcode: '5400000000001', source: FoodSource.custom, per100g: {'energy': 350}));
      expect(db.foodByBarcode('5400000000001')?.name, 'Proteïnereep');
      expect(db.searchSaved('reep').single.ref, 'custom:a');
    });
  });
}
