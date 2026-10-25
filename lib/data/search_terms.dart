/// Nederlandse zoektermen vertalen naar de Engelse namen in de USDA-database.
///
/// Zo vindt "banaan" ook "Bananas, raw". Woorden die hier niet staan, worden ongewijzigd gezocht.
library;

const _nlToEn = <String, String>{
  // Fruit
  'appel': 'apple', 'appels': 'apple', 'peer': 'pear', 'peren': 'pear', 'banaan': 'banana', 'bananen': 'banana',
  'sinaasappel': 'orange', 'sinaasappels': 'orange', 'mandarijn': 'tangerine', 'citroen': 'lemon', 'limoen': 'lime',
  'grapefruit': 'grapefruit', 'druif': 'grape', 'druiven': 'grape', 'aardbei': 'strawberr', 'aardbeien': 'strawberr',
  'framboos': 'raspberr', 'frambozen': 'raspberr', 'bosbes': 'blueberr', 'bosbessen': 'blueberr', 'blauwe bes': 'blueberr',
  'braambes': 'blackberr', 'bramen': 'blackberr', 'kers': 'cherr', 'kersen': 'cherr', 'pruim': 'plum', 'pruimen': 'plum',
  'perzik': 'peach', 'abrikoos': 'apricot', 'ananas': 'pineapple', 'meloen': 'melon', 'watermeloen': 'watermelon',
  'dadel': 'date', 'dadels': 'date', 'vijg': 'fig', 'vijgen': 'fig', 'rozijn': 'raisin', 'rozijnen': 'raisin',
  'granaatappel': 'pomegranate', 'kokos': 'coconut', 'kokosnoot': 'coconut',
  // Groenten
  'aardappel': 'potato', 'aardappelen': 'potato', 'zoete aardappel': 'sweet potato', 'wortel': 'carrot', 'wortelen': 'carrot',
  'tomaat': 'tomato', 'tomaten': 'tomato', 'komkommer': 'cucumber', 'sla': 'lettuce', 'spinazie': 'spinach',
  'boerenkool': 'kale', 'broccoli': 'broccoli', 'bloemkool': 'cauliflower', 'spruitjes': 'brussels sprouts',
  'kool': 'cabbage', 'rodekool': 'cabbage, red', 'witloof': 'chicory', 'prei': 'leeks', 'ui': 'onion', 'uien': 'onion',
  'knoflook': 'garlic', 'paprika': 'peppers, sweet', 'courgette': 'squash, summer', 'aubergine': 'eggplant',
  'champignon': 'mushroom', 'champignons': 'mushroom', 'paddenstoelen': 'mushroom', 'selder': 'celery', 'selderij': 'celery',
  'asperge': 'asparagus', 'asperges': 'asparagus', 'pompoen': 'pumpkin', 'biet': 'beets', 'rode biet': 'beets',
  'radijs': 'radish', 'mais': 'corn', 'maïs': 'corn', 'erwten': 'peas', 'sperziebonen': 'beans, snap', 'boontjes': 'beans, snap',
  'venkel': 'fennel', 'rucola': 'arugula', 'peterselie': 'parsley', 'basilicum': 'basil',
  // Peulvruchten, noten, zaden
  'bonen': 'beans', 'linzen': 'lentil', 'kikkererwten': 'chickpea', 'kidneybonen': 'kidney', 'zwarte bonen': 'beans, black',
  'sojabonen': 'soybeans', 'tofu': 'tofu', 'tempeh': 'tempeh', 'edamame': 'edamame',
  'amandel': 'almond', 'amandelen': 'almond', 'walnoot': 'walnut', 'walnoten': 'walnut', 'hazelnoot': 'hazelnut',
  'hazelnoten': 'hazelnut', 'cashew': 'cashew', 'cashewnoten': 'cashew', 'pinda': 'peanut', 'pindas': 'peanut',
  "pinda's": 'peanut', 'pindakaas': 'peanut butter', 'pistache': 'pistachio', 'paranoot': 'brazilnut', 'paranoten': 'brazilnut',
  'macadamia': 'macadamia', 'pecannoot': 'pecan', 'lijnzaad': 'flaxseed', 'chiazaad': 'chia', 'zonnebloempitten': 'sunflower seed',
  'pompoenpitten': 'pumpkin', 'sesamzaad': 'sesame', 'hennepzaad': 'hemp',
  // Granen
  'brood': 'bread',
  'volkorenbrood': 'bread, whole-wheat',
  'volkoren brood': 'bread, whole-wheat',
  'bruin brood': 'bread, whole-wheat',
  'wit brood': 'bread, white',
  'witbrood': 'bread, white',
  'rijst': 'rice',
  'zilvervliesrijst': 'rice, brown',
  'havermout': 'oat', 'haver': 'oat', 'havervlokken': 'oat', 'pasta': 'pasta', 'spaghetti': 'spaghetti', 'macaroni': 'macaroni', 'noedels': 'noodles',
  'quinoa': 'quinoa', 'boekweit': 'buckwheat', 'gierst': 'millet', 'couscous': 'couscous', 'bulgur': 'bulgur', 'gerst': 'barley',
  'bloem': 'wheat flour', 'meel': 'flour', 'müsli': 'muesli', 'musli': 'muesli', 'cornflakes': 'corn flakes', 'tarwe': 'wheat', 'rogge': 'rye',
  // Zuivel en eieren
  'ei': 'egg', 'eieren': 'egg', 'eigeel': 'egg, yolk', 'eiwit': 'egg, white', 'melk': 'milk', 'halfvolle melk': 'milk, reduced fat',
  'magere melk': 'milk, nonfat', 'volle melk': 'milk, whole', 'karnemelk': 'buttermilk', 'yoghurt': 'yogurt', 'kaas': 'cheese',
  'boter': 'butter', 'room': 'cream', 'slagroom': 'cream, whipping', 'mozzarella': 'mozzarella', 'parmezaan': 'parmesan',
  'feta': 'feta', 'cottage cheese': 'cottage', 'roomkaas': 'cream cheese', 'ricotta': 'ricotta',
  // Vlees, vis
  'kip': 'chicken',
  'kipfilet': 'chicken breast',
  'kippenborst': 'chicken breast',
  'kalkoen': 'turkey',
  'rundvlees': 'beef',
  'biefstuk': 'beef, steak',
  'gehakt': 'ground', 'varkensvlees': 'pork', 'spek': 'bacon', 'ham': 'ham', 'worst': 'sausage', 'lam': 'lamb', 'lamsvlees': 'lamb',
  'lever': 'liver', 'eend': 'duck', 'konijn': 'rabbit', 'hert': 'deer',
  'vis': 'fish', 'zalm': 'salmon', 'tonijn': 'tuna', 'kabeljauw': 'cod', 'makreel': 'mackerel', 'haring': 'herring',
  'sardines': 'sardine', 'sardientjes': 'sardine', 'garnalen': 'shrimp', 'mosselen': 'mussel', 'oesters': 'oyster',
  'forel': 'trout', 'tilapia': 'tilapia', 'koolvis': 'pollock', 'ansjovis': 'anchovy', 'inktvis': 'squid', 'krab': 'crab',
  // Vetten, zoet, dranken
  'olie': 'oil', 'olijfolie': 'olive oil', 'zonnebloemolie': 'sunflower oil', 'kokosolie': 'coconut oil', 'koolzaadolie': 'canola',
  'margarine': 'margarine', 'mayonaise': 'mayonnaise', 'honing': 'honey', 'suiker': 'sugar', 'chocolade': 'chocolate',
  'pure chocolade': 'chocolate, dark', 'jam': 'jam', 'stroop': 'syrup', 'koffie': 'coffee', 'thee': 'tea', 'water': 'water',
  'bier': 'beer', 'wijn': 'wine', 'rode wijn': 'wine, red', 'witte wijn': 'wine, white', 'sap': 'juice',
  'sinaasappelsap': 'orange juice', 'appelsap': 'apple juice', 'sojamelk': 'soymilk', 'amandelmelk': 'almond milk',
  'havermelk': 'oat milk', 'cola': 'cola',
  // Bereiding
  'rauw': 'raw', 'gekookt': 'cooked', 'gebakken': 'fried', 'geroosterd': 'roasted', 'gegrild': 'grilled', 'gestoomd': 'steamed',
  'gedroogd': 'dried', 'diepvries': 'frozen', 'blik': 'canned',
};

