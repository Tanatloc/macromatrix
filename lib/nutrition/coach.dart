/// Wekelijkse coach: de kleine samenvatting van je week die naar /api/coach gaat, en wat terugkomt.
///
/// Alleen cijfers die het weekrapport al berekent, plus de producten met de meeste energie als gewone namen, je
/// voorkeuren en allergieën als codes, een paar gewone voedingsmiddelen uit het Orakel die je tekorten aanvullen
/// ([CoachOption]) en de tips van vorige week met hoe die stoffen veranderden ([coachLastWeek]). Nooit je dagboek,
/// notities, namen of iets anders dat je zelf typte.
library;

import 'package:flutter/foundation.dart';

import '../data/food.dart';
import '../i18n.dart';
import 'allergens.dart';
import 'insights.dart' show stripKeys;
import 'nutrients.dart';
import 'preferences.dart';
import 'report.dart';

/// Vanaf zoveel volledig gelogde dagen biedt het weekrapport de coach aan (ook de server weigert minder).
const coachMinDays = 3;

/// Natrium en chloride onder je doel zijn geen tip waard: die haalt bijna iedereen ruim.
const _notLow = {'sodium', 'chloride'};

/// 'lactoseFree' → 'lactose_free'
String _snake(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

int _pct(double f) => (f * 100).round();

/// De stoffen waarvoor de coach voorstellen krijgt: de 3 vitaminen of mineralen die het verst onder je doel bleven, dan
/// eiwit en vezels als die onder je doel zaten, aangevuld tot 4 met de volgende vitamine of het volgende mineraal.
/// Hoogstens 5. [avg]: deel van het doel per stof (zie [WeeklyReport.avg]).
List<String> coachGapKeys(Map<String, double> avg) {
  final low = [
    for (final k in stripKeys)
      if (!_notLow.contains(k) && (avg[k] ?? 1) < 1) k,
  ]..sort((a, b) => avg[a]!.compareTo(avg[b]!));
  final macros = [
    for (final k in const ['protein', 'fiber'])
      if ((avg[k] ?? 1) < 1) k,
  ];
  final keys = [...low.take(3), ...macros];
  for (final k in low.skip(3)) {
    if (keys.length >= 4) break;
    keys.add(k);
  }
  return keys.take(5).toList();
}

/// Een voedingsmiddel dat een tekort aanvult, voor de coach: een gewone naam, een gewone portie en hoeveel van het
/// dagdoel die portie geeft.
@immutable
class CoachOption {
  const CoachOption({required this.food, required this.portion, required this.pct});
  final String food, portion;
  final int pct;

  Map<String, Object?> toJson() => {'food': food, 'portion': portion, 'pct': pct};
}

/// Wat geen gewoon basisvoedingsmiddel is voor een tip, ook al laat het Orakel het door (wild, orgaanvlees, dranken).
final _coachSkip = RegExp(
  r'\b(duck|horse|reindeer|hare|pigeon|snail|venison|pheasant|rabbit|octopus|crayfish|swordfish|guava|prickly pear|tamarind|passion fruit|lingonberry|acai|cocoa|liver|kidney saute|heart)\b',
);
const _coachSkipGroups = {'beverage', 'dish', 'offal', 'alcohol', 'supplement'};

/// Een gewone naam voor het voedingsmiddel ([FoodLabel.food], zonder merk) met de bereiding erbij als die iets zegt
/// ("spinach, boiled"), in het Nederlands als [nl]. Null zonder label, voor iets wat geen basisvoedingsmiddel is, of
/// in het Nederlands zonder vertaling (dan liever niets dan een Engelse naam in een Nederlandse vraag).
/// [anything]: ook gerechten, dranken en de rest (voor de vertaling van wat je at, niet voor een tip).
String? coachFoodName(Food f, {required bool nl, bool anything = false}) {
  final l = f.label;
  if (l == null) return null;
  if (!anything && (l.dish || _coachSkipGroups.contains(l.group) || _coachSkip.hasMatch(l.food))) return null;
  final special = '${l.food}|${l.part}';
  final String? base = nl ? (_foodNl[special] ?? _foodNl[l.food]) : (_foodEn.containsKey(special) ? _foodEn[special] : (_foodEn[l.food] ?? l.food));
  if (base == null) return null;
  // Noten en zaden zijn altijd gedroogd: dat hoeft er niet bij
  final dry = l.state == 'dried' && l.group == 'nut/seed';
  final state = dry ? null : (nl ? _stateNl[l.state] : (_stateSkipEn.contains(l.state) ? null : l.state));
  return state == null ? base : '$base, $state';
}

/// Een gewone portie voor [f] zoals het Orakel die kiest ([serving]), als "80 g" of "1 piece (120 g)". Gedroogd fruit
/// is een handvol (30 g), geen stuk van 150 g. In het Nederlands ([nl]) alleen een Nederlandse maat, anders het gewicht
/// (de porties uit de databanken zijn Engels).
Portion coachPortion(Food f, Portion serving, {bool nl = false}) {
  final l = f.label;
  final g = l?.group == 'fruit' && l?.state == 'dried' && serving.grams > 40 ? 30.0 : serving.grams;
  final grams = '${g.round()} g';
  if (g != serving.grams) return Portion(grams, g);
  // Zonder de "≈ 120 g" of "(30 g)" die er al in staat
  final label = serving.label.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
  // "80 g serving", "portie van 80 g": gewoon het gewicht
  if (RegExp(r'\d\s*(g|ml)\b').hasMatch(label) || label.isEmpty || label.length > 18) return Portion(grams, g);
  if (nl && !RegExp(r'^\d+ (stuk|stuks|portie|sneetje|sneetjes|kom|glas|handvol|schep|eetlepel|kopje)$').hasMatch(label)) {
    return Portion(grams, g);
  }
  return Portion('$label ($grams)', g);
}

/// De portie waar het Orakel op terugvalt als het niets beters weet (100 g): voor een tip geen gewone portie
/// ("100 g roomkaas", "100 g miso").
bool isFallbackServing(Portion p) => p.grams == 100 && RegExp(r'^(100 g serving|portie van 100 g)$').hasMatch(p.label);

/// De tips van vorige week en hoe de stoffen veranderden, of null zonder samenvatting van vorige week. De stoffen zijn
/// die waar de tips van vorige week op mikten ([CoachResult.focus]), anders de tekorten van vorige week.
Map<String, Object?>? coachLastWeek(WeeklyReport r, CoachResult? previous) {
  if (previous == null) return null;
  final keys = previous.focus.isNotEmpty ? previous.focus : coachGapKeys(r.prevAvg);
  final changes = [
    for (final k in keys.take(5))
      if (nutrientByKey[k] != null && r.prevAvg[k] != null && r.avg[k] != null)
        {'nutrient': nutrientByKey[k]!.name, 'before_pct': _pct(r.prevAvg[k]!), 'now_pct': _pct(r.avg[k]!)},
  ];
  return {
    'tips': [for (final t in previous.tips.take(3)) t.length > 200 ? t.substring(0, 200) : t],
    'changes': changes,
  };
}

/// De samenvatting van [r] voor /api/coach. [options]: per stof (sleutel) een paar voedingsmiddelen
/// (zie AppState.coachOptions); [lastWeek] uit [coachLastWeek].
Map<String, Object?> coachWeek(
  WeeklyReport r, {
  Set<DietPref> diet = const {},
  Set<Allergen> allergies = const {},
  String? lang,
  Map<String, List<CoachOption>> options = const {},
  Map<String, Object?>? lastWeek,
}) {
  Map<String, Object?>? macro(String k) {
    final f = r.avg[k], g = r.goals[k];
    if (f == null || g == null || g <= 0) return null;
    return {'avg': (f * g).round(), 'goal': g.round()};
  }

  // De vitaminen en mineralen die het verst onder je doel bleven
  final low = [
    for (final k in stripKeys)
      if (!_notLow.contains(k) && (r.avg[k] ?? 1) < 1) MapEntry(k, r.avg[k]!),
  ]..sort((a, b) => a.value.compareTo(b.value));
  // Wat gemiddeld boven een veilige bovengrens zat
  final high = [
    for (final e in r.upperShare.entries)
      if (e.value > 1 && nutrientByKey.containsKey(e.key)) e,
  ]..sort((a, b) => b.value.compareTo(a.value));

  final t = r.weightTrend;
  final change = r.weightChange ?? t?.change;
  final trend = t == null
      ? null
      : (t.stable
            ? 'stable'
            : switch (t.direction) {
                -1 => 'down',
                1 => 'up',
                _ => null,
              });

  return {
    'v': 1,
    'lang': lang ?? (isNl ? 'nl' : 'en'),
    'days': r.days,
    'score': r.score,
    'goal': r.plan.name,
    if (r.kcalAvg != null && r.kcalGoal != null) 'energy': {'avg': r.kcalAvg!.round(), 'goal': r.kcalGoal!.round()},
    'macros': {
      for (final k in const ['protein', 'carbs', 'fat', 'fiber']) k: ?macro(k),
    },
    'low': [
      for (final e in low.take(5)) {'key': e.key, 'name': nutrientByKey[e.key]!.name, 'pct': _pct(e.value)},
    ],
    'high': [
      for (final e in high.take(5)) {'key': e.key, 'name': nutrientByKey[e.key]!.name, 'pct': _pct(e.value)},
    ],
    if (change != null || trend != null) 'weight': {if (change != null) 'change_kg': double.parse(change.toStringAsFixed(1)), 'trend': ?trend},
    'foods': r.topFoods.take(5).toList(),
    'diet': [for (final d in diet) _snake(d.name)],
    'allergies': [for (final a in allergies) a.name],
    if (options.isNotEmpty)
      'options': {
        for (final e in options.entries)
          if (e.value.isNotEmpty && nutrientByKey[e.key] != null) nutrientByKey[e.key]!.name: [for (final o in e.value.take(4)) o.toJson()],
      },
    'last_week': ?lastWeek,
  };
}

/// Wat de coach schreef.
@immutable
class CoachResult {
  const CoachResult({required this.summary, required this.tips, this.lang = 'en', this.focus = const [], this.model});
  final String summary;
  final List<String> tips;

  /// De taal waarin de tekst geschreven is ('en' of 'nl'), ook na een taalwissel in de app.
  final String lang;

  /// Het model dat de tekst schreef (voor een melding), null bij een oudere bewaarde tekst.
  final String? model;

  /// De stoffen waarvoor de app voorstellen meestuurde (sleutels), alleen op dit toestel: zo weet de coach volgende
  /// week waar de tips op mikten.
  final List<String> focus;

  CoachResult withFocus(List<String> focus) => CoachResult(summary: summary, tips: tips, lang: lang, focus: focus, model: model);

  static CoachResult? fromJson(Object? j) {
    if (j is! Map || j['summary'] is! String || j['tips'] is! List) return null;
    final summary = (j['summary'] as String).trim();
    final tips = [
      for (final t in j['tips'] as List)
        if (t is String && t.trim().isNotEmpty) t.trim(),
    ];
    if (summary.isEmpty || tips.isEmpty) return null;
    return CoachResult(
      summary: summary,
      tips: tips.take(3).toList(),
      lang: j['lang'] == 'nl' ? 'nl' : 'en',
      model: j['model'] is String && (j['model'] as String).length <= 100 ? j['model'] as String : null,
      focus: [
        for (final k in (j['focus'] as List?) ?? const [])
          if (k is String) k,
      ],
    );
  }

  Map<String, Object?> toJson() => {'summary': summary, 'tips': tips, 'lang': lang, if (focus.isNotEmpty) 'focus': focus, 'model': ?model};
}

/// Bereidingen die in een Engelse naam niets toevoegen.
const _stateSkipEn = {'raw', 'not applicable', 'fresh', 'frozen', 'chilled', 'fermented', 'prepared', 'whole', 'cured'};

/// Bereidingen in het Nederlands; wat hier niet staat, valt weg.
const _stateNl = {
  'boiled': 'gekookt',
  'cooked': 'gekookt',
  'steamed': 'gestoomd',
  'stewed': 'gestoofd',
  'roasted': 'geroosterd',
  'grilled': 'gegrild',
  'baked': 'uit de oven',
  'fried': 'gebakken',
  'poached': 'gepocheerd',
  'dried': 'gedroogd',
  'canned': 'uit blik',
  'smoked': 'gerookt',
  'pickled': 'ingelegd',
};

/// Engelse namen die anders moeten dan [FoodLabel.food] (null: niet als tip).
const _foodEn = <String, String?>{
  'almond': 'almonds',
  'hazelnut': 'hazelnuts',
  'walnut': 'walnuts',
  'cashew': 'cashews',
  'brazil nut': 'brazil nuts',
  'pistachio nut': 'pistachios',
  'pine nut': 'pine nuts',
  'peanut': 'peanuts',
  'kidney bean': 'kidney beans',
  'white bean': 'white beans',
  'black bean': 'black beans',
  'chickpea': 'chickpeas',
  'lentil': 'lentils',
  'soybean': 'soybeans',
  'pea': 'peas',
  'prune': 'prunes',
  'olive': 'olives',
  'grape': 'grapes',
  'strawberry': 'strawberries',
  'blueberry': 'blueberries',
  'raspberry': 'raspberries',
  'mussel': 'mussels',
  'oyster': 'oysters',
  'sardine': 'sardines',
  'brussels sprout': 'brussels sprouts',
  'button mushroom': 'mushrooms',
  'mushroom': 'mushrooms',
  'sunflower|seed': 'sunflower seeds',
  'pumpkin|seed': 'pumpkin seeds',
  'chia|seed': 'chia seeds',
  'sesame seed|seed': 'sesame seeds',
  'sesame seed|kernel': 'sesame seeds',
  'poppy seed|seed': 'poppy seeds',
  'broccoli|sprout': 'broccoli sprouts',
  'soybean|sprout': 'soybean sprouts',
  'mung bean|sprout': 'bean sprouts',
  'pea|sprout': null,
  'sweet potato|leaf': null,
  'tamarind|leaf': null,
};

/// [FoodLabel.food] (of food|deel) in het Nederlands, voor de voedingsmiddelen die het Orakel als advies geeft.
const _foodNl = <String, String>{
  'sunflower|seed': 'zonnebloempitten',
  'pumpkin|seed': 'pompoenpitten',
  'chia|seed': 'chiazaad',
  'broccoli|sprout': 'broccolischeuten',
  'soybean|sprout': 'sojascheuten',
  'mung bean|sprout': 'taugé',
  'pumpkin|fruit': 'pompoen',
  'almond': 'amandelen',
  'anchovy': 'ansjovis',
  'apple': 'appel',
  'apricot': 'abrikozen',
  'artichoke': 'artisjok',
  'asparagus': 'asperges',
  'avocado': 'avocado',
  'banana': 'banaan',
  'beef': 'rundvlees',
  'beetroot': 'rode biet',
  'bell pepper': 'paprika',
  'black bean': 'zwarte bonen',
  'blackberry': 'bramen',
  'blackcurrant': 'zwarte bessen',
  'blueberry': 'blauwe bessen',
  'blue cheese': 'blauwe kaas',
  'brazil nut': 'paranoten',
  'bread roll': 'broodje',
  'brie cheese': 'brie',
  'broccoli': 'broccoli',
  'brussels sprout': 'spruitjes',
  'buckwheat': 'boekweit',
  'button mushroom': 'champignons',
  'cabbage': 'kool',
  'camembert cheese': 'camembert',
  'carrot': 'wortelen',
  'cashew': 'cashewnoten',
  'cauliflower': 'bloemkool',
  'celeriac': 'knolselder',
  'celery': 'selder',
  'chanterelle': 'cantharellen',
  'cheddar cheese': 'cheddar',
  'cheese': 'kaas',
  'chicken': 'kip',
  'chickpea': 'kikkererwten',
  'cod': 'kabeljauw',
  'cottage cheese': 'cottage cheese',
  'cow milk': 'melk',
  'milk': 'melk',
  'cream cheese': 'roomkaas',
  'cucumber': 'komkommer',
  'date': 'dadels',
  'duck': 'eend',
  'edamame': 'edamame',
  'egg': 'ei',
  'egg noodles': 'eiernoedels',
  'eggplant': 'aubergine',
  'endive': 'andijvie',
  'feta cheese': 'feta',
  'fig': 'vijgen',
  'flaxseed': 'lijnzaad',
  'garden cress': 'tuinkers',
  'garlic': 'look',
  'goat cheese': 'geitenkaas',
  'goat milk': 'geitenmelk',
  'gouda cheese': 'goudse kaas',
  'grana padano cheese': 'grana padano',
  'grape': 'druiven',
  'gruyere cheese': 'gruyère',
  'haddock': 'schelvis',
  'halibut': 'heilbot',
  'hazelnut': 'hazelnoten',
  'herring': 'haring',
  'kale': 'boerenkool',
  'kidney bean': 'kidneybonen',
  'kiwi': 'kiwi',
  'lamb': 'lamsvlees',
  'leek': 'prei',
  'lemon': 'citroen',
  'lemon sole': 'tongschar',
  'lentil': 'linzen',
  'lettuce': 'sla',
  'lobster': 'kreeft',
  'mackerel': 'makreel',
  'millet': 'gierst',
  'miso': 'miso',
  'mixed nuts': 'gemengde noten',
  'mixed vegetables': 'gemengde groenten',
  'mozzarella cheese': 'mozzarella',
  'mushroom': 'paddenstoelen',
  'mussel': 'mosselen',
  'oat': 'havermout',
  'okra': 'okra',
  'olive': 'olijven',
  'omelette': 'omelet',
  'orange': 'sinaasappel',
  'oyster': 'oesters',
  'pangasius': 'pangasius',
  'parmesan cheese': 'parmezaan',
  'parsnip': 'pastinaak',
  'pasta': 'pasta',
  'pea': 'erwten',
  'peach': 'perzik',
  'peanut': "pinda's",
  'peanut butter': 'pindakaas',
  'pear': 'peer',
  'pine nut': 'pijnboompitten',
  'pineapple': 'ananas',
  'pistachio nut': 'pistachenoten',
  'pita bread': 'pitabrood',
  'plaice': 'schol',
  'poppy seed': 'maanzaad',
  'pork': 'varkensvlees',
  'potato': 'aardappelen',
  'prune': 'pruimen',
  'quark': 'kwark',
  'quinoa': 'quinoa',
  'radicchio': 'radicchio',
  'rainbow trout': 'regenboogforel',
  'raisin': 'rozijnen',
  'raspberry': 'frambozen',
  'rice': 'rijst',
  'rocket': 'rucola',
  'rolled oats': 'havermout',
  'rusk': 'beschuit',
  'rye': 'rogge',
  'salmon': 'zalm',
  'sardine': 'sardientjes',
  'sesame seed': 'sesamzaad',
  'shallot': 'sjalot',
  'shiitake mushroom': 'shiitake',
  'shrimp': 'garnalen',
  'soy drink': 'sojadrink',
  'soybean': 'sojabonen',
  'spinach': 'spinazie',
  'sprat': 'sprot',
  'squid': 'inktvis',
  'strawberry': 'aardbeien',
  'sweet potato|root': 'zoete aardappel',
  'sweetcorn': 'maïs',
  'swiss chard': 'snijbiet',
  'tempeh': 'tempeh',
  'tofu': 'tofu',
  'tomato': 'tomaat',
  'tortilla': 'tortilla',
  'trout': 'forel',
  'tuna': 'tonijn',
  'turbot': 'tarbot',
  'turkey': 'kalkoen',
  'veal': 'kalfsvlees',
  'walnut': 'walnoten',
  'watercress': 'waterkers',
  'white bean': 'witte bonen',
  'wholemeal bread': 'volkorenbrood',
  'wholewheat pasta': 'volkorenpasta',
  'yoghurt': 'yoghurt',
  'zucchini': 'courgette',
  // Wat je vaak eet maar niet als tip krijgt: alleen om de namen van je meest gegeten producten te vertalen
  'bread': 'brood',
  'white bread': 'wit brood',
  'baguette': 'stokbrood',
  'muesli': 'muesli',
  'granola': 'granola',
  'cornflakes': 'cornflakes',
  'spaghetti bolognese': 'spaghetti bolognaise',
  'bolognese sauce': 'bolognaisesaus',
  'lasagne': 'lasagne',
  'pizza': 'pizza',
  'soup': 'soep',
  'french fries': 'frietjes',
  'fries': 'frietjes',
  'sweet potato fries': 'zoete-aardappelfrietjes',
  'crisps': 'chips',
  'chocolate': 'chocolade',
  'butter': 'boter',
  'olive oil': 'olijfolie',
  'sugar': 'suiker',
  'honey': 'honing',
  'jam': 'confituur',
  'coffee': 'koffie',
  'tea': 'thee',
  'beer': 'bier',
  'wine': 'wijn',
  'orange juice': 'sinaasappelsap',
  'apple juice': 'appelsap',
  'cola': 'cola',
  'biscuit': 'koekjes',
  'cookie': 'koekjes',
  'croissant': 'croissant',
  'cake': 'cake',
  'ice cream': 'ijs',
  'mayonnaise': 'mayonaise',
  'hamburger': 'hamburger',
  'sausage': 'worst',
  'ham': 'ham',
  'bacon': 'spek',
  'minced beef': 'rundergehakt',
  'minced meat': 'gehakt',
  'cow cream': 'room',
};
