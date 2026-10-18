// ignore_for_file: avoid_print
// Live controle: merkproducten uit Open Food Facts aanvullen. flutter test tool/off_enrich_probe_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/off_client.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/state/app_state.dart';

void main() {
  test('skyr en andere producten', () async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
      off: OffClient(),
    );
    for (final code in ['8710624358174', '5690845001987', '3017620422003', '5410188031072']) {
      final f = await s.lookupBarcode(code);
      if (f == null) {
        print('$code: niet gevonden');
        continue;
      }
      print(
        '${f.displayName} -> basis ${f.proxyRef} | calcium ${f.per100g['calcium']?.toStringAsFixed(0)} mg | '
        'B12 ${f.per100g['b12']?.toStringAsFixed(2)} | leucine ${f.per100g['leucine']?.toStringAsFixed(2)} | '
        '${f.per100g.length} stoffen, ${f.estimated.length} geschat',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
