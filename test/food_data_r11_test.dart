import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/fdc_client.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/off_client.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/food_groups.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/niacin.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/quick_parse.dart';
import 'package:macromatrix/nutrition/supplements.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';
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
      expect(
        {
          for (final x in [FoodSource.ciqual, FoodSource.frida, FoodSource.mvt, FoodSource.slv]) x.priority,
        },
        {0},
      );
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

  // Onafhankelijke controle van ronde 11 (voedingsapp-data/evaluaties/rondes/r11/data-verificatie.md): de punten 1-11
  group('R11-controle', () {
    final raw = sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly);
    final all = [
      for (final r in raw.select('SELECT source, source_id, nutrients, estimated, label FROM foods'))
        (
          ref: '${r['source']}:${r['source_id']}',
          n: (jsonDecode(r['nutrients'] as String) as Map).cast<String, num>(),
          est: (jsonDecode(r['estimated'] as String) as Map).cast<String, String>(),
          label: (r['label'] as String).isEmpty ? const <String, Object?>{} : (jsonDecode(r['label'] as String) as Map).cast<String, Object?>(),
        ),
    ];
    final adult = targetsFor(const Profile(sex: Sex.female, birthYear: 1990, weightKg: 65, heightCm: 170), year: 2026);

    test('1. foute tryptofaan telt niet meer in B3: rundshart ~10,8 mg NE, koffie en thee niet absurd', () {
      for (final r in ['frida:641', 'ciqual:40052', 'mvt:03.118', 'frida:566']) {
        final f = ref(r);
        expect(f.per100g['tryptophan']! / f.per100g['protein']!, lessThan(0.025), reason: r);
        expect(f.per100g['b3'], inInclusiveRange(7, 13), reason: '$r: ${f.per100g['b3']}');
      }
      expect(ref('frida:1075').per100g['b3'], lessThan(30)); // gemalen koffie, was 125
      expect(ref('ciqual:18003').per100g['b3'], lessThan(30));
      expect(ref('frida:537').per100g['b3'], lessThan(15)); // theebladeren, was 21
      expect(ref('frida:1089').per100g['b3'], lessThan(3)); // schorseneer, was 18
      // Boven 2,5 % van het eiwit alleen wat twee databanken onafhankelijk meten (dadels, pecannoten)
      final high = {
        for (final f in all)
          if ((f.n['protein'] ?? 0) >= 1 && f.n['tryptophan'] != null && f.n['tryptophan']! / f.n['protein']! > 0.025) f.label['f'],
      };
      // Spinazie: sinds 26-10-2026 ook door BLS gemeten, naast de USDA (2,5 à 2,8 % van het eiwit)
      expect(high, everyElement(isIn(['date', 'pecan nut', 'spinach'])));
    });

    test('1. tryptofaan, chroom en molybdeen zitten in de uitschieterscontrole', () {
      final report = File('tool/outlier_report.md').readAsStringSync();
      expect(report, contains('| frida:641 | Heart, beef, raw | offal | tryptophan |'));
      expect(report, contains('| frida:1075 | Coffee bean, roasted, ground |'));
    });

    test('2. NE van de bron zonder voorgevormde niacine: max(bron, niacine + tryptofaan/60)', () {
      expect(ref('frida:59').per100g['b3'], closeTo(0.8 + 179 / 60, 0.05)); // havervlokken ~3,8
      expect(ref('frida:617').per100g['b3'], greaterThan(25)); // tarwezemelen, was 3,4
      expect(ref('frida:1081').per100g['b3'], greaterThan(30)); // rijstzemelen, was 3,1
      expect(ref('cofid:13-805').per100g['b3'], closeTo(6.9 + 3.7, 0.05)); // basilicum: NIACEQU 1,6 was fout
      expect(ref('cofid:19-535').per100g['b3'], closeTo(3.0 + 2.9, 0.05)); // lamscurry: NIACEQU 0,6 was fout
      // Waar de bron wel klopt, blijft haar eigen NE (CoFID halfvolle melk 0,7)
      expect(ref('cofid:12-313').per100g['b3'], closeTo(0.7, 1e-6));
    });

    test('3. Matvaretabellen: de eigen NIAEQ', () {
      final heart = ref('mvt:03.118');
      expect(heart.per100g['b3'], closeTo(10.8, 1e-6));
      expect(heart.estimated, isNot(contains('b3')));
    });

    test('4. "semi-skimmed milk" en "halfvolle melk": een melk met ~1,5 % vet vooraan', () {
      for (final q in ['semi-skimmed milk', 'halfvolle melk', 'milk', 'melk']) {
        final quick = s.resolveQuick(QuickItem(q)).first.$1;
        final foods = [quick, if (q.contains('skimm') || q.contains('halfvol')) groupFoods(s.searchLocal(q)).first.main];
        for (final f in foods) {
          expect(f.per100g['fat'], inInclusiveRange(1.4, 1.9), reason: '$q: ${f.ref} ${f.name}');
          expect(f.per100g['energy'], inInclusiveRange(44, 50), reason: '$q: ${f.ref} ${f.name}');
        }
      }
      // De regel zelf: EU-benamingen met hun vetgehalte, niet één bepaald product
      expect(offStandardMilk(ref('mvt:01.292')), isTrue); // Noorse lettmelk 0,8 % als "semi-skimmed"
      expect(offStandardMilk(ref('ciqual:19041')), isFalse);
      expect(offStandardMilk(ref('cofid:12-313')), isFalse); // 1,7 %
      expect(offStandardMilk(ref('frida:1066')), isFalse); // magere melk 0,5 %
      expect(offStandardMilk(ref('frida:1265')), isFalse); // volle melk 3,5 %
    });

    test('5. "chicken breast" en "kipfilet": zonder vel vooraan, met vel alleen als je het vraagt', () {
      for (final q in ['chicken breast', 'kipfilet']) {
        for (final f in [groupFoods(s.searchLocal(q)).first.main, s.resolveQuick(QuickItem(q)).first.$1]) {
          expect(f.label?.part, isNot('muscle+skin'), reason: '$q: ${f.ref} ${f.name}');
          expect(f.name.toLowerCase(), isNot(contains('and skin')), reason: '$q: ${f.name}');
          expect(f.per100g['energy'], inInclusiveRange(130, 170), reason: '$q: ${f.name}');
          expect(f.per100g['protein'], greaterThanOrEqualTo(28), reason: '$q: ${f.name}');
        }
      }
      final withSkin = ref('cofid:18-325');
      expect(foodQueryScore(withSkin, 'chicken breast'), lessThan(foodQueryScore(withSkin, 'chicken breast with skin')));
    });

    test('6. geen schatting uit een nagekeken uitschieter of uit droge bladeren voor een drank', () {
      // Verse spirulina kreeg 35 940 µg jodium uit gedroogd Gracilaria-zeewier
      expect(ref('ciqual:20982').per100g['iodine'] ?? 0, lessThan(100));
      expect(ref('usda_sr:170091').per100g['iodine'] ?? 0, lessThan(100));
      final keep = (jsonDecode(File('tool/outlier_keep.json').readAsStringSync())['keep'] as Map).cast<String, Map>();
      for (final f in all) {
        for (final e in f.est.entries) {
          final donor = e.value.replaceFirst(RegExp(r'^~+'), '');
          expect(keep[donor]?.containsKey(e.key) ?? false, isFalse, reason: '${f.ref} ${e.key} uit $donor');
        }
      }
      // Thee als drank: geen 335 µg chroom (de waarde van de droge bladeren)
      for (final r in ['mvt:13.042', 'cofid:17-171', 'cofid:17-170', 'cofid:17-169', 'cofid:17-168']) {
        expect(ref(r).per100g['chromium'] ?? 0, lessThan(10), reason: r);
      }
      // Cafeïne in thee met melk is geen groepsgemiddelde van dranken (0,12 mg)
      expect(ref('cofid:17-169').estimated['caffeine'] ?? '', isNot(startsWith('~~')));
    });

    test('6. jodium, chroom, seleen, B12 en vitamine D: geen absurde schatting', () {
      // Ruim boven het hoogste gewone voedingsmiddel (paling 98 µg vitamine D, lever 100 µg B12), ver onder de oude fouten
      const limits = {'selenium': 400.0, 'b12': 120.0, 'vit_d': 120.0, 'chromium': 400.0};
      for (final f in all) {
        for (final MapEntry(key: k, value: max) in limits.entries) {
          if (f.est.containsKey(k)) expect(f.n[k]!, lessThan(max), reason: '${f.ref} $k ${f.n[k]}');
        }
        // Jodium in de tienduizenden alleen bij zeewier zelf
        if (f.est.containsKey('iodine') && f.n['iodine']! > 1000) expect(f.label['k'], 'algae', reason: f.ref);
      }
    });

    test('7. zeeduivel en grenadier: geen 414 en 356 µg selenium; een piek binnen dezelfde soort valt op', () {
      expect(ref('ciqual:26208').per100g['selenium'], lessThan(80));
      expect(ref('ciqual:26208').estimated, contains('selenium'));
      expect(ref('ciqual:26128').per100g['selenium'], lessThan(80));
      // Dezelfde toets vangt de gebraden gans van Matvaretabellen (~7× de mineralen van andere gans)
      expect(ref('mvt:03.245').per100g['zinc'], lessThan(8));
      expect(ref('mvt:03.245').per100g['b3'], lessThan(20)); // niacine 33,2 mg, NE 82: verbeterd in food_fixes.json
      final report = File('tool/outlier_report.md').readAsStringSync();
      expect(report, contains('(soort: monkfish)'));
      expect(report, contains('(soort: grenadier)'));
    });

    test('8. retinol apart, met de EFSA-bovengrens; geen bovengrens op het totaal (RE)', () {
      final n = nutrientByKey['retinol']!;
      expect(n.indent, 1);
      expect(nutrients.indexWhere((x) => x.key == 'retinol'), nutrients.indexWhere((x) => x.key == 'vit_a') + 1);
      expect(adult['retinol']!.upper, 3000);
      expect(adult['retinol']!.goal, isNull);
      expect(adult['vit_a']!.upper, isNull);
      expect(retinolUpperLimit(16), 2600);
      // Lever: bijna al het vitamine A is retinol; wortel: geen retinol
      for (final r in ['ciqual:40106', 'cofid:18-409', 'frida:698', 'usda_sr:169451']) {
        final liver = ref(r);
        expect(liver.per100g['retinol'], greaterThan(3000), reason: r);
        expect(liver.per100g['retinol']!, lessThanOrEqualTo(liver.per100g['vit_a']! * 1.01), reason: r);
      }
      for (final r in ['ciqual:20009', 'usda_sr:170393', 'frida:24']) {
        expect(ref(r).per100g['retinol'], 0, reason: r);
      }
      // USDA zonder apart retinol: RAE − bètacaroteen / 12 (boter 671 µg)
      expect(ref('usda_sr:173410').per100g['retinol'], closeTo(671, 1));
      expect(
        mapFdcNutrients([
          [1008, 'KCAL', 100],
          [1105, 'UG', 250],
        ])['retinol'],
        250,
      );
    });

    test('8. een dag met 100 g lever: waarschuwing; 300 g wortel: niet', () {
      NutrientMap day(String r, double grams) => {for (final e in ref(r).per100g.entries) e.key: e.value * grams / 100};
      final liver = day('ciqual:40106', 100);
      expect(isTooMuch(liver['retinol']!, adult['retinol']), isTrue);
      expect([for (final a in attentionList(liver, adult, limit: 4)) a.$1.key], contains('retinol'));
      final carrots = day('ciqual:20009', 300);
      expect(isTooMuch(carrots['vit_a']!, adult['vit_a']), isFalse);
      expect(isTooMuch(carrots['retinol'] ?? 0, adult['retinol']), isFalse);
      expect([
        for (final a in attentionList(carrots, adult, limit: 4))
          if (a.$3 == Level.high) a.$1.key,
      ], isEmpty);
    });

    test('8. gezondheidscheck: gemiddeld boven 3000 µg retinol geeft een tip over lever', () {
      final t = targetsFor(const Profile(), year: 2026);
      NutrientTotals day(double retinol) => NutrientTotals(
        {
          for (final k in stripKeys) k: (t[k]!.goal ?? 0) * 1.0,
          'energy': t['energy']!.goal!,
          'protein': t['protein']!.goal!,
          'fiber': 32,
          'sodium': 1600,
          'retinol': retinol,
        },
        const {},
        const {},
        10,
      );
      List<String> tips(double retinol) =>
          healthCheck([for (var i = 0; i < 7; i++) (day(retinol), t)], weightKg: 75)!.factors.firstWhere((f) => f.key == 'micro').tips;
      expect(tips(5000).join(' '), contains('retinol'));
      expect(tips(1000).join(' '), isNot(contains('retinol')));
    });

    testWidgets('8. retinol boven de bovengrens: rood in de lijst', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: NutrientRow(nutrient: nutrientByKey['retinol']!, amount: 13800, target: adult['retinol']),
            ),
          ),
        ),
      );
      expect(tester.widget<StatusMark>(find.byType(StatusMark)).level, Level.high);
    });

    test('9. CoFID zonder zetmeel/suikers: ÷ 1,10 bij zetmeelrijk, anders ÷ 1,05', () {
      expect(ref('cofid:13-107').per100g['carbs'], closeTo(23.9 / 1.10, 0.01)); // pintobonen, gekookt
      expect(ref('cofid:11-011').per100g['carbs'], closeTo(73.1 / 1.10, 0.01)); // maïsmeel
      expect(ref('cofid:14-265').per100g['carbs'], closeTo(56.5 / 1.05, 0.01)); // tamarinde
      expect(ref('cofid:13-805').per100g['carbs'], closeTo(43.2 / 1.05, 0.01)); // gedroogde basilicum
      expect(ref('cofid:13-107').per100g['energy'], 137); // energie ongewijzigd (3,75 kcal per g mono-eq.)
    });

    test('10. geschatte tryptofaan als deel van het eiwit', () {
      final shares = [
        for (final f in all)
          if (f.est.containsKey('tryptophan') && (f.n['protein'] ?? 0) >= 5 && f.label['f'] != 'pecan nut') f.n['tryptophan']! / f.n['protein']!,
      ]..sort();
      expect(shares[shares.length ~/ 2], inInclusiveRange(0.010, 0.014));
      expect(shares.last, lessThanOrEqualTo(0.025));
      // De cheddar uit de controle (0,156 g) was hüttenkäse met 12,4 g eiwit: 1,25 %, in orde
      final cottage = ref('usda_sr:167703');
      expect(cottage.per100g['tryptophan']! / cottage.per100g['protein']!, inInclusiveRange(0.010, 0.016));
    });

    test('11. rijst: niet de parboiled rijst met 61 mg calcium vooraan', () {
      for (final q in ['rice', 'rijst']) {
        for (final f in [groupFoods(s.searchLocal(q)).first.main, s.resolveQuick(QuickItem(q)).first.$1]) {
          expect(f.name.toLowerCase(), isNot(contains('parboiled')), reason: '$q: ${f.name}');
          expect(f.per100g['calcium'], lessThan(30), reason: '$q: ${f.name}');
          expect(f.per100g['energy'], inInclusiveRange(100, 160), reason: '$q: ${f.name}');
        }
      }
    });
  });

  // Wat na de controle van ronde 11 nog openstond: harder, nullen die niet gemeten zijn, NE bij merkproducten,
  // molybdeen in paprika, retinol uit supplementen, verse spirulina
  group('R11-restpunten', () {
    final raw = sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly);
    final all = [
      for (final r in raw.select('SELECT source, source_id, name, nutrients, estimated, label FROM foods'))
        (
          ref: '${r['source']}:${r['source_id']}',
          name: r['name'] as String,
          n: (jsonDecode(r['nutrients'] as String) as Map).cast<String, num>(),
          est: (jsonDecode(r['estimated'] as String) as Map).cast<String, String>(),
          label: (r['label'] as String).isEmpty ? const <String, Object?>{} : (jsonDecode(r['label'] as String) as Map).cast<String, Object?>(),
        ),
    ];

    test('1. harder rauw (CIQUAL): geen 168 µg selenium meer, maar een schatting zoals de andere harders', () {
      for (final r in ['ciqual:26091', 'ciqual:26026']) {
        final f = ref(r);
        expect(f.per100g['selenium'], inInclusiveRange(25, 70), reason: '$r ${f.per100g['selenium']}');
        expect(f.estimated, contains('selenium'), reason: r);
      }
      // De andere harders blijven gemeten
      expect(ref('cofid:16-095').per100g['selenium'], 51);
      expect(ref('ciqual:26085').estimated, isNot(contains('selenium')));
    });

    test('2. witte rijst (Matvaretabellen): calcium en ijzer 0 waren niet gemeten, nu geschat', () {
      final rice = ref('mvt:05.289');
      for (final k in ['calcium', 'iron']) {
        expect(rice.estimated, contains(k), reason: k);
        expect(rice.per100g[k]!, greaterThan(0), reason: k);
      }
      // Gewone witte rijst: niet het calcium van voorgekookte (parboiled) rijst (61-178 mg)
      expect(rice.per100g['calcium'], lessThan(30));
      expect(ref('mvt:05.212').per100g['calcium'], lessThan(40)); // ongekookt (USDA 28 mg)
      // Voorgekookte rijst blijft gemeten
      expect(ref('mvt:05.125').per100g['calcium'], 61);
    });

    test('2. geen gemeten 0 voor calcium, ijzer, magnesium, kalium, fosfor, zink in enkelvoudige granen, peulvruchten, groenten, vlees en vis', () {
      const plant = {'cereal', 'rice', 'pasta', 'bread', 'breakfast cereal', 'legume', 'vegetable', 'potato/tuber', 'nut/seed'};
      const animal = {'meat', 'poultry', 'offal', 'fish', 'shellfish'};
      final except = RegExp(r'\b(lute?fisk|alkaline cured|seaweed caviar)\b', caseSensitive: false);
      final fixes = (jsonDecode(File('tool/food_fixes.json').readAsStringSync())['fixes'] as Map).cast<String, Object?>();
      var checked = 0;
      for (final f in all) {
        final g = f.label['g'], k = f.label['k'];
        if (f.label.isEmpty || f.label['d'] == 1 || f.label['p'] == 'starch' || except.hasMatch(f.name) || fixes.containsKey(f.ref)) continue;
        final keys = [
          if ((plant.contains(g) && (k == 'plant' || k == 'algae')) || (animal.contains(g) && k == 'animal')) ...[
            'calcium',
            'iron',
            'magnesium',
            'potassium',
            'phosphorus',
            'zinc',
          ],
          if (animal.contains(g) && k == 'animal') 'selenium',
        ];
        for (final key in keys) {
          checked++;
          if (f.n[key] == 0) expect(f.est, contains(key), reason: '${f.ref} ${f.name} $key = 0 gemeten');
        }
      }
      expect(checked, greaterThan(50000));
    });

    test('2. echte nullen blijven: B12 in planten, vitamine C en vezels in vlees, mineralen in zetmeel', () {
      expect(ref('mvt:05.289').per100g['b12'], 0);
      expect(ref('cofid:18-323').per100g['vit_c'] ?? 0, lessThan(1)); // kipfilet
      expect(ref('cofid:18-323').per100g['fiber'] ?? 0, 0);
      expect(ref('mvt:05.015').per100g['zinc'], 0); // maïszetmeel: geen schatting
      expect(ref('mvt:05.015').estimated, isNot(contains('zinc')));
    });

    test('2. Matvaretabellen "onder de meetgrens" (bron 60a) bij een enkelvoudig product: aangevuld uit hetzelfde voedingsmiddel', () {
      // Gerookte kalkoenham: selenium 60a, aangevuld uit USDA kalkoen (vlees heeft altijd selenium)
      final ham = ref('mvt:03.323');
      expect(ham.per100g['selenium']!, greaterThan(10));
      expect(ham.estimated, contains('selenium'));
      // Een snoepmix blijft 0: daar is "hetzelfde voedingsmiddel" een ander recept (met chocolade)
      expect(ref('mvt:09.106').per100g['calcium'], 0);
    });

    test('3. merkproduct met alleen voorgevormde niacine: NE = niacine + eiwit × 0,2 mg (geschat)', () {
      // 20 g eiwit × 12 mg tryptofaan per g / 60 = 4 mg NE erbij
      final (n, est) = withNiacinEquivalents({'b3': 5, 'protein': 20}, 'off:123');
      expect(n['b3'], closeTo(9, 1e-9));
      expect(est['b3'], neFromProtein);
      // Zonder eiwit of zonder niacine: niets
      expect(withNiacinEquivalents({'b3': 5}, 'off:123').$1['b3'], 5);
      expect(withNiacinEquivalents({'protein': 20}, 'off:123').$1.containsKey('b3'), isFalse);
      // Gemeten tryptofaan (0,3 g = 5 mg NE) gaat voor en is geen schatting
      final (m, mest) = withNiacinEquivalents({'b3': 5, 'protein': 20, 'tryptophan': 0.3}, 'custom:x');
      expect(m['b3'], closeTo(10, 1e-9));
      expect(mest.containsKey('b3'), isFalse);
      // B3 uit het basisproduct van de databank (al NE), de databank zelf en supplementen: ongewijzigd
      expect(withNiacinEquivalents({'b3': 5, 'protein': 20}, 'off:123', estimated: {'b3': 'ciqual:19590'}).$1['b3'], 5);
      expect(withNiacinEquivalents({'b3': 5, 'protein': 20}, 'ciqual:19590').$1['b3'], 5);
      expect(withNiacinEquivalents({'b3': 16, 'protein': 0}, 'supp:bcomplex').$1['b3'], 16);
      for (final r in ['off:1', 'fdc:1', 'custom:1']) {
        expect(labelNiacinRef(r), isTrue, reason: r);
      }
      for (final r in ['ciqual:1', 'usda_sr:1', 'recipe:1', 'supp:1']) {
        expect(labelNiacinRef(r), isFalse, reason: r);
      }
    });

    test('3. in de app: Open Food Facts, USDA-barcode, eigen product en recept tellen NE, de databank niet dubbel', () {
      final user = UserDb(sqlite3.openInMemory());
      final app = AppState(foods: s.foods, user: user);
      final off = foodFromOff({
        'code': '5400000000001',
        'product_name': 'Protein bar',
        'nutriments': {'energy-kcal_100g': 380, 'proteins_100g': 30, 'carbohydrates_100g': 35, 'fat_100g': 12, 'vitamin-pp_100g': 0.008},
      })!;
      // Het etiket blijft zoals het is (8 mg voorgevormd); tellen doet 8 + 30 × 0,2 = 14 mg NE, gemarkeerd als geschat
      expect(off.per100g['b3'], closeTo(8, 1e-9));
      expect(app.per100gWithSugars(off)['b3'], closeTo(14, 1e-9));
      expect(app.estimatedOf(off)['b3'], neFromProtein);
      final fdc = productFromFdc({
        'found': true,
        'code': '0001',
        'name': 'GREEK YOGURT',
        'nutrients': [
          [1008, 'KCAL', 97],
          [1003, 'G', 9],
          [1167, 'MG', 0.2],
        ],
      })!.food!;
      expect(app.per100gWithSugars(fdc)['b3'], closeTo(0.2 + 9 * 0.2, 1e-9));
      // In het dagboek: elke regel telt zo, ook een oudere
      const day = '2026-10-20';
      user.addEntry(day: day, meal: Meal.breakfast, food: off, grams: 50, quantity: 1);
      const custom = Food(ref: 'custom:abc', name: 'Eigen kwark', source: FoodSource.custom, per100g: {'energy': 60, 'protein': 10, 'b3': 0.1});
      user.addEntry(day: day, meal: Meal.lunch, food: custom, grams: 200, quantity: 1);
      final db = ref('usda_sr:171477'); // kipfilet, al NE (19,75 mg)
      user.addEntry(day: day, meal: Meal.dinner, food: db, grams: 100, quantity: 1);
      final entries = user.entriesFor(day);
      double b3(String r) => app.entryValues(entries.firstWhere((e) => e.foodRef == r))['b3']!;
      expect(b3(off.ref), closeTo(14 / 2, 1e-9));
      expect(b3('custom:abc'), closeTo((0.1 + 10 * 0.2) * 2, 1e-9));
      expect(b3('usda_sr:171477'), closeTo(db.per100g['b3']!, 1e-9));
      // Een merkproduct waarvan B3 uit het basisproduct komt (al NE): niet nog eens
      final enriched = off.copyWith(per100g: {...off.per100g, 'b3': 3}, estimated: {'b3': 'ciqual:31000'});
      expect(app.per100gWithSugars(enriched)['b3'], 3);
      // Een recept met het merkproduct: de NE van dat ingrediënt telt mee, ook als het recept in het dagboek staat
      final recipe = Recipe(
        ref: 'recipe:r1',
        name: 'Bowl',
        servings: 1,
        ingredients: [
          ItemTemplate(foodRef: off.ref, name: off.name, grams: 50, quantity: 1, per100g: off.per100g),
          ItemTemplate(foodRef: db.ref, name: db.name, grams: 100, quantity: 1, per100g: db.per100g),
        ],
      );
      user.saveRecipe(recipe);
      final totals = app.recipeTotalsWithSugars(recipe);
      expect(totals['b3'], closeTo(recipe.totals['b3']! + 30 * 0.2 / 2, 1e-6));
      expect(app.per100gWithSugars(recipe.toFood())['b3']! * recipe.totalGrams / 100, closeTo(totals['b3']!, 1e-6));
    });

    test('4. rode paprika (Frida): geen 70 µg molybdeen, dus ook geen 741 µg in gevriesdroogde paprika', () {
      expect(ref('frida:38').per100g['molybdenum'] ?? 0, lessThan(10));
      expect(ref('frida:38').estimated, contains('molybdenum'));
      expect(ref('usda_sr:169373').per100g['molybdenum'] ?? 0, lessThan(60));
      for (final f in all) {
        if (f.est['molybdenum'] case final donor?) expect(donor, isNot(endsWith('frida:38')), reason: f.ref);
      }
    });

    test('5. supplementen: voorgevormde vitamine A telt als retinol, bètacaroteen niet', () {
      expect(supplementRetinol({'vit_a': 800}, 'Vitamine A (retinylpalmitaat) 800 µg'), 800);
      expect(supplementRetinol({'vit_a': 800}, 'Vitamin A (retinol)'), 800);
      expect(supplementRetinol(supplementCatalog.firstWhere((x) => x.id == 'multi').nutrients, 'Multivitamine'), 800);
      expect(supplementRetinol({'vit_a': 2500}, 'Bètacaroteen 15 mg'), 0);
      expect(supplementRetinol({'vit_a': 2500}, 'Beta-carotene 15 mg'), 0);
      // Vitamine A met bètacaroteen ernaast: 1200 µg bètacaroteen = 200 µg RE, de rest is retinol
      expect(supplementRetinol({'vit_a': 800, 'beta_carotene': 1200}, 'Multi'), 600);
      expect(supplementRetinol({'vit_a': 800, 'retinol': 400}, 'Multi'), 400);
      expect(supplementRetinol({'vit_d': 25}, 'Vitamine D'), isNull);
    });

    test('5. een week met één dag 100 g lever en een retinolsupplement: waarschuwing; met bètacaroteen niet', () {
      final t = targetsFor(const Profile(), year: 2026);
      expect(t['retinol']!.upper, 3000);
      final liver = ref('usda_sr:169451'); // runderlever, 4948 µg retinol
      List<String> tips(Supplement? supp) {
        final user = UserDb(sqlite3.openInMemory());
        final app = AppState(foods: s.foods, user: user);
        final days = [for (var d = 12; d <= 18; d++) '2026-10-$d'];
        user.addEntry(day: days.first, meal: Meal.dinner, food: liver, grams: 100, quantity: 1);
        if (supp != null) {
          for (final d in days) {
            user.setSupplementTaken(d, supp, true);
          }
        }
        final week = [
          for (final d in days)
            (
              NutrientTotals(
                {
                  for (final k in stripKeys) k: (t[k]!.goal ?? 0) * 1.0,
                  'energy': t['energy']!.goal!,
                  'protein': t['protein']!.goal!,
                  'fiber': 32,
                  'sodium': 1600,
                  'retinol': app.totalsOf(user.entriesFor(d))['retinol'],
                },
                const {},
                const {},
                10,
              ),
              t,
            ),
        ];
        return healthCheck(week, weightKg: 75)!.factors.firstWhere((f) => f.key == 'micro').tips;
      }

      const retinyl = Supplement(
        id: 'c-a',
        name: 'Vitamine A (retinylpalmitaat) 2400 µg',
        dose: '1 capsule',
        nutrients: {'energy': 0, 'vit_a': 2400},
      );
      const carotene = Supplement(id: 'c-b', name: 'Bètacaroteen 15 mg', dose: '1 capsule', nutrients: {'energy': 0, 'vit_a': 2400});
      // Lever één keer per week, zonder supplement: gemiddeld ~700 µg, geen waarschuwing
      expect(tips(null).join(' '), isNot(contains('retinol')));
      // Met 2400 µg retinol per dag: gemiddeld ~3100 µg, boven de bovengrens
      expect(tips(retinyl).join(' '), contains('retinol'));
      // Bètacaroteen telt mee voor vitamine A, niet voor retinol
      expect(tips(carotene).join(' '), isNot(contains('retinol')));
    });

    test('6. verse spirulina: jodium geschat uit gedroogde spirulina (per gram droge stof), niet uit zeewier', () {
      final fresh = ref('ciqual:20982');
      expect(fresh.per100g['iodine'], isNotNull);
      expect(fresh.per100g['iodine']!, lessThan(10));
      expect(fresh.estimated['iodine'], '~ciqual:11086');
    });
  });
}
