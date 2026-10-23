/// Vrije suikers (≈ WHO "free sugars"): toegevoegde suikers plus suikers uit honing, siropen en vruchtensap.
/// Suikers in heel fruit, groenten, peulvruchten en gewone melk of yoghurt tellen niet mee: die horen bij het
/// voedingsmiddel zelf. Een appel telt dus niet mee voor je suikermaximum, een glas appelsap wel (P183).
///
/// De databanken geven alleen het totaal aan suikers. Dit is een schatting op basis van het label van het product
/// (ingebouwde databank) of, zonder label, van de naam.
library;

import '../data/food.dart';
import 'values.dart';

/// Groepen waarvan de suikers bij het voedingsmiddel zelf horen (zolang het geen sap, jam of gezoete vorm is).
const _wholeGroups = {'fruit', 'vegetable', 'legume', 'potato/tuber', 'mushroom'};

/// Vormen van fruit en groenten waarvan de suikers wél vrij zijn: sap, concentraat, jam, siroop.
const _freeParts = {'juice', 'concentrate', 'jam', 'syrup'};

/// Lactose per 100 g in melk en yoghurt: dat deel van de suikers in gezoete zuivel is niet vrij.
const _lactosePer100g = 4.5;

/// Woorden die op toegevoegde suiker of sap wijzen (Engels, Nederlands, Frans). Bewust zonder \b vooraan:
/// Nederlandse samenstellingen als "appelsap" of "chocoladerepen" moeten ook tellen.
final _addedName = RegExp(
  r'(juice|\bjus\b|sap\b|sapje|smoothie|nectar\b|syrup|siroop|sirop|honey|honing|\bmiel\b|\bjam\b|jelly|confiture|marmalade|'
  r'compote|sweeten|gezoet|sugar|suiker|sucre|candied|gekonfijt|chocola|choco|cocoa|cacao|caramel|karamel|'
  r'cola|soda|lemonade|limonade|frisdrank|ice ?tea|candy|snoep|cake|cookie|koek|biscuit|dessert|pudding|\bvla\b|'
  r'\bpie\b|taart|\btart|crumble|muffin|pastry|gebak|granola|muesli|cereal|\bbars?\b|reep|'
  r'condensed|gecondenseerd|milkshake|\bijs\b|ice cream)',
  caseSensitive: false,
);

/// Een smaakje in zuivel ("aardbeienyoghurt", "vanillekwark"): daar zit bijna altijd suiker bij.
final _flavourName = RegExp(
  r'(vanill|flavou?r|smaak|\bfruit|vruchten|aardbei|strawberr|framboos|raspberr|perzik|peach|kers|cherry|mango|banan|'
  r'berr|bosbes|bessen|lemon|citroen|honey|stracciatella|mokka|mocha|coffee|koffie)',
  caseSensitive: false,
);

/// Zinnen die op het tegendeel wijzen: fruit in eigen sap, zonder suiker, "sweet potato".
final _notSweet = RegExp(
  r'in (its own |eigen )?(juice|sap)|unsweetened|ongezoet|no added sugars?|no sugars? added|sugars? not added|without (added )?sugars?|sugar[- ]?free|'
  r'zonder (toegevoegde )?suikers?|suikervrij|sans sucres? ajoutés?|sweet ?potato(es)?|zoete aardappel(en)?|sweet ?corn|'
  r'sweet peppers?|zoete paprika|sugar[- ]?snap|sugar peas?|honeydew|honeycrisp|nectarine|in tomato juice|'
  r'(gooseberries|apples?|pears?|plums?), dessert',
  caseSensitive: false,
);

/// Gewoon fruit, groenten en peulvruchten (Engels en Nederlands), voor eigen producten zonder label.
final _produceWord = RegExp(
  r'^(apples?|appels?|pears?|peren|peer|oranges?|sinaasappels?|mandarins?|mandarijnen?|clementines?|grapes?|druif|druiven|'
  r'strawberr(y|ies)|aardbei(en)?|raspberr(y|ies)|framboos|frambozen|blueberr(y|ies)|bes|bessen|berries|kiwis?|mangos?|mangoes|'
  r'pineapples?|ananas|peach(es)?|perziken?|plums?|pruim(en)?|cherr(y|ies)|kers(en)?|melons?|meloenen?|watermelons?|watermeloen|'
  r'apricots?|abrikoos|abrikozen|bananas?|banaan|bananen|avocados?|lemons?|citroenen?|grapefruits?|figs?|vijgen|'
  r'tomato(es)?|tomaten|tomaat|carrots?|wortels?|wortelen|cucumbers?|komkommers?|peppers?|paprikas?|onions?|uien|ui|'
  r'broccoli|spinach|spinazie|lettuce|sla|cabbage|kool|beets?|beetroots?|biet|bieten|pumpkins?|pompoen|'
  r'courgettes?|zucchini|aubergines?|eggplants?|cauliflower|bloemkool|leeks?|prei|celery|selder|asparagus|asperges|'
  r'mushrooms?|champignons?|potato(es)?|aardappel(en|s)?|beans?|bonen|lentils?|linzen|chickpeas?|kikkererwten|peas|erwten|'
  r'vegetables?|groenten?|fruit|fruits)$',
);

