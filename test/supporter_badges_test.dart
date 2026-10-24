import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/badges.dart';
import 'package:macromatrix/nutrition/supporter.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/supporter_tracker.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/widgets/badges_view.dart';
import 'package:macromatrix/ui/widgets/pro_widgets.dart';

import 'pro_test.dart' show FakeProRemote, newState, pump;

final _t0 = DateTime.utc(2026, 11, 1, 12);

ProStatus _active(DateTime now) => ProStatus(until: now.add(const Duration(days: 30)), source: 'manual');

void _addCustom(AppState s, int n) {
  for (var i = 0; i < n; i++) {
    s.user.saveFood(Food(ref: 'custom:t$i', name: 'Test $i', source: FoodSource.custom, per100g: const {'energy': 50}));
  }
}

/// Friends met een Pro die (niet) loopt.
/// In een widgettest ruimt [_end] Friends op (met zijn timer).
(Friends, Pro) _friends(AppState s, {required bool active}) {
  final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
  final server = FakeProRemote();
  final pro = Pro(account, remote: () => server);
  if (active) pro.status = _active(DateTime.now());
  final f = Friends(s, account, pro: pro);
  return (f, pro);
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  test('drempels van de supporterbadges', () {
    int tier(String id, int v) => categoryById[id]!.tierFor(v);
    expect(
      [
        for (final v in [9, 10, 49, 50, 100, 250, 500]) tier('labels', v),
      ],
      [0, 1, 1, 2, 3, 4, 5],
    );
    expect(
      [
        for (final v in [4, 5, 10, 25, 50]) tier('chef', v),
      ],
      [0, 1, 2, 3, 4],
    );
    expect(
      [
        for (final v in [2, 3, 6, 12, 24, 36]) tier('loyal', v),
      ],
      [0, 1, 2, 3, 4, 5],
    );
    expect(
      [
        for (final v in [0, 1, 10]) tier('offshare', v),
      ],
      [0, 1, 2],
    );
    for (final id in supporterBadgeIds) {
      expect(categoryById[id]!.pro, isTrue);
      expect(categoryById[id]!.thresholds.length, 5);
    }
    expect(categoryById['scanner']!.pro, isFalse);
    // Een oudere app kent de nieuwe sleutels niet en laat ze gewoon weg; deze versie leest ze wel
    expect(decodeShowcase('labels:2,streak:1'), [('labels', 2), ('streak', 1)]);
  });

  test('teller voor delen met Open Food Facts wordt defensief gelezen', () {
    expect(readCounter(null), 0);
    expect(readCounter('x'), 0);
    expect(readCounter(7), 7);
    expect(readCounter({'count': 3}), 3);
    expect(readCounter({'value': 4.0}), 4);
    expect(readCounter({'other': 5}), 5);
    expect(readCounter({'list': []}), 0);
  });

  test('alleen met Pro tellen de supporterbadges', () {
    const none = SupporterRecord();
    final off = supporterValues(active: false, record: none, now: _t0, customFoods: 300, offShared: 30, recipes: 60);
    expect(off.values.every((v) => v == 0), isTrue, reason: 'nooit Pro: alles op 0');
    final on = supporterValues(active: true, record: none.observe(_t0, active: true), now: _t0, customFoods: 60, offShared: 2, recipes: 12);
    final t = badgeTiers(on);
    expect(t['labels'], 2);
    expect(t['offshare'], 1);
    expect(t['chef'], 2);
    expect(t['loyal'], 0);
  });

  test('maanden Pro tellen en blijven staan na stoppen; verdiend blijft verdiend', () {
    var r = const SupporterRecord().observe(_t0, active: true, live: {'labels': 60, 'chef': 6});
    expect(r.firstPro, _t0);
    final day100 = _t0.add(const Duration(days: 100));
    r = r.observe(day100, active: true, until: day100.add(const Duration(days: 5)), live: {'labels': 120, 'chef': 6});
    expect(r.monthsAt(day100, active: true), 3);
    expect(r.best['labels'], 120);
    expect(r.best['loyal'], 3);

    // Pro stopt op dag 105; de app ziet het pas op dag 200
    final day200 = _t0.add(const Duration(days: 200));
    r = r.observe(day200, active: false, until: _t0.add(const Duration(days: 105)));
    expect(r.since, isNull);
    expect(r.bankedDays, 105);
    expect(r.monthsAt(day200, active: false), 3, reason: 'de maanden staan stil');

    // Zonder Pro: verdiende niveaus blijven, maar meer eigen producten tellen niet
    final lapsed = supporterValues(active: false, record: r, now: day200, customFoods: 400, recipes: 80);
    final t = badgeTiers(lapsed);
    expect(lapsed['labels'], 120);
    expect(t['labels'], 3, reason: 'goud blijft');
    expect(t['chef'], 1);
    expect(t['loyal'], 1);
    expect(availableTitles(t, supporter: r.hadPro, founder: isFounder(r.firstPro)).map((x) => x.id), containsAll(['supporter', 'founder']));

    // Weer Pro: het huidige aantal telt opnieuw en de maanden lopen verder vanaf de afgesloten dagen
    final back = r.observe(day200, active: true);
    expect(supporterValues(active: true, record: back, now: day200, customFoods: 400)['labels'], 400);
    expect(back.monthsAt(day200.add(const Duration(days: 60)), active: true), 5, reason: '105 + 60 dagen');
    expect(back.firstPro, _t0, reason: 'de eerste Pro-datum blijft');
  });

  test('een korte onderbreking breekt de reeks niet', () {
    var r = const SupporterRecord().observe(_t0, active: true);
    final d40 = _t0.add(const Duration(days: 40));
    r = r.observe(d40, active: true);
    // Even "geen Pro" (oude status op het toestel), twee dagen later weer wel
    r = r.observe(d40.add(const Duration(days: 1)), active: false, until: d40);
    r = r.observe(d40.add(const Duration(days: 2)), active: true);
    expect(r.daysAt(_t0.add(const Duration(days: 90)), active: true), 90);
  });

  test('Stichter: Pro geworden vóór 1 oktober 2027', () {
    expect(isFounder(null), isFalse);
    expect(isFounder(DateTime.utc(2026, 10, 24)), isTrue);
    expect(isFounder(DateTime.utc(2027, 9, 30, 23, 59)), isTrue);
    expect(isFounder(DateTime.utc(2027, 10, 1)), isFalse);
    expect(isFounder(DateTime.utc(2028, 1, 1)), isFalse);
    // De eerste Pro-datum: de vroegste van de lokale kopie en de gesynchroniseerde stand
    final m = SupporterRecord.merge(
      SupporterRecord(firstPro: DateTime.utc(2027, 12, 1), best: const {'labels': 3}),
      SupporterRecord(firstPro: DateTime.utc(2027, 2, 1), best: const {'labels': 1, 'chef': 6}),
    );
    expect(m.firstPro, DateTime.utc(2027, 2, 1));
    expect(m.best, {'labels': 3, 'chef': 6});
    expect(SupporterRecord.fromJson(m.toJson()).toJson(), m.toJson());
  });

  test('welke supportertitels je kunt kiezen', () {
    ids(Map<String, int> t, {bool supporter = false, bool founder = false}) =>
        availableTitles(t, supporter: supporter, founder: founder).map((x) => x.id).toSet();
    final none = ids(const {});
    expect(none.intersection({'supporter', 'patron', 'founder'}), isEmpty);
    expect(ids(const {}, founder: true), isNot(contains('founder')), reason: 'Stichter vraagt ook Pro');
    expect(ids(const {}, supporter: true), containsAll(['supporter', 'rookie']));
    expect(ids(const {}, supporter: true), isNot(contains('founder')));
    expect(ids(const {}, supporter: true, founder: true), contains('founder'));
    expect(ids(const {'loyal': 2}, supporter: true), isNot(contains('patron')));
    expect(ids(const {'loyal': 3}, supporter: true), contains('patron'), reason: '12 maanden Pro');
    for (final id in ['supporter', 'patron', 'founder']) {
      expect(titleById[id]!.pro, isTrue);
    }
    expect(titleById['champion']!.pro, isFalse);
  });

  test('tracker schrijft pas na de eerste sync, in de instelling en de lokale kopie', () {
    final s = newState();
    _addCustom(s, 12);
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    final pro = Pro(account, remote: () => FakeProRemote())..status = _active(DateTime.now());
    var synced = false;
    final tracker = SupporterTracker(s.user, account, pro, synced: () => synced);
    expect(tracker.update(), isFalse);
    expect(s.user.setting(supporterSetting), isNull, reason: 'eerst de bewaarde stand van de server afwachten');
    synced = true;
    expect(tracker.update(), isTrue);
    expect(tracker.update(), isFalse, reason: 'niets veranderd: niet opnieuw schrijven');
    final r = supporterRecordOf(s.user);
    expect(r.hadPro, isTrue);
    expect(r.best['labels'], 12);
    expect(s.user.setting(supporterLocalSetting), isNotNull);
    // Na een herinstallatie is de lokale kopie weg; de gesynchroniseerde stand bewaart de eerste Pro-datum
    s.user.deleteSetting(supporterLocalSetting);
    expect(supporterRecordOf(s.user).firstPro, r.firstPro);
  });

  test('Friends: supporterbadges en -titels volgen Pro', () {
    final s = newState();
    _addCustom(s, 55);
    final (f, pro) = _friends(s, active: false);
    expect(f.tiers['labels'], 0, reason: 'zonder Pro telt niets');
    expect(f.availableTitlesNow.map((t) => t.id), isNot(contains('supporter')));

    pro.status = _active(DateTime.now());
    pro.notifyListeners();
    expect(f.tiers['labels'], 2);
    expect(f.availableTitlesNow.map((t) => t.id), containsAll(['supporter', 'founder']));
    expect(supporterRecordOf(s.user).best['labels'], 55);

    // Pro stopt: het verdiende niveau en de titels blijven, maar extra producten tellen niet meer
    pro.status = ProStatus(until: DateTime.now().subtract(const Duration(minutes: 1)));
    pro.notifyListeners();
    _addCustom(s, 120);
    expect(f.tiers['labels'], 2);
    expect(f.availableTitlesNow.map((t) => t.id), containsAll(['supporter', 'founder']));
    f.dispose();
  });

  testWidgets('zonder Pro: supporterbadges op slot met een Pro-label, een tik opent Pro', (tester) async {
    final s = newState();
    final (f, pro) = _friends(s, active: false);
    await pump(
      tester,
      s,
      pro,
      const Scaffold(body: SingleChildScrollView(child: BadgesCard())),
      friends: f,
    );
    // Het totaal telt de supporterbadges niet mee
    expect(find.text('0 / ${(badgeCategories.length - supporterBadgeIds.length) * 5} tiers'), findsOneWidget);
    await tester.tap(find.text('All badges'));
    await tester.pumpAndSettle();
    for (final id in supporterBadgeIds) {
      expect(find.byKey(ValueKey('badge-locked-$id')), findsOneWidget);
    }
    expect(find.byType(ProTag), findsNWidgets(supporterBadgeIds.length));
    await tester.tap(find.byKey(const ValueKey('badge-locked-chef')));
    await tester.pumpAndSettle();
    expect(find.byType(ProScreen), findsOneWidget);
    await _end(tester, f);
  });

  testWidgets('met Pro: gewone badges; na stoppen blijven verdiende badges met een pauze-uitleg', (tester) async {
    final s = newState();
    _addCustom(s, 10);
    final (f, pro) = _friends(s, active: true);
    await pump(
      tester,
      s,
      pro,
      const Scaffold(body: SingleChildScrollView(child: BadgesCard())),
      friends: f,
    );
    await tester.tap(find.text('All badges'));
    await tester.pumpAndSettle();
    expect(find.byType(ProTag), findsNothing);
    expect(find.byKey(const ValueKey('badge-labels')), findsOneWidget);
    expect(find.text('Label hunter'), findsOneWidget);

    pro.status = ProStatus(until: DateTime.now().subtract(const Duration(days: 1)));
    pro.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('badge-labels')), findsOneWidget, reason: 'verdiend: niet op slot');
    expect(find.byKey(const ValueKey('badge-locked-chef')), findsOneWidget, reason: 'nooit verdiend: op slot');
    await tester.tap(find.byKey(const ValueKey('badge-labels')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('badge-paused')), findsOneWidget);
    expect(find.text('Bronze'), findsWidgets);
    await _end(tester, f);
  });

  Future<Friends> openTitles(WidgetTester tester, bool active) async {
    final s = newState();
    final (f, pro) = _friends(s, active: active);
    await pump(
      tester,
      s,
      pro,
      Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(onPressed: () => pickTitle(ctx), child: const Text('pick')),
        ),
      ),
      friends: f,
    );
    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    return f;
  }

  testWidgets('titelkeuze zonder Pro: geen supportertitels, ook niet op slot', (tester) async {
    final f = await openTitles(tester, false);
    expect(find.text('Supporter'), findsNothing);
    expect(find.text('Founder'), findsNothing);
    expect(find.text('Patron'), findsNothing);
    expect(find.text('Rookie'), findsOneWidget);
    await _end(tester, f);
  });

  testWidgets('titelkeuze met Pro: Supporter en Stichter, Mecenas pas na 12 maanden', (tester) async {
    final f = await openTitles(tester, true);
    expect(find.text('Supporter'), findsOneWidget);
    expect(find.text('Founder'), findsOneWidget);
    expect(find.text('Patron'), findsNothing);
    await tester.tap(find.text('Founder'));
    await tester.pumpAndSettle();
    expect(f.state.title, 'founder');
    await _end(tester, f);
  });
}

/// Boom weg en Friends opruimen (de achtergrondtimer), zodat er geen timer meer loopt.
Future<void> _end(WidgetTester tester, Friends f) async {
  await tester.pumpWidget(const SizedBox());
  f.dispose();
}
