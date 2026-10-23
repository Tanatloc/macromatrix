/// Gewone porties (sneetje, glas, kom, stuk, schep, lepel) voor producten waarvoor de databank er geen heeft, en de
/// stappen van de plus- en minknop bij de hoeveelheid.
library;

import 'dart:math' as math;

import '../data/food.dart';
import '../i18n.dart';

/// Een geschatte portie: geen gegeven uit de databank maar een gewone hoeveelheid voor dit soort product.
/// [label] (bv. "1 slice (≈35 g)") komt in het dagboek; [short] ("1 slice") staat op de knop, met de grammen eronder.
class EverydayPortion extends Portion {
  const EverydayPortion(this.short, super.label, super.grams);
  final String short;
}

/// Gewoon gewicht van één stuk, als de databank geen portie heeft.
double? typicalPieceGrams(String name) {
  const pieces = <String, double>{
    r'protein powder|\bwhey protein': 30,
    r'\begg': 55,
    r'\bcroissant': 60,
    r'\bbagel': 90,
    r'\b(bread )?roll\b': 60,
    r'\bslice': 35,
    r'\bmuffin': 70,
    r'\bbanana': 120,
    r'\bapple': 150,
    r'\borange\b': 150,
    r'\bpear\b': 160,
    r'\bkiwi': 75,
    r'\bmandarin|\btangerine|\bclementine': 70,
    r'\bbiscuit|\bcookie|\bdigestive': 15,
    r'\bcracker': 8,
    r'\brice cake': 9,
    r'\bsausage': 60,
    r'\bhash brown': 60,
    r'\bpotato\b': 150,
    r'\btomato\b': 120,
    r'\bcarrot': 60,
    r'\bavocado': 140,
    r'\bpeach': 150,
    r'\bplum\b': 65,
  };
  for (final e in pieces.entries) {
    if (RegExp(e.key).hasMatch(name)) return e.value;
  }
  return null;
}

// Soorten portie, met wat in een databankportie als "dezelfde soort" telt (dan geen schatting erbij)
const _slice = r'\bslices?\b';
const _glass = r'\b(glass|cup|mug|fl oz|decilitre|dl|can|bottle)\b';
const _bowl = r'\b(bowl|cup|serving|portion)\b';
const _piece = r'\b(piece|pcs|unit|item|whole|large|medium|small|egg|fruit|cookie|biscuit|bar)\b';
const _scoop = r'\b(scoop|serving|portion|dose)\b';
const _tsp = r'\b(tsp|teaspoons?)\b';
const _tbsp = r'\b(tbsp|tablespoons?)\b';

final _proteinPowder = RegExp(r'protein powder|\bwhey\b|\bcasein\b|protein shake powder');
final _spirits = RegExp(r'\b(vodka|whisk(e)?y|gin|rum|brandy|cognac|liqueur|tequila|spirits?|schnapps|jenever)\b');
final _wine = RegExp(r'\b(wine|champagne|prosecco|cava|port|sherry)\b');
final _beer = RegExp(r'\b(beer|lager|ale|pils|cider)\b');
final _hotDrink = RegExp(r'\b(coffee|tea|espresso|cappuccino|latte|hot chocolate|cocoa drink)\b');
final _drinkName = RegExp(
  r'\b(milk|juice|soda|cola|lemonade|water|smoothie|drink|kefir|buttermilk|soft drink|iced tea|nectar|squash)\b|'
  r'\b(wine|beer|lager|cider|coffee|tea|espresso|latte|cappuccino)\b',
);
final _notDrink = RegExp(
  r'\b(powder|powdered|dried|condensed|evaporated|chocolate|ground|beans?|instant|granules|leaves|concentrate|ice cream|'
  r'bread|cake|biscuits?|cookies?|pudding|sauce|vinegar|coconut flesh)\b',
);
final _oil = RegExp(r'\b(oil|ghee|lard|dripping|suet)\b');
final _spread = RegExp(
  r'\b(butter|margarine|spread|peanut butter|nut butter|nutella|jam|marmalade|honey|syrup|cream cheese|hummus|houmous|'
  r'pesto|tahini|chocolate spread|mayo|mayonnaise)\b(?! ?(beans?|chicken|cookies?|biscuits?|cake|croissant))',
);
final _yogurt = RegExp(r'\b(yog(h)?o?urt|skyr|quark|fromage frais|porridge|oatmeal|custard)\b');
final _cereal = RegExp(r'\b(cereal|muesli|granola|cornflakes|corn flakes|bran flakes|rice krispies|oat flakes|rolled oats|porridge oats)\b');
final _bread = RegExp(r'\b(bread|toast|baguette|loaf|sourdough|pumpernickel|brioche)\b');
final _notSlice = RegExp(r'\b(roll|bagel|croissant|bun|pitt?a|wrap|tortilla|naan|crumbs?|breadcrumbs|sticks?|pudding|sauce)\b');

final _notPiece = RegExp(r'\b(puree|purée|sauce|compote|juice|jam|pie|crumble|soup|salad|mash(ed)?|chips|fries|noodles|pasta)\b');

/// Groepen waarin "een stuk" iets betekent; voor andere groepen (bv. eiernoedels) geen stuk op naam alleen.
const _pieceGroups = {'fruit', 'egg', 'bakery', 'bread', 'vegetable', 'snack', 'sugar/sweets', 'processed meat', 'potato/tuber', 'dessert'};

String _approx(double g) => g == g.roundToDouble() ? '${g.round()}' : g.toStringAsFixed(1);

