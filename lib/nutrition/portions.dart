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
    r'\bpitt?a\b': 60,
    r'\bnaan\b': 90,
    r'\b(wrap|tortilla)s?\b': 60,
    r'\bbuns?\b': 60,
    r'\bcrumpets?\b': 55,
    r'\bscones?\b': 60,
    r'\bpancakes?\b': 50,
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
    r'\bcroquet': 35,
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
final _coconutMilk = RegExp(r'\bcoconut milk\b');
final _oil = RegExp(r'\b(oil|ghee|lard|dripping|suet)\b');
final _spread = RegExp(
  r'\b(butter|margarine|spread|peanut butter|nut butter|nutella|jam|marmalade|honey|syrup|cream cheese|hummus|houmous|'
  r'pesto|tahini|chocolate spread|mayo|mayonnaise)\b(?! ?(beans?|chicken|cookies?|biscuits?|cake|croissant))',
);
final _yogurt = RegExp(r'\b(yog(h)?o?urt|skyr|quark|fromage frais|porridge|oatmeal|custard)\b');
final _cereal = RegExp(r'\b(cereal|muesli|granola|cornflakes|corn flakes|bran flakes|rice krispies|oat flakes|rolled oats|porridge oats)\b');
final _bread = RegExp(r'\b(bread|toast|baguette|loaf|sourdough|pumpernickel|brioche)\b');
final _notSlice = RegExp(r'\b(roll|bagel|croissant|bun|pitt?a|wrap|tortilla|naan|crumbs?|breadcrumbs|sticks?|pudding|sauce)\b');

// Snacks uit een zakje: chips, popcorn, puffs (geen "stuk": een stuk aardappel van 150 g is geen zakje chips)
final _bagSnack = RegExp(
  r'\b(crisps|(potato|tortilla|corn|vegetable|veggie|lentil|rice|wheat|taro|multigrain|bean|pita|bagel) chips|popcorn|puffs|puffed|'
  r'cheese doodles|twiglets|prawn crackers?|shrimp crackers?|pork scratchings|pork rinds|bombay mix|trail mix|corn snack|'
  r'potato snack|potato rings|chevda|nachos)\b',
);
final _chips = RegExp(r'\bchips\b');
final _fries = RegExp(r'\b(fries|french|chips shop|chip shop|oven chips|frozen|deep[- ]fried potatoes|fast food)\b');

// Havermout: een kom (droog) en een eetlepel; gekookt (pap) een grote kom
final _oats = RegExp(r'\b(oats|rolled oats|oat flakes|porridge oats|oatmeal flakes|steel cut)\b');
final _cooked = RegExp(r'\b(cooked|boiled|bolied|prepared|with water|in water|with milk)\b');

// Soep: een kom (geen poeder, blokje of geconcentreerde soep)
final _soup = RegExp(r'\b(soup|broth|bouillon|consomm[eé]|chowder|gazpacho|bisque)\b');
final _notSoup = RegExp(r'\b(powder|dried|dry|cubes?|condensed|concentrate|mix|undiluted|vegetables for soups?|soup vegetables)\b');

// Taart en cake: een stuk (geen bodem, mix of vulling, en geen koekjes of stukgoed zoals een mince pie)
final _cake = RegExp(r'\b(cakes?|gateau|gâteau|cheesecake|pies?|tarts?|tarte|torte|swiss roll|yule log)\b');
final _notCake = RegExp(
  r'\b(mix|base|crust|shell|filling|cookies?|bars?|rusk|cone|rice cakes?|corn cakes?|oatcakes?|pancakes?|griddle|jaffa|welsh|rock|eccles|'
  r'pork|meat|fish|crab|potato|mince|cupcakes?|snack cakes?|fried|madeleine|shortcake)\b',
);

final _notPiece = RegExp(r'\b(puree|purée|sauce|compote|juice|jam|pie|crumble|soup|salad|mash(ed)?|chips|fries|noodles|pasta)\b');

