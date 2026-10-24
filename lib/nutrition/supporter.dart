/// Supporterbadges en -titels: extra's die je alleen met Pro verdient.
///
/// Badges (zie [badgeCategories] in badges.dart, groep [BadgeGroup.supporter]):
/// - Etiketjager (`labels`): eigen producten toegevoegd.
/// - Wereldverbeteraar (`offshare`): producten gedeeld met Open Food Facts (teller `offShared`).
/// - Chef (`chef`): recepten gemaakt of geïmporteerd.
/// - Trouwe supporter (`loyal`): maanden Pro.
///
/// Titels: Supporter (zodra je Pro hebt), Mecenas (12 maanden Pro, = Trouwe supporter goud) en Stichter (Pro
/// geworden vóór [founderCutoff], het eerste jaar).
///
/// Wat er gebeurt als Pro stopt (bewuste keuze):
/// - Wat je verdiende, blijft: de badges houden hun niveau en de titels blijven kiesbaar en zichtbaar voor vrienden.
///   Daarvoor bewaren we per badge de hoogste waarde die je bereikte terwijl Pro liep ([SupporterRecord.best]).
/// - Er komt niets meer bij: zonder Pro telt alleen die bewaarde waarde, niet je huidige aantal, en de maanden staan
///   stil. Wat je zonder Pro toevoegde, telt weer mee zodra Pro opnieuw loopt (dan geldt weer je huidige aantal).
///
/// De server kent alleen `until` (tot wanneer Pro loopt), niet sinds wanneer. Daarom houdt de app zelf bij wanneer
/// ze Pro voor het eerst zag en hoeveel dagen Pro er al waren. Dat staat in de gesynchroniseerde instelling
/// `supporter` (overleeft een herinstallatie) en als kopie lokaal in `_supporter`.
library;

import 'dart:math' as math;

/// Wie vóór dit moment (UTC) Pro werd, is Stichter.
final founderCutoff = DateTime.utc(2027, 10, 1);

/// Stichter: Pro voor het eerst gezien vóór [founderCutoff].
bool isFounder(DateTime? firstPro) => firstPro != null && firstPro.toUtc().isBefore(founderCutoff);

/// De supporterbadges (categorieën die alleen met Pro tellen).
const supporterBadgeIds = ['labels', 'offshare', 'chef', 'loyal'];

/// Een maand Pro = 30 dagen (een jaarabonnement van 365 dagen geeft zo zeker 12 maanden).
int monthsFromDays(int days) => days ~/ 30;

/// Een onderbreking van hoogstens zoveel dagen geldt niet als stoppen (bv. een verlenging die de app pas na een paar
/// dagen zag, of een toestel dat even offline was).
const _bridgeDays = 3;

DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;

DateTime? _earliest(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isBefore(b) ? a : b);

DateTime? _latest(DateTime? a, DateTime? b) => a == null ? b : (b == null || a.isAfter(b) ? a : b);

/// Wat de app over je Pro-geschiedenis onthoudt.
class SupporterRecord {
  const SupporterRecord({this.firstPro, this.since, this.lastActive, this.bankedDays = 0, this.best = const {}});

  /// Eerste keer dat de app Pro zag (voor Stichter).
  final DateTime? firstPro;

  /// Begin van de lopende Pro-periode (null = nu geen Pro).
  final DateTime? since;

  /// Laatste keer (dag) dat Pro liep: einde van een periode als `until` onbekend is.
  final DateTime? lastActive;

  /// Dagen Pro uit afgesloten periodes.
  final int bankedDays;

  /// Hoogste waarde per supporterbadge zolang Pro liep: dat blijft verdiend als Pro stopt.
  final Map<String, int> best;

  bool get hadPro => firstPro != null;

  /// Dagen Pro tot [now] (de lopende periode telt alleen mee zolang Pro loopt).
  int daysAt(DateTime now, {required bool active}) {
    final s = since;
    final running = active && s != null && now.isAfter(s) ? now.difference(s).inDays : 0;
    return bankedDays + running;
  }

  int monthsAt(DateTime now, {required bool active}) => math.max(monthsFromDays(daysAt(now, active: active)), best['loyal'] ?? 0);

