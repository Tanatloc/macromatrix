import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/fdc_client.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';
import 'package:macromatrix/ui/widgets/nutrient_row.dart';

/// Ronde 11 (voedingsfreak en sporter): brondata en conventies. CoFID-koolhydraten in gewicht, B3 in
/// niacine-equivalenten, vitamine A in RE, geen uitschieter als "rijkste bron", geen rood zonder maximum.
void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );
  Food ref(String r) => s.foods.byRef(r)!;

  group('NF-1: CoFID-koolhydraten als gewicht, havermout ~58 g', () {
    test('"oats" en "havermout": gewone havervlokken bovenaan, met 55–62 g koolhydraten', () {
      for (final q in ['oats', 'havermout']) {
        final box = groupFoods(s.searchLocal(q)).first.main;
        final quick = s.resolveQuick(QuickItem(q)).first.$1;
        for (final f in [box, quick]) {
          expect(f.name.toLowerCase(), contains('oat'), reason: '$q: ${f.name}');
          expect(f.source, isNot(FoodSource.cofid), reason: '$q: ${f.ref} ${f.name}');
          expect(f.per100g['carbs']!, inInclusiveRange(55, 62), reason: '$q: ${f.ref} ${f.name}');
          expect(f.label?.flags ?? const [], isNot(contains('fortified')), reason: '$q: ${f.name}');
        }
      }
    });

    test('CoFID omgerekend: zetmeel ÷ 1,10, disachariden ÷ 1,05, energie ongewijzigd', () {
      // Porridge oats: koolhydraten 70,7, zetmeel 70,4, sacharose 0,3 (monosacharide-equivalenten)
      final oats = ref('cofid:11-788');
      expect(oats.per100g['starch'], closeTo(70.4 / 1.10, 0.01));
      expect(oats.per100g['carbs'], closeTo(70.7 - (70.4 - 70.4 / 1.10) - (0.3 - 0.3 / 1.05), 0.01));
      expect(oats.per100g['energy'], 381);
      // Rijst, lange korrel, gekookt: 31,1 → ~28,3 (USDA 28,2)
      expect(ref('cofid:11-862').per100g['carbs'], closeTo(31.1 - (31.1 - 31.1 / 1.10), 0.05));
      // Halfvolle melk: alleen lactose, 4,7 → 4,48
      final milk = ref('cofid:12-313');
      expect(milk.per100g['sugars'], closeTo(4.7 / 1.05, 0.01));
      expect(milk.per100g['carbs'], closeTo(4.7 / 1.05, 0.01));
    });

    test('havermout in een groep: CoFID staat bij "Andere bronnen", niet vooraan', () {
      final g = groupFoods(s.searchLocal('oats')).firstWhere((g) => g.others.any((o) => o.ref == 'cofid:11-788') || g.main.ref == 'cofid:11-788');
      expect(g.main.ref, isNot('cofid:11-788'));
      expect(g.main.source.priority, lessThan(FoodSource.cofid.priority));
    });

    test('bronvoorkeur: CIQUAL/Frida/Matvaretabellen/Livsmedelsverket, dan CoFID, dan USDA', () {
      expect({for (final x in [FoodSource.ciqual, FoodSource.frida, FoodSource.mvt, FoodSource.slv]) x.priority}, {0});
      expect(FoodSource.cofid.priority, 1);
      expect(FoodSource.usda.priority, 2);
      // Halfvolle melk: niet de CoFID-rij met 0,9 µg B12 vooraan (NF-16)
      expect(groupFoods(s.searchLocal('halfvolle melk')).first.main.source, isNot(FoodSource.cofid));
    });
  });

  group('NF-2: B3 in niacine-equivalenten', () {
    test('NE = voorgevormde niacine + tryptofaan / 60', () {
      // USDA kip, borst, gebraden: niacine 13,712 mg + tryptofaan 0,362 g → 13,712 + 362 / 60 = 19,75 mg NE
      final chicken = ref('usda_sr:171477');
      expect(chicken.per100g['tryptophan'], closeTo(0.362, 1e-6));
      expect(chicken.per100g['b3'], closeTo(13.712 + 362 / 60, 0.01));
      // CoFID geeft NE zelf: halfvolle melk niacine 0,1 + tryptofaan/60 0,6 = 0,7 mg NE
      expect(ref('cofid:12-313').per100g['b3'], closeTo(0.7, 1e-6));
      // en tryptofaan/60 is ook de tryptofaan zelf: 2,7 mg × 60 = 0,162 g in havermout
      expect(ref('cofid:11-788').per100g['tryptophan'], closeTo(0.162, 1e-6));
    });

    test('label en doel in dezelfde eenheid', () {
      expect(nutrientByKey['b3']!.nameNl, contains('niacine-equivalenten'));
      // EFSA 1,6 mg NE per MJ
      final t = targetsFor(const Profile(sex: Sex.female, birthYear: 2004, weightKg: 60, heightCm: 168), year: 2026)['b3']!;
      expect(t.goal, greaterThan(10));
    });
  });

  group('NF-17: vitamine A in RE, zoals het EFSA-doel', () {
    test('plantaardig: RE = bètacaroteen / 6; RAE-bronnen omgerekend', () {
      // Matvaretabellen gaf RAE 474 (5688 / 12): nu RE 948 (5688 / 6)
      final carrot = ref('mvt:06.036');
      expect(carrot.per100g['vit_a'], closeTo(carrot.per100g['beta_carotene']! / 6, 0.5));
      expect(ref('ciqual:20009').per100g['vit_a'], closeTo(13200 / 6, 0.5));
      // USDA wortel: RAE 835 + 8285 / 12 + alfacaroteen 3477 / 24 = 1670 µg RE
      expect(ref('usda_sr:170393').per100g['vit_a'], closeTo(1670, 1));
      expect(nutrientByKey['vit_a']!.nameNl, contains('RE'));
      expect(nutrientByKey['vit_a']!.nameNl, isNot(contains('RAE')));
    });

    test('online USDA (barcode): RAE ook naar RE', () {
      final n = mapFdcNutrients([
        [1008, 'KCAL', 40],
        [1106, 'UG', 100],
        [1107, 'UG', 1200],
      ]);
      expect(n['vit_a'], closeTo(200, 1e-9));
    });
  });

  group('SP-1: uitschieter geen rijkste bron', () {
    test('eiwitshake: 125 mg mangaan weggelaten in de database (nu een schatting)', () {
      final shake = ref('usda_sr:174181');
      expect(shake.per100g['manganese'] ?? 0, lessThan(10));
      expect(shake.estimated, contains('manganese'));
      expect([for (final r in s.richestFor('manganese', limit: 40)) r.$1.ref], isNot(contains('usda_sr:174181')));
    });

    test('regel: meer dan 10× de bovengrens, of zonder bovengrens 10× het doel buiten gewone voeding', () {
      const mn = Target(goal: 3);
      expect(absurdShare(125, mn), isTrue);
      expect(absurdShare(20, mn), isFalse);
      // Lever met 70 µg B12 (geen bovengrens): een gewoon voedingsmiddel, blijft een bron
      expect(absurdShare(70, const Target(goal: 4), wholeFood: true), isFalse);
      // Kombu met 450 000 µg jodium tegenover een bovengrens van 600 µg
      expect(absurdShare(450000, const Target(goal: 150, upper: 600), wholeFood: true), isTrue);
      // Paranoten: selenium 1917 µg, 7,5× de bovengrens
      expect(absurdShare(1917, const Target(goal: 70, upper: 255)), isFalse);
      // Een limiet (zout) gaat niet over aanraden
      expect(absurdShare(30000, const Target(upper: 2000)), isFalse);
      // De shake is geen gewoon voedingsmiddel: met de oude waarde zou hij uit de lijst vallen
      expect(isAdviceFood(ref('usda_sr:174181')), isFalse);
    });
  });

  group('NF-6 / NW-15: rood alleen boven een maximum', () {
    test('één regel: zonder maximum nooit "te veel"', () {
      expect(isTooMuch(3195, const Target(goal: 250)), isFalse); // EPA+DHA
      expect(isTooMuch(3.34 * 0.6, const Target(goal: 0.6)), isFalse); // aminozuur 334%
      expect(isTooMuch(150, const Target(goal: 15, upper: 100)), isTrue); // vitamine D boven de bovengrens
      expect(isTooMuch(80, const Target(goal: 63, about: true)), isTrue); // vet 127%
    });

    Widget app(Widget child) => MaterialApp(
      theme: buildTheme(Brightness.light),
      home: Scaffold(body: SizedBox(width: 400, child: child)),
    );

    testWidgets('EPA+DHA >999% zonder maximum: geen rode tekst, geen rode balk, geen driehoek', (tester) async {
      await tester.pumpWidget(app(NutrientRow(nutrient: nutrientByKey['epa_dha']!, amount: 3195, target: const Target(goal: 250))));
      final p = tester.element(find.byType(NutrientRow)).pal;
      final pct = tester.widget<Text>(find.text('>999%'));
      expect(pct.style?.color, isNot(p.high));
      expect(tester.widget<StatusMark>(find.byType(StatusMark)).level, isNot(Level.high));
      final colors = [
        for (final b in tester.widgetList<DecoratedBox>(find.descendant(of: find.byType(RangeBar), matching: find.byType(DecoratedBox))))
          (b.decoration as BoxDecoration).color,
        for (final c in tester.widgetList<Container>(find.descendant(of: find.byType(RangeBar), matching: find.byType(Container))))
          (c.decoration as BoxDecoration?)?.color,
      ];
      expect(colors, isNot(contains(p.high)));
      expect(colors, isNot(contains(p.highFill)));
    });

    testWidgets('met een bovengrens: wel rood', (tester) async {
      await tester.pumpWidget(app(NutrientRow(nutrient: nutrientByKey['vit_d']!, amount: 400, target: const Target(goal: 15, upper: 100))));
      final p = tester.element(find.byType(NutrientRow)).pal;
      expect(tester.widget<StatusMark>(find.byType(StatusMark)).level, Level.high);
      expect(tester.widget<Text>(find.text('>999%')).style?.color, p.high);
    });
  });
}
