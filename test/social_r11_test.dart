// Testronde 11: vrienden, battles, uitdagingen, blokkeren en melden, supporterscherm, roadmap en de website
// (SO-1 tot SO-10, SU-6 tot SU-14, GP-11, GP-18).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/challenges.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/state/challenge_days.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/challenges.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/roadmap.dart';
import 'package:macromatrix/ui/screens/auth_screens.dart';
import 'package:macromatrix/ui/screens/friends_screen.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/avatar.dart';
import 'package:macromatrix/ui/widgets/avatar_frame_picker.dart';
import 'package:macromatrix/ui/widgets/badges_view.dart';
import 'package:macromatrix/ui/widgets/challenges_view.dart';

import 'early_access_test.dart' show FakeRoadmapRemote;
import 'pro_test.dart' show FakeProRemote, newPro, newState;

/// Ingelogd zonder server: genoeg om het vriendenscherm te tonen.
class _SignedIn extends Account {
  _SignedIn(super.db) : super(onRemoteChanges: () {});
  @override
  bool get signedIn => true;
}

/// Friends zonder server: een lijst die de test zelf vult, en wat er geblokkeerd, gemeld of aanvaard wordt.
class _FakeFriends extends Friends {
  _FakeFriends(super.state, super.account);

  List<Friend> server = const [];
  final blockedIds = <String>[];
  final reports = <(String, String)>[];

  @override
  Future<void> load({String? newName}) async {
    code = 'ABCD1234';
    list = [
      for (final x in server)
        if (!blocked.any((b) => b.id == x.id)) x,
    ];
    blockAvailable = true;
    notifyListeners();
  }

  @override
  Future<AddResult> add(String code) async => AddResult('not_found', addMessage('not_found'));

  @override
  Future<void> respond(Friend f, bool accept) async {
    server = [
      for (final x in server)
        if (x.id != f.id) x else if (accept) Friend(id: x.id, name: x.name, state: FriendState.friend),
    ];
    await load();
  }

  @override
  Future<bool> block(String id, {String name = '', String? avatar}) async {
    blockedIds.add(id);
    blocked = [BlockedUser(id: id, name: name, avatar: avatar), ...blocked];
    await load();
    return true;
  }

  @override
  Future<String?> report(String id, String reason, {String? note}) async {
    reports.add((id, reason));
    return 'reported';
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() => setAppLang(AppLang.en));

