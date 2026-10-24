/// Een ingrediëntregel van een recept ("2 carrots trimmed and finely chopped", "2 x 400g tins plum tomatoes") lezen en
/// opzoeken met dezelfde zoeker als Snel loggen (SU-1).
///
/// Elke regel geeft hoogstens één ingrediënt: bereidingswoorden ("finely chopped", "to serve", "optional") worden
/// notities en nooit een extra product. Het product wordt gezocht zoals in het zoekvak, maar in een recept is wat je
/// afweegt rauw of droog: wortel is een rauwe wortel, 400 g spaghetti is droge pasta, een blik tomaten zijn tomaten
/// uit blik. Kruiden en specerijen wegen een paar gram. Een regel die niet zeker is, wordt gemarkeerd om na te kijken.
library;

import '../data/food.dart';
import 'quick_parse.dart';

/// Wat er uit één regel gelezen is.
class RecipeLine {
  const RecipeLine({
    required this.raw,
    required this.food,
    this.grams,
    this.count,
    this.unit,
    this.unitGrams,
    this.notes = const [],
    this.optional = false,
    this.toServe = false,
    this.canned = false,
    this.dried = false,
    this.cooked = false,
    this.size = 1.0,
  });

  final String raw;

  /// De productwoorden, zonder hoeveelheid en notities ("smoked streaky bacon").
  final String food;

  /// Het totale gewicht (of volume in ml) als dat er staat of uit een eenheid volgt.
  final double? grams;

  /// Aantal stuks of eenheden ("2 carrots", "4 rashers").
  final double? count;

  /// De eenheid in het Engels (tbsp, tsp, rasher, clove, stick, sprig, pinch, tin, pack, ...).
  final String? unit;

  /// Gewicht van één eenheid als dat vast ligt (een eetlepel, een plakje spek).
  final double? unitGrams;

  /// Wat er na het product stond: "finely chopped", "to serve", "optional".
  final List<String> notes;

  final bool optional;

  /// "To serve" of "for garnish" zonder hoeveelheid: een suggestie, geen deel van het recept.
  final bool toServe;
  final bool canned;
  final bool dried;
  final bool cooked;

  /// "small", "large": factor op het gewone stukgewicht.
  final double size;

  bool get hasAmount => grams != null || count != null;

  @override
  String toString() =>
      'RecipeLine($food, grams: $grams, count: $count, unit: $unit $unitGrams, notes: $notes'
      '${optional ? ', optional' : ''}${toServe ? ', to serve' : ''}${canned ? ', canned' : ''}${dried ? ', dried' : ''})';
}

const _fractions = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125, '⅕': 0.2, '⅙': 1 / 6};

const _wordNumbers = {
  'a': 1.0, 'an': 1.0, 'one': 1.0, 'two': 2.0, 'three': 3.0, 'four': 4.0, 'five': 5.0, 'six': 6.0, 'seven': 7.0, //
  'eight': 8.0, 'nine': 9.0, 'ten': 10.0, 'twelve': 12.0, 'half': 0.5, 'een': 1.0, 'twee': 2.0, 'drie': 3.0, 'vier': 4.0,
};

/// Gewichtseenheden naar gram (ml telt als gram).
const _weights = {
  'g': 1.0, 'gr': 1.0, 'gram': 1.0, 'grams': 1.0, 'gramme': 1.0, 'grammes': 1.0, 'kg': 1000.0, 'kilo': 1000.0, //
  'ml': 1.0, 'millilitre': 1.0, 'milliliter': 1.0, 'cl': 10.0, 'dl': 100.0, 'l': 1000.0, 'litre': 1000.0, 'liter': 1000.0,
  'litres': 1000.0, 'oz': 28.35, 'ounce': 28.35, 'ounces': 28.35, 'lb': 453.6, 'lbs': 453.6, 'pound': 453.6, 'pounds': 453.6,
};

