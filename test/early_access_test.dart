import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/features.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/roadmap.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/screens/roadmap_screen.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/feature_gate.dart';

import 'pro_test.dart' show FakeProRemote, newState;

/// Een onschuldige vlag, alleen voor deze tests (in de app staat nog niets achter een vlag).
const _demo = 'demo_flag';

/// Nagebootste server voor de vlaggen: een lijst, geen migratie, of geen verbinding.
class FakeFeaturesRemote implements FeaturesRemote {
  List<FeatureFlag> flags = [];
  bool missing = false;
  bool offline = false;
  int calls = 0;

  @override
  Future<List<FeatureFlag>> mine() async {
    calls++;
    if (missing) throw const FeaturesMissing();
    if (offline) throw const SocketException('offline');
    return flags;
  }
}

/// Nagebootste server voor de roadmap: stemmen, een vast antwoord, een fout of geen migratie.
class FakeRoadmapRemote implements RoadmapRemote {
  FakeRoadmapRemote(this.items);
  List<RoadmapItem> items;
  bool missing = false;

  /// Een vast antwoord op roadmap_vote (bv. 'limit'), of null = gewoon stemmen.
  String? answer;
  bool fail = false;
  Completer<void>? gate;
  final votes = <(String, bool)>[];

  @override
  Future<List<RoadmapItem>> list() async {
    if (missing) throw const RoadmapMissing();
    return items;
  }

  @override
  Future<VoteResult> vote(String item, bool on) async {
    votes.add((item, on));
    if (gate != null) await gate!.future;
    if (missing) throw const RoadmapMissing();
    if (fail) throw const SocketException('offline');
    if (answer != null) return voteResultFrom(answer);
    items = [for (final i in items) i.id == item ? i.copyWith(mine: on, votes: i.votes + (on ? 1 : -1)) : i];
    return VoteResult.ok;
  }
}

final _now = DateTime.utc(2026, 11, 2, 12);

FeatureFlag _early({String id = _demo}) => FeatureFlag(
  id: id,
  titleEn: 'Training and rest days',
  titleNl: 'Trainings- en rustdagen',
  earlyFrom: _now.subtract(const Duration(hours: 1)),
  publicFrom: _now.add(const Duration(days: 21)),
);

Future<Pro> _pro(AppState s, {required bool active}) async {
  final server = FakeProRemote()
    ..status = active ? ProStatus(until: DateTime.now().add(const Duration(days: 30)), source: 'manual') : const ProStatus();
  final pro = Pro(Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);
  await pro.refresh();
  return pro;
}

Features _features(Pro pro, FakeFeaturesRemote? server, {Map<String, bool> known = const {_demo: false}, DateTime Function()? clock}) {
  final f = Features(pro.account, pro: pro, remote: () => server, known: known, clock: clock ?? () => _now);
  addTearDown(f.dispose);
  return f;
}

const _items = [
  RoadmapItem(id: 'a', titleEn: 'Training and rest days', titleNl: 'Trainings- en rustdagen', votes: 4),
  RoadmapItem(id: 'b', titleEn: 'Report for your dietitian', titleNl: 'Rapport voor je diëtist', votes: 2, status: RoadmapStatus.planned),
  RoadmapItem(id: 'c', titleEn: 'Deeper insights', titleNl: 'Diepere inzichten', votes: 1),
  RoadmapItem(id: 'd', titleEn: 'Choose your own app icon', titleNl: 'Kies je eigen app-icoon', votes: 0),
  RoadmapItem(id: 'e', titleEn: 'Dark mode', titleNl: 'Donkere modus', votes: 9, mine: true, status: RoadmapStatus.done),
];

