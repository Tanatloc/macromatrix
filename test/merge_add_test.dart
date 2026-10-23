import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/state/app_state.dart';

/// Twee keer hetzelfde product toevoegen geeft één regel met de som, en ongedaan maken zet de vorige hoeveelheid terug (P179).
void main() {
  late AppState s;
  late FoodDb foods;
  setUp(() {
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });

  test('zelfde product, maaltijd en portie: één regel met opgetelde hoeveelheid', () {
    final oats = foods.search('oats', limit: 1).first;
    final first = s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    final second = s.addFood(oats, meal: Meal.breakfast, grams: 40, quantity: 40);
    expect(first.merged, isFalse);
    expect(second.merged, isTrue);
    expect(second.id, first.id);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.grams, 100);
    expect(s.entries.single.quantity, 100);

    // Ongedaan maken van de tweede: terug naar 60 g, de regel blijft
    s.undoAdds([second]);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.id, first.id);
    expect(s.entries.single.grams, 60);
    expect(s.entries.single.quantity, 60);

    // Ongedaan maken van de eerste: regel weg
    s.undoAdds([first]);
    expect(s.entries, isEmpty);
  });

  test('portie: aantallen worden opgeteld', () {
    final banana = foods.search('banana', limit: 1).first;
    s.addFood(banana, meal: Meal.lunch, grams: 120, quantity: 1, portionLabel: 'medium');
    s.addAgain(s.entries.single, Meal.lunch);
    expect(s.entries, hasLength(1));
    expect(s.entries.single.grams, 240);
    expect(s.entries.single.quantity, 2);
  });

  test('snel loggen: twee keer hetzelfde in één keer, alles ongedaan maken', () {
    final oats = foods.search('oats', limit: 1).first;
    final added = [
      s.addFood(oats, meal: Meal.breakfast, grams: 30, quantity: 30),
      s.addFood(oats, meal: Meal.breakfast, grams: 20, quantity: 20),
    ];
    expect(s.entries.single.grams, 50);
    s.undoAdds(added);
    expect(s.entries, isEmpty);
  });

  test('andere maaltijd, portie, dag of eigen tijd: aparte regels', () {
    final oats = foods.search('oats', limit: 1).first;
    s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    s.addFood(oats, meal: Meal.lunch, grams: 60, quantity: 60);
    s.addFood(oats, meal: Meal.breakfast, grams: 40, quantity: 1, portionLabel: 'cup');
    expect(s.entries, hasLength(3));

    // Eerst een regel met een eigen tijd, dan een met een andere tijd: niet samenvoegen
    s.addFood(oats, meal: Meal.dinner, grams: 50, quantity: 50, time: '18:00');
    s.addFood(oats, meal: Meal.dinner, grams: 50, quantity: 50, time: '19:30');
    expect(s.entriesFor(Meal.dinner), hasLength(2));
    // Zelfde tijd wel
    s.addFood(oats, meal: Meal.dinner, grams: 10, quantity: 10, time: '18:00');
    expect(s.entriesFor(Meal.dinner), hasLength(2));

    s.shiftDay(-1);
    s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    expect(s.entries, hasLength(1));
  });
}
