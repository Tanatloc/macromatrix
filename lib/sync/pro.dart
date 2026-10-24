/// Pro: een abonnement bovenop de gratis app, en de dagteller voor loggen met een foto.
///
/// Bijna alles blijft gratis, voor altijd. Pro geeft tot 50 foto's per dag,
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

import '../i18n.dart';
import 'account.dart';
import 'challenges.dart' show isMissingTable;
import 'purchase.dart';

/// Gratis foto's per dag, en de rem tegen misbruik met Pro. Moeten gelijk zijn aan photo_limit() op de server.
const freePhotosPerDay = 3;
const proPhotosPerDay = 50;

/// De andere AI-functies met een dagteller op de server (ai_quota_use, migratie 20261027000000_ai_quota.sql).
enum AiKind {
  /// Een etiket lezen als een barcode nergens gevonden werd: 1 per dag gratis, 30 met Pro.
  label(free: 1, pro: 30),

  /// Een recept importeren uit een link of foto: alleen met Pro, 20 per dag.
  recipe(free: 0, pro: 20);

  const AiKind({required this.free, required this.pro});

  /// Moeten gelijk zijn aan ai_limit() op de server.
  final int free, pro;

  int limitFor(bool isPro) => isPro ? pro : free;

  /// Alleen met Pro (gratis 0 per dag).
  bool get proOnly => free == 0;
}

/// De dagteller voor de AI-functies bestaat (nog) niet op de server.
class AiQuotaMissing implements Exception {
  const AiQuotaMissing();
  @override
  String toString() => 'AiQuotaMissing';
}

/// Voor de AI-tellers: los van [ProRemote], zodat een server (of een nabootsing) zonder die tellers gewoon werkt.
abstract class AiQuotaRemote {
  /// Gooit [AiQuotaMissing] als de migratie er nog niet staat.
  Future<PhotoQuota?> aiQuota(AiKind kind);
}

/// De functies voor Pro bestaan (nog) niet op de server.
class ProMissing implements Exception {
  const ProMissing();
  @override
  String toString() => 'ProMissing';
}

/// Supporterranden rond je avatar (migratie 20261030000000_supporter_frame.sql). De ring houdt altijd de kleur van
/// je level; een rand verandert alleen de stijl, de beweging en de versiering. De [id]'s moeten gelijk zijn aan de
/// check op pro_status.frame.
enum AvatarFrame {
  /// Een zachte gloed in de levelkleur die traag aanzwelt.
  glow('glow'),

  /// Een helder lichtje dat rond de ring draait.
  orbit('orbit'),

  /// Een paar fonkelende sterretjes op de ring.
  sparkle('sparkle'),

  /// Een lauwerkrans aan de onderkant (staat stil).
  laurel('laurel'),

  /// Golfjes die van de ring naar buiten lopen en vervagen.
  ripple('ripple'),

  /// Een streepjeskrans net buiten de ring die traag ronddraait.
  spin('spin'),

  /// Korte zonnestralen rondom die om beurten langer worden.
  sunburst('sunburst'),

  /// Een kroontje linksboven op de ring (staat stil).
  crown('crown'),

  /// Vleugels links en rechts, met een metaalglans (staat stil).
  wings('wings'),

  /// Twee gebogen klingen die van onderaan naar buiten en omhoog lopen (staat stil).
  blades('blades'),

  /// Een tweede, dunne ring eromheen met blaadjes opzij en een edelsteentje bovenaan (staat stil).
  royal('royal');

  const AvatarFrame(this.id);
  final String id;

  String get label => switch (this) {
    glow => tr('Glow', 'Gloed'),
    orbit => tr('Orbit', 'Omloop'),
    sparkle => tr('Sparkle', 'Fonkeling'),
    laurel => tr('Laurel', 'Lauwerkrans'),
    ripple => tr('Ripple', 'Rimpeling'),
    spin => tr('Spin', 'Draaikrans'),
    sunburst => tr('Sunburst', 'Zonnestralen'),
    crown => tr('Crown', 'Kroon'),
    wings => tr('Wings', 'Vleugels'),
    blades => tr('Blades', 'Klingen'),
    royal => tr('Royal', 'Koninklijk'),
  };

  /// Beweegt deze rand? De versierde randen (lauwerkrans, kroon, vleugels, klingen, koninklijk) staan stil.
  bool get animated => switch (this) {
    glow || orbit || sparkle || ripple || spin || sunburst => true,
    laurel || crown || wings || blades || royal => false,
  };

