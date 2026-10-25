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
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/activity_ask.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

/// Van de allereerste start tot de eerste gelogde maaltijd (meting 25-10-2026, zie
/// voedingsapp-data/evaluaties/eerste-maaltijd-2026-10-25.md). Deze test houdt dat pad kort: komt er een scherm,
/// vraag of tik bij, dan faalt hij. Wil je toch iets toevoegen aan de eerste start, verhoog dan bewust de grenzen.
const maxTaps = 8;
const maxScreens = 4; // welkom, over jou, Vandaag, Snel loggen
const maxOnboardingFields = 3; // geboortejaar, lengte, gewicht
const maxOnboardingChoices = 2; // geslacht, doel

/// Zoals [AuthGate] met een geconfigureerde Supabase (in tests is die er niet): dezelfde [gateScreen].
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final a = context.watch<Account>();
    final s = context.watch<AppState>();
    return switch (gateScreen(ready: true, configured: true, signedIn: false, localOnly: a.localOnly, hasProfile: s.hasProfile)) {
      GateScreen.updateRequired || GateScreen.loading || GateScreen.otherAccount || GateScreen.firstSync => const SizedBox.shrink(),
      GateScreen.welcome => const WelcomeScreen(),
      GateScreen.profileSetup => const ProfileSetupScreen(),
      GateScreen.app => const DiaryScreen(),
    };
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() {
    appClock = DateTime.now;
    debugWebOverride = null;
  });

  final foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));

  for (final web in [true, false]) {
    testWidgets('${web ? 'web' : 'app'}: eerste start tot eerste maaltijd in hoogstens $maxTaps tikken en $maxScreens schermen', (tester) async {
      debugWebOverride = web;
      // 8 uur 's ochtends: Vandaag vraagt naar het ontbijt
      appClock = () => DateTime(2026, 10, 25, 8, 15);
      final user = UserDb(sqlite3.openInMemory());
      final state = AppState(foods: foods, user: user);
      final account = Account(user, onRemoteChanges: state.reloadFromDisk);
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider.value(value: account),
          ],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const _Gate()),
        ),
      );
      await tester.pump();

      var taps = 0;
      final screens = <String>{};
      Future<void> tap(Finder f) async {
        taps++;
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      Future<void> type(Finder f, String text) async {
        await tap(f);
        await tester.enterText(f, text);
        await tester.pump();
      }

      // 1. Welkom: zonder account, met de uitleg meteen onder de knop en geen extra venster
      expect(find.byType(WelcomeScreen), findsOneWidget);
      screens.add('welcome');
      expect(find.byKey(const ValueKey('guest-note')), findsOneWidget);
      await tap(find.text('Use without an account'));
      expect(find.byType(AlertDialog), findsNothing, reason: 'geen bevestigingsvenster meer na "zonder account"');
      expect(account.localOnly, isTrue);

      // 2. Over jou: alleen wat nodig is voor je doelen en de 18+-controle
      expect(find.byType(ProfileSetupScreen), findsOneWidget);
      screens.add('about-you');
      final setup = find.byType(ProfileSetupScreen);
      expect(find.descendant(of: setup, matching: find.byType(TextField)), findsNWidgets(maxOnboardingFields));
      expect(
        find.descendant(of: setup, matching: find.byWidgetPredicate((w) => w is Segmented)),
        findsNWidgets(maxOnboardingChoices),
      );
      expect(find.text('How active are you?'), findsNothing, reason: 'activiteit komt na de eerste maaltijd');
      expect(find.text('Appearance'), findsNothing, reason: 'thema volgt het toestel, keuze in Instellingen');
      expect(find.text('Allergies (optional)'), findsNothing, reason: 'allergieën via de kaart op Vandaag');
      await tap(find.text('Female'));
      final fields = find.descendant(of: setup, matching: find.byType(TextField));
      bool focused(int i) => tester.widget<EditableText>(find.descendant(of: fields.at(i), matching: find.byType(EditableText))).focusNode.hasFocus;
      await type(fields.at(0), '1991');
      // Een volledig jaartal en een lengte van 3 cijfers springen zelf naar het volgende veld: geen extra tik
      await tester.pump();
      expect(focused(1), isTrue, reason: 'na het geboortejaar meteen naar de lengte');
      await tester.enterText(fields.at(1), '168');
      await tester.pump();
      expect(focused(2), isTrue, reason: 'na de lengte meteen naar het gewicht');
      await tester.enterText(fields.at(2), '64');
      await tester.pump();
      await tap(find.text('Done, go to the app'));
      expect(state.hasProfile, isTrue);
      expect(state.profile.activity, Activity.light, reason: 'redelijke standaard tot je het zelf kiest');
      expect(state.profile.birthYear, 1991);

      // 3. Vandaag, een lege dag: meteen een veld "Wat at je?"
      expect(find.byType(DiaryScreen), findsOneWidget);
      screens.add('today');
      expect(find.text('What did you have for breakfast?'), findsOneWidget);
      final field = find.byKey(const ValueKey('start-quick-log'));
      expect(field, findsOneWidget);
      await type(field, '2 eggs and a slice of toast');
      taps++; // Enter op het toetsenbord
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await tester.pumpAndSettle();

      // 4. Snel loggen: de producten staan al klaar
      expect(find.text('Quick log'), findsOneWidget);
      screens.add('quick-log');
      await tap(find.text('Add 2 to breakfast'));

      final logged = state.entriesFor(Meal.breakfast);
      expect(logged, hasLength(2));
      expect(logged.map((e) => e.name.toLowerCase()).join(' '), allOf(contains('egg'), anyOf(contains('toast'), contains('bread'))));
      expect(taps, lessThanOrEqualTo(maxTaps), reason: '$taps tikken tot de eerste maaltijd');
      expect(screens.length, lessThanOrEqualTo(maxScreens), reason: 'schermen: $screens');

      // Na de eerste maaltijd: de vraag naar je activiteit, één keer
      expect(find.text('What did you have for breakfast?'), findsNothing);
      await tester.ensureVisible(find.byKey(const ValueKey('activity-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-ask')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('activity-moderate')));
      await tester.pumpAndSettle();
      expect(state.profile.activity, Activity.moderate);
      expect(find.byKey(const ValueKey('activity-ask')), findsNothing);
      expect(activityAskDue(state), isFalse);
    });
  }

  testWidgets('wie de app al gebruikte (profiel zonder open vraag), krijgt de activiteitsvraag niet', (tester) async {
    final user = UserDb(sqlite3.openInMemory());
    final state = AppState(foods: foods, user: user)
      ..saveProfile(const Profile(sex: Sex.female, birthYear: 1990, heightCm: 170, weightKg: 65, activity: Activity.active));
    state.addFood(foods.search('banana', limit: 1).first, meal: Meal.breakfast, grams: 120, quantity: 120);
    expect(activityAskDue(state), isFalse);
    askActivityLater(state);
    // Een profiel dat al iets anders zegt dan "licht actief" (bv. na inloggen in een bestaand account): niet vragen
    expect(activityAskDue(state), isFalse);
    state.saveProfile(state.profile.copyWith(activity: Activity.light));
    expect(activityAskDue(state), isTrue);
    activityAsked(state);
    expect(activityAskDue(state), isFalse);
  });
}
