/// Synchronisatie tussen de lokale database en de server, "lokaal eerst": de app werkt altijd met de lokale
/// database; deze motor stuurt wijzigingen door en haalt die van andere toestellen op.
///
/// - Versturen: rijen met `synced = 0` (zie [UserDb.dirtyRows]), in pakketten. Daarna vergelijken we wat de server
///   bewaarde: hield hij een andere versie (nieuwer van een ander toestel, of met een begrensde tijd), dan nemen we
///   die over in plaats van de rij als verstuurd te markeren. Rijen die de app zelf maakte ([UserDb.generatedAt]) gaan
///   alleen mee als de server ze nog niet heeft.
/// - Weigert de server een pakket om één rij (te lang, te veel rijen …), dan zoeken we die rij door het pakket te
///   halveren; ze krijgt `synced = 2` en de rest gaat gewoon door. Een fout bij één tabel houdt de andere niet tegen.
/// - Ophalen: per tabel alles wat de server sinds de vorige keer kreeg (`server_ts`, de klok van de server),
///   met twee minuten overlap voor wijzigingen die net nog bezig waren. Dubbel ophalen is onschuldig.
/// - Conflicten: de laatste wijziging wint (`updated_at`), zowel hier ([UserDb.applyRemote]) als op de server
///   (trigger in supabase/migrations).
library;

import '../data/user_db.dart';
import 'api.dart' show SequenceRemote;

/// Soort fout van de server.
enum SyncErrorKind {
  /// De server weigert (een rij uit) de gegevens: te lang, te veel rijen, ongeldige waarde.
  row,

  /// Een probleem met de hele tabel (bv. een kolom die op de server nog ontbreekt): de andere tabellen gaan door.
  table,

  /// Geen internet, sessie verlopen, server onbereikbaar …: stoppen en later opnieuw.
  fatal,
}

/// De server, los van Supabase, zodat de motor testbaar is.
abstract class SyncRemote {
  /// Rijen opslaan (of bijwerken) voor de ingelogde gebruiker. Met [insertOnly] alleen rijen die de server nog niet
  /// heeft: een bestaande blijft zoals ze is. Geeft voor de rijen die de server opsloeg de versie (`updated_at`) die
  /// hij nu heeft, op sleutel; wat hij niet opsloeg (een oudere versie, of al aanwezig) ontbreekt. Null: onbekend.
  Future<Map<String, int>?> push(SyncTable table, List<Map<String, Object?>> rows, {bool insertOnly = false});

  /// Rijen met een `server_ts` na [since] (null = alles), oplopend gesorteerd, hooguit [limit].
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit);

  /// De rijen met deze sleutels zoals ze nu op de server staan (wat er niet is, ontbreekt).
  Future<List<Map<String, Object?>>> fetch(SyncTable table, List<String> keys);

  SyncErrorKind classify(Object error);
}

/// De synchronisatie werd afgebroken (uitgelogd of een ander account): niets meer schrijven.
class SyncCancelled implements Exception {
  const SyncCancelled();
}

class SyncResult {
  const SyncResult({this.pushed = 0, this.pulled = 0, this.rejected = 0, this.errors = const {}});
  final int pushed;

  /// Rijen van de server die hier iets veranderden.
  final int pulled;

  /// Rijen die de server deze keer weigerde (ze blijven op dit toestel, zie [UserDb.rejectedCount]).
  final int rejected;

  /// Tabellen die niet lukten, met de fout. De andere tabellen zijn wel gesynchroniseerd.
  final Map<String, Object> errors;
}

class SyncEngine {
  SyncEngine(this.db, this.remote, {required this.userId, this.active});

  final UserDb db;
  final SyncRemote remote;

  /// Cursors horen bij één gebruiker: een andere gebruiker begint opnieuw.
  final String userId;

  /// Mag deze synchronisatie nog schrijven? Gecontroleerd vóór elke schrijfactie (na uitloggen niet meer).
  final bool Function()? active;

