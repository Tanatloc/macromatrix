import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/nutrients.dart';
import 'package:macromatrix/nutrition/report.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/recap_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/share_actions.dart';
import 'package:macromatrix/ui/widgets/share_cards.dart';
import 'package:macromatrix/ui/widgets/share_sheet.dart';

/// Deelkaarten: elke kaart past zonder overloop op 1080 × 1350, in licht en donker, in beide talen, ook met alle
/// vinkjes aan en met lange namen. Het voorbeeld toont gewicht pas als je het aanvinkt.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_GB');
    await initializeDateFormatting('nl_BE');
  });
  tearDown(() => setAppLang(AppLang.en));

  const profile = ShareProfile(avatar: 'preset:3', level: 42);
  const all = {ShareShow.profile, ShareShow.energy, ShareShow.weight, ShareShow.topFood};

  Recap recap({bool year = false}) {
    final from = year ? DateTime(2026) : DateTime(2026, 9);
    return Recap(
      from: from,
      to: year ? DateTime(2026, 12, 31) : DateTime(2026, 9, 30),
      year: year,
      daysLogged: 26,
      daysInPeriod: year ? 365 : 30,
      distinctFoods: 1234,
      entries: 300,
      topFoods: const [('Volkoren boterham met extra belegen kaas en tomaat van de markt', 22)],
      avgScore: 87,
      longestStreak: 123,
      xp: 123456,
      avgKcal: 2345,
      dayScores: {
        for (var d = 1; d <= 30; d++)
          if (d % 5 != 0) '2026-${year ? '0${(d % 9) + 1}' : '09'}-${d.toString().padLeft(2, '0')}': 40 + d * 2,
      },
      previous: Recap(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
        year: false,
        daysLogged: 20,
        daysInPeriod: 31,
        distinctFoods: 50,
        entries: 100,
        topFoods: const [],
        avgScore: 80,
        longestStreak: 9,
        xp: 1000,
        avgKcal: 2000,
      ),
    );
  }

  WeeklyReport week() => WeeklyReport(
    monday: DateTime(2026, 9, 14),
    score: 91,
    prevScore: 85,
    days: 6,
    best: [(nutrientByKey['vit_c']!, 2.4), (nutrientByKey['b12']!, 1.6), (nutrientByKey['pantothenic_acid'] ?? nutrientByKey['magnesium']!, 1.1)],
    worst: [(nutrientByKey['vit_d']!, 0.3)],
    kcalAvg: 2210,
    kcalGoal: 2400,
    weightStart: 81.4,
    weightEnd: 80.8,
  );

  final cards = <String, Widget Function(Set<String>)>{
    'recap': (show) => RecapShareCard(recap: recap(), show: show, profile: profile),
    'year': (show) => RecapShareCard(recap: recap(year: true), show: show, profile: profile),
    'streak': (show) =>
        StreakShareCard(days: 1234, longest: 1234, recent: List.generate(14, (i) => i.isEven), totalDays: 2000, show: show, profile: profile),
    'badge': (show) => GoalShareCard.badge(category: 'omega', tier: 5, value: 60, show: show, profile: profile),
    'micros': (show) => GoalShareCard.allMicros(reached: 24, total: 24, day: DateTime(2026, 9, 23), show: show, profile: profile),
    'week': (show) => WeekShareCard(report: week(), dayScores: const [88, 92, null, 95, 71, 100, 64], streak: 1234, show: show, profile: profile),
  };

  Future<void> pumpCard(WidgetTester tester, Widget card, {required bool dark}) async {
    tester.view.physicalSize = shareCardSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Align(
          alignment: Alignment.topLeft,
          child: shareCardThemed(card, dark: dark),
        ),
      ),
    );
    await tester.pump();
  }

  for (final e in cards.entries) {
    testWidgets('kaart ${e.key} past zonder overloop (licht/donker, EN/NL, met en zonder vinkjes)', (tester) async {
      for (final lang in AppLang.values) {
        setAppLang(lang);
        for (final dark in [false, true]) {
          for (final show in [<String>{}, all]) {
            await pumpCard(tester, e.value(show), dark: dark);
            expect(tester.takeException(), isNull, reason: '${e.key} $lang dark=$dark show=$show');
            expect(tester.getSize(find.byType(ShareCardFrame)), shareCardSize);
            expect(find.text('macromatrix.eu'), findsOneWidget);
            expect(find.text('MacroMatrix'), findsOneWidget);
          }
        }
      }
    });
  }

  testWidgets('persoonlijke gegevens alleen met vinkje', (tester) async {
    await pumpCard(tester, cards['week']!({}), dark: false);
    expect(find.textContaining('kg'), findsNothing);
    expect(find.text('2,210'), findsNothing);
    await pumpCard(tester, cards['week']!({ShareShow.weight, ShareShow.energy}), dark: false);
    expect(find.text('−0.6 kg'), findsOneWidget);
    expect(find.text('2,210'), findsOneWidget);
  });

  testWidgets('buiten beeld tekenen geeft een PNG van 1080 × 1350', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final view = tester.view;
    for (final dark in [false, true]) {
      final png = (await tester.runAsync(() => renderShareCard(cards['streak']!({}), view: view, dark: dark)))!;
      expect(png.sublist(1, 4), 'PNG'.codeUnits);
      final header = ByteData.sublistView(png, 16, 24);
      expect(header.getUint32(0), 1080);
      expect(header.getUint32(4), 1350);
    }
  });

  testWidgets('voorbeeld: gewicht en profiel pas na aanvinken', (tester) async {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => shareWeek(context, week(), copyText: 'x'),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final preview = find.byKey(const Key('share-preview'));
    expect(preview, findsOneWidget);
    expect(find.descendant(of: preview, matching: find.text('−0.6 kg')), findsNothing);
    expect(find.descendant(of: preview, matching: find.byType(ShareCardFrame)), findsOneWidget);

    // Alle vinkjes staan standaard uit
    for (final id in [ShareShow.energy, ShareShow.weight, ShareShow.profile]) {
      expect(tester.widget<CheckboxListTile>(find.byKey(Key('share-toggle-$id'))).value, isFalse);
    }
    await tester.tap(find.byKey(const Key('share-toggle-${ShareShow.weight}')));
    await tester.pump();
    expect(find.descendant(of: preview, matching: find.text('−0.6 kg')), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-toggle-${ShareShow.weight}')));
    await tester.pump();
    expect(find.descendant(of: preview, matching: find.text('−0.6 kg')), findsNothing);

    // Donker kiezen verandert de achtergrond van de kaart
    Color bg() => (tester.widget<Container>(find.descendant(of: find.byType(ShareCardFrame), matching: find.byType(Container)).first).color)!;
    expect(bg(), Palette.light.bg);
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(bg(), Palette.dark.bg);
    expect(find.byKey(const Key('share-go')), findsOneWidget);
    expect(find.text('Copy text'), findsOneWidget);
  });

  testWidgets('maandoverzicht: "Delen als afbeelding" opent het voorbeeld', (tester) async {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    final now = logicalNow();
    final apple = foods.search('apple', limit: 1).first;
    for (var i = 0; i < 3; i++) {
      s.setDate(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
      s.addFood(apple, meal: Meal.breakfast, grams: 150, quantity: 1);
    }
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final from = DateTime(now.year, now.month);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: s,
        child: MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: RecapScreen(from: from, year: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recap-share')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(RecapShareCard), findsOneWidget);
    // Wat je het vaakst at staat standaard aan, energie en profiel niet
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('share-toggle-${ShareShow.topFood}'))).value, isTrue);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('share-toggle-${ShareShow.energy}'))).value, isFalse);
    expect(tester.widget<CheckboxListTile>(find.byKey(const Key('share-toggle-${ShareShow.profile}'))).value, isFalse);
  });

  testWidgets('alle vitaminen: telt alleen stoffen met een doel', (tester) async {
    final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    final s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
    final t = s.targets;
    final values = {for (final e in t.entries) e.key: (e.value.goal ?? 0) * 1.2};
    final m = microsReached(values, t);
    expect(m.total, greaterThan(15));
    expect(m.reached, m.total);
    expect(microsReached(const {}, t).reached, 0);
  });

  // Afbeeldingen bekijken: MM_SHARE_DUMP=/map flutter test test/share_cards_test.dart
  final dump = Platform.environment['MM_SHARE_DUMP'];
  if (dump != null) {
    testWidgets('kaarten als PNG bewaren (met de echte lettertypes)', (tester) async {
      await tester.runAsync(() async {
        for (final (family, files) in [
          (kSans, ['Geist-Regular', 'Geist-Medium', 'Geist-SemiBold', 'Geist-Bold']),
          (kMono, ['GeistMono-Regular', 'GeistMono-Medium', 'GeistMono-SemiBold']),
        ]) {
          final loader = FontLoader(family);
          for (final f in files) {
            loader.addFont(rootBundle.load('assets/fonts/$f.ttf'));
          }
          await loader.load();
        }
        final icons = File(
          '${Platform.environment['FLUTTER_ROOT'] ?? '/home/xargo/development/flutter'}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        );
        if (icons.existsSync()) {
          await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())))).load();
        }
      });
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      final context = tester.element(find.byType(SizedBox));
      await tester.runAsync(() => precacheImage(const AssetImage('assets/logo.png'), context));
      for (final e in cards.entries) {
        for (final dark in [false, true]) {
          final png = (await tester.runAsync(() => renderShareCard(e.value({ShareShow.topFood}), view: tester.view, dark: dark)))!;
          File('$dump/${e.key}-${dark ? 'dark' : 'light'}.png').writeAsBytesSync(png);
        }
        final png = (await tester.runAsync(() => renderShareCard(e.value(all), view: tester.view, dark: true)))!;
        File('$dump/${e.key}-all.png').writeAsBytesSync(png);
      }
    });
  }
}