/// Groepen waarin "een stuk" iets betekent; voor andere groepen (bv. eiernoedels) geen stuk op naam alleen.
const _pieceGroups = {'fruit', 'egg', 'bakery', 'bread', 'vegetable', 'snack', 'sugar/sweets', 'processed meat', 'potato/tuber', 'dessert'};

String _approx(double g) => g == g.roundToDouble() ? '${g.round()}' : g.toStringAsFixed(1);

EverydayPortion _p(String en, String nl, double grams, {String unit = 'g'}) {
  final short = tr(en, nl);
  return EverydayPortion(short, '$short (≈${_approx(grams)} $unit)', grams);
}

/// Een drank (melk, sap, water, bier, koffie): hoeveelheden in ml in plaats van gram (N85). Poeder, concentraat en
/// gecondenseerde melk tellen niet.
bool isDrink(Food f) {
  final l = f.label;
  final name = f.name.toLowerCase();
  if (l != null) return (l.part == 'drink' || l.part == 'juice') && const {'beverage', 'dairy', 'alcohol'}.contains(l.group);
  return _drinkName.hasMatch(name) && !_notDrink.hasMatch(name);
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
  if (isDrink(f)) {
    // Kokosmelk uit blik is om mee te koken: een eetlepel of een blik, geen glas van 400 kcal (N84)
    if (_coconutMilk.hasMatch(name) && !RegExp(r'\bdrink\b').hasMatch(name)) {
      return unless([(_tbsp, _p('1 tablespoon', '1 eetlepel', 15, unit: 'ml')), (r'\b(can|tin|box)\b', _p('1 can', '1 blik', 400, unit: 'ml'))]);
    }
    if (_spirits.hasMatch(name)) return unless([(r'\b(shot|glass|measure|fl oz)\b', _p('1 shot', '1 borrel', 35, unit: 'ml'))]);
    if (_wine.hasMatch(name)) return unless([(_glass, _p('1 glass', '1 glas', 150, unit: 'ml'))]);
    // Bier: een glas en een Britse pint van 568 ml (N48, N84)
    if (_beer.hasMatch(name)) {
      return unless([(_glass, _p('1 glass', '1 glas', 250, unit: 'ml')), (r'\bpint\b', _p('1 pint', '1 pint', 568, unit: 'ml'))]);
    }
    if (_hotDrink.hasMatch(name)) return unless([(_glass, _p('1 mug', '1 mok', 250, unit: 'ml'))]);
    return unless([(_glass, _p('1 glass', '1 glas', 200, unit: 'ml'))]);
  }
  // Poeder of concentraat van een drank: geen glas
  if (const {'beverage', 'alcohol'}.contains(group)) return const [];

  // Bloem en zetmeel: een eetlepel (N84)
  if (part == 'flour' || (l == null && RegExp(r'\b(flour|cornflour|cornstarch|corn starch)\b').hasMatch(name))) {
    return unless([(_tbsp, _p('1 tablespoon', '1 eetlepel', 10))]);
  }

  // Pizza: een punt en een hele (zoals bij Snel loggen)
  if (RegExp(r'\bpizzas?\b(?! ?(sauce|dough|base|topping|cheese|seasoning|bread))').hasMatch(name)) {
    return unless([(r'\b(slice|piece)\b', _p('1 slice', '1 punt', 100)), (r'\b(whole|pizza)\b', _p('1 pizza', '1 pizza', 400))]);
  }

  // Vetten en beleg: een koffielepel, een eetlepel, en voor beleg wat je op een boterham smeert
  final fat = group == 'oil/fat' || (l == null && _oil.hasMatch(name));
  final spread =
      _spread.hasMatch(name) &&
      (l == null || const {'oil/fat', 'sauce/condiment', 'sugar/sweets', 'dairy', 'nut/seed', 'legume', 'other'}.contains(group));
  if (fat || spread) {
    final isOil = _oil.hasMatch(name) || part == 'oil';
    return unless([
      if (!isOil) (_slice, _p('on 1 slice', 'op 1 boterham', 10)),
      (_tsp, _p('1 teaspoon', '1 koffielepel', 5)),
      (_tbsp, _p('1 tablespoon', '1 eetlepel', 15)),
    ]);
  }

  // Chips en andere snacks uit een zakje: een (klein) zakje, nooit een stuk
  final snackName = '$name ${l?.food ?? ''}'.toLowerCase();
  final bag =
      !(l?.dish ?? false) &&
      // Rijstwafels en crackers blijven per stuk (behalve kroepoek)
      !RegExp(r'\bcakes?\b|(?<!prawn |shrimp )\bcrackers?\b').hasMatch(snackName) &&
      (group == 'snack' && (_bagSnack.hasMatch(snackName) || _chips.hasMatch(snackName)) ||
          l == null && _bagSnack.hasMatch(name) && !_fries.hasMatch(name));
  if (bag) {
    return unless([
      (r'\b(small bag|multipack|bag|packet|pack|package|sachet)\b', _p('1 small bag', '1 klein zakje', 25)),
      (r'\b(bag|packet|pack|package)\b', _p('1 bag', '1 zakje', 32)),
    ]);
  }

  // Soep: een kom
  final soupLike = group == 'soup' || (l == null && _soup.hasMatch(name));
  if (soupLike && !_notSoup.hasMatch(name) && !const {'powder', 'concentrate'}.contains(part) && l?.state != 'dried') {
    return unless([(_bowl, _p('1 bowl', '1 kom', 250))]);
  }

  // Havermout: droog een kom en een eetlepel, gekookt een kom pap
  final oatsLike = _oats.hasMatch(name) || const {'oats', 'rolled oats'}.contains(l?.food);
  if (oatsLike &&
      (l == null || const {'cereal', 'breakfast cereal'}.contains(group)) &&
      !RegExp(r'\b(bars?|biscuits?|cookies?|bread|drink)\b').hasMatch(name)) {
    final cookedOats = _cooked.hasMatch(name) || const {'boiled', 'cooked', 'prepared', 'steamed'}.contains(l?.state);
    if (cookedOats) return unless([(_bowl, _p('1 bowl', '1 kom', 250))]);
    return unless([(_bowl, _p('1 bowl', '1 kom', 40)), (_tbsp, _p('1 tablespoon', '1 eetlepel', 10))]);
  }

  // Taart en cake: een stuk
  final cakeName = (l?.food ?? name).toLowerCase();
  if ((l == null || const {'bakery', 'dessert'}.contains(group)) &&
      _cake.hasMatch(cakeName) &&
      !_notCake.hasMatch(cakeName) &&
      !_notCake.hasMatch(name)) {
    return unless([(r'\b(slice|piece|pcs|serving|portion)\b', _p('1 slice', '1 stuk taart', 75))]);
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

/// Volgende waarde voor de plus- of minknop. Porties (stuks, recepten): per 1, alleen onder 1 per halve (N32); een
/// halve portie daarboven tik je zelf in. Gram: per 10 onder 100 g, daarboven
/// per 25. Het resultaat ligt altijd op een veelvoud van de stap (97 → 100, niet 107), nooit onder 0.
double stepQuantity(double q, {required bool up, required bool portion}) {
  const eps = 1e-9;
  final double step = portion
      ? (up ? (q < 1 - eps ? 0.5 : 1) : (q <= 1 + eps ? 0.5 : 1))
      : (up ? (q < 100 - eps ? 10 : 25) : (q <= 100 + eps ? 10 : 25));
  final next = up ? ((q / step + eps).floor() + 1) * step : ((q / step - eps).ceil() - 1) * step;
  return math.max(0, next);
}
