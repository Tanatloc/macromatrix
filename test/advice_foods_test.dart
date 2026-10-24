import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/state/app_state.dart';

/// Advies (wat je nog kunt eten, de tip van de week) gaat over gewoon eten, met de echte databank.
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  final odd = RegExp(
    r'\bagar\b|seaweed|kombu|wakame|yeast|energy drink|chewing gum|tablets|cream of tartar|\btea\b|bouillon|broth|gelatin|'
    r'powder|isolate|liver|(?<!beans, )kidney|Alaska Native|vitamins and minerals|mushrooms?, dried|yolk|psyllium|fibre',
    caseSensitive: false,
  );

  test('geen ingrediënten, supplementen of vreemde producten als advies', () {
    for (final k in [...stripKeys, 'fiber', 'epa_dha', 'protein']) {
      for (final perKcal in [true, false]) {
        for (final (f, _) in s.richestFor(k, perKcal: perKcal, limit: 25, advice: true)) {
          expect(odd.hasMatch(f.name), isFalse, reason: '$k: ${f.name}');
          expect(f.label?.food == 'kidney bean' && f.label?.state == 'raw', isFalse, reason: '$k: ${f.name}');
        }
      }
    }
  });

  test('voor elke stof met een doel is er advies', () {
    for (final k in [...stripKeys.where((k) => k != 'sodium'), 'fiber', 'epa_dha']) {
      expect(s.richestFor(k, perKcal: true, limit: 5, advice: true), isNotEmpty, reason: k);
    }
  });

  test('gewone bronnen bovenaan: wortel voor vitamine A, vette vis voor omega-3', () {
    expect(s.richestFor('vit_a', perKcal: true, limit: 3, advice: true).first.$1.label!.food, 'carrot');
    final fish = {for (final (f, _) in s.richestFor('epa_dha', perKcal: true, limit: 10, advice: true)) f.label!.group};
    expect(fish, {'fish'});
  });

  test('geen frieten, fastfood, gepaneerd of gezoet als advies, ook niet uit wat je eet', () {
    final db = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    for (final q in ['French fries, deepfried, fast food', 'chips', 'nuggets', 'doughnut']) {
      for (final f in db.search(q, limit: 20)) {
        if (RegExp(r'fries|fast food|nugget|doughnut|donut|deep', caseSensitive: false).hasMatch(f.name)) {
          expect(isAdviceFood(f), isFalse, reason: f.name);
        }
      }
    }
  });

  test('Orakel: geen uitschieters tussen databanken (eend zonder vel 46,7 g eiwit) of stamspecifieke producten', () {
    final s = AppState(foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)), user: UserDb(sqlite3.openInMemory()));
    for (final every in [true, false]) {
      final protein = s.oracle('protein', limit: 40, everyday: every);
      expect(protein.map((r) => r.$1.ref), isNot(contains('mvt:03.232')), reason: 'eend zonder vel, gebraden');
      expect(protein.map((r) => r.$1.ref), isNot(contains('mvt:03.234')), reason: 'gans met vel, gebraden');
      for (final (f, _) in [...protein, ...s.oracle('fiber', limit: 40, everyday: every)]) {
        expect(f.name, isNot(matches(RegExp('Alaska Native|Navajo|Shoshone'))), reason: f.name);
      }
    }
  });
}
