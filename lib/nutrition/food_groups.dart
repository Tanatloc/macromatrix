/// Zoekresultaten bundelen: hetzelfde voedingsmiddel uit verschillende landen (CIQUAL, Frida, CoFID, ...) wordt één
/// resultaat, met de beste bron vooraan en de andere onder "Andere bronnen".
library;

import 'dart:math' as math;

import '../data/food.dart';
import '../data/search_terms.dart';
import 'free_sugars.dart';
import 'gap_plan.dart';

class FoodGroup {
  const FoodGroup(this.main, this.others, {this.disagreeing = const {}});

  /// Wat je ziet: een Europese bron met zo veel mogelijk gemeten waarden.
  final Food main;

  /// Hetzelfde voedingsmiddel uit andere bronnen.
  final List<Food> others;

  /// Refs van bronnen die duidelijk afwijken van de andere (zie [disagreeingSources]); nooit [main] als er een
  /// bron is die wel overeenkomt.
  final Set<String> disagreeing;
}

/// Gewogen mét afval (schil, pitten, graat, been): de waarden gelden per 100 g zoals gekocht, niet per 100 g die je
/// eet. Correct, maar een valkuil: zo'n banaan heeft 51 kcal per 100 g in plaats van 89.
final _weighedWith = RegExp(r'weighed with|as purchased|including (skin|bones?|pips|shell)', caseSensitive: false);

bool weighedWithWaste(Food f) => _weighedWith.hasMatch(f.name) || (f.label?.flags.contains('with bone') ?? false);

/// Kenmerken die niets aan de voedingswaarden veranderen en dus niet apart hoeven.
const _sameFlags = {'organic', 'brand'};

/// Sleutel voor "hetzelfde product": voedingsmiddel, groep, deel, bereiding, gerecht en kenmerken (zonder label: de
/// ref zelf, dus nooit samen met iets anders).
String sameProductKey(Food f) => _key(f);

String _key(Food f) {
  final l = f.label;
  if (l == null) return f.ref;
  // "No added sugars" of "reduced sugar" in de naam is een ander product, ook als het label dat niet zegt: zo staat
  // muesli zonder suiker niet onder de gewone muesli (en omgekeerd)
  final flags = {
    for (final x in l.flags)
      if (!_sameFlags.contains(x)) x,
    if (noAddedSugarName.hasMatch(f.name)) 'unsweetened',
    if (lowSugarName.hasMatch(f.name)) 'reduced sugar',
  }.toList()..sort();
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
        // Een bron die afwijkt van de andere komt niet vooraan (eend zonder vel met 46,7 g eiwit tegenover 23–27 g)
        final off = _disagreeing(members);
        int order(Food a, Food b) {
          final agree = (off.contains(a.ref) ? 1 : 0) - (off.contains(b.ref) ? 1 : 0);
          if (agree != 0) return agree;
          final c = _better(a, b);
          // Bij gelijke stand de zoekvolgorde (sort is niet stabiel)
          return c != 0 ? c : members.indexOf(a) - members.indexOf(b);
        }

        final best = [...members]..sort(order);
        return FoodGroup(best.first, [...best.skip(1)], disagreeing: off);
      }(),
  ];
}

/// Hoofdwaarden die voor hetzelfde product in elke databank ongeveer gelijk moeten zijn, met de toegelaten factor
/// (zoals bij het Orakel): eiwit en koolhydraten 1,4×, energie, vet en water 1,6× (mager tegenover doorregen). Met
/// het kleinste verschil dat telt, zodat 0,2 tegenover 0,5 g koolhydraten in vlees geen "afwijking" is.
const _agreeKeys = {'protein': (1.4, 3.0), 'carbs': (1.4, 3.0), 'energy': (1.6, 40.0), 'fat': (1.6, 3.0), 'water': (1.6, 8.0)};

