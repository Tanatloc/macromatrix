import 'dart:convert';

import '../i18n.dart';
import '../nutrition/values.dart';

/// Herkomst van een voedingsmiddel. De volgorde bepaalt de voorkeur bij zoeken: Europese bronnen eerst.
enum FoodSource {
  ciqual('CIQUAL', ('France', 'Frankrijk'), 'ANSES-CIQUAL 2025', european: true),
  slv('Livsmedelsverket', ('Sweden', 'Zweden'), 'Livsmedelsverket, Livsmedelsdatabasen', european: true),
  mvt('Matvaretabellen', ('Norway', 'Noorwegen'), 'Matvaretabellen, Mattilsynet', european: true),
  frida('Frida', ('Denmark', 'Denemarken'), 'Frida, DTU Fødevareinstituttet', european: true),
  cofid('CoFID', ('UK', 'VK'), "McCance and Widdowson's Composition of Foods Integrated Dataset", european: true),
  usda('USDA', ('US', 'VS'), 'USDA FoodData Central'),
  off('Open Food Facts', null, 'Open Food Facts (ODbL)'),
  custom('Eigen product', null, 'Eigen product'),
  recipe('Recept', null, 'Eigen recept');

  const FoodSource(this._label, this._country, this.citation, {this.european = false});

  final String _label;
  final (String, String)? _country;

  /// Korte naam in lijsten.
  String get label => switch (this) {
    custom => tr('Own product', 'Eigen product'),
    recipe => tr('Recipe', 'Recept'),
    _ => _label,
  };

  /// Land van de databank, of null voor merkproducten en eigen producten.
  String? get country => _country == null ? null : tr(_country.$1, _country.$2);

  /// Bronvermelding zoals de licentie die vraagt.
  final String citation;
  final bool european;

  String get labelWithCountry => country == null ? label : '$label ($country)';

  /// Voorkeur als hoofdbron bij hetzelfde basisproduct uit meerdere databanken (lager = eerst; zoekvak, Snel loggen
  /// en het Orakel tonen dan die bron vooraan). Eerst de volledige Europese tabellen (CIQUAL, Frida, Matvaretabellen,
  /// Livsmedelsverket), dan CoFID: koolhydraten staan daar als monosacharide-equivalenten (omgerekend, maar het blijft
  /// een andere analyse: havermout 64 g tegenover 58 g elders) en B12 in melk ligt dubbel zo hoog als elders (NF-1,
  /// NF-16). USDA als laatste: Amerikaanse producten en verrijking. Merk- en eigen producten doen hier niet mee.
  int get priority => switch (this) {
    ciqual || frida || mvt || slv => 0,
    cofid => 1,
    usda => 2,
    _ => 3,
  };

  /// Bron uit de kolom "source" van de ingebouwde database (usda_sr en usda_fnd zijn allebei USDA).
  static FoodSource fromDb(String s) => s.startsWith('usda') ? usda : FoodSource.values.byName(s);
}

/// Een portie die de gebruiker kan kiezen, bv. "1 cup (240 g)" of "1 portie (30 g)".
class Portion {
  const Portion(this.label, this.grams);
  final String label;
  final double grams;

  Map<String, Object> toJson() => {'label': label, 'grams': grams};
  factory Portion.fromJson(Map<String, Object?> j) => Portion(j['label'] as String, (j['grams'] as num).toDouble());
}

/// Label van een product uit de ingebouwde databank (tool/food_labels.jsonl): wat het is, los van de naam.
class FoodLabel {
  const FoodLabel({
    required this.food,
    required this.group,
    required this.part,
    required this.kind,
    required this.state,
    this.flags = const [],
    this.dish = false,
    this.spread = 1,
  });

  factory FoodLabel.fromJson(Map<String, Object?> j) => FoodLabel(
    food: j['f'] as String,
    group: j['g'] as String,
    part: j['p'] as String,
    kind: j['k'] as String,
    state: j['c'] as String,
    flags: [...?(j['fl'] as List?)?.cast<String>()],
    dish: j['d'] == 1,
    spread: (j['n'] as num?)?.toInt() ?? 1,
  );

