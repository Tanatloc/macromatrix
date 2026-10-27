import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/gap_plan.dart';
import 'package:macromatrix/nutrition/health.dart';
import 'package:macromatrix/nutrition/insights.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/report.dart';
import 'package:macromatrix/nutrition/supplements.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/nutrition/values.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/nutrient_detail_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Regressietests voor de rekenfouten uit de review van de voedingsmotor (doel 0, bodem onder het energiedoel, plan
/// per dag, beweging in elke score, dagwissel om 03:00, supplementdagen, zout in de weektip).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  final oldClock = appClock;
  tearDown(() => appClock = oldClock);

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  AppState newState() => AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));

  /// De echte datum van vandaag (de aanmaaktijd van een regel volgt de echte klok, zie countsForXp).
  DateTime realToday() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  group('1. een doel van 0', () {
    test('score, dagscore en plan delen niet door 0', () {
      final t = {...targetsFor(const Profile(), year: 2026), 'vit_c': const Target(goal: 0), 'iron': const Target(goal: 0, upper: 45)};
      const values = {'vit_c': 50.0, 'iron': 10.0, 'energy': 2000.0, 'calcium': 500.0};
      expect(() => completenessScore(values, t), returnsNormally);
      expect(completenessScore(values, t), inInclusiveRange(0, 100));
      expect(completenessScore(const {}, t), inInclusiveRange(0, 100));
      expect(() => dayScore(values, t), returnsNormally);
      // Zonder doel telt vitamine C niet mee: dezelfde score als zonder die stof
      final without = {...t}..remove('vit_c');
      expect(completenessScore(values, t), completenessScore(values, without));
      final plan = planGaps(totals: values, targets: t, kcalLeft: 600, candidates: foods.search('orange', limit: 5));
      for (final i in plan?.items ?? const <PlanItem>[]) {
        expect(i.grams.isFinite, isTrue);
      }
    });

    testWidgets('het doelvenster weigert een minimum van 0', (tester) async {
      final s = newState();
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: NutrientDetailScreen(nutrient: nutrientByKey['vit_c']!),
          ),
        ),
      );
      await tester.pump();
      final set = find.text('Custom goal');
      await tester.scrollUntilVisible(set, 300, scrollable: find.byType(Scrollable).first);
      // Al gebouwd (in de cache onder het scherm) is nog niet zichtbaar
      await tester.ensureVisible(set);
      await tester.pumpAndSettle();
      await tester.tap(set);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'At least (recommended)'), '0');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Must be more than 0'), findsOneWidget);
      expect(s.settings.overrides.containsKey('vit_c'), isFalse);
      // Een echt minimum mag wel
      await tester.enterText(find.widgetWithText(TextField, 'At least (recommended)'), '80');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(s.settings.overrides['vit_c']?.goal, 80);
    });
  });

  group('2. het energiedoel volgt het tempo, met een waarschuwing bij extremen', () {
    test('afvallen aan 1 kg per week: doel volgt het tempo, waarschuwing onder 1200 kcal (vrouw)', () {
      const p = Profile(
        sex: Sex.female,
        birthYear: 1956,
        weightKg: 60,
        heightCm: 160,
        activity: Activity.sedentary,
        goal: Goal.lose,
        rateKgPerWeek: -0.5,
      );
      final raw = (formulaTdee(p, 2026) + p.goalKcal).roundToDouble();
      expect(raw, lessThan(1200));
      expect(energyTarget(p, 2026), raw);
      expect(paceWarning(p, 2026), PaceWarning.low);
      final t = targetsFor(p, year: 2026);
      expect(t['energy']!.goal, raw);
      // Eiwit, koolhydraten en vet samen komen uit op het doel
      final macros = t['protein']!.goal! * 4 + t['carbs']!.goal! * 4 + t['fat']!.goal! * 9;
      expect(macros, closeTo(raw, 1));
      // Een rustig tempo geeft geen waarschuwing
      expect(paceWarning(p.copyWith(activity: Activity.active, rateKgPerWeek: () => -0.25), 2026), isNull);
    });

    test('mannen: waarschuwing onder 1500 kcal, of onder je ruststofwisseling als die hoger ligt', () {
      const big = Profile(
        sex: Sex.male,
        birthYear: 2001,
        weightKg: 84.8,
        heightCm: 184,
        activity: Activity.sedentary,
        goal: Goal.lose,
        rateKgPerWeek: -0.5,
      );
      final rest = bmr(big, big.ageIn(2026)).roundToDouble();
      expect(energyMinimum(big, 2026), rest);
      expect(energyTarget(big, 2026), lessThan(rest));
      expect(paceWarning(big, 2026), PaceWarning.low);
    });

    test('aankomen: waarschuwing boven een halve kilo per week, doel blijft wat het tempo vraagt', () {
      final p = Profile(weightKg: 70, goal: Goal.gain, targetWeightKg: 76, targetDate: DateTime(2026, 7, 1));
      final day = DateTime(2026, 6, 1);
      expect(paceWarning(p, 2026, day: day), PaceWarning.high);
      expect(energyTarget(p, 2026, day: day), greaterThan(formulaTdee(p, 2026) + maxSurplusKcal));
      expect(paceWarning(const Profile(goal: Goal.gain, rateKgPerWeek: 0.25), 2026), isNull);
    });

    test('nooit negatief', () {
      const p = Profile(
        sex: Sex.female,
        birthYear: 1931,
        weightKg: 40,
        heightCm: 140,
        activity: Activity.sedentary,
        goal: Goal.lose,
        rateKgPerWeek: -1.0,
      );
      expect(formulaTdee(p, 2026) + p.goalKcal, lessThan(0), reason: 'het tempo vraagt een negatief doel');
      final t = targetsFor(p, year: 2026);
      expect(t['energy']!.goal, 0);
      for (final e in t.entries) {
        expect(e.value.goal ?? 0, greaterThanOrEqualTo(0), reason: e.key);
        expect(e.value.upper ?? 0, greaterThanOrEqualTo(0), reason: e.key);
      }
    });

    test('een eigen energiedoel blijft zoals je het typte', () {
      const p = Profile(sex: Sex.female, goal: Goal.lose, rateKgPerWeek: -1.0, energyOverride: 1100);
      expect(energyTarget(p, 2026), 1100);
      expect(paceWarning(p, 2026), isNull);
    });
  });

  group('3 en 10. plan met doelgewicht en datum', () {
    test('het doel van een vroegere dag verandert niet meer als de datum dichterbij komt', () {
      appClock = () => DateTime(2026, 6, 1, 12);
      final p = Profile(weightKg: 90, heightCm: 180, goal: Goal.lose, targetWeightKg: 84, targetDate: DateTime(2026, 9, 1));
      final day = DateTime(2026, 5, 31);
      final before = energyTarget(p, 2026, day: day);
      final t = targetsFor(p, year: 2026, day: day);
      appClock = () => DateTime(2026, 7, 20, 12);
      expect(energyTarget(p, 2026, day: day), before);
      expect(targetsFor(p, year: 2026, day: day)['energy']!.goal, t['energy']!.goal);
      // Vandaag vraagt het plan wel meer (minder weken over)
      expect(energyTarget(p, 2026), lessThan(before));
    });

    test('in de app: een gelogde vroegere dag houdt zijn doel, ook weken later', () {
      final today = realToday();
      appClock = () => DateTime(today.year, today.month, today.day, 12);
      final s = newState();
      s.saveProfile(Profile(weightKg: 90, heightCm: 180, goal: Goal.lose, targetWeightKg: 84, targetDate: today.plusDays(70)));
      final yesterday = today.plusDays(-1);
      s.setDate(yesterday);
      s.addFood(foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 100, quantity: 1);
      final before = s.targetsForDate(yesterday)['energy']!.goal;
      appClock = () => DateTime(today.year, today.month, today.day + 42, 12);
      expect(s.targetsForDate(yesterday)['energy']!.goal, before);
    });

    test('een voorbije datum gebruikt het standaardtempo, niet het hoogste', () {
      final now = logicalNow();
      final late = Profile(weightKg: 80, goal: Goal.lose, targetWeightKg: 78, targetDate: DateTime(now.year, now.month, now.day - 10));
      expect(late.rate, Goal.lose.defaultRate);
      expect(late.goalKcal, closeTo(Goal.lose.defaultRate * kcalPerKg / 7, 1e-9));
      final gain = Profile(weightKg: 60, goal: Goal.gain, targetWeightKg: 64, targetDate: DateTime(now.year, now.month, now.day));
      expect(gain.rate, Goal.gain.defaultRate);
    });
  });

  group('4. een dag met beweging heeft overal dezelfde score', () {
    test('Vandaag, XP, weekscore, overzicht en uitdagingen gebruiken dezelfde doelen', () {
      final today = realToday();
      appClock = () => DateTime(today.year, today.month, today.day, 12);
      final s = newState();
      final day = today.plusDays(-1);
      s.setDate(day);
      // ±3100 kcal: zonder de training ver boven je doel, met de training er ongeveer op
      s.addFood(foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 3500, quantity: 1);
      final key = dayKey(day);
      final withoutExercise = s.dayStats[key]!.score;
      s.addExercise('Running', 1000, minutes: 90);
      expect(s.exerciseKcalInGoal, greaterThan(0));
      final todayView = dayScore(s.totals.values, s.targets);
      expect(todayView, isNot(withoutExercise), reason: 'de training verandert de score');
      expect(s.dayStats[key]!.score, todayView, reason: 'XP en battlepunten (cache met beweging)');
      expect(s.weekScore(mondayOf(day))!.score, todayView);
      expect(s.recap(day, day, year: false)!.dayScores[key], todayView);
      expect(s.targetsBetween(day, day)[key]!['energy']!.goal, s.targets['energy']!.goal);
      expect(s.targetsWithExercise(day)['energy']!.goal, s.targets['energy']!.goal);
    });
  });

  test('5. om 03:00 sluit gisteren af, ook in de bewaarde XP-scores', () {
    final today = realToday();
    appClock = () => DateTime(today.year, today.month, today.day, 22);
    final s = newState();
    // Weinig gegeten: een afgesloten dag verliest punten door de energiefactor
    s.addFood(foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 100, quantity: 1);
    final key = dayKey(today);
    final open = s.dayStats[key]!.score;
    expect(open, s.dayStats[key]!.micro, reason: 'vandaag telt energie nog niet mee');
    appClock = () => DateTime(today.year, today.month, today.day + 1, 4);
    final closed = s.dayStats[key]!.score;
    expect(closed, lessThan(open));
    expect(closed, s.weekScore(mondayOf(today))!.score);
  });

  group('7 en 8. dagen met alleen supplementen', () {
    test('tellen niet mee in de weekscore en in het maandoverzicht', () {
      final today = realToday();
      appClock = () => DateTime(today.year, today.month, today.day, 12);
      final s = newState();
      final monday = mondayOf(today).plusDays(-7);
      s.setDate(monday);
      s.addFood(foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 300, quantity: 1);
      final foodScore = dayScore(s.totals.values, s.targets);
      final kcal = s.totals['energy'];
      final vitD = supplementCatalog.firstWhere((x) => x.id == 'vitd25');
      for (var i = 1; i < 7; i++) {
        s.user.setSupplementTaken(dayKey(monday.plusDays(i)), vitD, true);
      }
      final week = s.weekScore(monday)!;
      expect(week.days, 1);
      expect(week.score, foodScore);
      final recap = s.recap(monday, monday.plusDays(6), year: false)!;
      expect(recap.daysLogged, 1);
      expect(recap.avgKcal, kcal.round());
      expect(recap.avgScore, foodScore);
      expect(recap.longestStreak, 1);
      expect(recap.dayScores.keys, [dayKey(monday)]);
    });
  });

  test('9. weektip: met te veel zout geen product met merkbaar natrium', () {
    final today = realToday();
    appClock = () => DateTime(today.year, today.month, today.day, 12);
    final s = newState();
    final monday = mondayOf(today).plusDays(-7);
    // Een dagmenu dat alles ruim haalt behalve vitamine D, met 3 g natrium (boven de limiet van 2 g): de tip gaat dan
    // over vitamine D, en zalm uit blik (±330 mg natrium per portie) mag niet meer
    final t = s.targets;
    final per100g = <String, double>{
      for (final k in stripKeys)
        if (t[k]?.goal case final g?) k: g * 1.1 / 10,
      'vit_d': 0,
      'sodium': 300,
      'energy': t['energy']!.goal! / 10,
      'protein': t['protein']!.goal! * 1.1 / 10,
      'carbs': t['carbs']!.goal! / 10,
      'fat': t['fat']!.goal! / 10,
      'fiber': 3,
    };
    final menu = Food(ref: 'custom:menu', name: 'Day menu', source: FoodSource.custom, per100g: per100g);
    for (var i = 0; i < 7; i++) {
      s.setDate(monday.plusDays(i));
      s.addFood(menu, meal: Meal.lunch, grams: 1000, quantity: 1);
    }
    final r = s.weeklyReport(monday)!;
    expect(r.days, 7);
    expect(r.worst.first.$1.key, 'vit_d');
    final tip = r.tip;
    if (tip != null) {
      expect(tip.nutrient.key, 'vit_d');
      final sodium = (withDerived(tip.food.per100g)['sodium'] ?? 0) * tip.grams / 100;
      expect(sodium, lessThanOrEqualTo(tipSodiumMaxWhenHigh), reason: '${tip.food.name}: ${sodium.round()} mg natrium');
    }
  });

  test('energieadvies: afgerond op honderdtallen met duizendtallen', () {
    final m = energyMessage(EnergyCase.over, eaten: 3650, goal: 2400);
    expect(m.advice, contains('1,300'));
    expect(m.advice, isNot(contains('1300')));
  });

  test('scoreEnergyNote volgt de klok van de app', () {
    final t = targetsFor(const Profile(energyOverride: 2000), year: 2026);
    const values = {'energy': 800.0};
    appClock = () => DateTime(2026, 10, 22, 21);
    expect(scoreEnergyNote(values, t, closed: false), isNotNull, reason: '\'s avonds ver onder je doel');
    appClock = () => DateTime(2026, 10, 22, 10);
    expect(scoreEnergyNote(values, t, closed: false), isNull, reason: '\'s ochtends nog niets te melden');
  });
}
