/// Pro kopen met Google Play Billing (abonnementen pro_monthly en pro_yearly).
///
/// Zo loopt een aankoop:
/// 1. [PlayPurchaseProvider.subscribe] opent het betaalvenster van Google Play.
/// 2. De winkel meldt de aankoop op [PlayStore.purchases]. We sturen het purchaseToken naar /api/play-verify; de
///    server kijkt het na bij Google, koppelt het aan je account en zet Pro aan (pro_status).
/// 3. Pas als de server ok zegt, bevestigen we de aankoop bij de winkel ([PlayStore.complete]). Zegt de server nee,
///    dan bevestigen we niet: Google betaalt een onbevestigde aankoop na 3 dagen terug.
/// 4. Daarna haalt [Pro] de status opnieuw op. De app beslist dus nooit zelf of je Pro hebt.
///
/// De plugin zelf zit achter [PlayStore] (lib/sync/play_store_plugin.dart), zodat dit bestand zonder plugin te testen
/// is en de F-Droid-build zonder de niet-vrije Play-bibliotheek kan.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../platform/ai_request.dart' show apiEndpoint;
import 'account.dart';
import 'play_store_stub.dart' if (dart.library.io) 'play_store_plugin.dart';
import 'purchase.dart';

/// Een abonnement zoals de winkel het kent.
@immutable
class StoreProduct {
  const StoreProduct({required this.id, required this.price, this.raw});
  final String id;

  /// De prijs zoals de winkel ze toont, al opgemaakt in de munt van de gebruiker ("€ 2,99", "£2.49").
  final String price;

  /// Het object van de plugin (nodig om te kopen).
  final Object? raw;
}

enum StorePurchaseStatus { pending, purchased, restored, error, canceled }

/// Een aankoop zoals de winkel ze meldt.
@immutable
class StorePurchase {
  const StorePurchase({
    required this.productId,
    required this.token,
    required this.status,
    this.packageName,
    this.needsCompletion = false,
    this.error,
    this.raw,
  });
  final String productId;

  /// Het purchaseToken van Google Play (serverVerificationData).
  final String token;
  final StorePurchaseStatus status;
  final String? packageName;

  /// Moet nog bevestigd worden bij de winkel (completePurchase).
  final bool needsCompletion;

  /// Bij [StorePurchaseStatus.error]: de foutcode van de winkel.
  final String? error;
  final Object? raw;
}

/// Wat we van de winkel nodig hebben: klein genoeg om na te bootsen in tests.
abstract class PlayStore {
  Future<bool> isAvailable();
  Future<List<StoreProduct>> products(Set<String> ids);
  Stream<List<StorePurchase>> get purchases;

  /// Het betaalvenster openen. [accountId] gaat als obfuscatedAccountId mee, zodat de server kan nakijken dat de
  /// aankoop bij dit account hoort. Geeft false als het venster niet openging.
  Future<bool> buy(StoreProduct product, {String? accountId});

  /// De aankoop bevestigen (acknowledge).
  Future<void> complete(StorePurchase purchase);

  /// Eerdere aankopen opnieuw melden op [purchases] (als restored).
  Future<void> restore();
}

/// Het antwoord van /api/play-verify: ok, of een reden (not_configured, other_account, pending, expired, login,
/// network, failed, ...).
@immutable
class PlayVerdict {
  const PlayVerdict.ok([this.until]) : ok = true, reason = null;
  const PlayVerdict.refused(String this.reason) : ok = false, until = null;
  final bool ok;
  final String? reason;
  final DateTime? until;
}

abstract class PlayVerifier {
  Future<PlayVerdict> verify({required String token, required String productId, String? packageName});
}

/// Naar /api/play-verify, met het Supabase-token van de ingelogde gebruiker.
class HttpPlayVerifier implements PlayVerifier {
  HttpPlayVerifier(this.accessToken, {this.client});
  final String? Function() accessToken;

  /// Zonder een nieuwe verbinding per verzoek; in tests een nagebootste client.
  final http.Client? client;