  static const pushBatch = 500;
  static const pullPage = 1000;
  static const overlap = Duration(minutes: 2);

  /// Hoeveel verzoeken een tabel per keer mag gebruiken om geweigerde rijen te zoeken. Daarna de volgende keer verder.
  static const rejectSearchBudget = 100;

  /// Geweigerde rijen na zoveel tijd opnieuw proberen (misschien is de server intussen anders).
  static const retryRejectedAfter = Duration(days: 7);

  Map<String, Object?> get _state {
    final s = db.setting('_sync');
    return s != null && s['user'] == userId ? s : {'user': userId, 'cursors': <String, Object?>{}};
  }

  /// Tijdstip van de laatste synchronisatie waarbij de instellingen (je profiel) binnenkwamen (ms), of null: dan
  /// is er voor deze gebruiker nog nooit iets van de server opgehaald.
  int? get lastSync => (_state['last'] as num?)?.toInt();

  void _check() {
    if (active != null && !active!()) throw const SyncCancelled();
  }

  bool _fatal(Object e) => e is SyncCancelled || remote.classify(e) == SyncErrorKind.fatal;

  var _pushed = 0, _pulled = 0, _rejected = 0, _budget = 0;

  Future<SyncResult> run() async {
    _check();
    final state = _state;
    final cursors = Map<String, Object?>.from(state['cursors'] as Map? ?? const {});
    final errors = <String, Object>{};
    _pushed = _pulled = _rejected = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Sinds wanneer er geweigerde rijen zijn (null: geen)
    var rejectedAt = (state['rejected'] as num?)?.toInt();
    if (rejectedAt != null && now - rejectedAt > retryRejectedAfter.inMilliseconds) {
      db.retryRejected();
      rejectedAt = null;
    }

    for (final t in UserDb.syncTables) {
      try {
        await _pushTable(t);
      } catch (e) {
        if (_fatal(e)) rethrow;
        errors[t.name] = e;
      }
    }

    var settingsPulled = false;
    Future<void> pull(SyncTable t) async {
      try {
        final newest = await _pullTable(t, cursors[t.name] as String?);
        if (newest != null) cursors[t.name] = newest;
        if (t.name == 'settings') settingsPulled = true;
      } catch (e) {
        if (_fatal(e)) rethrow;
        errors[t.name] ??= e;
      }
    }

    // De eigen server: alle tabellen tegelijk (één wachttijd in plaats van negen). Elke tabel schrijft in zijn eigen
    // transactie, dus dat kan veilig door elkaar. Supabase zoals vroeger, na elkaar.
    if (remote is SequenceRemote) {
      await Future.wait([for (final t in UserDb.syncTables) pull(t)], eagerError: true);
    } else {
      for (final t in UserDb.syncTables) {
        await pull(t);
      }
    }

    _check();
    if (_rejected > 0) rejectedAt ??= now;
    db.setSetting('_sync', {
      for (final e in state.entries)
        if (e.key != 'rejected') e.key: e.value,
      'cursors': cursors,
      if (settingsPulled) 'last': DateTime.now().millisecondsSinceEpoch,
      'rejected': ?rejectedAt,
    });
    return SyncResult(pushed: _pushed, pulled: _pulled, rejected: _rejected, errors: errors);
  }

  Future<void> _pushTable(SyncTable t) async {
    _budget = rejectSearchBudget;
    // Hoogstens zoveel rondes: een rij die telkens opnieuw gewijzigd wordt, houdt de rest niet eindeloos op
    for (var round = 0; round < 200; round++) {
      final rows = db.dirtyRows(t, limit: pushBatch);
      if (rows.isEmpty) break;
      bool generated(Map<String, Object?> r) => ((r['updated_at'] as num?)?.toInt() ?? 0) <= UserDb.generatedAt;
      final normal = [for (final r in rows) if (!generated(r)) r];
      final fresh = [for (final r in rows) if (generated(r)) r];
      if (normal.isNotEmpty) await _push(t, normal, insertOnly: false);
      if (fresh.isNotEmpty) await _push(t, fresh, insertOnly: true);
      if (rows.length < pushBatch) break;
    }
  }

