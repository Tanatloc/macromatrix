import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/badges.dart';
import 'package:macromatrix/nutrition/challenges.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/challenges.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/friends_screen.dart';
import 'package:macromatrix/ui/shell.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/avatar.dart';
import 'package:macromatrix/ui/widgets/battles_view.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

import 'pro_test.dart' show newState;

/// Ingelogd zonder server: genoeg om het vriendenscherm te tonen.
class _SignedIn extends Account {
  _SignedIn(super.db) : super(onRemoteChanges: () {});
  @override
  bool get signedIn => true;
}

/// Friends zonder server. [load] doet wat de echte doet: meteen "bezig" melden (dus synchroon, net als de echte),
/// even wachten en dan de lijst van [server] zetten. Zo zie je of een melding midden in een bouwbeurt het scherm
/// laat hangen (S01, S03).
class _FakeFriends extends Friends {
  _FakeFriends(super.state, super.account);

  List<Friend> server = const [];
  List<Battle> serverBattles = const [];
  int loads = 0;
  final added = <String>[];

  @override
  Future<void> load({String? newName}) async {
    loads++;
    loading = true;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    code = 'ABCD1234';
    list = server;
    battles = serverBattles;
    loading = false;
    notifyListeners();
  }

  /// Wat de poll van 20 s zou binnenhalen.
  void serverChanged() => notifyListeners();

  @override
  Future<AddResult> add(String code) async {
    added.add(code);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final clean = code.replaceAll(RegExp('[^A-Za-z0-9]'), '').toUpperCase();
    final r = clean == 'JENS0001' ? 'friends' : 'not_found';
    return AddResult(r, addMessage(r, name: 'Jens'));
  }

  @override
  Future<void> respondBattle(Battle b, bool accept) async {
    serverBattles = [
      for (final x in serverBattles)
        if (x.id != b.id) x else if (accept) x.copyWith(accepted: true),
    ];
    await load();
  }
}

