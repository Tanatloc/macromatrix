// ignore_for_file: avoid_print
// Snelle controle tegen de echte Open Food Facts-API: dart run tool/off_smoke.dart
import 'package:voedingsapp/data/off_client.dart';

Future<void> main() async {
  final off = OffClient();
  for (final code in ['3017620422003', '5410188031072', '3168930010265']) {
    final f = await off.product(code);
    print(
      '$code -> ${f?.displayName} | kcal ${f?.per100g['energy']} | eiwit ${f?.per100g['protein']} | natrium ${f?.per100g['sodium']?.toStringAsFixed(0)} mg | ijzer ${f?.per100g['iron']} | porties ${f?.portions.map((p) => '${p.label}=${p.grams}g')}',
    );
  }
  final r = await off.search('skyr');
  print('zoeken "skyr": ${r.length} resultaten, bv. ${r.take(4).map((f) => f.displayName).join(' | ')}');
}