  factory SupporterRecord.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const SupporterRecord();
    final best = j['best'];
    return SupporterRecord(
      firstPro: _date(j['first']),
      since: _date(j['since']),
      lastActive: _date(j['last']),
      bankedDays: (j['days'] as num?)?.toInt() ?? 0,
      best: {
        if (best is Map)
          for (final e in best.entries)
            if (e.value is num) '${e.key}': (e.value as num).toInt(),
      },
    );
  }

  Map<String, Object?> toJson() => {
    'first': firstPro?.toUtc().toIso8601String(),
    'since': since?.toUtc().toIso8601String(),
    'last': lastActive?.toUtc().toIso8601String(),
    'days': bankedDays,
    'best': best,
  };

  /// Twee versies samenvoegen (de lokale kopie en de gesynchroniseerde): de vroegste eerste Pro-datum, de meeste
  /// dagen en per badge de hoogste waarde. Zo gaat er nooit iets verloren als een ander toestel ertussen schreef.
  static SupporterRecord merge(SupporterRecord a, SupporterRecord b) {
    // Basis: de versie met de meeste afgesloten dagen; bij gelijkstand die met een lopende periode
    final base = a.bankedDays > b.bankedDays || (a.bankedDays == b.bankedDays && a.since != null) ? a : b;
    return SupporterRecord(
      firstPro: _earliest(a.firstPro, b.firstPro),
      since: base.since,
      lastActive: _latest(a.lastActive, b.lastActive),
      bankedDays: base.bankedDays,
      best: {
        for (final k in {...a.best.keys, ...b.best.keys}) k: math.max(a.best[k] ?? 0, b.best[k] ?? 0),
      },
    );
  }

  /// Nieuwe stand na een blik op de Pro-status: [active] loopt Pro nu, [until] van de server, [live] de huidige
  /// waarden van de supporterbadges (alleen gebruikt zolang Pro loopt).
  SupporterRecord observe(DateTime now, {required bool active, DateTime? until, Map<String, int> live = const {}}) {
    final today = DateTime.utc(now.toUtc().year, now.toUtc().month, now.toUtc().day);
    if (active) {
      var start = since;
      var banked = bankedDays;
      if (start == null) {
        // Nieuwe periode; was de vorige pas net voorbij, dan loopt ze gewoon door
        final end = lastActive;
        if (end != null && now.difference(end).inDays <= _bridgeDays) {
          start = end.subtract(Duration(days: banked));
          banked = 0;
        } else {
          start = now.toUtc();
        }
      }
      final next = SupporterRecord(firstPro: _earliest(firstPro, now.toUtc()), since: start, lastActive: today, bankedDays: banked, best: best);
      final months = next.monthsAt(now, active: true);
      return SupporterRecord(
        firstPro: next.firstPro,
        since: next.since,
        lastActive: next.lastActive,
        bankedDays: next.bankedDays,
        best: {
          ...best,
          for (final e in live.entries)
            if (e.key != 'loyal' && e.value > (best[e.key] ?? 0)) e.key: e.value,
          if (months > (best['loyal'] ?? 0)) 'loyal': months,
        },
      );
    }
    final s = since;
    if (s == null) return this;
    // Pro is gestopt: de periode afsluiten op `until` (als die klopt), anders op de laatste dag dat Pro liep
    var end = lastActive ?? s;
    final u = until?.toUtc();
    if (u != null && u.isAfter(s) && !u.isAfter(now.toUtc())) end = _latest(end, u)!;
    final days = bankedDays + (end.isAfter(s) ? end.difference(s).inDays : 0);
    final months = monthsFromDays(days);
    return SupporterRecord(
      firstPro: firstPro,
      lastActive: end,
      bankedDays: days,
      best: {...best, if (months > (best['loyal'] ?? 0)) 'loyal': months},
    );
  }
}

/// Lees een teller defensief: een getal, of een instelling als {'count': 3} / {'value': 3} / {'n': 3}.
int readCounter(Object? v) {
  if (v is num) return v.toInt();
  if (v is Map) {
    for (final k in const ['count', 'value', 'n', 'shared']) {
      if (v[k] is num) return (v[k] as num).toInt();
    }
    for (final x in v.values) {
      if (x is num) return x.toInt();
    }
  }
  return 0;
}

/// Waarden van de supporterbadges.
///
/// Met Pro: je huidige aantallen (en nooit minder dan wat je al bereikte). Zonder Pro: alleen wat je bereikte
/// terwijl Pro liep (verdiend blijft verdiend, maar er komt niets bij). Wie nooit Pro had, staat overal op 0.
Map<String, int> supporterValues({
  required bool active,
  required SupporterRecord record,
  required DateTime now,
  int customFoods = 0,
  int offShared = 0,
  int recipes = 0,
}) {
  final best = record.best;
  if (!active) {
    return {
      'labels': best['labels'] ?? 0,
      'offshare': best['offshare'] ?? 0,
      'chef': best['chef'] ?? 0,
      'loyal': record.monthsAt(now, active: false),
    };
  }
  return {
    'labels': math.max(customFoods, best['labels'] ?? 0),
    'offshare': math.max(offShared, best['offshare'] ?? 0),
    'chef': math.max(recipes, best['chef'] ?? 0),
    'loyal': record.monthsAt(now, active: true),
  };
}
