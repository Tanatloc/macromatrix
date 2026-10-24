import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3, OpenMode;
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/challenges.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/state/challenge_days.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/challenges.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/challenges_view.dart';

/// Nagebootste server voor uitdagingen: bewaart wat de app doorstuurt en geeft een ranglijst terug.
class FakeChallengeServer implements ChallengeRemote {
  /// Gooit [ChallengesMissing] zoals een server zonder de migratie.
  bool missing = false;
  final created = <String, (ChallengeTemplate, DateTime, List<String>)>{};
  final pushed = <String, Map<String, bool>>{};
  final responded = <String, bool>{};
  final left = <String>[];

  /// Extra uitdagingen (bv. een uitnodiging van een vriend) en de stand van anderen.
  final extra = <RemoteChallenge>[];
  final othersMet = <String, int>{};

  void _check() {
    if (missing) throw const ChallengesMissing();
  }

  @override
  Future<String> create(ChallengeTemplate t, DateTime start, List<String> invite) async {
    _check();
    final id = 'srv-${created.length + 1}';
    created[id] = (t, start, invite);
    return id;
  }

  @override
  Future<String> invite(String id, String friend) async {
    _check();
    final c = created[id]!;
    created[id] = (c.$1, c.$2, [...c.$3, friend]);
    return 'invited';
  }

  @override
  Future<void> respond(String id, bool accept) async {
    _check();
    responded[id] = accept;
  }

  @override
  Future<void> leave(String id) async {
    _check();
    left.add(id);
    created.remove(id);
  }

  @override
  Future<List<RemoteChallenge>> list() async {
    _check();
    return [
      for (final e in created.entries)
        RemoteChallenge(
          id: e.key,
          template: e.value.$1,
          start: e.value.$2,
          ownerIsMe: true,
          members: [
            RemoteMember(id: 'me', name: 'Me', me: true, met: pushed[e.key]?.values.where((v) => v).length ?? 0),
            for (final f in e.value.$3) RemoteMember(id: f, name: 'Friend $f', met: othersMet[f] ?? 0),
          ],
        ),
      for (final x in extra)
        RemoteChallenge(
          id: x.id,
          template: x.template,
          start: x.start,
          invitedBy: x.invitedBy,
          members: [for (final m in x.members) m.me ? RemoteMember(id: m.id, name: m.name, me: true, accepted: responded[x.id] == true) : m],
        ),
    ];
  }

