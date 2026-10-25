import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/cloudflare_auth.dart' show AccountUser;
import 'package:macromatrix/sync/play_purchase.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/purchase.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';

import 'pro_test.dart' show FakeProRemote, newState, pump;

/// Nagebootste Google Play-winkel: producten, het betaalvenster en eerdere aankopen.
class FakePlayStore implements PlayStore {
  bool storeAvailable = true;
  List<StoreProduct> catalog = const [
    StoreProduct(id: 'pro_monthly', price: '£2.49'),
    StoreProduct(id: 'pro_yearly', price: '£16.99'),
  ];

  /// Wat de winkel meldt na het betaalvenster (null = niets: het venster blijft open).
  List<StorePurchase>? Function(StoreProduct product)? onBuy;

  /// Wat een herstel meldt.
  List<StorePurchase> owned = [];

  final bought = <String>[];
  final accountIds = <String?>[];
  final completed = <String>[];
  int restores = 0;
  final log = <String>[];

  final _ctrl = StreamController<List<StorePurchase>>.broadcast();
  void emit(List<StorePurchase> list) => _ctrl.add(list);

  @override
  Future<bool> isAvailable() async => storeAvailable;

  @override
  Future<List<StoreProduct>> products(Set<String> ids) async => catalog.where((p) => ids.contains(p.id)).toList();

  @override
  Stream<List<StorePurchase>> get purchases => _ctrl.stream;

  @override
  Future<bool> buy(StoreProduct product, {String? accountId}) async {
    bought.add(product.id);
    accountIds.add(accountId);
    final out = onBuy?.call(product);
    if (out != null) scheduleMicrotask(() => emit(out));
    return true;
  }

  @override
  Future<void> complete(StorePurchase purchase) async {
    log.add('complete ${purchase.token}');
    completed.add(purchase.token);
  }

  @override
  Future<void> restore() async {
    restores++;
    emit([...owned]);
  }
}

/// Nagebootste /api/play-verify.
class FakeVerifier implements PlayVerifier {
  PlayVerdict Function(String token) answer = (_) => const PlayVerdict.ok();
  final tokens = <String>[];
  final List<String> log;
  FakeVerifier(this.log);

  @override
  Future<PlayVerdict> verify({required String token, required String productId, String? packageName}) async {
    tokens.add(token);
    log.add('verify $token');
    return answer(token);
  }
}

StorePurchase bought(String token, {String product = 'pro_yearly', StorePurchaseStatus status = StorePurchaseStatus.purchased}) =>
    StorePurchase(productId: product, token: token, status: status, packageName: 'eu.macromatrix.app', needsCompletion: true);

/// Ingelogd (of niet) zonder echte server.
class _Signed extends Account {
  _Signed(super.db, {this.id = 'user-1'}) : super(onRemoteChanges: () {});
  String? id;
  @override
  SupabaseClient? get client => null;
  @override
  bool get signedIn => id != null;
  @override
  AccountUser? get user => id == null ? null : AccountUser(id!, null);
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  late FakePlayStore store;
  late FakeVerifier verifier;
  late bool signedIn;
  late int refreshes;

  Future<PlayPurchaseProvider> provider() async {
    final p = PlayPurchaseProvider(
      store: store,
      verifier: verifier,
      signedIn: () => signedIn,
      userId: () => signedIn ? 'user-1' : null,
      restoreTimeout: const Duration(seconds: 2),
    )..attach(() async => refreshes++);
    await p.init();
    return p;
  }

  setUp(() {
    store = FakePlayStore();
    verifier = FakeVerifier(store.log);
    signedIn = true;
    refreshes = 0;
  });

