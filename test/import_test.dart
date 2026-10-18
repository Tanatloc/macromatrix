import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:voedingsapp/data/user_db.dart';
import 'package:voedingsapp/i18n.dart';
import 'package:voedingsapp/import/csv.dart';
import 'package:voedingsapp/import/importer.dart';

(String, Uint8List) file(String name, String text) => (name, Uint8List.fromList(utf8.encode(text)));

const cronometerServings =
    'Day,Time,Group,Food Name,Amount,Category,Energy (kcal),Alcohol (g),Caffeine (mg),Water (g),B1 (Thiamine) (mg),'
    'B12 (Cobalamin) (µg),Folate (µg),Vitamin A (µg),Vitamin C (mg),Vitamin D (IU),Calcium (mg),Iron (mg),Magnesium (mg),'
    'Potassium (mg),Selenium (µg),Sodium (mg),Zinc (mg),Carbs (g),Fiber (g),Sugars (g),Added Sugars (g),Net Carbs (g),Fat (g),'
    'Cholesterol (mg),Saturated (g),Trans-Fats (g),Omega-3 (g),Omega-6 (g),Leucine (g),Protein (g)\n'
    '2026-10-14,8:05 AM,Breakfast,"Oats, Rolled",60.00 g,Breakfast Cereals,228,0,0,5.2,0.3,0,19.2,0,0,0,31.2,2.6,82.8,257,17.4,1.2,2.2,40.6,6.0,0.6,0,34.6,4.1,0,0.7,0,0.06,1.5,0.6,7.9\n'
    '2026-10-14,,Lunch,"Banana, Fresh",1.00 medium,Fruits,105,0,0,88,0,0,24,4,10.3,0,6,0.3,32,422,1,1,0.2,27,3.1,14.4,0,23.9,0.4,0,0.1,0,0,0,0.1,1.3\n'
    '2026-10-14,7:30 PM,Dinner,Salmon,150.00 g,Fish,312,0,0,96,0.3,4.8,38,60,0,526,13,0.5,40,560,41,93,0.6,0,0,0,0,0,20,82,3.1,0,3.3,0.3,1.9,30\n'
    '2026-10-14,7:30 PM,Dinner,Salmon,150.00 g,Fish,312,0,0,96,0.3,4.8,38,60,0,526,13,0.5,40,560,41,93,0.6,0,0,0,0,0,20,82,3.1,0,3.3,0.3,1.9,30\n';

const cronometerBiometrics =
    'Day,Time,Group,Metric,Unit,Amount\n'
    '2026-10-14,07:00,,Weight,lbs,176.4\n'
    '2026-10-14,07:01,,Blood Pressure,mmHg,120/80\n'
    '2026-10-14,07:02,,Blood Glucose,mg/dL,90\n'
    '2026-10-14,07:03,,Steps,steps,10000\n';

const cronometerExercises = 'Day,Time,Group,Exercise,Minutes,Calories Burned\n2026-10-14,18:00,,Running,30,-350\n';
const cronometerNotes = 'Day,Group,Note\n2026-10-14,Breakfast,Slecht geslapen\n2026-10-14,Dinner,"Uit eten, veel zout"\n';