/// Bronnen in [foods] die duidelijk afwijken van de andere bronnen van hetzelfde product ([sameProductKey]): een
/// hoofdwaarde meer dan 1,4× of 1,6× boven of onder de mediaan van minstens twee andere bronnen. Meestal een
/// uitgedroogd of verkeerd gemeten product (Matvaretabellens gebraden eend en gans).
Set<String> disagreeingSources(Iterable<Food> foods) {
  final groups = <String, List<Food>>{};
  for (final f in foods) {
    groups.putIfAbsent(_key(f), () => []).add(f);
  }
  return {for (final members in groups.values) ..._disagreeing(members)};
}

Set<String> _disagreeing(List<Food> members) {
  if (members.length < 3) return const {};
  double? value(Food f, String k) => f.estimated.containsKey(k) ? null : f.per100g[k];
  double median(List<double> xs) {
    final s = [...xs]..sort();
    final m = s.length ~/ 2;
    return s.length.isOdd ? s[m] : (s[m - 1] + s[m]) / 2;
  }

  return {
    for (final f in members)
      if (_agreeKeys.entries.any((e) {
        final own = value(f, e.key);
        if (own == null) return false;
        final others = [
          for (final o in members)
            if (o.ref != f.ref) ?value(o, e.key),
        ];
        if (others.length < 2) return false;
        final (factor, minDiff) = e.value;
        bool off(double med) => (own - med).abs() >= minDiff && (own > factor * med || own * factor < med);
        // Ook tegenover de mediaan van de hele groep: bij drie bronnen trekt de uitschieter de mediaan van de andere
        // twee mee, en zou anders een gewone bron (23 g tegenover 25 en 46,7) zelf als afwijkend gelden
        return off(median(others)) && off(median([own, ...others]));
      }))
        f.ref,
  };
}

/// Een bijzondere vorm van het gewone product: diepvries, gehakt, poeder, lactosevrij, "light" (P156), voorgekookt
/// (parboiled rijst neemt kalk op uit het weekwater: 61 mg tegenover 6 à 10 mg), of uit een fastfoodzaak (frietjes van
/// de frituur thuis vóór die van een keten).
final _variant = RegExp(
  r'\b(frozen|minced?|powder(ed)?|dried|dehydrated|concentrate|reduced|lactose[- ]?(free|reduced)|low lactose|flavou?red|long eggs|organic|parboiled|pre-?boiled|easy[- ]cook|fast food|restaurant|takeaway)\b',
  caseSensitive: false,
);

/// Diepvries of gedroogd en daarna bereid ("frozen, deep-fried", "dried, boiled"): dan geen bijzondere vorm meer. Wel
/// nog als het omgekeerd is ("boiled, frozen" is een diepvries-ei).
final _prepared = RegExp(
  r'\b(frozen|dried)\b.*\b(boiled|cooked|(?<!pre-)fried|baked|roasted|grilled|reheated|oven[- ]heated|microwaved)\b',
  caseSensitive: false,
);

/// Melk met een EU-benaming waarbij het vetgehalte niet past (Verordening (EU) nr. 1308/2013, bijlage VII, deel IV):
/// magere melk hooguit 0,5 % vet, halfvolle melk 1,5 tot 1,8 %, volle melk minstens 3,5 % (met wat speling voor
/// afronding). Matvaretabellen noemt Noorse lettmelk (0,5 à 1,2 %) "semi-skimmed": die staat dan niet vooraan bij
/// "halfvolle melk", maar een melk met 1,5 % wel. Geldt voor elk product dat zo heet, niet voor één bepaalde melk.
bool offStandardMilk(Food f) {
  final fat = f.per100g['fat'];
  final n = f.name.toLowerCase();
  if (fat == null || f.label?.group != 'dairy' || !RegExp(r'\bmilk\b').hasMatch(n)) return false;
  if (RegExp(r'\b(semi|half|partially)[- ]skimmed\b').hasMatch(n)) return fat < 1.4 || fat > 1.9;
  if (RegExp(r'\bskimmed\b').hasMatch(n)) return fat > 0.6;
  if (RegExp(r'\bwhole\b').hasMatch(n) && !RegExp(r'\b(powder|dried|dry|condensed|evaporated)\b').hasMatch(n)) return fat < 3.4;
  return false;
}

