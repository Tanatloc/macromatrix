/// De ingebouwde database met basisvoedingsmiddelen uit Europese en Amerikaanse tabellen, alleen-lezen.
/// Gebouwd met tool/build_foods.py.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:sqlite3/common.dart';

import 'food.dart';
import 'search_terms.dart';

/// Een verhaspelde naam uit de bron rechtzetten zonder de databank opnieuw te bouwen (N85):
/// "Milk, whole, 3.5, (UHT), % fat" wordt "Milk, whole, 3.5% fat (UHT)".
///
/// Met [source] ook namen die in het Engels iets anders betekenen: Britse "Potato chips" (CoFID) zijn frietjes, geen
/// zakje chips (NF-7), en Noors "Havremel" (MVT, "Oatmeal") is havermeel, geen havermout (NW-13).
String tidyFoodName(String name, {String? source, String? local}) {
  var n = name.replaceFirstMapped(RegExp(r', (\d+(?:\.\d+)?), (\([^)]*\)), % fat'), (m) => ', ${m[1]}% fat ${m[2]}');
  if (source == 'cofid') n = n.replaceFirst(RegExp(r'^Potato chips\b'), 'French fries');
  if (source == 'mvt' && (local ?? '').startsWith('Havremel')) n = n.replaceFirst(RegExp(r'^Oatmeal\b'), 'Oat flour');
  return n;
}

class FoodDb {
  /// Openen gebeurt per platform (lib/platform/): als bestand op gsm en pc, in het geheugen in de browser.
  FoodDb(this._db);
  final CommonDatabase _db;

  static const asset = 'assets/db/foods.db';

  /// Bronnen in de ingebouwde database (prefix van [Food.ref]).
  static const dbSources = {'ciqual', 'slv', 'mvt', 'frida', 'cofid', 'bls', 'usda_sr', 'usda_fnd', 'usda_fndds'};

  static bool isDbRef(String ref) => dbSources.contains(ref.split(':').first);

  /// Vingerafdruk van de waarden in deze versie van de database (leeg bij een oude database zonder meta-tabel).
  String get version {
    try {
      final rows = _db.select("SELECT value FROM meta WHERE key = 'version'");
      return rows.isEmpty ? '' : rows.first['value'] as String;
    } on SqliteException {
      return '';
    }
  }

  Food _food(Row r) {
    final local = r['name_local'] as String;
    return Food(
      ref: '${r['source']}:${r['source_id']}',
      name: tidyFoodName(r['name'] as String, source: r['source'] as String, local: local),
      localName: local.isEmpty ? null : local,
      category: (r['category'] as String).isEmpty ? null : r['category'] as String,
      source: FoodSource.fromDb(r['source'] as String),
      per100g: decodeNutrients(r['nutrients'] as String),
      estimated: (jsonDecode(r['estimated'] as String) as Map).cast<String, String>(),
      label: switch (r.containsKey('label') ? r['label'] : null) {
        final String l when l.isNotEmpty => FoodLabel.fromJson((jsonDecode(l) as Map).cast<String, Object?>()),
        _ => null,
      },
      portions: [
        for (final row in _db.select('SELECT label, grams FROM portions WHERE food_id = ? ORDER BY rowid', [r['id']]))
          Portion(row['label'] as String, (row['grams'] as num).toDouble()),
      ],
    );
  }

  /// Voedingsmiddel op verwijzing, bv. `ciqual:13000`.
  Food? byRef(String ref) {
    final i = ref.indexOf(':');
    if (i < 0) return null;
    final rows = _db.select('SELECT * FROM foods WHERE source = ? AND source_id = ?', [ref.substring(0, i), ref.substring(i + 1)]);
    return rows.isEmpty ? null : _food(rows.first);
  }

