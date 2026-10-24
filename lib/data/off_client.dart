/// Open Food Facts: open database met merkproducten (licentie ODbL, naamsvermelding verplicht).
///
/// - Product op barcode: API v2 (`https://world.openfoodfacts.org/api/v2/product/<barcode>`)
/// - Zoeken op naam: Search-a-licious (https://search.openfoodfacts.org/search)
///
/// OFF vraagt een eigen User-Agent en heeft limieten (ongeveer 100 productopvragingen en 10 zoekopdrachten
/// per minuut). Zoeken gebeurt daarom alleen op verzoek, niet bij elke toetsaanslag.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../platform/platform.dart';

import '../nutrition/values.dart';
import 'food.dart';
import 'product_info.dart';
import '../i18n.dart';

const _userAgent = 'MacroMatrix/0.1 (https://macromatrix.eu)';
const _fields =
    'code,product_name,product_name_nl,product_name_en,generic_name,brands,quantity,serving_size,serving_quantity,nutriments,categories_properties,allergens_tags,traces_tags,ingredients_text,ingredients_text_nl,ingredients_text_en,nova_group';

/// OFF-veld -> (sleutel in de app, factor van de OFF-eenheid naar de app-eenheid).
/// OFF bewaart massa's in gram per 100 g; energie in kcal.
const _map = <String, (String, double)>{
  'energy-kcal_100g': ('energy', 1),
  'proteins_100g': ('protein', 1),
  'carbohydrates_100g': ('carbs', 1),
  'fiber_100g': ('fiber', 1),
  'sugars_100g': ('sugars', 1),
  'starch_100g': ('starch', 1),
  'fat_100g': ('fat', 1),
  'saturated-fat_100g': ('sfa', 1),
  'monounsaturated-fat_100g': ('mufa', 1),
  'polyunsaturated-fat_100g': ('pufa', 1),
  'trans-fat_100g': ('trans', 1),
  'cholesterol_100g': ('cholesterol', 1000),
  'omega-3-fat_100g': ('omega3', 1),
  'alpha-linolenic-acid_100g': ('ala', 1),
  'eicosapentaenoic-acid_100g': ('epa', 1),
  'docosahexaenoic-acid_100g': ('dha', 1),
  'omega-6-fat_100g': ('omega6', 1),
  'linoleic-acid_100g': ('la', 1),
  'arachidonic-acid_100g': ('aa', 1),
  'caffeine_100g': ('caffeine', 1000),
  'vitamin-a_100g': ('vit_a', 1e6),
  'beta-carotene_100g': ('beta_carotene', 1e6),
  'vitamin-c_100g': ('vit_c', 1000),
  'vitamin-d_100g': ('vit_d', 1e6),
  'vitamin-e_100g': ('vit_e', 1000),
  'vitamin-k_100g': ('vit_k', 1e6),
  'vitamin-b1_100g': ('b1', 1000),
  'vitamin-b2_100g': ('b2', 1000),
  'vitamin-pp_100g': ('b3', 1000),
  'pantothenic-acid_100g': ('b5', 1000),
  'vitamin-b6_100g': ('b6', 1000),
  'biotin_100g': ('b7', 1e6),
  'vitamin-b9_100g': ('b9', 1e6),
  'vitamin-b12_100g': ('b12', 1e6),
  'choline_100g': ('choline', 1000),
  'calcium_100g': ('calcium', 1000),
  'chromium_100g': ('chromium', 1e6),
  'copper_100g': ('copper', 1000),
  'fluoride_100g': ('fluoride', 1000),
  'iodine_100g': ('iodine', 1e6),
  'iron_100g': ('iron', 1000),
  'magnesium_100g': ('magnesium', 1000),
  'manganese_100g': ('manganese', 1000),
  'molybdenum_100g': ('molybdenum', 1e6),
  'phosphorus_100g': ('phosphorus', 1000),
  'potassium_100g': ('potassium', 1000),
  'selenium_100g': ('selenium', 1e6),
  'sodium_100g': ('sodium', 1000),
  'zinc_100g': ('zinc', 1000),
};

/// Zet de "nutriments" van OFF om naar voedingswaarden per 100 g in de eenheden van de app.
NutrientMap mapOffNutriments(Map<String, Object?> n) {
  final out = <String, double>{};
  for (final MapEntry(key: field, value: (key, factor)) in _map.entries) {
    final v = n[field];
    if (v is num) out[key] = v.toDouble() * factor;
  }
  // Energie soms alleen in kJ
  if (!out.containsKey('energy')) {
    final kj = n['energy-kj_100g'] ?? n['energy_100g'];
    if (kj is num) out['energy'] = kj / 4.184;
  }
  // Energie nakijken tegen de macro's: in OFF staat soms kJ in het kcal-veld (bv. gehakt met "947 kcal")
  final fixed = checkEnergy(out['energy'], protein: out['protein'], carbs: out['carbs'], fat: out['fat'], fiber: out['fiber']);
  if (fixed != null) out['energy'] = fixed;
  // Natrium ontbreekt soms terwijl zout er wel staat (zout = natrium x 2,5)
  if (!out.containsKey('sodium') && n['salt_100g'] is num) {
    out['sodium'] = (n['salt_100g'] as num) / 2.5 * 1000;
  }
  // Alcohol staat in OFF als % vol; omrekenen naar gram per 100 g (dichtheid ethanol 0,789)
  if (n['alcohol_100g'] is num) out['alcohol'] = (n['alcohol_100g'] as num) * 0.789;
  return withDerived(out);
}

