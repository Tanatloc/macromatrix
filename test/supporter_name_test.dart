// De betaalde laag heet in alles wat je ziet "Supporter" (niet meer "Pro"): het scherm, de chips en de knoppen
// passen op een smalle telefoon (360 breed), en "Supporter" staat nooit twee keer onder elkaar (SU-11, SO-9).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/ui/screens/friends_screen.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/screens/recap_screen.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/ai_quota_note.dart';
import 'package:macromatrix/ui/widgets/badges_view.dart';
import 'package:macromatrix/ui/widgets/battles_view.dart';
import 'package:macromatrix/ui/widgets/level_card.dart';
import 'package:macromatrix/ui/widgets/pro_widgets.dart';

import 'pro_test.dart' show FakeProRemote, newPro, newState, quota;

/// Zoals pump in pro_test.dart, maar op een smalle telefoon van 360 breed.
Future<void> pumpPhone(WidgetTester tester, AppState s, Pro? pro, Widget home, {Friends? friends, Account? account}) async {
  tester.view.physicalSize = const Size(360, 3400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: s),
        if (pro != null) ChangeNotifierProvider<Pro>.value(value: pro),
        if (friends != null) ChangeNotifierProvider<Friends>.value(value: friends),
        if (account != null) ChangeNotifierProvider<Account>.value(value: account),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// Geen enkele zichtbare tekst noemt nog "Pro" (behalve de debugschakelaar, die alleen in een debug-build staat).
void expectNoPro(WidgetTester tester) {
  final texts = [
    for (final t in tester.widgetList<Text>(find.byType(Text)))
      if (find.ancestor(of: find.byWidget(t), matching: find.byKey(const ValueKey('pro-debug'))).evaluate().isEmpty)
        t.data ?? t.textSpan?.toPlainText() ?? '',
  ];
  for (final t in texts) {
    expect(RegExp(r'\bPro\b').hasMatch(t), isFalse, reason: 'nog "Pro" in "$t"');
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en_GB');
    await initializeDateFormatting('nl_BE');
  });
  tearDown(() => setAppLang(AppLang.en));

  for (final lang in AppLang.values) {
    group('360 breed (${lang.name})', () {
      setUp(() => setAppLang(lang));

      testWidgets('Supporter-scherm: gratis, dan supporter; niets loopt over', (tester) async {
        final s = newState();
        final server = FakeProRemote()..photo = quota(1);
        final pro = newPro(s, server);
        await pumpPhone(tester, s, pro, const ProScreen());
        expect(tester.takeException(), isNull);
        expect(find.text('Supporter'), findsWidgets);
        expectNoPro(tester);

        server.status = ProStatus(until: DateTime(2099, 3, 1), source: 'manual');
        await pro.refresh();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text(tr('You are a supporter', 'Je bent supporter')), findsOneWidget);
        // Naast "Je bent supporter" alleen het hartje, niet nog eens het woord Supporter
        final badge = tester.widget<SupporterBadge>(find.byType(SupporterBadge));
        expect(badge.compact, isTrue);
        expectNoPro(tester);
      });

      testWidgets('Instellingen: kleur en achtergrond met het SUPPORTER-label', (tester) async {
        final s = newState();
        final pro = newPro(s, FakeProRemote());
        await pumpPhone(
          tester,
          s,
          pro,
          Provider.value(value: Reminders(s), child: const SettingsScreen()),
          account: pro.account,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(ProTag), findsWidgets);
        expect(find.text('SUPPORTER'), findsWidgets);
        expect(find.text(tr('Become a supporter', 'Supporter worden')), findsOneWidget);
        expectNoPro(tester);
      });

      testWidgets('badges op slot: het label past in de badge van 72 breed', (tester) async {
        final s = newState();
        final pro = newPro(s, FakeProRemote());
        final f = Friends(s, pro.account, pro: pro);
        await pumpPhone(
          tester,
          s,
          pro,
          const Scaffold(body: SingleChildScrollView(child: BadgesCard())),
          friends: f,
        );
        await tester.tap(find.text(tr('All badges', 'Alle badges')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(ProTag), findsWidgets);
        for (final tag in tester.widgetList<ProTag>(find.byType(ProTag))) {
          expect(tag.compact, isTrue);
        }
        for (final e in find.byType(ProTag).evaluate()) {
          expect(e.size!.width, lessThanOrEqualTo(72));
        }
        expectNoPro(tester);
        await tester.pumpWidget(const SizedBox());
        f.dispose();
      });

      testWidgets('uitgebreid jaaroverzicht: SUPPORTER naast de titels', (tester) async {
        final s = newState();
        final now = logicalNow();
        final pro = newPro(s, FakeProRemote())..setDebugPro(true);
        await pumpPhone(tester, s, pro, RecapScreen(from: DateTime(now.year), year: true));
        expect(tester.takeException(), isNull);
        expectNoPro(tester);
        pro.setDebugPro(null);
      });

      testWidgets('foto- en etiketteller: de Supporter-knop past', (tester) async {
        final s = newState();
        await pumpPhone(tester, s, null, Scaffold(body: PhotoQuotaNote(quota: quota(3), pro: false)));
        expect(tester.takeException(), isNull);
        expect(find.descendant(of: find.byKey(const ValueKey('photo-quota-pro')), matching: find.text('Supporter')), findsOneWidget);
        expectNoPro(tester);

        await pumpPhone(
          tester,
          s,
          null,
          Scaffold(
            body: AiQuotaNote(kind: AiKind.label, quota: quota(1, limit: 1), pro: false),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            tr(
              'Free label scan used today, back tomorrow, or become a supporter.',
              'Gratis etiketscan van vandaag gebruikt. Morgen kan het weer, of word supporter.',
            ),
          ),
          findsOneWidget,
        );
        expectNoPro(tester);

        await pumpPhone(tester, s, null, const Scaffold(body: AiQuotaNote(kind: AiKind.recipe, quota: null, pro: false)));
        expect(tester.takeException(), isNull);
        expect(find.descendant(of: find.byKey(const ValueKey('ai-quota-pro-recipe')), matching: find.text('Supporter')), findsOneWidget);
        expectNoPro(tester);
      });
    });
  }

  group('nooit twee keer Supporter (SU-11, SO-9)', () {
    setUp(() => setAppLang(AppLang.en));

    test('showSupporterBadge: niet als de titel al Supporter is', () {
      expect(showSupporterBadge(supporter: true, title: 'rookie'), isTrue);
      expect(showSupporterBadge(supporter: true), isTrue);
      expect(showSupporterBadge(supporter: true, title: 'supporter'), isFalse);
      expect(showSupporterBadge(supporter: false, title: 'founder'), isFalse);
    });

    testWidgets('ranglijst: titel Supporter, dan geen hartje ernaast', (tester) async {
      final s = newState();
      Widget tile(String title) => Scaffold(
        body: RankTile(
          row: RankRow(name: 'An', avatar: null, level: 3, supporter: true, title: title),
          place: 1,
          byLevel: false,
        ),
      );
      await pumpPhone(tester, s, null, tile('founder'));
      expect(find.byKey(const ValueKey('supporter-badge')), findsOneWidget);
      await pumpPhone(tester, s, null, tile('supporter'));
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
      expect(find.text('Supporter'), findsOneWidget);
    });

    testWidgets('je Profiel (levelkaart): titel Supporter, dan geen badge ernaast', (tester) async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime.now().add(const Duration(days: 30)));
      final pro = newPro(s, server);
      await pro.refresh();
      s.setTitle('rookie');
      await pumpPhone(tester, s, pro, const Scaffold(body: SingleChildScrollView(child: LevelCard())));
      expect(find.byKey(const ValueKey('supporter-badge')), findsOneWidget);
      s.setTitle('supporter');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
      expect(find.text('Supporter'), findsOneWidget);
    });

    testWidgets('profiel van een vriend: chip alleen als de titel niet Supporter is', (tester) async {
      final s = newState();
      final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
      final f = Friends(s, account);
      Future<void> open(String title) async {
        f.list = [Friend(id: 'lotte', name: 'Lotte', state: FriendState.friend, level: 3, title: title, supporter: true)];
        // Een vers scherm, zonder het blad van daarnet
        await tester.pumpWidget(const SizedBox());
        await pumpPhone(
          tester,
          s,
          null,
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(onPressed: () => showFriendSheet(context, f.list.first), child: const Text('open')),
            ),
          ),
          friends: f,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      }

      await open('founder');
      expect(find.byKey(const ValueKey('supporter-badge')), findsOneWidget);
      expect(find.text('Level 3 · Founder'), findsOneWidget);

      await open('supporter');
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
      expect(find.text('Level 3 · Supporter'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      f.dispose();
    });
  });
}
