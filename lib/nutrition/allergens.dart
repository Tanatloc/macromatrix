/// Allergenen: de 14 die in de EU op het etiket moeten (Verordening 1169/2011, bijlage II).
///
/// Bij een product van Open Food Facts kijkt de app naar de allergenen en "kan sporen bevatten" die OFF opgeeft,
/// en naar de ingrediëntenlijst. Bij basisproducten zonder etiket kan alleen de naam gecontroleerd worden. Altijd
/// het etiket nakijken: een databank kan fouten bevatten.
library;

import '../data/food.dart';
import '../i18n.dart';

enum Allergen {
  peanuts('Peanuts', 'Pinda', 'en:peanuts', r'peanuts?|groundnuts?|arachis|pinda\w*|apenootjes?|arachides?|cacahu[eè]tes?|erdn[uü]ss\w*'),
  nuts(
    'Tree nuts',
    'Noten',
    'en:nuts',
    r'almonds?|hazelnuts?|walnuts?|cashews?|pecans?|pistachios?|macadamias?|brazil nuts?|amandel\w*|hazelno\w*|walno\w*|cashewno\w*|pistache\w*|amandes?|noisettes?|noix|mandeln?|haseln[uü]ss\w*|waln[uü]ss\w*|praline|marzipan|marsepein',
  ),
  milk(
    'Milk',
    'Melk',
    'en:milk',
    r'milk|cheese|butter|cream|yogh?urt|whey|casein\w*|lactose|ghee|kefir|skyr|quark|melk\w*|kaas|boter|room|wei|ca[sz]e[iï]ne|lait|fromage|beurre|cr[eè]me|milch|k[aä]se|sahne|molke',
  ),
  eggs('Eggs', 'Ei', 'en:eggs', r'eggs?|albumen|mayonnaise|mayo|eieren|eigeel|eidooier|kippenei|[oœ]ufs?|eier'),
  gluten(
    'Gluten',
    'Gluten',
    'en:gluten',
    r'gluten|wheat|barley|rye|spelt|semolina|couscous|bulgur|seitan|malt|tarwe\w*|gerst\w*|rogge\w*|griesmeel|bl[eé]|orge|seigle|[eé]peautre|weizen|gerste|roggen|dinkel',
  ),
  soy('Soy', 'Soja', 'en:soybeans', r'soy|soya|soja\w*|tofu|tempeh|edamame|miso'),
  fish(
    'Fish',
    'Vis',
    'en:fish',
    r'fish|salmon|tuna|cod|anchov\w*|sardines?|mackerel|herring|trout|haddock|pollock|vis|zalm|tonijn|kabeljauw|ansjovis|haring|makreel|forel|poisson|saumon|thon|morue|anchois|fisch|lachs|thunfisch',
  ),
  crustaceans(
    'Crustaceans',
    'Schaaldieren',
    'en:crustaceans',
    r'shrimps?|prawns?|crabs?|lobsters?|crayfish|langoustines?|garna\w*|krab\w*|kreeft\w*|scampi|crevettes?|crabes?|homards?|garnelen?|krabben|hummer',
  ),
  molluscs(
    'Molluscs',
    'Weekdieren',
    'en:molluscs',
    r'mussels?|oysters?|clams?|squids?|octopus|scallops?|snails?|cuttlefish|mossel\w*|oester\w*|inktvis\w*|slakken|moules?|hu[iî]tres?|calmars?|poulpes?|escargots?',
  ),
  celery('Celery', 'Selder', 'en:celery', r'celery|celeriac|selder\w*|selderij|c[eé]leri|sellerie'),
  mustard('Mustard', 'Mosterd', 'en:mustard', r'mustard|mosterd\w*|moutarde|senf'),
  sesame('Sesame', 'Sesam', 'en:sesame-seeds', r'sesame|tahini|tahin|sesam\w*|s[eé]same'),
  sulphites(
    'Sulphites',
    'Sulfiet',
    'en:sulphur-dioxide-and-sulphites',
    r'sulph?ites?|sulfiet\w*|sulfite|sulphur dioxide|sulfur dioxide|zwaveldioxide|disulfite|e22[0-8]',
  ),
  lupin('Lupin', 'Lupine', 'en:lupin', r'lupin\w*');

  const Allergen(this.en, this.nl, this.offTag, this._words);
  final String en, nl;

  /// Code in Open Food Facts (allergens_tags / traces_tags).
  final String offTag;
  final String _words;

  String get label => tr(en, nl);
  RegExp get pattern => RegExp('\\b(?:$_words)\\b', caseSensitive: false, unicode: true);
}

/// Plantaardige "melk", "boter" en "room" zijn geen zuivel (amandelmelk, pindakaas, kokosroom).
final _plantDairy = RegExp(
  r'\b(peanut|almond|cashew|cocoa|nut|seed|sesame|coconut|soy|soya|oat|rice|hazelnut|shea|pinda|amandel|kokos|haver|rijst)\s*-?\s*(butter|milk|cream|drink|yogh?urt|boter|melk|room|drank)',
  caseSensitive: false,
);

/// "Pindakaas" blijft pinda, maar "boter" telt dan niet als zuivel.
String _noPlantDairy(String s) => s.replaceAllMapped(_plantDairy, (m) => '${m[1]} ');

enum AllergenLevel { contains, traces, name }

class AllergenHit {
  const AllergenHit(this.allergen, this.level);
  final Allergen allergen;

  /// contains: staat op het etiket of in de ingrediënten; traces: "kan sporen bevatten";
  /// name: alleen afgeleid uit de naam (geen etiketgegevens).
  final AllergenLevel level;
}

/// Gegevens van het etiket (Open Food Facts), voor zover bekend.
class LabelInfo {
  const LabelInfo({this.allergens = const [], this.traces = const [], this.ingredients});
  final List<String> allergens, traces;
  final String? ingredients;
  bool get hasData => allergens.isNotEmpty || traces.isNotEmpty || (ingredients?.trim().isNotEmpty ?? false);
}

/// Welke van [mine] zitten in een product. Met etiketgegevens ([label]) is dat betrouwbaarder dan op de naam.
List<AllergenHit> allergenHits(Set<Allergen> mine, {required String name, LabelInfo? label}) {
  if (mine.isEmpty) return const [];
  final out = <AllergenHit>[];
  final ingredients = _noPlantDairy(label?.ingredients ?? '');
  final cleanName = _noPlantDairy(name);
  for (final a in mine) {
    if (label != null && label.hasData) {
      if (label.allergens.contains(a.offTag) || (ingredients.isNotEmpty && a.pattern.hasMatch(ingredients))) {
        out.add(AllergenHit(a, AllergenLevel.contains));
      } else if (label.traces.contains(a.offTag)) {
        out.add(AllergenHit(a, AllergenLevel.traces));
      } else if (a.pattern.hasMatch(cleanName)) {
        out.add(AllergenHit(a, AllergenLevel.name));
      }
    } else if (a.pattern.hasMatch(cleanName)) {
      out.add(AllergenHit(a, AllergenLevel.name));
    }
  }
  return out;
}

/// Snelle controle op naam en categorie (voor suggesties en rijkste bronnen).
bool containsAllergen(Food f, Set<Allergen> mine) {
  if (mine.isEmpty) return false;
  final text = _noPlantDairy('${f.name} ${f.localName ?? ''} ${f.category ?? ''}');
  return mine.any((a) => a.pattern.hasMatch(text));
}
