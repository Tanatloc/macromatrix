/// Gegevens overnemen uit andere apps (Cronometer, MyFitnessPal). Herkent bestanden aan hun kolommen, niet aan hun
/// naam, omdat de exports per versie verschillen. Zonder Flutter, zodat het testbaar is.
///
/// - Cronometer (gratis export, CSV): "servings" (elk product met alle voedingsstoffen), biometrics, exercises,
///   notes, en de dagtotalen als er geen servings zijn.
/// - MyFitnessPal (ZIP of CSV): het dagboek per product als dat in de export zit, anders de totalen per maaltijd
///   ("Nutrition Summary"); beweging en metingen.
///
/// Elke regel krijgt een vaste id (uit bron, dag, maaltijd, naam, hoeveelheid): opnieuw importeren maakt geen dubbels.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:uuid/uuid.dart';

import '../data/user_db.dart' show Meal;
import '../nutrition/nutrients.dart';
import 'csv.dart';
import '../i18n.dart';

enum ImportSource {
  cronometer('Cronometer', 'cm'),
  myfitnesspal('MyFitnessPal', 'mfp');

  const ImportSource(this.label, this.code);
  final String label;
  final String code;
}

enum WeightUnit { kg, lb }

class ImportedEntry {
  const ImportedEntry({
    required this.id,
    required this.day,
    required this.meal,
    required this.name,
    required this.grams,
    required this.quantity,
    required this.per100g,
    this.time,
    this.brand,
    this.portionLabel,
    this.foodRef = '',
  });
  final String id;
  final String day;

  /// 0 = ontbijt, 1 = lunch, 2 = avondeten, 3 = tussendoortjes (zoals [Meal]).
  final int meal;
  final String? time;
  final String name;
  final String? brand;
  final double grams;
  final double quantity;
  final String? portionLabel;
  final Map<String, double> per100g;
  final String foodRef;
}

class ImportedExercise {
  const ImportedExercise({required this.id, required this.day, required this.name, required this.kcal, this.minutes});
  final String id;
  final String day;
  final String name;
  final double kcal;
  final double? minutes;
}

class ImportedBiometric {
  const ImportedBiometric({required this.id, required this.day, required this.type, required this.value, this.value2, this.time, this.unit});
  final String id;
  final String day;
  final String? time;

  /// Sleutel zoals in [BiometricType] (weight, body_fat, ...) of `custom:<naam>`.
  final String type;
  final double value;
  final double? value2;

  /// Eenheid voor een eigen meting.
  final String? unit;
}

/// Wat er in de gekozen bestanden zit, klaar om te bewaren.
class ImportBatch {
  final entries = <ImportedEntry>[];
  final exercises = <ImportedExercise>[];
  final biometrics = <ImportedBiometric>[];

  /// Notities per dag.
  final notes = <String, String>{};

  /// Per bestand: naam, wat het is (of waarom niet), aantal rijen.
  final files = <(String, String, int)>[];
  final warnings = <String>{};

  /// MyFitnessPal zet geen eenheid bij het gewicht: dan kiest de gebruiker kg of lb.
  bool weightUnitUnknown = false;

  /// De eenheid die gebruikt werd voor gewichten zonder eenheid (gekozen, of geraden).
  WeightUnit weightUnitUsed = WeightUnit.kg;

  Set<String> get days => {for (final e in entries) e.day, for (final b in biometrics) b.day, for (final x in exercises) x.day};
  bool get isEmpty => entries.isEmpty && exercises.isEmpty && biometrics.isEmpty && notes.isEmpty;
}

class Importer {
  Importer(this.source, {this.weightUnit});
  final ImportSource source;

  /// Eenheid voor gewichten zonder eenheid (MyFitnessPal); null = raden (boven 130 is het waarschijnlijk lb).
  final WeightUnit? weightUnit;

  static const _uuid = Uuid();
  final _seen = <String, int>{};

