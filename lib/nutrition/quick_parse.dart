/// Snel loggen met een zin (getypt of ingesproken), bv. "200 g chicken and a bowl of rice" of
/// "2 eieren en een snee volkoren brood". Elk stuk wordt een hoeveelheid plus een zoekterm.
library;

class QuickItem {
  const QuickItem(this.query, {this.grams, this.count, this.unitGrams});
  final String query;

  /// Gewicht als het gezegd werd (gram, ml of kg).
  final double? grams;

  /// Aantal stuks of porties ("2 eggs", "een kom").
  final double? count;

  /// Geschat gewicht van één eenheid als die genoemd werd (kom, glas, eetlepel, ...).
  final double? unitGrams;

  @override
  String toString() => 'QuickItem($query, grams: $grams, count: $count, unit: $unitGrams)';
}

const _numbers = {
  'a': 1.0, 'an': 1.0, 'one': 1.0, 'een': 1.0, 'één': 1.0, 'two': 2.0, 'twee': 2.0, 'three': 3.0, 'drie': 3.0, 'four': 4.0, //
  'vier': 4.0, 'five': 5.0, 'vijf': 5.0, 'six': 6.0, 'zes': 6.0, 'half': 0.5, 'halve': 0.5, 'some': 1.0, 'wat': 1.0, //
};

/// Eenheden met een geschat gewicht per stuk (gram).
const _units = {
  'bowl': 250.0, 'bowls': 250.0, 'kom': 250.0, 'kommen': 250.0, 'kommetje': 200.0, //
  'cup': 240.0, 'cups': 240.0, 'kopje': 150.0, 'kopjes': 150.0, 'mug': 250.0, 'mok': 250.0, //
  'glass': 200.0, 'glasses': 200.0, 'glas': 200.0, 'glazen': 200.0, //
  'plate': 350.0, 'bord': 350.0, 'borden': 350.0, //
  'tablespoon': 15.0, 'tablespoons': 15.0, 'tbsp': 15.0, 'eetlepel': 15.0, 'eetlepels': 15.0, 'el': 15.0, //
  'teaspoon': 5.0, 'teaspoons': 5.0, 'tsp': 5.0, 'theelepel': 5.0, 'theelepels': 5.0, 'tl': 5.0, //
  'handful': 30.0, 'handfuls': 30.0, 'handvol': 30.0, 'handje': 30.0, //
  'slice': 35.0, 'slices': 35.0, 'snee': 35.0, 'sneetje': 35.0, 'sneetjes': 35.0, 'sneden': 35.0, 'plak': 20.0, 'plakje': 20.0, 'plakjes': 20.0, //
  'scoop': 30.0, 'scoops': 30.0, 'schep': 30.0, 'schepje': 30.0, //
  'portion': 150.0, 'portie': 150.0, 'serving': 150.0, //
};

/// Woorden die alleen een stuk aanduiden (het product bepaalt het gewicht).
const _pieces = {'piece', 'pieces', 'stuk', 'stuks', 'stukje', 'stukjes'};

final _splitter = RegExp(r'\s*(?:(?<!\d),|,(?!\d)|;|\+|&|\band\b|\ben\b|\bwith\b|\bmet\b|\bplus\b)\s*', caseSensitive: false);
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

List<QuickItem> parseQuick(String text) {
  final out = <QuickItem>[];
  for (var part in [for (final p in text.trim().split(_splitter)) ..._splitOnQuantities(p)]) {
    part = part.trim().replaceAll(RegExp(r'[.!?]+$'), '');
    if (part.isEmpty) continue;
    double? grams, count, unitGrams;
    var rest = part;
    final m = _amount.firstMatch(part);
    if (m != null) {
      final n = double.parse(m.group(1)!.replaceAll(',', '.'));
      final unit = m.group(2)?.toLowerCase();
      rest = m.group(3)!.trim();
      switch (unit) {
        case 'kg' || 'l':
          grams = n * 1000;
        case 'cl':
          grams = n * 10;
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
    // Eenheid na het getal: "2 slices of bread", "een kom rijst"
    final words = rest.split(RegExp(r'\s+'));
    if (words.isNotEmpty) {
      final w = words.first.toLowerCase();
      if (_units.containsKey(w)) {
        unitGrams = _units[w];
        count ??= 1;
        rest = words.skip(1).join(' ');
      } else if (_pieces.contains(w)) {
        count ??= 1;
        rest = words.skip(1).join(' ');
      }
    }
    rest = rest.replaceFirst(_filler, '').trim();
    if (rest.isEmpty) continue;
    out.add(QuickItem(rest, grams: grams, count: count, unitGrams: unitGrams));
  }
  return out;
}
