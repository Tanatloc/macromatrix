import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/profile_screen.dart';
import 'package:macromatrix/ui/theme.dart';

/// Eén eiwitdoel overal: de Macro's-rij toont een eigen eiwitdoel, en typen past dat eigen doel aan (N06, N60).
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  testWidgets('Macro\'s-rij toont en wijzigt het eigen eiwitdoel', (tester) async {
    final user = UserDb(sqlite3.openInMemory());
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: user,
    );
    final account = Account(user, onRemoteChanges: s.reloadFromDisk);
    tester.view.physicalSize = const Size(412, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s.saveProfile(const Profile(weightKg: 90, energyOverride: 3000));
    s.setOverride('protein', const Target(goal: 180));
    // Op Vandaag staat gisteren open: het Profiel toont toch de doelen van vandaag
    s.shiftDay(-1);
    final carbsBefore = s.todayTargets['carbs']!.goal!;

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
    final grams = find.byKey(const ValueKey('macro-grams-protein'));
    expect(find.descendant(of: grams, matching: find.text('180 g')), findsOneWidget);

    await tester.ensureVisible(grams);
    await tester.tap(grams);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '200');
    await tester.tap(find.text('Set'));
    await tester.pumpAndSettle();

    expect(s.settings.overrides['protein']!.goal, 200);
    expect(s.todayTargets['protein']!.goal, 200);
    expect(find.descendant(of: grams, matching: find.text('200 g')), findsOneWidget);
    // 20 g eiwit meer = 80 kcal minder voor koolhydraten en vet samen
    expect(s.todayTargets['carbs']!.goal!, lessThan(carbsBefore));
  });
}