EverydayPortion _p(String en, String nl, double grams, {String unit = 'g'}) {
  final short = tr(en, nl);
  return EverydayPortion(short, '$short (≈${_approx(grams)} $unit)', grams);
}

/// Gewone porties voor dit product die de databank nog niet heeft (hoogstens 3), op basis van naam en label.
/// Leeg als het product niet herkend wordt of de databank al zo'n portie heeft.
List<EverydayPortion> everydayPortions(Food f) {
  final name = f.name.toLowerCase();
  final l = f.label;
  final group = l?.group;
  final part = l?.part;
  final existing = [for (final p in f.portions) p.label.toLowerCase()];
  bool has(String pattern) => existing.any(RegExp(pattern).hasMatch);
  List<EverydayPortion> unless(List<(String, EverydayPortion)> kinds) => [
    for (final (pattern, portion) in kinds)
      if (!has(pattern)) portion,
  ];

  // Eiwitpoeder: een schep
  if (_proteinPowder.hasMatch(name) || (group == 'supplement' && part == 'powder')) {
    return unless([(_scoop, _p('1 scoop', '1 schep', 30))]);
  }

  // Dranken: een glas (wijn kleiner, sterkedrank een borrel), koffie en thee een mok
  final drinkByLabel = l != null && (part == 'drink' || part == 'juice') && const {'beverage', 'dairy', 'alcohol'}.contains(group);
  final drinkByName = l == null && _drinkName.hasMatch(name) && !_notDrink.hasMatch(name);
  if (drinkByLabel || drinkByName) {
    if (_spirits.hasMatch(name)) return unless([(r'\b(shot|glass|measure|fl oz)\b', _p('1 shot', '1 borrel', 35, unit: 'ml'))]);
    if (_wine.hasMatch(name)) return unless([(_glass, _p('1 glass', '1 glas', 150, unit: 'ml'))]);
    if (_beer.hasMatch(name)) return unless([(_glass, _p('1 glass', '1 glas', 250, unit: 'ml'))]);
    if (_hotDrink.hasMatch(name)) return unless([(_glass, _p('1 mug', '1 mok', 250, unit: 'ml'))]);
    return unless([(_glass, _p('1 glass', '1 glas', 200, unit: 'ml'))]);
  }
  // Poeder of concentraat van een drank: geen glas
  if (const {'beverage', 'alcohol'}.contains(group)) return const [];

  // Vetten en beleg: een koffielepel, een eetlepel, en voor beleg wat je op een boterham smeert
  final fat = group == 'oil/fat' || (l == null && _oil.hasMatch(name));
  final spread =
      _spread.hasMatch(name) &&
      (l == null || const {'oil/fat', 'sauce/condiment', 'sugar/sweets', 'dairy', 'nut/seed', 'legume', 'other'}.contains(group));
  if (fat || spread) {
    final isOil = _oil.hasMatch(name) || part == 'oil';
    return unless([
      if (!isOil) (_slice, _p('on a slice', 'op een boterham', 10)),
      (_tsp, _p('1 teaspoon', '1 koffielepel', 5)),
      (_tbsp, _p('1 tablespoon', '1 eetlepel', 15)),
    ]);
  }

  // Yoghurt, pap en ontbijtgranen: een kom
  if (group == 'breakfast cereal' || (_cereal.hasMatch(name) && !RegExp(r'\bbars?\b').hasMatch(name))) {
    return unless([(_bowl, _p('1 bowl', '1 kom', 40))]);
  }
  if (_yogurt.hasMatch(name) && (l == null || const {'dairy', 'dessert', 'cereal', 'soy product'}.contains(group))) {
    return unless([(_bowl, _p('1 bowl', '1 kom', 150))]);
  }

  // Brood: een sneetje (broodjes, bagels en croissants zijn een stuk)
  if ((group == 'bread' || _bread.hasMatch(name)) && !_notSlice.hasMatch(name)) {
    return unless([(_slice, _p('1 slice', '1 sneetje', 35))]);
  }

  // Fruit, eieren, koekjes en ander stukgoed
  final piece = typicalPieceGrams(name);
  final notPiece = (l?.dish ?? false) || const {'puree', 'juice', 'powder', 'concentrate'}.contains(part) || _notPiece.hasMatch(name);
  if (piece != null && !notPiece && (l == null || _pieceGroups.contains(group))) {
    return unless([(_piece, _p('1 piece', '1 stuk', piece))]);
  }
  return const [];
}

/// De porties op de knoppen bij de hoeveelheid: die uit de databank en de geschatte erbij, samen hoogstens [max].
/// Geschatte porties krijgen voorrang op de staart van een lange databanklijst (minder gewone maten zoals "1 cubic inch").
List<Portion> portionOptions(Food f, {int max = 6}) {
  final extra = everydayPortions(f);
  return [...f.portions.take(math.max(max - extra.length, 3)), ...extra].take(max).toList();
}

/// Volgende waarde voor de plus- of minknop. Porties: per 1, onder 2 per halve. Gram: per 10 onder 100 g, daarboven
/// per 25. Het resultaat ligt altijd op een veelvoud van de stap (97 → 100, niet 107), nooit onder 0.
double stepQuantity(double q, {required bool up, required bool portion}) {
  const eps = 1e-9;
  final double step = portion
      ? (up ? (q < 2 - eps ? 0.5 : 1) : (q <= 2 + eps ? 0.5 : 1))
      : (up ? (q < 100 - eps ? 10 : 25) : (q <= 100 + eps ? 10 : 25));
  final next = up ? ((q / step + eps).floor() + 1) * step : ((q / step - eps).ceil() - 1) * step;
  return math.max(0, next);
}
