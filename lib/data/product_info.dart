/// Alles wat de Scan-tab over een product toont: Nutri-Score, NOVA, additieven, allergenen, ingrediënten,
/// herkomst en een productscore.
///
/// Productscore: 60% voedingswaarde (Nutri-Score), 30% additieven, 10% biologisch. Een
/// additief met een hoog risico (EFSA: overschrijding van de aanvaardbare inname mogelijk) zet de score op
/// hoogstens 49.
library;

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../i18n.dart';
import 'food.dart';

/// Risico van een additief volgens de EFSA-beoordeling in Open Food Facts.
enum AdditiveRisk { none, unknown, moderate, high }

class Additive {
  const Additive(this.code, this._en, this._nl, this.risk, this.classKey, {this.anses = false});
  final String code;
  final String _en, _nl;
  final AdditiveRisk risk;
  final String classKey;

  /// Staat op de lijst van additieven die het Franse ANSES extra opvolgt.
  final bool anses;

  String get name => tr(_en, _nl);
  String get eNumber => code.toUpperCase();

  /// Wat de app toont: hoog/matig volgens EFSA, "beperkt" als ANSES het extra opvolgt, anders geen gekend risico.
  AdditiveLevel get level => switch (risk) {
    AdditiveRisk.high => AdditiveLevel.high,
    AdditiveRisk.moderate => AdditiveLevel.moderate,
    _ => anses ? AdditiveLevel.limited : AdditiveLevel.free,
  };
}

enum AdditiveLevel { free, limited, moderate, high }

/// De additievenlijst (assets/additives.json, uit de taxonomie van Open Food Facts).
class AdditiveCatalog {
  AdditiveCatalog._(this._items, this._classes);
  final Map<String, List<dynamic>> _items;
  final Map<String, List<dynamic>> _classes;

  static AdditiveCatalog? _instance;
  static Future<AdditiveCatalog> load() async {
    if (_instance != null) return _instance!;
    final j = jsonDecode(await rootBundle.loadString('assets/additives.json')) as Map<String, dynamic>;
    return _instance = AdditiveCatalog._((j['additives'] as Map).cast<String, List<dynamic>>(), (j['classes'] as Map).cast<String, List<dynamic>>());
  }

  Additive? lookup(String tag) {
    final code = tag.replaceFirst('en:', '').toLowerCase();
    final v = _items[code];
    if (v == null) return null;
    final risk = switch (v[2] as int) {
      0 => AdditiveRisk.none,
      2 => AdditiveRisk.moderate,
      3 => AdditiveRisk.high,
      _ => AdditiveRisk.unknown,
    };
    return Additive(code, v[0] as String, v[1] as String, risk, v[3] as String, anses: v[4] == 1);
  }

  String className(String key) {
    final c = _classes[key];
    if (c == null) return key.replaceAll('-', ' ');
    return tr(c[0] as String, c[1] as String);
  }
}

/// [mixed]: uit de EU en daarbuiten (bv. "ingrediënten uit de EU en niet-EU", NF-12).
enum Region { eu, us, other, mixed, unknown }

/// Herkomst: waar gemaakt (of waar de ingrediënten vandaan komen), of anders het land van de barcode.
class Origin {
  const Origin(this.region, this.place, this.basis);
  final Region region;

  /// Leesbaar land of plaats, bv. "Belgium" of "France, Spain".
  final String? place;

  /// made: productieplaats; ingredients: herkomst van de ingrediënten; barcode: alleen het barcodeland.
  final String basis;
}

const _eu = {
  'austria', 'belgium', 'bulgaria', 'croatia', 'cyprus', 'czech-republic', 'czechia', 'denmark', 'estonia', 'finland', //
  'france', 'germany', 'greece', 'hungary', 'ireland', 'italy', 'latvia', 'lithuania', 'luxembourg', 'malta', //
  'netherlands', 'poland', 'portugal', 'romania', 'slovakia', 'slovenia', 'spain', 'sweden', 'european-union', 'eu', //
  'belgique', 'belgie', 'belgië', 'nederland', 'frankrijk', 'duitsland', 'italie', 'italië', 'spanje', 'deutschland', //
};
const _us = {'united-states', 'usa', 'us', 'united-states-of-america', 'verenigde-staten'};

Region _regionOf(String tag) {
  final t = tag.replaceFirst(RegExp(r'^[a-z]{2}:'), '').toLowerCase().trim().replaceAll(' ', '-');
  if (_eu.contains(t)) return Region.eu;
  if (_us.contains(t)) return Region.us;
  return t.isEmpty ? Region.unknown : Region.other;
}