Battle _battle(String id, {required bool byMe, bool accepted = false, String name = 'Jens'}) =>
    Battle(id: id, week: mondayOf(DateTime.now()), challengedByMe: byMe, accepted: accepted, other: 'u-$id', otherName: name);

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() => setAppLang(AppLang.en));

  Future<_FakeFriends> pumpFriends(WidgetTester tester, AppState s, {Size size = const Size(412, 3000)}) async {
    final account = _SignedIn(s.user);
    late _FakeFriends f;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: s),
          ChangeNotifierProvider<Account>.value(value: account),
          ChangeNotifierProvider<Friends>(create: (_) => f = _FakeFriends(s, account)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const FriendsScreen()),
      ),
    );
    // Na de eerste frame begint het laden; daarna komt de lijst binnen
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return f;
  }

  group('S01/S03: laden vanuit initState', () {
    testWidgets('het scherm bouwt opnieuw bij elke latere melding (geen hangende bouwbeurt)', (tester) async {
      final s = newState();
      final f = await pumpFriends(tester, s);
      // Geen fout "setState() or markNeedsBuild() called during build" en de eerste lijst staat er
      expect(tester.takeException(), isNull);
      expect(f.loads, 1);
      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(find.textContaining('No friends yet'), findsOneWidget);

      // Een verzoek komt binnen via de poll: meteen zichtbaar, zonder ergens te tikken
      f.list = const [Friend(id: 'j', name: 'Jens', state: FriendState.incoming)];
      f.serverChanged();
      await tester.pump();
      expect(find.text('1 friend request'), findsOneWidget);

      // Aanvaard (de lijst verandert, hetzelfde aantal rijen): ook dat verschijnt meteen
      f.list = const [Friend(id: 'j', name: 'Jens', state: FriendState.friend, score: 80, days: 2)];
      f.serverChanged();
      await tester.pump();
      expect(find.text('1 friend request'), findsNothing);
      expect(find.text('Jens'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);

      // En een nieuwe score bij dezelfde vriend
      f.list = const [Friend(id: 'j', name: 'Jens', state: FriendState.friend, score: 93, days: 3)];
      f.serverChanged();
      await tester.pump();
      expect(find.text('93'), findsOneWidget);
    });

    testWidgets('een widget die in initState laadt, blijft daarna bijwerken', (tester) async {
      // Algemene vorm van de fout: load() meldt synchroon "bezig". Met het laden na de frame gaat er geen
      // melding verloren en volgt het scherm elke latere melding.
      final s = newState();
      final f = await pumpFriends(tester, s);
      for (var i = 1; i <= 3; i++) {
        f.list = [for (var j = 0; j < i; j++) Friend(id: 'f$j', name: 'Friend $j', state: FriendState.friend)];
        f.serverChanged();
        await tester.pump();
        expect(find.textContaining('Friend '), findsNWidgets(i));
      }
    });
  });

  group('S02/S06: battles', () {
    testWidgets('een inkomende uitdaging verschijnt na de poll met Weigeren/Aanvaarden, en het bolletje klopt', (tester) async {
      final s = newState();
      final f = await pumpFriends(tester, s);
      expect(find.textContaining('No battle this week'), findsOneWidget);

      f.battles = [_battle('b1', byMe: false)];
      f.serverChanged();
      await tester.pump();
      expect(find.text('Jens challenges you this week'), findsOneWidget);
      final invite = find.byKey(const ValueKey('battle-invite-b1'));
      expect(find.descendant(of: invite, matching: find.text('Decline')), findsOneWidget);
      expect(find.descendant(of: invite, matching: find.text('Accept')), findsOneWidget);
      // Dezelfde telling als het bolletje op het tabblad
      expect(f.battles.where((b) => b.pending && !b.challengedByMe).length, 1);

      // Aanvaarden: de uitnodiging verdwijnt en de battle staat er
      f.serverBattles = f.battles;
      await tester.tap(find.descendant(of: invite, matching: find.text('Accept')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('Jens challenges you this week'), findsNothing);
      expect(find.text('VS'), findsOneWidget);
      // De battle zegt waarom de punten anders zijn dan de ranglijst
      expect(find.textContaining('The leaderboard shows the average'), findsOneWidget);
    });

    testWidgets('je eigen open uitdaging staat op de kaart met Annuleren', (tester) async {
      final s = newState();
      final f = await pumpFriends(tester, s);
      f.battles = [_battle('b2', byMe: true, name: 'Marc')];
      f.serverChanged();
      await tester.pump();
      final row = find.byKey(const ValueKey('battle-sent-b2'));
      expect(find.descendant(of: row, matching: find.text('Waiting for Marc to accept')), findsOneWidget);
      expect(find.descendant(of: row, matching: find.text('Cancel')), findsOneWidget);
    });

    test('melding als een verstuurde uitdaging geweigerd of aanvaard werd', () {
      final before = {'b1': 'Marc', 'b2': 'Lotte', 'b3': 'Jens'};
      final (messages, open) = sentBattleNotices(before, [
        _battle('b2', byMe: true, accepted: true, name: 'Lotte'),
        _battle('b3', byMe: true, name: 'Jens'),
        _battle('b4', byMe: true, name: 'Anna'),
      ]);
      expect(messages, ['Marc declined your battle challenge.', 'Lotte accepted your challenge: the battle is on!']);
      expect(open, {'b3': 'Jens', 'b4': 'Anna'});
      // Zelf ingetrokken: geen melding
      final (none, _) = sentBattleNotices({'b1': 'Marc'}, const [], cancelled: {'b1'});
      expect(none, isEmpty);
    });

    test('de uitleg zegt dat je met meerdere vrienden tegelijk een battle kan hebben', () {
      expect(battleRules, contains('several at once'));
    });
  });

  group('S04/S05/S12: vriend toevoegen', () {
    testWidgets('Add wordt actief zodra er een code staat; een foute code blijft staan met de uitleg eronder', (tester) async {
      final s = newState();
      final f = await pumpFriends(tester, s);
      FilledButton add() => tester.widget<FilledButton>(find.byKey(const Key('friend-add')));
      expect(add().onPressed, isNull);

      await tester.enterText(find.byKey(const Key('friend-code')), 'ABCD-1235');
      await tester.pump();
      expect(add().onPressed, isNotNull);

      // Ook tijdens een poll (loading) blijft de knop bruikbaar
      f.loading = true;
      f.serverChanged();
      await tester.pump();
      expect(add().onPressed, isNotNull);
      f.loading = false;

      await tester.tap(find.byKey(const Key('friend-add')));
      await tester.pump(const Duration(milliseconds: 10));
      expect(f.added, ['ABCD-1235']);
      // De code blijft staan, de uitleg staat onder het veld (geen melding over "Your code")
      expect(find.text('ABCD-1235'), findsOneWidget);
      expect(find.text('No account found with that code. Check the letters and numbers.'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(add().onPressed, isNotNull);

      // Typen wist de uitleg; de code van een bestaande vriend: "al vrienden", en het veld wordt leeg
      await tester.enterText(find.byKey(const Key('friend-code')), 'jens 0001');
      await tester.pump();
      expect(find.textContaining('No account found'), findsNothing);
      await tester.tap(find.byKey(const Key('friend-add')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(find.text('You\'re already friends with Jens.'), findsOneWidget);
      expect(find.text('jens 0001'), findsNothing);
    });

    test('teksten bij de uitkomsten van friend_add', () {
      expect(addMessage('friends', name: 'Jens'), 'You\'re already friends with Jens.');
      expect(addMessage('friends'), 'You are already friends.');
      expect(addMessage('accepted', name: 'Lotte'), 'You and Lotte are now friends.');
      expect(const AddResult('not_found', '').clearField, isFalse);
      expect(const AddResult('self', '').clearField, isFalse);
      expect(const AddResult(null, '').clearField, isFalse);
      expect(const AddResult('friends', '').clearField, isTrue);
      setAppLang(AppLang.nl);
      expect(addMessage('friends', name: 'Jens'), 'Je bent al vrienden met Jens.');
    });
  });

  group('S07: eigen uitdaging', () {
    test('koolhydraten staan in de lijst', () {
      expect(challengeNutrients, containsAll(['carbs', 'sugars']));
    });

    testWidgets('volledige labels en vragen voor je een ingevuld formulier weggooit', (tester) async {
      final s = newState();
      await pumpFriends(tester, s);
      await tester.ensureVisible(find.text('New'));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Your own challenge'));
      await tester.tap(find.text('Your own challenge'));
      await tester.pumpAndSettle();
      expect(find.text('Per day'), findsOneWidget);
      expect(find.text('Days'), findsOneWidget);
      expect(find.text('Needed'), findsOneWidget);
      // Het label van de hoeveelheid heeft de volle breedte
      expect(tester.getSize(find.byKey(const Key('challenge-amount'))).width, greaterThan(300));

      await tester.enterText(find.byKey(const Key('challenge-amount')), '30');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Discard this challenge?'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('Per day'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      expect(find.text('Per day'), findsNothing);
      expect(find.text('New challenge'), findsNothing);
    });

    testWidgets('een leeg formulier sluit meteen met Escape', (tester) async {
      final s = newState();
      await pumpFriends(tester, s);
      await tester.ensureVisible(find.text('New'));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('New challenge'), findsNothing);
      expect(find.text('Discard this challenge?'), findsNothing);
    });
  });

  group('S08/S09/S11: badges en titels', () {
    test('een kleinere showcase blijft zoals je ze bewaarde', () {
      const tiers = {'days': 1, 'social': 1};
      expect(showcaseOf(const [], tiers), containsAll(['days', 'social']));
      expect(showcaseOf(const ['days'], tiers, fill: false), ['days']);
      expect(showcaseOf(const [], tiers, fill: false), isEmpty);

      final s = newState();
      final f = Friends(s, Account(s.user, onRemoteChanges: () {}));
      addTearDown(f.dispose);
      f.list = const [Friend(id: 'j', name: 'Jens', state: FriendState.friend)];
      s.setShowcase(const ['social']);
      expect(f.showcase, ['social']);
    });

    test('enkelvoud bij 1 en een titel voor je eerste vriend', () {
      expect(categoryById['battles']!.goal(1), 'Finish 1 battle.');
      expect(categoryById['battles']!.goal(5), 'Finish 5 battles.');
      expect(categoryById['comeback']!.goal(1), 'Win 1 battle you were losing after Wednesday.');
      expect(categoryById['social']!.goal(1), 'Have 1 friend.');
      expect(availableTitles(const {'social': 1}).map((t) => t.id), contains('team_player'));
      expect(availableTitles(const {}).map((t) => t.id), isNot(contains('team_player')));
    });

    test('de badge Sociaal blijft na het verwijderen van je enige vriend', () async {
      final s = newState();
      final f = Friends(s, Account(s.user, onRemoteChanges: () {}));
      addTearDown(f.dispose);
      expect(f.socialBest, 0);
      s.user.setSetting(socialBestSetting, {'n': 1});
      f.list = const [];
      expect(f.socialBest, 1);
      expect(f.tiers['social'], 1);
      f.list = const [
        Friend(id: 'a', name: 'A', state: FriendState.friend),
        Friend(id: 'b', name: 'B', state: FriendState.friend),
        Friend(id: 'c', name: 'C', state: FriendState.incoming),
      ];
      expect(f.socialBest, 2);
    });
  });

  group('S10/S13/S14: ranglijst, teksten en tikdoelen', () {
    testWidgets('geen beker zonder score, "You" zonder "(you)" en de juiste naam voor de score', (tester) async {
      final s = newState();
      final f = await pumpFriends(tester, s);
      f.list = const [Friend(id: 'j', name: 'Jens', state: FriendState.friend), Friend(id: 'm', name: 'Marc', state: FriendState.friend)];
      f.serverChanged();
      await tester.pump();
      // Niemand logde: geen bekers
      expect(find.byIcon(Icons.emoji_events_rounded), findsNothing);
      expect(find.text('You'), findsWidgets);
      expect(find.textContaining('(you)'), findsNothing);
      expect(find.textContaining('average Nutrient score'), findsOneWidget);
      expect(find.textContaining('Voedingsscore'), findsNothing);
      // This week / Level is groot genoeg om te raken
      expect(tester.getSize(find.byWidgetPredicate((w) => w is Segmented).first).height, greaterThanOrEqualTo(44));
    });

    test('RankTile: beker alleen met een score boven 0 (of op level)', () {
      RankTile tile(int? score, {bool byLevel = false, int place = 2}) => RankTile(
        row: RankRow(name: 'x', avatar: null, level: 3, score: score),
        place: place,
        byLevel: byLevel,
      );
      expect(tile(null).medal, isFalse);
      expect(tile(0).medal, isFalse);
      expect(tile(40).medal, isTrue);
      expect(tile(null, byLevel: true).medal, isTrue);
      expect(tile(90, place: 4).medal, isFalse);
    });

    test('groenten zonder "porties porties", en een uitdaging die morgen begint is nog niet gestart', () {
      final veg = builtinChallenges.firstWhere((t) => t.id == 'veg5');
      expect(veg.dailyRule, 'at least 5 portions of vegetables');
      final now = logicalNow();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      expect(Challenges.startedText(tomorrow), 'Challenge set for tomorrow. Good luck!');
      expect(Challenges.startedText(DateTime(now.year, now.month, now.day)), 'Challenge started. Good luck!');
      setAppLang(AppLang.nl);
      expect(veg.dailyRule, 'minstens 5 porties groenten');
      expect(Challenges.startedText(tomorrow), 'Uitdaging staat klaar voor morgen. Succes!');
    });

    testWidgets('Weigeren is een omlijnde knop van minstens 48 px; avatars hebben een naam', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: AnswerButtons(onDecline: () {}, onAccept: () {}),
          ),
        ),
      );
      final decline = find.widgetWithText(OutlinedButton, 'Decline');
      expect(decline, findsOneWidget);
      expect(tester.getSize(decline).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.widgetWithText(FilledButton, 'Accept')).height, greaterThanOrEqualTo(48));
      expect(avatarPresetNames.length, avatarPresets.length);
    });

    testWidgets('avatarkeuze: naam onder elk icoon en voor de schermlezer', (tester) async {
      tester.view.physicalSize = const Size(412, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(onPressed: () => pickAvatar(context, 'preset:11'), child: const Text('open')),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Heart'), findsOneWidget);
      expect(find.text('Dumbbell'), findsOneWidget);
      expect(find.bySemanticsLabel('Heart'), findsOneWidget);
    });
  });

  group('S15: meldingen op een pc', () {
    testWidgets('niet over de zijbalk en niet over de volle breedte', (tester) async {
      setAppLang(AppLang.nl);
      final user = UserDb(sqlite3.openInMemory());
      final state = AppState(
        foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
        user: user,
      );
      final account = Account(user, onRemoteChanges: state.reloadFromDisk);
      tester.view.physicalSize = const Size(1366, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: state),
            ChangeNotifierProvider.value(value: account),
            Provider.value(value: Reminders(state)),
            ChangeNotifierProvider(create: (_) => Friends(state, account)),
          ],
          child: MaterialApp(theme: buildTheme(Brightness.light), home: const Shell()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      ScaffoldMessenger.of(tester.element(find.text('SNEL NAAR'))).showSnackBar(const SnackBar(content: Text('Hallo')));
      await tester.pumpAndSettle();
      final r = tester.getRect(find.descendant(of: find.byType(SnackBar), matching: find.byType(Material)).first);
      expect(r.left, greaterThan(236));
      expect(r.width, lessThanOrEqualTo(560));
    });
  });
}