Future<void> _pump(WidgetTester tester, AppState s, Pro pro, Widget home, {Features? features}) async {
  tester.view.physicalSize = const Size(412, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: s),
        ChangeNotifierProvider<Pro>.value(value: pro),
        if (features != null) ChangeNotifierProvider<Features>.value(value: features),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  group('Vroege toegang', () {
    test('zonder server of zonder rij: de standaard, en onbekend staat uit', () async {
      final s = newState();
      final pro = await _pro(s, active: true);
      final server = FakeFeaturesRemote();
      final f = _features(pro, server, known: const {_demo: false, 'shipped_on': true});
      await pumpEventQueue();
      expect(server.calls, greaterThan(0));
      expect(f.has(_demo), isFalse);
      expect(f.has('shipped_on'), isTrue);
      expect(f.has('nobody_knows_me'), isFalse);
      expect(f.isEarly(_demo), isFalse);

      // Niet ingelogd (geen server): alleen de standaarden, ook als er iets bewaard is
      server.flags = [_early(id: 'shipped_on').copyWithPublic(null).withEarly(null)];
      await f.refresh();
      expect(f.has('shipped_on'), isFalse);
      final out = _features(pro, null, known: const {_demo: false, 'shipped_on': true});
      expect(out.has('shipped_on'), isTrue);
      expect(out.inEarlyAccess, isEmpty);
    });

    test('de server beslist: eerst supporters, op de publieke dag iedereen', () async {
      final s = newState();
      final supporter = await _pro(s, active: true);
      final server = FakeFeaturesRemote()..flags = [_early()];
      var now = _now;
      final f = _features(supporter, server, clock: () => now);
      await pumpEventQueue();
      expect(f.has(_demo), isTrue);
      expect(f.isEarly(_demo), isTrue);
      expect(f.inEarlyAccess.map((e) => e.id), [_demo]);

      final free = await _pro(newState(), active: false);
      final g = _features(free, server, clock: () => now);
      await pumpEventQueue();
      expect(g.has(_demo), isFalse);
      expect(g.isEarly(_demo), isFalse);
      // Ook zonder Pro zie je wat er in vroege toegang is (voor de roadmap)
      expect(g.inEarlyAccess.map((e) => e.id), [_demo]);

      // Drie weken later: voor iedereen, en niet meer "vroeg"
      now = _now.add(const Duration(days: 22));
      expect(g.has(_demo), isTrue);
      expect(f.isEarly(_demo), isFalse);
      expect(f.inEarlyAccess, isEmpty);
    });

    test('een rij op de server gaat voor de standaard, ook om iets uit te zetten', () async {
      final s = newState();
      final pro = await _pro(s, active: false);
      final server = FakeFeaturesRemote()..flags = [FeatureFlag(id: _demo, earlyFrom: _now.add(const Duration(days: 1)))];
      final f = _features(pro, server, known: const {_demo: true});
      await pumpEventQueue();
      expect(f.has(_demo), isFalse);
    });

    test('Pro verandert: vroege functies gaan meteen open of dicht', () async {
      final s = newState();
      final pro = await _pro(s, active: false);
      final server = FakeFeaturesRemote()..flags = [_early()];
      final f = _features(pro, server);
      await pumpEventQueue();
      expect(f.has(_demo), isFalse);
      var notified = 0;
      f.addListener(() => notified++);
      pro.setDebugPro(true);
      expect(f.has(_demo), isTrue);
      expect(notified, greaterThan(0));
      pro.setDebugPro(null);
      expect(f.has(_demo), isFalse);
    });

    test('bewaard op het toestel: zonder internet blijft het laatste antwoord gelden', () async {
      final s = newState();
      final pro = await _pro(s, active: true);
      final server = FakeFeaturesRemote()..flags = [_early()];
      final f = _features(pro, server);
      await pumpEventQueue();
      expect(f.has(_demo), isTrue);

      // Opnieuw opgestart, zonder verbinding
      final offline = FakeFeaturesRemote()..offline = true;
      final g = _features(pro, offline);
      expect(g.has(_demo), isTrue);
      await pumpEventQueue();
      expect(offline.calls, greaterThan(0));
      expect(g.has(_demo), isTrue);
      expect(g.available, isTrue);
    });

    test('migratie ontbreekt: de standaarden, zonder fout', () async {
      final s = newState();
      final pro = await _pro(s, active: true);
      final server = FakeFeaturesRemote()..flags = [_early()];
      final f = _features(pro, server, known: const {_demo: true});
      await pumpEventQueue();
      expect(f.has(_demo), isTrue);
      server.flags = [_early().copyWithPublic(null).withEarly(null)];
      await f.refresh();
      expect(f.has(_demo), isFalse);
      server.missing = true;
      await f.refresh();
      expect(f.available, isFalse);
      expect(f.has(_demo), isTrue);
      expect(f.inEarlyAccess, isEmpty);
    });

    testWidgets('featureOn bouwt opnieuw als de vlag verandert, en valt terug op de standaard', (tester) async {
      final s = newState();
      final pro = await tester.runAsync(() => _pro(s, active: false));
      final server = FakeFeaturesRemote()..flags = [_early()];
      final f = _features(pro!, server);
      await tester.runAsync(pumpEventQueue);
      Widget gated() => Builder(builder: (c) => Text(featureOn(c, _demo) ? 'on' : 'off'));
      await _pump(tester, s, pro, Scaffold(body: gated()), features: f);
      expect(find.text('off'), findsOneWidget);
      pro.setDebugPro(true);
      await tester.pump();
      expect(find.text('on'), findsOneWidget);
      pro.setDebugPro(null);
      // Zonder Features in de boom: de standaard (uit)
      await _pump(tester, s, pro, Scaffold(body: gated()));
      expect(find.text('off'), findsOneWidget);
    });
  });

  group('Roadmap', () {
    Future<(FakeRoadmapRemote, Roadmap)> open(WidgetTester tester, {required bool pro, List<RoadmapItem> items = _items, Features? features}) async {
      final s = newState();
      final p = (await tester.runAsync(() => _pro(s, active: pro)))!;
      final server = FakeRoadmapRemote(items);
      final r = Roadmap(null, remote: () => server);
      addTearDown(r.dispose);
      await _pump(tester, s, p, RoadmapScreen(roadmap: r), features: features);
      return (server, r);
    }

    testWidgets('iedereen ziet de lijst met status en stemmen; zonder Pro een rustige regel naar Pro', (tester) async {
      await open(tester, pro: false);
      expect(find.text("What's next"), findsOneWidget);
      expect(find.text('Training and rest days'), findsOneWidget);
      expect(find.text('Planned'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-count-a')), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('Supporters vote on what comes next.'), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-about-pro')), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-vote-a')), findsNothing);
      expect(find.byKey(const ValueKey('roadmap-votes-left')), findsNothing);
    });

    testWidgets('supporter stemt: meteen zichtbaar, en terugnemen', (tester) async {
      final (server, r) = await open(tester, pro: true);
      expect(find.text('3 votes left'), findsOneWidget); // de stem op wat klaar is, telt niet mee
      expect(find.byKey(const ValueKey('roadmap-vote-e')), findsNothing); // klaar: geen knop

      server.gate = Completer<void>();
      await tester.tap(find.byKey(const ValueKey('roadmap-vote-a')));
      await tester.pump();
      // Optimistisch: al geteld voor de server antwoordt
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2 votes left'), findsOneWidget);
      server.gate!.complete();
      server.gate = null;
      await tester.pumpAndSettle();
      expect(server.votes, [('a', true)]);
      expect(find.text('5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('roadmap-vote-a')));
      await tester.pumpAndSettle();
      expect(server.votes.last, ('a', false));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('3 votes left'), findsOneWidget);
      expect(r.items.firstWhere((i) => i.id == 'a').mine, isFalse);
    });

    testWidgets('grens van 3: vriendelijke melding en terug zoals het was', (tester) async {
      final (server, r) = await open(tester, pro: true);
      for (final id in ['a', 'b', 'c']) {
        await tester.tap(find.byKey(ValueKey('roadmap-vote-$id')));
        await tester.pumpAndSettle();
      }
      expect(find.text('0 votes left'), findsOneWidget);
      // Lokaal al op: de server wordt niet eens gevraagd
      await tester.tap(find.byKey(const ValueKey('roadmap-vote-d')));
      await tester.pumpAndSettle();
      expect(server.votes.length, 3);
      expect(find.textContaining('You have used all 3 votes'), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-count-d')).evaluate().single.widget, isA<Text>().having((t) => t.data, 'data', '0'));

      // De server zegt 'limit' (bv. gestemd op een ander toestel): terugdraaien
      await tester.tap(find.byKey(const ValueKey('roadmap-vote-a'))); // terugnemen
      await tester.pumpAndSettle();
      server.answer = 'limit';
      await tester.tap(find.byKey(const ValueKey('roadmap-vote-d')));
      await tester.pumpAndSettle();
      expect(r.items.firstWhere((i) => i.id == 'd').mine, isFalse);
      expect(r.items.firstWhere((i) => i.id == 'd').votes, 0);
      expect(find.textContaining('You have used all 3 votes'), findsOneWidget);
    });

    testWidgets('fout bij het stemmen: terug zoals het was, met een melding', (tester) async {
      final (server, r) = await open(tester, pro: true);
      server.fail = true;
      await tester.tap(find.byKey(const ValueKey('roadmap-vote-b')));
      await tester.pumpAndSettle();
      expect(r.items.firstWhere((i) => i.id == 'b').mine, isFalse);
      expect(r.items.firstWhere((i) => i.id == 'b').votes, 2);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3 votes left'), findsOneWidget);
      expect(find.textContaining('Check your connection'), findsOneWidget);
    });

    testWidgets('migratie ontbreekt: vriendelijk "nog niet beschikbaar", geen fout', (tester) async {
      final s = newState();
      final p = (await tester.runAsync(() => _pro(s, active: true)))!;
      final server = FakeRoadmapRemote(_items)..missing = true;
      final r = Roadmap(null, remote: () => server);
      addTearDown(r.dispose);
      await _pump(tester, s, p, RoadmapScreen(roadmap: r));
      expect(find.byKey(const ValueKey('roadmap-missing')), findsOneWidget);
      expect(find.text('The roadmap is not available yet. Check back soon.'), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-item-a')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wat in vroege toegang is, met de dag voor iedereen', (tester) async {
      final s = newState();
      final p = (await tester.runAsync(() => _pro(s, active: true)))!;
      final fs = FakeFeaturesRemote()..flags = [_early()];
      final f = Features(p.account, pro: p, remote: () => fs, known: const {_demo: false}, clock: () => _now);
      addTearDown(f.dispose);
      await tester.runAsync(pumpEventQueue);
      final r = Roadmap(null, remote: () => FakeRoadmapRemote(_items));
      addTearDown(r.dispose);
      await _pump(tester, s, p, RoadmapScreen(roadmap: r), features: f);
      expect(find.byKey(const ValueKey('roadmap-early')), findsOneWidget);
      expect(find.text('For everyone on 23 November'), findsOneWidget);
      expect(find.byKey(const ValueKey('early-access-chip')), findsOneWidget);
    });

    testWidgets('ingangen: tegel in de instellingen en een link op het Pro-scherm', (tester) async {
      final s = newState();
      final p = (await tester.runAsync(() => _pro(s, active: false)))!;
      await _pump(tester, s, p, const ProScreen());
      expect(find.text('Early access to new features, now the weekly coach'), findsOneWidget);
      expect(find.text('Vote on what we build next'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-roadmap')), findsOneWidget);
      await _pump(
        tester,
        s,
        p,
        ChangeNotifierProvider<Account>.value(
          value: p.account,
          child: Provider.value(value: Reminders(s), child: const SettingsScreen()),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('roadmap-tile')));
      await tester.pumpAndSettle();
      // Zonder account: vriendelijk vragen om in te loggen
      expect(find.byType(RoadmapScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('roadmap-signed-out')), findsOneWidget);
    });
  });
}

extension on FeatureFlag {
  FeatureFlag copyWithPublic(DateTime? publicFrom) =>
      FeatureFlag(id: id, titleEn: titleEn, titleNl: titleNl, earlyFrom: earlyFrom, publicFrom: publicFrom);
  FeatureFlag withEarly(DateTime? earlyFrom) => FeatureFlag(id: id, titleEn: titleEn, titleNl: titleNl, earlyFrom: earlyFrom, publicFrom: publicFrom);
}
