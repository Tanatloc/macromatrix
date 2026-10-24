/// "Wat moet ik nog eten?": 2 à 3 concrete producten die samen de grootste tekorten van vandaag zo goed mogelijk
/// aanvullen, binnen de energie die je nog over hebt.
///
/// Werkwijze (gulzig): kies telkens het product en de hoeveelheid die het meest van de resterende tekorten vult
/// (per stof hoogstens tot 100% van het doel, de grootste tekorten zwaarder), in een gewone portie, binnen de energie
/// die over is en zonder een bovengrens te overschrijden. Daarna worden de totalen bijgewerkt en zoekt het volgende
/// product verder.
library;

import 'dart:math' as math;

import '../data/food.dart';
import 'insights.dart';
import 'nutrients.dart';
import 'portions.dart' show typicalPieceGrams;
import 'processing.dart';
import 'targets.dart';
import 'values.dart';

class PlanItem {
  const PlanItem({required this.food, required this.grams, this.portion, required this.kcal, required this.fills});
  final Food food;
  final double grams;
  final Portion? portion;
  final double kcal;

  /// Voedingsstoffen die het vooral aanvult: (stof, deel van het doel vóór, na).
  final List<(Nutrient, double, double)> fills;
}

class GapPlan {
  const GapPlan(this.items, this.before, this.after);
  final List<PlanItem> items;

  /// Voedingsscore vóór en na het plan.
  final int before, after;
  double get kcal => items.fold(0, (a, i) => a + i.kcal);
}

final _measure = RegExp(r'\b(cup|cups|tbsp|tsp|oz|fl|ml|dl|l|quart|pint|decilitres?|tablespoons?|teaspoons?)\b', caseSensitive: false);
final _notAFood = RegExp(
  r'\b(oil|supplement|powder|shake mix|meal replacement|protein shake|extract|fortified|infant|babyfood|yeast extract|spice|spices|salt|seasoning|herbs?|gelatin(e|ou)?|gelatine|sweetener|aspartame|stevia|saccharin|meat extender|protein isolate|cod liver|fish oil|raising agent|baking|leaven)\b',
  caseSensitive: false,
);

/// Gedroogde kruiden en specerijen: rijk per 100 g, maar niemand eet er 50 g van.
final _herb = RegExp(
  r'\b(basil|oregano|thyme|rosemary|sage|parsley|dill|cumin|paprika|turmeric|cinnamon|curry|coriander|marjoram|tarragon|chervil|bay|clove|nutmeg|ginger|pepper|mustard seed|fenugreek|savory|spearmint|peppermint|chili)\b',
  caseSensitive: false,
);

/// Geen alledaags eten: rauw vlees of rauwe vis, en droge, ongekookte basisproducten (zemelen, meel, kiemen).
final _rawAnimal = RegExp(
  r'\b(beef|pork|veal|lamb|chicken|turkey|duck|kidney|liver|heart|tongue|tripe|fish|cod|salmon|herring|mackerel|meat|offal|sweetbread)\b.*\braw\b|\braw\b.*\b(beef|pork|veal|lamb|chicken|turkey|kidney|liver|heart|meat)\b',
  caseSensitive: false,
);
final _unprepared = RegExp(
  r'\b(bran|flour|meal|germ|dehydrated|unenriched|dry, raw|dry form|uncooked|unprepared|concentrate)\b',
  caseSensitive: false,
);
final _organ = RegExp(r'\b(liver|kidney|heart|tongue|tripe|offal|sweetbread|giblets|gizzard)\b', caseSensitive: false);

bool _isHerb(Food f) =>
    (f.category ?? '').toLowerCase().contains('spice') ||
    (f.category ?? '').toLowerCase().contains('herb') ||
    (_herb.hasMatch(f.name) && RegExp(r'\b(dried|ground|powder)\b', caseSensitive: false).hasMatch(f.name));

/// Iets wat je gewoon op je bord legt: geen recept, olie, supplement, kruid, rauw vlees of droog basisproduct.
bool isEverydayFood(Food f) =>
    f.source != FoodSource.recipe && !_notAFood.hasMatch(f.name) && !_isHerb(f) && !_rawAnimal.hasMatch(f.name) && !_unprepared.hasMatch(f.name);