  Future<void> _push(SyncTable t, List<Map<String, Object?>> rows, {required bool insertOnly}) async {
    Map<String, int>? kept;
    try {
      kept = await remote.push(t, rows, insertOnly: insertOnly);
    } catch (e) {
      if (e is SyncCancelled || remote.classify(e) != SyncErrorKind.row) rethrow;
      if (rows.length == 1) {
        _check();
        db.markRejected(t, rows.single);
        _rejected++;
        return;
      }
      // Halveren tot de geweigerde rij(en) gevonden zijn; is het budget op, dan de volgende keer verder
      if ((_budget -= 2) < 0) rethrow;
      final half = rows.length ~/ 2;
      await _push(t, rows.sublist(0, half), insertOnly: insertOnly);
      await _push(t, rows.sublist(half), insertOnly: insertOnly);
      return;
    }
    _check();
    if (kept == null) {
      db.markSynced(t, rows);
      _pushed += rows.length;
      return;
    }
    final same = <Map<String, Object?>>[], other = <Map<String, Object?>>[];
    for (final r in rows) {
      (kept['${r[t.key]}'] == (r['updated_at'] as num?)?.toInt() ? same : other).add(r);
    }
    db.markSynced(t, same);
    _pushed += same.length;
    if (other.isEmpty) return;
    // De server hield een andere versie: die overnemen, zodat dit toestel niet denkt dat zijn versie er staat
    final server = {for (final s in await remote.fetch(t, [for (final r in other) '${r[t.key]}'])) '${s[t.key]}': s};
    _check();
    final missing = <Map<String, Object?>>[];
    db.transaction(() {
      for (final r in other) {
        final s = server['${r[t.key]}'];
        if (s == null) {
          missing.add(r);
        } else if (db.replaceIfUnchanged(t, s, (r['updated_at'] as num).toInt())) {
          _pulled++;
        }
      }
    });
    // Niets op de server (zou niet mogen): als verstuurd beschouwen, anders blijft het eindeloos proberen
    if (missing.isNotEmpty) db.markSynced(t, missing);
  }

  /// Geeft de nieuwe cursor (of null als er niets was).
  Future<String?> _pullTable(SyncTable t, String? cursor) async {
    final r = remote;
    if (r is SequenceRemote) return _pullSequence(r, t, cursor);
    var since = cursor == null ? null : DateTime.parse(cursor).subtract(overlap).toUtc().toIso8601String();
    String? newest = cursor;
    while (true) {
      final rows = await remote.pull(t, since, pullPage);
      if (rows.isEmpty) break;
      _check();
      db.transaction(() {
        for (final r in rows) {
          if (db.applyRemote(t, r)) _pulled++;
        }
      });
      // Altijd als UTC met "Z": een "+00:00" in de URL kan als spatie aankomen
      final last = DateTime.parse(rows.last['server_ts'] as String).toUtc().toIso8601String();
      if (newest == null || DateTime.parse(last).isAfter(DateTime.parse(newest))) newest = last;
      if (rows.length < pullPage) break;
      since = last;
    }
    return newest;
  }

  /// Zoals [_pullTable], met een oplopend getal als cursor (de eigen server): geen overlap nodig. Een cursor die geen
  /// getal is (nog van Supabase), telt niet: dan alles opnieuw ophalen.
  Future<String?> _pullSequence(SequenceRemote r, SyncTable t, String? cursor) async {
    var since = int.tryParse(cursor ?? '') == null ? null : cursor;
    String? newest = since;
    while (true) {
      final rows = await r.pull(t, since, pullPage);
      if (rows.isEmpty) break;
      _check();
      db.transaction(() {
        for (final row in rows) {
          if (db.applyRemote(t, row)) _pulled++;
        }
      });
      newest = since = r.cursorOf(rows.last);
      if (rows.length < pullPage) break;
    }
    return newest;
  }
}
