import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';

/// Een nieuw doel verandert vorige dagen niet meer met terugwerkende kracht (P86, P185, P128).
void main() {
  test('vorige dagen houden de doelen van toen, vandaag volgt het nieuwe doel', () {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    s.saveProfile(const Profile(weightKg: 80, heightCm: 180));
    final today = logicalNow();
    final yesterday = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 1));
    final food = foods.search('banana', limit: 1).first;
    s.setDate(yesterday);
    s.addFood(food, meal: Meal.lunch, grams: 100, quantity: 1);

    final before = s.targetsForDate(yesterday)['protein']!.goal!;
    // Eiwitrijk schema en een keto-maandag voor elke weekdag: zou gisteren anders volledig herberekenen
    s.saveProfile(s.profile.copyWith(proteinPct: 35, carbsPct: 35, fatPct: 30));
    s.saveSettings(s.settings.copyWith(schedule: {for (var d = 1; d <= 7; d++) d: (20.0, 5.0, 75.0)}));

    expect(s.targetsForDate(yesterday)['protein']!.goal!, closeTo(before, 0.01));
    expect(s.targetsForDate(yesterday)['carbs']!.goal!, greaterThan(100), reason: 'gisteren geen keto met terugwerkende kracht');
    expect(s.targetsForDate(today)['carbs']!.goal!, lessThan(60), reason: 'vandaag volgt het nieuwe schema');
  });
}
