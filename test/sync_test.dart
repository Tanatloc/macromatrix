import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/sync_engine.dart';

/// Fout van de nagebootste server, met de soort zoals [SupabaseRemote.classifyError] die zou geven.
class FakeServerError implements Exception {
  FakeServerError(this.kind, this.message);
  final SyncErrorKind kind;
  final String message;
  @override
  String toString() => message;
}

/// Nagebootste server met dezelfde regels als de Supabase-triggers (supabase/migrations): oudere wijzigingen worden
/// genegeerd (stil), elke opgeslagen rij krijgt een oplopende server_ts, te lange velden en te veel rijen worden
/// geweigerd (het hele pakket, zoals één INSERT met meerdere rijen), en de upsert geeft terug wat opgeslagen werd.
class FakeServer implements SyncRemote {
  final rows = <String, Map<String, Map<String, Object?>>>{};
  var _clock = DateTime.utc(2026, 1, 1);
  var pushes = 0;

  /// Klok van de server (ms) voor het begrenzen van updated_at (20261107100000_sync_safety.sql); null: die migratie
  /// staat er nog niet op, niets begrenzen.
  int? nowMs;

  /// Hoogstens zoveel rijen per tabel (limit_rows). [oldLimitRows]: zoals vóór 20261107100000_sync_safety.sql, toen
  /// ook een upsert van een bestaande rij meetelde en verwijderde rijen ook.
  int maxRows = 50000;
  bool oldLimitRows = false;

  /// Tabellen waarbij versturen of ophalen helemaal mislukt (bv. een kolom die op de server nog ontbreekt).
  final brokenPush = <String>{}, brokenPull = <String>{};

  /// Geen internet.
  bool offline = false;

  /// Wordt opgeroepen vlak voor een ophaling antwoordt (om iets te laten gebeuren terwijl de synchronisatie loopt).
  Future<void> Function(SyncTable table)? beforePullReturns;

  String _tick() => (_clock = _clock.add(const Duration(milliseconds: 1))).toIso8601String();

  /// Grenzen uit 20261018000000_hardening.sql (een deel).
  static String? _tooLong(String table, Map<String, Object?> r) {
    int len(String c) => (r[c] as String?)?.length ?? 0;
    if (table == 'notes' && len('text') > 20000) return 'notes_size';
    if ((table == 'foods' || table == 'diary') && (len('name') > 500 || len('brand') > 300)) return '${table}_size';
    if ((table == 'meals' || table == 'exercise') && len('name') > 300) return '${table}_size';
    return null;
  }

  @override
  Future<Map<String, int>?> push(SyncTable table, List<Map<String, Object?>> batch, {bool insertOnly = false}) async {
    if (offline) throw Exception('geen internet');
    pushes++;
    if (brokenPush.contains(table.name)) throw FakeServerError(SyncErrorKind.table, 'Could not find a column of ${table.name}');
    final t = rows.putIfAbsent(table.name, () => {});
    for (final r in batch) {
      final why = _tooLong(table.name, r);
      if (why != null) throw FakeServerError(SyncErrorKind.row, 'new row violates check constraint "$why"');
    }
    // limit_rows: een trigger "before insert" per rij, dus ook bij een upsert
    var live = t.values.where((r) => oldLimitRows || r['deleted'] != 1).length;
    for (final r in batch) {
      final exists = t.containsKey(r[table.key]);
      if (exists && !oldLimitRows) continue;
      if (live >= maxRows) throw FakeServerError(SyncErrorKind.row, 'te veel rijen in ${table.name}');
      if (!exists) live++;
    }
    final kept = <String, int>{};
    for (final r in batch) {
      final key = r[table.key] as String;
      final old = t[key];
      if (old != null && insertOnly) continue;
      var at = r['updated_at'] as int;
      final now = nowMs;
      if (now != null && at > now + 5 * 60 * 1000) at = now + 5 * 60 * 1000;
      if (old != null && (old['updated_at'] as int) > at) continue;
      t[key] = {...r, 'updated_at': at, 'server_ts': _tick()};
      kept[key] = at;
    }
    return kept;
  }

  /// Hoe vaak er (ook vergeefs) opgehaald werd.
  int pullCalls = 0;

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    pullCalls++;
    if (offline) throw Exception('geen internet');
    if (brokenPull.contains(table.name)) throw FakeServerError(SyncErrorKind.table, 'ophalen van ${table.name} mislukt');
    final all =
        (rows[table.name]?.values ?? const <Map<String, Object?>>[])
            .where((r) => since == null || (r['server_ts'] as String).compareTo(since) > 0)
            .toList()
          ..sort((a, b) => (a['server_ts'] as String).compareTo(b['server_ts'] as String));
    await beforePullReturns?.call(table);
    return all.take(limit).toList();
  }

  @override
  Future<List<Map<String, Object?>>> fetch(SyncTable table, List<String> keys) async {
    if (offline) throw Exception('geen internet');
    return [for (final k in keys) ?rows[table.name]?[k]];
  }

  @override
  SyncErrorKind classify(Object error) => error is FakeServerError ? error.kind : SyncErrorKind.fatal;
}

const _banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90, 'potassium': 320});