  /// Uit een id van de server; onbekend of leeg = geen rand.
  static AvatarFrame? parse(Object? id) => values.where((f) => f.id == id).firstOrNull;
}

/// Pro zoals de server het kent.
@immutable
class ProStatus {
  const ProStatus({this.until, this.source, this.showBadge = true, this.frame});

  /// Tot wanneer Pro loopt (null = nooit gehad).
  final DateTime? until;

  /// manual, gift, play, web, ...
  final String? source;

  /// Het Supporter-badge tonen aan vrienden.
  final bool showBadge;

  /// De gekozen supporterrand (null = geen, of een server zonder de migratie).
  final AvatarFrame? frame;

  bool activeAt(DateTime now) => until != null && until!.isAfter(now);

  factory ProStatus.fromJson(Map j) => ProStatus(
    until: j['until'] is String ? DateTime.tryParse(j['until'] as String) : null,
    source: j['source'] as String?,
    showBadge: j['show_badge'] != false,
    frame: AvatarFrame.parse(j['frame']),
  );

  Map<String, Object?> toJson() => {'until': until?.toUtc().toIso8601String(), 'source': source, 'show_badge': showBadge, 'frame': frame?.id};

  ProStatus copyWith({bool? showBadge}) => ProStatus(until: until, source: source, showBadge: showBadge ?? this.showBadge, frame: frame);

  /// Dezelfde status met een andere rand (null = geen).
  ProStatus withFrame(AvatarFrame? f) => ProStatus(until: until, source: source, showBadge: showBadge, frame: f);
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

/// De supporterrand bestaat (nog) niet op de server.
class FrameMissing implements Exception {
  const FrameMissing();
  @override
  String toString() => 'FrameMissing';
}

/// Voor de supporterrand: los van [ProRemote], zodat een server (of een nabootsing) zonder randen gewoon werkt.
abstract class ProFrameRemote {
  /// Je rand kiezen (null = geen). Geeft false als de server weigert (geen Pro). Gooit [FrameMissing] als de
  /// migratie er nog niet staat.
  Future<bool> setFrame(AvatarFrame? frame);
}

/// Wat de app van de server nodig heeft. Gooit [ProMissing] als de migratie er nog niet staat.
abstract class ProRemote {
  Future<ProStatus> mine();
  Future<PhotoQuota?> quota();
  Future<void> showBadge(bool show);
}

class SupabaseProRemote implements ProRemote, AiQuotaRemote, ProFrameRemote {
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

  @override
  Future<bool> setFrame(AvatarFrame? frame) async {
    try {
      return await client.rpc('pro_set_frame', params: {'p_frame': frame?.id}) == true;
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const FrameMissing();
      rethrow;
    }
  }

  @override
  Future<PhotoQuota?> aiQuota(AiKind kind) async {
    try {
      return PhotoQuota.fromJson(await client.rpc('ai_quota', params: {'p_kind': kind.name}));
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const AiQuotaMissing();
      rethrow;
    }
  }
}

class Pro extends ChangeNotifier {
  Pro(this.account, {ProRemote? Function()? remote, this.purchases = const NoPurchaseProvider(), DateTime Function()? clock})
    : _remoteFor = remote,
      _clock = clock ?? DateTime.now {
    _uid = account.user?.id;
    _loadCache();
    account.addListener(_changed);
    // Na een aankoop die de server goedkeurde: de status opnieuw ophalen. De winkel klaar (of een betaling in
    // afwachting): het Pro-scherm opnieuw tekenen.
    purchases.attach(refresh);
    if (purchases case final Listenable l) l.addListener(_purchasesChanged);
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
    _ai.clear();
    available = true;
    aiAvailable = true;
    frameAvailable = true;
    _rechecked = false;
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
    _maybeRecheck();
  }

  void _purchasesChanged() {
    notifyListeners();
    _maybeRecheck();
  }

  /// Al stil nagekeken bij de winkel in deze sessie (voor dit account)?
  bool _rechecked = false;

