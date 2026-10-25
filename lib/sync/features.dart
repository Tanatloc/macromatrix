/// Vroege toegang: nieuwe functies eerst voor supporters (Pro), een paar weken later voor iedereen.
///
/// Een functie achter een vlag zetten gaat zo:
///
/// 1. Geef ze een id en een standaard in [knownFeatures], bv. `'training_days': false`. De standaard geldt zolang de
///    server niets over die id weet (geen rij in public.features, migratie nog niet uitgevoerd, niet ingelogd of
///    nog nooit opgehaald). Zo kan een functie al in de app zitten voor de server klaar is.
/// 2. Zet de knop of het scherm in de app achter `featureOn(context, 'training_days')` (ui/widgets/feature_gate.dart),
///    of `features.has('training_days')` buiten een widget. Toon eventueel een [EarlyAccessChip] als
///    `features.isEarly(id)`.
/// 3. Zet ze aan in de SQL-editor: supporters nu, iedereen over 3 weken:
///
///    ```sql
///    insert into public.features (id, title_en, title_nl, early_from, public_from)
///    values ('training_days', 'Training and rest days', 'Trainings- en rustdagen', now(), now() + interval '3 weeks');
///    ```
///
/// Of iets aan staat, komt van de server (my_features, migratie 20261031000000_early_access.sql); de app bewaart
/// het laatste antwoord per account, zodat het ook zonder internet klopt. Met die bewaarde data rekent de app zelf
/// met early_from en public_from (en met [Pro.isPro]), zodat een functie op de juiste dag voor iedereen opengaat,
/// ook offline. Een id die nergens bekend is, staat uit.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase/supabase.dart';

import '../i18n.dart';
import 'account.dart';
import 'api.dart';
import 'challenges.dart' show isMissingTable;
import 'pro.dart';

/// De functies die in de app achter een vlag staan, met hun standaard.
const knownFeatures = <String, bool>{
  // Wekelijkse coach in het weekrapport (ui/widgets/coach_panel.dart, /api/coach, migratie 20261103000000_coach.sql)
  coachFeature: false,
};

/// Id van de wekelijkse coach, hier en in public.features.
const coachFeature = 'coach';

/// De vlaggen bestaan (nog) niet op de server.
class FeaturesMissing implements Exception {
  const FeaturesMissing();
  @override
  String toString() => 'FeaturesMissing';
}

/// Een vlag zoals de server ze kent.
@immutable
class FeatureFlag {
  const FeatureFlag({required this.id, this.titleEn = '', this.titleNl = '', this.earlyFrom, this.publicFrom});
  final String id, titleEn, titleNl;

  /// Vanaf wanneer supporters het hebben (null = geen vroege toegang).
  final DateTime? earlyFrom;

  /// Vanaf wanneer iedereen het heeft (null = nog niet voor iedereen).
  final DateTime? publicFrom;

  String get title => tr(titleEn.isEmpty ? id : titleEn, titleNl.isEmpty ? (titleEn.isEmpty ? id : titleEn) : titleNl);

  bool publicAt(DateTime now) => publicFrom != null && !publicFrom!.isAfter(now);

  /// Zit nu in de periode van vroege toegang (supporters wel, de rest nog niet).
  bool earlyAt(DateTime now) => earlyFrom != null && !earlyFrom!.isAfter(now) && !publicAt(now);

  bool onFor({required bool pro, required DateTime now}) => publicAt(now) || (pro && earlyAt(now));

  static DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

  factory FeatureFlag.fromJson(Map j) => FeatureFlag(
    id: j['id'] as String,
    titleEn: j['title_en'] as String? ?? '',
    titleNl: j['title_nl'] as String? ?? '',
    earlyFrom: _time(j['early_from']),
    publicFrom: _time(j['public_from']),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'title_en': titleEn,
    'title_nl': titleNl,
    'early_from': earlyFrom?.toUtc().toIso8601String(),
    'public_from': publicFrom?.toUtc().toIso8601String(),
  };
}

/// Wat de app van de server nodig heeft. Gooit [FeaturesMissing] als de migratie er nog niet staat.
abstract class FeaturesRemote {
  Future<List<FeatureFlag>> mine();
}

class SupabaseFeaturesRemote implements FeaturesRemote {
  SupabaseFeaturesRemote(this.client);
  final Rpc client;

  @override
  Future<List<FeatureFlag>> mine() async {
    try {
      final rows = await client.rpc('my_features');
      return [
        if (rows is List)
          for (final r in rows)
            if (r is Map && r['id'] is String) FeatureFlag.fromJson(r),
      ];
    } on PostgrestException catch (e) {
      if (isMissingTable(e)) throw const FeaturesMissing();
      rethrow;
    }
  }
}

