import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/friends_screen.dart';
import 'package:macromatrix/ui/theme.dart';

import 'pro_test.dart' show newState;

/// Ingelogd zonder server: genoeg om het vriendenscherm te tonen.
class _SignedIn extends Account {
  _SignedIn(super.db) : super(onRemoteChanges: () {});
  @override
  bool get signedIn => true;
}

/// Friends zonder server: houdt bij wat er geblokkeerd, gedeblokkeerd en gemeld wordt.
class _FakeFriends extends Friends {
  _FakeFriends(super.state, super.account);

  List<Friend> server = const [];
  bool serverKnowsBlocks = true;
  final blockedIds = <String>[];
  final unblockedIds = <String>[];
  final reports = <(String, String, String?)>[];

  @override
  Future<void> load({String? newName}) async {
    code = 'ABCD1234';
    list = [
      for (final x in server)
        if (!blocked.any((b) => b.id == x.id)) x,
    ];
    blockAvailable = serverKnowsBlocks;
    notifyListeners();
  }

  @override
  Future<bool> block(String id, {String name = '', String? avatar}) async {
    blockedIds.add(id);
    blocked = [BlockedUser(id: id, name: name, avatar: avatar), ...blocked];
    await load();
    return true;
  }

  @override
  Future<bool> unblock(String id) async {
    unblockedIds.add(id);
    blocked = [
      for (final b in blocked)
        if (b.id != id) b,
    ];
    await load();
    return true;
  }

  @override
  Future<String?> report(String id, String reason, {String? note}) async {
    reports.add((id, reason, note));
    return 'reported';
  }
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() => setAppLang(AppLang.en));

  Future<_FakeFriends> pumpFriends(WidgetTester tester, AppState s, {List<Friend> server = const [], bool knows = true}) async {
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
          ChangeNotifierProvider<Friends>(
            create: (_) => f = _FakeFriends(s, account)
              ..server = server
              ..serverKnowsBlocks = knows,
          ),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const FriendsScreen(active: false)),
      ),
    );
    await f.load();
    await tester.pumpAndSettle();
    return f;
  }

  const jens = Friend(id: 'jens', name: 'Jens', state: FriendState.friend, score: 70, days: 2);

  group('Blokkeren', () {
    testWidgets('vanuit het menu in de ranglijst, na bevestigen; daarna in Geblokkeerd met Deblokkeren', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [jens]);
      expect(find.text('Blocked'), findsNothing);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Remove friend'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();

      // Bevestigen: annuleren doet niets
      expect(find.text('Block Jens?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.blockedIds, isEmpty);

      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-confirm')));
      await tester.pumpAndSettle();
      expect(f.blockedIds, ['jens']);
      expect(find.text('Jens is blocked.'), findsOneWidget);

      // Weg uit de ranglijst, wel bij Geblokkeerd
      expect(find.text('Blocked'), findsOneWidget);
      expect(find.byKey(const Key('unblock-jens')), findsOneWidget);
      await tester.tap(find.byKey(const Key('unblock-jens')));
      await tester.pumpAndSettle();
      expect(f.unblockedIds, ['jens']);
      expect(find.text('Blocked'), findsNothing);
    });

    testWidgets('een binnenkomend verzoek heeft ook Blokkeren', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [Friend(id: 'x', name: 'Xavier', state: FriendState.incoming)]);
      expect(find.text('1 friend request'), findsOneWidget);
      await tester.tap(find.byKey(const Key('safety-x')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-confirm')));
      await tester.pumpAndSettle();
      expect(f.blockedIds, ['x']);
      expect(find.text('1 friend request'), findsNothing);
    });

    testWidgets('zonder de migratie op de server: geen Blokkeren of Melden', (tester) async {
      await pumpFriends(tester, newState(), server: const [jens, Friend(id: 'x', name: 'Xavier', state: FriendState.incoming)], knows: false);
      expect(find.byKey(const Key('safety-x')), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Remove friend'), findsOneWidget);
      expect(find.text('Block'), findsNothing);
      expect(find.text('Report'), findsNothing);
    });
  });

  group('Melden', () {
    testWidgets('reden kiezen (verplicht) en een optionele notitie', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [jens]);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report Jens'), findsOneWidget);
      for (final label in ['Spam', 'Harassment or bullying', 'Inappropriate name or photo', 'Something else']) {
        expect(find.text(label), findsOneWidget);
      }
      // Zonder reden kan je niet versturen
      expect(tester.widget<FilledButton>(find.byKey(const Key('report-send'))).onPressed, isNull);

      await tester.tap(find.byKey(const Key('report-inappropriate')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('report-note')), 'Offensive photo');
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(f.reports, [('jens', 'inappropriate', 'Offensive photo')]);
      expect(find.textContaining('received your report'), findsOneWidget);
      // Melden alleen blokkeert niet
      expect(f.blockedIds, isEmpty);
    });

    testWidgets('annuleren stuurt niets', (tester) async {
      final f = await pumpFriends(tester, newState(), server: const [jens]);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-spam')));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.reports, isEmpty);
    });

    testWidgets('in het Nederlands', (tester) async {
      setAppLang(AppLang.nl);
      await pumpFriends(tester, newState(), server: const [jens]);
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('Blokkeren'), findsOneWidget);
      await tester.tap(find.text('Melden'));
      await tester.pumpAndSettle();
      expect(find.text('Jens melden'), findsOneWidget);
      expect(find.text('Pesten of lastigvallen'), findsOneWidget);
    });
  });
}
