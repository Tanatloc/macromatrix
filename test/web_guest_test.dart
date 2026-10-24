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
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/sync_engine.dart';
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/account_card.dart';
import 'package:macromatrix/ui/widgets/guest_nudge.dart';

/// Server zoals de Supabase-trigger: een oudere versie overschrijft nooit een nieuwere.
class _Server implements SyncRemote {
  final rows = <String, Map<String, Map<String, Object?>>>{};
  var _clock = DateTime.utc(2026, 1, 1);

  @override
  Future<void> push(SyncTable table, List<Map<String, Object?>> batch) async {
    final t = rows.putIfAbsent(table.name, () => {});
    for (final r in batch) {
      final key = r[table.key] as String;
      final old = t[key];
      if (old != null && (old['updated_at'] as int) > (r['updated_at'] as int)) continue;
      t[key] = {...r, 'server_ts': (_clock = _clock.add(const Duration(milliseconds: 1))).toIso8601String()};
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    final all =
        (rows[table.name]?.values ?? const <Map<String, Object?>>[])
            .where((r) => since == null || (r['server_ts'] as String).compareTo(since) > 0)
            .toList()
          ..sort((a, b) => (a['server_ts'] as String).compareTo(b['server_ts'] as String));
    return all.take(limit).toList();
  }
}

const _banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90});

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() => debugWebOverride = null);

  group('welk scherm (AuthGate)', () {
    GateScreen gate({bool signedIn = false, bool localOnly = false, bool hasProfile = true}) =>
        gateScreen(ready: true, configured: true, signedIn: signedIn, localOnly: localOnly, hasProfile: hasProfile);

    test('zonder account gekozen: gewoon de app, ook op het web (NW-1)', () {
      expect(gate(localOnly: true), GateScreen.app);
      expect(gate(localOnly: true, hasProfile: false), GateScreen.profileSetup);
    });

    test('nog niets gekozen: welkomscherm; ingelogd: de app', () {
      expect(gate(), GateScreen.welcome);
      expect(gate(signedIn: true), GateScreen.app);
      expect(gateScreen(ready: false, configured: true, signedIn: false, localOnly: true, hasProfile: true), GateScreen.loading);
      expect(gateScreen(ready: true, configured: false, signedIn: false, localOnly: false, hasProfile: true), GateScreen.app);
    });
  });

  Future<(AppState, Account)> pump(WidgetTester tester, Widget home) async {
    final user = UserDb(sqlite3.openInMemory());
    final state = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: user,
    );
    final account = Account(user, onRemoteChanges: state.reloadFromDisk);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: state),
          ChangeNotifierProvider.value(value: account),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ),
    );
    await tester.pump();
    return (state, account);
  }

  testWidgets('web: welkomscherm biedt "zonder account" aan, met eerlijke uitleg over de browser', (tester) async {
    debugWebOverride = true;
    final (_, account) = await pump(tester, const WelcomeScreen());
    expect(find.text('Use without an account'), findsOneWidget);
    expect(find.text('Your data is then kept in this browser only.'), findsOneWidget);

    await tester.tap(find.text('Use without an account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your data is kept in this browser only.'), findsOneWidget);
    expect(find.textContaining('What you logged here comes along.'), findsOneWidget);
    expect(account.localOnly, isFalse);

    await tester.tap(find.text('Continue without account'));
    await tester.pumpAndSettle();
    expect(account.localOnly, isTrue);
  });

  testWidgets('app (niet web): zelfde knop, zonder de browsernoot', (tester) async {
    debugWebOverride = false;
    await pump(tester, const WelcomeScreen());
    expect(find.text('Use without an account'), findsOneWidget);
    expect(find.text('Your data is then kept in this browser only.'), findsNothing);
    await tester.tap(find.text('Use without an account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Everything stays on this device only.'), findsOneWidget);
  });

  testWidgets('gast in Instellingen: uitleg en account maken, met de belofte dat alles meegaat', (tester) async {
    debugWebOverride = true;
    final (_, account) = await pump(tester, const Scaffold(body: GuestAccountPanel()));
    account.setLocalOnly(true);
    await tester.pump();
    expect(find.textContaining('Your data is kept in this browser only'), findsOneWidget);

    await tester.tap(find.text('Create free account'));
    await tester.pumpAndSettle();
    expect(find.text('Everything you logged so far comes along to your new account.'), findsOneWidget);
    // Je blijft gast tot het account er echt is
    expect(account.localOnly, isTrue);
  });

  group('herinnering na 3 dagen', () {
    bool due({int days = 3, bool seen = false, bool localOnly = true, bool signedIn = false}) =>
        GuestNudgeCard.due(configured: true, signedIn: signedIn, localOnly: localOnly, loggedDays: days, seen: seen);

    test('alleen voor gasten, pas na 3 gelogde dagen en maar één keer', () {
      expect(due(), isTrue);
      expect(due(days: 2), isFalse);
      expect(due(seen: true), isFalse);
      expect(due(localOnly: false), isFalse);
      expect(due(signedIn: true), isFalse);
    });

    testWidgets('"Not now" onthoudt dat ze gezien is', (tester) async {
      final (state, _) = await pump(tester, const Scaffold(body: GuestNudgeCard()));
      expect(find.textContaining('Create a free account to keep your data.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(find.byKey(const ValueKey('guest-nudge')), findsNothing);
      expect(state.user.setting(GuestNudgeCard.seenKey)?['seen'], isTrue);
    });
  });

  group('van gast naar account: gegevens gaan mee (NW-3)', () {
    late _Server server;
    setUp(() => server = _Server());

    Future<void> firstLogin(UserDb db) async {
      // Zoals Account._afterLogin bij een toestel dat nog nooit synchroniseerde
      expect(db.setting('_sync'), isNull);
      db.yieldUnsentSettings();
      await SyncEngine(db, server, userId: 'u1').run();
    }

    test('nieuw account: dagboek en profiel gaan naar de server', () async {
      final guest = UserDb(sqlite3.openInMemory())..setSetting('_local_only', {'on': true});
      guest.addEntry(day: '2026-10-20', meal: Meal.breakfast, food: _banana, grams: 120, quantity: 120);
      guest.setSetting('profile', {'weightKg': 70});
      await firstLogin(guest);

      expect(server.rows['diary']!.values.single['name'], 'Banana, raw');
      expect((server.rows['settings']!['profile']!['value'] as String), contains('70'));
      expect(server.rows['settings']!.containsKey('_local_only'), isFalse, reason: 'instellingen met _ blijven lokaal');
      expect(guest.hasDirtyRows, isFalse);
      expect(guest.setting('profile')?['weightKg'], 70);
    });

    test('bestaand account: dagboek wordt samengevoegd, het profiel van het account blijft', () async {
      final phone = UserDb(sqlite3.openInMemory());
      phone.addEntry(day: '2026-10-19', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      phone.setSetting('profile', {'weightKg': 82});
      await SyncEngine(phone, server, userId: 'u1').run();

      await Future<void>.delayed(const Duration(milliseconds: 2));
      final guest = UserDb(sqlite3.openInMemory());
      guest.addEntry(day: '2026-10-20', meal: Meal.breakfast, food: _banana, grams: 120, quantity: 120);
      guest.setSetting('profile', {'weightKg': 70});
      guest.setSetting('targets_custom', {'protein': 120});
      await firstLogin(guest);

      expect(server.rows['diary']!.length, 2);
      expect(guest.entriesFor('2026-10-19'), hasLength(1));
      expect(guest.entriesFor('2026-10-20'), hasLength(1));
      expect(guest.setting('profile')?['weightKg'], 82, reason: 'het profiel in het account wint');
      expect(server.rows['settings']!.containsKey('targets_custom'), isTrue, reason: 'wat het account nog niet had, komt erbij');
    });
  });
}
