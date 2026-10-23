/// Zoekresultaten bundelen: hetzelfde voedingsmiddel uit verschillende landen (CIQUAL, Frida, CoFID, ...) wordt één
/// resultaat, met de beste bron vooraan en de andere onder "Andere bronnen".
library;

import 'dart:math' as math;

import '../data/food.dart';
import '../data/search_terms.dart';
import 'gap_plan.dart';

class FoodGroup {
  const FoodGroup(this.main, this.others);

  /// Wat je ziet: een Europese bron met zo veel mogelijk gemeten waarden.
  final Food main;

  /// Hetzelfde voedingsmiddel uit andere bronnen.
  final List<Food> others;
}

/// Gewogen mét afval (schil, pitten, graat, been): de waarden gelden per 100 g zoals gekocht, niet per 100 g die je
/// eet. Correct, maar een valkuil: zo'n banaan heeft 51 kcal per 100 g in plaats van 89.
final _weighedWith = RegExp(r'weighed with|as purchased|including (skin|bones?|pips|shell)', caseSensitive: false);

bool weighedWithWaste(Food f) => _weighedWith.hasMatch(f.name) || (f.label?.flags.contains('with bone') ?? false);

/// Kenmerken die niets aan de voedingswaarden veranderen en dus niet apart hoeven.
const _sameFlags = {'organic', 'brand'};

String _key(Food f) {
  final l = f.label;
  if (l == null) return f.ref;
  final flags = [
    for (final x in l.flags)
      if (!_sameFlags.contains(x)) x,
  ]..sort();
  return [l.food, l.group, l.part, l.state, l.dish ? 'dish' : '', ...flags].join('|');
}

/// Groepeert in de volgorde van [foods] (de zoekvolgorde): een groep staat waar zijn eerste lid stond.
List<FoodGroup> groupFoods(List<Food> foods) {
  final groups = <String, List<Food>>{};
  for (final f in foods) {
    groups.putIfAbsent(_key(f), () => []).add(f);
  }
  return [
    for (final members in groups.values)
      () {
        // Bij gelijke stand de zoekvolgorde (sort is niet stabiel)
        final best = [...members]..sort((a, b) => _better(a, b) != 0 ? _better(a, b) : members.indexOf(a) - members.indexOf(b));
        return FoodGroup(best.first, [...best.skip(1)]);
      }(),
  ];
}

/// Een bijzondere vorm van het gewone product: diepvries, gehakt, poeder, lactosevrij, "light" (P156).
final _variant = RegExp(
  r'\b(frozen|minced?|powder(ed)?|dried|dehydrated|concentrate|reduced|lactose[- ]?(free|reduced)|low lactose|flavou?red|long eggs|organic)\b',
  caseSensitive: false,
);

/// Beter = niet gewogen met afval, de gewone vorm (geen diepvries-ei of kipgehakt), Europees, meer gemeten (niet
/// geschatte) waarden; anders de zoekvolgorde.
int _better(Food a, Food b) {
  int score(Food f) =>
      (weighedWithWaste(f) ? 0 : 2000) +
      (_variant.allMatches(f.name).length * -300).clamp(-900, 0) +
      (f.source.european ? 500 : 0) +
      (f.per100g.length - f.estimated.length).clamp(0, 499);
  return score(b).compareTo(score(a));
}