String _pretty(String tag) {
  final raw = tag.replaceFirst(RegExp(r'^[a-z]{2}:'), '').toLowerCase().trim().replaceAll(' ', '-');
  if (raw == 'european-union' || raw == 'eu') return tr('the EU', 'de EU');
  if (raw == 'non-european-union' || raw == 'non-eu') return tr('outside the EU', 'buiten de EU');
  final t = tag.replaceFirst(RegExp(r'^[a-z]{2}:'), '').replaceAll('-', ' ');
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

/// Land van de barcode (GS1-prefix). Zegt waar het merk geregistreerd is, niet waar het product gemaakt werd.
(Region, String)? barcodeCountry(String code) {
  if (code.length < 8) return null;
  final c = code.length == 12 ? '0$code' : code;
  final p3 = int.tryParse(c.substring(0, 3));
  if (p3 == null) return null;
  bool r(int a, int b) => p3 >= a && p3 <= b;
  if (r(0, 19) || r(30, 39) || r(60, 139)) return (Region.us, tr('United States or Canada', 'Verenigde Staten of Canada'));
  const eu = <(int, int, String, String)>[
    (300, 379, 'France', 'Frankrijk'),
    (380, 380, 'Bulgaria', 'Bulgarije'),
    (383, 383, 'Slovenia', 'Slovenië'),
    (385, 385, 'Croatia', 'Kroatië'),
    (400, 440, 'Germany', 'Duitsland'),
    (474, 474, 'Estonia', 'Estland'),
    (475, 475, 'Latvia', 'Letland'),
    (477, 477, 'Lithuania', 'Litouwen'),
    (520, 521, 'Greece', 'Griekenland'),
    (529, 529, 'Cyprus', 'Cyprus'),
    (535, 535, 'Malta', 'Malta'),
    (539, 539, 'Ireland', 'Ierland'),
    (540, 549, 'Belgium or Luxembourg', 'België of Luxemburg'),
    (560, 560, 'Portugal', 'Portugal'),
    (570, 579, 'Denmark', 'Denemarken'),
    (590, 590, 'Poland', 'Polen'),
    (594, 594, 'Romania', 'Roemenië'),
    (599, 599, 'Hungary', 'Hongarije'),
    (640, 649, 'Finland', 'Finland'),
    (730, 739, 'Sweden', 'Zweden'),
    (800, 839, 'Italy', 'Italië'),
    (840, 849, 'Spain', 'Spanje'),
    (858, 858, 'Slovakia', 'Slowakije'),
    (859, 859, 'Czechia', 'Tsjechië'),
    (870, 879, 'Netherlands', 'Nederland'),
    (900, 919, 'Austria', 'Oostenrijk'),
  ];
  for (final (a, b, en, nl) in eu) {
    if (r(a, b)) return (Region.eu, tr(en, nl));
  }
  if (r(200, 299) || r(977, 979)) return null;
  return (Region.other, tr('Outside the EU and US', 'Buiten de EU en de VS'));
}

class ProductInfo {
  const ProductInfo({
    required this.code,
    required this.name,
    this.brand,
    this.image,
    this.food,
    this.nutriscore,
    this.nova,
    this.additiveTags = const [],
    this.allergenTags = const [],
    this.traceTags = const [],
    this.ingredients,
    this.madeIn = const [],
    this.ingredientOrigins = const [],
    this.organic = false,
    this.source = 'off',
    this.categories = const [],
    this.countries = const [],
    this.offline = false,
  });

  final String code, name;
  final String? brand, image;

  /// Om aan het dagboek toe te voegen (null als er geen voedingswaarden zijn).
  final Food? food;

  /// a tot e, of null.
  final String? nutriscore;

  /// 1 (onbewerkt) tot 4 (ultrabewerkt), of null.
  final int? nova;
  final List<String> additiveTags, allergenTags, traceTags, madeIn, ingredientOrigins;
  final String? ingredients;
  final bool organic;

  /// off of usda.
  final String source;

  /// Categorieën van Open Food Facts, van algemeen naar specifiek (bv. en:beverages ... en:colas).
  final List<String> categories;

  /// Landen waar het verkocht wordt (countries_tags van Open Food Facts, bv. en:belgium).
  final List<String> countries;

  /// Te koop in België of Nederland: die gaan voor bij betere keuzes (NF-9).
  bool get soldNearby => countries.any((c) => c == 'en:belgium' || c == 'en:netherlands');

  /// Uit de bewaarde gegevens op dit toestel (geen internet).
  final bool offline;

  ProductInfo asOffline() => _copy(offline: true);

  /// Met je eigen product (van het etiket ingevuld) als de bron zelf geen voedingswaarden heeft.
  ProductInfo withFood(Food f) => _copy(food: f);

  ProductInfo _copy({Food? food, bool? offline}) => ProductInfo(
    code: code,
    name: name,
    brand: brand,
    image: image,
    food: food ?? this.food,
    nutriscore: nutriscore,
    nova: nova,
    additiveTags: additiveTags,
    allergenTags: allergenTags,
    traceTags: traceTags,
    ingredients: ingredients,
    madeIn: madeIn,
    ingredientOrigins: ingredientOrigins,
    organic: organic,
    source: source,
    categories: categories,
    countries: countries,
    offline: offline ?? this.offline,
  );

  factory ProductInfo.fromOff(Map<String, Object?> p, Food? food) {
    String? text(Object? v) {
      if (v is String && v.trim().isNotEmpty) return v.trim();
      if (v is List && v.isNotEmpty) return text(v.first);
      return null;
    }

    List<String> tags(Object? v) => [for (final x in (v as List?) ?? const []) '$x'];
    final grade = text(p['nutriscore_grade'])?.toLowerCase();
    return ProductInfo(
      code: '${p['code'] ?? ''}',
      name:
          food?.name ??
          text(p['product_name_nl']) ??
          text(p['product_name']) ??
          text(p['product_name_en']) ??
          tr('Unknown product', 'Onbekend product'),
      brand: text(p['brands'])?.split(',').first.trim(),
      image: text(p['image_front_small_url']) ?? text(p['image_front_url']),
      food: food,
      nutriscore: grade != null && RegExp(r'^[a-e]$').hasMatch(grade) ? grade : null,
      nova: (p['nova_group'] as num?)?.toInt(),
      additiveTags: tags(p['additives_tags']),
      allergenTags: tags(p['allergens_tags']),
      traceTags: tags(p['traces_tags']),
      ingredients: isNl
          ? text(p['ingredients_text_nl']) ?? text(p['ingredients_text']) ?? text(p['ingredients_text_en'])
          : text(p['ingredients_text_en']) ?? text(p['ingredients_text']) ?? text(p['ingredients_text_nl']),
      madeIn: [
        ...tags(p['manufacturing_places_tags']),
        if (tags(p['manufacturing_places_tags']).isEmpty && text(p['manufacturing_places']) != null) ...text(p['manufacturing_places'])!.split(','),
      ],
      ingredientOrigins: tags(p['origins_tags']),
      organic: tags(p['labels_tags']).any((l) => l.contains('organic') || l.contains('bio')),
      categories: [
        for (final c in tags(p['categories_tags']))
          if (c.startsWith('en:')) c,
      ],
      countries: tags(p['countries_tags']),
    );
  }

  /// Waar het product vandaan komt.
  Origin get origin {
    Origin? from(List<String> list, String basis) {
      final regions = {for (final t in list) _regionOf(t)}..remove(Region.unknown);
      if (regions.isEmpty) return null;
      // EU en daarbuiten samen is gemengd, niet "van buiten de EU" (NF-12)
      final region = regions.length == 1
          ? regions.first
          : (regions.contains(Region.us) ? Region.us : (regions.contains(Region.eu) ? Region.mixed : Region.other));
      return Origin(region, list.take(3).map(_pretty).join(', '), basis);
    }

    final made = from(madeIn, 'made') ?? from(ingredientOrigins, 'ingredients');
    if (made != null) return made;
    if (source == 'usda') return Origin(Region.us, tr('United States (USDA database)', 'Verenigde Staten (USDA-databank)'), 'source');
    final bc = barcodeCountry(code);
    return bc == null ? const Origin(Region.unknown, null, 'barcode') : Origin(bc.$1, bc.$2, 'barcode');
  }

  /// Weten we welke additieven erin zitten? Alleen met een ingrediëntenlijst of additieven van Open Food Facts; anders
  /// is "0 additieven" onbekend, niet "geen" (NF-4).
  bool get additivesKnown => source == 'off' && (ingredients != null || additiveTags.isNotEmpty);

  /// Additieven uit de lijst van Open Food Facts en uit de ingrediëntentekst (E-nummers en gangbare namen die OFF
  /// soms mist, NF-13), zonder dubbels: E322i valt weg als E322 er al staat.
  List<Additive> additives(AdditiveCatalog catalog) {
    final codes = {
      for (final t in additiveTags) t.replaceFirst('en:', '').toLowerCase(),
      ...additivesInText(ingredients ?? '').where((c) => catalog.lookup(c) != null),
    };
    return [
      for (final c in codes)
        if (!codes.contains(c.replaceFirst(RegExp(r'(?<=\d)[a-z]+$'), '')) || c.replaceFirst(RegExp(r'(?<=\d)[a-z]+$'), '') == c) ?catalog.lookup(c),
    ];
  }

  /// Productscore 0–100, of null als er te weinig gegevens zijn. Zonder ingrediëntenlijst zijn de additieven onbekend:
  /// dan telt dat deel niet als 100% maar wordt de score herschaald over wat we wel weten (zie [scoreIncomplete]).
  int? score(AdditiveCatalog catalog) {
    if (nutriscore == null) return null;
    final ns = const {'a': 100, 'b': 75, 'c': 50, 'd': 25, 'e': 0}[nutriscore]!;
    if (!additivesKnown) return ((0.6 * ns + (organic ? 10 : 0)) / 0.7).round().clamp(0, 100);
    final adds = additives(catalog);
    int n(AdditiveLevel l) => adds.where((a) => a.level == l).length;
    final high = n(AdditiveLevel.high);
    final addScore = (100 - 60 * high - 30 * n(AdditiveLevel.moderate) - 10 * n(AdditiveLevel.limited)).clamp(0, 100);
    var s = (0.6 * ns + 0.3 * addScore + (organic ? 10 : 0)).round();
    if (high > 0) s = s.clamp(0, 49);
    return s;
  }

  /// De score mist het deel over additieven: geen eindoordeel als "Uitstekend" (NF-4).
  bool get scoreIncomplete => nutriscore != null && !additivesKnown;
}

/// Gangbare additieven op naam, in het Engels, Nederlands en Frans (de talen van etiketten in België), voor als Open
/// Food Facts ze niet herkende (NF-13: E471 in een wafel, E341 in haverdrank).
final _additiveNames = <String, RegExp>{
  for (final e in {
    'e471': r'mono-?\s*(?:and|en|et|und|&|-)?\s*di-?\s*glyc[eé]rid\w*',
    'e341': r'(?:tri|mono|di)?calcium\s*phosphates?|(?:tri|mono|di)?calciumfosfa\w*|phosphates?\s+(?:tri|mono|di)?calciques?',
    // Ook samengesteld: sojalecithine, zonnebloemlecithine
    'e322': r'\w*lecithin\w*|\w*l[eé]cithines?',
    'e330': r'citric acid|citroenzuur|acide citrique',
    'e500': r'sodium (?:bi|hydrogen )?carbonates?|natrium(?:bi|waterstof)?carbona\w*|(?:bi)?carbonates? de sodium',
    'e503': r'ammonium (?:bi|hydrogen )?carbonates?|ammonium(?:bi|waterstof)?carbona\w*|(?:bi)?carbonates? d.ammonium',
    'e415': r'xanthan\w*|xanthaan\w*',
    'e412': r'guar\s*gum|guarpitmeel|guargom|gomme de guar',
    'e410': r'locust bean gum|carob (?:bean )?gum|johannesbroodpitmeel|farine de graines de caroube',
    'e440': r'pectins?|pectine',
    'e407': r'carrageena\w*|carragh[eé]nanes?',
    'e300': r'ascorbic acid|ascorbinezuur|acide ascorbique',
    'e202': r'potassium sorbate|kaliumsorbaat|sorbate de potassium',
    'e211': r'sodium benzoate|natriumbenzoaat|benzoate de sodium',
    'e951': r'aspartame?',
    'e955': r'sucralose',
    'e950': r'acesulfa(?:me|am)(?:[- ]?k(?:alium)?)?',
    'e418': r'gellan\w*',
  }.entries)
    e.key: RegExp('(?<![\\p{L}])(?:${e.value})(?![\\p{L}])', caseSensitive: false, unicode: true),
};

final _eNumber = RegExp(r'\bE\s?-?(\d{3,4}[a-z]{0,3})\b', caseSensitive: false);

/// Additieven (e322, e471, ...) die in een ingrediëntentekst staan: als E-nummer of met een gangbare naam. De codes
/// moeten nog in de additievenlijst staan ([AdditiveCatalog.lookup]).
Set<String> additivesInText(String text) {
  if (text.trim().isEmpty) return const {};
  return {
    for (final m in _eNumber.allMatches(text)) 'e${m[1]!.toLowerCase()}',
    for (final e in _additiveNames.entries)
      if (e.value.hasMatch(text)) e.key,
  };
}

/// Velden die de Scan-tab bij Open Food Facts opvraagt.
const productInfoFields =
    'code,product_name,product_name_nl,product_name_en,generic_name,brands,quantity,serving_size,serving_quantity,nutriments,categories_properties,'
    'image_front_small_url,image_front_url,nutriscore_grade,nova_group,additives_tags,allergens_tags,traces_tags,ingredients_text,ingredients_text_nl,'
    'ingredients_text_en,manufacturing_places,manufacturing_places_tags,origins_tags,labels_tags,categories_tags,countries_tags';