void main() {
  late FakeServer server;
  late UserDb a, b;

  Future<SyncResult> sync(UserDb db) => SyncEngine(db, server, userId: 'user-1').run();

  setUp(() {
    server = FakeServer();
    a = UserDb(sqlite3.openInMemory());
    b = UserDb(sqlite3.openInMemory());
  });

  test('wat op toestel A komt, verschijnt op toestel B', () async {
    a.addEntry(day: '2026-10-16', meal: Meal.breakfast, food: _banana, grams: 120, quantity: 120);
    a.addBiometric(day: '2026-10-16', type: 'weight', value: 78.4);
    a.setNote('2026-10-16', 'Goed geslapen');
    a.setSetting('profile', {'weightKg': 78.4});
    final r = await sync(a);
    expect(r.pushed, 4);

    final rb = await sync(b);
    expect(rb.pulled, 4);
    expect(b.entriesFor('2026-10-16').single.name, 'Banana, raw');
    expect(b.note('2026-10-16'), 'Goed geslapen');
    expect(b.setting('profile')?['weightKg'], 78.4);
    expect(b.hasDirtyRows, isFalse, reason: 'binnengehaalde rijen moeten niet terug verstuurd worden');

    // Tweede keer: niets meer te doen
    final again = await sync(a);
    expect(again.pushed, 0);
    expect(again.pulled, 0);
  });

  test('wijzigen en verwijderen gaan mee', () async {
    final id = a.addEntry(day: '2026-10-16', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    await sync(a);
    await sync(b);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    b.updateEntry(id, meal: Meal.snacks, grams: 150, quantity: 150);
    await sync(b);
    await sync(a);
    expect(a.entriesFor('2026-10-16').single.grams, 150);
    expect(a.entriesFor('2026-10-16').single.meal, Meal.snacks);

    await Future<void>.delayed(const Duration(milliseconds: 2));
    a.deleteEntry(id);
    await sync(a);
    await sync(b);
    expect(b.entriesFor('2026-10-16'), isEmpty);
  });

  test('conflict: de laatste wijziging wint, op beide toestellen', () async {
    final id = a.addEntry(day: '2026-10-16', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    await sync(a);
    await sync(b);

    // Allebei offline gewijzigd; B iets later
    a.updateEntry(id, meal: Meal.lunch, grams: 111, quantity: 111);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    b.updateEntry(id, meal: Meal.lunch, grams: 222, quantity: 222);

    await sync(b);
    await sync(a); // A verstuurt zijn oudere versie: de server negeert ze, en A krijgt die van B
    await sync(b);
    expect(a.entriesFor('2026-10-16').single.grams, 222);
    expect(b.entriesFor('2026-10-16').single.grams, 222);
  });

  test('herhaalde items worden niet dubbel als twee toestellen ze aanmaken', () async {
    a.saveRepeat(
      mealIndex: 0,
      item: const ItemTemplate(foodRef: 'x', name: 'Vitamine D3', grams: 1, quantity: 1, per100g: {'vit_d': 2500}),
      weekdays: 0x7f,
      startDay: '2026-10-01',
    );
    await sync(a);
    await sync(b);
    a.applyRepeats('2026-10-16', DateTime(2026, 10, 16));
    b.applyRepeats('2026-10-16', DateTime(2026, 10, 16));
    await sync(a);
    await sync(b);
    await sync(a);
    expect(a.entriesFor('2026-10-16'), hasLength(1));
    expect(b.entriesFor('2026-10-16'), hasLength(1));
  });

  test('weergave en sessie blijven op het toestel', () async {
    a.setSetting('ui', {'theme': 'dark'});
    a.setSetting('_session', {'json': 'geheim'});
    await sync(a);
    expect(server.rows['settings'] ?? const {}, isEmpty);
    await sync(b);
    expect(b.setting('ui'), isNull);
  });

  test('grote hoeveelheden gaan in pakketten', () async {
    for (var i = 0; i < 1203; i++) {
      a.addBiometric(day: '2026-10-16', type: 'custom:stappen', value: i.toDouble());
    }
    server.pushes = 0;
    final r = await sync(a);
    expect(r.pushed, 1203);
    expect(server.pushes, 3);
    final rb = await sync(b);
    expect(rb.pulled, 1203);
    expect(b.biometricHistory('custom:stappen'), hasLength(1203));
  });

  test('uitloggen wist de gegevens, behalve de weergave', () async {
    a.addEntry(day: '2026-10-16', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    a.setSetting('ui', {'theme': 'light'});
    a.wipeUserData();
    expect(a.entriesFor('2026-10-16'), isEmpty);
    expect(a.setting('ui')?['theme'], 'light');
    expect(a.hasDirtyRows, isFalse);
  });

  test('bestaande gegevens van vóór de synchronisatie worden de eerste keer verstuurd', () async {
    // Na de migratie staat alles op "nog te versturen"
    a.addEntry(day: '2026-10-15', meal: Meal.dinner, food: _banana, grams: 80, quantity: 80);
    expect(a.hasDirtyRows, isTrue);
    await sync(a);
    expect(a.hasDirtyRows, isFalse);
  });
}
