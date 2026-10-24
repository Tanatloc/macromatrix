/// Pro: een abonnement bovenop de gratis app, en de dagteller voor loggen met een foto.
///
/// Bijna alles blijft gratis, voor altijd. Pro geeft onbeperkt loggen met een foto (met een rem van 50 per dag),
/// later AI-functies, en extra's voor wie de app steunt: extra kleuren, een Supporter-badge bij vrienden en een
/// uitgebreid jaaroverzicht. Spraak, sync, vrienden en uitdagingen blijven gratis.
///
/// Of je Pro hebt, komt altijd van de server (my_pro); de app bewaart het laatste antwoord zodat het ook zonder
/// internet klopt. Staat de migratie 20261026000000_pro.sql nog niet op de server, dan is [Pro.available] false: geen
/// Pro, geen teller, en loggen met een foto werkt zoals vroeger.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import 'account.dart';
import 'challenges.dart' show isMissingTable;
import 'purchase.dart';

/// Gratis foto's per dag, en de rem tegen misbruik met Pro. Moeten gelijk zijn aan photo_limit() op de server.
const freePhotosPerDay = 3;
const proPhotosPerDay = 50;

/// De functies voor Pro bestaan (nog) niet op de server.
class ProMissing implements Exception {
  const ProMissing();
  @override
  String toString() => 'ProMissing';
}

/// Pro zoals de server het kent.
@immutable
class ProStatus {
  const ProStatus({this.until, this.source, this.showBadge = true});

  /// Tot wanneer Pro loopt (null = nooit gehad).
  final DateTime? until;

  /// manual, gift, play, web, ...
  final String? source;

  /// Het Supporter-badge tonen aan vrienden.
  final bool showBadge;

  bool activeAt(DateTime now) => until != null && until!.isAfter(now);

  factory ProStatus.fromJson(Map j) => ProStatus(
    until: j['until'] is String ? DateTime.tryParse(j['until'] as String) : null,
    source: j['source'] as String?,
    showBadge: j['show_badge'] != false,
  );

  Map<String, Object?> toJson() => {'until': until?.toUtc().toIso8601String(), 'source': source, 'show_badge': showBadge};

  ProStatus copyWith({bool? showBadge}) => ProStatus(until: until, source: source, showBadge: showBadge ?? this.showBadge);
}

/// Dag in UTC (jjjj-mm-dd): de teller op de server telt per UTC-dag.
String utcDayKey(DateTime now) {
  final u = now.toUtc();
  return '${u.year.toString().padLeft(4, '0')}-${u.month.toString().padLeft(2, '0')}-${u.day.toString().padLeft(2, '0')}';
}

/// Hoeveel foto's je vandaag gebruikte en hoeveel er mogen.
@immutable
class PhotoQuota {
  const PhotoQuota({required this.used, required this.limit, this.pro = false, required this.day});
  final int used, limit;
  final bool pro;

  /// UTC-dag waarvoor deze stand geldt.
  final String day;

  int get left => math.max(0, limit - used);
  bool get allowed => used < limit;

  /// Uit het antwoord van photo_quota(_use) of /api/photo.
  static PhotoQuota? fromJson(Object? j, {DateTime? now}) {
    if (j is! Map || j['limit'] is! num) return null;
    return PhotoQuota(
      used: (j['used'] as num?)?.toInt() ?? 0,
      limit: (j['limit'] as num).toInt(),
      pro: j['pro'] == true,
      day: utcDayKey(now ?? DateTime.now()),
    );
  }

  /// Een stand van een vorige dag geldt niet meer: vandaag begin je opnieuw.
  PhotoQuota on(DateTime now) {
    final today = utcDayKey(now);
    return today == day ? this : PhotoQuota(used: 0, limit: limit, pro: pro, day: today);
  }
}

/// Wat de app van de server nodig heeft. Gooit [ProMissing] als de migratie er nog niet staat.
abstract class ProRemote {
  Future<ProStatus> mine();
  Future<PhotoQuota?> quota();
  Future<void> showBadge(bool show);
}

class SupabaseProRemote implements ProRemote {
  SupabaseProRemote(this.client);
  final SupabaseClient client;

  Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const ProMissing();
      rethrow;
    }
  }

  @override
  Future<ProStatus> mine() => _guard(() async {
    final j = await client.rpc('my_pro');
    return j is Map ? ProStatus.fromJson(j) : const ProStatus();
  });

  @override
  Future<PhotoQuota?> quota() => _guard(() async => PhotoQuota.fromJson(await client.rpc('photo_quota')));

  @override
  Future<void> showBadge(bool show) => _guard(() => client.rpc('pro_show_badge', params: {'p_show': show}));
}

class Pro extends ChangeNotifier {
  Pro(this.account, {ProRemote? Function()? remote, this.purchases = const NoPurchaseProvider(), DateTime Function()? clock})
    : _remoteFor = remote,
      _clock = clock ?? DateTime.now {
    _uid = account.user?.id;
    _loadCache();
    account.addListener(_changed);
  }

