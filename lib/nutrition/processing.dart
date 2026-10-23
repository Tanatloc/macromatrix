/// Hoe bewerkt is wat je eet: de NOVA-indeling (Monteiro e.a., Universiteit van São Paulo).
///
/// 1 = onbewerkt of weinig bewerkt (groente, fruit, vlees, melk, eieren, peulvruchten, rijst ...)
/// 2 = keukeningrediënten (olie, boter, suiker, zout)
/// 3 = bewerkt (kaas, brood, ingemaakt, gerookt, bier en wijn)
/// 4 = ultrabewerkt (frisdrank, snoep, koek, chips, worst, kant-en-klaar, vleesvervangers ...)
///
/// Merkproducten van Open Food Facts hebben vaak een NOVA-groep op het etiket; die gaat voor. Voor de ingebouwde
/// databank leiden we de groep af uit het label (voedingsgroep, bereiding, kenmerken) en de naam. Een benadering:
/// tabellen zeggen niet of je brood van de bakker of uit de fabriek komt.
library;

import '../data/food.dart';
import '../i18n.dart';

enum Nova {
  unprocessed(1, 'Unprocessed', 'Onbewerkt'),
  culinary(2, 'Cooking ingredients', 'Keukeningrediënten'),
  processed(3, 'Processed', 'Bewerkt'),
  ultra(4, 'Ultra-processed', 'Ultrabewerkt');

  const Nova(this.group, this.en, this.nl);
  final int group;
  final String en, nl;
  String get label => tr(en, nl);

  static Nova? of(int? group) => group == null || group < 1 || group > 4 ? null : values[group - 1];
}

RegExp _re(String s) => RegExp(s, caseSensitive: false);

/// Typisch ultrabewerkt, in welke groep het ook staat.
final _ultra = _re(
  r'\b(?:cola|soda|soft drink|energy drink|lemonade|cordial|sports drink|iced tea|candy|candies|sweets|gummy|gummies|'
  r'marshmallow|lollipop|toffee|chocolate bar|cookie|cookies|biscuit|biscuits|wafer|cracker|crackers|crisps|chips|'
  r'popcorn, (caramel|sweet|microwave)|nugget|nuggets|fish fingers?|fish sticks?|hot ?dog|frankfurter|sausage|salami|'
  r'chorizo|luncheon|corned beef|pâté|pate|spam|burger|ready meal|instant|noodles, instant|cup noodles|'
  r'margarine|spread|processed cheese|cheese spread|ice cream|custard|pudding|mousse|cake|muffin|doughnut|donut|'
  r'croissant|brioche|pastry|pastries|cereal bar|granola bar|protein bar|breakfast cereal|cornflakes|'
  r'mayonnaise|ketchup|dressing|stock cube|bouillon|gravy|sweetener|glucose syrup|liqueur|whisky|whiskey|vodka|gin|rum|'
  r'brandy|cognac|meat substitute|vegetarian burger|veggie|imitation|surimi|flavou?red|sweetened|french fries|'
  r'(?:whey|casein|pea|soy|rice|hemp|egg white) protein|protein powder|protein isolate|protein concentrate|protein shake|'
  r'fruit yog(?:h)?urt)(?:e?s)?\b|yog(?:h)?urt\b.*\bfruit',
);

/// Fabrieksversie van een gerecht, soep of brood.
final _factory = _re(r'\b(prepacked|pre-packed|retail|ready[- ]to|frozen|instant|canned|dehydrated|powder)\b');

/// Bewerkt: ingemaakt, gezouten, gerookt, kaas, brood, bier en wijn.
final _processed = _re(
  r'\b(canned|tinned|in brine|in oil|in syrup|pickled|salted|smoked|cured|ham|bacon|cheese|bread|beer|wine|cider|'
  r'tofu|tempeh|sauerkraut|olives|jam|marmalade|peanut butter|nut butter|dried meat|jerky)\b',
);

/// Keukeningrediënten.
final _culinary = _re(r'\b(oil|butter|lard|ghee|sugar|honey|salt|vinegar|starch|cornflour|maple syrup)\b');

/// Groepen uit het label die als geheel bij een NOVA-groep horen (tenzij de naam iets anders zegt).
const _byGroup = {
  'vegetable': Nova.unprocessed,
  'fruit': Nova.unprocessed,
  'legume': Nova.unprocessed,
  'nut/seed': Nova.unprocessed,
  'egg': Nova.unprocessed,
  'meat': Nova.unprocessed,
  'poultry': Nova.unprocessed,
  'fish': Nova.unprocessed,
  'shellfish': Nova.unprocessed,
  'offal': Nova.unprocessed,
  'potato/tuber': Nova.unprocessed,
  'rice': Nova.unprocessed,
  'pasta': Nova.unprocessed,
  'cereal': Nova.unprocessed,
  'mushroom': Nova.unprocessed,
  'herb/spice': Nova.unprocessed,
  'dairy': Nova.unprocessed,
  'beverage': Nova.unprocessed,
  'oil/fat': Nova.culinary,
  'bread': Nova.processed,
  'soup': Nova.processed,
  'dish': Nova.processed,
  'soy product': Nova.processed,
  'alcohol': Nova.processed,
  'processed meat': Nova.processed,
  'sugar/sweets': Nova.ultra,
  'snack': Nova.ultra,
  'dessert': Nova.ultra,
  'bakery': Nova.ultra,
  'breakfast cereal': Nova.ultra,
  'meat substitute': Nova.ultra,
  'sauce/condiment': Nova.ultra,
};