/// Energie die niet past bij eiwit, koolhydraten en vet verbeteren. Geeft null als ze klopt (of niet te controleren
/// is). Past de waarde gedeeld door 4,184 wel (kJ in het kcal-veld), dan die; anders de berekening uit de macro's.
double? checkEnergy(double? kcal, {double? protein, double? carbs, double? fat, double? fiber}) {
  if (kcal == null || protein == null || fat == null) return null;
  final calc = 4 * protein + 4 * (carbs ?? 0) + 9 * fat + 2 * (fiber ?? 0);
  if (calc < 20) return null;
  bool near(double v) => (v - calc).abs() <= calc * 0.25 + 15;
  if (near(kcal)) return null;
  if (near(kcal / 4.184)) return kcal / 4.184;
  return calc;
}

/// Een OFF-product omzetten naar een [Food]. Geeft null als er geen bruikbare voedingswaarden zijn.
Food? foodFromOff(Map<String, Object?> p) {
  final code = '${p['code'] ?? ''}';
  final nutriments = (p['nutriments'] as Map?)?.cast<String, Object?>() ?? const {};
  final per100g = mapOffNutriments(nutriments);
  if (code.isEmpty || !per100g.containsKey('energy')) return null;

  String? text(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v.trim();
    if (v is List && v.isNotEmpty) return text(v.first);
    return null;
  }

  final name =
      text(p['product_name_nl']) ??
      text(p['product_name']) ??
      text(p['product_name_en']) ??
      text(p['generic_name']) ??
      tr('Unknown product', 'Onbekend product');
  final brands = text(p['brands'])?.split(',').first.trim();
  // OFF koppelt producten aan een CIQUAL-voedingsmiddel (Agribalyse-code): bv. skyr -> "Yogurt, ..., plain"
  final props = (p['categories_properties'] as Map?)?.cast<String, Object?>() ?? const {};
  final ciqual = props['agribalyse_food_code:en'] ?? props['agribalyse_proxy_food_code:en'];
  final serving = (p['serving_quantity'] is num) ? (p['serving_quantity'] as num).toDouble() : double.tryParse('${p['serving_quantity']}');
  final servingLabel = text(p['serving_size']);
  return Food(
    ref: 'off:$code',
    name: name,
    brand: brands,
    barcode: code,
    source: FoodSource.off,
    per100g: per100g,
    portions: [
      if (serving != null && serving > 0)
        Portion(servingLabel == null ? tr('1 serving', '1 portie') : tr('1 serving ($servingLabel)', '1 portie ($servingLabel)'), serving),
    ],
    proxyRef: ciqual == null ? null : 'ciqual:$ciqual',
    allergenTags: [for (final x in (p['allergens_tags'] as List?) ?? const []) '$x'],
    traceTags: [for (final x in (p['traces_tags'] as List?) ?? const []) '$x'],
    ingredients: text(p['ingredients_text_nl']) ?? text(p['ingredients_text']) ?? text(p['ingredients_text_en']),
    nova: (p['nova_group'] as num?)?.toInt(),
  );
}

class OffException implements Exception {
  OffException(this.message);
  final String message;
  @override
  String toString() => message;
}

class OffClient {
  OffClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  Future<Map<String, Object?>> _get(Uri uri) async {
    final http.Response res;
    try {
      // Een browser stuurt zelf zijn User-Agent; een eigen header zou een extra CORS-controle uitlokken
      res = await _http
          .get(uri, headers: isWeb ? const {} : {'User-Agent': _userAgent, 'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw OffException(
        tr('No connection to Open Food Facts. Check your internet.', 'Geen verbinding met Open Food Facts. Controleer je internet.'),
      );
    }
    if (res.statusCode == 404) return const {};
    if (res.statusCode == 429) {
      throw OffException(tr('Too many lookups. Try again in a minute.', 'Even te veel opzoekingen. Probeer het binnen een minuut opnieuw.'));
    }
    if (res.statusCode != 200) {
      throw OffException(
        tr('Open Food Facts is temporarily unavailable (${res.statusCode}).', 'Open Food Facts is tijdelijk niet bereikbaar (${res.statusCode}).'),
      );
    }
    try {
      return (jsonDecode(utf8.decode(res.bodyBytes)) as Map).cast<String, Object?>();
    } on FormatException {
      throw OffException(tr('Open Food Facts is temporarily unavailable.', 'Open Food Facts is tijdelijk niet bereikbaar.'));
    }
  }

  /// Product opzoeken op barcode. Geeft null als het product niet bestaat of geen voedingswaarden heeft.
  Future<Food?> product(String barcode) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode', {'fields': _fields});
    final data = await _get(uri);
    final product = (data['product'] as Map?)?.cast<String, Object?>();
    if (product == null) return null;
    return foodFromOff({...product, 'code': product['code'] ?? barcode});
  }

