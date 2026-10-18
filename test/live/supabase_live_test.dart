// Test tegen een echt Supabase-project. Draait alleen met deze omgevingsvariabelen (anders overgeslagen):
//   SUPABASE_URL, SUPABASE_ANON_KEY, LIVE_EMAIL_A, LIVE_OTP_A, LIVE_EMAIL_B, LIVE_OTP_B
// De codes maak je zonder mail met de admin-API (generate_link, type magiclink); zie supabase/README.md.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:supabase/supabase.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/sync_engine.dart';

void main() {
  final env = Platform.environment;
  final url = env['SUPABASE_URL'] ?? '', key = env['SUPABASE_ANON_KEY'] ?? '';
  final skip = url.isEmpty || key.isEmpty || (env['LIVE_OTP_A'] ?? '').isEmpty ? 'geen live-gegevens' : null;
  const banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90});

  Future<(SupabaseClient, String)> login(String email, String otp) async {
    final c = SupabaseClient(url, key, authOptions: const AuthClientOptions(authFlowType: AuthFlowType.implicit));
    final r = await c.auth.verifyOTP(type: OtpType.email, email: email, token: otp);
    return (c, r.user!.id);
  }

  test('twee toestellen van A synchroniseren; B ziet niets van A; account verwijderen', skip: skip, () async {
    final (ca, ua) = await login(env['LIVE_EMAIL_A']!, env['LIVE_OTP_A']!);
    final (cb, ub) = await login(env['LIVE_EMAIL_B']!, env['LIVE_OTP_B']!);
    final a1 = UserDb(sqlite3.openInMemory()), a2 = UserDb(sqlite3.openInMemory()), b = UserDb(sqlite3.openInMemory());
    Future<SyncResult> sync(UserDb db, SupabaseClient c, String uid) => SyncEngine(db, SupabaseRemote(c, uid), userId: uid).run();

    // Toestel 1 van A logt iets, toestel 2 krijgt het
    final id = a1.addEntry(day: '2026-10-16', meal: Meal.breakfast, food: banana, grams: 120, quantity: 120);
    a1.setNote('2026-10-16', 'live test');
    a1.setSetting('profile', {'weightKg': 77.7});
    a1.startFast(DateTime(2026, 10, 16, 8), 16);
    expect((await sync(a1, ca, ua)).pushed, 4);
    final r2 = await sync(a2, ca, ua);
    expect(r2.pulled, 4);
    expect(a2.entriesFor('2026-10-16').single.grams, 120);
    expect(a2.note('2026-10-16'), 'live test');
    expect(a2.currentFast()?.goalHours, 16);

    // Wijzigen op toestel 2, verwijderen op toestel 1
    await Future<void>.delayed(const Duration(milliseconds: 5));
    a2.updateEntry(id, meal: Meal.lunch, grams: 200, quantity: 200);
    await sync(a2, ca, ua);
    await sync(a1, ca, ua);
    expect(a1.entriesFor('2026-10-16').single.grams, 200);

    // Een oudere versie overschrijft de nieuwere niet (trigger op de server)
    await ca.from('diary').upsert({
      'id': id,
      'user_id': ua,
      'day': '2026-10-16',
      'meal': 0,
      'food_ref': 'x',
      'name': 'oud',
      'grams': 1,
      'quantity': 1,
      'nutrients': '{}',
      'created_at': 1,
      'updated_at': 1,
      'deleted': 0,
    }, onConflict: 'user_id,id');
    final server = await ca.from('diary').select('grams, name').eq('id', id).single();
    expect(server['grams'], 200);

    // B ziet niets van A en kan niets van A schrijven
    expect((await sync(b, cb, ub)).pulled, 0);
    expect(await cb.from('diary').select(), isEmpty);
    await expectLater(
      cb.from('diary').insert({
        'id': 'x',
        'user_id': ua,
        'day': 'd',
        'meal': 0,
        'food_ref': 'x',
        'name': 'x',
        'grams': 1,
        'quantity': 1,
        'nutrients': '{}',
        'created_at': 1,
        'updated_at': 1,
      }),
      throwsA(isA<PostgrestException>()),
    );

    // Account A verwijderen: alles weg
    await ca.rpc('delete_account');
    for (final c in [ca, cb]) {
      c.dispose();
    }
  });
}