/// Woorden die niets veranderen aan "gewoon fruit of groente": bereiding, kleur, maat.
const _fillers = {
  'raw', 'rauw', 'fresh', 'vers', 'verse', 'organic', 'bio', 'plain', 'whole', 'heel', 'hele', 'cooked', 'gekookt', 'boiled',
  'steamed', 'gestoomd', 'roasted', 'geroosterd', 'baked', 'frozen', 'diepvries', 'sliced', 'gesneden', 'peeled', 'geschild',
  'with', 'without', 'met', 'zonder', 'skin', 'schil', 'red', 'rode', 'rood', 'green', 'groene', 'groen', 'yellow', 'gele',
  'white', 'witte', 'black', 'zwarte', 'blue', 'blauwe', 'sweet', 'zoete', 'baby', 'mini', 'cherry', 'cocktail', 'kidney',
  'and', 'en', 'mixed', 'gemengde', 'g', 'gr', 'kg', 'stuk', 'piece', 'medium', 'large', 'small', 'groot', 'grote', 'klein',
  'kleine', 'jonge', 'canned', 'blik', 'in', 'water', 'brine', 'pekel', 'own', 'eigen', 'juice', 'sap', 'its',
};

/// De naam is duidelijk gewoon fruit, groente of peulvruchten: alle overige woorden horen in [_produceWord].
bool _plainProduceName(String name) {
  final words = [
    for (final w in name.toLowerCase().split(RegExp(r"[^a-zà-ÿ']+")))
      if (w.isNotEmpty && !_fillers.contains(w)) w,
  ];
  return words.isNotEmpty && words.every(_produceWord.hasMatch);
}

/// Gewone melk, yoghurt en kwark, voor eigen producten zonder label.
final _plainDairy = RegExp(
  r'(milk|melk|yog(h)?o?urt|kwark|quark|skyr|kefir|karnemelk|buttermilk|cottage cheese|hüttenkäse|fromage blanc|cheese|kaas)',
  caseSensitive: false,
);

final _milkDrink = RegExp(
  r'^(?!.*\bchai\b).*(latte|capp?uc+ino|cortado|flat white|macchiato|au lait|koffie verkeerd|'
  r'(coffee|tea|koffie|thee),? (with|met) (\w+ )?(milk|melk))',
  caseSensitive: false,
);

bool _added(String s) => _addedName.hasMatch(s.replaceAll(_notSweet, ' '));
bool _flavoured(String s) => _flavourName.hasMatch(s.replaceAll(_notSweet, ' '));

/// Vrije suikers in gram per 100 g, of null als het product geen suikers vermeldt.
double? freeSugarsPer100g(NutrientMap per100g, {FoodLabel? label, required String name}) {
  final sugars = per100g['sugars'];
  if (sugars == null) return null;
  if (sugars <= 0) return 0;
  return sugars * _freeShare(label, name, sugars);
}

/// Welk deel (0–1) van de suikers vrij is.
double _freeShare(FoodLabel? l, String name, double sugarsPer100g) {
  // Melk of yoghurt met suiker: de lactose blijft niet-vrij, de rest is toegevoegd
  double sweetDairy() => ((sugarsPer100g - _lactosePer100g) / sugarsPer100g).clamp(0, 1);
  final unsweetened = _notSweet.hasMatch(name) && !_added(name);

  if (l == null) {
    // Eigen product of merkproduct zonder label: alles vrij, tenzij de naam duidelijk gewoon fruit, groente of melk is
    if (_plainDairy.hasMatch(name) && !RegExp('cream|room|ijs', caseSensitive: false).hasMatch(name)) {
      return _added(name) || _flavoured(name) ? sweetDairy() : 0;
    }
    if (!_added(name) && _plainProduceName(name)) return 0;
    return 1;
  }
  // "No sugar added" in de naam weegt zwaarder dan een label dat het product als gezoet ziet
  final sweetened = (l.flags.contains('sweetened') || l.flags.contains('in syrup')) && !unsweetened;
  final plain = l.flags.contains('unsweetened') || unsweetened;
  if (_wholeGroups.contains(l.group)) {
    if (sweetened || _freeParts.contains(l.part)) return 1;
    // Compote en moes: meestal met suiker, behalve als er uitdrukkelijk "zonder suiker" bij staat
    if (l.part == 'puree' && l.group == 'fruit' && !plain) return 1;
    if (!plain && _added('${l.food} $name')) return 1;
    return 0;
  }
  // Koffie of thee met melk: de lactose is niet vrij, zolang er geen suiker of smaakje bij zit
  if (l.group == 'beverage' && _milkDrink.hasMatch(name) && !sweetened && !_added(name) && !_flavoured(name)) return 0;
  if (l.group == 'dairy') {
    if (sweetened || ((_added('${l.food} $name') || _flavoured(l.food) || _flavoured(name)) && !plain)) return sweetDairy();
    return 0;
  }
  return 1;
}

/// Voedingswaarden per 100 g met de vrije suikers erbij (als ze er nog niet waren).
NutrientMap withFreeSugars(NutrientMap per100g, {FoodLabel? label, required String name}) {
  if (per100g.containsKey('free_sugars')) return per100g;
  final free = freeSugarsPer100g(per100g, label: label, name: name);
  return free == null ? per100g : {...per100g, 'free_sugars': free};
}