/// Eenheden met hun Engelse naam en (als dat vast ligt) een gewicht per eenheid. null: hangt van het product af.
const _units = <String, (String, double?)>{
  'tbsp': ('tbsp', 15), 'tbsps': ('tbsp', 15), 'tablespoon': ('tbsp', 15), 'tablespoons': ('tbsp', 15), 'tbs': ('tbsp', 15),
  'el': ('tbsp', 15), 'eetlepel': ('tbsp', 15), 'eetlepels': ('tbsp', 15), //
  'tsp': ('tsp', 5), 'tsps': ('tsp', 5), 'teaspoon': ('tsp', 5), 'teaspoons': ('tsp', 5), 'tl': ('tsp', 5),
  'theelepel': ('tsp', 5), 'theelepels': ('tsp', 5), 'koffielepel': ('tsp', 5), //
  'cup': ('cup', 240), 'cups': ('cup', 240), 'kopje': ('cup', 150), //
  'pinch': ('pinch', 0.4), 'pinches': ('pinch', 0.4), 'snufje': ('pinch', 0.4), 'snuf': ('pinch', 0.4), //
  'dash': ('dash', 1), 'splash': ('splash', 10), 'drizzle': ('drizzle', 5), 'scheutje': ('splash', 10), //
  'handful': ('handful', 30), 'handfuls': ('handful', 30), 'handvol': ('handful', 30), //
  'bunch': ('bunch', 25), 'bunches': ('bunch', 25), 'bosje': ('bunch', 25), //
  'pack': ('pack', null), 'packs': ('pack', null), 'packet': ('pack', null), 'packets': ('pack', null), 'pak': ('pack', null),
  'bag': ('pack', null), 'bags': ('pack', null), //
  'sprig': ('sprig', 1), 'sprigs': ('sprig', 1), 'takje': ('sprig', 1), 'takjes': ('sprig', 1), //
  'rasher': ('rasher', 25), 'rashers': ('rasher', 25), //
  'clove': ('clove', 5), 'cloves': ('clove', 5), 'teen': ('clove', 5), 'teentje': ('clove', 5), 'teentjes': ('clove', 5), //
  'stick': ('stick', 40), 'sticks': ('stick', 40), 'stalk': ('stick', 40), 'stalks': ('stick', 40), 'rib': ('stick', 40),
  'ribs': ('stick', 40), 'stengel': ('stick', 40), 'stengels': ('stick', 40), //
  'slice': ('slice', 35), 'slices': ('slice', 35), 'sneetje': ('slice', 35), 'sneetjes': ('slice', 35), //
  'knob': ('knob', 15), 'knobs': ('knob', 15), 'klontje': ('knob', 15), //
  'tin': ('tin', 400), 'tins': ('tin', 400), 'can': ('tin', 400), 'cans': ('tin', 400), 'blik': ('tin', 400), 'blikje': ('tin', 400),
  'jar': ('jar', 350), 'jars': ('jar', 350), 'pot': ('jar', 350), 'potje': ('jar', 350), //
  'glass': ('glass', 150), 'glasses': ('glass', 150), 'glas': ('glass', 150), //
  'sheet': ('sheet', 20), 'sheets': ('sheet', 20), //
  'leaf': ('leaf', null), 'leaves': ('leaf', null), 'blad': ('leaf', null), 'blaadje': ('leaf', null), 'blaadjes': ('leaf', null),
  'piece': ('piece', null), 'pieces': ('piece', null), 'stuk': ('piece', null), 'stuks': ('piece', null), 'stukje': ('piece', null),
  'fillet': ('fillet', null), 'fillets': ('fillet', null), 'head': ('head', null), 'heads': ('head', null),
  'thumb': ('thumb', 15), 'thumb-sized': ('thumb', 15), 'thumb-size': ('thumb', 15),
  'cube': ('cube', 10), 'cubes': ('cube', 10),
};

/// Grootte voor een stuk: een kleine ui weegt minder dan een grote.
const _sizes = {
  'small': 0.7,
  'smallish': 0.8,
  'medium': 1.0,
  'large': 1.3,
  'big': 1.3,
  'extra-large': 1.5,
  'heaped': 1.5,
  'level': 1.0,
  'generous': 1.3,
  'good': 1.0,
  'klein': 0.7,
  'kleine': 0.7,
  'middelgrote': 1.0,
  'groot': 1.3,
  'grote': 1.3,
};

/// Bereiding en opdiening: wat hierna komt, is een notitie, geen product.
final _prep = RegExp(
  r'\b(finely|roughly|thinly|coarsely|freshly|lightly|very|chopped|diced|sliced|grated|crushed|peeled|trimmed|deseeded|'
  r'seeded|de-seeded|stoned|pitted|halved|quartered|picked|torn|shredded|drained|rinsed|washed|scrubbed|beaten|whisked|'
  r'softened|melted|sifted|cubed|julienned|zested|juiced|squeezed|cut|snipped|bashed|bruised|crumbled|mashed|separated|'
  r'defrosted|thawed|cooled|warmed|toasted|segmented|skinned|boned|boneless|skinless|cored|hulled|spiralized|spiralised|'
  r'gehakt|fijngehakt|gesnipperd|gesneden|geraspt|geperst|geschild|in blokjes|in stukjes|in plakjes|'
  r'to serve|to taste|to garnish|for garnish|for garnishing|for serving|for frying|for greasing|for dusting|for drizzling|'
  r'for the|plus|optional|optioneel|naar smaak|om te serveren|at room temperature|room temperature|left whole|the rest|'
  r'such as|ideally|preferably|about|approx|approximately|roughly|each|into)\b',
  caseSensitive: false,
);

/// Bereidingswoorden die vóór het product mogen staan ("finely chopped onion", "grated parmesan").
final _leadingPrep = RegExp(
  r'^(?:(?:finely|roughly|thinly|coarsely|freshly|lightly|chopped|diced|sliced|grated|crushed|peeled|trimmed|halved|'
  r'shredded|cubed|crumbled|melted|softened|beaten|cooked|fresh|ripe|good-quality|good quality|quality|organic|'
  r'free-range|free range|unsalted|salted)\s+)+',
  caseSensitive: false,
);

/// Kopjes in een ingrediëntenlijst ("For the sauce", "To serve:").
final _header = RegExp(
  r'^(for (the )?[a-z ]+|to (season|serve|garnish|finish|decorate)|voor (de|het) [a-z ]+|garnish|topping|dressing|marinade|sauce)\s*:?$',
  caseSensitive: false,
);

double _n(String s) => double.parse(s.replaceAll(',', '.'));

