/// Snel loggen met een zin (getypt of ingesproken), bv. "200 g chicken and a bowl of rice" of
/// "2 eieren en een snee volkoren brood". Elk stuk wordt een hoeveelheid plus een zoekterm.
library;

class QuickItem {
  const QuickItem(this.query, {this.grams, this.count, this.unitGrams, this.unit, this.after, this.afterCount, this.ml});
  final String query;

  /// Gewicht als het gezegd werd (gram, ml of kg).
  final double? grams;

  /// Als het gezegd werd in ml, cl of l: het volume (dan staat het ook in [grams], als 1 g per ml). Een drank weegt
  /// per ml iets meer of minder (zie mlDensity).
  final double? ml;

  /// Aantal stuks of porties ("2 eggs", "een kom").
  final double? count;

  /// Geschat gewicht van één eenheid als die genoemd werd (kom, glas, eetlepel, ...).
  final double? unitGrams;

  /// De genoemde eenheid in het Engels (slice, glass, pint, rasher, ...), zodat het gewicht bij het product kan
  /// passen: een punt pizza weegt meer dan een sneetje brood, een plakje ham minder.
  final String? unit;

  /// Het product vóór "met"/"with" ("koffie met melk", "2 sneetjes brood met ham") en hoeveel daarvan: dan is dit
  /// een scheutje of beleg, geen volle portie.
  final String? after;
  final double? afterCount;

  /// Hetzelfde met een andere zoekterm (na een alias).
  QuickItem withQuery(String q) =>
      QuickItem(q, grams: grams, count: count, unitGrams: unitGrams, unit: unit, after: after, afterCount: afterCount, ml: ml);

  @override
  String toString() => 'QuickItem($query, grams: $grams, count: $count, unit: ${unit ?? '-'} $unitGrams, after: $after)';
}

const _numbers = {
  'a': 1.0, 'an': 1.0, 'one': 1.0, 'een': 1.0, 'één': 1.0, 'two': 2.0, 'twee': 2.0, 'three': 3.0, 'drie': 3.0, 'four': 4.0, //
  'vier': 4.0, 'five': 5.0, 'vijf': 5.0, 'six': 6.0, 'zes': 6.0, 'seven': 7.0, 'zeven': 7.0, 'eight': 8.0, 'acht': 8.0, //
  'nine': 9.0, 'negen': 9.0, 'ten': 10.0, 'tien': 10.0, 'half': 0.5, 'halve': 0.5, 'anderhalf': 1.5, 'anderhalve': 1.5, //
  'some': 1.0, 'wat': 1.0, //
};