void main() {
  // De verwachte teksten hieronder zijn Nederlands
  setAppLang(AppLang.nl);
  test('CSV: aanhalingstekens, komma\'s en regeleinden in velden', () {
    final rows = parseCsv('a,b,c\n"1,5","zei ""hallo""","twee\nregels"\r\n\n3,4,5');
    expect(rows, [
      ['a', 'b', 'c'],
      ['1,5', 'zei "hallo"', 'twee\nregels'],
      ['3', '4', '5'],
    ]);
    expect(parseCsv('x;y\n1,5;2'), [
      ['x', 'y'],
      ['1,5', '2'],
    ]);
  });

  group('Cronometer', () {
    final batch = Importer(ImportSource.cronometer).read([
      file('servings.csv', cronometerServings),
      file('biometrics.csv', cronometerBiometrics),
      file('exercises.csv', cronometerExercises),
      file('notes.csv', cronometerNotes),
    ]);

    test('producten met alle voedingsstoffen, per 100 g', () {
      expect(batch.entries, hasLength(4));
      final oats = batch.entries.first;
      expect(oats.name, 'Oats, Rolled');
      expect(oats.meal, 0);
      expect(oats.time, '08:05');
      expect(oats.grams, 60);
      expect(oats.per100g['energy'], closeTo(380, 0.01)); // 228 kcal in 60 g
      expect(oats.per100g['carbs'], closeTo(34.6 / 0.6, 0.01), reason: 'netto koolhydraten = beschikbare koolhydraten');
      expect(oats.per100g['leucine'], closeTo(0.6 / 0.6, 1e-9));
      expect(oats.per100g.containsKey('Added Sugars'), isFalse);
      final salmon = batch.entries[2];
      expect(salmon.per100g['vit_d'], closeTo(526 / 40 / 1.5, 0.001), reason: 'IE naar µg');
      expect(salmon.time, '19:30');
      expect(salmon.meal, 2);
    });

    test('hoeveelheid zonder gram wordt een portie, met de totalen', () {
      final banana = batch.entries[1];
      expect(banana.portionLabel, '1.00 medium');
      expect(banana.grams, 100);
      expect(banana.per100g['energy'], 105);
      expect(banana.meal, 1);
      expect(banana.time, isNull);
    });

    test('twee identieke regels blijven twee regels', () {
      expect(batch.entries[2].id, isNot(batch.entries[3].id));
    });

    test('metingen, beweging en notities', () {
      final weight = batch.biometrics.firstWhere((b) => b.type == 'weight');
      expect(weight.value, closeTo(80.01, 0.01));
      final bp = batch.biometrics.firstWhere((b) => b.type == 'blood_pressure');
      expect((bp.value, bp.value2), (120, 80));
      expect(batch.biometrics.firstWhere((b) => b.type == 'glucose').value, closeTo(5.0, 0.01));
      expect(batch.biometrics.firstWhere((b) => b.type == 'custom:Steps').unit, 'steps');
      expect(batch.exercises.single.kcal, 350);
      expect(batch.exercises.single.minutes, 30);
      expect(batch.notes['2026-10-14'], 'Slecht geslapen\nUit eten, veel zout');
      expect(batch.files.map((f) => f.$2), ['dagboek per product', 'metingen', 'beweging', 'notities']);
    });

    test('opnieuw inlezen geeft dezelfde ids, opnieuw bewaren geen dubbels', () {
      final again = Importer(ImportSource.cronometer).read([file('servings.csv', cronometerServings)]);
      expect(again.entries.map((e) => e.id), batch.entries.map((e) => e.id));
      final db = UserDb(sqlite3.openInMemory());
      expect(db.importBatch(batch), (4 + 4 + 1 + 1, 0));
      expect(db.importBatch(batch), (0, 10));
      expect(db.entriesFor('2026-10-14'), hasLength(4));
      expect(db.note('2026-10-14'), 'Slecht geslapen\nUit eten, veel zout');
      expect(db.hasDirtyRows, isTrue, reason: 'geïmporteerde gegevens gaan naar de server');
    });
  });

  group('MyFitnessPal', () {
    const nutrition =
        'Date,Meal,Calories,Fat (g),Saturated Fat,Polyunsaturated Fat,Monounsaturated Fat,Trans Fat,Cholesterol,Sodium (mg),'
        'Potassium,Carbohydrates (g),Fiber,Sugar,Protein (g),Vitamin A,Vitamin C,Calcium,Iron,Note\n'
        '2026-10-14,Breakfast,450,12,3,2,5,0,30,300,400,60,6,10,25,10,20,15,8,Goed begonnen\n'
        '2026-10-14,Dinner,700,25,8,4,10,0.5,90,900,800,70,8,6,45,15,10,10,20,\n';
    const exercise =
        'Date,Exercise,Type,Exercise Calories,Exercise Minutes,Sets,Reps Per Set,Kilograms,Steps,Note\n'
        '2026-10-14,"Running (jogging), general",Cardio,320,30,,,,,\n';
    const measurements = 'Date,Weight,Body Fat %,Neck\n2026-10-10,180.2,22,15\n2026-10-14,178.6,21.5,15\n';

    Uint8List zip() {
      final a = Archive()
        ..addFile(ArchiveFile.string('Nutrition-Summary-2026-10-10-to-2026-10-14.csv', nutrition))
        ..addFile(ArchiveFile.string('Exercise-Summary-2026-10-10-to-2026-10-14.csv', exercise))
        ..addFile(ArchiveFile.string('Measurement-Summary-2026-10-10-to-2026-10-14.csv', measurements));
      return Uint8List.fromList(ZipEncoder().encode(a));
    }

    test('ZIP met totalen per maaltijd, beweging en metingen', () {
      final batch = Importer(ImportSource.myfitnesspal).read([('export.zip', zip())]);
      expect(batch.entries, hasLength(2));
      final b = batch.entries.first;
      expect(b.name, 'MyFitnessPal: ontbijt (totaal)');
      expect(b.per100g['energy'], 450);
      expect(b.per100g['carbs'], 54, reason: 'totaal min vezels');
      expect(b.per100g['sfa'], 3);
      expect(b.per100g['sodium'], 300);
      expect(b.per100g.containsKey('vit_a'), isFalse, reason: '% van de dagwaarde wordt niet overgenomen');
      expect(batch.warnings.any((w) => w.contains('Vitamin A')), isTrue);
      expect(batch.entries.last.meal, 2);
      expect(batch.notes['2026-10-14'], 'Goed begonnen');
      expect(batch.exercises.single.name, 'Running (jogging), general');
      // Gewicht zonder eenheid: rond 180 is waarschijnlijk lb
      expect(batch.weightUnitUnknown, isTrue);
      expect(batch.biometrics.firstWhere((x) => x.type == 'weight').value, closeTo(81.74, 0.01));
      expect(batch.biometrics.where((x) => x.type == 'body_fat'), hasLength(2));
      expect(batch.warnings.any((w) => w.contains('Neck')), isTrue);
    });

    test('gekozen eenheid voor het gewicht heeft voorrang', () {
      final batch = Importer(ImportSource.myfitnesspal, weightUnit: WeightUnit.kg).read([('export.zip', zip())]);
      expect(batch.biometrics.firstWhere((x) => x.type == 'weight').value, 180.2);
    });

    test('dagboek per product (volledige export) en Amerikaanse datums', () {
      const diary =
          'Date,Meal,Time,Food Name,Brand,Serving Size,Calories,Protein (g),Carbohydrates (g),Fat (g),Fiber (g)\n'
          '10/14/2026,Lunch,12:30,Greek Yogurt,Fage,170 g,100,18,6,0,0\n';
      final batch = Importer(ImportSource.myfitnesspal).read([file('food_diary.csv', diary)]);
      final e = batch.entries.single;
      expect(e.day, '2026-10-14');
      expect(e.brand, 'Fage');
      expect(e.grams, 170);
      expect(e.per100g['protein'], closeTo(18 / 1.7, 1e-9));
    });

    test('onbekend bestand wordt overgeslagen met uitleg', () {
      final batch = Importer(ImportSource.myfitnesspal).read([file('profile.csv', 'Email,Goal\nx@y.be,lose\n')]);
      expect(batch.isEmpty, isTrue);
      expect(batch.files.single.$2, 'niet herkend, overgeslagen');
    });
  });
}
