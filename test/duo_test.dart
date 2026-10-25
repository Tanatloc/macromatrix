// Duo in de app (lib/sync/duo.dart, Pro, het Supporter-scherm): plannen en prijzen, een vriend kiezen als koper,
// wisselen pas na 30 dagen, en als partner uit de Duo stappen. De server zelf: server/test/rpc_duo.test.mjs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/duo.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/purchase.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';

import 'pro_test.dart' show FakeProRemote, newState, pump;

/// De server met Duo erbij.
class _DuoServer extends FakeProRemote implements DuoRemote {
  DuoStatus duo = DuoStatus.none;
  final calls = <String>[];
  DuoResult next = DuoResult.ok;

  @override
  Future<DuoStatus> duoStatus() async => duo;

  @override
  Future<(DuoResult, DuoStatus)> duoSetPartner(String friendId) async {
    calls.add('set $friendId');
    if (next == DuoResult.ok) {
      duo = DuoStatus(role: DuoRole.owner, active: true, until: duo.until, partner: DuoPerson(friendId, 'Alex'), nextChange: DateTime.now().add(const Duration(days: 30)));
    }
    return (next, duo);
  }

  @override
  Future<DuoStatus> duoRemove() async {
    calls.add('remove');
    return duo = DuoStatus(role: DuoRole.owner, active: true, until: duo.until, nextChange: DateTime.now().add(const Duration(days: 30)));
  }

  @override
  Future<DuoStatus> duoLeave() async {
    calls.add('leave');
    return duo = DuoStatus.none;
  }
}

class _Friends extends Friends {
  _Friends(super.state, super.account, this.friends);
  final List<Friend> friends;
  @override
  List<Friend> get list => friends;
}

/// Ingelogd (de echte Account zou een server nodig hebben).
class _Signed extends Account {
  _Signed(super.db) : super(onRemoteChanges: () {});
  @override
  bool get signedIn => true;
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  test('plannen: Supporter en Duo met de prijzen van 25-10, en het jaar met korting', () {
    expect([for (final p in ProPlan.values) (p.productId, p.price, p.duo)], [
      ('pro_monthly', '€3.99', false),
      ('pro_yearly', '€29.99', false),
      ('duo_monthly', '€4.99', true),
      ('duo_yearly', '€39.99', true),
    ]);
    expect(ProPlan.duoMonthly.yearlyOfKind, ProPlan.duoYearly);
    expect(ProPlan.yearly.monthlyOfKind, ProPlan.monthly);
    expect(ProPlan.duoYearly.labelFor('€39.99'), '€39.99 / year');
  });

  test('de status van de server lezen', () {
    final s = DuoStatus.fromJson({
      'role': 'owner',
      'active': true,
      'until': '2027-11-01T12:00:00.000Z',
      'partner': {'id': 'b', 'name': 'Bert', 'code': 'ABCD1234'},
      'next_change': '2026-12-01T12:00:00.000Z',
    });
    expect((s.role, s.active, s.partner?.name, s.nextChange?.month), (DuoRole.owner, true, 'Bert', 12));
    expect(DuoStatus.fromJson(null).role, DuoRole.none);
    expect(DuoResult.parse('too_soon'), DuoResult.tooSoon);
    expect(DuoResult.parse('iets'), DuoResult.failed);
  });

  testWidgets('koper zonder partner: een vriend kiezen (met bevestiging), daarna staat die erin', (tester) async {
    final s = newState();
    final server = _DuoServer()..duo = DuoStatus(role: DuoRole.owner, active: true, until: DateTime.utc(2027, 11, 1));
    server.status = ProStatus(until: DateTime.utc(2027, 11, 1), source: 'play');
    final account = _Signed(s.user);
    final pro = Pro(account, remote: () => server);
    final friends = _Friends(s, account, const [
      Friend(id: 'a', name: 'Alex', state: FriendState.friend),
      Friend(id: 'x', name: 'Xena', state: FriendState.outgoing),
    ]);
    await pump(tester, s, pro, const ProScreen(), friends: friends);
    expect(find.text('Your Duo'), findsOneWidget);
    expect(find.byKey(const ValueKey('duo-choose-a')), findsOneWidget);
    // Een openstaand verzoek is nog geen vriend
    expect(find.byKey(const ValueKey('duo-choose-x')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('duo-choose-a')));
    await tester.pumpAndSettle();
    expect(find.text('Give Alex Supporter?'), findsOneWidget);
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(server.calls, ['set a']);
    expect(find.text('Alex is a supporter through your Duo.'), findsOneWidget);
    expect(find.textContaining('You can switch to another friend from'), findsOneWidget);
     friends.dispose();
  });

  testWidgets('wisselen te snel: de server zegt het, de app ook', (tester) async {
    final s = newState();
    final server = _DuoServer()
      ..duo = DuoStatus(role: DuoRole.owner, active: true, until: DateTime.utc(2027, 11, 1))
      ..next = DuoResult.tooSoon;
    final account = _Signed(s.user);
    final pro = Pro(account, remote: () => server);
    final friends = _Friends(s, account, const [Friend(id: 'a', name: 'Alex', state: FriendState.friend)]);
    await pump(tester, s, pro, const ProScreen(), friends: friends);
    await tester.tap(find.byKey(const ValueKey('duo-choose-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('You can only switch once every 30 days.'), findsOneWidget);
    friends.dispose();
  });

  testWidgets('partner: ziet van wie de Duo is en kan eruit stappen', (tester) async {
    final s = newState();
    final server = _DuoServer()..duo = DuoStatus(role: DuoRole.partner, active: true, until: DateTime.utc(2027, 11, 1), owner: const DuoPerson('o', 'Olga'));
    server.status = ProStatus(until: DateTime.utc(2027, 11, 1), source: 'duo');
    final pro = Pro(_Signed(s.user), remote: () => server);
    await pump(tester, s, pro, const ProScreen());
    expect(find.textContaining("You're a supporter through Olga's Duo"), findsOneWidget);
    expect(find.textContaining("Through a friend's Duo subscription"), findsOneWidget);
    // Een partner koopt niet bovenop de Duo: geen abonneerknop
    expect(find.byKey(const ValueKey('pro-subscribe')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('duo-leave')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(server.calls, ['leave']);
    expect(find.byKey(const ValueKey('duo-panel')), findsNothing);
  });

  testWidgets('prijzen zonder winkel: kiezen tussen alleen ik en Duo toont de juiste prijzen', (tester) async {
    final s = newState();
    final pro = Pro(_Signed(s.user), remote: () => _DuoServer());
    await pump(tester, s, pro, const ProScreen());
    expect(find.text('€3.99'), findsOneWidget);
    await tester.tap(find.text('Duo · you + 1 friend'));
    await tester.pumpAndSettle();
    expect(find.text('€4.99'), findsOneWidget);
    expect(find.text('€39.99'), findsOneWidget);
    expect(find.textContaining('You choose one friend'), findsOneWidget);
  });
}
