import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart' show PostgrestException;
import 'package:macromatrix/app_version.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/labs/markers.dart';
import 'package:macromatrix/nutrition/challenges.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/state/challenge_days.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/challenges.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/name_filter.dart';
import 'package:macromatrix/ui/screens/labs_screen.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/about_links.dart';
import 'package:macromatrix/ui/widgets/challenges_view.dart';

import 'challenges_test.dart' show FakeChallengeServer;

/// Bevindingen van de Google Play-reviewer, ronde 11 (GP-2, GP-3, GP-5, GP-7, GP-8, GP-9).

/// Vrienden met een nagebootste server voor uitdagingen, en blokkeren/melden die alleen onthouden wat er gevraagd
/// werd (de echte RPC's staan in block_report_supabase_test.dart).
class _Friends extends Friends {
  _Friends(super.state, super.account, this.server);
  final FakeChallengeServer server;
  final blockedIds = <String>[];
  final reports = <(String, String)>[];

  late final Challenges _challenges = Challenges(state, account, remote: () => server);

  @override
  Challenges get challenges => _challenges;

  @override
  Future<bool> block(String id, {String name = '', String? avatar}) async {
    blockedIds.add(id);
    blocked = [BlockedUser(id: id, name: name, avatar: avatar), ...blocked];
    notifyListeners();
    return true;
  }

  @override
  Future<String?> report(String id, String reason, {String? note}) async {
    reports.add((id, reason));
    return 'reported';
  }
}

