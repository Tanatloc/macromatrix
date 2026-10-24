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

  test('Profiel: doelen van vandaag, ook als een andere dag openstaat; overzichten per dag het doel van toen (N60, N61)', () {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    s.saveProfile(const Profile(weightKg: 80, heightCm: 180, energyOverride: 2700));
    final now = logicalNow();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    s.setDate(yesterday);
    s.addFood(foods.search('banana', limit: 1).first, meal: Meal.lunch, grams: 100, quantity: 1);
    s.saveProfile(s.profile.copyWith(energyOverride: () => 2200));

    expect(s.targets['energy']!.goal, 2700, reason: 'gisteren blijft bevroren');
    expect(s.todayTargets['energy']!.goal, 2200, reason: 'het Profiel toont meteen het nieuwe doel van vandaag');
    final perDay = s.targetsBetween(yesterday, today);
    expect(perDay[dayKey(yesterday)]!['energy']!.goal, 2700);
    expect(perDay[dayKey(today)]!['energy']!.goal, 2200);
  });

  test('suikers: vrije-suikergrens nooit boven je eigen grens; een gewist eigen doel wordt onthouden (N63, N05)', () {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    s.saveProfile(const Profile(energyOverride: 1900));
    expect(s.targets['free_sugars']!.upper, closeTo(47.5, 0.01));
    s.setOverride('sugars', const Target(upper: 30));
    expect(s.targets['free_sugars']!.upper, 30);
    s.setOverride('sugars', null);
    expect(s.lastOverride('sugars')!.upper, 30);
    expect(s.targets['free_sugars']!.upper, closeTo(47.5, 0.01));
  });

  test('alleen een maximum voor koolhydraten: geen verborgen minimum (N24)', () {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    s.setOverride('carbs', const Target(upper: 130));
    expect(s.targets['carbs']!.goal, isNull);
    expect(s.targets['carbs']!.isLimit, isTrue);
  });
}