  /// Zoeken op naam (Engels of de taal van de bron). Nederlandse woorden worden vertaald (zie search_terms.dart), en
  /// een woord vindt ook zijn andere spellingen ([otherSpellings]: "muesli" ook "müsli"). Namen waarin ook één van
  /// [alsoWith] staat (bv. "sugar" of "sweet" bij "sugar free muesli") vallen nooit weg door [limit]: ze staan op hun
  /// plaats in de rangschikking, ook bij een woord met honderden treffers (yoghurt).
  List<Food> search(String query, {int limit = 50, List<String> alsoWith = const []}) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];
    final words = [for (final t in tokens) [t, ...?otherSpellings[t]]];
    final where = [for (final w in words) '(${List.filled(w.length, 'search LIKE ?').join(' OR ')})'].join(' AND ');
    final params = [
      for (final w in words)
        for (final t in w) '%$t%',
    ];
    final rows = _db.select('SELECT * FROM foods WHERE $where LIMIT 600', params);
    final also = alsoWith.isEmpty
        ? const <Row>[]
        : _db.select('SELECT * FROM foods WHERE $where AND (${List.filled(alsoWith.length, 'search LIKE ?').join(' OR ')}) LIMIT 600', [
            ...params,
            for (final a in alsoWith) '%$a%',
          ]);
    final alsoIds = {for (final r in also) r['id']};
    final seen = <Object?>{};
    final all = [
      for (final r in [...rows, ...also])
        if (seen.add(r['id'])) r,
    ];
    // Bij gelijke stand de volgorde van de databank (sort is niet stabiel)
    final ranked = [for (final (i, r) in all.indexed) (_rank(r, tokens, sugar: alsoWith.isNotEmpty) * 1000 + i, r)]
      ..sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (final (i, (_, r)) in ranked.indexed)
        if (i < limit || alsoIds.contains(r['id'])) _food(r),
    ];
  }

  /// Lager = beter.
  /// 1. Hoe goed de naam overeenkomt: "Banana, raw" voor "banana" vóór "Pepper, banana".
  /// 2. Bij een goede overeenkomst: Europese bronnen vóór USDA.
  /// 3. De gewone vorm (fruit rauw, rijst en pasta gekookt), dan producten met veel gegevens, dan kortere namen.
  /// Met [sugar] (een suikerwens bij het zoeken) is "reduced sugar" geen bijzondere vorm.
  static int _rank(Row r, List<String> tokens, {bool sugar = false}) {
    final name = sameSpelling((r['name'] as String).toLowerCase());
    final source = FoodSource.fromDb(r['source'] as String);
    final nutrientCount = ':'.allMatches(r['nutrients'] as String).length;

    final parts = name.split(',').map((s) => s.trim()).toList();
    final first = parts.first;
    final t = tokens.first;
    bool same(String s) => s == t || s == '${t}s' || s == '${t}es';
    int match;
    // Soms staat een categorie van één woord voorop ("Fish, salmon, ...", "Nuts, almonds, ..."): dan telt ook
    // het tweede deel, maar iets minder dan een naam die er zelf mee begint
    final categoryFirst = parts.length > 1 && !first.contains(' ') && same(parts[1]);
    if (same(first)) {
      match = 0;
    } else if (first.startsWith(t) || categoryFirst) {
      match = 1;
    } else if (RegExp('\\b${RegExp.escape(t)}(s|es)?\\b').hasMatch(name)) {
      match = 2;
    } else if (RegExp('\\b${RegExp.escape(t)}').hasMatch(name)) {
      // Begin van een ander woord: "egg" in "eggplant"
      match = 3;
    } else {
      // Midden in een woord: "cola" in "chocolate"
      match = 4;
    }
    // Een tweede zoekwoord dat alleen als stukje voorkomt, maakt het een slechtere treffer
    for (final o in tokens.skip(1)) {
      if (!RegExp('\\b${RegExp.escape(o)}').hasMatch(name)) match = math.max(match, 3);
    }
    final tier = match <= 1 ? 0 : match; // exacte en "begint met"-treffers samen, zodat Europa daar voorgaat
    final europe = source.european ? 0 : 1;
    final q = tokens.join(' ');
    // De gewone vorm: fruit en groenten rauw, maar granen, pasta en peulvruchten gekookt (P156)
    final cooks = RegExp(r'\b(rice|pasta|spaghetti|macaroni|noodles?|quinoa|lentils?|beans?|chickpeas?|barley|couscous|bulgur|egg|eggs)\b').hasMatch(name);
    final raw = (cooks && !RegExp(r'\b(raw|dry|uncooked)\b').hasMatch(q)
            ? RegExp(r'\b(cooked|boiled)\b').hasMatch(name)
            : RegExp(r'\braw\b').hasMatch(name))
        ? 0
        : 1;
    // Wat je zoekt is de drank of het product zelf, niet een ingrediënt of cocktail ervan (tenzij je dat typt)
    final special = sugar ? name.replaceAll(RegExp(r'reduced[- ]sugars?'), '') : name;
    final odd =
        (RegExp(r'\b(irish|liqueur|cocktail|bulk|powder(ed)?|dehydrated|concentrate)\b').hasMatch(name) &&
                !RegExp(r'irish|liqueur|cocktail|bulk|powder|dehydrated|concentrate|whey|protein').hasMatch(q)) ||
            (RegExp(r'\b(coffee|tea|cocoa)\b').hasMatch(name) &&
                RegExp(r'\b(ground|beans?|leaves|leaf|instant|granules)\b').hasMatch(name) &&
                !RegExp(r'ground|bean|lea[fv]|instant|granule').hasMatch(q)) ||
            // Gehakt, diepvries, lactosevrij, "light" en energiedrank alleen als je ze noemt
            (RegExp(r'\b(minced?|frozen|lactose|reduced|energy drink)\b').hasMatch(special) &&
                !RegExp(r'minc|frozen|lactose|reduced|energy').hasMatch(q))
        ? 1
        : 0;
    return (((((tier * 2 + odd) * 2 + europe) * 5 + match) * 2 + raw) * 2 + (nutrientCount < 30 ? 1 : 0)) * 1000 + name.length.clamp(0, 999);
  }

  /// SQL-uitdrukking voor de hoeveelheid van een voedingsstof per 100 g (ook voor afgeleide stoffen).
  static String _valueSql(String key) => switch (key) {
    'epa_dha' => "(coalesce(json_extract(nutrients, '\$.epa'), 0) + coalesce(json_extract(nutrients, '\$.dha'), 0)) * 1000",
    'met_cys' => "(json_extract(nutrients, '\$.methionine') + json_extract(nutrients, '\$.cystine'))",
    'phe_tyr' => "(json_extract(nutrients, '\$.phenylalanine') + json_extract(nutrients, '\$.tyrosine'))",
    _ => "json_extract(nutrients, '\$.$key')",
  };

  // De databank verandert niet terwijl de app draait: deze zware zoekopdrachten (een volledige doorloop van alle
  // producten) hoeven maar één keer. Ze liepen bij elke opbouw van Vandaag (weekrapport, tips) en kostten op een gsm,
  // waar de databank van de opslag gelezen wordt, ±1 s per tik (27-10).
  final _richest = <String, List<(Food, double)>>{};
  final _siblings = <String, Map<String, List<(String, double, List<String>)>>>{};

  /// "Oracle": voedingsmiddelen die het rijkst zijn aan een voedingsstof, per 100 g of per 100 kcal.
  /// Alleen gemeten waarden (geen schattingen); producten met heel weinig energie tellen niet mee per kcal.
  List<(Food, double)> richestIn(String key, {bool perKcal = false, int limit = 40}) =>
      _richest.putIfAbsent('$key|$perKcal|$limit', () => List.unmodifiable(_richestIn(key, perKcal: perKcal, limit: limit)));

  List<(Food, double)> _richestIn(String key, {required bool perKcal, required int limit}) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(key)) return const [];
    final value = _valueSql(key);
    final score = perKcal ? '$value / json_extract(nutrients, \'\$.energy\') * 100' : value;
    final rows = _db.select(
      '''
      SELECT *, $score AS score FROM foods
      WHERE $value > 0
        AND json_extract(estimated, '\$.$key') IS NULL
        AND json_extract(nutrients, '\$.energy') >= ${perKcal ? 15 : 0}
        AND lower(name) NOT LIKE '%babyfood%' AND lower(name) NOT LIKE '%infant formula%'
      ORDER BY score DESC LIMIT ?''',
      [limit],
    );
    return [for (final r in rows) (_food(r), (r['score'] as num).toDouble())];
  }

  /// Omgekeerd Orakel: voedingsmiddelen met het minst van een voedingsstof, per 100 g of per 100 kcal, eventueel
  /// alleen uit voedingsgroepen [groups] (leeg = alles). Alleen gemeten waarden (0 telt mee, een ontbrekende waarde
  /// niet) en geen producten onder [minEnergy] kcal per 100 g: water, thee en light frisdrank hebben van alles het
  /// minst. Bij gelijke waarden eerst de kortste naam (de gewone vorm: "Wit brood" voor "Wit brood, met ...").
  List<(Food, double)> leastIn(String key, {bool perKcal = false, Set<String> groups = const {}, int limit = 1500, double minEnergy = 10}) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(key)) return const [];
    final value = _valueSql(key);
    final score = perKcal ? '$value / json_extract(nutrients, \'\$.energy\') * 100' : value;
    final inGroups = groups.isEmpty
        ? ''
        : "AND json_extract(CASE WHEN label != '' THEN label END, '\$.g') IN (${List.filled(groups.length, '?').join(',')})";
    final rows = _db.select(
      '''
      SELECT *, $score AS score FROM foods
      WHERE $value IS NOT NULL AND $value >= 0
        AND json_extract(estimated, '\$.$key') IS NULL
        AND json_extract(nutrients, '\$.energy') >= ?
        AND lower(name) NOT LIKE '%babyfood%' AND lower(name) NOT LIKE '%infant formula%'
        $inGroups
      ORDER BY score ASC, length(name) ASC LIMIT ?''',
      [math.max(minEnergy, perKcal ? 15.0 : 0.0), ...groups, limit],
    );
    return [for (final r in rows) (_food(r), (r['score'] as num).toDouble())];
  }

  /// Waarden van een voedingsstof per 100 g voor alle producten met dit label-voedingsmiddel ([FoodLabel.food]),
  /// per "voedingsmiddel|groep|bereiding". Om uitschieters (tikfouten in een databank) te herkennen.
  Map<String, List<(String, double, List<String>)>> siblingValues(String key, Set<String> labelFoods) =>
      _siblings.putIfAbsent('$key|${(labelFoods.toList()..sort()).join('|')}', () => _siblingValues(key, labelFoods));

  Map<String, List<(String, double, List<String>)>> _siblingValues(String key, Set<String> labelFoods) {
    if (labelFoods.isEmpty || !RegExp(r'^[a-z0-9_]+$').hasMatch(key)) return const {};
    final value = _valueSql(key);
    final rows = _db.select('''
      SELECT source, source_id, label, $value AS v FROM foods
      WHERE label != '' AND json_extract(label, '\$.f') IN (${List.filled(labelFoods.length, '?').join(',')})
        AND $value IS NOT NULL AND json_extract(estimated, '\$.$key') IS NULL''', labelFoods.toList());
    final out = <String, List<(String, double, List<String>)>>{};
    for (final r in rows) {
      final l = (jsonDecode(r['label'] as String) as Map).cast<String, Object?>();
      out.putIfAbsent('${l['f']}|${l['g']}|${l['c']}', () => []).add((
        '${r['source']}:${r['source_id']}',
        (r['v'] as num).toDouble(),
        [...?(l['fl'] as List?)?.cast<String>()],
      ));
    }
    return out;
  }

  /// Bronnen met hun bronvermelding en aantal producten (voor de schermen "Bronnen").
  List<(String, String, int)> sources() => [
    for (final r in _db.select('SELECT source, description, foods FROM sources ORDER BY rowid'))
      (r['source'] as String, r['description'] as String, r['foods'] as int),
  ];

  void close() => _db.close();
}
