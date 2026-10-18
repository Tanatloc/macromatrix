/// De ingebouwde database met basisvoedingsmiddelen uit Europese en Amerikaanse tabellen, alleen-lezen.
/// Gebouwd met tool/build_foods.py.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart';

import 'food.dart';
import 'search_terms.dart';

class FoodDb {
  /// Openen gebeurt per platform (lib/platform/): als bestand op gsm en pc, in het geheugen in de browser.
  FoodDb(this._db);
  final CommonDatabase _db;

  static const asset = 'assets/db/foods.db';

  /// Bronnen in de ingebouwde database (prefix van [Food.ref]).
  static const dbSources = {'ciqual', 'slv', 'mvt', 'usda_sr', 'usda_fnd'};

  static bool isDbRef(String ref) => dbSources.contains(ref.split(':').first);

  Food _food(Row r) {
    final local = r['name_local'] as String;
    return Food(
      ref: '${r['source']}:${r['source_id']}',
      name: r['name'] as String,
      localName: local.isEmpty ? null : local,
      category: (r['category'] as String).isEmpty ? null : r['category'] as String,
      source: FoodSource.fromDb(r['source'] as String),
      per100g: decodeNutrients(r['nutrients'] as String),
      estimated: (jsonDecode(r['estimated'] as String) as Map).cast<String, String>(),
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

  /// Zoeken op naam (Engels of de taal van de bron). Nederlandse woorden worden vertaald (zie search_terms.dart).
  List<Food> search(String query, {int limit = 50}) {
    final tokens = searchTokens(query);
    if (tokens.isEmpty) return const [];
    final where = List.filled(tokens.length, 'search LIKE ?').join(' AND ');
    final rows = _db.select('SELECT * FROM foods WHERE $where LIMIT 600', [for (final t in tokens) '%$t%']);
    final ranked = [for (final r in rows) (_rank(r, tokens), r)]..sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final (_, r) in ranked.take(limit)) _food(r)];
  }

  /// Lager = beter.
  /// 1. Hoe goed de naam overeenkomt: "Banana, raw" voor "banana" vóór "Pepper, banana".
  /// 2. Bij een goede overeenkomst: Europese bronnen vóór USDA.
  /// 3. Rauwe/basisvorm, dan producten met veel gegevens, dan kortere namen.
  static int _rank(Row r, List<String> tokens) {
    final name = (r['name'] as String).toLowerCase();
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
    } else if (RegExp('\\b${RegExp.escape(t)}').hasMatch(name)) {
      match = 2;
    } else {
      match = 3;
    }
    final tier = match <= 1 ? 0 : match; // exacte en "begint met"-treffers samen, zodat Europa daar voorgaat
    final europe = source.european ? 0 : 1;
    final raw = RegExp(r'\braw\b').hasMatch(name) ? 0 : 1;
    return ((((tier * 2 + europe) * 4 + match) * 2 + raw) * 2 + (nutrientCount < 30 ? 1 : 0)) * 1000 + name.length.clamp(0, 999);
  }

  /// SQL-uitdrukking voor de hoeveelheid van een voedingsstof per 100 g (ook voor afgeleide stoffen).
  static String _valueSql(String key) => switch (key) {
    'epa_dha' => "(coalesce(json_extract(nutrients, '\$.epa'), 0) + coalesce(json_extract(nutrients, '\$.dha'), 0)) * 1000",
    'met_cys' => "(json_extract(nutrients, '\$.methionine') + json_extract(nutrients, '\$.cystine'))",
    'phe_tyr' => "(json_extract(nutrients, '\$.phenylalanine') + json_extract(nutrients, '\$.tyrosine'))",
    _ => "json_extract(nutrients, '\$.$key')",
  };

  /// "Oracle": voedingsmiddelen die het rijkst zijn aan een voedingsstof, per 100 g of per 100 kcal.
  /// Alleen gemeten waarden (geen schattingen); producten met heel weinig energie tellen niet mee per kcal.
  List<(Food, double)> richestIn(String key, {bool perKcal = false, int limit = 40}) {
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

  /// Bronnen met hun bronvermelding en aantal producten (voor de schermen "Bronnen").
  List<(String, String, int)> sources() => [
    for (final r in _db.select('SELECT source, description, foods FROM sources ORDER BY rowid'))
      (r['source'] as String, r['description'] as String, r['foods'] as int),
  ];

  void close() => _db.close();
}
