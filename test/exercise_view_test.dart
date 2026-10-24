import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart' show addExercise;
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';
import 'package:macromatrix/ui/widgets/exercise_view.dart';

/// De app met één dag beweging, zodat de vensters met de echte toestand getekend worden.
AppState _state({required bool watch}) {
  final user = UserDb(sqlite3.openInMemory());
  // Zelfde 'vandaag' als de app: na middernacht hoort het nog bij de vorige dag
  final day = dayKey(logicalNow());
  user.setSetting('profile', const Profile(weightKg: 88, heightCm: 184).toJson());
  if (watch) {
    user.insertExerciseOnce(id: 'hc:abc', day: day, name: 'Lopen', kcal: 452, minutes: 42);
  } else {
    user.addExercise(day: day, name: 'Hardlopen (10 km/u)', kcal: 515, minutes: 40);
  }
  return AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: user,
  );
}

Future<void> _pump(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(onPressed: () => openDayExercise(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => setAppLang(AppLang.nl));
  tearDown(() => setAppLang(AppLang.en));

  testWidgets('beweging openen: wat ze opbrengt en wat je doel daardoor wordt', (tester) async {
    final state = _state(watch: false);
    await _pump(tester, state);

    // Eén activiteit: meteen de details.
    expect(find.text('Hardlopen (10 km/u)'), findsOneWidget);
    expect(find.text('515 kcal'), findsOneWidget);
    expect(find.text('zelf toegevoegd'), findsOneWidget);
    expect(find.text('40 min'), findsOneWidget);
    expect(find.textContaining('kcal/min'), findsOneWidget);

    // Het doel loopt met de beweging mee op.
    final budget = state.targets['energy']!.goal!;
    expect(find.text(fmtInt(budget)), findsOneWidget);
    // De beweging die boven je activiteitsniveau uitkomt, komt bij je doel
    expect(find.text('+${fmtInt(state.exerciseKcalInGoal)}'), findsOneWidget);
  });

  testWidgets('beweging van het horloge vertelt over het rustverbruik', (tester) async {
    final state = _state(watch: true);
    await _pump(tester, state);

    expect(find.text('van je horloge, via Health Connect'), findsOneWidget);
    expect(find.textContaining('rustverbruik'), findsOneWidget);
  });

  group('beweging toevoegen', () {
    Future<void> openAdd(WidgetTester tester, AppState state) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: state,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(onPressed: () => addExercise(context), child: const Text('add')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
    }

    TextEditingController field(WidgetTester tester, String label) => tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!;
    const minutesLabel = 'Duur', kcalLabel = 'Verbrand (leeg = schatting)';

    Future<void> pick(WidgetTester tester, String activity) async {
      await tester.tap(find.byType(DropdownButtonFormField<Object>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(activity).last);
      await tester.pumpAndSettle();
      // De korte pauze na het openen van de lijst laten aflopen
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('opent leeg, ook als je eerder iets deed (N66)', (tester) async {
      await openAdd(tester, _state(watch: false));
      // De vorige activiteit staat als knop klaar, maar is niet ingevuld
      expect(find.text('Hardlopen (10 km/u) · 40 min'), findsOneWidget);
      expect(find.text('Kies een activiteit'), findsOneWidget);
      expect(field(tester, minutesLabel).text, '30');
      expect(field(tester, kcalLabel).text, '');

      // Zonder activiteit en zonder kcal: een melding in het venster, niets bewaard
      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(find.text('Beweging toevoegen'), findsOneWidget);
      expect(find.text('Kies een activiteit'), findsNWidgets(2));
    });

    testWidgets('Opnieuw vult de velden in en voegt pas toe na Toevoegen, met Ongedaan maken (N19)', (tester) async {
      final state = _state(watch: false);
      await openAdd(tester, state);
      await tester.tap(find.text('Hardlopen (10 km/u) · 40 min'));
      await tester.pumpAndSettle();
      expect(state.exercise, hasLength(1));
      expect(find.text('Beweging toevoegen'), findsOneWidget);
      expect(field(tester, minutesLabel).text, '40');
      expect(field(tester, kcalLabel).text, '515');

      // Kortere duur: de kcal schaalt mee
      await tester.enterText(find.widgetWithText(TextField, minutesLabel), '20');
      await tester.pump();
      expect(field(tester, kcalLabel).text, '258');

      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(state.exercise, hasLength(2));
      expect(state.exercise.where((e) => e.minutes == 20 && e.kcal == 258), hasLength(1));
      expect(find.text('Hardlopen (10 km/u) · 20 min toegevoegd'), findsOneWidget);

      // Ongedaan maken negeert een tik in de eerste halve seconde (echte tijd)
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
      await tester.tap(find.text('Ongedaan maken'));
      await tester.pumpAndSettle();
      expect(state.exercise, hasLength(1));
    });

    testWidgets('andere activiteit: de overgenomen kcal valt weg, zelf getypte blijft (N30)', (tester) async {
      await openAdd(tester, _state(watch: false));
      await tester.tap(find.text('Hardlopen (10 km/u) · 40 min'));
      await tester.pumpAndSettle();
      expect(field(tester, kcalLabel).text, '515');

      await pick(tester, 'Fietsen (rustig, 16-19 km/u)');
      expect(field(tester, kcalLabel).text, '');
      expect(find.textContaining('Schatting:'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, kcalLabel), '400');
      await pick(tester, 'Hardlopen (8 km/u)');
      expect(field(tester, kcalLabel).text, '400');
    });

    testWidgets('99.999 minuten wordt geweigerd (N66)', (tester) async {
      final state = _state(watch: false);
      await openAdd(tester, state);
      await pick(tester, 'Wandelen (rustig, 4 km/u)');
      await tester.enterText(find.widgetWithText(TextField, minutesLabel), '99999');
      await tester.enterText(find.widgetWithText(TextField, kcalLabel), '99999');
      await tester.tap(find.text('Toevoegen'));
      await tester.pumpAndSettle();
      expect(find.text('Een dag telt 1.440 minuten'), findsOneWidget);
      expect(find.textContaining('niet realistisch'), findsOneWidget);
      expect(state.exercise, hasLength(1));
    });
  });

  testWidgets('aanpassen weigert ook 99.999 minuten', (tester) async {
    final state = _state(watch: false);
    await _pump(tester, state);
    await tester.tap(find.text('Aanpassen'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Duur'), '99999');
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();
    expect(find.text('Een dag telt 1.440 minuten'), findsOneWidget);
    expect(state.exercise.single.minutes, 40);
  });

  test('grenzen voor beweging', () {
    expect(exerciseMinutesError(90), isNull);
    expect(exerciseMinutesError(1440), isNull);
    expect(exerciseMinutesError(1441), isNotNull);
    expect(exerciseMinutesError(1000, otherMinutes: 500), isNotNull);
    expect(exerciseKcalError(800, 60), isNull);
    expect(exerciseKcalError(800, null), isNull);
    // 3000 kcal in 30 minuten: 100 kcal per minuut
    expect(exerciseKcalError(3000, 30), isNotNull);
    expect(exerciseKcalError(16000, null), isNotNull);
    expect(exerciseKcalError(9000, 600, otherKcal: 7000), isNotNull);
  });
}