class Features extends ChangeNotifier {
  Features(this.account, {this.pro, FeaturesRemote? Function()? remote, this.known = knownFeatures, DateTime Function()? clock})
    : _remoteFor = remote,
      _clock = clock ?? DateTime.now {
    _uid = account.user?.id;
    _wasPro = pro?.isPro ?? false;
    _loadCache();
    account.addListener(_accountChanged);
    pro?.addListener(_proChanged);
    if (remote != null || _uid != null) unawaited(refresh());
  }

  final Account account;

  /// Voor vroege toegang; zonder (bv. in sommige tests) ben je gewoon geen supporter.
  final Pro? pro;
  final FeaturesRemote? Function()? _remoteFor;

  /// De functies die de app kent, met hun standaard ([knownFeatures]; andere in tests).
  final Map<String, bool> known;
  final DateTime Function() _clock;

  /// De server, alleen als je ingelogd bent (of de nagebootste in tests).
  FeaturesRemote? get remote {
    if (_remoteFor != null) return _remoteFor();
    final c = account.api;
    return c == null || account.user == null ? null : SupabaseFeaturesRemote(c);
  }

  /// false zodra blijkt dat de server geen vlaggen kent (migratie nog niet uitgevoerd): dan gelden de standaarden.
  bool available = true;

  /// Laatst bekende vlaggen van de server (ook bewaard op dit toestel, per account).
  Map<String, FeatureFlag> _flags = {};

  bool loading = false;
  String? _uid;
  bool _wasPro = false;

  bool get _isPro => pro?.isPro ?? false;

  /// Staat [id] nu aan? Volgens de server als die de id kent, anders de standaard uit [knownFeatures] (en uit als
  /// ook die er niet is). Niet ingelogd of zonder server: alleen de standaarden.
  bool has(String id) {
    final f = remote == null ? null : _flags[id];
    if (f == null) return known[id] ?? false;
    return f.onFor(pro: _isPro, now: _clock());
  }

  /// Heb je [id] nu alleen dankzij vroege toegang (voor een "Early access"-label)?
  bool isEarly(String id) {
    final f = remote == null ? null : _flags[id];
    return f != null && _isPro && f.earlyAt(_clock());
  }

  /// De functies die nu in vroege toegang zijn (voor iedereen te zien op het roadmapscherm, met hun datum).
  List<FeatureFlag> get inEarlyAccess {
    if (remote == null) return const [];
    final now = _clock();
    return [
      for (final f in _flags.values)
        if (f.earlyAt(now)) f,
    ]..sort((a, b) => (a.publicFrom ?? DateTime(9999)).compareTo(b.publicFrom ?? DateTime(9999)));
  }

  void _loadCache() {
    final c = account.db.setting('_features');
    _flags = {};
    if (c == null || c['uid'] != _uid || c['flags'] is! List) return;
    for (final j in c['flags'] as List) {
      if (j is Map && j['id'] is String) {
        final f = FeatureFlag.fromJson(j);
        _flags[f.id] = f;
      }
    }
  }

  void _saveCache() => account.db.setSetting('_features', {
    'uid': _uid,
    'flags': [for (final f in _flags.values) f.toJson()],
  });

  void _accountChanged() {
    final uid = account.user?.id;
    if (uid == _uid) return;
    // Ander account: niets van het vorige onthouden
    _uid = uid;
    available = true;
    _loadCache();
    notifyListeners();
    if (uid != null) unawaited(refresh());
  }

  void _proChanged() {
    final now = _isPro;
    if (now == _wasPro) return;
    _wasPro = now;
    // Supporter geworden of niet meer: wat vroeg open staat, verandert meteen; daarna vers ophalen
    notifyListeners();
    unawaited(refresh());
  }

  Future<void>? _pending;
  bool _disposed = false;

  /// De vlaggen ophalen bij de server. Loopt er al een, dan wacht je op die.
  Future<void> refresh() {
    if (remote == null) return Future.value();
    return _pending ??= _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    final r = remote!;
    final uid = _uid;
    loading = true;
    try {
      final flags = await r.mine();
      // Intussen een ander account: dit antwoord hoort er niet bij
      if (uid != _uid || _disposed) return;
      _flags = {for (final f in flags) f.id: f};
      available = true;
      _saveCache();
    } on FeaturesMissing {
      if (uid != _uid || _disposed) return;
      available = false;
      _flags = {};
      account.db.deleteSetting('_features');
    } catch (e) {
      // Geen verbinding of een storing: de bewaarde vlaggen blijven gelden
      debugPrint('features: $e');
    } finally {
      loading = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    account.removeListener(_accountChanged);
    pro?.removeListener(_proChanged);
    super.dispose();
  }
}