  @override
  Future<PlayVerdict> verify({required String token, required String productId, String? packageName}) async {
    final auth = accessToken();
    if (auth == null) return const PlayVerdict.refused('login');
    final c = client ?? http.Client();
    try {
      final res = await c
          .post(
            apiEndpoint('/api/play-verify'),
            headers: {'Authorization': 'Bearer $auth', 'Content-Type': 'application/json'},
            body: jsonEncode({'purchaseToken': token, 'productId': productId, 'packageName': ?packageName}),
          )
          .timeout(const Duration(seconds: 30));
      final Object? j;
      try {
        j = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        return const PlayVerdict.refused('failed');
      }
      if (j is Map && j['ok'] == true) return PlayVerdict.ok(j['until'] is String ? DateTime.tryParse(j['until'] as String) : null);
      if (j is Map && j['reason'] is String) return PlayVerdict.refused(j['reason'] as String);
      return PlayVerdict.refused(res.statusCode == 401 ? 'login' : 'failed');
    } on TimeoutException {
      return const PlayVerdict.refused('network');
    } catch (_) {
      return const PlayVerdict.refused('network');
    } finally {
      if (client == null) c.close();
    }
  }
}

/// sha256 van de gebruikers-id als hex (64 tekens, het maximum van Google). Zelfde als accountHash in
/// functions/_lib/play.js. Zo krijgt Google geen account-id, en kan de server toch nakijken bij wie een aankoop hoort.
String accountHash(String userId) => crypto.sha256.convert(utf8.encode(userId)).toString();

class PlayPurchaseProvider extends PurchaseProvider with ChangeNotifier {
  PlayPurchaseProvider({
    required this.store,
    required this.verifier,
    required this.signedIn,
    required this.userId,
    this.restoreTimeout = const Duration(seconds: 30),
  });

  final PlayStore store;
  final PlayVerifier verifier;
  final bool Function() signedIn;
  final String? Function() userId;
  final Duration restoreTimeout;

  final Map<ProPlan, StoreProduct> _products = {};
  bool _ready = false;
  bool _pending = false;
  StreamSubscription<List<StorePurchase>>? _sub;
  Future<void> Function()? _refresh;

  /// Een lopende aankoop (wacht op de melding van de winkel) en een lopend herstel.
  Completer<PurchaseOutcome>? _buying;
  Completer<PurchaseOutcome>? _restoring;

  /// Aankopen die de server nu nakijkt, per token (dezelfde aankoop niet twee keer tegelijk).
  final Map<String, Future<PurchaseOutcome>> _verifying = {};

  /// Winkel en producten nakijken. Tot dit klaar is (en als de winkel of een product ontbreekt) is [available]
  /// false, en toont het Pro-scherm "Binnenkort", net als zonder Play.
  Future<void> init() async {
    _sub ??= store.purchases.listen(_onPurchases, onError: (Object e) => debugPrint('play: $e'));
    try {
      if (!await store.isAvailable()) return;
      final found = await store.products({for (final p in ProPlan.values) p.productId});
      for (final f in found) {
        final plan = ProPlan.fromProductId(f.id);
        if (plan != null) _products[plan] = f;
      }
      _ready = ProPlan.values.every(_products.containsKey);
    } catch (e) {
      debugPrint('play: $e');
    } finally {
      notifyListeners();
    }
  }

  @override
  bool get available => _ready;

  @override
  String? priceOf(ProPlan plan) => _products[plan]?.price;

  @override
  bool get pending => _pending;

  @override
  void attach(Future<void> Function() refresh) => _refresh = refresh;

  void _setPending(bool on) {
    if (_pending == on) return;
    _pending = on;
    notifyListeners();
  }

  @override
  Future<PurchaseOutcome> subscribe(ProPlan plan) async {
    final product = _products[plan];
    if (!_ready || product == null) return PurchaseOutcome.unavailable;
    final uid = userId();
    if (!signedIn() || uid == null) return PurchaseOutcome.signedOut;
    if (_buying != null) return _buying!.future;
    final c = _buying = Completer<PurchaseOutcome>();
    try {
      if (!await store.buy(product, accountId: accountHash(uid))) _finishBuy(PurchaseOutcome.failed);
    } catch (e) {
      debugPrint('play buy: $e');
      _finishBuy(PurchaseOutcome.failed);
    }
    return c.future;
  }

  void _finishBuy(PurchaseOutcome out) {
    final c = _buying;
    _buying = null;
    if (c != null && !c.isCompleted) c.complete(out);
  }

  @override
  Future<PurchaseOutcome> restore() async {
    if (!_ready) return PurchaseOutcome.unavailable;
    if (!signedIn()) return PurchaseOutcome.signedOut;
    if (_restoring != null) return _restoring!.future;
    final c = _restoring = Completer<PurchaseOutcome>();
    try {
      await store.restore();
    } catch (e) {
      debugPrint('play restore: $e');
      _restoring = null;
      return PurchaseOutcome.failed;
    }
    final out = await c.future.timeout(restoreTimeout, onTimeout: () => PurchaseOutcome.failed);
    if (identical(_restoring, c)) _restoring = null;
    return out;
  }