  Future<_FakeFriends> pumpFriends(WidgetTester tester, AppState s, {List<Friend> server = const []}) async {
    final account = _SignedIn(s.user);
    late _FakeFriends f;
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: s),
          ChangeNotifierProvider<Account>.value(value: account),
          ChangeNotifierProvider<Friends>(create: (_) => f = _FakeFriends(s, account)..server = server),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const FriendsScreen(active: false)),
      ),
    );
    await f.load();
    await tester.pumpAndSettle();
    return f;
  }

  group('SO-1: startdatum van een uitdaging', () {
    final today = DateTime(2026, 10, 24);
    test('vandaag, gisteren en morgen in woorden, verder een datum', () {
      expect(challengeStartText(today, today: today), 'started today');
      expect(challengeStartText(DateTime(2026, 10, 23), today: today), 'started yesterday');
      expect(challengeStartText(DateTime(2026, 10, 25), today: today), 'starts tomorrow');
      expect(challengeStartText(DateTime(2026, 10, 20), today: today), 'started Tue 20 Oct');
      expect(challengeStartText(DateTime(2026, 10, 28), today: today), 'starts Wed 28 Oct');
    });

    test('rond de wissel naar wintertijd telt een kalenderdag, geen 24 uur', () {
      // 25 oktober 2026 duurt 25 uur: "gisteren" blijft gisteren
      expect(challengeStartText(DateTime(2026, 10, 25), today: DateTime(2026, 10, 26)), 'started yesterday');
    });
  });

  group('SO-2: blokkeren in een gedeelde uitdaging', () {
    test('challenge_list laat de ander weg in beide richtingen', () {
      final sql = File('supabase/migrations/20261106300000_challenge_blocks_roadmap.sql').readAsStringSync();
      expect(sql, contains('create or replace function public.challenge_list()'));
      expect(sql, contains('(x.blocker = auth.uid() and x.blocked = m.user_id) or (x.blocker = m.user_id and x.blocked = auth.uid())'));
      expect(sql, contains("set search_path = ''"));
      expect(sql, contains('grant execute on function public.challenge_list() to authenticated;'));
    });
  });

  group('SO-10: alleen over in een groepsuitdaging', () {
    Future<Challenge> pumpPanel(WidgetTester tester, AppState s, List<RemoteMember> members) async {
      final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
      final f = Friends(s, account);
      final t = builtinChallenges.first;
      final n = logicalNow();
      final start = DateTime(n.year, n.month, n.day);
      final c = s.addChallenge(t, start, remoteId: 'r1', owner: false);
      f.challenges.remoteById = {'r1': RemoteChallenge(id: 'r1', template: t, start: start, members: members)};
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: s),
            ChangeNotifierProvider<Account>.value(value: account),
            // Met create: het scherm ruimt Friends (en zijn timers) op aan het einde
            ChangeNotifierProvider<Friends>(create: (_) => f),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const Scaffold(body: SingleChildScrollView(child: ChallengesPanel())),
          ),
        ),
      );
      await tester.pump();
      return c;
    }

    testWidgets('de maker stopte: "alleen" bij wie overblijft', (tester) async {
      await pumpPanel(tester, newState(), const [RemoteMember(id: 'me', name: 'Alex', me: true)]);
      expect(find.textContaining('on your own'), findsOneWidget);
    });

    testWidgets('met een andere deelnemer: niet "alleen"', (tester) async {
      await pumpPanel(tester, newState(), const [
        RemoteMember(id: 'me', name: 'Alex', me: true),
        RemoteMember(id: 'marc', name: 'Marc'),
      ]);
      expect(find.textContaining('on your own'), findsNothing);
      expect(find.text('Marc'), findsOneWidget);
    });
  });

  group('SO-3/SO-4: meldingen', () {
    testWidgets('een nieuwe melding vervangt de vorige meteen, met een sluitknop', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      friendsSay(ScaffoldMessenger.of(ctx), 'Challenge sent to Alex.');
      await tester.pumpAndSettle();
      expect(find.text('Challenge sent to Alex.'), findsOneWidget);
      // Een oude melding (die met een schermlezer bleef hangen) mag niet terugkomen na de nieuwe
      friendsSay(ScaffoldMessenger.of(ctx), 'Alex declined your battle challenge.');
      await tester.pumpAndSettle();
      expect(find.text('Challenge sent to Alex.'), findsNothing);
      expect(find.text('Alex declined your battle challenge.'), findsOneWidget);
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).showCloseIcon, isTrue);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    test('een geweigerde battle geeft een melding, een ingetrokken niet', () {
      final (messages, open) = sentBattleNotices({'b1': 'Alex', 'b2': 'Lotte'}, const [], cancelled: {'b2'});
      expect(messages, ['Alex declined your battle challenge.']);
      expect(open, isEmpty);
    });
  });

  group('SO-5: bevestigingen', () {
    test('wie je verzoek aanvaardde, krijgt een melding', () {
      final notices = acceptedRequestNotices({'a': 'Alex', 'l': 'Lotte'}, const [
        Friend(id: 'a', name: 'Alex', state: FriendState.friend),
        Friend(id: 'l', name: 'Lotte', state: FriendState.outgoing),
      ]);
      expect(notices, ['Alex accepted your friend request.']);
      expect(acceptedRequestNotices(const {}, const [Friend(id: 'a', name: 'Alex', state: FriendState.friend)]), isEmpty);
    });

    testWidgets('een verzoek aanvaarden zegt dat jullie nu vrienden zijn', (tester) async {
      await pumpFriends(tester, newState(), server: const [Friend(id: 'x', name: 'Xavier', state: FriendState.incoming)]);
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('You and Xavier are now friends.'), findsOneWidget);
    });
  });

  group('SO-6: melden na blokkeren, en blokkeren bij melden', () {
    testWidgets('in Geblokkeerd staat Melden naast Deblokkeren', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [Friend(id: 'j', name: 'Jens', state: FriendState.friend)]);
      await f.block('j', name: 'Jens');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('blocked-report-j')));
      await tester.pumpAndSettle();
      // Al geblokkeerd: geen vinkje "Ook blokkeren"
      expect(find.byKey(const Key('report-block')), findsNothing);
      await tester.tap(find.byKey(const Key('report-harassment')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(f.reports, [('j', 'harassment')]);
      expect(find.text('Thanks. We received your report and will look into it.'), findsOneWidget);
    });

    testWidgets('melden met "Ook blokkeren" blokkeert meteen', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [Friend(id: 'j', name: 'Jens', state: FriendState.friend)]);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-spam')));
      await tester.tap(find.byKey(const Key('report-block')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(f.reports, [('j', 'spam')]);
      expect(f.blockedIds, ['j']);
      expect(find.textContaining('Jens is blocked.'), findsOneWidget);
      expect(find.byKey(const Key('unblock-j')), findsOneWidget);
    });
  });

  group('SO-7: foutmelding bij de code', () {
    testWidgets('verdwijnt zodra er iemand bijkomt in je lijst', (tester) async {
      final f = await pumpFriends(tester, newState());
      await tester.enterText(find.byKey(const Key('friend-code')), 'GNVB-BPRL');
      await tester.pump();
      await tester.tap(find.byKey(const Key('friend-add')));
      await tester.pumpAndSettle();
      expect(find.text('Could not add a friend with this code. Check the letters and numbers.'), findsOneWidget);

      f.server = const [Friend(id: 'm', name: 'Marc', state: FriendState.incoming)];
      await f.load();
      await tester.pumpAndSettle();
      expect(find.text('Could not add a friend with this code. Check the letters and numbers.'), findsNothing);
      expect(find.text('GNVB-BPRL'), findsNothing);
    });
  });

  group('SO-8: battle voor volgende week', () {
    final monday = mondayOf(DateTime.now());
    Battle battle(DateTime week, {bool accepted = false, bool mine = true}) =>
        Battle(id: 'b', week: week, challengedByMe: mine, accepted: accepted, other: 'a', otherName: 'Alex');

    test('aanvaard voor volgende week: nog niet lopend, wel "upcoming"', () {
      final b = battle(monday.plusDays(7), accepted: true);
      expect(b.upcoming, isTrue);
      expect(b.live, isFalse);
      expect(b.finished, isFalse);
      expect(b.nextWeek, isTrue);
      expect(battle(monday, accepted: true).upcoming, isFalse);
      expect(battle(monday).nextWeek, isFalse);
    });

    test('aanvaard voor volgende week: melding "begint maandag"', () {
      final (messages, _) = sentBattleNotices({'b': 'Alex'}, [battle(monday.plusDays(7), accepted: true)]);
      expect(messages, ['Alex accepted your challenge: the battle starts on Monday.']);
    });

    testWidgets('op zaterdag en zondag eerst volgende week, anders deze week', (tester) async {
      final s = newState();
      await pumpFriends(tester, s, server: const [Friend(id: 'a', name: 'Alex', state: FriendState.friend)]);
      await tester.tap(find.text('Alex'));
      await tester.pumpAndSettle();
      if (DateTime.now().weekday >= DateTime.saturday) {
        expect(find.byKey(const Key('battle-next-week')), findsOneWidget);
        expect(find.byKey(const Key('battle-this-week-short')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('battle-this-week')), findsOneWidget);
        expect(find.byKey(const Key('battle-next-week')), findsNothing);
      }
    });
  });

  group('SU-6: supporterscherm', () {
    test('hoe het verlengt, volgens waar het abonnement vandaan komt', () {
      expect(ProScreen.renewalText('play'), contains('Renews automatically through Google Play'));
      expect(ProScreen.renewalText('play'), contains('Payments & subscriptions'));
      expect(ProScreen.renewalText('manual'), contains('does not renew'));
      expect(ProScreen.renewalText('web'), isNull);
    });
  });

  group('SU-8/SU-9: avatarranden', () {
    Positioned bubble(WidgetTester tester) =>
        tester.widget<Positioned>(find.ancestor(of: find.text('3'), matching: find.byType(Positioned)).first);

    testWidgets('bij de kroon zit het levelbolletje rechtsonder, anders rechtsboven', (tester) async {
      Future<void> show(AvatarFrame? f) => tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Center(child: LevelAvatar(avatar: null, level: 3, size: 64, frame: f, animate: false)),
        ),
      );
      await show(AvatarFrame.crown);
      expect(bubble(tester).bottom, isNotNull);
      expect(bubble(tester).top, isNull);
      await show(null);
      expect(bubble(tester).top, isNotNull);
    });

    testWidgets('op een gsm vier per rij, met een groot voorbeeld van je rand', (tester) async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime(2099), source: 'manual', frame: AvatarFrame.crown);
      final pro = newPro(s, server);
      await pro.refresh();
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppState>.value(value: s),
            ChangeNotifierProvider<Pro>.value(value: pro),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: AvatarFramePicker(),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('frame-preview')), findsOneWidget);
      final keys = ['none', for (final f in AvatarFrame.values.take(3)) f.id];
      final tops = {for (final k in keys) tester.getTopLeft(find.byKey(ValueKey('frame-$k'))).dy};
      expect(tops, hasLength(1), reason: 'de eerste vier staan op één rij');
    });
  });

  group('SU-10: accentkleuren', () {
    double hueGap(Color a, Color b) {
      final d = (HSVColor.fromColor(a).hue - HSVColor.fromColor(b).hue).abs();
      return d > 180 ? 360 - d : d;
    }

    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
    }

    test('goud en roos liggen een eind van koolhydraten, vet, te weinig en te veel', () {
      for (final id in ['gold', 'rose']) {
        final a = accentById(id);
        for (final (pal, brand) in [(Palette.light, a.light), (Palette.dark, a.dark)]) {
          for (final c in [pal.carbs, pal.fat, pal.low, pal.high]) {
            expect(hueGap(brand, c), greaterThanOrEqualTo(17), reason: '$id tegenover $c');
          }
        }
        expect(contrast(a.light, Colors.white), greaterThanOrEqualTo(4.5));
        expect(contrast(a.dark, a.darkOn), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('SU-11/SU-14: titels, badges en kleurstalen', () {
    testWidgets('supportertitel: een gouden hartje in badgestijl', (tester) async {
      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: const Center(child: TitleIcon(supporter: true))));
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.favorite_rounded);
      expect(icon.color, const Color(0xFF835C00));
    });

    testWidgets('het badgevenster heeft een naam voor de schermlezer, en "1 month"', (tester) async {
      final handle = tester.ensureSemantics();
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      showBadgeCategory(ctx, 'loyal', value: 0);
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Loyal supporter, Locked'), findsOneWidget);
      expect(find.text('Be a supporter for 1 month.'), findsOneWidget);
      handle.dispose();
    });
  });

  group('SU-14: kleurstalen', () {
    testWidgets('één keer voorgelezen, en de naam van de gekozen kleur staat erbij', (tester) async {
      final handle = tester.ensureSemantics();
      final s = newState();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: s,
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const Scaffold(body: AccentPicker())),
        ),
      );
      expect(find.text('Colour · Petrol'), findsOneWidget);
      expect(find.bySemanticsLabel('Petrol'), findsOneWidget);
      expect(find.bySemanticsLabel('Ocean (Supporter)'), findsOneWidget);
      handle.dispose();
    });
  });

  group('SU-12: roadmap', () {
    RoadmapItem item(String id, RoadmapStatus st, {bool mine = false}) => RoadmapItem(id: id, titleEn: id, status: st, mine: mine);

    test("'early' wordt herkend; stemmen kan dan niet meer en telt niet mee", () async {
      expect(RoadmapItem.fromJson({'id': 'c', 'status': 'early'}).status, RoadmapStatus.early);
      final remote = FakeRoadmapRemote([
        item('coach', RoadmapStatus.early, mine: true),
        item('a', RoadmapStatus.idea, mine: true),
        item('b', RoadmapStatus.idea),
      ]);
      final r = Roadmap(null, remote: () => remote);
      await r.refresh();
      expect(r.votesLeft, roadmapVotesMax - 1);
      expect(await r.toggle(r.items.first), VoteResult.closed);
      expect(remote.votes, isEmpty);
    });

    test('de migratie zet de coach op vroege toegang en scherpt wat al bestaat aan', () {
      final sql = File('supabase/migrations/20261106300000_challenge_blocks_roadmap.sql').readAsStringSync();
      expect(sql, contains("check (status in ('idea', 'planned', 'building', 'early', 'done'))"));
      expect(sql, contains("if st in ('early', 'done') then"));
      expect(sql, contains("set status = 'early' where title_en = 'Weekly AI coach summary'"));
      expect(sql, contains('Macro schedule'));
    });
  });

  group('GP-11: na het inloggen geen flits van "Over jou"', () {
    test('zolang het profiel nog onderweg is: laden', () {
      expect(
        gateScreen(ready: true, configured: true, signedIn: true, localOnly: false, hasProfile: false, fetching: true),
        GateScreen.loading,
      );
      expect(gateScreen(ready: true, configured: true, signedIn: true, localOnly: false, hasProfile: false), GateScreen.profileSetup);
      expect(gateScreen(ready: true, configured: true, signedIn: true, localOnly: false, hasProfile: true, fetching: true), GateScreen.app);
    });
  });

  group('GP-18: geen APK-link vanuit de app', () {
    tearDown(() => debugWebOverride = null);

    test('de app opent /about/, het web de homepage', () {
      debugWebOverride = false;
      expect(aboutPagePath, '/about/');
      debugWebOverride = true;
      expect(aboutPagePath, '/');
    });

    test('alles over downloaden staat tussen de markeringen die build_site.sh weghaalt', () {
      final html = File('site/index.html').readAsStringSync();
      expect('<!--dl-->'.allMatches(html).length, '<!--/dl-->'.allMatches(html).length);
      final about = html.replaceAll(RegExp(r'<!--dl-->[\s\S]*?<!--/dl-->'), '');
      for (final s in ['.apk', 'Obtainium', 'macromatrix-releases', '#download', 'Download']) {
        expect(about, isNot(contains(s)), reason: s);
      }
      expect(about, contains('id="pricing"'));
      expect(about, contains('id="faq"'));
      expect(File('tool/build_site.sh').readAsStringSync(), contains('build/site/about/index.html'));
      expect(File('site/_headers').readAsStringSync(), contains('/about/*'));
    });

    test('NW-7: geen "nearly everything" meer op de homepage', () {
      expect(File('site/index.html').readAsStringSync(), isNot(contains('nearly everything')));
    });
  });
}
