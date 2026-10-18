import 'package:flutter_test/flutter_test.dart';
import 'package:voedingsapp/i18n.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:voedingsapp/data/export.dart';
import 'package:voedingsapp/data/food.dart';
import 'package:voedingsapp/data/models.dart';
import 'package:voedingsapp/data/off_client.dart';
import 'package:voedingsapp/nutrition/estimate.dart';
import 'package:voedingsapp/data/user_db.dart';
import 'package:voedingsapp/nutrition/targets.dart';

void main() {
  const banaan = Food(ref: 'ciqual:13005', name: 'Banaan', source: FoodSource.ciqual, per100g: {'energy': 90, 'potassium': 360});
  const havermout = Food(ref: 'ciqual:9310', name: 'Havervlokken', source: FoodSource.ciqual, per100g: {'energy': 370, 'protein': 13});

  ItemTemplate item(Food f, double g) => ItemTemplate(foodRef: f.ref, name: f.name, grams: g, quantity: g, per100g: f.per100g);

  test('recept: voedingswaarden per 100 g van het eindresultaat en per portie', () {
    final db = UserDb(sqlite3.openInMemory());
    final r = Recipe(
      ref: UserDb.newRecipeRef(),
      name: 'Havermoutpap',
      servings: 2,
      cookedGrams: 500, // met water gekookt
      ingredients: [item(havermout, 100), item(banaan, 100)],
    );
    db.saveRecipe(r);
    final food = db.food(r.ref)!;
    expect(food.source, FoodSource.recipe);
    expect(food.per100g['energy'], closeTo((370 + 90) / 5, 1e-9)); // 460 kcal in 500 g
    expect(food.portions.single.grams, 250);
    expect(db.recipe(r.ref)!.ingredients, hasLength(2));
  });

  test('opgeslagen maaltijd', () {
    final db = UserDb(sqlite3.openInMemory());
    db.saveMeal('Ontbijt standaard', [item(havermout, 60), item(banaan, 120)]);
    final m = db.savedMeals().single;
    expect(m.items, hasLength(2));
    expect(m.kcal, closeTo(370 * 0.6 + 90 * 1.2, 1e-9));
  });

  test('terugkerende items komen één keer, ook na verwijderen niet terug', () {
    final db = UserDb(sqlite3.openInMemory());
    db.saveRepeat(mealIndex: 0, item: item(banaan, 100), weekdays: 0x7f, startDay: '2026-10-01');
    final d = DateTime(2026, 10, 15);
    expect(db.applyRepeats('2026-10-15', d), 1);
    expect(db.applyRepeats('2026-10-15', d), 0);
    final e = db.entriesFor('2026-10-15').single;
    db.deleteEntry(e.id);
    expect(db.applyRepeats('2026-10-15', d), 0);
    expect(db.applyRepeats('2026-09-30', DateTime(2026, 9, 30)), 0); // voor de startdag
  });

  test('alleen op gekozen weekdagen', () {
    const r = RepeatItem(
      id: 'x',
      mealIndex: 0,
      item: ItemTemplate(foodRef: 'a', name: 'a', grams: 1, quantity: 1, per100g: {}),
      weekdays: 1,
      startDay: '2000-01-01',
    );
    expect(r.appliesTo(DateTime(2026, 10, 12)), isTrue); // maandag
    expect(r.appliesTo(DateTime(2026, 10, 13)), isFalse);
  });

  test('metingen, beweging, notities en vasten', () {
    final db = UserDb(sqlite3.openInMemory());
    db.addBiometric(day: '2026-10-15', type: 'weight', value: 78.4);
    db.addBiometric(day: '2026-10-15', type: 'blood_pressure', value: 120, value2: 80);
    expect(db.biometricsFor('2026-10-15'), hasLength(2));
    expect(db.biometricHistory('weight').single.value, 78.4);
    db.addExercise(day: '2026-10-15', name: 'Hardlopen', kcal: 450, minutes: 40);
    expect(db.exerciseKcalBetween('2026-10-01', '2026-10-31')['2026-10-15'], 450);
    db.setNote('2026-10-15', 'Slecht geslapen');
    expect(db.note('2026-10-15'), 'Slecht geslapen');
    db.startFast(DateTime(2026, 10, 15, 20), 16);
    final f = db.currentFast()!;
    db.endFast(f.id, DateTime(2026, 10, 16, 12));
    expect(db.currentFast(), isNull);
    expect(db.recentFasts().single.elapsed().inHours, 16);
  });

  test('eigen doelen en weekschema heen en terug naar JSON', () {
    const s = TargetSettings(
      overrides: {'magnesium': Target(goal: 400, upper: 600), 'sodium': Target(upper: 1500)},
      schedule: {6: (30, 30, 40)},
      addExercise: false,
    );
    final t = TargetSettings.fromJson(s.toJson());
    expect(t.overrides['magnesium']!.goal, 400);
    expect(t.overrides['sodium']!.isLimit, isTrue);
    expect(t.schedule[6], (30.0, 30.0, 40.0));
    expect(t.addExercise, isFalse);
  });

  test('beweging telt bij het energiedoel', () {
    const p = Profile(energyOverride: 2000);
    expect(targetsFor(p, year: 2026, extraKcal: 300)['energy']!.goal, 2300);
  });

  test('export naar CSV met puntkomma en decimale komma', () {
    final db = UserDb(sqlite3.openInMemory());
    db.addEntry(day: '2026-10-15', meal: Meal.breakfast, food: banaan, grams: 120, quantity: 120, time: '08:15');
    setAppLang(AppLang.nl);
    final lines = diaryCsv(db).trim().split('\n');
    expect(lines, hasLength(2));
    expect(lines.first, startsWith('datum;tijd;maaltijd;product;merk;gram;Energie (kcal)'));
    expect(lines.last, startsWith('2026-10-15;08:15;Ontbijt;Banaan;;120;108;'));
    setAppLang(AppLang.en);
    final en = diaryCsv(db).trim().split('\n');
    expect(en.first, startsWith('date,time,meal,product,brand,grams,Energy (kcal)'));
    expect(en.last, startsWith('2026-10-15,08:15,Breakfast,Banaan,,120,108,'));
  });

  test('merkproduct: ontbrekende waarden uit het basisproduct, geschaald op eiwit en vet', () {
    const skyr = {'energy': 63.0, 'protein': 11.0, 'carbs': 4.0, 'sugars': 4.0, 'fat': 0.2, 'sfa': 0.1};
    const yoghurt = {'energy': 45.5, 'protein': 4.0, 'fat': 1.5, 'calcium': 128.0, 'leucine': 0.4, 'vit_a': 15.0, 'sfa': 0.9, 'sugars': 5.0};
    final (v, est) = estimateMissing(skyr, yoghurt, 'ciqual:19593');
    expect(v['calcium'], 128); // mineralen: zoals het basisproduct
    expect(v['leucine'], closeTo(0.4 * 11 / 4, 1e-9)); // aminozuren schalen met eiwit
    expect(v['vit_a'], closeTo(15 * 0.2 / 1.5, 1e-9)); // vetoplosbaar schaalt met vet
    expect(v['sfa'], 0.1); // staat op het etiket: niet vervangen
    expect(v['sugars'], 4.0);
    expect(est.keys, containsAll(['calcium', 'leucine', 'vit_a']));
    expect(est.containsKey('sfa'), isFalse);
  });

  test('OFF-koppeling met een CIQUAL-basisproduct wordt herkend', () {
    final f = foodFromOff({
      'code': '8710624358174',
      'product_name': 'Skyr naturel',
      'nutriments': {'energy-kcal_100g': 63},
      'categories_properties': {'agribalyse_proxy_food_code:en': '19593'},
    })!;
    expect(f.proxyRef, 'ciqual:19593');
  });

  test('bewaarde merkproducten houden hun schattingen; dagboek wordt aangevuld', () {
    final db = UserDb(sqlite3.openInMemory());
    const off = Food(ref: 'off:1', name: 'Skyr', barcode: '1', source: FoodSource.off, per100g: {'energy': 63, 'protein': 11});
    db.addEntry(day: '2026-10-16', meal: Meal.breakfast, food: off, grams: 150, quantity: 150);
    final enriched = off.copyWith(per100g: {...off.per100g, 'calcium': 128}, estimated: {'calcium': 'ciqual:19593'}, proxyRef: 'ciqual:19593');
    db.saveFood(enriched);
    final back = db.food('off:1')!;
    expect(back.estimated['calcium'], 'ciqual:19593');
    expect(back.proxyRef, 'ciqual:19593');
    expect(db.fillDiarySnapshots('off:1', enriched.per100g), 1);
    expect(db.entriesFor('2026-10-16').single.amounts['calcium'], closeTo(192, 1e-9));
    expect(db.fillDiarySnapshots('off:1', enriched.per100g), 0); // al aangevuld
  });
}