/// Beter = niet gewogen met afval, de gewone vorm (geen diepvries-ei of kipgehakt), een vetgehalte dat bij de naam past
/// ([offStandardMilk]), de voorkeursbron ([FoodSource.priority]: CIQUAL/Frida/Matvaretabellen/Livsmedelsverket, dan
/// CoFID, dan USDA), meer gemeten (niet geschatte) waarden; anders de zoekvolgorde.
int _better(Food a, Food b) {
  int score(Food f) =>
      (weighedWithWaste(f) ? 0 : 2000) +
      // Zwaarder dan de bronvoorkeur (250 per stap) plus het aantal gemeten waarden
      (offStandardMilk(f) ? 0 : 600) +
      (_variant.allMatches(_prepared.hasMatch(f.name) ? f.name.replaceAll(RegExp(r'\b(frozen|dried)\b', caseSensitive: false), '') : f.name).length *
              -300)
          .clamp(-900, 0) +
      // Bronvoorkeur (zie FoodSource.priority) weegt zwaarder dan het aantal gemeten waarden (hooguit ~80)
      (3 - f.source.priority).clamp(0, 3) * 250 +
      (f.per100g.length - f.estimated.length).clamp(0, 249);
  return score(b).compareTo(score(a));
}

/// Wat iemand over suiker vraagt: [none] zonder toegevoegde suiker ("sugar free", "unsweetened", "zonder suiker"),
/// [low] minder suiker ("low sugar", "reduced sugar", "minder suiker").
enum SugarAsk { none, low }

/// Zo zegt iemand dat in een zoekopdracht (Engels en Nederlands), eventueel met "with"/"met" ervoor.
final _askNone = RegExp(
  r'\b((with|met) )?(sugar[- ]?free|sugarless|zero sugar|unsweetened|not sweetened|no (added )?sugars?( added)?|without (any )?(added )?sugars?|'
  r'(zonder|geen) (toegevoegde )?suikers?( toegevoegd)?|suikervrije?|ongezoete?)(?![a-zà-ÿ])',
);
final _askLow = RegExp(r'\b((with|met) )?((low|reduced|less|lower)[- ]sugars?|sugar[- ]reduced|(minder|weinig) suikers?|suikerarme?)(?![a-zà-ÿ])');