  /// Loopt Pro binnen 3 dagen af (of is het al afgelopen, of nooit gehad)? Dan één keer per sessie stil bij de winkel
  /// nakijken of er een abonnement loopt. Zo verlengt een vernieuwd abonnement Pro vanzelf (de server schuift until
  /// op), en wordt een aankoop die nooit bij de server aankwam (app gestopt na het betalen) alsnog gekoppeld.
  void _maybeRecheck() {
    if (_rechecked || !purchases.available || account.user == null || remote == null || debugPro != null) return;
    final until = status.until;
    if (until != null && until.isAfter(_clock().add(const Duration(days: 3)))) return;
    _rechecked = true;
    unawaited(purchases.recheck());
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

  // --- De AI-tellers (etiket lezen, recept importeren)

  final Map<AiKind, PhotoQuota> _ai = {};

  /// false zodra blijkt dat de server de AI-tellers niet kent (migratie 20261027000000 nog niet uitgevoerd). Een
  /// etiket lezen werkt dan zonder teller; een recept importeren kan dan niet (Pro is niet na te kijken).
  bool aiAvailable = true;

  /// Stand van de teller voor [kind] vandaag (null = onbekend). In een debug-build met Pro nagebootst: de grens die
  /// je met (of zonder) Pro zou zien.
  PhotoQuota? aiQuota(AiKind kind) {
    final q = _ai[kind]?.on(_clock());
    if (q == null) return null;
    final dbg = debugPro;
    if (dbg == null || q.pro == dbg) return q;
    return PhotoQuota(used: q.used, limit: kind.limitFor(dbg), pro: dbg, day: q.day);
  }

  /// Mag je [kind] nu gebruiken, volgens wat de app weet? De server beslist altijd zelf; dit is voor de knoppen.
  /// Een recept importeren alleen met Pro (of met Pro nagebootst in een debug-build).
  bool canUse(AiKind kind) {
    if (kind.proOnly && !isPro) return false;
    return aiQuota(kind)?.allowed ?? true;
  }

  /// De AI-teller van [kind] ophalen (bij het openen van het etiket- of receptscherm).
  Future<void> refreshAiQuota(AiKind kind) async {
    final ai = switch (remote) {
      final AiQuotaRemote a => a,
      _ => null,
    };
    if (ai == null || !aiAvailable) return;
    try {
      final q = await ai.aiQuota(kind);
      if (q != null) _ai[kind] = q;
    } on AiQuotaMissing {
      aiAvailable = false;
    } on ProMissing {
      aiAvailable = false;
    } catch (e) {
      debugPrint('pro ai: $e');
    }
    notifyListeners();
  }

  /// Stand die /api/label of /api/recipe meestuurde (na gebruik, of bij "op" met een 429).
  void noteAiQuota(AiKind kind, PhotoQuota q) {
    _ai[kind] = q;
    aiAvailable = true;
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

  /// false zodra blijkt dat de server de supporterranden niet kent (migratie 20261030000000 nog niet uitgevoerd).
  bool frameAvailable = true;

  /// Je eigen rand: alleen zolang Pro loopt. Loopt Pro af, dan verdwijnt hij (de server bewaart de keuze wel).
  AvatarFrame? get frame => isPro ? status.frame : null;

  /// Een rand kiezen (null = geen). In een debug-build met Pro nagebootst alleen op dit toestel. Geeft true als het
  /// lukte.
  Future<bool> setFrame(AvatarFrame? f) async {
    final r = remote;
    var ok = false;
    if (r is ProFrameRemote && isPro && debugPro == null) {
      try {
        ok = await (r as ProFrameRemote).setFrame(f);
        frameAvailable = true;
      } on FrameMissing {
        frameAvailable = false;
      } catch (e) {
        debugPrint('pro frame: $e');
      }
    }
    if (ok || debugPro == true) {
      status = status.withFrame(f);
      _saveCache();
      ok = true;
    }
    notifyListeners();
    return ok;
  }

  /// Abonneren via de [purchases]; bij succes de status opnieuw ophalen. Pro hoort bij een account: zonder inloggen
  /// [PurchaseOutcome.signedOut].
  Future<PurchaseOutcome> subscribe(ProPlan plan) async {
    if (!purchases.available) return PurchaseOutcome.unavailable;
    final out = await purchases.subscribe(plan);
    if (out == PurchaseOutcome.done) await refresh();
    return out;
  }

  /// Wat de winkel bij het laatste herstel zei (null = geen winkel). Voor een duidelijke melding als het niet lukte,
  /// bv. [PurchaseOutcome.otherAccount].
  PurchaseOutcome? restoreOutcome;

  /// Een aankoop herstellen: eerst bij de winkel (als die er is), daarna altijd de status bij de server ophalen,
  /// want daar staat Pro (ook als het met de hand of via het web toegekend is). Geeft true als Pro nu loopt.
  Future<bool> restore() async {
    restoreOutcome = purchases.available ? await purchases.restore() : null;
    await refresh();
    return isPro;
  }

  @override
  void dispose() {
    account.removeListener(_changed);
    if (purchases case final Listenable l) l.removeListener(_purchasesChanged);
    super.dispose();
  }
}
