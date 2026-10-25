// Veiligheid van de synchronisatie (review 2026-10-25): geweigerde rijen, door de app gemaakte rijen, instellingen
// bij het inloggen, klokverschillen, uitloggen tijdens een synchronisatie, mislukte eerste synchronisatie en
// gegevens van een ander account. Tegen de nagebootste server uit sync_test.dart (zelfde regels als de triggers).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/supplements.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/sync_engine.dart';
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:macromatrix/ui/screens/other_tab_screen.dart';
import 'package:macromatrix/ui/theme.dart';

import 'sync_test.dart' show FakeServer, FakeServerError;

const _banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90});
const _day = '2026-10-16';
const _vitD = Supplement(id: 'vitd', name: 'Vitamine D', dose: '1 capsule', nutrients: {'vit_d': 25}, auto: true);

/// Een toestel: de database van de gebruiker en de ruwe sqlite (om bv. een verkeerde klok na te bootsen).
class _Device {
  _Device() : raw = sqlite3.openInMemory() {
    db = UserDb(raw);
  }
  final Database raw;
  late final UserDb db;

  int updatedAt(String table, String key, {String col = 'id'}) =>
      raw.select('SELECT updated_at FROM $table WHERE "$col" = ?', [key]).first['updated_at'] as int;
  int synced(String table, String key, {String col = 'id'}) => raw.select('SELECT synced FROM $table WHERE "$col" = ?', [key]).first['synced'] as int;
  void setUpdatedAt(String table, String key, int at, {String col = 'id'}) =>
      raw.execute('UPDATE $table SET updated_at = ? WHERE "$col" = ?', [at, key]);
}

String _session(String id, String email) => jsonEncode({
  'access_token': 'test-$id',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'r-$id',
  'user': {'id': id, 'aud': 'authenticated', 'email': email, 'created_at': '2026-01-01T00:00:00Z', 'app_metadata': {}, 'user_metadata': {}},
});

/// Een [Account] dat "ingelogd" is (sessie alleen lokaal) en met de nagebootste server synchroniseert.
Future<Account> _signedIn(UserDb db, FakeServer server, String id, {String? email}) async {
  final client = SupabaseClient('http://127.0.0.1:9', 'anon', authOptions: const AuthClientOptions(autoRefreshToken: false));
  await client.auth.setInitialSession(_session(id, email ?? '$id@example.com'));
  return Account(db, onRemoteChanges: () {})..debugConnect(client, (_) => server);
}

