// Live meldingen tegen het echte project: wat toestel A logt, komt vanzelf op toestel B. Alleen met:
//   flutter test --dart-define-from-file=supabase.json test/live/realtime_live_test.dart
// en LIVE_EMAIL + LIVE_PASSWORD van een bevestigde (tijdelijke) testgebruiker.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/account.dart';

void main() {
  final env = Platform.environment;
  final skip = !Account.configured || (env['LIVE_PASSWORD'] ?? '').isEmpty ? 'geen live-gegevens' : null;

  test('een wijziging op toestel A verschijnt vanzelf op toestel B', skip: skip, timeout: const Timeout(Duration(minutes: 2)), () async {
    final dbA = UserDb(sqlite3.openInMemory()), dbB = UserDb(sqlite3.openInMemory());
    var reloadsB = 0;
    final a = Account(dbA, onRemoteChanges: () {});
    final b = Account(dbB, onRemoteChanges: () => reloadsB++);
    await a.init();
    await b.init();
    await a.signIn(env['LIVE_EMAIL']!, env['LIVE_PASSWORD']!);
    await b.signIn(env['LIVE_EMAIL']!, env['LIVE_PASSWORD']!);
    await Future<void>.delayed(const Duration(seconds: 3)); // live verbinding opzetten

    final started = DateTime.now();
    dbA.addEntry(
      day: '2026-10-16',
      meal: Meal.lunch,
      food: const Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90}),
      grams: 120,
      quantity: 120,
    );
    // A verstuurt na 3 seconden; B moet het daarna binnen enkele seconden hebben, zonder zelf te synchroniseren
    while (dbB.entriesFor('2026-10-16').isEmpty && DateTime.now().difference(started) < const Duration(seconds: 40)) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final took = DateTime.now().difference(started);
    // ignore: avoid_print
    print('Op toestel B na ${took.inMilliseconds} ms (waarvan 3 s wachttijd op A)');
    expect(dbB.entriesFor('2026-10-16'), hasLength(1));
    // De rij staat er al terwijl B nog de andere tabellen afloopt; daarna herlaadt de app
    for (var i = 0; i < 20 && reloadsB == 0; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    expect(reloadsB, greaterThan(0));
    expect(took, lessThan(const Duration(seconds: 15)));

    await a.deleteAccount();
    a.dispose();
    b.dispose();
  });
}