  @override
  Future<void> pushDays(String id, Map<String, bool> days) async {
    _check();
    pushed.putIfAbsent(id, () => {}).addAll(days);
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  AppState newState() => AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  DateTime today() {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime daysAgo(int n) {
    final t = today();
    return DateTime(t.year, t.month, t.day - n);
  }

  // Eigen producten met precies bekende waarden per 100 g
  const fiberBar = Food(ref: 'custom:fiber', name: 'Fibre bar', source: FoodSource.custom, per100g: {'energy': 300, 'fiber': 10, 'free_sugars': 0});
  const candy = Food(ref: 'custom:candy', name: 'Candy', source: FoodSource.custom, per100g: {'energy': 400, 'sugars': 50, 'free_sugars': 50});
  const shake = Food(ref: 'custom:shake', name: 'Protein shake', source: FoodSource.custom, per100g: {'energy': 400, 'protein': 80});

  void log(AppState s, DateTime day, Food f, double grams) {
    s.setDate(day);
    s.addFood(f, meal: Meal.lunch, grams: grams, quantity: grams);
    s.goToToday();
  }

  group('dagbeoordeling per sjabloon', () {
    ChallengeTemplate builtin(String id) => builtinChallenges.firstWhere((t) => t.id == id);
    ChallengeDayStatus eval(String id, double v, {bool today = false, bool logged = true, double? goal}) => evaluateChallengeDay(
      builtin(id),
      ChallengeDayInput(logged: logged, value: v, goal: goal),
      today: today,
    );

    test('30 g vezels: minstens', () {
      expect(eval('fiber30', 30), ChallengeDayStatus.met);
      expect(eval('fiber30', 29.9), ChallengeDayStatus.missed);
      expect(eval('fiber30', 12, today: true), ChallengeDayStatus.open);
      expect(eval('fiber30', 31, today: true), ChallengeDayStatus.met);
      expect(eval('fiber30', 0, logged: false), ChallengeDayStatus.missed);
    });

    test('vrije suikers: hoogstens, en een lege dag telt niet als gehaald', () {
      expect(eval('sugar_week', 25), ChallengeDayStatus.met);
      expect(eval('sugar_week', 26), ChallengeDayStatus.missed);
      expect(eval('sugar_week', 10, today: true), ChallengeDayStatus.open);
      expect(eval('sugar_week', 40, today: true), ChallengeDayStatus.missed);
      expect(eval('sugar_week', 0, logged: false), ChallengeDayStatus.missed);
      expect(eval('sugar_week', 0, logged: false, today: true), ChallengeDayStatus.open);
    });

    test('5 porties groenten en natrium', () {
      expect(eval('veg5', 5), ChallengeDayStatus.met);
      expect(eval('veg5', 4.5), ChallengeDayStatus.missed);
      expect(eval('sodium14', 1999), ChallengeDayStatus.met);
      expect(eval('sodium14', 2400), ChallengeDayStatus.missed);
      expect(eval('water21', 2000), ChallengeDayStatus.met);
    });

    test('eiwitdoel: 95% van je eigen doel, 10 van de 14 dagen', () {
      final t = builtin('protein10of14');
      expect(t.days, 14);
      expect(t.need, 10);
      expect(eval('protein10of14', 95, goal: 100), ChallengeDayStatus.met);
      expect(eval('protein10of14', 90, goal: 100), ChallengeDayStatus.missed);
      expect(eval('protein10of14', 200), ChallengeDayStatus.missed, reason: 'zonder doel geen gehaalde dag');
    });

    test('sjablonen hebben een naam en overleven JSON', () {
      for (final t in builtinChallenges) {
        expect(t.name, isNotEmpty);
        expect(ChallengeTemplate.fromJson(t.toJson()), t);
      }
      const custom = ChallengeTemplate(id: 'custom', nutrient: 'vit_c', rule: ChallengeRule.min, amount: 90, days: 10, need: 8);
      expect(custom.name, 'At least 90 mg vitamin c, 8 of 10 days');
      expect(ChallengeTemplate.fromJson(custom.toJson()), custom);
    });

    test('een lopende uitdaging: ring, gewonnen en niet meer haalbaar', () {
      final start = daysAgo(3);
      final c = Challenge(id: 'x', template: builtin('fiber30').copyWith(), start: start);
      // Dag 0 en 2 gehaald, dag 1 niets gelogd, vandaag nog open
      final p = challengeProgress(
        c,
        today(),
        (d) => d == start || d == daysAgo(1) ? const ChallengeDayInput(logged: true, value: 31) : const ChallengeDayInput(logged: true, value: 5),
      );
      expect(p.statuses.take(4), [ChallengeDayStatus.met, ChallengeDayStatus.missed, ChallengeDayStatus.met, ChallengeDayStatus.open]);
      expect(p.met, 2);
      expect(p.missed, 1);
      expect(p.remaining, 27);
      expect(p.dayNumber(today()), 4);
      expect(p.lost, isTrue, reason: '30 van de 30 kan niet meer na een gemiste dag');
      expect(p.pushable().length, 4);
      expect(p.pushable()[dayKey(today())], isFalse);

      const short = ChallengeTemplate(id: 'custom', nutrient: 'fiber', rule: ChallengeRule.min, amount: 30, days: 3, need: 2);
      final done = challengeProgress(
        Challenge(id: 'y', template: short, start: daysAgo(5)),
        today(),
        (_) => const ChallengeDayInput(logged: true, value: 40),
      );
      expect(done.finished, isTrue);
      expect(done.won, isTrue);
      expect(done.ring, 1);
    });
  });

  group('uit het dagboek', () {
    test('vezels, vrije suikers en eiwit per dag', () {
      final s = newState();
      final fiber = s.addChallenge(builtinChallenges.firstWhere((t) => t.id == 'fiber30'), daysAgo(2));
      final sugar = s.addChallenge(builtinChallenges.firstWhere((t) => t.id == 'sugar_week'), daysAgo(2));
      final protein = s.addChallenge(builtinChallenges.firstWhere((t) => t.id == 'protein10of14'), daysAgo(2));
      log(s, daysAgo(2), fiberBar, 300); // 30 g vezels
      log(s, daysAgo(2), candy, 20); // 10 g vrije suikers
      log(s, daysAgo(1), fiberBar, 100); // 10 g vezels
      log(s, daysAgo(1), candy, 80); // 40 g vrije suikers
      final goal = s.targetsForDate(daysAgo(1))['protein']!.goal!;
      log(s, daysAgo(1), shake, goal * 1.25); // precies het doel (80 g eiwit per 100 g)
      log(s, today(), fiberBar, 50);

      final pf = s.challengeProgressOf(fiber);
      expect(pf.statuses.take(3), [ChallengeDayStatus.met, ChallengeDayStatus.missed, ChallengeDayStatus.open]);
      expect(pf.todayInput!.value, closeTo(5, 1e-6));
      expect(challengeTodayText(pf), '5 g of 30 g today');

      final ps = s.challengeProgressOf(sugar);
      expect(ps.statuses.take(3), [ChallengeDayStatus.met, ChallengeDayStatus.missed, ChallengeDayStatus.open]);

      final pp = s.challengeProgressOf(protein);
      expect(pp.statuses.take(3), [ChallengeDayStatus.missed, ChallengeDayStatus.met, ChallengeDayStatus.open]);
    });

    test('porties groenten: 80 g per portie, peulvruchten hoogstens één', () {
      final s = newState();
      final broccoli = s.foods.byRef('ciqual:20057')!;
      final lentils = s.foods.byRef('mvt:06.105')!;
      final c = s.addChallenge(builtinChallenges.firstWhere((t) => t.id == 'veg5'), today());
      log(s, today(), broccoli, 240); // 3 porties
      log(s, today(), lentils, 300); // telt als 1
      expect(s.challengeProgressOf(c).todayInput!.value, closeTo(4, 1e-6));
      expect(s.challengeProgressOf(c).statusOn(today()), ChallengeDayStatus.open);
      log(s, today(), broccoli, 80);
      expect(s.challengeProgressOf(c).statusOn(today()), ChallengeDayStatus.met);
    });
  });

  group('ranglijst', () {
    test('meeste dagen eerst, gelijke stand deelt de plaats, jij bovenaan bij gelijkstand', () {
      final r = rankChallenge(const [
        ChallengeEntry(id: 'a', name: 'Anna', met: 5),
        ChallengeEntry(id: 'me', name: 'Me', met: 7, me: true),
        ChallengeEntry(id: 'b', name: 'Bram', met: 7),
        ChallengeEntry(id: 'c', name: 'Cas', met: 2),
        ChallengeEntry(id: 'd', name: 'Dirk', met: 9, accepted: false),
      ]);
      expect([for (final (p, e) in r) '$p ${e.id}'], ['1 me', '1 b', '3 a', '4 c']);
    });

    test('jouw stand komt uit je dagboek, die van vrienden van de server', () async {
      final s = newState();
      final server = FakeChallengeServer()..othersMet['f1'] = 3;
      final c = Challenges(s, Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      addTearDown(c.dispose);
      await c.startGroup(builtinChallenges.first, daysAgo(1), ['f1']);
      log(s, daysAgo(1), fiberBar, 300);
      log(s, today(), fiberBar, 300);
      final ch = s.challenges.single;
      await c.load();
      final board = c.board(ch, myName: 'Me');
      expect([for (final (p, e) in board) '$p ${e.met} ${e.me}'], ['1 3 false', '2 2 true']);
    });
  });

  group('alleen voor jezelf', () {
    test('werkt zonder account en zonder server', () async {
      final s = newState();
      final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
      expect(account.signedIn, isFalse);
      final c = Challenges(s, account);
      addTearDown(c.dispose);
      expect(c.remote, isNull);
      expect(c.canGroup, isFalse);
      final ch = c.startSolo(builtinChallenges.first, today());
      expect(ch.group, isFalse);
      expect(s.challenges.single.id, ch.id);
      expect(s.activeChallenges, hasLength(1));
      await c.load(); // doet niets zonder server
      expect(c.error, isNull);
      // Met vrienden kan niet: het wordt een uitdaging voor jezelf
      final msg = await c.startGroup(builtinChallenges[1], today(), ['f1']);
      expect(msg, contains('not available'));
      expect(s.challenges.where((x) => !x.group), hasLength(2));
      log(s, today(), fiberBar, 400);
      expect(c.board(ch, myName: 'Me').single.$2.met, 1);
      await c.leave(ch);
      expect(s.challenges, hasLength(1));
    });

    test('bewaard in de instellingen (gaat mee naar je andere toestellen)', () {
      final s = newState();
      s.addChallenge(builtinChallenges.first, today());
      expect(s.user.setting('challenges')?['list'], hasLength(1));
      // Een kapotte rij breekt de lijst niet
      s.user.setSetting('challenges', {
        'list': [
          {'id': 1},
          ...(s.user.setting('challenges')!['list'] as List),
        ],
      });
      expect(s.challenges, hasLength(1));
    });
  });

  group('met vrienden', () {
    test('aanmaken, alleen ja/nee per dag doorsturen, uitnodiging aannemen', () async {
      final s = newState();
      final server = FakeChallengeServer();
      final c = Challenges(s, Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      addTearDown(c.dispose);
      log(s, daysAgo(1), fiberBar, 300);
      final msg = await c.startGroup(builtinChallenges.first, daysAgo(1), ['f1', 'f2']);
      expect(msg, contains('invitation'));
      final ch = s.challenges.single;
      expect(ch.remoteId, 'srv-1');
      expect(server.created['srv-1']!.$3, ['f1', 'f2']);
      expect(server.pushed['srv-1'], {dayKey(daysAgo(1)): true, dayKey(today()): false});
      // Niets veranderd: niets opnieuw
      server.pushed.clear();
      await c.pushDays();
      expect(server.pushed, isEmpty);
      log(s, today(), fiberBar, 300);
      await c.pushDays();
      expect(server.pushed['srv-1'], {dayKey(today()): true});

      // Uitnodiging van een vriend
      server.extra.add(
        RemoteChallenge(
          id: 'srv-x',
          template: builtinChallenges[1],
          start: today(),
          invitedBy: 'Anna',
          members: const [
            RemoteMember(id: 'anna', name: 'Anna'),
            RemoteMember(id: 'me', name: 'Me', me: true, accepted: false),
          ],
        ),
      );
      await c.load();
      expect(c.invites.single.id, 'srv-x');
      expect(s.challenges, hasLength(1));
      await c.respond(c.invites.single, true);
      expect(server.responded['srv-x'], isTrue);
      expect(c.invites, isEmpty);
      expect(s.challenges.map((x) => x.remoteId), containsAll(['srv-1', 'srv-x']));
      expect(s.challenges.firstWhere((x) => x.remoteId == 'srv-x').owner, isFalse);

      // Verwijderd op de server (iedereen weg): verdwijnt ook hier
      server.created.remove('srv-1');
      await c.load();
      expect(s.challenges.map((x) => x.remoteId), ['srv-x']);
    });

    test('een uitdaging voor jezelf wordt een groepsuitdaging bij de eerste uitnodiging', () async {
      final s = newState();
      final server = FakeChallengeServer();
      final c = Challenges(s, Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      addTearDown(c.dispose);
      final ch = c.startSolo(builtinChallenges.first, today());
      expect(await c.invite(ch, ['f1']), 'Invitation sent.');
      expect(s.challenges.single.remoteId, 'srv-1');
      expect(server.created['srv-1']!.$2, today());
      await c.invite(s.challenges.single, ['f2']);
      expect(server.created['srv-1']!.$3, ['f1', 'f2']);
      expect(c.waitingFor(s.challenges.single), isEmpty, reason: 'de nagebootste server zet iedereen op aanvaard');
    });
  });

  group('server zonder de migratie', () {
    test('groepsfunctie valt stil, alleen voor jezelf blijft werken', () async {
      final s = newState();
      final server = FakeChallengeServer()..missing = true;
      final c = Challenges(s, Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      addTearDown(c.dispose);
      expect(c.canGroup, isTrue);
      await c.load();
      expect(c.groupAvailable, isFalse);
      expect(c.error, isNull, reason: 'geen foutmelding, gewoon niet beschikbaar');
      expect(c.canGroup, isFalse);
      final msg = await c.startGroup(builtinChallenges.first, today(), ['f1']);
      expect(msg, contains('not available'));
      expect(s.challenges.single.group, isFalse);
      await c.pushDays(); // doet niets
      expect(server.pushed, isEmpty);
    });

    test('een groepsuitdaging die al bestond: doorsturen stopt zonder fout', () async {
      final s = newState();
      final server = FakeChallengeServer();
      final c = Challenges(s, Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
      addTearDown(c.dispose);
      await c.startGroup(builtinChallenges.first, today(), const []);
      server.missing = true;
      log(s, today(), fiberBar, 400);
      await c.pushDays();
      expect(c.groupAvailable, isFalse);
      // Lokaal blijft ze gewoon staan
      expect(s.challenges.single.remoteId, 'srv-1');
      expect(s.challengeProgressOf(s.challenges.single).met, 1);
    });
  });

  group('schermen', () {
    Widget wrap(AppState s, Widget child) {
      final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider(create: (_) => Friends(s, account)),
        ],
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );
    }

    testWidgets('paneel: lopend met ring, nieuw starten zonder account, afgelopen met badge', (tester) async {
      final s = newState();
      const short = ChallengeTemplate(id: 'custom', nutrient: 'fiber', rule: ChallengeRule.min, amount: 30, days: 2, need: 1);
      s.addChallenge(short, daysAgo(4));
      log(s, daysAgo(4), fiberBar, 300);
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(wrap(s, const ChallengesPanel()));
      expect(find.text('Challenges'), findsOneWidget);
      expect(find.text('Finished'), findsOneWidget);
      expect(find.byIcon(Icons.workspace_premium_rounded), findsOneWidget);

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Log in to do challenges with friends'), findsOneWidget);
      await tester.tap(find.text('A week under 25 g free sugars'));
      await tester.pump();
      await tester.ensureVisible(find.text('Start challenge'));
      await tester.tap(find.text('Start challenge'));
      await tester.pumpAndSettle();
      expect(s.activeChallenges.single.template.id, 'sugar_week');
      expect(find.byType(ChallengeRing), findsOneWidget);
      expect(find.text('Nothing logged yet today'), findsOneWidget);
    });

    testWidgets('Vandaag: een regel per lopende uitdaging', (tester) async {
      final s = newState();
      final c = s.addChallenge(builtinChallenges.first, daysAgo(1));
      s.addChallenge(builtinChallenges[1], today().add(const Duration(days: 1))); // nog niet begonnen: niet tonen
      log(s, today(), fiberBar, 320);
      await tester.pumpWidget(wrap(s, const ChallengeTodayStrip()));
      expect(find.byKey(ValueKey('challenge-today-${c.id}')), findsOneWidget);
      expect(find.textContaining('Done today'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('1/30'), findsOneWidget);
    });
  });
}