/// Breuken, bereiken en ounces omzetten naar gewone getallen.
String _normalNumbers(String line) {
  var t = line.replaceAll(' ', ' ').trim().replaceAll(RegExp(r'^[-–•*▢☐□·]+\s*'), '');
  // Breuken als teken ("1½", "1 ½", "½")
  t = t.replaceAllMapped(RegExp('(\\d+)?\\s*([${_fractions.keys.join()}])'), (m) {
    final whole = m.group(1) == null ? 0 : int.parse(m.group(1)!);
    return '${_fmt(whole + _fractions[m.group(2)]!)} ';
  });
  // Breuken als tekst ("1 1/2", "3/4")
  t = t.replaceAllMapped(RegExp(r'(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)'), (m) {
    final whole = m.group(1) == null ? 0 : int.parse(m.group(1)!);
    final d = int.parse(m.group(3)!);
    if (d == 0) return m.group(0)!;
    return _fmt(whole + int.parse(m.group(2)!) / d);
  });
  // Een bereik ("2-3 sprigs", "2 to 3"): het midden
  t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:-|–|to|tot)\s*(\d+(?:[.,]\d+)?)(?=\s*[a-zA-Z(]|$)'), (m) {
    return _fmt((_n(m.group(1)!) + _n(m.group(2)!)) / 2);
  });
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _fmt(double v) {
  final r = double.parse(v.toStringAsFixed(3));
  return r == r.roundToDouble() ? '${r.round()}' : '$r';
}