  group('PlayPurchaseProvider', () {
    test('beschikbaar alleen met winkel en beide producten; de prijs van de winkel', () async {
      final p = await provider();
      expect(p.available, isTrue);
      expect(p.priceOf(ProPlan.monthly), '£2.49');
      expect(p.priceOf(ProPlan.yearly), '£16.99');

      store = FakePlayStore()..storeAvailable = false;
      final off = await provider();
      expect(off.available, isFalse);
      expect(await off.subscribe(ProPlan.yearly), PurchaseOutcome.unavailable);
      expect(off.priceOf(ProPlan.yearly), isNull);

      store = FakePlayStore()..catalog = const [StoreProduct(id: 'pro_monthly', price: '€2,99')];
      expect((await provider()).available, isFalse);
    });

    test('productId en ProPlan op één plek', () {
      expect(ProPlan.monthly.productId, 'pro_monthly');
      expect(ProPlan.yearly.productId, 'pro_yearly');
      expect(ProPlan.fromProductId('pro_yearly'), ProPlan.yearly);
      expect(ProPlan.fromProductId('iets_anders'), isNull);
    });

    test('kopen → server nakijken → pas dan bevestigen → status ophalen', () async {
      final p = await provider();
      store.onBuy = (prod) => [bought('tok-1', product: prod.id)];
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.done);
      expect(store.bought, ['pro_yearly']);
      // Het account gaat versleuteld mee, zodat de server kan nakijken bij wie de aankoop hoort
      expect(store.accountIds.single, accountHash('user-1'));
      expect(accountHash('user-1'), hasLength(64));
      expect(store.log, ['verify tok-1', 'complete tok-1']);
      expect(refreshes, 1);
    });

    test('server weigert: niet bevestigen bij de winkel', () async {
      final p = await provider();
      store.onBuy = (prod) => [bought('tok-2')];
      verifier.answer = (_) => const PlayVerdict.refused('other_account');
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.otherAccount);
      verifier.answer = (_) => const PlayVerdict.refused('failed');
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.failed);
      verifier.answer = (_) => const PlayVerdict.refused('network');
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.failed);
      expect(store.completed, isEmpty);
      expect(refreshes, 0);
    });

    test('server nog niet ingesteld: notConfigured, niet bevestigd', () async {
      final p = await provider();
      store.onBuy = (prod) => [bought('tok-3')];
      verifier.answer = (_) => const PlayVerdict.refused('not_configured');
      expect(await p.subscribe(ProPlan.monthly), PurchaseOutcome.notConfigured);
      expect(store.completed, isEmpty);
    });

    test('betaling in behandeling: pending, en later toch betaald', () async {
      final p = await provider();
      var changes = 0;
      p.addListener(() => changes++);
      store.onBuy = (prod) => [bought('tok-4', status: StorePurchaseStatus.pending)];
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.pending);
      expect(p.pending, isTrue);
      expect(changes, greaterThan(0));
      expect(verifier.tokens, isEmpty);

      // Google bevestigt de betaling later: de winkel meldt ze, zonder dat iemand op een knop drukt
      store.emit([bought('tok-4')]);
      await pumpEventQueue();
      expect(store.log, ['verify tok-4', 'complete tok-4']);
      expect(p.pending, isFalse);
      expect(refreshes, 1);
    });

    test('server zegt pending (betaling nog niet binnen): pending, niet bevestigd', () async {
      final p = await provider();
      store.onBuy = (prod) => [bought('tok-5')];
      verifier.answer = (_) => const PlayVerdict.refused('pending');
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.pending);
      expect(p.pending, isTrue);
      expect(store.completed, isEmpty);
    });

    test('zelf afgebroken of een fout van de winkel', () async {
      final p = await provider();
      store.onBuy = (prod) => [bought('', status: StorePurchaseStatus.canceled)];
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.cancelled);
      store.onBuy = (prod) => [StorePurchase(productId: prod.id, token: '', status: StorePurchaseStatus.error, error: 'purchase_error BillingResponse.error')];
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.failed);
      expect(verifier.tokens, isEmpty);
    });

    test('al in bezit (gekocht op een ander toestel): opnieuw koppelen', () async {
      final p = await provider();
      store.owned = [bought('tok-owned', status: StorePurchaseStatus.restored)];
      store.onBuy = (prod) => [
        StorePurchase(productId: prod.id, token: '', status: StorePurchaseStatus.error, error: 'purchase_error BillingResponse.itemAlreadyOwned'),
      ];
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.done);
      expect(store.restores, 1);
      expect(store.completed, ['tok-owned']);
    });

    test('herstellen: eerdere aankopen nakijken en bevestigen; niets gevonden', () async {
      final p = await provider();
      store.owned = [bought('tok-6', status: StorePurchaseStatus.restored)];
      expect(await p.restore(), PurchaseOutcome.done);
      expect(store.log, ['verify tok-6', 'complete tok-6']);
      expect(refreshes, 1);

      store.owned = [];
      expect(await p.restore(), PurchaseOutcome.notFound);

      store.owned = [bought('tok-7', status: StorePurchaseStatus.restored)];
      verifier.answer = (_) => const PlayVerdict.refused('other_account');
      expect(await p.restore(), PurchaseOutcome.otherAccount);
      expect(store.completed, ['tok-6']);
    });

    test('niet ingelogd: "Log eerst in", zonder betaalvenster of server', () async {
      signedIn = false;
      final p = await provider();
      expect(await p.subscribe(ProPlan.yearly), PurchaseOutcome.signedOut);
      expect(await p.restore(), PurchaseOutcome.signedOut);
      expect(store.bought, isEmpty);
      // Een aankoop die binnenkomt zonder account wordt niet nagekeken en niet bevestigd
      store.emit([bought('tok-8')]);
      await pumpEventQueue();
      expect(verifier.tokens, isEmpty);
      expect(store.completed, isEmpty);
    });

    test('dezelfde aankoop twee keer tegelijk: één keer naar de server', () async {
      final p = await provider();
      final gate = Completer<void>();
      final slow = verifier.answer;
      var calls = 0;
      final v = _GatedVerifier(gate.future, () => calls++, slow);
      final q = PlayPurchaseProvider(store: store, verifier: v, signedIn: () => true, userId: () => 'user-1');
      await q.init();
      store.emit([bought('tok-9')]);
      store.emit([bought('tok-9')]);
      await pumpEventQueue();
      gate.complete();
      await pumpEventQueue();
      expect(calls, 1);
      expect(p.available, isTrue);
    });
  });

  group('HttpPlayVerifier', () {
    test('ok, een reden, not_configured (503), geen JSON, zonder account', () async {
      late http.Request sent;
      Future<PlayVerdict> run(http.Response res) => HttpPlayVerifier(
        () => 'jwt-1',
        client: MockClient((r) async {
          sent = r;
          return res;
        }),
      ).verify(token: 'tok', productId: 'pro_yearly', packageName: 'eu.macromatrix.app');

      final ok = await run(http.Response('{"ok":true,"until":"2027-11-05T12:00:00.000Z"}', 200));
      expect(ok.ok, isTrue);
      expect(ok.until, DateTime.utc(2027, 11, 5, 12));
      expect(sent.url.path, '/api/play-verify');
      expect(sent.headers['Authorization'], 'Bearer jwt-1');
      expect(jsonDecode(sent.body), {'purchaseToken': 'tok', 'productId': 'pro_yearly', 'packageName': 'eu.macromatrix.app'});

      expect((await run(http.Response('{"ok":false,"reason":"other_account"}', 409))).reason, 'other_account');
      expect((await run(http.Response('{"ok":false,"reason":"not_configured"}', 503))).reason, 'not_configured');
      expect((await run(http.Response('<html>', 502))).reason, 'failed');
      expect((await run(http.Response('{"error":"login"}', 401))).reason, 'login');
      expect((await HttpPlayVerifier(() => null).verify(token: 't', productId: 'pro_yearly')).reason, 'login');
    });
  });

  group('Pro met Google Play', () {
    test('bij de start stil nakijken als Pro binnen 3 dagen afloopt; niet als het nog lang loopt', () async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime.now().add(const Duration(days: 2)), source: 'play');
      final p = await provider();
      final pro = Pro(_Signed(s.user), remote: () => server, purchases: p);
      await pro.refresh();
      await pumpEventQueue();
      expect(store.restores, 1);
      // Eén keer per sessie
      await pro.refresh();
      await pumpEventQueue();
      expect(store.restores, 1);

      store = FakePlayStore();
      verifier = FakeVerifier(store.log);
      server.status = ProStatus(until: DateTime.now().add(const Duration(days: 40)), source: 'play');
      final pro2 = Pro(_Signed(s.user), remote: () => server, purchases: await provider());
      await pro2.refresh();
      await pumpEventQueue();
      expect(store.restores, 0);
    });

    test('afgelopen Pro: een verlenging bij de winkel zet Pro vanzelf weer aan', () async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime.now().subtract(const Duration(days: 1)), source: 'play');
      store.owned = [bought('tok-renew', status: StorePurchaseStatus.restored)];
      verifier.answer = (_) {
        server.status = ProStatus(until: DateTime.now().add(const Duration(days: 30)), source: 'play');
        return const PlayVerdict.ok();
      };
      final p = PlayPurchaseProvider(store: store, verifier: verifier, signedIn: () => true, userId: () => 'user-1');
      final pro = Pro(_Signed(s.user), remote: () => server, purchases: p);
      await p.init();
      await pro.refresh();
      for (var i = 0; i < 5; i++) {
        await pumpEventQueue();
      }
      expect(verifier.tokens, ['tok-renew']);
      expect(pro.isPro, isTrue);
    });

    test('niet ingelogd: niet nakijken bij de winkel', () async {
      final s = newState();
      final p = await provider();
      final pro = Pro(_Signed(s.user, id: null), remote: () => null, purchases: p);
      await pro.refresh();
      await pumpEventQueue();
      expect(store.restores, 0);
    });
  });

  group('Pro-scherm met Google Play', () {
    testWidgets('de prijs van de winkel, kopen en "betaling in behandeling"', (tester) async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime(2099), source: 'manual');
      server.status = const ProStatus();
      final p = await provider();
      final pro = Pro(_Signed(s.user), remote: () => server, purchases: p);
      await pump(tester, s, pro, const ProScreen());
      expect(find.text('£2.49'), findsOneWidget);
      expect(find.text('£16.99'), findsOneWidget);
      expect(find.text('Subscribe · £16.99 / year'), findsOneWidget);
      // Google-regel voor abonnementen: prijs, plan en automatische verlenging bij de knop (GP-2)
      expect(find.byKey(const ValueKey('pro-coming-soon')), findsNothing);
      expect(find.textContaining('MacroMatrix Supporter, yearly: £16.99 per year. Renews automatically every year'), findsOneWidget);
      expect(find.textContaining('Cancel anytime in Google Play'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
      await tester.pump();
      expect(find.text('Subscribe · £2.49 / month'), findsOneWidget);
      expect(find.textContaining('Renews automatically every month'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-plan-yearly')));
      await tester.pump();

      store.onBuy = (prod) => [bought('tok-w1', status: StorePurchaseStatus.pending)];
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pro-pending')), findsOneWidget);
      expect(find.textContaining('Payment pending'), findsNWidgets(2));

      // Google bevestigt; de server zet Pro aan
      verifier.answer = (_) {
        server.status = ProStatus(until: DateTime(2027, 11, 5), source: 'play');
        return const PlayVerdict.ok();
      };
      await tester.runAsync(() async {
        store.emit([bought('tok-w1')]);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pumpAndSettle();
      expect(find.text('You are a supporter'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-prices')), findsNothing);
    });

    testWidgets('kopen lukt: bedankt; de server nog niet ingesteld: vriendelijke uitleg', (tester) async {
      final s = newState();
      final server = FakeProRemote();
      final p = await provider();
      final pro = Pro(_Signed(s.user), remote: () => server, purchases: p);
      await pump(tester, s, pro, const ProScreen());

      store.onBuy = (prod) => [bought('tok-w2')];
      verifier.answer = (_) => const PlayVerdict.refused('not_configured');
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.textContaining("you don't need to pay again"), findsOneWidget);

      verifier.answer = (_) {
        server.status = ProStatus(until: DateTime(2027, 11, 5), source: 'play');
        return const PlayVerdict.ok();
      };
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.text("Thank you! You're a supporter now."), findsOneWidget);
      expect(store.completed, ['tok-w2']);
    });

    testWidgets('niet ingelogd: "Log in first"', (tester) async {
      final s = newState();
      signedIn = false;
      final p = await provider();
      final pro = Pro(_Signed(s.user, id: null), remote: () => FakeProRemote(), purchases: p);
      await pump(tester, s, pro, const ProScreen());
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Log in first'), findsOneWidget);
      expect(store.bought, isEmpty);
    });

    testWidgets('herstellen: hoort bij een ander account', (tester) async {
      final s = newState();
      final p = await provider();
      final pro = Pro(_Signed(s.user), remote: () => FakeProRemote(), purchases: p);
      await pump(tester, s, pro, const ProScreen());
      store.owned = [bought('tok-w3', status: StorePurchaseStatus.restored)];
      verifier.answer = (_) => const PlayVerdict.refused('other_account');
      await tester.tap(find.byKey(const ValueKey('pro-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('already belongs to another MacroMatrix account'), findsOneWidget);
    });

    testWidgets('zonder winkel: de vaste prijs in euro en "Binnenkort"', (tester) async {
      final s = newState();
      store.storeAvailable = false;
      final p = await provider();
      final pro = Pro(_Signed(s.user), remote: () => FakeProRemote(), purchases: p);
      await pump(tester, s, pro, const ProScreen());
      expect(find.text('€29.99'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-subscribe')), findsNothing);
      expect(find.byKey(const ValueKey('pro-coming-soon')), findsOneWidget);
    });
  });
}

/// Een server die pas antwoordt als [gate] klaar is.
class _GatedVerifier implements PlayVerifier {
  _GatedVerifier(this.gate, this.onCall, this.answer);
  final Future<void> gate;
  final void Function() onCall;
  final PlayVerdict Function(String) answer;

  @override
  Future<PlayVerdict> verify({required String token, required String productId, String? packageName}) async {
    onCall();
    await gate;
    return answer(token);
  }
}