  /// Leest CSV- en ZIP-bestanden. Bestanden die niet herkend worden, staan in [ImportBatch.files] met de reden.
  ImportBatch read(List<(String, Uint8List)> files) {
    final batch = ImportBatch();
    final csvs = <(String, List<List<String>>)>[];
    for (final (name, bytes) in files) {
      if (name.toLowerCase().endsWith('.zip')) {
        try {
          for (final f in ZipDecoder().decodeBytes(bytes).files) {
            if (f.isFile && f.name.toLowerCase().endsWith('.csv')) csvs.add((f.name.split('/').last, parseCsv(_text(f.content))));
          }
        } catch (_) {
          batch.files.add((name, tr('could not open the ZIP file', 'kon het ZIP-bestand niet openen'), 0));
        }
      } else {
        csvs.add((name, parseCsv(_text(bytes))));
      }
    }
    // Cronometer: dagtotalen alleen gebruiken als er geen producten (servings) zijn
    final kinds = {for (final (name, rows) in csvs) name: _kind(rows)};
    final hasItems = kinds.values.any((k) => k == _Kind.items);
    for (final (name, rows) in csvs) {
      final kind = kinds[name]!;
      final before = (batch.entries.length, batch.exercises.length, batch.biometrics.length, batch.notes.length);
      switch (kind) {
        case _Kind.items:
          _items(rows, batch);
        case _Kind.mealTotals:
          if (!hasItems) _totals(rows, batch, perMeal: true);
        case _Kind.dayTotals:
          if (!hasItems) _totals(rows, batch, perMeal: false);
        case _Kind.biometrics:
          _biometrics(rows, batch);
        case _Kind.measurements:
          _measurements(rows, batch);
        case _Kind.exercise:
          _exercise(rows, batch);
        case _Kind.notes:
          _notes(rows, batch);
        case _Kind.unknown:
          break;
      }
      final added =
          batch.entries.length -
          before.$1 +
          batch.exercises.length -
          before.$2 +
          batch.biometrics.length -
          before.$3 +
          batch.notes.length -
          before.$4;
      final label = switch (kind) {
        _Kind.items => tr('diary per product', 'dagboek per product'),
        _Kind.mealTotals =>
          hasItems
              ? tr('totals per meal (not needed: products are listed separately)', 'totalen per maaltijd (niet nodig: producten staan apart)')
              : tr('diary, totals per meal', 'dagboek, totalen per maaltijd'),
        _Kind.dayTotals =>
          hasItems
              ? tr('daily totals (not needed: products are listed separately)', 'dagtotalen (niet nodig: producten staan apart)')
              : tr('diary, totals per day', 'dagboek, totalen per dag'),
        _Kind.biometrics || _Kind.measurements => tr('measurements', 'metingen'),
        _Kind.exercise => tr('exercise', 'beweging'),
        _Kind.notes => tr('notes', 'notities'),
        _Kind.unknown => tr('not recognised, skipped', 'niet herkend, overgeslagen'),
      };
      batch.files.add((name, label, added));
    }
    return batch;
  }

  static String _text(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }

  // ── Herkennen ──

  _Kind _kind(List<List<String>> rows) {
    if (rows.isEmpty) return _Kind.unknown;
    final h = rows.first.map(_norm).toSet();
    bool has(String s) => h.any((x) => x == s || x.startsWith('$s ('));
    final energy = has('energy') || has('calories');
    if (has('metric') && has('amount')) return _Kind.biometrics;
    if (has('food name') || ((has('food') || has('description') || has('item')) && energy)) return _Kind.items;
    if (has('exercise') && (has('minutes') || has('calories burned') || has('exercise calories') || has('exercise minutes'))) return _Kind.exercise;
    if (has('meal') && energy) return _Kind.mealTotals;
    if ((has('date') || has('day')) && energy) return _Kind.dayTotals;
    if (has('weight') && (has('date') || has('day'))) return _Kind.measurements;
    if (has('note') && (has('day') || has('date'))) return _Kind.notes;
    return _Kind.unknown;
  }

  /// Kolomnaam zonder eenheid tussen haakjes, in kleine letters: "B12 (Cobalamin) (µg)" wordt "b12 (cobalamin)".
  static String _norm(String header) => header.trim().toLowerCase().replaceFirst(_unitSuffix, '').trim();

  static final _unitSuffix = RegExp(r'\s*\((g|mg|µg|μg|mcg|ug|iu|kcal|kj|%|% dv|%dv|ml|mmol/l|mg/dl)\)\s*$', caseSensitive: false);

  static String? _unit(String header) {
    final m = _unitSuffix.firstMatch(header.trim());
    if (m == null) return null;
    final u = m.group(1)!.toLowerCase();
    return switch (u) {
      'mcg' || 'ug' || 'μg' => 'µg',
      '% dv' || '%dv' => '%',
      _ => u,
    };
  }