/// Eenheden met een geschat gewicht per stuk (gram) en hun naam in het Engels. Een pint is een Britse pint
/// (568 ml), een Belgisch pintje 25 cl.
const _units = <String, (double, String)>{
  'bowl': (250, 'bowl'), 'bowls': (250, 'bowl'), 'kom': (250, 'bowl'), 'kommen': (250, 'bowl'), 'kommetje': (200, 'bowl'), //
  'cup': (240, 'cup'), 'cups': (240, 'cup'), 'kopje': (150, 'cup'), 'kopjes': (150, 'cup'), 'tas': (150, 'cup'), //
  'tasje': (150, 'cup'), 'mug': (250, 'mug'), 'mugs': (250, 'mug'), 'mok': (250, 'mug'), //
  'glass': (200, 'glass'), 'glasses': (200, 'glass'), 'glas': (200, 'glass'), 'glazen': (200, 'glass'), //
  'glaasje': (200, 'glass'), //
  'pint': (568, 'pint'), 'pints': (568, 'pint'), 'pintje': (250, 'pint'), 'pintjes': (250, 'pint'), //
  'can': (330, 'can'), 'cans': (330, 'can'), 'blikje': (330, 'can'), 'blikjes': (330, 'can'), //
  'plate': (350, 'plate'), 'bord': (350, 'plate'), 'borden': (350, 'plate'), //
  'tablespoon': (15, 'tbsp'), 'tablespoons': (15, 'tbsp'), 'tbsp': (15, 'tbsp'), 'eetlepel': (15, 'tbsp'), //
  'eetlepels': (15, 'tbsp'), 'el': (15, 'tbsp'), //
  'teaspoon': (5, 'tsp'), 'teaspoons': (5, 'tsp'), 'tsp': (5, 'tsp'), 'theelepel': (5, 'tsp'), 'theelepels': (5, 'tsp'), //
  'tl': (5, 'tsp'), 'koffielepel': (5, 'tsp'), 'koffielepels': (5, 'tsp'), //
  'handful': (30, 'handful'), 'handfuls': (30, 'handful'), 'handvol': (30, 'handful'), 'handje': (30, 'handful'), //
  'slice': (35, 'slice'), 'slices': (35, 'slice'), 'snee': (35, 'slice'), 'sneetje': (35, 'slice'), //
  'sneetjes': (35, 'slice'), 'sneden': (35, 'slice'), 'punt': (100, 'slice'), 'punten': (100, 'slice'), //
  'plak': (20, 'thin slice'), 'plakje': (20, 'thin slice'), 'plakjes': (20, 'thin slice'), 'plakken': (20, 'thin slice'), //
  'rasher': (25, 'rasher'), 'rashers': (25, 'rasher'), 'reepje': (25, 'rasher'), 'reepjes': (25, 'rasher'), //
  'bag': (30, 'bag'), 'bags': (30, 'bag'), 'packet': (30, 'bag'), 'packets': (30, 'bag'), 'zakje': (30, 'bag'), //
  'zakjes': (30, 'bag'), //
  'scoop': (30, 'scoop'), 'scoops': (30, 'scoop'), 'schep': (30, 'scoop'), 'schepje': (30, 'scoop'), //
  'schepjes': (30, 'scoop'), //
  'portion': (150, 'portion'), 'portie': (150, 'portion'), 'porties': (150, 'portion'), 'serving': (150, 'portion'), //
  'servings': (150, 'portion'), //
};

/// Een eenheid zonder product erbij: "a pint" of "een pintje" is bier.
const _unitAlone = {'pint': 'beer'};

/// Woorden die alleen een stuk aanduiden (het product bepaalt het gewicht).
const _pieces = {'piece', 'pieces', 'stuk', 'stuks', 'stukje', 'stukjes'};

/// Niet bij "with no added sugar" of "met minder suiker": dat zegt iets over het product zelf (zie splitSugarAsk).
final _splitter = RegExp(
  r'\s*(?:(?<!\d),|,(?!\d)|;|\+|&|\band\b|\ben\b|\bwith\b(?!\s+(no|less|reduced|low|lower)(\s+added)?\s+sugars?\b)|'
  r'\bmet\b(?!\s+(minder|weinig)\s+suikers?\b)|\bplus\b)\s*',
  caseSensitive: false,
);
final _withWord = RegExp(r'\b(with|met)\b', caseSensitive: false);
final _amount = RegExp(r'^(\d+(?:[.,]\d+)?)\s*(kg|g|gr|gram|grams|gramme|ml|cl|l)?\b\s*(.*)$', caseSensitive: false);
final _filler = RegExp(r'^(?:of|van|de|het|the|some|wat|a|an|een)\s+', caseSensitive: false);

/// Woorden die geen deel van een productnaam zijn (hoeveelheid, eenheid, verbindingswoord).
final _qtyToken = RegExp(r'^\d+(?:[.,]\d+)?(?:kg|g|gr|ml|cl|l)?$', caseSensitive: false);
const _notFood = {'of', 'van', 'de', 'het', 'the', 'kg', 'g', 'gr', 'gram', 'grams', 'gramme', 'ml', 'cl', 'l'};

