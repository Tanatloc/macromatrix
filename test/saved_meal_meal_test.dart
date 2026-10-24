import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/add_food_screen.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/theme.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  const item = ItemTemplate(foodRef: 'ciqual:13005', name: 'Banana', grams: 120, quantity: 120, per100g: {'energy': 90});

  test('opgeslagen maaltijd onthoudt zijn maaltijd', () {
    final db = UserDb(sqlite3.openInMemory());
    db.saveMeal('Kipcurry', [item], meal: Meal.dinner);
    db.saveMeal('Iets', [item]);
    final meals = {for (final m in db.savedMeals()) m.name: m};
    expect(meals['Kipcurry']!.mealIndex, Meal.dinner.index);
    expect(meals['Iets']!.mealIndex, isNull);
    // Ook via de synchronisatie
    final t = UserDb.syncTables.firstWhere((t) => t.name == 'meals');
    // Gaat pas mee naar de server zodra de migratie daar staat (syncSavedMealMeal)
    if (syncSavedMealMeal) expect(db.dirtyRows(t).firstWhere((r) => r['name'] == 'Kipcurry')['meal'], Meal.dinner.index);
  });

  test('oude databank zonder kolom meal: migratie en oude rijen laden nog', () {
    final raw = sqlite3.openInMemory();
    UserDb(raw);
    // Terug naar het schema van versie 4: kolom weg, een oude rij erin
    raw.execute('ALTER TABLE meals DROP COLUMN meal; PRAGMA user_version = 4;');
    raw.execute("INSERT INTO meals (id, name, items, updated_at, deleted) VALUES ('old', 'Ontbijt', '[]', 1, 0)");
    final db = UserDb(raw);
    final m = db.savedMeals().single;
    expect(m.mealIndex, isNull);
    expect(savedMealTarget(m, Meal.lunch), Meal.breakfast); // naam
    // Een rij van een oudere app via de synchronisatie (zonder 'meal')
    final t = UserDb.syncTables.firstWhere((t) => t.name == 'meals');
    db.applyRemote(t, {'id': 'r', 'name': 'Kipcurry', 'items': '[]', 'updated_at': 5, 'deleted': 0});
    expect(db.savedMeals().firstWhere((m) => m.id == 'r').mealIndex, isNull);
    // Nog een keer openen verandert niets
    expect(() => UserDb(raw), returnsNormally);
  });

  test('doel en volgorde van opgeslagen maaltijden', () {
    const stored = SavedMeal(id: 'a', name: 'Ontbijt', items: [], mealIndex: 2);
    const named = SavedMeal(id: 'b', name: 'Lunch box', items: []);
    const plain = SavedMeal(id: 'c', name: 'Kipcurry', items: []);
    expect(savedMealTarget(stored, Meal.lunch), Meal.dinner); // opgeslagen maaltijd wint van de naam
    expect(savedMealTarget(named, Meal.dinner), Meal.lunch);
    expect(savedMealTarget(plain, Meal.snacks), Meal.snacks);
    expect(sortSavedMeals([plain, named, stored], Meal.dinner).map((m) => m.id), ['a', 'c', 'b']);
    expect(sortSavedMeals([plain, stored, named], Meal.lunch).map((m) => m.id), ['b', 'c', 'a']);
  });

  Future<AppState> pump(WidgetTester tester, void Function(AppState s) setup) async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    );
    setup(s);
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const DiaryScreen()),
      ),
    );
    await tester.pump();
    return s;
  }

  testWidgets('Begin je dag: opgeslagen maaltijd gaat naar zijn eigen maaltijd', (tester) async {
    // Een maaltijd die niet de voorgestelde is (die hangt van het uur af)
    late Meal target;
    final s = await pump(tester, (s) {
      target = Meal.values.firstWhere((m) => m != s.suggestedMeal);
      s.user.saveMeal('Kipcurry', [item], meal: target);
    });
    await tester.tap(find.text('Kipcurry'));
    await tester.pump();
    expect(s.entriesFor(target), hasLength(1));
    expect(s.entriesFor(s.suggestedMeal), isEmpty);
  });

  testWidgets('Meestal bij: opnieuw toevoegen kan ongedaan gemaakt worden', (tester) async {
    final s = await pump(tester, (s) {
      final banana = s.foods.search('banana', limit: 1).first;
      // Niet op opeenvolgende dagen: geen reeks-badge nodig in deze test
      for (final d in [3, 5, 7]) {
        s.user.addEntry(
          day: dayKey(s.date.subtract(Duration(days: d))),
          meal: s.suggestedMeal,
          food: banana,
          grams: 120,
          quantity: 120,
        );
      }
    });
    final meal = s.suggestedMeal;
    expect(s.usualFor(meal), hasLength(1));
    await tester.tap(find.byType(ActionChip).first);
    await tester.pump();
    expect(s.entriesFor(meal), hasLength(1));
    await tester.pump(const Duration(seconds: 1)); // melding schuift in beeld
    expect(find.text('Undo'), findsOneWidget);
    // Een tik in de eerste halve seconde telt niet als ongedaan maken (dubbeltik-bescherming)
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 600)));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(s.entriesFor(meal), isEmpty);
  });
}