  /// Het voedingsmiddel zelf, bv. `spinach`, `egg`, `gouda cheese`.
  final String food;

  /// Voedingsgroep, bv. `vegetable`, `fish`, `processed meat`.
  final String group;

  /// Deel of vorm, bv. `leaf`, `fillet`, `powder`, `liver`.
  final String part;

  /// `plant`, `animal`, `fungus`, `algae`, `mixed` of `other`.
  final String kind;

  /// Bereiding, bv. `raw`, `boiled`, `dried`.
  final String state;
  final List<String> flags;

  /// Samengesteld gerecht.
  final bool dish;

  /// In hoeveel databanken dit voedingsmiddel voorkomt (1–7): hoe meer, hoe gewoner.
  final int spread;
}

/// Een voedingsmiddel uit een van de bronnen, met voedingswaarden per 100 g.
class Food {
  const Food({
    required this.ref,
    required this.name,
    required this.source,
    required this.per100g,
    this.brand,
    this.barcode,
    this.category,
    this.localName,
    this.portions = const [],
    this.estimated = const {},
    this.proxyRef,
    this.allergenTags = const [],
    this.traceTags = const [],
    this.ingredients,
    this.label,
    this.nova,
  });

  /// NOVA-groep van het etiket (Open Food Facts, 1 = onbewerkt … 4 = ultrabewerkt), als die bekend is.
  final int? nova;

  /// Alleen bij producten uit de ingebouwde databank.
  final FoodLabel? label;

  /// Van het etiket (Open Food Facts): allergenen, "kan sporen bevatten" en de ingrediëntenlijst.
  final List<String> allergenTags, traceTags;
  final String? ingredients;

  /// Unieke, blijvende verwijzing: `<databank>:<code>` (bv. `ciqual:13000`, `usda_sr:173944`),
  /// `off:<barcode>` of `custom:<uuid>`.
  final String ref;
  final String name;

  /// Naam in de taal van de bron (bv. Frans bij CIQUAL), als die verschilt.
  final String? localName;
  final String? brand;
  final String? barcode;
  final String? category;
  final FoodSource source;
  final NutrientMap per100g;
  final List<Portion> portions;

  /// Voedingsstoffen die in de bron ontbraken en aangevuld zijn uit hetzelfde voedingsmiddel in een
  /// andere databank: sleutel -> verwijzing naar dat voedingsmiddel (zie tool/build_foods.py).
  final Map<String, String> estimated;

  /// Vergelijkbaar basisproduct waaruit ontbrekende waarden geschat worden (bv. `ciqual:19593` voor skyr).
  /// Open Food Facts koppelt merkproducten zelf aan een CIQUAL-code (via Agribalyse).
  final String? proxyRef;

  Food copyWith({NutrientMap? per100g, Map<String, String>? estimated, String? proxyRef}) => Food(
    ref: ref,
    name: name,
    source: source,
    per100g: per100g ?? this.per100g,
    brand: brand,
    barcode: barcode,
    category: category,
    localName: localName,
    portions: portions,
    estimated: estimated ?? this.estimated,
    proxyRef: proxyRef ?? this.proxyRef,
    allergenTags: allergenTags,
    traceTags: traceTags,
    ingredients: ingredients,
    label: label,
    nova: nova,
  );

  double get kcalPer100g => per100g['energy'] ?? 0;

  String get displayName => brand == null || brand!.isEmpty ? name : '$name · $brand';
}

String encodeNutrients(NutrientMap n) => jsonEncode(n);

NutrientMap decodeNutrients(String s) => (jsonDecode(s) as Map<String, Object?>).map((k, v) => MapEntry(k, (v as num).toDouble()));

String encodePortions(List<Portion> p) => jsonEncode([for (final x in p) x.toJson()]);

List<Portion> decodePortions(String? s) =>
    s == null || s.isEmpty ? const [] : [for (final x in jsonDecode(s) as List) Portion.fromJson((x as Map).cast<String, Object?>())];
