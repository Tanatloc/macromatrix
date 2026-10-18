import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:voedingsapp/data/food.dart';
import 'package:voedingsapp/data/models.dart';
import 'package:voedingsapp/data/user_db.dart';
import 'package:voedingsapp/sync/sync_engine.dart';

/// Nagebootste server met dezelfde regels als de Supabase-trigger: oudere wijzigingen worden genegeerd,
/// elke opgeslagen rij krijgt een oplopende server_ts.
class FakeServer implements SyncRemote {
  final rows = <String, Map<String, Map<String, Object?>>>{};
  var _clock = DateTime.utc(2026, 1, 1);
  var pushes = 0;

  String _tick() => (_clock = _clock.add(const Duration(milliseconds: 1))).toIso8601String();

  @override
  Future<void> push(SyncTable table, List<Map<String, Object?>> batch) async {
    pushes++;
    final t = rows.putIfAbsent(table.name, () => {});
    for (final r in batch) {
      final key = r[table.key] as String;
      final old = t[key];
      if (old != null && (old['updated_at'] as int) > (r['updated_at'] as int)) continue;
      t[key] = {...r, 'server_ts': _tick()};
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(SyncTable table, String? since, int limit) async {
    final all =
        (rows[table.name]?.values ?? const <Map<String, Object?>>[])
            .where((r) => since == null || (r['server_ts'] as String).compareTo(since) > 0)
            .toList()
          ..sort((a, b) => (a['server_ts'] as String).compareTo(b['server_ts'] as String));
    return all.take(limit).toList();
  }
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