void main() {
  late FakeServer server;
  late _Device a, b;

  Future<SyncResult> sync(_Device d, {bool Function()? active}) => SyncEngine(d.db, server, userId: 'user-1', active: active).run();

  setUp(() {
    setAppLang(AppLang.en);
    server = FakeServer();
    a = _Device();
    b = _Device();
  });

  group('1. één geweigerde rij houdt de rest niet tegen', () {
    test('een te lange notitie: de rest van de tabel, de andere tabellen en het ophalen gaan door', () async {
      b.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await sync(b);

      for (var i = 0; i < 700; i++) {
        a.db.setNote('2026-01-${(i % 28 + 1).toString().padLeft(2, '0')}-$i', 'notitie $i');
      }
      // Rechtstreeks in de database (de app knipt zelf al af): zoals een notitie van vóór die grens
      a.raw.execute('INSERT INTO notes (day, text, updated_at) VALUES (?,?,?)', [_day, 'x' * 25000, DateTime.now().millisecondsSinceEpoch]);
      a.db.addBiometric(day: _day, type: 'weight', value: 80);
      server.pushes = 0;

      final r = await sync(a);
      expect(r.rejected, 1);
      expect(r.errors, isEmpty);
      expect(server.rows['notes'], hasLength(700), reason: 'de andere notities staan op de server');
      expect(server.rows['biometrics'], hasLength(1), reason: 'een andere tabel gaat gewoon door');
      expect(a.db.entriesFor(_day), hasLength(1), reason: 'ophalen gebeurt ook');
      expect(a.synced('notes', _day, col: 'day'), 2);
      expect(a.db.rejectedCount, 1);
      expect(a.db.hasDirtyRows, isFalse, reason: 'de geweigerde rij wordt niet telkens opnieuw verstuurd');
      expect(a.db.hasUnsentRows, isTrue, reason: 'maar ze staat niet op de server: uitloggen vraagt eerst');
      expect(server.pushes, lessThan(40), reason: 'zoeken door te halveren, niet rij per rij');

      // Aanpassen (korter): de synchronisatie probeert het opnieuw
      a.db.setNote(_day, 'korter');
      final again = await sync(a);
      expect(again.pushed, 1);
      expect(a.db.rejectedCount, 0);
      expect(server.rows['notes']![_day]!['text'], 'korter');
    });

    test('een geweigerde rij die gewijzigd wordt met UPDATE, gaat ook opnieuw mee', () async {
      a.raw.execute(
        'INSERT INTO diary (id, day, meal, food_ref, name, grams, quantity, nutrients, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        ['lang', _day, 0, 'x', 'n' * 600, 100, 100, '{}', 1000, 1000],
      );
      await sync(a);
      expect(a.synced('diary', 'lang'), 2);
      a.db.deleteEntry('lang');
      expect(a.synced('diary', 'lang'), 0);
    });

    test('de app houdt zich aan de grenzen van de server', () {
      a.db.setNote(_day, 'x' * 25000);
      expect(a.db.note(_day).length, UserDb.maxNoteLength);
      a.db.saveFood(Food(ref: 'custom:1', name: 'n' * 600, brand: 'b' * 400, source: FoodSource.custom, per100g: const {'energy': 1}));
      expect(a.db.food('custom:1')!.name.length, UserDb.maxNameLength);
      expect(a.db.food('custom:1')!.brand!.length, UserDb.maxBrandLength);
      a.db.addEntry(
        day: _day,
        meal: Meal.lunch,
        food: Food(ref: 'x', name: 'n' * 600, source: FoodSource.custom, per100g: const {}),
        grams: 1,
        quantity: 1,
      );
      expect(a.db.entriesFor(_day).single.name.length, UserDb.maxNameLength);
      a.db.addExercise(day: _day, name: 'e' * 400, kcal: 10);
      expect(a.db.exerciseFor(_day).single.name.length, UserDb.maxShortNameLength);
    });

    test('een fout bij één tabel (bv. een kolom die ontbreekt): de andere tabellen en het ophalen gaan door', () async {
      b.db.setNote(_day, 'van b');
      await sync(b);
      a.db.saveMeal('Ontbijt', const [], meal: Meal.breakfast);
      a.db.addBiometric(day: _day, type: 'weight', value: 80);
      server.brokenPush.add('meals');
      final r = await sync(a);
      expect(r.errors.keys, ['meals']);
      expect(server.rows['biometrics'], hasLength(1));
      expect(a.db.note(_day), 'van b');
      expect(a.db.rejectedCount, 0, reason: 'een tabelfout zet geen rijen apart');
      expect(a.db.hasDirtyRows, isTrue, reason: 'de maaltijd gaat later alsnog');
      server.brokenPush.clear();
      await sync(a);
      expect(server.rows['meals'], hasLength(1));
    });

    test('geen internet: stoppen zoals vroeger (later opnieuw)', () async {
      a.db.addBiometric(day: _day, type: 'weight', value: 80);
      server.offline = true;
      await expectLater(sync(a), throwsA(isA<Exception>()));
      expect(a.db.hasDirtyRows, isTrue);
      expect(a.db.rejectedCount, 0);
    });

    test('limit_rows van vroeger (telde ook upserts van bestaande rijen): bijwerken blokkeert de rest niet', () async {
      final ids = [for (var i = 0; i < 3; i++) a.db.addBiometric(day: _day, type: 'weight', value: 80.0 + i)];
      await sync(a);
      server
        ..maxRows = 3
        ..oldLimitRows = true;
      a.db.updateBiometric(ids.first, value: 70);
      a.db.setNote(_day, 'gaat wel');
      final r = await sync(a);
      expect(r.rejected, 1);
      expect(server.rows['notes']![_day]!['text'], 'gaat wel');
      // Met de nieuwe limit_rows (20261107100000_sync_safety.sql) telt een bestaande rij niet
      server.oldLimitRows = false;
      a.db.updateBiometric(ids.first, value: 71);
      await sync(a);
      expect(server.rows['biometrics']![ids.first]!['value'], 71);
    });

    test('geweigerde rijen worden na een week opnieuw geprobeerd', () async {
      a.raw.execute('INSERT INTO notes (day, text, updated_at) VALUES (?,?,?)', [_day, 'x' * 25000, 1000]);
      await sync(a);
      expect(a.db.rejectedCount, 1);
      final state = a.db.setting('_sync')!;
      a.db.setSetting('_sync', {...state, 'rejected': DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch});
      a.raw.execute('UPDATE notes SET text = ? WHERE day = ?', ['kort genoeg', _day]); // bv. de server werd ruimer
      a.raw.execute('UPDATE notes SET synced = 2 WHERE day = ?', [_day]);
      await sync(a);
      expect(a.db.rejectedCount, 0);
      expect(server.rows['notes']![_day]!['text'], 'kort genoeg');
    });
  });

  group('2. wat de app zelf maakt, overschrijft geen wijziging van een ander toestel', () {
    test('herhaling: verwijderd op A, B maakt ze opnieuw aan bij het opstarten (vóór het ophalen)', () async {
      a.db.saveRepeat(
        mealIndex: 0,
        item: const ItemTemplate(foodRef: 'x', name: 'Havermout', grams: 50, quantity: 50, per100g: {'energy': 370}),
        weekdays: 0x7f,
        startDay: '2026-10-01',
      );
      await sync(a);
      await sync(b);
      a.db.applyRepeats(_day, DateTime(2026, 10, 16));
      final id = a.db.entriesFor(_day).single.id;
      expect(a.updatedAt('diary', id), UserDb.generatedAt);
      await sync(a);
      expect(server.rows['diary']![id], isNotNull, reason: 'nieuw: gaat wel naar de server');

      a.db.deleteEntry(id);
      await sync(a);
      // B opent de app en vult de herhaling in voor het eerst binnenhalen
      b.db.applyRepeats(_day, DateTime(2026, 10, 16));
      await sync(b);
      expect(b.db.entriesFor(_day), isEmpty, reason: 'de verwijdering van A wint');
      expect(server.rows['diary']![id]!['deleted'], 1);
      expect(b.db.hasDirtyRows, isFalse);
    });

    test('automatisch supplement: afgevinkt op A, B vinkt het vanzelf aan', () async {
      a.db.setSupplementTaken(_day, _vitD, true, auto: true);
      await sync(a);
      a.db.setSupplementTaken(_day, _vitD, false);
      await sync(a);
      b.db.setSupplementTaken(_day, _vitD, true, auto: true);
      await sync(b);
      expect(b.db.entriesFor(_day), isEmpty);
      expect(server.rows['diary']![_vitD.entryId(_day)]!['deleted'], 1);
    });

    test('Health Connect: meting met vaste id, op een ander toestel aangepast', () async {
      a.db.upsertBiometric(id: 'hc:weight:$_day', day: _day, type: 'weight', value: 80);
      await sync(a);
      await sync(b);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      b.db.updateBiometric('hc:weight:$_day', value: 79);
      await sync(b);
      // Een tweede gsm haalt hetzelfde uit Health Connect vóór hij ophaalt
      final c = _Device();
      c.db.upsertBiometric(id: 'hc:weight:$_day', day: _day, type: 'weight', value: 80);
      c.db.insertExerciseOnce(id: 'hc:run1', day: _day, name: 'Run', kcal: 300);
      await sync(c);
      expect(c.db.biometricsFor(_day).single.value, 79);
      expect(server.rows['biometrics']!['hc:weight:$_day']!['value'], 79);
      expect(server.rows['exercise']!['hc:run1'], isNotNull);
    });

    test('voedingswaarden bijgewerkt na een update: een verwijdering op een ander toestel wint', () async {
      final id = a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await sync(a);
      await sync(b);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      b.db.deleteEntry(id);
      await sync(b);
      a.db.replaceDiarySnapshots(_banana.ref, const {'energy': 95});
      await sync(a);
      expect(a.db.entriesFor(_day), isEmpty);
      expect(server.rows['diary']![id]!['deleted'], 1);
    });
  });

  group('3. inloggen op een tweede toestel overschrijft de instellingen van het account niet', () {
    test('ook niet als de server al een versie met dezelfde (oudste) tijd heeft', () async {
      // Een eerder toestel stuurde zijn instellingen ook als "wijkend" (tijd 1)
      b.db.setSetting('profile', {'weightKg': 82});
      b.db.yieldUnsentSettings();
      await sync(b);
      expect(server.rows['settings']!['profile']!['updated_at'], 1);

      a.db.setSetting('profile', {'weightKg': 70});
      a.db.yieldUnsentSettings();
      await sync(a);
      expect(jsonDecode(server.rows['settings']!['profile']!['value'] as String)['weightKg'], 82);
      expect(a.db.setting('profile')?['weightKg'], 82, reason: 'het toestel neemt de versie van het account over');
      expect(a.db.hasDirtyRows, isFalse);
    });

    test('een nieuw account: de instellingen van dit toestel krijgen een gewone tijd', () {
      a.db.setSetting('profile', {'weightKg': 70});
      a.db.yieldUnsentSettings();
      a.db.claimUnsentSettings();
      expect(a.updatedAt('settings', 'profile', col: 'key'), greaterThan(UserDb.generatedAt));
    });

    test('Account: na het bevestigen van een nieuw account wijken de instellingen niet', () async {
      a.db.setSetting('profile', {'weightKg': 70});
      final account = await _signedIn(a.db, server, 'new-user');
      await account.debugAfterLogin(newAccount: true);
      expect(server.rows['settings']!['profile']!['updated_at'], greaterThan(UserDb.generatedAt));
      account.dispose();
    });
  });

  group('4. klokverschil: wat de server bewaarde, telt', () {
    test('een klok die voorloopt, blokkeert latere wijzigingen niet (begrensd op nu + 5 min)', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      server.nowMs = now;
      final id = a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      a.setUpdatedAt('diary', id, now + const Duration(hours: 1).inMilliseconds);
      await sync(a);
      expect(server.rows['diary']![id]!['updated_at'], now + 5 * 60 * 1000);
      expect(a.updatedAt('diary', id), now + 5 * 60 * 1000, reason: 'A neemt de begrensde versie over');
      expect(a.db.hasDirtyRows, isFalse);

      await sync(b);
      b.db.updateEntry(id, meal: Meal.lunch, grams: 150, quantity: 150);
      b.setUpdatedAt('diary', id, now + 10 * 60 * 1000); // tien minuten later
      server.nowMs = now + 10 * 60 * 1000;
      await sync(b);
      await sync(a);
      expect(a.db.entriesFor(_day).single.grams, 150);
    });

    test('een klok die achterloopt: de wijziging wordt niet stil als verstuurd gemarkeerd', () async {
      final id = a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await sync(a);
      await sync(b);
      b.db.updateEntry(id, meal: Meal.lunch, grams: 150, quantity: 150);
      b.setUpdatedAt('diary', id, 5); // een klok ver in het verleden
      final r = await sync(b);
      expect(r.pushed, 0);
      expect(b.db.entriesFor(_day).single.grams, 100, reason: 'B heeft weer wat de server heeft, zoals A');
      expect(b.db.hasDirtyRows, isFalse);
    });
  });

  group('5. uitloggen tijdens een synchronisatie', () {
    test('de motor schrijft niets meer zodra hij niet meer actief is', () async {
      b.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await sync(b);
      var active = true;
      server.beforePullReturns = (t) async {
        if (t.name == 'diary') {
          active = false;
          a.db.wipeUserData();
        }
      };
      await expectLater(sync(a, active: () => active), throwsA(isA<SyncCancelled>()));
      expect(a.db.entriesFor(_day), isEmpty);
      expect(a.db.setting('_sync'), isNull);
    });

    test('Account: uitloggen wacht op de lopende synchronisatie en wist daarna alles', () async {
      b.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await sync(b);
      final account = await _signedIn(a.db, server, 'user-1');
      await account.debugAfterLogin();
      Future<bool>? out;
      server.beforePullReturns = (t) async {
        if (t.name == 'diary' && out == null) out = account.signOut(force: true);
      };
      // Een nieuwe wijziging op B, zodat er iets op te halen valt
      b.db.addBiometric(day: _day, type: 'weight', value: 80);
      await sync(b);
      final running = account.sync();
      await running;
      expect(await out, isTrue);
      expect(account.signedIn, isFalse);
      expect(a.db.entriesFor(_day), isEmpty);
      expect(a.db.biometricsFor(_day), isEmpty);
      account.dispose();
    });
  });

  group('update nodig (v1.17.4)', () {
    test('Account.paused: niets versturen; na het vrijgeven gaat alles alsnog mee', () async {
      final account = await _signedIn(a.db, server, 'user-1');
      await account.debugAfterLogin();
      account.paused = true;
      final before = server.pushes;
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      await account.sync();
      expect(server.pushes, before);
      expect(a.db.hasDirtyRows, isTrue);
      account.paused = false;
      await account.sync();
      expect(server.pushes, greaterThan(before));
      expect(a.db.hasDirtyRows, isFalse);
      account.dispose();
    });

    test('het updatescherm gaat voor alles', () {
      expect(
        gateScreen(updateRequired: true, ready: false, configured: true, signedIn: true, localOnly: false, hasProfile: true),
        GateScreen.updateRequired,
      );
    });
  });

  group('6. mislukte eerste synchronisatie: geen "Over jou"', () {
    test('zonder geslaagd ophalen van de instellingen is er geen lastSync', () async {
      server.brokenPull.add('settings');
      await sync(a);
      expect(SyncEngine(a.db, server, userId: 'user-1').lastSync, isNull);
      server.brokenPull.clear();
      await sync(a);
      expect(SyncEngine(a.db, server, userId: 'user-1').lastSync, isNotNull);
    });

    test('gateScreen: ingelogd, geen profiel en nog niets opgehaald', () {
      GateScreen gate({bool firstSync = false, bool hasProfile = false, bool otherAccount = false}) => gateScreen(
        ready: true,
        configured: true,
        signedIn: true,
        localOnly: false,
        hasProfile: hasProfile,
        firstSync: firstSync,
        otherAccount: otherAccount,
      );
      expect(gate(firstSync: true), GateScreen.firstSync);
      expect(gate(), GateScreen.profileSetup);
      expect(gate(firstSync: true, hasProfile: true), GateScreen.app);
      expect(gate(otherAccount: true, hasProfile: true), GateScreen.otherAccount);
    });

    testWidgets('Account offline bij de eerste synchronisatie: opnieuw proberen of uitloggen', (tester) async {
      server.offline = true;
      final account = (await tester.runAsync(() => _signedIn(a.db, server, 'user-1')))!;
      await tester.runAsync(account.debugAfterLogin);
      expect(account.needsFirstSync, isTrue);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: account,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const FirstSyncScreen()),
        ),
      );
      expect(find.byKey(const ValueKey('first-sync-failed')), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Log out'), findsOneWidget);

      server.offline = false;
      await tester.runAsync(account.sync);
      expect(account.needsFirstSync, isFalse);
      account.dispose();
    });
  });

  group('7. inloggen met een ander account', () {
    test('niet-verstuurde gegevens van A gaan nooit naar B; eerst kiezen', () async {
      // A logt in, maar de eerste synchronisatie lukt niet (geen internet), en A logt een maaltijd
      server.offline = true;
      final accountA = await _signedIn(a.db, server, 'user-a', email: 'a@example.com');
      await accountA.debugAfterLogin();
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      accountA.dispose();

      // Daarna logt B in op hetzelfde toestel, met internet
      server.offline = false;
      final accountB = await _signedIn(a.db, server, 'user-b');
      await accountB.debugAfterLogin();
      expect(accountB.otherAccountData, isTrue);
      expect(accountB.otherAccountEmail, 'a@example.com');
      await accountB.sync();
      expect(server.rows['diary'] ?? const {}, isEmpty, reason: 'het dagboek van A mag niet in B terechtkomen');
      expect(a.db.entriesFor(_day), hasLength(1), reason: 'en het is ook niet stil gewist');

      // Kiezen: wissen en verder met B
      await accountB.discardOtherAccountData();
      expect(accountB.otherAccountData, isFalse);
      expect(a.db.entriesFor(_day), isEmpty);
      expect(server.rows['diary'] ?? const {}, isEmpty);
      expect(accountB.needsFirstSync, isFalse);
      accountB.dispose();
    });

    test('of toch als A: uitloggen zonder te wissen, daarna gaan de gegevens naar A', () async {
      a.db.setSetting('_owner', {'id': 'user-a', 'email': 'a@example.com'});
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      final accountB = await _signedIn(a.db, server, 'user-b');
      await accountB.debugAfterLogin();
      await accountB.switchToOtherAccount();
      expect(accountB.signedIn, isFalse);
      expect(a.db.entriesFor(_day), hasLength(1));
      accountB.dispose();

      final accountA = await _signedIn(a.db, server, 'user-a');
      await accountA.debugAfterLogin();
      expect(accountA.otherAccountData, isFalse);
      expect(server.rows['diary'], hasLength(1));
      accountA.dispose();
    });

    test('alles van A staat al op de server: gewoon wissen, zonder te vragen', () async {
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      final accountA = await _signedIn(a.db, server, 'user-a');
      await accountA.debugAfterLogin();
      expect(a.db.hasUnsentRows, isFalse);
      accountA.dispose();

      final other = FakeServer();
      final accountB = await _signedIn(a.db, other, 'user-b');
      await accountB.debugAfterLogin();
      expect(accountB.otherAccountData, isFalse);
      expect(a.db.entriesFor(_day), isEmpty);
      expect(other.rows['diary'] ?? const {}, isEmpty);
      accountB.dispose();
    });
  });

  group('8. twee tabbladen', () {
    testWidgets('melding met "Hier gebruiken", daarna wachten op het andere tabblad', (tester) async {
      var asked = 0;
      await tester.pumpWidget(OtherTabApp(onTakeOver: () async => asked++));
      expect(find.text('MacroMatrix is already open in another tab'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('use-here')));
      await tester.pump();
      expect(asked, 1);
      expect(find.textContaining('Waiting for the other tab'), findsOneWidget);
    });
  });

  test('FakeServerError wordt als rijfout herkend (zoals SQLSTATE 23514 bij Supabase)', () {
    expect(SupabaseRemote.classifyError(const PostgrestException(message: 'check', code: '23514')), SyncErrorKind.row);
    expect(SupabaseRemote.classifyError(const PostgrestException(message: 'te veel', code: '54000')), SyncErrorKind.row);
    expect(SupabaseRemote.classifyError(const PostgrestException(message: 'kolom', code: 'PGRST204')), SyncErrorKind.table);
    expect(SupabaseRemote.classifyError(const PostgrestException(message: 'jwt', code: 'PGRST301')), SyncErrorKind.fatal);
    expect(SupabaseRemote.classifyError(const PostgrestException(message: 'bad gateway', code: '502')), SyncErrorKind.fatal);
    expect(SupabaseRemote.classifyError(Exception('offline')), SyncErrorKind.fatal);
    expect(server.classify(FakeServerError(SyncErrorKind.row, 'x')), SyncErrorKind.row);
  });
  group('opnieuw proberen na een mislukte synchronisatie (live-test 25-10)', () {
    late Duration unit;
    setUp(() => unit = Account.retryUnit);
    tearDown(() => Account.retryUnit = unit);

    test('niet-verstuurde regels: vanzelf opnieuw met een wachttijd, ook zonder nieuwe wijziging', () async {
      Account.retryUnit = const Duration(milliseconds: 10);
      final acc = await _signedIn(a.db, server, 'user-1');
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      server.offline = true;
      await acc.debugAfterLogin(newAccount: true);
      expect(acc.status, SyncStatus.offline);
      expect(a.db.hasDirtyRows, isTrue);
      server.offline = false;
      // Eerste nieuwe poging na 2 eenheden (20 ms)
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(a.db.hasDirtyRows, isFalse);
      expect(acc.status, SyncStatus.idle);
      acc.dispose();
    });

    test('weer netwerk: meteen synchroniseren, zonder op de wachttijd te wachten', () async {
      Account.retryUnit = const Duration(hours: 1);
      final acc = await _signedIn(a.db, server, 'user-1');
      a.db.addEntry(day: _day, meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
      server.offline = true;
      await acc.debugAfterLogin(newAccount: true);
      expect(a.db.hasDirtyRows, isTrue);
      server.offline = false;
      acc.networkBack();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.db.hasDirtyRows, isFalse);
      acc.dispose();
    });

    test('niets te versturen: geen nieuwe pogingen (de gewone ronde om de 5 min volstaat)', () async {
      Account.retryUnit = const Duration(milliseconds: 5);
      final acc = await _signedIn(a.db, server, 'user-1');
      server.offline = true;
      await acc.debugAfterLogin(newAccount: true);
      final before = server.pullCalls;
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(server.pullCalls, before);
      acc.dispose();
    });
  });
}
