import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/allergens.dart';
import 'package:macromatrix/nutrition/coach.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/preferences.dart';
import 'package:macromatrix/nutrition/report.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/platform/ai_request.dart';
import 'package:macromatrix/platform/coach_request.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/features.dart';
import 'package:macromatrix/sync/friends.dart' show mondayOf;
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/coach_panel.dart';

import 'early_access_test.dart' show FakeFeaturesRemote;
import 'pro_test.dart' show FakeProRemote, newState;

/// Nagebootste /api/coach: een vast antwoord of een fout, en wat er verstuurd werd.
class FakeCoach extends CoachRequest {
  final sent = <Map<String, Object?>>[];
  AiException? error;
  PhotoQuota? quota;
  CoachResult result = const CoachResult(
    summary: 'You logged five days and stayed close to your energy goal.',
    tips: ['Add a handful of lentils to a soup or salad twice this week.', 'Have yoghurt with oats at breakfast.'],
  );

  @override
  Future<CoachResult> write(Map<String, Object?> week, {required String token}) async {
    sent.add(week);
    lastQuota = quota;
    if (error case final e?) {
      lastQuota = e.quota;
      throw e;
    }
    return result;
  }
}

final _monday = DateTime(2026, 10, 12);

WeeklyReport _report({int days = 5}) => WeeklyReport(
  monday: _monday,
  score: 64,
  days: days,
  best: const [],
  worst: const [],
  avg: const {
    'energy': 0.91,
    'protein': 0.72,
    'fiber': 0.55,
    'carbs': 0.95,
    'fat': 1.0,
    'vit_d': 0.22,
    'iodine': 0.48,
    'magnesium': 0.61,
    'sodium': 0.4,
    'zinc': 1.2,
  },
  goals: const {'protein': 100, 'fiber': 30, 'carbs': 230, 'fat': 70},
  kcalAvg: 1820,
  kcalGoal: 2000,
  upperShare: const {'sodium': 1.35, 'zinc': 0.5},
  weightStart: 80.4,
  weightEnd: 80.0,
  weightTrend: const WeightTrend(change: -0.6, days: 13, count: 6),
  plan: Goal.lose,
  topFoods: const ['Bread, wholemeal', 'Pasta, cooked'],
  notes: const {'2026-10-13': 'Dinner at Anna\'s place'},
);

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  setUp(() => coachUnavailable = false);

  group('Samenvatting voor de coach', () {
    test('cijfers, tekorten, bovengrens, gewicht en codes', () {
      final w = coachWeek(_report(), diet: {DietPref.vegetarian, DietPref.lactoseFree}, allergies: {Allergen.peanuts}, lang: 'en');
      expect(w['days'], 5);
      expect(w['score'], 64);
      expect(w['goal'], 'lose');
      expect(w['energy'], {'avg': 1820, 'goal': 2000});
      expect((w['macros'] as Map)['protein'], {'avg': 72, 'goal': 100});
      expect((w['macros'] as Map)['fiber'], {'avg': 17, 'goal': 30});
      // Van laag naar hoog, zonder natrium (dat zit boven de grens, niet onder het doel)
      final low = [for (final l in w['low'] as List) (l as Map)['key']];
      expect(low, ['vit_d', 'iodine', 'magnesium']);
      expect((w['low'] as List).first, {'key': 'vit_d', 'name': nutrientByKey['vit_d']!.name, 'pct': 22});
      expect(w['high'], [
        {'key': 'sodium', 'name': nutrientByKey['sodium']!.name, 'pct': 135},
      ]);
      expect(w['weight'], {'change_kg': -0.4, 'trend': 'down'});
      expect(w['diet'], unorderedEquals(['vegetarian', 'lactose_free']));
      expect(w['allergies'], ['peanuts']);
      expect(w['foods'], ['Bread, wholemeal', 'Pasta, cooked']);
      // Notities gaan nooit mee
      expect(jsonEncode(w), isNot(contains('Anna')));
    });

    test('echte week: geen notities, merken of namen van eigen producten', () {
      final s = newState();
      final now = logicalNow();
      final monday = DateTime(mondayOf(now).year, mondayOf(now).month, mondayOf(now).day - 7);
      final bread = s.foods.search('bread', limit: 1).first;
      const mine = Food(
        ref: 'custom:soup-1',
        name: "Grandma Jeanne's secret soup",
        source: FoodSource.custom,
        brand: 'Jeanne',
        per100g: {'energy': 120, 'protein': 6, 'carbs': 12, 'fat': 5},
      );
      final grams = s.targets['energy']!.goal! * 0.6 / (bread.per100g['energy']! / 100);
      for (var i = 0; i < 5; i++) {
        final day = DateTime(monday.year, monday.month, monday.day + i);
        s.setDate(day);
        s.addFood(bread, meal: Meal.lunch, grams: grams, quantity: 1);
        s.addFood(mine, meal: Meal.dinner, grams: 500, quantity: 1);
        s.user.setNote(dayKey(day), 'Felt tired after the party at Marc\'s');
      }
      s.user.setSetting('allergies', {
        'list': ['peanuts'],
      });
      final r = s.weeklyReport(monday)!;
      expect(r.days, 5);
      final text = jsonEncode(coachWeek(r, diet: s.preferences, allergies: s.allergies, lang: 'en'));
      expect(text, isNot(contains('Jeanne')));
      expect(text, isNot(contains('secret')));
      expect(text, isNot(contains('Marc')));
      expect(text, isNot(contains('tired')));
      expect(text, contains('own product'));
      expect(text, contains('"allergies":["peanuts"]'));
      // Koolhydraten, vet en vezels tegenover hun doel
      final w = jsonDecode(text) as Map;
      expect((w['macros'] as Map).keys, containsAll(['protein', 'carbs', 'fat', 'fiber']));
      expect((w['foods'] as List).length, lessThanOrEqualTo(5));
    });

    test('CoachResult: hoogstens 3 tips, lege tips vallen weg', () {
      final r = CoachResult.fromJson({
        'summary': ' Fine week. ',
        'tips': ['a', '', 'b', 'c', 'd', 3],
        'lang': 'nl',
      })!;
      expect(r.summary, 'Fine week.');
      expect(r.tips, ['a', 'b', 'c']);
      expect(r.lang, 'nl');
      expect(CoachResult.fromJson({'summary': 'x', 'tips': []}), isNull);
    });
  });

  group('Paneel in het weekrapport', () {
    late FakeCoach coach;
    setUp(() {
      coach = FakeCoach();
      coachRequest = coach;
      coachToken = (_) => 'tok';
    });

    Future<(AppState, Features)> setup({required bool pro, bool flag = true, bool public = false}) async {
      final s = newState();
      final server = FakeProRemote()
        ..status = pro ? ProStatus(until: DateTime.now().add(const Duration(days: 30)), source: 'manual') : const ProStatus();
      final p = Pro(Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      await p.refresh();
      final now = DateTime.now();
      final fs = FakeFeaturesRemote()
        ..flags = [
          if (flag)
            FeatureFlag(
              id: coachFeature,
              titleEn: 'Weekly coach',
              titleNl: 'Wekelijkse coach',
              earlyFrom: now.subtract(const Duration(days: 1)),
              publicFrom: public ? now.subtract(const Duration(hours: 1)) : DateTime(2026, 11, 14, 12),
            ),
        ];
      final f = Features(p.account, pro: p, remote: () => fs);
      addTearDown(f.dispose);
      await f.refresh();
      return (s, f);
    }

    Future<void> pump(WidgetTester tester, AppState s, Features? f, {WeeklyReport? report}) async {
      tester.view.physicalSize = const Size(412, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: s),
            if (f != null) ChangeNotifierProvider<Features>.value(value: f),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(body: CoachPanel(report: report ?? _report())),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zonder vlaggen, zonder rij of met te weinig dagen: niets', (tester) async {
      final (s, f) = await setup(pro: true, flag: false);
      await pump(tester, s, null);
      expect(find.byKey(const ValueKey('coach-panel')), findsNothing);
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-panel')), findsNothing);
      final (s2, f2) = await setup(pro: true);
      await pump(tester, s2, f2, report: _report(days: 2));
      expect(find.byKey(const ValueKey('coach-panel')), findsNothing);
      expect(find.text('Weekly coach'), findsNothing);
    });

    testWidgets('geen supporter tijdens vroege toegang: een rustige regel met de datum, naar Pro', (tester) async {
      final (s, f) = await setup(pro: false);
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-locked')), findsOneWidget);
      expect(find.textContaining('Supporters get this first; for everyone from 14 November'), findsOneWidget);
      expect(find.byKey(const ValueKey('coach-write')), findsNothing);
      expect(find.byKey(const ValueKey('early-access-chip')), findsNothing);
    });

    testWidgets('supporter: schrijven, tonen en bewaren per week (opnieuw openen kost niets)', (tester) async {
      final (s, f) = await setup(pro: true);
      coach.quota = PhotoQuota(used: 1, limit: 3, pro: true, day: utcDayKey(DateTime.now()));
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('early-access-chip')), findsOneWidget);
      expect(find.textContaining("It can be wrong; it isn't medical advice"), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('coach-write')));
      await tester.pumpAndSettle();
      expect(coach.sent.single['days'], 5);
      expect(find.byKey(const ValueKey('coach-summary')), findsOneWidget);
      expect(find.text('Have yoghurt with oats at breakfast.'), findsOneWidget);
      expect(find.byKey(const ValueKey('coach-again')), findsOneWidget);

      // Opnieuw openen: uit het geheugen van het toestel, geen nieuw verzoek
      await tester.pumpWidget(const SizedBox());
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-summary')), findsOneWidget);
      expect(coach.sent, hasLength(1));
      // Een andere week heeft nog niets
      await pump(
        tester,
        s,
        f,
        report: WeeklyReport(monday: DateTime(2026, 10, 19), score: 50, days: 4, best: const [], worst: const []),
      );
      expect(find.byKey(const ValueKey('coach-write')), findsOneWidget);
    });

    testWidgets('voor iedereen open: geen chip, ook zonder Pro', (tester) async {
      final (s, f) = await setup(pro: false, public: true);
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('early-access-chip')), findsNothing);
    });

    testWidgets('teller op: uitleg en de knop staat uit', (tester) async {
      final (s, f) = await setup(pro: true);
      coach.error = AiException('quota', quota: PhotoQuota(used: 3, limit: 3, pro: true, day: utcDayKey(DateTime.now())));
      await pump(tester, s, f);
      await tester.tap(find.byKey(const ValueKey('coach-write')));
      await tester.pumpAndSettle();
      expect(find.textContaining("today's last one"), findsOneWidget);
      final btn = tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('coach-write')));
      expect(btn.onPressed, isNull);
      // Ook na opnieuw openen weet de app dat het voor vandaag op is
      await tester.pumpWidget(const SizedBox());
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-spent')), findsOneWidget);
    });

    testWidgets('server zonder coach (not_configured): het paneel verdwijnt', (tester) async {
      final (s, f) = await setup(pro: true);
      coach.error = AiException('not_configured');
      await pump(tester, s, f);
      await tester.tap(find.byKey(const ValueKey('coach-write')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await pump(tester, s, f);
      expect(find.byKey(const ValueKey('coach-panel')), findsNothing);
    });

    testWidgets('geen verbinding: een gewone foutmelding, opnieuw proberen kan', (tester) async {
      final (s, f) = await setup(pro: true);
      coach.error = AiException('network');
      await pump(tester, s, f);
      await tester.tap(find.byKey(const ValueKey('coach-write')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('coach-error')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('coach-write'))).onPressed, isNotNull);
    });
  });
}