/// Hoe goed een product past bij wat iemand typt of zegt, hoger = beter. Gedeeld door het zoekvak en Snel loggen
/// (P152), zodat "rijst", "griekse yoghurt" of "halfvolle melk" op beide plaatsen hetzelfde product bovenaan zet:
/// hele woorden, het gewone product (geen gerecht, poeder, diepvries of dieetvariant), en bij granen, pasta,
/// peulvruchten, vlees en eieren de bereide vorm. Eigen voorkeuren (eerder gekozen of gegeten) komen er los bij.
double foodQueryScore(Food f, String rawQuery) {
  final n = f.name.toLowerCase();
  final tokens = searchTokens(rawQuery);
  // Zowel wat je typte als de Engelse vertaling ("halfvolle melk" = "milk reduced fat") telt als "gevraagd"
  final query = '${rawQuery.toLowerCase()} ${tokens.join(' ')}';
  final queryWords = [
    for (final w in tokens)
      if (w.length > 1) w,
  ];
  var s = 0.0;
  // Hele woorden tellen: "egg" is geen eggplant, "cola" geen chocolate
  final head = n.split(',').first;
  for (final w in queryWords) {
    final stem = w.replaceAll(RegExp(r'(es|s)$'), '');
    final whole = RegExp('\\b${RegExp.escape(stem)}(es|s|ed)?\\b');
    if (whole.hasMatch(n)) {
      s += 4;
      if (whole.hasMatch(head)) s += 6;
    } else if (n.contains(stem)) {
      s -= 14;
    }
  }
  // Een woord dat alleen iets anders beschrijft ("spinach spaghetti", "quinoa pasta") is niet het product zelf
  final last = head.trim().split(RegExp(r'\s+')).last;
  if (queryWords.length == 1 && !last.startsWith(queryWords.first.replaceAll(RegExp(r'(es|s)$'), '')) && head.split(RegExp(r'\s+')).length > 1) {
    s -= 4;
  }
  // Elk extra woord maakt het een ander product ("batter pudding with semi-skimmed milk" is geen melk)
  const plain = {'raw', 'boiled', 'cooked', 'plain', 'whole', 'fresh', 'infusion', 'ready-to-drink', 'prepared', 'average', 'all', 'types'};
  final extra = head
      .split(RegExp(r'[\s/()-]+'))
      .where((w) => w.length > 2 && !plain.contains(w) && !query.contains(w.replaceAll(RegExp(r'(es|s)$'), '')));
  s -= math.min(9, extra.length * 1.5);
  // Een gerecht met het product erin, terwijl je het product zelf noemt
  if (RegExp(r'(w/|\b(with|in|sauce|pudding|pie|soup|salad|sandwich)\b)').hasMatch(n) &&
      !RegExp(r'\b(with|sauce|pudding|pie|soup|salad|sandwich)\b').hasMatch(query)) {
    s -= 10;
  }
  if (RegExp(r'\b(coated|breaded|battered|french|swedish)\b').hasMatch(n) && !RegExp(r'coat|bread|batter|french|swedish').hasMatch(query)) {
    s -= 12;
  }
  // Vleeswaren en kant-en-klare vormen alleen als je ze noemt
  if (RegExp(r'\b(roll|loaf|luncheon|deli|sliced|nuggets?|patty|patties|takeaway|prepacked)\b').hasMatch(n) &&
      !RegExp(r'roll|loaf|luncheon|deli|slice|nugget|patt|takeaway').hasMatch(query)) {
    s -= 10;
  }
  // "Whey" of "protein shake" is eiwitpoeder, geen wei
  if (RegExp(r'^whey$|protein').hasMatch(query.trim()) && n.contains('protein')) s += 15;
  // Een ingrediënt in plaats van wat je eet of drinkt: melkpoeder, concentraat, energiedrank (whey en eiwit zijn wel poeder)
  if (RegExp(r'\b(powder(ed)?|dry|dried|dehydrated|concentrate|bulk|energy drink)\b').hasMatch(n) &&
      !RegExp(r'powder|dry|dried|dehydrated|concentrate|bulk|energy|whey|protein|cocoa|spice|curry|paprika|cinnamon').hasMatch(query)) {
    s -= 25;
  }
  // Koffie en thee zijn de drank, niet gemalen bonen of bladeren
  if (RegExp(r'\b(coffee|tea|cocoa)\b').hasMatch(n) &&
      RegExp(r'\b(ground|grounds|beans?|leaves|leaf|instant|granules|dry)\b').hasMatch(n) &&
      !RegExp(r'ground|bean|lea[fv]|instant|granule').hasMatch(query)) {
    s -= 25;
  }
  // Cocktails en likeuren alleen als je ze noemt (koffie is geen Irish coffee)
  if (RegExp(r'\b(irish|liqueur|cocktail|with (rum|whisky|whiskey|brandy|vodka)|spiked)\b').hasMatch(n) &&
      !RegExp(r'irish|liqueur|cocktail|rum|whisk|brandy|vodka').hasMatch(query)) {
    s -= 30;
  }
  // Eieren zijn kippeneieren, tenzij je een ander ei noemt
  if (RegExp(r'\b(goose|duck|quail|turkey|emu|ostrich)\b').hasMatch(n) &&
      RegExp(r'\begg').hasMatch(n) &&
      !RegExp(r'goose|duck|quail|turkey|emu|ostrich').hasMatch(query)) {
    s -= 30;
  }
  // Bereid krijgt voorrang bij vlees, vis, granen, eieren en aardappelen; fruit en zuivel liefst zoals ze zijn
  final cookable = RegExp(
    r'\b(chicken|beef|pork|turkey|lamb|fish|salmon|cod|tuna|rice|pasta|spaghetti|noodles?|quinoa|potato(es)?|lentils?|beans?|egg|eggs|kip|rijst|vis|aardappel(en)?)\b',
  );
  if (cookable.hasMatch(n) && RegExp(r'\b(cooked|boiled|baked|grilled|roasted|steamed|whole)\b').hasMatch(n)) s += 12;
  if (RegExp(r'\b(fried|deep fried|candied|canned|syrup|chips|sweetened)\b').hasMatch(n) &&
      !RegExp(r'fried|candied|canned|syrup|chips|sweet').hasMatch(query)) {
    s -= 15;
  }
  if (!isEverydayFood(f) && !(n.contains('protein') && RegExp(r'whey|protein').hasMatch(query))) s -= 30;
  if (RegExp(r'\b(rice|pasta|spaghetti|noodles?|quinoa|lentils?|beans?|oats?|barley|couscous|bulgur)\b').hasMatch(n) &&
      RegExp(r'\b(raw|dry|uncooked)\b').hasMatch(n) &&
      !RegExp(r'\b(raw|dry|uncooked|rauw|droog)\b').hasMatch(query)) {
    s -= 30;
  }
  // "White" alleen bij eieren (eiwit): wit brood en witte rijst zijn gewoon de gewone
  if ((RegExp(r'\b(yolk|powder|dried|flour|substitute|frozen)\b').hasMatch(n) || (RegExp(r'\begg').hasMatch(n) && RegExp(r'\bwhite\b').hasMatch(n))) &&
      !query.contains(RegExp(r'yolk|white|powder|dried|flour|frozen|whey|protein'))) {
    s -= 15;
  }
  // Yoghurt, kwark of melk met een smaakje is niet de gewone
  final flavour = RegExp(r'\b(fruit|strawberry|raspberry|blueberry|cherry|peach|vanilla|flavou?r(ed)?|chocolate|honey|banana|lemon|mango)\b');
  if (flavour.hasMatch(n) && !flavour.allMatches(n).any((m) => query.contains(m[0]!.substring(0, 4)))) s -= 8;
  // Gezuurd, ingedikt of van een ander dier: een ander product dan de gewone melk of yoghurt
  if (RegExp(r"\b(cultured|fermented|condensed|evaporated|goat'?s?|sheep'?s?|ewe'?s?|buffalo)\b").hasMatch(n) &&
      !RegExp(r'cultur|ferment|condens|evapor|goat|sheep|ewe|buffalo|geit|schaap').hasMatch(query)) {
    s -= 10;
  }
  // Een merknaam in hoofdletters ("..., CHOBANI") als je geen merk noemt
  if (RegExp(r'\b[A-Z]{4,}\b').allMatches(f.name).any((m) => !query.contains(m[0]!.toLowerCase()))) s -= 8;
  // Gehakt, lactosevrij en andere bijzondere vormen alleen als je ze noemt (P156)
  if (RegExp(r'\b(minced?|ground (beef|meat|pork|turkey|chicken))\b').hasMatch(n) && !RegExp(r'minc|gehakt|ground').hasMatch(query)) s -= 15;
  if (RegExp(r'\blactose\b|\blow lactose\b').hasMatch(n) && !RegExp(r'lactos').hasMatch(query)) s -= 15;
  // Fastfood en restaurant alleen als je het noemt ("chicken" is geen fastfoodkip)
  if (RegExp(r'\b(fast food|restaurant|takeaway|take-away|drive-in)\b').hasMatch(n) && !RegExp(r'fast|restaurant|take').hasMatch(query)) s -= 15;
  // Brood is een gewoon brood (wit, bruin, volkoren), geen pita, bagel of panini tenzij je die noemt
  if (RegExp(r'\bbread\b').hasMatch(n) &&
      RegExp(r'\b(pitt?a|bagel|panini|naan|ciabatta|focaccia|brioche|rolls?|buns?|wraps?|tortilla|crumbs?|pudding|garlic|fried|croissant|chapati|matzo|soda|malt|fruit)\b').hasMatch(n) &&
      !RegExp(r'pitt?a|bagel|panini|naan|ciabatta|focaccia|brioche|roll|bun|wrap|tortilla|crumb|pudding|garlic|fried|croissant|chapati|matzo|soda|malt|fruit|broodje').hasMatch(query)) {
    s -= 10;
  }
  // Alleen "melk" of "kaas": de gewoonste soort (halfvolle melk; gouda, cheddar, edam, emmentaler)
  if (RegExp(r'^(milk|melk)$').hasMatch(rawQuery.trim().toLowerCase()) && RegExp(r'semi-skimmed|half-skimmed|\b1[.,]5 ?%').hasMatch(n)) s += 6;
  if (RegExp(r'^(cheese|kaas)$').hasMatch(rawQuery.trim().toLowerCase()) && RegExp(r'\b(gouda|cheddar|edam|emmenth?al(er)?)\b').hasMatch(n)) s += 6;
  // Bijproducten en merkproducten van ketens zijn zelden wat iemand bedoelt
  if (RegExp(r'\b(rendered|grease|drippings|skin only|by-products?)\b|(?<!%\s?)\bfat\b(?!\s*\d)')
          .hasMatch(n.replaceAll(RegExp(r'[\d.,]+\s*%\s*fat'), '')) &&
      !RegExp(r'fat|vet').hasMatch(query)) {
    s -= 20;
  }
  if (RegExp(r"^[A-Z0-9 &'.-]{4,},").hasMatch(f.name)) s -= 12;
  // Een zoekwoord dat alleen in een merk- of bedrijfsnaam staat ("cola" in THE COCA-COLA COMPANY)
  final plainName = f.name.replaceAll(RegExp(r"\b[A-Z][A-Z0-9&'.]+(?:-[A-Z0-9&'.]+)*\b"), ' ').toLowerCase();
  if (queryWords.any((w) => n.contains(w) && !plainName.contains(w))) s -= 12;
  // Orgaanvlees en dieetvarianten alleen als je ze zelf noemt
  if (RegExp(r'\b(liver|kidney|heart|gizzard|giblets|tongue|lever)\b').hasMatch(n) &&
      !RegExp(r'liver|kidney|heart|gizzard|tongue|lever').hasMatch(query)) {
    s -= 25;
  }
  if (RegExp(r'\b(gluten free|low fat|reduced|diet|light|sugar free|unsalted|low sodium)\b').hasMatch(n) &&
      !RegExp(r'gluten|low|reduced|diet|light|free|unsalted').hasMatch(query)) {
    s -= 10;
  }
  return s - n.length / 15;
}


/// Een energiedrank terwijl je die niet vraagt ("cola zero" is geen NOS Zero van The Coca-Cola Company, P151).
/// Zoekvak en Snel loggen laten die weg.
bool unaskedEnergyDrink(Food f, String query) =>
    RegExp(r'\benergy drink', caseSensitive: false).hasMatch(f.name) &&
    !RegExp(r'energ|\bnos\b|red ?bull|monster|rockstar|burn', caseSensitive: false).hasMatch(query);