/// Groepen die je als advies kunt krijgen: gewone voedingsmiddelen, geen snoep, sauzen, dranken, gerechten of
/// vleeswaren.
const _adviceGroups = {
  'dairy',
  'egg',
  'meat',
  'poultry',
  'fish',
  'shellfish',
  'cereal',
  'bread',
  'pasta',
  'rice',
  'breakfast cereal',
  'legume',
  'soy product',
  'nut/seed',
  'vegetable',
  'potato/tuber',
  'fruit',
  'mushroom',
  'meat substitute',
};

/// Delen die je niet als eten aanraadt: poeders, bloem, olie, sap en orgaanvlees.
const _adviceSkipParts = {
  'powder',
  'concentrate',
  'flour',
  'bran',
  'germ',
  'starch',
  'syrup',
  'oil',
  'fat',
  'skin',
  'blood',
  'peel',
  'juice',
  'bone/broth',
  'liver',
  'kidney',
  'heart',
  'tongue',
  'brain',
  'other offal',
  'tripe',
  'gizzard',
  'yolk',
  'white',
  'roe',
};

/// Ongezond als advies, ook al levert het een stof: gefrituurd, fastfood, chips en snoep.
final _unhealthyAdvice = RegExp(
  r'\b(deep[- ]?fried|fast food|takeaway|take-away|fries|french fries|chips|crisps|nuggets?|doughnuts?|donuts?|candy|sweets|chocolate bar|soft drink|energy drink)\b',
  caseSensitive: false,
);

// Ook gezouten vis en vlees (gezouten makreel: een dagportie zout in één stuk)
final _oddVariant = RegExp(r'\b(low[- ]sodium|sodium[- ]free|topping|imitation|salted|salt[- ]cured)\b', caseSensitive: false);

/// Staat wel in een paar tabellen, maar ligt hier zelden in de winkel (ook paling, gans en viskuit: N35).
final _exotic = RegExp(
  r'\b(eel|goose|roe|caviar|amaranth|rose ?hip|acerola|fenugreek|dock|sorrel|jute|taro|cassava|moringa|purslane|epazote|kantola|bitter gourd|balsam|jujube|sea lion|seal|whale|walrus|caribou|tunicate)\b',
);
final _unusual = RegExp(
  r'Alaska Native|Navajo|Shoshone|Hopi|Apache|Northern Plains|ultraviolet|soy ?beans?\b.*\broasted|roasted soy',
  caseSensitive: false,
);

/// Smaakmakers die als groente in de tabel staan: niemand eet 100 g chilipeper, knoflook of gember.
final _seasoningVeg = RegExp(
  r'\b(chill?i(es)?|chile|jalape[nñ]o|habanero|cayenne|scotch bonnet|garlic|ginger|horseradish|wasabi|capers?|lemon ?grass|shallots?)\b',
  caseSensitive: false,
);

/// Wild en zeldzaam vlees: in een gewone winkel hier zelden te koop.
final _game = RegExp(
  r'\b(game|venison|deer|elk|moose|reindeer|hare|rabbit|pheasant|partridge|quail|grouse|pigeon|squab|wild boar|boar|bison|'
  r'buffalo|kangaroo|ostrich|emu|horse|squirrel|snipe|woodcock|guinea ?fowl|ptarmigan|beaver|bear|opossum|frog)\b',
  caseSensitive: false,
);

/// Gewogen met schaal, dop of graat: het gewicht is niet wat je eet.
final _withShell = RegExp(r'\bweighed with\b|\bwith (shells?|bones?)\b|\bin (shell|the shell)\b', caseSensitive: false);

/// Wat je niet rauw eet (of droog, zoals ongekookte peulvruchten en pasta).
const _cookFirst = {'meat', 'poultry', 'fish', 'shellfish', 'egg', 'legume', 'cereal', 'rice', 'pasta', 'potato/tuber'};

