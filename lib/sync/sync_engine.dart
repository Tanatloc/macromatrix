/// Synchronisatie tussen de lokale database en de server, "lokaal eerst": de app werkt altijd met de lokale
/// database; deze motor stuurt wijzigingen door en haalt die van andere toestellen op.
///
/// - Versturen: rijen met `synced = 0` (zie [UserDb.dirtyRows]), in pakketten.
/// - Ophalen: per tabel alles wat de server sinds de vorige keer kreeg (`server_ts`, de klok van de server),
///   met twee minuten overlap voor wijzigingen die net nog bezig waren. Dubbel ophalen is onschuldig.
/// - Conflicten: de laatste wijziging wint (`updated_at`), zowel hier ([UserDb.applyRemote]) als op de server
///   (trigger in supabase/migrations).
library;

import '../data/user_db.dart';

/// De server, los van Supabase, zodat de motor testbaar is.
abstract class SyncRemote {
  /// Rijen opslaan (of bijwerken) voor de ingelogde gebruiker.
  Future<void> push(SyncTable table, List<Map<String, Object?>> rows);

  /// Rijen met een `server_ts` na [since] (null = alles), oplopend gesorteerd, hooguit [limit].
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit);
}

class SyncResult {
  const SyncResult({this.pushed = 0, this.pulled = 0});
  final int pushed;

  /// Rijen van de server die hier iets veranderden.
  final int pulled;
}

class SyncEngine {
  SyncEngine(this.db, this.remote, {required this.userId});

  final UserDb db;
  final SyncRemote remote;

  /// Cursors horen bij één gebruiker: een andere gebruiker begint opnieuw.
  final String userId;

  static const pushBatch = 500;
  static const pullPage = 1000;
  static const overlap = Duration(minutes: 2);

  Map<String, Object?> get _state {
    final s = db.setting('_sync');
    return s != null && s['user'] == userId ? s : {'user': userId, 'cursors': <String, Object?>{}};
  }

  /// Tijdstip van de laatste geslaagde synchronisatie (ms), of null.
  int? get lastSync => (_state['last'] as num?)?.toInt();

  Future<SyncResult> run() async {
    final state = _state;
    final cursors = Map<String, Object?>.from(state['cursors'] as Map? ?? const {});
    var pushed = 0, pulled = 0;

    for (final t in UserDb.syncTables) {
      while (true) {
        final rows = db.dirtyRows(t, limit: pushBatch);
        if (rows.isEmpty) break;
        await remote.push(t, rows);
        db.markSynced(t, rows);
        pushed += rows.length;
        if (rows.length < pushBatch) break;
      }
    }

    for (final t in UserDb.syncTables) {
      final cursor = cursors[t.name] as String?;
      var since = cursor == null ? null : DateTime.parse(cursor).subtract(overlap).toUtc().toIso8601String();
      String? newest = cursor;
      while (true) {
        final rows = await remote.pull(t, since, pullPage);
        if (rows.isEmpty) break;
        db.transaction(() {
          for (final r in rows) {
            if (db.applyRemote(t, r)) pulled++;
          }
        });
        // Altijd als UTC met "Z": een "+00:00" in de URL kan als spatie aankomen
        final last = DateTime.parse(rows.last['server_ts'] as String).toUtc().toIso8601String();
        if (newest == null || DateTime.parse(last).isAfter(DateTime.parse(newest))) newest = last;
        if (rows.length < pullPage) break;
        since = last;
      }
      if (newest != null) cursors[t.name] = newest;
    }

    db.setSetting('_sync', {...state, 'cursors': cursors, 'last': DateTime.now().millisecondsSinceEpoch});
    return SyncResult(pushed: pushed, pulled: pulled);
  }
}