  static Map<String, int> _index(List<String> header) => {for (final (i, h) in header.indexed) _norm(h): i};

  static int? _col(Map<String, int> idx, List<String> names) {
    for (final n in names) {
      if (idx[n] case final i?) return i;
    }
    return null;
  }

  // ── Voedingsstoffen ──

  /// Kolom → (sleutel in de app, factor naar de eenheid van de app), of null als de kolom niet bruikbaar is.
  (String, double)? _nutrientColumn(String header, ImportBatch batch) {
    final name = _norm(header);
    final unit = _unit(header);
    String? key;
    final candidates = {
      name,
      name.split(' (').first.trim(),
      if (name.contains('(')) name.substring(name.indexOf('(') + 1).replaceAll(')', '').trim(),
    };
    for (final c in candidates) {
      key ??= _aliases[c];
    }
    if (key == null) return null;
    final target = key.startsWith('_') ? 'g' : nutrientByKey[key]?.unit;
    if (target == null) return null;

    final from = unit ?? _defaultUnit(key);
    if (from == null) {
      batch.warnings.add(
        tr(
          '${_pretty(header)} has no unit in the export (probably % of the US daily value) and is not imported.',
          '${_pretty(header)} staat zonder eenheid in de export (waarschijnlijk % van de Amerikaanse dagwaarde) en wordt niet overgenomen.',
        ),
      );
      return null;
    }
    if (from == '%') {
      batch.warnings.add(
        tr(
          '${_pretty(header)} is given as % of the US daily value in the export and is not imported.',
          '${_pretty(header)} staat als % van de Amerikaanse dagwaarde in de export en wordt niet overgenomen.',
        ),
      );
      return null;
    }
    final factor = _convert(key, from, target);
    if (factor == null) {
      batch.warnings.add(
        tr(
          '${_pretty(header)} in $from cannot be converted reliably and is not imported.',
          '${_pretty(header)} in $from kan niet betrouwbaar omgerekend worden en wordt niet overgenomen.',
        ),
      );
      return null;
    }
    return (key, factor);
  }

  static String _pretty(String header) => header.trim();

  static String? _defaultUnit(String key) {
    if (key == 'energy') return 'kcal';
    if (key.startsWith('_') ||
        const {
          'protein',
          'carbs',
          'fat',
          'fiber',
          'sugars',
          'starch',
          'sfa',
          'mufa',
          'pufa',
          'trans',
          'water',
          'alcohol',
          'omega3',
          'omega6',
        }.contains(key)) {
      return 'g';
    }
    if (const {'sodium', 'potassium', 'cholesterol', 'caffeine'}.contains(key)) return 'mg';
    return null; // vitaminen en mineralen zonder eenheid: onzeker
  }

  static double? _convert(String key, String from, String to) {
    if (key == 'energy') {
      return switch (from) {
        'kcal' => 1,
        'kj' => 1 / 4.184,
        _ => null,
      };
    }
    // Water staat in ml; 1 g water is 1 ml (N85)
    if (key == 'water' && to == 'ml') return from == 'g' || from == 'ml' ? 1 : null;
    if (from == 'iu') {
      // Vitamine D: 40 IE = 1 µg. Vitamine A en E in IE hangen af van de vorm: niet omrekenen.
      return key == 'vit_d' && to == 'µg' ? 1 / 40 : null;
    }
    const mass = {'g': 1e6, 'mg': 1e3, 'µg': 1.0};
    final a = mass[from], b = mass[to];
    if (a == null || b == null) return null;
    return a / b;
  }