  @override
  Future<void> recheck() async {
    await restore();
  }

  Future<void> _onPurchases(List<StorePurchase> list) async {
    final ours = list.where((p) => ProPlan.fromProductId(p.productId) != null).toList();
    // Een herstel meldt alles in één keer als restored (of niets, als er geen aankoop is)
    final isRestore = ours.every((p) => p.status == StorePurchaseStatus.restored);
    final checks = <Future<PurchaseOutcome>>[];
    for (final p in ours) {
      switch (p.status) {
        case StorePurchaseStatus.pending:
          _setPending(true);
          _finishBuy(PurchaseOutcome.pending);
        case StorePurchaseStatus.canceled:
          _finishBuy(PurchaseOutcome.cancelled);
        case StorePurchaseStatus.error:
          // Al in bezit (bv. gekocht op een ander toestel): opnieuw koppelen in plaats van een fout
          if ((p.error ?? '').toLowerCase().contains('alreadyowned') && _buying != null) {
            final c = _buying!;
            _buying = null;
            unawaited(restore().then((out) => c.isCompleted ? null : c.complete(out)));
          } else {
            _finishBuy(PurchaseOutcome.failed);
          }
        case StorePurchaseStatus.purchased:
          final f = _check(p);
          checks.add(f);
          unawaited(f.then(_finishBuy));
        case StorePurchaseStatus.restored:
          checks.add(_check(p));
      }
    }
    final outs = await Future.wait(checks);
    if (isRestore) {
      final c = _restoring;
      if (c != null && !c.isCompleted) c.complete(_combine(outs));
    }
  }

  /// Wat een herstel oplevert: één goedgekeurde aankoop is genoeg.
  static PurchaseOutcome _combine(List<PurchaseOutcome> outs) {
    if (outs.isEmpty) return PurchaseOutcome.notFound;
    for (final o in const [
      PurchaseOutcome.done,
      PurchaseOutcome.otherAccount,
      PurchaseOutcome.notConfigured,
      PurchaseOutcome.pending,
      PurchaseOutcome.signedOut,
    ]) {
      if (outs.contains(o)) return o;
    }
    return outs.contains(PurchaseOutcome.failed) ? PurchaseOutcome.failed : PurchaseOutcome.notFound;
  }

  Future<PurchaseOutcome> _check(StorePurchase p) =>
      _verifying[p.token] ??= _verify(p).whenComplete(() {
        // Met een blok: remove geeft de Future zelf terug, en whenComplete zou daar dan op wachten
        _verifying.remove(p.token);
      });

  Future<PurchaseOutcome> _verify(StorePurchase p) async {
    // Zonder account niet bevestigen: de winkel meldt de aankoop opnieuw na het inloggen (herstellen of bij de start)
    if (!signedIn()) return PurchaseOutcome.signedOut;
    final v = await verifier.verify(token: p.token, productId: p.productId, packageName: p.packageName);
    if (!v.ok) {
      switch (v.reason) {
        case 'pending':
          _setPending(true);
          return PurchaseOutcome.pending;
        case 'other_account':
          return PurchaseOutcome.otherAccount;
        case 'not_configured':
          return PurchaseOutcome.notConfigured;
        case 'login':
          return PurchaseOutcome.signedOut;
        case 'expired':
          // Afgelopen: niets meer te bevestigen of aan te zetten
          return PurchaseOutcome.notFound;
        default:
          return PurchaseOutcome.failed;
      }
    }
    // Pas nu bevestigen bij de winkel: de server heeft de aankoop gezien en gekoppeld
    if (p.needsCompletion) {
      try {
        await store.complete(p);
      } catch (e) {
        // Niet erg: de server bevestigde ook al
        debugPrint('play complete: $e');
      }
    }
    _setPending(false);
    await _refresh?.call();
    return PurchaseOutcome.done;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Wat Pro gebruikt om te betalen: Google Play op Android (als de winkel er is), anders niets ("Binnenkort"). In de
/// F-Droid-build geeft [createPlayStore] null.
PurchaseProvider purchaseProviderFor(Account account) {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return const NoPurchaseProvider();
  final store = createPlayStore();
  if (store == null) return const NoPurchaseProvider();
  final p = PlayPurchaseProvider(
    store: store,
    verifier: HttpPlayVerifier(() => account.accessToken),
    signedIn: () => account.signedIn,
    userId: () => account.user?.id,
  );
  unawaited(p.init());
  return p;
}
