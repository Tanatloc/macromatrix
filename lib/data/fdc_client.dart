/// USDA FoodData Central, Branded Foods: reservebron voor merkproducten die Open Food Facts niet kent (vooral
/// Amerikaanse producten). De app vraagt het via de eigen server (/api/fdc/barcode, een Cloudflare-functie) zodat
/// de API-sleutel nooit in de app zit. Publiek domein.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../i18n.dart';
import '../nutrition/values.dart';
import '../platform/platform.dart';
import 'food.dart';
import 'product_info.dart';

/// FDC-nutriënt-id -> (sleutel in de app, eenheid van de app). Zelfde keuze als tool/build_foods.py.
const _ids = <int, (String, String)>{
  1008: ('energy', 'KCAL'),
  1003: ('protein', 'G'),
  1079: ('fiber', 'G'),
  2000: ('sugars', 'G'),
  1009: ('starch', 'G'),
  1004: ('fat', 'G'),
  1258: ('sfa', 'G'),
  1292: ('mufa', 'G'),
  1293: ('pufa', 'G'),
  1257: ('trans', 'G'),
  1253: ('cholesterol', 'MG'),
  1018: ('alcohol', 'G'),
  1057: ('caffeine', 'MG'),
  1106: ('vit_a', 'UG'),
  1105: ('retinol', 'UG'),
  1107: ('beta_carotene', 'UG'),
  1162: ('vit_c', 'MG'),
  1114: ('vit_d', 'UG'),
  1109: ('vit_e', 'MG'),
  1185: ('vit_k', 'UG'),
  1165: ('b1', 'MG'),
  1166: ('b2', 'MG'),
  1167: ('b3', 'MG'),
  1170: ('b5', 'MG'),
  1175: ('b6', 'MG'),
  1176: ('b7', 'UG'),
  1177: ('b9', 'UG'),
  1178: ('b12', 'UG'),
  1180: ('choline', 'MG'),
  1087: ('calcium', 'MG'),
  1089: ('iron', 'MG'),
  1090: ('magnesium', 'MG'),
  1091: ('phosphorus', 'MG'),
  1092: ('potassium', 'MG'),
  1093: ('sodium', 'MG'),
  1095: ('zinc', 'MG'),
  1098: ('copper', 'MG'),
  1101: ('manganese', 'MG'),
  1103: ('selenium', 'UG'),
  1100: ('iodine', 'UG'),
};

const _factor = <(String, String), double>{('UG', 'MG'): 0.001, ('MG', 'G'): 0.001, ('G', 'MG'): 1000, ('MG', 'UG'): 1000, ('KJ', 'KCAL'): 1 / 4.184};

/// Voedingswaarden per 100 g uit de compacte lijst [id, eenheid, waarde] van /api/fdc/barcode.
NutrientMap mapFdcNutrients(List<dynamic> list) {
  final raw = <int, (String, double)>{for (final n in list) (n as List)[0] as int: ((n[1] as String).toUpperCase(), (n[2] as num).toDouble())};
  final out = <String, double>{};
  for (final MapEntry(key: id, value: (key, unit)) in _ids.entries) {
    final v = raw[id];
    if (v == null) continue;
    final f = v.$1 == unit ? 1.0 : _factor[(v.$1, unit)];
    if (f != null) out[key] = v.$2 * f;
  }
  // Energie soms alleen in kJ; vitamine D soms alleen in IE (1 µg = 40 IE)
  if (!out.containsKey('energy') && raw[1062] != null) out['energy'] = raw[1062]!.$2 / 4.184;
  if (!out.containsKey('vit_d') && raw[1110] != null) out['vit_d'] = raw[1110]!.$2 / 40;
  // USDA geeft vitamine A als RAE (bètacaroteen / 12); de app rekent in RE (bètacaroteen / 6) zoals de EFSA-doelen
  if (out['vit_a'] case final rae? when out['beta_carotene'] != null) out['vit_a'] = rae + out['beta_carotene']! / 12;
  // Koolhydraten "by difference" bevatten vezels; Europese etiketten niet
  final diff = raw[1005]?.$2;
  if (diff != null) out['carbs'] = (diff - (out['fiber'] ?? 0)).clamp(0, 100).toDouble();
  return withDerived(out);
}

/// Een antwoord van /api/fdc/barcode omzetten naar productinfo (met een [Food] om te loggen).
ProductInfo? productFromFdc(Map<String, Object?> j) {
  if (j['found'] != true) return null;
  final code = '${j['code']}';
  final per100g = mapFdcNutrients((j['nutrients'] as List?) ?? const []);
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
  final name = _title(text(j['name']) ?? tr('Unknown product', 'Onbekend product'));
  final brand = text(j['brand']) == null ? null : _title(text(j['brand'])!);
  final serving = (j['serving'] as num?)?.toDouble();
  final unit = '${j['servingUnit'] ?? ''}'.toUpperCase();
  final household = text(j['household']);
  final ingredients = text(j['ingredients']);
  final food = per100g.containsKey('energy')
      ? Food(
          ref: 'fdc:$code',
          name: name,
          brand: brand,
          barcode: code,
          source: FoodSource.usda,
          per100g: per100g,
          category: text(j['category']),
          portions: [
            if (serving != null && serving > 0 && (unit == 'G' || unit == 'GRM' || unit == 'ML' || unit == 'MLT'))
              Portion(household == null ? tr('1 serving', '1 portie') : tr('1 serving ($household)', '1 portie ($household)'), serving),
          ],
          ingredients: ingredients,
        )
      : null;
  return ProductInfo(code: code, name: name, brand: brand, food: food, ingredients: ingredients, source: 'usda');
}

/// USDA-namen staan vaak in hoofdletters: "CHEERIOS CEREAL" -> "Cheerios cereal".
String _title(String s) {
  if (s != s.toUpperCase()) return s;
  final lower = s.toLowerCase();
  return lower[0].toUpperCase() + lower.substring(1);
}

class FdcClient {
  FdcClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  /// Product op barcode, of null als USDA het niet kent of niet bereikbaar is (het is maar een reservebron).
  Future<ProductInfo?> product(String barcode) async {
    final j = await raw(barcode);
    return j == null ? null : productFromFdc(j);
  }

  /// Ruw antwoord van /api/fdc/barcode als het product gevonden werd, anders null.
  Future<Map<String, Object?>?> raw(String barcode) async {
    final params = {'code': barcode};
    final uri = isWeb
        ? Uri.base.resolve('/api/fdc/barcode').replace(queryParameters: params)
        : Uri.https('macromatrix.eu', '/api/fdc/barcode', params);
    try {
      final res = await _http.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) return null;
      final j = (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, Object?>();
      return j['found'] == true ? j : null;
    } on Exception {
      return null;
    }
  }
}
