import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/preferences.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/profile_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Profiel: dagdoel en beweging (N17), eigen energiedoel tegen het plan (N68), koolhydraten 130 g en "hoogstens"
/// (N24), eiwit en procenten bij een eigen energiedoel (N67), voorkeur met Ongedaan maken (N25).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  AppState newState() => AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  Future<void> pumpProfile(WidgetTester tester, AppState s) async {
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    tester.view.physicalSize = const Size(412, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider(create: (_) => Friends(s, account)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const ProfileScreen()),
      ),
    );
    await tester.pump();
  }

  String note(WidgetTester tester) => tester.widget<Text>(find.byKey(const ValueKey('daily-goal-note'))).data!;

  test('N67: eigen energiedoel verlaagt eiwit niet, en de procenten tellen op tot 100', () {
    const base = Profile(weightKg: 90, heightCm: 180, activity: Activity.moderate);
    final before = targetsFor(base, year: 2026);
    final after = targetsFor(base.copyWith(energyOverride: () => 1900), year: 2026);
    expect(after['protein']!.goal, closeTo(before['protein']!.goal!, 0.01));
    final kcal = after['energy']!.goal!;
    final sum = ['protein', 'carbs', 'fat'].fold(0.0, (a, k) => a + macroShare(k, after[k]!.goal!, kcal));
    expect(sum, closeTo(1, 0.001));
  });

  test('N17: alleen beweging boven het activiteitsniveau komt erbij, ook bij een eigen doel', () {
    const p = Profile(weightKg: 80, activity: Activity.light, energyOverride: 1900);
    final inLevel = exerciseInActivity(p, 2026);
    expect(inLevel, greaterThan(200));
    final s = newState();
    s.saveProfile(p);
    s.addExercise('Walk', inLevel + 150);
    expect(s.exerciseKcalInGoal, closeTo(150, 0.5));
    expect(s.targets['energy']!.goal, closeTo(2050, 0.5));
  });

  testWidgets('N17: dagdoel zegt eerlijk wat er met beweging gebeurt; schakelaar staat in het Profiel', (tester) async {
    final s = newState();
    s.saveProfile(const Profile(weightKg: 80, activity: Activity.light));
    s.addExercise('Walk', 150);
    await pumpProfile(tester, s);
    expect(note(tester), contains('already in your activity level'));
    expect(note(tester), isNot(contains('automatically')));

    final sw = find.byKey(const ValueKey('add-exercise-switch'));
    await tester.ensureVisible(sw);
    await tester.tap(sw);
    await tester.pump();
    expect(s.settings.addExercise, isFalse);
    expect(note(tester), contains('exercise is not added'));
  });

  testWidgets('N68: eigen energiedoel boven het afvalplan geeft een waarschuwing', (tester) async {
    final s = newState();
    final p = const Profile(weightKg: 75, goal: Goal.lose);
    final tdee = formulaTdee(p, DateTime.now().year);
    s.saveProfile(p.copyWith(energyOverride: () => (tdee + 300).roundToDouble()));
    await pumpProfile(tester, s);
    final warn = find.byKey(const ValueKey('override-plan-note'));
    expect(warn, findsOneWidget);
    expect(tester.widget<Text>(warn).data, contains('will not lose weight'));

    // Lager dan het verbruik maar hoger dan het tempo: trager, geen rode waarschuwing
    s.saveProfile(s.profile.copyWith(energyOverride: () => (tdee - 200).roundToDouble()));
    await tester.pump();
    expect(tester.widget<Text>(warn).data, contains('slower than your pace'));
  });

  testWidgets('te snel afvallen: het dagdoel volgt het tempo en het Profiel waarschuwt neutraal', (tester) async {
    final s = newState();
    const p = Profile(
      sex: Sex.female,
      birthYear: 1956,
      weightKg: 60,
      heightCm: 160,
      activity: Activity.sedentary,
      goal: Goal.lose,
      rateKgPerWeek: -0.5,
    );
    s.saveProfile(p);
    await pumpProfile(tester, s);
    expect(s.todayTargets['energy']!.goal, lessThan(1200));
    final note = find.byKey(const ValueKey('pace-warning-note'));
    expect(note, findsOneWidget);
    expect(tester.widget<Text>(note).data, contains('under 1,200 kcal a day'));

    // Een rustiger tempo met meer beweging: geen waarschuwing
    s.saveProfile(s.profile.copyWith(activity: Activity.active, rateKgPerWeek: () => -0.25));
    await tester.pump();
    expect(note, findsNothing);
  });

  testWidgets('N24: 130 g koolhydraten blijft 130 g, en "hoogstens" maakt er een maximum van', (tester) async {
    final s = newState();
    s.saveProfile(const Profile(weightKg: 75));
    await pumpProfile(tester, s);
    final grams = find.byKey(const ValueKey('macro-grams-carbs'));

    Future<void> type(String v, {bool atMost = false}) async {
      await tester.ensureVisible(grams);
      await tester.tap(grams);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, v);
      if (atMost) await tester.tap(find.byKey(const ValueKey('macro-at-most')));
      await tester.pump();
      await tester.tap(find.text('Set'));
      await tester.pumpAndSettle();
    }

    await type('130');
    expect(s.todayTargets['carbs']!.goal, closeTo(130, 0.01));
    expect(find.descendant(of: grams, matching: find.text('130 g')), findsOneWidget);

    await type('130', atMost: true);
    expect(s.settings.overrides['carbs']!.goal, isNull);
    expect(s.settings.overrides['carbs']!.upper, 130);
    expect(find.descendant(of: grams, matching: find.text('≤ 130 g')), findsOneWidget);
  });

  testWidgets('N25: een voorkeur aanzetten toont Ongedaan maken', (tester) async {
    final s = newState();
    await pumpProfile(tester, s);
    final chip = find.text(DietPref.values.first.label);
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
    expect(s.preferences, contains(DietPref.values.first));
    expect(find.text('Undo'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    // Een tik in de eerste halve seconde telt niet (dubbeltik-bescherming)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.preferences, isNot(contains(DietPref.values.first)));
  });
}