  static const _aliases = {
    'energy': 'energy',
    'calories': 'energy',
    'kcal': 'energy',
    'protein': 'protein',
    'proteins': 'protein',
    'carbs': '_carbs_total',
    'carbohydrates': '_carbs_total',
    'carbohydrate': '_carbs_total',
    'total carbs': '_carbs_total',
    'total carbohydrates': '_carbs_total',
    'net carbs': '_carbs_net',
    'fat': 'fat',
    'total fat': 'fat',
    'fats': 'fat',
    'fiber': 'fiber',
    'fibre': 'fiber',
    'dietary fiber': 'fiber',
    'sugar': 'sugars',
    'sugars': 'sugars',
    'total sugars': 'sugars',
    'starch': 'starch',
    'saturated': 'sfa',
    'saturated fat': 'sfa',
    'saturated fats': 'sfa',
    'monounsaturated': 'mufa',
    'monounsaturated fat': 'mufa',
    'polyunsaturated': 'pufa',
    'polyunsaturated fat': 'pufa',
    'trans fat': 'trans',
    'trans-fats': 'trans',
    'trans fats': 'trans',
    'trans-fat': 'trans',
    'cholesterol': 'cholesterol',
    'omega-3': 'omega3',
    'omega 3': 'omega3',
    'omega-6': 'omega6',
    'omega 6': 'omega6',
    'water': 'water',
    'alcohol': 'alcohol',
    'caffeine': 'caffeine',
    'vitamin a': 'vit_a',
    'vitamin c': 'vit_c',
    'vitamin d': 'vit_d',
    'vitamin e': 'vit_e',
    'vitamin k': 'vit_k',
    'b1': 'b1',
    'thiamin': 'b1',
    'thiamine': 'b1',
    'vitamin b1': 'b1',
    'b2': 'b2',
    'riboflavin': 'b2',
    'vitamin b2': 'b2',
    'b3': 'b3',
    'niacin': 'b3',
    'vitamin b3': 'b3',
    'b5': 'b5',
    'pantothenic acid': 'b5',
    'vitamin b5': 'b5',
    'b6': 'b6',
    'pyridoxine': 'b6',
    'vitamin b6': 'b6',
    'b7': 'b7',
    'biotin': 'b7',
    'b9': 'b9',
    'folate': 'b9',
    'vitamin b9': 'b9',
    'b12': 'b12',
    'cobalamin': 'b12',
    'vitamin b12': 'b12',
    'choline': 'choline',
    'calcium': 'calcium',
    'copper': 'copper',
    'iron': 'iron',
    'magnesium': 'magnesium',
    'manganese': 'manganese',
    'phosphorus': 'phosphorus',
    'potassium': 'potassium',
    'selenium': 'selenium',
    'sodium': 'sodium',
    'zinc': 'zinc',
    'iodine': 'iodine',
    'chromium': 'chromium',
    'molybdenum': 'molybdenum',
    'fluoride': 'fluoride',
    'chloride': 'chloride',
    'histidine': 'histidine',
    'isoleucine': 'isoleucine',
    'leucine': 'leucine',
    'lysine': 'lysine',
    'methionine': 'methionine',
    'cystine': 'cystine',
    'cysteine': 'cystine',
    'phenylalanine': 'phenylalanine',
    'threonine': 'threonine',
    'tryptophan': 'tryptophan',
    'tyrosine': 'tyrosine',
    'valine': 'valine',
  };

  /// Voedingsstoffen van één rij: totalen zoals in de export. Koolhydraten worden "beschikbare koolhydraten" zoals
  /// in de Europese tabellen: netto koolhydraten als die er zijn, anders totaal min vezels.
  Map<String, double> _nutrients(List<String> row, Map<int, (String, double)> columns) {
    final v = <String, double>{};
    for (final MapEntry(key: i, value: (key, factor)) in columns.entries) {
      if (i >= row.length) continue;
      final x = _num(row[i]);
      if (x != null) v[key] = x * factor;
    }
    final net = v.remove('_carbs_net'), total = v.remove('_carbs_total');
    if (net != null) {
      v['carbs'] = net;
    } else if (total != null) {
      v['carbs'] = math.max(0, total - (v['fiber'] ?? 0));
    }
    return v;
  }

  Map<int, (String, double)> _nutrientColumns(List<String> header, ImportBatch batch) => {
    for (final (i, h) in header.indexed) i: ?_nutrientColumn(h, batch),
  };

  // ── Dagboek ──