/// Kenmerken die een onbewerkt product bewerkt of ultrabewerkt maken.
const _ultraFlags = {'sweetened', 'diet', 'instant', 'breaded'};
const _processedFlags = {'salted', 'in syrup', 'in sauce', 'smoked'};

/// NOVA-groep van een voedingsmiddel, of null als we het niet weten (supplementen, babyvoeding, eigen producten
/// zonder herkenbare naam). Recepten: zie [novaOfRecipe].
Nova? novaOf(Food f) {
  final label = Nova.of(f.nova);
  if (label != null) return label;
  final l = f.label;
  final name = f.name;
  if (l == null) {
    // Eigen of gescand product zonder NOVA op het etiket: alleen een duidelijke naam telt
    if (_ultra.hasMatch(name)) return Nova.ultra;
    if (f.source == FoodSource.off) return null;
    if (_processed.hasMatch(name)) return Nova.processed;
    if (_culinary.hasMatch(name)) return Nova.culinary;
    return null;
  }
  if (l.group == 'supplement' || l.group == 'baby food' || l.group == 'other') return null;
  final base = _byGroup[l.group];
  if (base == null) return null;
  // Groepen die al ultrabewerkt zijn, blijven dat; anders kan de naam of een kenmerk het zwaarder maken
  if (base == Nova.ultra) {
    // Suiker en honing zijn keukeningrediënten, geen snoep
    if (l.group == 'sugar/sweets' && _culinary.hasMatch(name) && !_ultra.hasMatch(name)) return Nova.culinary;
    return Nova.ultra;
  }
  if (l.flags.any(_ultraFlags.contains) || _ultra.hasMatch(name)) {
    // Gezoete melk of yoghurt, gepaneerde vis, instantpuree, sterke drank, worst ...
    return Nova.ultra;
  }
  if (base == Nova.culinary) return Nova.culinary;
  if (const {'dish', 'soup', 'bread'}.contains(l.group) && _factory.hasMatch(name)) return Nova.ultra;
  if (base == Nova.processed) return Nova.processed;
  // Onbewerkte groep: kaas, ingemaakt, gerookt of gezouten maakt het bewerkt
  if (l.flags.any(_processedFlags.contains) || _processed.hasMatch(name) || l.state == 'canned') return Nova.processed;
  if (l.group == 'dairy' && _culinary.hasMatch(name)) return Nova.culinary;
  return Nova.unprocessed;
}

/// Zelf gemaakt: een recept neemt de zwaarste groep over die samen een flink deel (≥ 20%) van de energie levert.
/// Pasta met tomaat en olijfolie blijft zo onbewerkt; een recept met veel worst wordt ultrabewerkt. Kleinere
/// stukjes bewerkt of ultrabewerkt (een kant-en-klare saus, eiwitpoeder) tellen samen: vanaf 5% is het recept
/// minstens "bewerkt", niet "onbewerkt".
Nova? novaOfRecipe(List<(Nova?, double kcal)> ingredients) {
  final total = ingredients.fold(0.0, (a, i) => a + i.$2);
  if (total <= 0) return null;
  final share = <Nova, double>{};
  var known = 0.0;
  for (final (n, kcal) in ingredients) {
    if (n == null) continue;
    known += kcal;
    share[n] = (share[n] ?? 0) + kcal / total;
  }
  if (known / total < 0.5) return null;
  Nova? worst;
  for (final e in share.entries) {
    if (e.key == Nova.culinary || e.value < 0.2) continue;
    if (worst == null || e.key.group > worst.group) worst = e.key;
  }
  final processedBits = (share[Nova.processed] ?? 0) + (share[Nova.ultra] ?? 0);
  if ((worst == null || worst.group < Nova.processed.group) && processedBits >= 0.05) return Nova.processed;
  return worst ?? Nova.unprocessed;
}

/// Verdeling van de energie over de NOVA-groepen; [unknown] = energie waarvan we de groep niet kennen.
class ProcessingShare {
  const ProcessingShare(this.kcal, this.unknown);
  final Map<Nova, double> kcal;
  final double unknown;

  double get known => kcal.values.fold(0.0, (a, b) => a + b);

  /// Deel van de bekende energie in een groep (0–1).
  double share(Nova n) => known <= 0 ? 0 : (kcal[n] ?? 0) / known;

  /// Genoeg om iets over te zeggen: minstens 100 kcal en twee derde van de energie bekend.
  bool get meaningful => known >= 100 && known >= (known + unknown) * 2 / 3;

  static ProcessingShare of(Iterable<(Nova?, double kcal)> items) {
    final kcal = <Nova, double>{};
    var unknown = 0.0;
    for (final (n, k) in items) {
      if (k <= 0) continue;
      if (n == null) {
        unknown += k;
      } else {
        kcal[n] = (kcal[n] ?? 0) + k;
      }
    }
    return ProcessingShare(kcal, unknown);
  }
}