/// Iets wat je als advies kunt krijgen: een gewoon, bereid voedingsmiddel dat in minstens 4 databanken in de tabel
/// staat. Geen agar, gist, kauwgom, energiedrank of zeeleeuwlever. Producten zonder label (gescand, eigen
/// producten) volgen [isEverydayFood].
bool isAdviceFood(Food f) {
  // Nooit aanraden: gefrituurd, gepaneerd, fastfood, chips, gezoet of ultrabewerkt. Ook als het een tekort aanvult
  // (frieten 'voor vitamine K' komt uit het frituurvet).
  if (_unhealthyAdvice.hasMatch(f.name) || novaOf(f) == Nova.ultra) return false;
  // Fabrieksvarianten die hier zelden in de winkel liggen ("Parmesan cheese topping, fat free", "low sodium")
  if (_oddVariant.hasMatch(f.name)) return false;
  final l = f.label;
  if (l == null) return isEverydayFood(f);
  if (l.state == 'deep-fried' || (l.state == 'fried' && l.group == 'potato/tuber')) return false;
  if (l.flags.any(const {'breaded', 'sweetened', 'in syrup', 'brand'}.contains)) return false;
  if (!_adviceGroups.contains(l.group) || _adviceSkipParts.contains(l.part) || l.dish) return false;
  if (l.kind == 'algae' || l.kind == 'other' || l.food.contains('yeast') || l.flags.contains('infant')) return false;
  // Oesters eet je wel rauw
  if (_cookFirst.contains(l.group) && (l.state == 'raw' || l.state == 'dried' || l.state == 'frozen') && l.food != 'oyster') return false;
  if (l.state == 'dried' && l.group != 'fruit' && l.group != 'nut/seed') return false;
  if (_exotic.hasMatch(l.food) || _unusual.hasMatch(f.name)) return false;
  // Wat je niet per portie eet (NW-10, NW-11): chilipepers en andere smaakmakers, rauwe paddenstoelen (30 g rauwe
  // cantharellen voor vitamine D), wild, en "gewogen met schaal of graat" (die grammen eet je niet op)
  if (_seasoningVeg.hasMatch(f.name) || _seasoningVeg.hasMatch(l.food)) return false;
  if (l.group == 'mushroom' && l.state == 'raw') return false;
  if (_game.hasMatch(f.name) || _game.hasMatch(l.food)) return false;
  if (l.flags.contains('with bone') || _withShell.hasMatch(f.name)) return false;
  // Rauwe kiemen van bonen (behalve taugé en soja) bevatten giftige lectines
  if (l.part == 'sprout' && l.state == 'raw' && l.food.contains('bean') && !RegExp('mung|soy').hasMatch(l.food)) return false;
  return l.spread >= 4 && !_notAFood.hasMatch(f.name) && !_unprepared.hasMatch(f.name);
}

/// Een gewone portie en de grootste portie die je redelijk in één keer eet, per soort voedingsmiddel (NW-10): geen
/// 100 g rauwe spinazie, 100 g noten of 100 g kaas. Zonder label: 100 g, hoogstens 150 g.
(double typical, double cap) adviceServing(Food f) {
  final l = f.label;
  final name = f.name.toLowerCase();
  if (l == null) return (100, 150);
  final dried = l.state == 'dried' || RegExp(r'\b(dried|dehydrated)\b').hasMatch(name);
  final leaf = l.part == 'leaf' || RegExp(r'\b(spinach|lettuce|rocket|arugula|watercress|chard|kale)\b').hasMatch(name);
  final cheese = l.food.contains('cheese') && !RegExp(r'cottage|quark|ricotta|fromage frais|cream cheese').hasMatch(l.food);
  return switch (l.group) {
    'fruit' when dried => (30, 40),
    'fruit' => (typicalPieceGrams(name) ?? 120, 200),
    'vegetable' when leaf && l.state == 'raw' => (50, 80),
    'vegetable' => (100, 200),
    'mushroom' => (75, 125),
    'legume' => (120, 200),
    'nut/seed' when RegExp(r'\bseeds?\b').hasMatch(name) => (15, 20),
    'nut/seed' => (30, 30),
    'dairy' when cheese => (30, 40),
    'dairy' when l.part == 'drink' => (250, 250),
    'dairy' => (150, 200),
    'egg' => (55, 110),
    'meat' || 'poultry' || 'meat substitute' || 'soy product' => (125, 150),
    'fish' || 'shellfish' => (l.state == 'canned' ? 90 : 125, 150),
    'bread' => (35, 70),
    'breakfast cereal' => (40, 60),
    'cereal' || 'rice' || 'pasta' => (150, 225),
    'potato/tuber' => (150, 250),
    _ => (100, 150),
  };
}

