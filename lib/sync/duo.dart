/// Duo: wie een Duo-abonnement heeft, kiest één vriend die ook Supporter is zolang het abonnement loopt
/// (server/src/rpc/duo.js). De partner wisselt hoogstens één keer per 30 dagen.
library;

import 'package:flutter/foundation.dart';

enum DuoRole { none, owner, partner }

/// Uitkomst van een partner kiezen.
enum DuoResult {
  ok,

  /// Geen lopend Duo-abonnement.
  noDuo,

  /// Jezelf gekozen.
  self,

  /// Geen vrienden (meer).
  notFriends,

  /// Zit al in een Duo.
  taken,

  /// Pas na 30 dagen opnieuw wisselen.
  tooSoon,

  /// Geen verbinding of een andere fout.
  failed;

  static DuoResult parse(Object? s) => switch (s) {
    'ok' => ok,
    'no_duo' => noDuo,
    'self' => self,
    'not_friends' => notFriends,
    'taken' => taken,
    'too_soon' => tooSoon,
    _ => failed,
  };
}

@immutable
class DuoPerson {
  const DuoPerson(this.id, this.name);
  final String id;
  final String? name;
}

@immutable
class DuoStatus {
  const DuoStatus({this.role = DuoRole.none, this.active = false, this.until, this.partner, this.owner, this.nextChange});

  static const none = DuoStatus();

  final DuoRole role;

  /// Loopt het Duo-abonnement van de koper nog?
  final bool active;
  final DateTime? until;

  /// Voor de koper: de gekozen vriend (null = nog niemand).
  final DuoPerson? partner;

  /// Voor de partner: wie het abonnement heeft.
  final DuoPerson? owner;

  /// Voor de koper: vanaf wanneer de partner weer kan wisselen (null = nu al).
  final DateTime? nextChange;

  factory DuoStatus.fromJson(Object? j) {
    if (j is! Map) return none;
    DuoPerson? person(Object? p) => p is Map && p['id'] is String ? DuoPerson(p['id'] as String, p['name'] as String?) : null;
    DateTime? date(Object? v) => v is String ? DateTime.tryParse(v) : null;
    return DuoStatus(
      role: switch (j['role']) {
        'owner' => DuoRole.owner,
        'partner' => DuoRole.partner,
        _ => DuoRole.none,
      },
      active: j['active'] == true,
      until: date(j['until']),
      partner: person(j['partner']),
      owner: person(j['owner']),
      nextChange: date(j['next_change']),
    );
  }
}

/// De server voor Duo.
abstract class DuoRemote {
  Future<DuoStatus> duoStatus();
  Future<(DuoResult, DuoStatus)> duoSetPartner(String friendId);
  Future<DuoStatus> duoRemove();
  Future<DuoStatus> duoLeave();
}