/// Hetzelfde woord in een andere spelling in de namen van de bronnen (Deens en Zweeds "müsli", Brits "yoghurt"):
/// het zoekwoord vindt ook die (zie FoodDb.search). Alleen spellingen die niet midden in iets anders staan ("musli"
/// zit in het Deense "musling", mossel; die namen hebben daarnaast toch "müsli").
const otherSpellings = <String, List<String>>{'muesli': ['müsli'], 'yogurt': ['yoghurt']};

final _spellingOf = RegExp(r'müsli|musli(?!ng)|yoghurt');

/// Een naam in de spelling van de zoekwoorden ("Müsli" wordt "muesli"), om te vergelijken met [searchTokens].
String sameSpelling(String s) => s.replaceAllMapped(_spellingOf, (m) => m[0]!.startsWith('y') ? 'yogurt' : 'muesli');

/// Zoekwoorden (in het Engels) voor een Nederlandse of Engelse zoekopdracht.
/// Woordcombinaties ("zoete aardappel") gaan voor losse woorden.
List<String> searchTokens(String query) {
  var q = query.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  final phrases = _nlToEn.keys.where((k) => k.contains(' ')).toList()..sort((a, b) => b.length - a.length);
  final tokens = <String>[];
  for (final p in phrases) {
    if (q.contains(p)) {
      tokens.addAll(_split(_nlToEn[p]!));
      q = q.replaceAll(p, ' ');
    }
  }
  for (final w in q.split(' ').where((w) => w.isNotEmpty)) {
    tokens.addAll(_split(_nlToEn[w] ?? w));
  }
  return tokens.toSet().toList();
}

List<String> _split(String s) => s.split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();