/// Een suikerwens is geen voedingsmiddel: "sugar free muesli" wordt ("muesli", [SugarAsk.none]) en "muesli zonder
/// toegevoegde suiker" ook. De overige woorden bepalen het voedingsmiddel, de wens alleen welke vorm bovenaan staat
/// (zie [foodQueryScore]). Zonder ander woord ("sugar free", "no added sugar") blijft de zoekopdracht zoals ze is.
(String, SugarAsk?) splitSugarAsk(String query) {
  final q = query.toLowerCase();
  for (final (re, ask) in [(_askNone, SugarAsk.none), (_askLow, SugarAsk.low)]) {
    if (!re.hasMatch(q)) continue;
    final rest = q
        .replaceAll(re, ' ')
        .replaceAll(RegExp(r'[\s,]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'^(with|met|and|en) |\s(with|met|and|en)$'), '')
        .trim();
    if (rest.isNotEmpty) return (rest, ask);
  }
  return (query, null);
}

/// Hoe goed een product past bij wat iemand typt of zegt, hoger = beter. Gedeeld door het zoekvak en Snel loggen
/// (P152), zodat "rijst", "griekse yoghurt" of "halfvolle melk" op beide plaatsen hetzelfde product bovenaan zet:
/// hele woorden, het gewone product (geen gerecht, poeder, diepvries of dieetvariant), en bij granen, pasta,
/// peulvruchten, vlees en eieren de bereide vorm. Eigen voorkeuren (eerder gekozen of gegeten) komen er los bij.
/// Een suikerwens ([sugar], of nog in [rawQuery]: zie [splitSugarAsk]) zet de vorm zonder of met minder suiker
/// vooraan; is die er niet, dan blijft het gewone product de beste.
double foodQueryScore(Food f, String rawQuery, {SugarAsk? sugar}) {
  if (sugar == null) (rawQuery, sugar) = splitSugarAsk(rawQuery);
  final full = sameSpelling(f.name.toLowerCase());
  // Bij een suikerwens is "no added sugars" in de naam geen dieetvariant of extra woord: dat telt hieronder apart
  final n = sugar == null ? full : full.replaceAll(noAddedSugarName, ' ').replaceAll(lowSugarName, ' ');
  // Waarin iets gekookt of gebakken is, maakt er geen gerecht of dieetvariant van ("boiled in unsalted water",
  // "fried in corn oil")
  final dish = n.replaceAll(RegExp(r'\bin (unsalted |salted )?water\b|\bin (\w+ )?oil\b|\bin (beef )?dripping\b'), '');
  // Diepvries of gedroogd, maar daarna bereid: dat is gewoon het bereide product (gekookte gedroogde spaghetti,
  // gefrituurde diepvriesfrietjes)
  final prepared = _prepared.hasMatch(n);
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
  // Samen één woord: "apple sauce" is "applesauce" (NF-8), geen ander product
  final compound = queryWords.length > 1 && RegExp('\\b${RegExp.escape(queryWords.join())}').hasMatch(n);
  var named = false;
  for (final w in queryWords) {
    final stem = w.replaceAll(RegExp(r'(es|s)$'), '');
    final whole = RegExp('\\b${RegExp.escape(stem)}(es|s|ed)?\\b');
    if (whole.hasMatch(n)) {
      if (w == queryWords.first) named = true;
      s += 4;
      if (whole.hasMatch(head)) s += 6;
    } else if (compound) {
      if (w == queryWords.first) named = true;
      s += 4;
      if (head.contains(queryWords.join())) s += 6;
    } else if (n.contains(stem)) {
      s -= 14;
    }
  }
  // Het eigenlijke product (het eerste zoekwoord) staat niet in de naam, en ook niet in de lokale naam: alleen
  // gevonden via een synoniem (NEVO: "spaghetti" bij "Pasta, wit, gekookt"). Dan gaat een product dat het wel in de
  // naam heeft voor.
  if (queryWords.isNotEmpty && !named) {
    final local = sameSpelling((f.localName ?? '').toLowerCase());
    final typed = rawQuery.toLowerCase().trim().split(RegExp(r'\s+')).first;
    final inLocal = [queryWords.first, typed].any((w) => w.length > 1 && RegExp('\\b${RegExp.escape(w)}').hasMatch(local));
    if (!inLocal) s -= 20;
  }
  // Een woord dat alleen iets anders beschrijft ("spinach spaghetti", "quinoa pasta") is niet het product zelf. Wat
  // tussen haakjes staat, telt niet ("Muesli (average)" is gewoon muesli).
  final last = head.replaceAll(RegExp(r'\([^)]*\)?'), ' ').trim().split(RegExp(r'\s+')).last;
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
  // Baked beans zitten altijd in tomatensaus en in blik: dat maakt er geen gerecht of conserve van (N15)
  final bakedBeans = RegExp(r'\bbaked beans?\b').hasMatch(query) && RegExp(r'\bbaked beans?\b|\bbeans, baked\b').hasMatch(n);
  if (RegExp(r'(w/|\b(with|in|sauce|pudding|pie|soup|salad|sandwich)\b)')
          .hasMatch(bakedBeans ? dish.replaceAll(RegExp(r'\bin tomato sauce\b'), '') : dish) &&
      !RegExp(r'\b(with|sauce|pudding|pie|soup|salad|sandwich)\b').hasMatch(query)) {
    s -= 10;
  }
  // Alleen de vulling: "doughnut filled w/ apple sauce" is geen appelmoes (NF-8)
  if (RegExp(r'\b(filled|stuffed)\b').hasMatch(n) && !RegExp(r'fill|stuff').hasMatch(query)) s -= 12;
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
  if (RegExp(r'\b(powder(ed)?|dry|dehydrated|concentrate|bulk|energy drink)\b|\bdried\b(?!.*\b(boiled|cooked)\b)').hasMatch(n) &&
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
  // Niet bij chips: "potato crisps, oven baked" is geen gebakken aardappel
  if (cookable.hasMatch(n) &&
      RegExp(r'\b(cooked|boiled|baked|grilled|roasted|steamed|whole)\b').hasMatch(n) &&
      !RegExp(r'\b(crisps?|chips)\b').hasMatch(n)) {
    s += 12;
  }
  // Rauw vlees, rauwe vis of rauwe vleeswaren alleen als je het zo noemt: "ham" of "bacon" op je bord is bereid, geen
  // rauwe hamlap (SU-5). Gerookt, gedroogd of gezouten heet niet "raw" en blijft gewoon staan.
  if (RegExp(r'\braw\b').hasMatch(n) &&
      const {'meat', 'poultry', 'processed meat', 'fish'}.contains(f.label?.group) &&
      !RegExp(r'\b(raw|rauw|uncooked|tartare|sushi|sashimi|carpaccio|ceviche|poke)\b').hasMatch(query)) {
    s -= 10;
  }
  // Frietjes zijn gefrituurd ("fries" vraagt dus wel om "fried" en "chips")
  if (RegExp(r'\b(fried|deep fried|candied|canned|syrup|chips|sweetened)\b').hasMatch(bakedBeans ? n.replaceAll('canned', '') : n) &&
      !RegExp(r'fried|fries|candied|canned|syrup|chips|sweet').hasMatch(query)) {
    s -= 15;
  }
  if (!isEverydayFood(f) && !(n.contains('protein') && RegExp(r'whey|protein').hasMatch(query))) s -= 30;
  if (RegExp(r'\b(rice|pasta|spaghetti|noodles?|quinoa|lentils?|beans?|oats?|barley|couscous|bulgur)\b').hasMatch(n) &&
      RegExp(r'\b(raw|dry|uncooked)\b').hasMatch(n) &&
      !RegExp(r'\b(raw|dry|uncooked|rauw|droog)\b').hasMatch(query)) {
    s -= 30;
  }
  // "White" alleen bij eieren (eiwit): wit brood en witte rijst zijn gewoon de gewone
  if ((RegExp(r'\b(yolk|powder|flour|substitute)\b').hasMatch(n) ||
          (!prepared && RegExp(r'\b(dried|frozen)\b').hasMatch(n)) ||
          (RegExp(r'\begg').hasMatch(n) && RegExp(r'\bwhite\b').hasMatch(n))) &&
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
      RegExp(
        r'\b(pitt?a|bagel|panini|naan|ciabatta|focaccia|brioche|rolls?|buns?|wraps?|tortilla|crumbs?|pudding|garlic|fried|croissant|chapati|matzo|soda|malt|fruit)\b',
      ).hasMatch(n) &&
      !RegExp(
        r'pitt?a|bagel|panini|naan|ciabatta|focaccia|brioche|roll|bun|wrap|tortilla|crumb|pudding|garlic|fried|croissant|chapati|matzo|soda|malt|fruit|broodje',
      ).hasMatch(query)) {
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
  final plainName = sameSpelling(f.name.replaceAll(RegExp(r"\b[A-Z][A-Z0-9&'.]+(?:-[A-Z0-9&'.]+)*\b"), ' ').toLowerCase());
  if (queryWords.any((w) => n.contains(w) && !plainName.contains(w))) s -= 12;
  // Orgaanvlees en dieetvarianten alleen als je ze zelf noemt
  if (RegExp(r'\b(liver|kidney|heart|gizzard|giblets|tongue|lever)\b').hasMatch(n) &&
      !RegExp(r'liver|kidney|heart|gizzard|tongue|lever').hasMatch(query)) {
    s -= 25;
  }
  // Met vel alleen als je het vraagt: kipfilet is zonder vel. "Met vel gegrild, alleen het vlees" is wel zonder vel.
  final withSkin =
      f.label?.part == 'muscle+skin' || (f.label?.flags.contains('with skin') ?? false) || RegExp(r'\b(with|and) skin\b|\bskin[- ]on\b').hasMatch(n);
  if (withSkin &&
      const {'poultry', 'meat', 'fish', 'processed meat'}.contains(f.label?.group ?? 'poultry') &&
      !RegExp(r'\b(meat|flesh) only\b|\bwithout skin\b|\bskinless\b').hasMatch(n) &&
      !RegExp(r'skin|\bvel\b').hasMatch(query)) {
    s -= 10;
  }
  // Verrijkt (extra vitaminen of ijzer) is niet de gewone vorm: "havermout" is gewone havervlokken
  if (RegExp(r'\b(enriched|fortified)\b').hasMatch(n) && !RegExp(r'enrich|fortif|verrijk').hasMatch(query)) s -= 6;
  if (RegExp(r'\b(gluten free|low fat|reduced|diet|light|sugar free|unsalted|low sodium)\b').hasMatch(dish) &&
      !RegExp(r'gluten|low|reduced|diet|light|free|unsalted').hasMatch(query)) {
    s -= 10;
  }
  if (sugar != null) {
    final none = noAddedSugarName.hasMatch(full) || (f.label?.flags.contains('unsweetened') ?? false);
    final low = lowSugarName.hasMatch(full);
    // "Low sugar" neemt ook "no added sugar", "sugar free" ook "reduced sugar" (maar minder graag)
    s += switch (sugar) {
      SugarAsk.none => none ? 16 : (low ? 8 : 0),
      SugarAsk.low => low ? 16 : (none ? 14 : 0),
    };
    // Met suiker, honing of siroop, terwijl je zonder of met minder vraagt: liever de gewone
    if (!none && !low && (RegExp(r'\b(sweetened|sugars?|honey|syrup|candied)\b').hasMatch(n) || (f.label?.flags.contains('sweetened') ?? false))) {
      s -= 8;
    }
  }
  return s - n.length / 15;
}

/// Een energiedrank terwijl je die niet vraagt ("cola zero" is geen NOS Zero van The Coca-Cola Company, P151).
/// Zoekvak en Snel loggen laten die weg.
bool unaskedEnergyDrink(Food f, String query) =>
    RegExp(r'\benergy drink', caseSensitive: false).hasMatch(f.name) &&
    !RegExp(r'energ|\bnos\b|red ?bull|monster|rockstar|burn', caseSensitive: false).hasMatch(query);

/// Een product zónder wat je vraagt: "protein bar" is geen kinderpap "milk protein free", "milk" geen melkvrije pap
/// (N15). Zoekvak en Snel loggen laten die weg, tenzij je zelf "free" of "vrij" typt.
bool unaskedFree(Food f, String query) {
  final q = query.toLowerCase();
  if (RegExp(r'free|vrij').hasMatch(q)) return false;
  final n = f.name.toLowerCase();
  return searchTokens(q).any((w) => w.length > 2 && RegExp('\\b${RegExp.escape(w)}[- ]?free\\b').hasMatch(n));
}