/// Hoeveelheden om te proberen: een herkenbare portie uit de databank, een gewone portie, de grootste redelijke en
/// een halve (zie [adviceServing]).
List<(double, Portion?)> _amounts(Food f) {
  final (typical, cap) = adviceServing(f);
  final portion = f.portions.where((p) => p.grams >= math.max(15, typical * 0.5) && p.grams <= cap && !_measure.hasMatch(p.label)).firstOrNull;
  final grams = <double>{typical, if (cap > typical) cap, if (typical / 2 >= 15) typical / 2};
  return [
    if (portion != null) (portion.grams, portion),
    for (final g in grams)
      if (portion == null || (g - portion.grams).abs() > 5) (g, null),
  ];
}

/// Calcium uit spinazie, snijbiet en rabarber wordt door oxalaat maar voor ±5% opgenomen (zie bioavailability.dart):
/// in het plan telt het niet als calciumbron (NF-5).
final _oxalate = RegExp(r'\b(spinach|chard|rhubarb|beet greens|sorrel)\b', caseSensitive: false);
double _absorbed(Food f, String key) => key == 'calcium' && _oxalate.hasMatch(f.name) ? 0.05 : 1;

/// Plan voor de rest van de dag, of null als er geen noemenswaardige tekorten zijn.
/// [mine] zijn producten die je vaak eet; die krijgen een kleine voorkeur.
///
/// De grootste tekorten van dit moment (hoogstens 3) wegen zwaarder, zodat het plan die echt aanpakt (NF-5:
/// calcium bleef op 41% staan terwijl spinazie vitamine K over 100% duwde). Energie die nog over is, mag gebruikt
/// worden: tot ±75% ervan telt een beetje mee, zodat het plan geen 94 kcal is bij 665 kcal over. Per product
/// hoogstens een redelijk deel van wat er over is, en nooit meer dan er over is.
GapPlan? planGaps({
  required NutrientMap totals,
  required Map<String, Target> targets,
  required double kcalLeft,
  required List<Food> candidates,
  Set<String> mine = const {},
  int maxItems = 3,
}) {
  final now = Map<String, double>.of(totals);
  final keys = [
    for (final k in stripKeys)
      if (targets[k]?.goal != null) k,
  ];
  double remaining(String k) => math.max(0, 1 - (now[k] ?? 0) / targets[k]!.goal!);
  if (keys.every((k) => remaining(k) < 0.15)) return null;

  final before = completenessScore(totals, targets);
  final energyLeft = math.max(kcalLeft, 0.0);
  var budget = math.max(kcalLeft, 250.0);
  // Eén product neemt hoogstens anderhalf keer zijn deel van de resterende energie (en minstens 150 kcal mag)
  final share = math.max(budget / maxItems * 1.5, 150.0);
  var planned = 0.0;
  final items = <PlanItem>[];
  final used = <String>{};
  // Hoogstens één keer vis en één keer vlees: geen sprot én zalm in hetzelfde plan (yoghurt en kaas mag wel)
  final usedGroups = <String>{};
  String? kindOf(Food f) => switch (f.label?.group) {
    'fish' || 'shellfish' => 'seafood',
    'meat' || 'poultry' => 'meat',
    _ => null,
  };
  final pool = [
    for (final f in candidates)
      if (isAdviceFood(f)) f,
  ];

  Set<String> biggest() => ([
    for (final k in keys)
      if (remaining(k) >= 0.25) k,
  ]..sort((a, b) => remaining(b).compareTo(remaining(a)))).take(3).toSet();
  // De grootste tekorten bij het begin krijgen elk een product dat er minstens 15% van het doel bij doet, zolang er
  // zo'n product is: anders vult spinazie vitamine K en A tot boven 100% en blijft calcium liggen (NF-5)
  final mustCover = biggest();
  double gained(String k) => ((now[k] ?? 0) - (totals[k] ?? 0)) / targets[k]!.goal!;
  bool givesEnough(Food f, double g, String k) => (withDerived(f.per100g)[k] ?? 0) * g / 100 * _absorbed(f, k) / targets[k]!.goal! >= 0.15;

  for (var round = 0; round < maxItems; round++) {
    final top = biggest();
    final open = {
      for (final k in mustCover)
        if (gained(k) < 0.15 && remaining(k) >= 0.25) k,
    };
    // Laatste kansen: alleen nog producten die een open groot tekort aanpakken (als er zo een bestaat)
    final focus =
        open.isNotEmpty &&
        maxItems - round <= open.length &&
        pool.any((f) => !used.contains(f.ref) && _amounts(f).any((a) => open.any((k) => givesEnough(f, a.$1, k))));
    (Food, double, Portion?, double, NutrientMap)? best;
    var bestScore = 0.0;
    for (final f in pool) {
      // Niet twee keer hetzelfde voedingsmiddel (rauwe en gekookte spinazie)
      if (used.contains(f.ref) || used.contains(f.label?.food) || usedGroups.contains(kindOf(f))) continue;
      final v = withDerived(f.per100g);
      for (final (g, portion) in _amounts(f)) {
        final kcal = (v['energy'] ?? 0) * g / 100;
        if (kcal > budget || kcal > 500) continue;
        if (focus && !open.any((k) => givesEnough(f, g, k))) continue;
        var filled = 0.0, over = false;
        for (final k in keys) {
          final add = (v[k] ?? 0) * g / 100;
          if (add <= 0) continue;
          final t = targets[k]!;
          // Niet boven een bovengrens, en geen extreme hoeveelheden (bv. lever: vitamine A ver boven je doel)
          if ((t.upper != null && (now[k] ?? 0) + add > t.upper!) || (now[k] ?? 0) + add > t.goal! * 5) {
            over = true;
            break;
          }
          final weight = top.contains(k) ? 2.5 : 1.0;
          filled += weight * math.min(add * _absorbed(f, k) / t.goal!, remaining(k));
        }
        if (over || filled < 0.1) continue;
        // Wat energie is goed zolang er nog veel over is (tot 75% van wat over is)
        final aim = energyLeft * 0.75 - planned;
        final energy = aim > 0 && energyLeft > 0 ? math.min(kcal, aim) / energyLeft * 0.6 : 0.0;
        var score = (filled + energy) * (kcal > share ? share / kcal : 1);
        if (mine.contains(f.ref)) score *= 1.5;
        if (_organ.hasMatch(f.name)) score *= 0.6;
        if (f.source.european) score *= 1.1;
        // Wat in veel tabellen staat, is gewoner eten
        if ((f.label?.spread ?? 0) >= 6) score *= 1.1;
        if (score > bestScore) {
          bestScore = score;
          best = (f, g, portion, kcal, v);
        }
      }
    }
    if (best == null || bestScore < 0.12) break;
    final (f, g, portion, kcal, v) = best;
    final fills = <(Nutrient, double, double)>[];
    for (final k in keys) {
      final add = (v[k] ?? 0) * g / 100 * _absorbed(f, k);
      final t = targets[k]!.goal!;
      final b = (now[k] ?? 0) / t;
      if (add / t >= 0.1 && b < 1) fills.add((nutrientByKey[k]!, b, ((now[k] ?? 0) + add) / t));
    }
    fills.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
    for (final e in v.entries) {
      now[e.key] = (now[e.key] ?? 0) + e.value * g / 100 * _absorbed(f, e.key);
    }
    items.add(PlanItem(food: f, grams: g, portion: portion, kcal: kcal, fills: fills.take(3).toList()));
    used.add(f.ref);
    if (f.label != null) used.add(f.label!.food);
    if (kindOf(f) case final k?) usedGroups.add(k);
    budget -= kcal;
    planned += kcal;
  }
  if (items.isEmpty) return null;
  return GapPlan(items, before, completenessScore(now, targets));
}