/// Ingesproken tekst heeft geen komma's: "100 g chicken 2 eggs a glass of milk". Begin een nieuw stuk bij elke
/// hoeveelheid (getal of telwoord) die volgt op een productnaam.
List<String> _splitOnQuantities(String part) {
  final out = <String>[];
  var current = <String>[];
  var hasFood = false;
  for (final w in part.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
    final lw = w.toLowerCase();
    final isQty = _qtyToken.hasMatch(lw) || _numbers.containsKey(lw);
    if (isQty && hasFood) {
      out.add(current.join(' '));
      current = [];
      hasFood = false;
    }
    current.add(w);
    if (!isQty && !_notFood.contains(lw) && !_units.containsKey(lw) && !_pieces.contains(lw)) hasFood = true;
  }
  if (current.isNotEmpty) out.add(current.join(' '));
  return out;
}

/// De stukken van de zin, met per stuk of het na "met"/"with" kwam.
List<(String, bool)> _parts(String text) {
  final out = <(String, bool)>[];
  var start = 0;
  var withBefore = false;
  void add(String chunk, bool withIt) {
    for (final (i, p) in _splitOnQuantities(chunk).indexed) {
      out.add((p, withIt && i == 0));
    }
  }

  for (final m in _splitter.allMatches(text)) {
    add(text.substring(start, m.start), withBefore);
    withBefore = _withWord.hasMatch(m.group(0)!);
    start = m.end;
  }
  add(text.substring(start), withBefore);
  return out;
}

List<QuickItem> parseQuick(String text) {
  final out = <QuickItem>[];
  QuickItem? previous;
  for (var (part, withPrevious) in _parts(text.trim())) {
    part = part.trim().replaceAll(RegExp(r'[.!?]+$'), '');
    if (part.isEmpty) continue;
    double? grams, count, unitGrams, ml;
    String? unit;
    var rest = part;
    final m = _amount.firstMatch(part);
    if (m != null) {
      final n = double.parse(m.group(1)!.replaceAll(',', '.'));
      final u = m.group(2)?.toLowerCase();
      rest = m.group(3)!.trim();
      switch (u) {
        case 'kg':
          grams = n * 1000;
        case 'l':
          grams = ml = n * 1000;
        case 'cl':
          grams = ml = n * 10;
        case 'ml':
          grams = ml = n;
        case null:
          count = n;
        default:
          grams = n;
      }
    } else {
      final first = rest.split(RegExp(r'\s+')).first.toLowerCase();
      if (_numbers.containsKey(first)) {
        count = _numbers[first];
        rest = rest.substring(first.length).trim();
      }
    }
    // "een halve pizza", "a half pint"
    final half = RegExp(r'^(half|halve)\b\s*', caseSensitive: false).firstMatch(rest);
    if (half != null && count != null && grams == null) {
      count *= 0.5;
      rest = rest.substring(half.end);
    }
    // Eenheid na het getal: "2 slices of bread", "een kom rijst", "half a pint of cider"
    rest = rest.replaceFirst(_filler, '').trim();
    final words = rest.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final w = words.first.toLowerCase();
      if (_units[w] case (final g, final name)) {
        unitGrams = g;
        unit = name;
        count ??= 1;
        rest = words.skip(1).join(' ');
        if (rest.trim().isEmpty && _unitAlone[name] != null) rest = _unitAlone[name]!;
      } else if (_pieces.contains(w)) {
        count ??= 1;
        unit = 'piece';
        rest = words.skip(1).join(' ');
      }
    }
    rest = rest.replaceFirst(_filler, '').trim();
    if (rest.isEmpty) continue;
    // "0 eggs" of "0 g": geen regel van 0 g
    if (count == 0 || grams == 0) continue;
    final item = QuickItem(
      rest,
      grams: grams,
      count: count,
      unitGrams: unitGrams,
      unit: unit,
      after: withPrevious ? previous?.query : null,
      afterCount: withPrevious ? previous?.count : null,
      ml: ml,
    );
    out.add(item);
    previous = item;
  }
  return out;
}