  void _items(List<List<String>> rows, ImportBatch batch) {
    final header = rows.first, idx = _index(header);
    final day = _col(idx, ['day', 'date']);
    final time = _col(idx, ['time']);
    final meal = _col(idx, ['group', 'meal', 'meal type', 'meal name']);
    final name = _col(idx, ['food name', 'food', 'description', 'item', 'name']);
    final brand = _col(idx, ['brand']);
    final amount = _col(idx, ['amount', 'serving size', 'serving', 'quantity']);
    final columns = _nutrientColumns(header, batch);
    if (day == null || name == null) return;
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      final n = _at(r, name).trim();
      if (d == null || n.isEmpty) continue;
      final totals = _nutrients(r, columns);
      if (totals.isEmpty) continue;
      final amountText = amount == null ? '' : _at(r, amount).trim();
      final grams = _grams(amountText);
      final m = _meal(meal == null ? '' : _at(r, meal));
      final t = time == null ? null : _time(_at(r, time));
      final b = brand == null ? null : _at(r, brand).trim();
      // Zonder gewicht in gram: de hoeveelheid als portie, met de totalen "per portie van 100"
      final g = grams ?? 100;
      batch.entries.add(
        ImportedEntry(
          id: _id(['entry', d, '$m', t ?? '', n, amountText]),
          day: d,
          meal: m,
          time: t,
          name: n,
          brand: b == null || b.isEmpty ? null : b,
          grams: g,
          quantity: grams ?? 1,
          portionLabel: grams == null && amountText.isNotEmpty ? amountText : null,
          per100g: {for (final e in totals.entries) e.key: e.value * 100 / g},
          foodRef: 'import:${source.code}:${n.toLowerCase()}',
        ),
      );
    }
  }

  /// Totalen per maaltijd of per dag (als de export geen producten apart heeft).
  void _totals(List<List<String>> rows, ImportBatch batch, {required bool perMeal}) {
    final header = rows.first, idx = _index(header);
    final day = _col(idx, ['date', 'day']);
    final meal = _col(idx, ['meal', 'group']);
    final note = _col(idx, ['note', 'notes']);
    final columns = _nutrientColumns(header, batch);
    if (day == null) return;
    final mealNames = [for (final m in Meal.values) m.label];
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      if (d == null) continue;
      final totals = _nutrients(r, columns);
      if ((totals['energy'] ?? 0) <= 0) continue;
      final m = perMeal && meal != null ? _meal(_at(r, meal)) : 3;
      final label = perMeal
          ? tr('${source.label}: ${mealNames[m].toLowerCase()} (total)', '${source.label}: ${mealNames[m].toLowerCase()} (totaal)')
          : tr('${source.label}: daily total', '${source.label}: dagtotaal');
      batch.entries.add(
        ImportedEntry(
          id: _id(['total', d, '$m', label]),
          day: d,
          meal: m,
          name: label,
          grams: 100,
          quantity: 1,
          portionLabel: 'totaal',
          per100g: totals,
          foodRef: 'import:${source.code}:totaal',
        ),
      );
      if (note != null) _addNote(batch, d, _at(r, note));
    }
    batch.warnings.add(
      perMeal
          ? tr(
              '${source.label} only provided totals per meal: they come in as one entry per meal, without the separate products.',
              '${source.label} gaf alleen totalen per maaltijd: die komen als één regel per maaltijd, zonder de producten apart.',
            )
          : tr(
              '${source.label} only provided daily totals: they come in as one entry per day.',
              '${source.label} gaf alleen dagtotalen: die komen als één regel per dag.',
            ),
    );
  }

  // ── Beweging, metingen en notities ──

  void _exercise(List<List<String>> rows, ImportBatch batch) {
    final idx = _index(rows.first);
    final day = _col(idx, ['day', 'date']);
    final name = _col(idx, ['exercise', 'activity', 'name']);
    final minutes = _col(idx, ['minutes', 'exercise minutes', 'duration']);
    final kcal = _col(idx, ['calories burned', 'exercise calories', 'calories', 'energy']);
    if (day == null || name == null || kcal == null) return;
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      final k = _num(_at(r, kcal))?.abs();
      final n = _at(r, name).trim();
      if (d == null || k == null || k <= 0 || n.isEmpty) continue;
      final min = minutes == null ? null : _num(_at(r, minutes));
      batch.exercises.add(ImportedExercise(id: _id(['exercise', d, n, '$k', '$min']), day: d, name: n, kcal: k, minutes: min));
    }
  }

  /// Cronometer: één meting per rij (Metric, Unit, Amount).
  void _biometrics(List<List<String>> rows, ImportBatch batch) {
    final idx = _index(rows.first);
    final day = _col(idx, ['day', 'date']);
    final time = _col(idx, ['time']);
    final metric = _col(idx, ['metric']);
    final unit = _col(idx, ['unit']);
    final amount = _col(idx, ['amount']);
    if (day == null || metric == null || amount == null) return;
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      final m = _at(r, metric).trim();
      final u = unit == null ? '' : _at(r, unit).trim();
      final raw = _at(r, amount).trim();
      if (d == null || m.isEmpty || raw.isEmpty) continue;
      final t = time == null ? null : _time(_at(r, time));
      final b = _biometric(m, u, raw, d, t);
      if (b != null) batch.biometrics.add(b);
    }
  }

  ImportedBiometric? _biometric(String metric, String unit, String raw, String day, String? time) {
    final m = metric.toLowerCase(), u = unit.toLowerCase();
    String id(String type) => _id(['bio', day, time ?? '', type, raw]);
    if (m.contains('blood pressure')) {
      final parts = raw.split(RegExp(r'[/\s]+')).map(_num).whereType<double>().toList();
      if (parts.isEmpty) return null;
      return ImportedBiometric(
        id: id('blood_pressure'),
        day: day,
        time: time,
        type: 'blood_pressure',
        value: parts[0],
        value2: parts.length > 1 ? parts[1] : null,
      );
    }
    final v = _num(raw);
    if (v == null) return null;
    if (m == 'weight' || m == 'body weight') {
      return ImportedBiometric(id: id('weight'), day: day, time: time, type: 'weight', value: u.startsWith('lb') ? v * 0.45359237 : v);
    }
    if (m.contains('body fat')) return ImportedBiometric(id: id('body_fat'), day: day, time: time, type: 'body_fat', value: v);
    if (m == 'waist') return ImportedBiometric(id: id('waist'), day: day, time: time, type: 'waist', value: u.startsWith('in') ? v * 2.54 : v);
    if (m.contains('heart rate') || m.contains('pulse')) {
      return ImportedBiometric(id: id('heart_rate'), day: day, time: time, type: 'heart_rate', value: v);
    }
    if (m.contains('glucose')) {
      return ImportedBiometric(id: id('glucose'), day: day, time: time, type: 'glucose', value: u.contains('mg') ? v / 18.016 : v);
    }
    if (m.contains('ketone')) return ImportedBiometric(id: id('ketones'), day: day, time: time, type: 'ketones', value: v);
    if (m.contains('sleep')) return ImportedBiometric(id: id('sleep'), day: day, time: time, type: 'sleep', value: v);
    return ImportedBiometric(id: id('custom:$metric'), day: day, time: time, type: 'custom:$metric', value: v, unit: unit);
  }

  /// MyFitnessPal: één kolom per meting (Weight, Body Fat %, ...), zonder eenheid bij het gewicht.
  void _measurements(List<List<String>> rows, ImportBatch batch) {
    final header = rows.first, idx = _index(header);
    final day = _col(idx, ['date', 'day']);
    final weight = _col(idx, ['weight']);
    final fat = _col(idx, ['body fat %', 'body fat', 'body fat percentage']);
    if (day == null) return;
    final weights = weight == null ? <double>[] : [for (final r in rows.skip(1)) ?_num(_at(r, weight))];
    final unitFromHeader = weight == null ? null : header[weight].toLowerCase();
    var lb = unitFromHeader != null && unitFromHeader.contains('lb');
    if (weight != null && !lb && !(unitFromHeader?.contains('kg') ?? false)) {
      if (weightUnit != null) {
        lb = weightUnit == WeightUnit.lb;
      } else {
        batch.weightUnitUnknown = true;
        final sorted = [...weights]..sort();
        lb = sorted.isNotEmpty && sorted[sorted.length ~/ 2] > 130;
      }
      batch.weightUnitUsed = lb ? WeightUnit.lb : WeightUnit.kg;
    }
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      if (d == null) continue;
      if (weight != null) {
        final w = _num(_at(r, weight));
        if (w != null && w > 0) {
          batch.biometrics.add(ImportedBiometric(id: _id(['bio', d, 'weight', '$w']), day: d, type: 'weight', value: lb ? w * 0.45359237 : w));
        }
      }
      if (fat != null) {
        final f = _num(_at(r, fat));
        if (f != null && f > 0) batch.biometrics.add(ImportedBiometric(id: _id(['bio', d, 'body_fat', '$f']), day: d, type: 'body_fat', value: f));
      }
    }
    final other = [
      for (final (i, h) in header.indexed)
        if (i != day && i != weight && i != fat && h.trim().isNotEmpty) h.trim(),
    ];
    if (other.isNotEmpty) {
      batch.warnings.add(
        tr(
          'Measurements without a unit (${other.join(', ')}) are not imported.',
          'Metingen zonder eenheid (${other.join(', ')}) worden niet overgenomen.',
        ),
      );
    }
  }

  void _notes(List<List<String>> rows, ImportBatch batch) {
    final idx = _index(rows.first);
    final day = _col(idx, ['day', 'date']);
    final note = _col(idx, ['note', 'notes', 'text']);
    if (day == null || note == null) return;
    for (final r in rows.skip(1)) {
      final d = _date(_at(r, day));
      if (d != null) _addNote(batch, d, _at(r, note));
    }
  }

  static void _addNote(ImportBatch batch, String day, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    final old = batch.notes[day];
    if (old == null) {
      batch.notes[day] = t;
    } else if (!old.contains(t)) {
      batch.notes[day] = '$old\n$t';
    }
  }

  // ── Hulpjes ──

  /// Vaste id: zelfde gegevens geven dezelfde id; identieke regels op dezelfde dag krijgen een volgnummer.
  String _id(List<String> parts) {
    final key = [source.code, ...parts].join('|');
    final n = _seen[key] = (_seen[key] ?? 0) + 1;
    return 'import-${source.code}-${_uuid.v5(Namespace.url.value, '$key|$n')}';
  }

  static String _at(List<String> row, int i) => i < row.length ? row[i] : '';

  static double? _num(String s) {
    var t = s.trim().replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (t.isEmpty || t == '-') return null;
    // "1.234,5" en "1,234.5": het laatste scheidingsteken is de decimaal
    final lastComma = t.lastIndexOf(','), lastDot = t.lastIndexOf('.');
    if (lastComma > lastDot) {
      t = t.replaceAll('.', '').replaceAll(',', '.');
    } else {
      t = t.replaceAll(',', '');
    }
    return double.tryParse(t);
  }

  /// "150.00 g", "1 kg", "4 oz" naar gram; andere eenheden (kop, stuk, ml) geven null.
  static double? _grams(String amount) {
    final m = RegExp(r'^\s*([0-9]+(?:[.,][0-9]+)?)\s*([a-zA-Zµ]+)\b').firstMatch(amount);
    if (m == null) return null;
    final v = _num(m.group(1)!);
    if (v == null || v <= 0) return null;
    return switch (m.group(2)!.toLowerCase()) {
      'g' || 'gr' || 'gram' || 'grams' || 'gramm' => v,
      'kg' => v * 1000,
      'mg' => v / 1000,
      'oz' || 'ounce' || 'ounces' => v * 28.349523,
      'lb' || 'lbs' || 'pound' || 'pounds' => v * 453.59237,
      _ => null,
    };
  }

  static int _meal(String s) {
    final t = s.toLowerCase();
    if (t.contains('breakfast') || t.contains('ontbijt')) return 0;
    if (t.contains('lunch')) return 1;
    if (t.contains('dinner') || t.contains('supper') || t.contains('avond') || t.contains('diner')) return 2;
    return 3;
  }

  /// "2024-01-31", "31/01/2024", "01/31/2024" (Amerikaans als het eerste getal ≤ 12 en het tweede > 12, of bij
  /// MyFitnessPal), "31-01-2024" naar "jjjj-mm-dd".
  String? _date(String s) {
    final t = s.trim();
    var m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (m != null) return _ymd(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    m = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})').firstMatch(t);
    if (m == null) return null;
    var a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
    if (y < 100) y += 2000;
    final us = b > 12 || (a <= 12 && source == ImportSource.myfitnesspal && t.contains('/'));
    return us ? _ymd(y, a, b) : _ymd(y, b, a);
  }

  static String? _ymd(int y, int mo, int d) {
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || y < 1990 || y > 2100) return null;
    return '${y.toString().padLeft(4, '0')}-${mo.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  }

  /// "8:15 AM", "20:15", "20:15:00" naar "uu:mm".
  static String? _time(String s) {
    final m = RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?').firstMatch(s.trim());
    if (m == null) return null;
    var h = int.parse(m[1]!);
    final min = int.parse(m[2]!);
    final ampm = m[3]?.toLowerCase();
    if (ampm == 'pm' && h < 12) h += 12;
    if (ampm == 'am' && h == 12) h = 0;
    if (h > 23 || min > 59) return null;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }
}

enum _Kind { items, mealTotals, dayTotals, biometrics, measurements, exercise, notes, unknown }
