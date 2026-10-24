/// Houdt je Pro-geschiedenis bij voor de supporterbadges en -titels (zie nutrition/supporter.dart).
///
/// Kijkt bij elke wijziging van Pro, je account of je gegevens of er iets veranderde, en schrijft dan de
/// gesynchroniseerde instelling `supporter` en de lokale kopie `_supporter`. Beide worden altijd eerst samengevoegd,
/// zodat de vroegste eerste Pro-datum en de hoogste waarden blijven staan.
///
/// Op een nieuw toestel (of na een herinstallatie) wachten we met schrijven tot de eerste sync klaar is: anders zou
/// een verse lege stand de bewaarde stand op de server overschrijven (de laatste wijziging wint) en ben je je
/// Stichter-titel kwijt.
library;

import 'dart:convert';

import '../data/user_db.dart';
import '../nutrition/supporter.dart';
import 'account.dart';
import 'pro.dart';

/// Instelling (gesynchroniseerd) en lokale kopie.
const supporterSetting = 'supporter';
const supporterLocalSetting = '_supporter';

/// De bewaarde stand: lokale kopie en gesynchroniseerde instelling samen.
SupporterRecord supporterRecordOf(UserDb db) =>
    SupporterRecord.merge(SupporterRecord.fromJson(db.setting(supporterSetting)), SupporterRecord.fromJson(db.setting(supporterLocalSetting)));

/// Gedeeld met Open Food Facts: een teller die het delen zelf ophoogt. Ontbreekt die, dan 0.
int offSharedCount(UserDb db) => readCounter(db.setting('offShared'));

class SupporterTracker {
  SupporterTracker(this.db, this.account, this.pro, {DateTime Function()? clock, this.synced}) : _clock = clock ?? DateTime.now;

  final UserDb db;
  final Account account;
  final Pro pro;
  final DateTime Function() _clock;

  /// Alleen voor tests: zeggen of de eerste sync al klaar is.
  final bool Function()? synced;

  /// Is er al minstens één keer gesynchroniseerd (of is er geen server)?
  bool get _ready {
    final f = synced;
    if (f != null) return f();
    if (!Account.configured) return true;
    // Pro hoort bij een account: zonder (nog niet ingelogd bij het starten) zegt de status niets
    if (!account.signedIn) return false;
    return account.lastSync != null;
  }

  /// Stand bijwerken. Geeft true als er iets geschreven werd.
  bool update() {
    final active = pro.isPro;
    final rec = supporterRecordOf(db);
    // Nooit Pro gehad en nu ook niet: niets te doen
    if (!active && rec.since == null && !rec.hadPro) return false;
    if (!_ready) return false;
    final now = _clock();
    final live = active ? {'labels': db.customFoodCount(), 'offshare': offSharedCount(db), 'chef': db.recipeCount()} : const <String, int>{};
    final next = rec.observe(now, active: active, until: pro.status.until, live: live);
    final json = next.toJson();
    final enc = jsonEncode(json);
    String stored(String key) => jsonEncode(SupporterRecord.fromJson(db.setting(key)).toJson());
    var wrote = false;
    if (enc != stored(supporterSetting)) {
      db.setSetting(supporterSetting, json);
      wrote = true;
    }
    if (enc != stored(supporterLocalSetting)) db.setSetting(supporterLocalSetting, json);
    return wrote;
  }
}