void main() {
  late FoodDb foods;
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting('en');
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
  });

  AppState newState() => AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));

  Future<void> pump(WidgetTester tester, List<SingleChildWidget> providers, Widget home) async {
    tester.view.physicalSize = const Size(412, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: providers,
        child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('GP-2 Pro zonder winkel', () {
    testWidgets('geen actieve abonneerknop, wel meteen "Coming soon" op die plek', (tester) async {
      final s = newState();
      await pump(tester, [ChangeNotifierProvider<AppState>.value(value: s)], const ProScreen());
      expect(find.byKey(const ValueKey('pro-subscribe')), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Subscribe'), findsNothing);
      final soon = find.byKey(const ValueKey('pro-coming-soon'));
      expect(soon, findsOneWidget);
      expect(find.descendant(of: soon, matching: find.textContaining('Coming soon')), findsOneWidget);
      // Direct onder de prijzen, niet pas onderaan de pagina
      final prices = tester.getRect(find.byKey(const ValueKey('pro-prices')));
      expect(prices.contains(tester.getCenter(soon)), isTrue);
      // GP-3: geen "onbeperkt" meer, wel de echte grens
      expect(find.textContaining('Unlimited'), findsNothing);
      expect(find.textContaining('up to 50 photos a day'), findsOneWidget);
    });
  });

  group('GP-5 Over in Instellingen', () {
    testWidgets('privacybeleid, voorwaarden, account verwijderen, contact en versie', (tester) async {
      final s = newState();
      final opened = <String>[];
      final before = openAboutLink;
      openAboutLink = (t) async => opened.add(t);
      addTearDown(() => openAboutLink = before);
      await pump(tester, [
        ChangeNotifierProvider<AppState>.value(value: s),
        ChangeNotifierProvider<Account>(create: (_) => Account(s.user, onRemoteChanges: () {})),
        Provider.value(value: Reminders(s)),
      ], const SettingsScreen());
      for (final k in ['privacy', 'terms', 'delete', 'contact']) {
        await tester.ensureVisible(find.byKey(ValueKey('about-$k')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('about-$k')));
        await tester.pump();
      }
      expect(opened, ['/privacy/', '/terms/', '/delete-account/', 'mailto:support@macromatrix.eu']);
      expect(find.text('Privacy policy'), findsOneWidget);
      expect(find.text('support@macromatrix.eu'), findsOneWidget);
      expect(find.text('MacroMatrix version $appVersion'), findsOneWidget);
    });

    test('de getoonde versie is die van pubspec.yaml', () {
      final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(appVersion, v);
    });
  });

  group('GP-7 uitdagingen melden en blokkeren', () {
    testWidgets('titel melden, en een medespeler die geen vriend is blokkeren of melden', (tester) async {
      final s = newState();
      final server = FakeChallengeServer();
      late _Friends f;
      const t = ChallengeTemplate(id: 'custom', nutrient: 'fiber', rule: ChallengeRule.min, amount: 25, days: 14, title: 'Fibre fortnight');
      final n = logicalNow();
      final start = DateTime(n.year, n.month, n.day);
      s.addChallenge(t, start, remoteId: 'srv-9', owner: false);
      await pump(tester, [
        ChangeNotifierProvider<AppState>.value(value: s),
        ChangeNotifierProvider<Account>(create: (_) => Account(s.user, onRemoteChanges: () {})),
        ChangeNotifierProvider<Friends>(
          create: (_) {
            f = _Friends(s, Account(s.user, onRemoteChanges: () {}), server);
            f.challenges.remoteById = {
              'srv-9': RemoteChallenge(
                id: 'srv-9',
                template: t,
                start: start,
                members: const [
                  RemoteMember(id: 'me', name: 'Me', me: true),
                  RemoteMember(id: 'owner-1', name: 'Olga', met: 1),
                  RemoteMember(id: 'stranger-2', name: 'Sam', met: 0),
                ],
              ),
            };
            return f;
          },
        ),
      ], const Scaffold(body: SingleChildScrollView(child: ChallengesPanel())));

      // De titel melden via het menu van de kaart
      await tester.tap(find.byKey(Key('challenge-menu-${s.activeChallenges.single.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report challenge'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Fibre fortnight'), findsWidgets);
      await tester.enterText(find.byKey(const Key('challenge-report-note')), 'rude');
      await tester.tap(find.byKey(const Key('challenge-report-send')));
      await tester.pumpAndSettle();
      expect(server.reported, {'srv-9': 'rude'});
      expect(find.textContaining('We received your report'), findsOneWidget);

      // Sam (geen vriend) melden: menu op zijn rij in de ranglijst
      expect(find.text('Sam'), findsOneWidget);
      await tester.tap(find.byKey(const Key('safety-stranger-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('report-inappropriate')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-send')));
      await tester.pumpAndSettle();
      expect(f.reports, [('stranger-2', 'inappropriate')]);

      // En blokkeren: hij verdwijnt meteen uit de ranglijst
      await tester.tap(find.byKey(const Key('safety-stranger-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Block').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('block-confirm')));
      await tester.pumpAndSettle();
      expect(f.blockedIds, ['stranger-2']);
      expect(find.text('Sam'), findsNothing);
      expect(find.text('Olga'), findsOneWidget);
    });

    testWidgets('eigen uitdaging: niet te melden; zonder de migratie verdwijnt "Report challenge"', (tester) async {
      final s = newState();
      final server = FakeChallengeServer()..reportMissing = true;
      late _Friends f;
      const t = ChallengeTemplate(id: 'custom', nutrient: 'fiber', rule: ChallengeRule.min, amount: 25, days: 14);
      final n = logicalNow();
      final start = DateTime(n.year, n.month, n.day);
      final other = s.addChallenge(t, start, remoteId: 'srv-1', owner: false);
      s.addChallenge(t, start, remoteId: 'srv-2');
      await pump(tester, [
        ChangeNotifierProvider<AppState>.value(value: s),
        ChangeNotifierProvider<Account>(create: (_) => Account(s.user, onRemoteChanges: () {})),
        ChangeNotifierProvider<Friends>(
          create: (_) {
            f = _Friends(s, Account(s.user, onRemoteChanges: () {}), server);
            return f;
          },
        ),
      ], const Scaffold(body: SingleChildScrollView(child: ChallengesPanel())));
      final mine = s.activeChallenges.firstWhere((c) => c.owner);
      await tester.tap(find.byKey(Key('challenge-menu-${mine.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Report challenge'), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('challenge-menu-${other.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report challenge'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('challenge-report-send')));
      await tester.pumpAndSettle();
      expect(f.challenges.reportAvailable, isFalse);
      expect(f.challenges.groupAvailable, isTrue, reason: 'uitdagingen zelf werken gewoon verder');
      await tester.tap(find.byKey(Key('challenge-menu-${other.id}')));
      await tester.pumpAndSettle();
      expect(find.text('Report challenge'), findsNothing);
    });
  });

  group('GP-8 woordfilter', () {
    test('hele woorden, ook verbogen of met cijfers; geen stukjes van woorden', () {
      for (final t in ['Fuck you nazi', 'sh1t', 'B1tch', 'FUUUCK', 'motherfucker', 'kankerlijer', 'Klootzak!', 'sieg  heil', 'Kut-dag']) {
        expect(textBlocked(t), isTrue, reason: t);
      }
      for (final t in [
        'Scunthorpe',
        'Shiitake week',
        'shitake',
        'Catering',
        'Dick',
        'Vezels 30 dagen',
        'Analyse',
        'Sluiten',
        'Wankel',
        'Anna',
        '',
        null,
      ]) {
        expect(textBlocked(t), isFalse, reason: t);
      }
    });

    test('dezelfde lijsten en tekens als de migratie op de server', () {
      final sql = File('supabase/migrations/20261105100000_moderation.sql').readAsStringSync();
      List<String> arrayIn(String fn) {
        final body = RegExp('function public\\.$fn\\(\\)[\\s\\S]*?array\\[([\\s\\S]*?)\\]').firstMatch(sql)!.group(1)!;
        return [
          for (final line in body.split('\n'))
            for (final m in RegExp(r"'([^']*)'").allMatches(line.split('--').first)) m.group(1)!,
        ];
      }

      expect(arrayIn('blocked_words'), blockedWords);
      expect(arrayIn('blocked_stems'), blockedStems);
      expect(sql, contains("translate(lower(p), 'áàâäãåéèêëíìîïóòôöõúùûüçñ013457@\$', 'aaaaaaeeeeiiiiooooouuuucnoieastas')"));
    });

    test('foutmelding van de server wordt een vriendelijke tekst', () {
      expect(moderationMessage(const PostgrestException(message: 'name_not_allowed', code: '22023')), nameNotAllowedText);
      expect(moderationMessage(const PostgrestException(message: 'title_not_allowed', code: '22023')), titleNotAllowedText);
      expect(moderationMessage(const PostgrestException(message: 'iets anders')), isNull);
      expect(moderationMessage(Exception('name_not_allowed')), isNull);
    });

    test('vriendennaam: een scheldnaam gaat niet naar de server', () async {
      final s = newState();
      final f = Friends(s, Account(s.user, onRemoteChanges: () {}));
      addTearDown(f.dispose);
      await f.setName('Fuck you nazi');
      expect(f.error, nameNotAllowedText);
    });

    testWidgets('nieuwe uitdaging: een scheldtitel geeft meteen uitleg en kan niet starten', (tester) async {
      final s = newState();
      await pump(tester, [
        ChangeNotifierProvider<AppState>.value(value: s),
        ChangeNotifierProvider<Account>(create: (_) => Account(s.user, onRemoteChanges: () {})),
        ChangeNotifierProvider<Friends>(create: (_) => Friends(s, Account(s.user, onRemoteChanges: () {}))),
      ], const Scaffold(body: SingleChildScrollView(child: ChallengesPanel())));
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Your own challenge'));
      await tester.tap(find.text('Your own challenge'));
      await tester.pumpAndSettle();
      final name = find.widgetWithText(TextField, 'Name (optional)');
      await tester.ensureVisible(name);
      await tester.enterText(name, 'Kut uitdaging');
      await tester.pump();
      expect(find.text(titleNotAllowedText), findsOneWidget);
      await tester.ensureVisible(find.text('Start challenge'));
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start challenge')).onPressed, isNull);
      await tester.enterText(name, 'Fibre fortnight');
      await tester.pump();
      expect(find.text(titleNotAllowedText), findsNothing);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Start challenge')).onPressed, isNotNull);
    });
  });

  group('GP-9 bloedwaarden zonder dosissen of diagnoses', () {
    test('geen dosissen, geen oorzaken of ziektes, altijd de arts', () {
      final dose = RegExp(r'\d+\s*(–\s*\d+\s*)?(µg|mg|IU|IE)\b');
      const banned = [
        'fatty liver',
        'vette lever',
        'gout',
        'jicht',
        'anaemia',
        'bloedarmoede',
        'heart and vascular disease',
        'hart- en vaatziekten',
        'usually from',
        'meestal door',
      ];
      for (final m in labMarkers) {
        for (final t in [?m.lowText, ?m.highText]) {
          for (final x in [t.$1, t.$2]) {
            expect(dose.hasMatch(x), isFalse, reason: '${m.key}: $x');
            for (final b in banned) {
              expect(x.toLowerCase(), isNot(contains(b)), reason: '${m.key}: $x');
            }
          }
          expect(t.$1, contains('doctor'), reason: m.key);
          expect(t.$2, contains('arts'), reason: m.key);
        }
      }
    });

    testWidgets('vaste uitleg bovenaan het scherm, de waarden blijven naast de normaal', (tester) async {
      final user = UserDb(sqlite3.openInMemory());
      user.saveLabs(
        dayKey(DateTime.now()),
        parseLabReport(const [
          ['Ferritine', '-', '18', 'µg/L', '30 - 400'],
        ]).values,
      );
      final s = AppState(foods: foods, user: user);
      await pump(tester, [ChangeNotifierProvider<AppState>.value(value: s)], const LabsScreen());
      expect(find.byKey(const ValueKey('labs-disclaimer')), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      expect(find.textContaining('Ferritin low'), findsOneWidget);
      expect(find.textContaining('what it means for your eating'), findsNothing);
      expect(find.textContaining('µg (400'), findsNothing);
    });
  });
}