/// Een ingrediëntregel lezen. Geeft null voor een kopje ("For the sauce") of een lege regel.
RecipeLine? parseRecipeLine(String raw) {
  var t = _normalNumbers(raw);
  if (t.isEmpty || !RegExp(r'[a-zA-Zà-ÿ]').hasMatch(t)) return null;
  if (!RegExp(r'\d').hasMatch(t) && (_header.hasMatch(t) || t.endsWith(':'))) return null;
  final notes = <String>[];
  double? parenGrams;
  // Tussen haakjes: een gewicht ("1 tin (400 g)") of een notitie ("(optional)")
  t = t.replaceAllMapped(RegExp(r'\(([^)]*)\)'), (m) {
    final inner = m.group(1)!.trim();
    final w = RegExp(r'^(?:about |approx\.? |ca\.? )?(\d+(?:[.,]\d+)?)\s*([a-z]+)\b', caseSensitive: false).firstMatch(inner);
    if (w != null && _weights.containsKey(w.group(2)!.toLowerCase())) {
      parenGrams ??= _n(w.group(1)!) * _weights[w.group(2)!.toLowerCase()]!;
    } else if (inner.isNotEmpty) {
      notes.add(inner);
    }
    return ' ';
  });
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();

  double? grams, count, unitGrams;
  String? unit;
  var canned = false;
  var size = 1.0;

  // "2 x 400g tins", "2 × 400 ml"
  final times = RegExp(r'^(\d+(?:[.,]\d+)?)\s*[x×]\s*(\d+(?:[.,]\d+)?)\s*([a-z]+)\b\.?\s*(.*)$', caseSensitive: false).firstMatch(t);
  if (times != null && _weights.containsKey(times.group(3)!.toLowerCase())) {
    grams = _n(times.group(1)!) * _n(times.group(2)!) * _weights[times.group(3)!.toLowerCase()]!;
    t = times.group(4)!;
  } else {
    // Een getal, eventueel met een gewichtseenheid eraan vast ("500g", "125ml", "1.5 kg")
    final m = RegExp(r'^(\d+(?:[.,]\d+)?)\s*([a-z]+\b\.?)?\s*(.*)$', caseSensitive: false).firstMatch(t);
    if (m != null) {
      final n = _n(m.group(1)!);
      final u = m.group(2)?.toLowerCase().replaceAll('.', '');
      if (u != null && _weights.containsKey(u)) {
        grams = n * _weights[u]!;
        t = m.group(3)!;
      } else {
        count = n;
        t = '${m.group(2) ?? ''} ${m.group(3)!}'.trim();
      }
    } else {
      final first = t.split(' ').first.toLowerCase();
      if (_wordNumbers.containsKey(first)) {
        count = _wordNumbers[first];
        t = t.substring(first.length).trim();
        // "a half", "half a"
        if (RegExp(r'^(half|a half)\b', caseSensitive: false).hasMatch(t)) {
          count = count! * 0.5;
          t = t.replaceFirst(RegExp(r'^(a )?half\s*', caseSensitive: false), '');
        }
        t = t.replaceFirst(RegExp(r'^(a|an)\s+', caseSensitive: false), '');
      }
    }
  }
  // Grootte en eenheid: "2 medium onions", "small pack basil", "1 tin chopped tomatoes", "a pinch of salt"
  for (var i = 0; i < 3; i++) {
    final words = t.split(' ');
    final w = words.first.toLowerCase().replaceAll(RegExp(r'[.,]$'), '');
    if (_sizes.containsKey(w) && words.length > 1) {
      size *= _sizes[w]!;
      t = words.skip(1).join(' ');
      continue;
    }
    if (unit == null && _units.containsKey(w) && words.length > 1) {
      final (name, g) = _units[w]!;
      unit = name;
      count ??= 1;
      unitGrams = g;
      if (name == 'tin') canned = true;
      t = words.skip(1).join(' ').replaceFirst(RegExp(r'^(of|van)\s+', caseSensitive: false), '');
      continue;
    }
    break;
  }
  // "1 tin (400 g)": het gewicht tussen haakjes per blik
  if (parenGrams != null && grams == null) {
    grams = parenGrams! * (count ?? 1);
    if (unit == null || unit == 'tin' || unit == 'jar' || unit == 'pack') {
      count = null;
      unitGrams = null;
    } else {
      grams = parenGrams;
    }
  }
  // Na een gewicht nog een verpakking: "400g tins plum tomatoes", "400ml can coconut milk"
  final pack = RegExp(
    r'^(tins?|cans?|jars?|packs?|packets?|cartons?|bottles?|bags?|blik(je)?|pot(je)?)\b\s*(of\s+)?',
    caseSensitive: false,
  ).firstMatch(t);
  if (pack != null) {
    if (RegExp(r'^(tin|can|blik)', caseSensitive: false).hasMatch(pack.group(0)!)) canned = true;
    t = t.substring(pack.end);
  }
  t = t.replaceFirst(RegExp(r'^(of|van)\s+', caseSensitive: false), '').trim();
  // "thumb-sized piece of ginger"
  if (unit != null) t = t.replaceFirst(RegExp(r'^(piece|pieces|stuk|stukje)\s+(of\s+)?', caseSensitive: false), '');

  // Bereidingswoorden vooraan weg ("finely chopped onion", "boneless, skinless chicken thighs")
  t = t.replaceFirst(_leadingPrep, '');
  for (;;) {
    final m = RegExp(r'^([a-z-]+(ed|less|ly))[,\s]+', caseSensitive: false).firstMatch(t);
    if (m == null || !_prep.hasMatch(m.group(1)!) || RegExp(r'^(dried|smoked|minced)$', caseSensitive: false).hasMatch(m.group(1)!)) break;
    t = t.substring(m.end);
  }
  // De rest: product, daarna notities. Alles na de eerste komma (geen decimale komma) is een notitie.
  final comma = RegExp(r'(?<!\d),|,(?!\d)|;| - | – ').firstMatch(t);
  if (comma != null) {
    final after = t.substring(comma.end).trim();
    if (after.isNotEmpty) notes.add(after);
    t = t.substring(0, comma.start).trim();
  }
  final lower0 = t.toLowerCase();
  // "chopped tomatoes" of "passata" zonder blik is in een recept nog steeds uit blik of pak
  if (RegExp(r'^(chopped|crushed|plum|peeled) tomatoes\b|\bpassata\b|\btinned\b|\bcanned\b').hasMatch(lower0)) canned = true;
  t = t.replaceAll(RegExp(r'\b(tinned|canned)\s+', caseSensitive: false), '');
  t = t.replaceFirst(_leadingPrep, '');
  // Het eerste bereidingswoord na het product: vanaf daar notitie ("onions finely chopped", "bread to serve")
  final prep = _prep.firstMatch(t);
  if (prep != null && prep.start > 0) {
    notes.add(t.substring(prep.start).trim());
    t = t.substring(0, prep.start).trim();
  } else if (prep != null && prep.start == 0) {
    // Alleen een notitie ("to taste"): er is geen product
    notes.add(t);
    t = '';
  }
  // Twee keuzes ("butter or margarine", "salt and pepper"): de eerste
  t = t.replaceFirst(RegExp(r'\s+(or|and|en|&|/)\s+.*$', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'^[\s.;:,]+|[\s.;:,]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  final allNotes = notes.join(' ').toLowerCase();
  final optional = RegExp(r'\b(optional|optioneel|if you like|if liked)\b').hasMatch('${raw.toLowerCase()} $allNotes');
  final toServe =
      RegExp(r'\b(to serve|for serving|to garnish|for garnish|om te serveren)\b').hasMatch(allNotes) &&
      !allNotes.contains('plus') &&
      grams == null &&
      count == null;
  final lower = t.toLowerCase();
  // Vormwoorden achteraan worden de eenheid: "2 garlic cloves", "2 celery sticks", "2 fresh bay leaves"
  final form = RegExp(r'\s+(cloves?|sticks?|stalks?|sprigs?|leaves|leaf|rashers?|slices?|fillets?)$').firstMatch(lower);
  if (form != null && unit == null) {
    final (name, g) = _units[form.group(1)!]!;
    unit = name;
    unitGrams = g;
    t = t.substring(0, form.start).trim();
  } else if (form != null && (form.group(1) == 'leaves' || form.group(1) == 'leaf')) {
    // "small pack basil leaves": de verpakking is de eenheid, "leaves" hoort niet bij de zoekterm
    t = t.substring(0, form.start).trim();
  }
  if (unitGrams != null && size != 1.0 && unit != 'tbsp' && unit != 'tsp') {
    unitGrams = unitGrams * size;
    size = 1.0;
  }
  final dried = RegExp(r'\b(dried|dry|gedroogde?)\b').hasMatch('$lower $allNotes');
  final cooked = RegExp(r'\b(cooked|leftover|boiled|gekookte?)\b').hasMatch(raw.toLowerCase());
  return RecipeLine(
    raw: raw.trim(),
    food: t.replaceFirst(_leadingPrep, '').replaceAll(RegExp(r'\b(fresh|verse?)\s+', caseSensitive: false), '').trim(),
    grams: grams,
    count: count,
    size: size,
    unit: unit,
    unitGrams: unitGrams,
    notes: notes,
    optional: optional,
    toServe: toServe,
    canned: canned,
    dried: dried,
    cooked: cooked,
  );
}

// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
// Opzoeken

/// Water en ijs: geen voedingsstoffen, niet meetellen.
final _water = RegExp(r'^(cold |hot |warm |boiling |tap |iced? )*(water|ice|ice cubes|ijs|ijsblokjes)$');

/// Zout en peper "naar smaak": klein, en zonder hoeveelheid niet meetellen.
final _saltPepper = RegExp(r'^(sea |table |rock |kosher |flaky |fine )*(salt|zout)$|^(freshly )?(ground )?(black |white )?(pepper|peper)$');

/// Kruiden (vers of gedroogd) en specerijen: een paar gram.
final _herb = RegExp(
  r'\b(basil|bay|oregano|thyme|rosemary|parsley|coriander|cilantro|mint|dill|chives?|sage|tarragon|marjoram|herbs?|'
  r'basilicum|laurier|tijm|rozemarijn|peterselie|koriander|munt|dille|bieslook|salie|dragon)\b',
);
final _spice = RegExp(
  r'\b(cumin|paprika|turmeric|cinnamon|nutmeg|garam masala|curry powder|chilli powder|chili powder|chilli flakes|chili flakes|'
  r'cayenne|ground ginger|ground coriander|cloves|cardamom|allspice|seeds|star anise|saffron|baking powder|bicarbonate|'
  r'baking soda|yeast|mixed spice|five spice|spice|komijn|kurkuma|kaneel|nootmuskaat|kerriepoeder|bakpoeder|gist)\b',
);

/// Hoe weinig een kruid of specerij weegt, per eenheid.
double? _minorGrams(RecipeLine l, {required bool spice}) {
  final dried = l.dried || spice;
  final n = l.count ?? 1;
  if (l.grams != null) return l.grams;
  switch (l.unit) {
    case 'tsp':
      return n * (dried ? (spice ? 2.5 : 1) : 1);
    case 'tbsp':
      return n * (dried ? (spice ? 7.5 : 3) : 3);
    case 'pinch':
      return n * 0.4;
    case 'dash':
      return n * 0.5;
    case 'leaf':
      return n * (RegExp(r'\bbay|laurier').hasMatch(l.food.toLowerCase()) ? 0.2 : 0.5);
    case 'sprig':
      return n * 1;
    case 'pack' || 'bunch':
      return n * 20;
    case 'handful':
      return n * 10;
    case 'cup':
      return n * 20;
    case null:
      if (l.count != null) return n * (RegExp(r'\bbay|laurier').hasMatch(l.food.toLowerCase()) ? 0.2 : 1);
      return dried ? 1 : 5;
    default:
      return n * 1;
  }
}

/// Gewone stukgewichten in een recept (gram), voor wat de databank niet als stuk kent of te groot schat.
const _pieces = <String, double>{
  r'cherry tomato': 15,
  r'plum tomato|vine tomato|tomato': 120,
  r'spring onion|scallion': 15,
  r'shallot': 30,
  r'red onion|onion': 150,
  r'carrot': 70,
  r'celery': 40,
  r'garlic': 5,
  r'sweet potato': 200,
  r'potato': 175,
  r'(red|green|yellow|orange|bell) pepper': 160,
  r'chil+i|chile': 15,
  r'cucumber': 300,
  r'courgette|zucchini': 200,
  r'aubergine|eggplant': 250,
  r'lemon': 100,
  r'lime': 65,
  r'egg': 55,
  r'olive': 4,
  r'mushroom': 20,
  r'avocado': 150,
  r'apple': 150,
  r'banana': 120,
  r'chicken breast': 150,
  r'chicken thigh': 100,
  r'sausage': 60,
  r'leek': 150,
  r'tortilla|wrap': 60,
  r'stock cube|bouillon cube|cube': 10,
  r'ginger': 15,
  r'radish': 10,
  r'beetroot': 100,
  r'parsnip': 120,
  r'pear': 160,
  r'orange': 150,
  r'peach': 150,
  r'salmon|cod|haddock|hake|trout|sea bass|mackerel|fish': 130,
};

double? _pieceGrams(String food) {
  final f = food.toLowerCase();
  for (final e in _pieces.entries) {
    if (RegExp('\\b(${e.key})(e?s)?\\b').hasMatch(f)) return e.value;
  }
  return null;
}

/// Kan rauw zijn: groente, vlees, vis en eieren weeg je in een recept rauw af.
final _rawable = RegExp(
  r'\b(beef|pork|lamb|veal|chicken|turkey|duck|mince|minced|bacon|pancetta|sausages?|steak|salmon|cod|haddock|tuna steak|'
  r'prawns?|shrimps?|fish|onions?|shallots?|carrots?|celery|garlic|potato(es)?|tomato(es)?|peppers?|chil+ies|chil+i|courgettes?|'
  r'zucchini|aubergines?|eggplants?|mushrooms?|spinach|broccoli|cauliflower|cabbage|leeks?|ginger|cucumbers?|lettuce|kale|'
  r'squash|pumpkin|beetroot|parsnips?|radish(es)?|peas|green beans|sweetcorn|corn|avocados?|lemons?|limes?|apples?|'
  r'bananas?|pears?|oranges?|berries|strawberries|blueberries|eggs?|tofu|rocket|spring onions?|herbs?|basil|parsley|'
  r'coriander|mint|rosemary|thyme|dill|chives)\b',
);

/// Pasta, rijst en granen weeg je in een recept droog af.
final _dryGrain = RegExp(
  r'\b(spaghetti|penne|fusilli|macaroni|tagliatelle|linguine|fettuccine|rigatoni|farfalle|orzo|lasagne|lasagna|pasta|'
  r'noodles?|rice|basmati|risotto|arborio|couscous|bulgur|bulghur|quinoa|lentils?|split peas|barley|oats|polenta)\b',
);

final _pastaShape = RegExp(r'\b(spaghetti|penne|fusilli|macaroni|tagliatelle|linguine|fettuccine|rigatoni|farfalle|orzo|pasta)\b');

/// Andere namen voor hetzelfde in de databank, voor het zoeken.
const _aliases = <String, String>{
  r'^(beef )?mince$|^minced beef$|^ground beef$|^lean (beef )?mince$': 'minced beef',
  r'^pork mince$|^minced pork$|^ground pork$': 'minced pork',
  r'^turkey mince$|^minced turkey$': 'minced turkey',
  r'^lamb mince$|^minced lamb$': 'minced lamb',
  r'^passata$': 'tomato passata',
  r'^tomato pur[ée]e$': 'tomato purée',
  r'^bay$': 'bay leaf',
  r'^(beef|chicken|vegetable|veg) stock cubes?$': r'$1 stock cube',
  r'^stock cubes?$': 'stock cube',
  r'^(extra[- ]virgin )?olive oil$': 'olive oil',
  r'^streaky bacon$|^smoked streaky bacon$|^(smoked )?bacon rashers$': 'streaky bacon',
  r'^crusty bread$': 'bread',
  r'^ginger$|^root ginger$|^fresh root ginger$': 'ginger',
  r'^(red |green )?chil+ies$|^(red |green )?chil+i$': r'chilli',
  r'^natural yog(h)?urt$|^plain yog(h)?urt$': 'yoghurt plain',
  r'^(kalamata |black |green )olives$': 'olives',
  r'^feta cheese$': 'feta',
  r'^(dried |red |crushed )*chil+i (flakes|powder)$|^crushed chil+is?$': 'chili powder',
  r'^(free[- ]range |large |medium )?eggs?$': 'eggs chicken whole',
  r'^parmesan cheese$': 'parmesan',
  r'^red wine vinegar$': 'vinegar wine',
  r'^double cream$': 'cream double',
  r'^single cream$': 'cream single',
};

/// Het hoofdwoord moet in de naam van de treffer staan: wortel is geen varkensvlees.
const _headSynonyms = <String, String>{
  'chilli': r'chil+i|chile|pepper',
  'chili': r'chil+i|chile|pepper',
  'purée': r'pur[ée]e|paste',
  'puree': r'pur[ée]e|paste',
  'mince': r'minc',
  'minced': r'minc',
  'courgette': r'courgette|zucchini',
  'zucchini': r'courgette|zucchini',
  'aubergine': r'aubergine|eggplant',
  'eggplant': r'aubergine|eggplant',
  'coriander': r'coriander|cilantro',
  'prawn': r'prawn|shrimp',
  'shrimp': r'prawn|shrimp',
  'chickpea': r'chickpea|garbanzo|chick pea',
  'yoghurt': r'yog',
  'yogurt': r'yog',
  'leaf': r'lea[fv]',
  'scallion': r'scallion|spring onion',
  'passata': r'passata|pur[ée]e|sieved|tomato',
};

String _stem(String w) {
  if (w.length > 4 && w.endsWith('ies')) return w.substring(0, w.length - 3);
  if (w.length > 4 && RegExp(r'(oes|ches|shes|sses|xes)$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.length > 3 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
  return w;
}

bool _hasWord(String name, String word) {
  final syn = _headSynonyms[word] ?? _headSynonyms[_stem(word)];
  // Een heel woord: "salt" is geen "salted fish"
  final pattern = syn ?? '${RegExp.escape(_stem(word))}(e|es|s|ies|y|i)?\\b';
  return RegExp('\\b($pattern)', caseSensitive: false).hasMatch(name);
}

/// Een gerecht of bereid product terwijl de regel om het basisproduct vraagt.
final _dish = RegExp(
  r'(\b(garnished|with|in sauce|sauce|stew|stewed|soup|salad|pie|lasagn|pudding|filled|stuffed|sandwich|pizza|'
  r'deep ?fried|deepfried|fried|roasted|grilled|baked|breaded|battered|pickled|takeaway|ready meal|dish|casserole|curry|juice|drink|ketchup|rtd)\b|\bw/(?!o))',
  caseSensitive: false,
);

/// Een deel of bijproduct (vel, botten, lever) terwijl de regel om het vlees vraagt.
final _part = RegExp(
  r'\b(skin|bones?|giblets|liver|heart|gizzards?|feet|neck|kidneys?|tongue|separable fat|fat only|drippings?)\b',
  caseSensitive: false,
);

/// Een bewerkte vorm van het product: alleen als de regel erom vraagt.
final _form = RegExp(r'\b(pur[ée]e|paste|conc|concentrated?|powder|dried|sun-?dried|flakes|juice|dehydrated|smoothie)\b');

/// Woorden die alleen een vorm zijn: zonder het woord ervoor zoek je iets anders ("chilli flakes" is geen havervlokken).
final _generic = RegExp(
  r'^(flakes?|powder|seeds?|sauce|paste|juice|stock|cubes?|extract|syrup|oil|milk|cream|vinegar|cheese|leaf|leaves|mix|seasoning|zest|water|breasts?|thighs?|legs?|wings?|fillets?|steaks?|chops?)$',
);

/// Enkelvoud voor het zoeken ("chicken thighs" vindt niets, "chicken thigh" wel); couscous en hummus blijven.
String _singular(String w) {
  if (w.length <= 3 || RegExp(r'(ss|us|is|ous)$').hasMatch(w)) return w;
  if (w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
  if (RegExp(r'(oes|ches|shes|xes)$').hasMatch(w)) return w.substring(0, w.length - 2);
  if (w.endsWith('s')) return w.substring(0, w.length - 1);
  return w;
}

/// Het resultaat van één regel: de treffers (zoals Snel loggen ze geeft) en of je ze best nakijkt.
class RecipeMatch {
  const RecipeMatch(this.line, this.item, this.options, {this.check = false, this.counted = true, this.why});
  final RecipeLine line;
  final QuickItem item;
  final List<(Food, double, Portion?)> options;

  /// Niet zeker: geen of een twijfelachtige treffer, of een geschatte hoeveelheid.
  final bool check;

  /// Telt mee in het recept (water, "to taste" en een serveersuggestie niet).
  final bool counted;

  /// Waarom nakijken of niet meetellen, als code: none, unsure, amount, minor, water, taste, serve.
  final String? why;
}

typedef QuickResolver = List<(Food, double, Portion?)> Function(QuickItem);

/// Eén receptregel opzoeken met de zoeker van Snel loggen ([resolve] = AppState.resolveQuick). Geeft null als de regel
/// geen ingrediënt is (een kopje).
RecipeMatch? matchRecipeLine(String raw, QuickResolver resolve) {
  final l = parseRecipeLine(raw);
  if (l == null) return null;
  return matchParsed(l, resolve);
}

RecipeMatch matchParsed(RecipeLine l, QuickResolver resolve) {
  var food = l.food.toLowerCase().trim();
  if (food.isEmpty) {
    return RecipeMatch(l, QuickItem(l.raw), const [], check: true, counted: false, why: 'none');
  }
  // Water telt niet mee
  if (_water.hasMatch(food)) {
    return RecipeMatch(l, QuickItem(food), const [], counted: false, why: 'water');
  }
  for (final e in _aliases.entries) {
    final re = RegExp(e.key);
    final m = re.firstMatch(food);
    if (m != null) {
      food = e.value.contains(r'$1') ? e.value.replaceAll(r'$1', m.group(1) ?? '').trim() : e.value;
      break;
    }
  }
  // Tomaten uit blik: "plum", "chopped" of "whole" maakt geen ander product
  if (l.canned && RegExp(r'\btomato(es)?$').hasMatch(food)) food = 'tomatoes';
  final saltPepper = _saltPepper.hasMatch(food);
  final spice = saltPepper || _spice.hasMatch(food);
  final herb = !spice && _herb.hasMatch(food) && !RegExp(r'\b(oil|butter|sauce|paste|pesto|tea)\b').hasMatch(food);
  final minor = saltPepper || spice || herb;

  // De hoeveelheid voor de zoeker
  double? grams = l.grams;
  double? count = l.count;
  double? unitGrams = l.unitGrams;
  String? unit = l.unit;
  var guessedAmount = false;
  if (minor) {
    if (saltPepper && !l.hasAmount) {
      return RecipeMatch(l, QuickItem(food), const [], counted: false, why: 'taste');
    }
    grams = _minorGrams(l, spice: spice);
    count = null;
    unitGrams = null;
  } else if (grams == null) {
    final piece = _pieceGrams(food);
    final isOilOrFat = RegExp(r'\b(oil|butter|margarine|ghee|lard)\b').hasMatch(food);
    if (count != null && unitGrams == null) {
      // Stuks: een gewoon stukgewicht voor dit product, of een verpakking die we niet kennen
      if (unit == 'pack' || unit == 'head' || unit == 'leaf') {
        guessedAmount = true;
      } else if (piece != null) {
        unitGrams = piece * l.size;
        unit ??= 'piece';
      }
    } else if (count == null) {
      if (isOilOrFat) {
        grams = 15;
      } else if (l.toServe) {
        return RecipeMatch(l, QuickItem(food), resolve(QuickItem(food)), counted: false, why: 'serve');
      } else {
        guessedAmount = true;
      }
    }
    // Een kopje bloem of suiker weegt minder dan een kopje water
    if (unit == 'cup') {
      for (final (re, g) in const [
        (r'\b(flour|cocoa|icing sugar|powdered sugar)\b', 125.0),
        (r'\b(sugar)\b', 200.0),
        (r'\b(rice|lentils|quinoa|couscous)\b', 185.0),
        (r'\b(oats|breadcrumbs)\b', 90.0),
        (r'\b(cheese|cheddar|parmesan|mozzarella)\b', 100.0),
        (r'\b(nuts|almonds|walnuts|peanuts|cashews)\b', 140.0),
        (r'\b(spinach|rocket|lettuce|kale)\b', 30.0),
        (r'\b(butter)\b', 225.0),
      ]) {
        if (RegExp(re).hasMatch(food)) {
          unitGrams = g;
          break;
        }
      }
    }
    // Een eetlepel olie weegt minder dan een eetlepel water
    if (isOilOrFat && unit == 'tbsp') unitGrams = 13.5;
    if (isOilOrFat && unit == 'tsp') unitGrams = 4.5;
  }
  QuickItem item(String q) => QuickItem(
    q,
    grams: grams,
    count: grams != null ? null : count,
    unitGrams: grams != null ? null : unitGrams,
    unit: grams != null ? null : (unit == 'piece' ? null : unit),
  );

  // Welke vorm: droog (pasta, rijst), uit blik, of rauw
  String? modifier;
  RegExp? wanted;
  if (!l.cooked && _dryGrain.hasMatch(food) && !l.canned && (grams != null || unit == 'cup')) {
    modifier = 'dry';
    wanted = RegExp(r'\b(dry|dried|raw|uncooked)\b(?!.*\b(boiled|cooked)\b)');
    if (_pastaShape.hasMatch(food) && !RegExp(r'\b(gluten|wholewheat|whole wheat|wholemeal|spelt|egg|fresh)\b').hasMatch(food)) {
      food = 'pasta';
    }
  } else if (l.canned) {
    modifier = 'canned';
    wanted = RegExp(r'\b(canned|tinned|can)\b');
  } else if (l.dried && herb) {
    modifier = 'dried';
    wanted = RegExp(r'\bdried\b');
  } else if (!l.cooked && _rawable.hasMatch(food) && !RegExp(r'\b(juice|oil|sauce|paste|purée|powder|stock|smoked salmon)\b').hasMatch(food)) {
    modifier = 'raw';
    wanted = RegExp(r'\b(raw|fresh)\b');
  }

  if (modifier == 'dry' || modifier == 'dried') food = food.replaceAll(RegExp(r'\b(dried|dry)\s*'), '').trim();
  final words = food.split(' ').where((w) => w.isNotEmpty).toList();
  final head = words.isEmpty ? food : words.last;
  bool headOk(Food f) => _hasWord(f.name, head);
  // Puree, poeder of sap alleen als de regel erom vraagt (een blik tomaten is geen tomatenpuree)
  final asked = '$food ${modifier ?? ''} ${modifier == 'dry' ? 'dried' : ''}';
  bool formOk(Food f) => _form.allMatches(f.name.toLowerCase()).every((m) => asked.contains(m.group(0)!.substring(0, 3)));
  bool plainOk(Food f) =>
      headOk(f) &&
      formOk(f) &&
      (!_dish.hasMatch(f.name) || words.any((w) => _dish.hasMatch(w))) &&
      (!_part.hasMatch(f.name.replaceAll(RegExp(r'\b(without|w/o|no) skin\b|\bskinless\b', caseSensitive: false), '')) ||
          words.any((w) => _part.hasMatch(w)));

  // Wat past eerst, dan wat alleen het hoofdwoord heeft; iets zonder het hoofdwoord (haver bij tomaten) niet
  List<(Food, double, Portion?)> ordered(List<(Food, double, Portion?)> opts, bool Function(Food) good) => [
    ...opts.where((o) => good(o.$1)),
    ...opts.where((o) => !good(o.$1) && plainOk(o.$1)),
  ];

  // Van specifiek naar algemeen: "streaky bacon raw", "streaky bacon", "bacon raw", "bacon". Elk woord van de
  // zoekterm moet in de naam staan (kippendij is geen eendenborst).
  final variants = switch (modifier) {
    'dry' => const ['dry', 'dried raw', 'raw'],
    null => const <String>[],
    final m => [m],
  };
  // Droge pasta of rijst mag nooit stilletjes gekookt worden
  final strict = modifier == 'dry';
  List<(Food, double, Portion?)>? chosen, loose, firstFound;
  for (var i = 0; i < words.length && chosen == null; i++) {
    final tier = words.sublist(i);
    // Een losse eigenschap of vorm ("red", "flakes", "powder") is geen product
    if (i > 0 && tier.length == 1 && (tier.first.length < 3 || _generic.hasMatch(tier.first))) break;
    bool tierOk(Food f) => plainOk(f) && tier.every((w) => _hasWord(f.name, w));
    bool good(Food f) => tierOk(f) && wanted!.hasMatch(f.name.toLowerCase());
    final asTyped = tier.join(' ');
    final single = tier.map(_singular).join(' ');
    for (final v in variants) {
      for (final q in {asTyped, single}) {
        final opts = resolve(item('$q $v'));
        if (opts.isNotEmpty) firstFound ??= opts;
        if (opts.any((o) => good(o.$1))) {
          chosen = ordered(opts, good);
          break;
        }
      }
      if (chosen != null) break;
    }
    if (chosen != null) break;
    var opts = resolve(item(asTyped));
    if (single != asTyped && !opts.any((o) => tierOk(o.$1))) opts = resolve(item(single));
    if (opts.isNotEmpty) firstFound ??= opts;
    if (strict && opts.any((o) => good(o.$1))) {
      chosen = ordered(opts, good);
    } else if (strict) {
      if (opts.any((o) => tierOk(o.$1))) loose ??= ordered(opts, tierOk);
    } else if (opts.any((o) => tierOk(o.$1))) {
      chosen = ordered(opts, tierOk);
    }
  }
  final sure = chosen != null;
  chosen ??= loose;
  final options = chosen ?? firstFound ?? const <(Food, double, Portion?)>[];
  final top = options.isEmpty ? null : options.first;
  var check = !sure;
  String? why = sure ? null : 'unsure';
  if (top != null && !minor) {
    // Stuks zonder gewicht: als de databank geen stuk kent, is 100 g per stuk een gok
    if (count != null && grams == null && unitGrams == null && top.$3 == null) {
      check = true;
      why ??= 'amount';
    }
    if (guessedAmount) {
      check = true;
      why ??= 'amount';
    }
    final kcal = (top.$1.per100g['energy'] ?? 0) * top.$2 / 100;
    if (top.$2 > 2000 || kcal > 3000) {
      check = true;
      why ??= 'amount';
    }
  }
  return RecipeMatch(l, item(food), options, check: check, why: why ?? (minor ? 'minor' : null));
}
