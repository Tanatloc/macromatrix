import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';
import 'package:macromatrix/ui/widgets/exercise_view.dart';

/// De app met één dag beweging, zodat de vensters met de echte toestand getekend worden.
AppState _state({required bool watch}) {
  final user = UserDb(sqlite3.openInMemory());
  final day = dayKey(DateTime.now());
  user.setSetting('profile', const Profile(weightKg: 88, heightCm: 184).toJson());
  if (watch) {
    user.insertExerciseOnce(id: 'hc:abc', day: day, name: 'Lopen', kcal: 452, minutes: 42);
  } else {
    user.addExercise(day: day, name: 'Hardlopen (10 km/u)', kcal: 515, minutes: 40);
  }
  return AppState(foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)), user: user);
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
}
