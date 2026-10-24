import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/oracle_screen.dart';
import 'package:macromatrix/ui/theme.dart';

AppState newState() => AppState(
  foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
  user: UserDb(sqlite3.openInMemory()),
);

/// Wat nooit in een "minst"-lijst mag staan: water, gewone thee en koffie, zout, kruiden, zoetstoffen.
final _noise = RegExp(
  r'^((bottled|mineral|tap|spring) )?water(,|$)|^((table|sea|mineral) )?salt\b|\b(sweetener|aspartame|stevia|sucralose|espresso)\b|^(tea|coffee)\b',
  caseSensitive: false,
);

void expectAscending(List<(Food, double)> r) {
  for (var i = 1; i < r.length; i++) {
    expect(r[i - 1].$2, lessThanOrEqualTo(r[i].$2), reason: r[i].$1.name);
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });

  // N97: brood of ontbijtgranen met de minste suiker of koolhydraten
  test('least sugar in bread: everyday bread, lowest first, per 100 g', () {
    final s = newState();
    final relaxed = <String>{};
    final r = s.oracle('sugars', groups: {'bread'}, limit: 10, everyday: true, least: true, relaxed: relaxed);
    expect(r, hasLength(10));
    expect(relaxed, isEmpty);
    expectAscending(r);
    for (final (f, v) in r) {
      expect(f.label?.group, 'bread');
      expect(v, closeTo(f.per100g['sugars']!, 1e-9));
      expect(f.per100g['energy'], greaterThanOrEqualTo(AppState.oracleLeastMinKcal));
    }
    // Het minst is ook echt minder dan het meest
    final most = s.oracle('sugars', groups: {'bread'}, limit: 10, everyday: true);
    expect(r.last.$2, lessThan(most.last.$2));
  });

  test('least over all groups: no water, tea, coffee, salt, spices, sweeteners or near-zero energy', () {
    final s = newState();
    for (final key in const ['sugars', 'carbs', 'sodium', 'fat']) {
      for (final everyday in const [true, false]) {
        final r = s.oracle(key, limit: 50, everyday: everyday, least: true);
        expect(r, isNotEmpty, reason: key);
        expectAscending(r);
        for (final (f, _) in r) {
          expect(f.per100g['energy'], greaterThanOrEqualTo(AppState.oracleLeastMinKcal), reason: f.name);
          expect(f.label?.group, isNot('herb/spice'), reason: f.name);
          expect(f.label?.group, isNot('supplement'), reason: f.name);
          expect(_noise.hasMatch(f.name), isFalse, reason: f.name);
        }
      }
    }
  });

  test('least per serving and per 100 kcal stay sorted and inside the chosen groups', () {
    final s = newState();
    final portion = s.oracle('carbs', groups: {'breakfast cereal'}, rank: OracleRank.perPortion, limit: 10, everyday: true, least: true);
    expect(portion, isNotEmpty);
    expectAscending(portion);
    for (final (f, v) in portion) {
      expect(f.label?.group, 'breakfast cereal');
      expect(v, closeTo(f.per100g['carbs']! * AppState.oraclePortion(f) / 100, 1e-9));
    }
    final kcal = s.oracle('carbs', groups: {'fruit', 'vegetable'}, rank: OracleRank.per100kcal, limit: 10, everyday: true, least: true);
    expect(kcal, isNotEmpty);
    expectAscending(kcal);
    expect(kcal.every((r) => const {'fruit', 'vegetable'}.contains(r.$1.label?.group)), isTrue);
  });

  test('herbs only when you pick that group yourself', () {
    final s = newState();
    final r = s.oracle('sugars', groups: {'herb/spice'}, limit: 10, least: true);
    expect(r, isNotEmpty);
    expect(r.every((x) => x.$1.label?.group == 'herb/spice'), isTrue);
  });

  test('noise filter', () {
    Food f(String name) => Food(ref: 'x', name: name, source: FoodSource.custom, per100g: const {'energy': 50});
    for (final n in ['Aspartame sweetener, in tablets', 'Coffee, instant, powder', 'Tea, black, infusion', 'Cola, with sweetener(s)']) {
      expect(AppState.isOracleLeastNoise(f(n)), isTrue, reason: n);
    }
    for (final n in ['Bread, wholemeal', 'Tea cake, toasted', 'Coffee, infusion, with milk', 'Steak, grilled']) {
      expect(AppState.isOracleLeastNoise(f(n)), isFalse, reason: n);
    }
  });

  testWidgets('sugar focus: least by default for sugars, most for protein, and switchable', (tester) async {
    final s = newState()..setSugarFocus(true);
    tester.view.physicalSize = const Size(1440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Future<void> open(String key) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: OracleScreen(key: ValueKey(key), nutrient: key),
          ),
        ),
      );
      await tester.pump();
    }

    await open('sugars');
    expect(find.textContaining('Laagste '), findsOneWidget);
    expect(find.textContaining('Top '), findsNothing);
    await tester.tap(find.text('Meeste'));
    await tester.pump();
    expect(find.textContaining('Top '), findsOneWidget);
    expect(find.textContaining('Laagste '), findsNothing);

    await open('protein');
    expect(find.textContaining('Top '), findsOneWidget);
    await tester.tap(find.text('Minste'));
    await tester.pump();
    expect(find.textContaining('Laagste '), findsOneWidget);
    expect(find.textContaining('Top 0'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