  /// Alles voor de Scan-tab: voedingswaarden plus Nutri-Score, NOVA, additieven, allergenen en herkomst.
  /// Geeft null als Open Food Facts het product niet kent.
  Future<ProductInfo?> productInfo(String barcode) async {
    final p = await productInfoRaw(barcode);
    return p == null ? null : ProductInfo.fromOff(p, foodFromOff(p));
  }

  /// Ruwe productgegevens voor de Scan-tab (om ook offline te bewaren), of null.
  Future<Map<String, Object?>?> productInfoRaw(String barcode) async {
    final uri = Uri.https('world.openfoodfacts.org', '/api/v2/product/$barcode', {'fields': productInfoFields});
    final data = await _get(uri);
    final product = (data['product'] as Map?)?.cast<String, Object?>();
    return product == null ? null : {...product, 'code': product['code'] ?? barcode};
  }

  /// Zoeken op naam (Belgische en Nederlandse producten eerst).
  Future<List<Food>> search(String query, {int pageSize = 30}) async {
    final params = {'q': query, 'page_size': '$pageSize', 'fields': _fields, 'langs': 'nl,fr,en'};
    // De zoekdienst van OFF staat geen verzoeken uit de browser toe: daar via de eigen server (nginx-proxy)
    final uri = isWeb
        ? Uri.base.resolve('/api/off/search').replace(queryParameters: params)
        : Uri.https('search.openfoodfacts.org', '/search', params);
    final data = await _get(uri);
    final hits = (data['hits'] as List?) ?? const [];
    return [for (final h in hits) ?foodFromOff((h as Map).cast<String, Object?>())];
  }

  /// Ruwe zoekopdracht met de zoeksyntax van Search-a-licious (bv. `categories_tags:"en:colas"`).
  Future<List<Map<String, Object?>>> _searchRaw(String q, {String fields = 'code,nutriscore_grade', int pageSize = 20}) async {
    final params = {'q': q, 'page_size': '$pageSize', 'fields': fields, 'sort_by': '-unique_scans_n'};
    final uri = isWeb
        ? Uri.base.resolve('/api/off/search').replace(queryParameters: params)
        : Uri.https('search.openfoodfacts.org', '/search', params);
    final data = await _get(uri);
    return [for (final h in (data['hits'] as List?) ?? const []) (h as Map).cast<String, Object?>()];
  }

  /// Betere keuzes: populaire producten uit dezelfde (zo specifiek mogelijke) categorie met een betere
  /// Nutri-Score, eerst uit België, Nederland en Frankrijk. Geeft de barcodes, beste kandidaten eerst.
  Future<List<String>> betterCandidates(ProductInfo p, {int max = 6}) async {
    final ns = p.nutriscore;
    if (p.categories.isEmpty) return const [];
    final grades = [
      for (final g in 'abcde'.split(''))
        if (ns == null ? g.compareTo('c') < 0 : g.compareTo(ns) < 0) g,
    ];
    if (grades.isEmpty) grades.add('a');
    final gradeQ = 'nutrition_grades:(${grades.join(' OR ')})';
    const near = 'countries_tags:("en:belgium" OR "en:netherlands" OR "en:france")';
    final out = <String>[];
    // Van specifiek naar iets algemener (hoogstens twee niveaus terug)
    for (final cat in p.categories.reversed.take(3)) {
      for (final region in [near, null]) {
        // Weinig additieven (de index kent alleen het aantal); de echte score volgt na het ophalen
        final q = ['categories_tags:"$cat"', gradeQ, 'additives_n:[0 TO 2]', ?region].join(' AND ');
        for (final h in await _searchRaw(q)) {
          final code = '${h['code'] ?? ''}';
          if (code.isNotEmpty && code != p.code && !out.contains(code)) out.add(code);
        }
        if (out.length >= max) return out.take(max).toList();
      }
    }
    return out;
  }
}

/// Is deze tekst een barcode (EAN-8, EAN-13, UPC-A of GTIN-14)?
bool looksLikeBarcode(String s) => RegExp(r'^\d{8}$|^\d{12,14}$').hasMatch(s.trim());