  final Account account;
  final ProRemote? Function()? _remoteFor;
  final DateTime Function() _clock;

  /// Google Play, een betaalpagina op het web, of (voorlopig) niets.
  final PurchaseProvider purchases;

  /// De server, alleen als je ingelogd bent (of de nagebootste in tests).
  ProRemote? get remote {
    if (_remoteFor != null) return _remoteFor();
    final c = account.client;
    return c == null || account.user == null ? null : SupabaseProRemote(c);
  }

  /// false zodra blijkt dat de server Pro niet kent (migratie nog niet uitgevoerd).
  bool available = true;

  /// Laatst bekende status (ook bewaard op dit toestel, per account).
  ProStatus status = const ProStatus();

  /// Stand van de fototeller vandaag (null = onbekend: niet ingelogd, offline of geen migratie).
  PhotoQuota? _quota;
  PhotoQuota? get quota {
    final q = _quota?.on(_clock());
    if (q == null) return null;
    // Pro nagebootst in een debug-build: de grens die je met (of zonder) Pro zou zien. Anders geldt wat de server zegt.
    final dbg = debugPro;
    if (dbg == null || q.pro == dbg) return q;
    return PhotoQuota(used: q.used, limit: dbg ? proPhotosPerDay : freePhotosPerDay, pro: dbg, day: q.day);
  }

  bool loading = false;
  String? _uid;

  /// Alleen in een debug-build: Pro op dit toestel aan of uit zetten om te testen (null = wat de server zegt).
  bool? get debugPro => kDebugMode ? (account.db.setting('_pro_debug')?['on'] as bool?) : null;

  void setDebugPro(bool? on) {
    if (!kDebugMode) return;
    account.db.setSetting('_pro_debug', {'on': on});
    notifyListeners();
  }

  /// Loopt Pro nu?
  bool get isPro => debugPro ?? status.activeAt(_clock());

  /// Supporter-badge naast je naam (Pro en niet zelf verborgen).
  bool get supporter => isPro && status.showBadge;

  void _loadCache() {
    final c = account.db.setting('_pro');
    status = c != null && c['uid'] == _uid ? ProStatus.fromJson(c) : const ProStatus();
  }

  void _saveCache() => account.db.setSetting('_pro', {...status.toJson(), 'uid': _uid});

  void _changed() {
    final uid = account.user?.id;
    if (uid == _uid) return;
    // Ander account: niets van het vorige onthouden
    _uid = uid;
    _quota = null;
    available = true;
    _loadCache();
    notifyListeners();
    if (uid != null) unawaited(refresh());
  }

  Future<T?> _run<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on ProMissing {
      available = false;
      return null;
    } catch (e) {
      // Geen verbinding of een storing: de bewaarde status blijft gelden
      debugPrint('pro: $e');
      return null;
    }
  }

  /// Status en fototeller ophalen bij de server.
  Future<void> refresh() async {
    final r = remote;
    if (r == null || loading) return;
    loading = true;
    try {
      final s = await _run(r.mine);
      if (s != null) {
        status = s;
        available = true;
        _saveCache();
      }
      if (available) {
        final q = await _run(r.quota);
        if (q != null) _quota = q;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Alleen de fototeller (bij het openen van Snel loggen).
  Future<void> refreshQuota() async {
    final r = remote;
    if (r == null || !available) return;
    final q = await _run(r.quota);
    if (q != null) _quota = q;
    notifyListeners();
  }

  /// Stand die /api/photo meestuurde (na een foto, of bij "op" met een 429).
  void noteQuota(PhotoQuota q) {
    _quota = q;
    available = true;
    // De server zegt iets anders over Pro dan wat we bewaarden: status opnieuw ophalen
    if (q.pro != status.activeAt(_clock())) unawaited(refresh());
    notifyListeners();
  }

  /// Het Supporter-badge bij vrienden tonen of verbergen.
  Future<bool> setShowBadge(bool show) async {
    final r = remote;
    if (r == null) return false;
    final ok = await _run(() async {
      await r.showBadge(show);
      return true;
    });
    if (ok == true) {
      status = status.copyWith(showBadge: show);
      _saveCache();
    }
    notifyListeners();
    return ok == true;
  }

  /// Abonneren via de [purchases]; bij succes de status opnieuw ophalen.
  Future<PurchaseOutcome> subscribe(ProPlan plan) async {
    if (!purchases.available) return PurchaseOutcome.unavailable;
    final out = await purchases.subscribe(plan);
    if (out == PurchaseOutcome.done) await refresh();
    return out;
  }

  /// Een aankoop herstellen: eerst bij de winkel (als die er is), daarna altijd de status bij de server ophalen,
  /// want daar staat Pro (ook als het met de hand of via het web toegekend is). Geeft true als Pro nu loopt.
  Future<bool> restore() async {
    if (purchases.available) await purchases.restore();
    await refresh();
    return isPro;
  }

  @override
  void dispose() {
    account.removeListener(_changed);
    super.dispose();
  }
}
