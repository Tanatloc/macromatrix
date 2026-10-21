/// Een labo-verslag lezen: uit regels met kolommen (zie pdf_text.dart) de datum van de afname en elke uitslag
/// met naam, waarde, eenheid, referentiewaarden en of het labo ze als te laag of te hoog aanduidt.
///
/// Persoonsgegevens (naam, rijksregisternummer, adres) worden niet gelezen of bewaard.
library;

import 'markers.dart';

class LabValue {
  const LabValue({required this.name, required this.value, this.marker, this.unit, this.comparator, this.low, this.high, this.flag = 0});

  /// Zoals op het verslag.
  final String name;
  final LabMarker? marker;
  final double value;
  final String? unit;

  /// "<" of ">" bij een uitslag als "< 5".
  final String? comparator;

  /// Referentiewaarden van het labo, in de eenheid van het verslag.
  final double? low, high;

  /// -1 te laag, 0 normaal, 1 te hoog (volgens het labo, of afgeleid uit de referentiewaarden).
  final int flag;

  /// Waarde in de eenheid van de app, of null bij een onbekende stof of eenheid.
  double? get standard => marker == null ? null : toMarkerUnit(marker!, value, unit);

  /// -1 te laag, 0 goed, 1 te hoog: volgens het labo, en anders volgens de grenzen van de app.
  int get status {
    if (flag != 0 || low != null || high != null) return flag;
    final v = standard, m = marker;
    if (v == null || m == null) return 0;
    if (m.low != null && v < m.low!) return -1;
    if (m.high != null && v > m.high!) return 1;
    return 0;
  }

  LabValue copyWith({double? value, String? unit}) => LabValue(
    name: name,
    value: value ?? this.value,
    marker: marker,
    unit: unit ?? this.unit,
    comparator: comparator,
    low: low,
    high: high,
    flag: flag,
  );
}

/// Een bewaarde uitslag: met de dag van de afname.
class LabResult {
  const LabResult({required this.id, required this.day, required this.value});
  final String id;

  /// jjjj-mm-dd.
  final String day;
  final LabValue value;
}

class LabReport {
  const LabReport(this.date, this.values);

  /// Datum van de afname, of null als die niet gevonden werd.
  final DateTime? date;
  final List<LabValue> values;

  /// Uitslagen die de app kent en kan gebruiken.
  List<LabValue> get known => [
    for (final v in values)
      if (v.marker != null) v,
  ];
}

final _number = RegExp(r'^(\d+(?:[.,]\d+)?)$');
final _value = RegExp(r'^([<>]=?)?\s*([+-]\s+)?(\d+(?:[.,]\d+)?)\s*([HLhl*]|↑|↓)?$');
final _range = RegExp(r'^(\d+(?:[.,]\d+)?)\s*[-–]\s*(\d+(?:[.,]\d+)?)$');
final _below = RegExp(r'^<\s*=?\s*(\d+(?:[.,]\d+)?)$');
final _above = RegExp(r'^>\s*=?\s*(\d+(?:[.,]\d+)?)$');
final _aboveRange = RegExp(r'^>\s*(\d+(?:[.,]\d+)?)\s*[-–]\s*(\d+(?:[.,]\d+)?)$');
const _flags = {'+': 1, '++': 1, 'h': 1, 'H': 1, '↑': 1, '*': 0, '-': -1, '--': -1, 'l': -1, 'L': -1, '↓': -1};
final _date = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{4})');
final _dateLabel = RegExp(
  r'datum labo|datum afname|afnamedatum|afname|staalname|prelevement|prélèvement|sample|collected|date du|date de',
  caseSensitive: false,
);
final _birth = RegExp(r'geboorte|naissance|birth|geb\.|né', caseSensitive: false);
const _headers = {'analyse', 'analyses', 'test', 'onderzoek', 'parametre', 'resultat', 'resultaat', 'result'};

double _n(String s) => double.parse(s.replaceAll(',', '.'));

/// Referentiewaarden: "13,2 - 17,3", "< 190", "> 40".
(double?, double?)? _ref(String s) {
  final t = s.trim();
  if (_range.firstMatch(t) case final m?) return (_n(m.group(1)!), _n(m.group(2)!));
  if (_aboveRange.firstMatch(t) case final m?) return (_n(m.group(1)!), _n(m.group(2)!));
  if (_below.firstMatch(t) case final m?) return (null, _n(m.group(1)!));
  if (_above.firstMatch(t) case final m?) return (_n(m.group(1)!), null);
  return null;
}

/// Een verslag lezen uit regels met kolommen.
LabReport parseLabReport(List<List<String>> lines) {
  DateTime? date, firstDate;
  final values = <LabValue>[];
  for (final line in lines) {
    final joined = line.join(' ');
    if (date == null && !_birth.hasMatch(joined)) {
      final m = _date.firstMatch(joined);
      if (m != null) {
        final d = DateTime.tryParse('${m.group(3)}-${m.group(2)!.padLeft(2, '0')}-${m.group(1)!.padLeft(2, '0')}');
        if (d != null && d.year > 1950) {
          if (_dateLabel.hasMatch(joined)) date = d;
          firstDate ??= d;
        }
      }
    }
    final v = _row(line);
    if (v != null) values.add(v);
  }
  // Dezelfde uitslag twee keer (bv. herhaald op een volgende pagina): de eerste houden
  final seen = <String>{};
  return LabReport(date ?? firstDate, [
    for (final v in values)
      if (seen.add('${normalizeLabName(v.name)}|${v.unit}')) v,
  ]);
}

LabValue? _row(List<String> cells) {
  if (cells.length < 2) return null;
  final name = cells.first.replaceAll(RegExp(r'[°*]+$'), '').trim();
  if (!RegExp('[A-Za-z]').hasMatch(name) || _headers.contains(normalizeLabName(name))) return null;
  var i = 1, flag = 0;
  if (_flags.containsKey(cells[i].trim())) {
    flag = _flags[cells[i].trim()]!;
    i++;
  }
  if (i >= cells.length) return null;
  final m = _value.firstMatch(cells[i].trim());
  if (m == null) return null;
  if (m.group(2) != null) flag = m.group(2)!.trim() == '+' ? 1 : -1;
  if (m.group(4) != null) flag = _flags[m.group(4)!] ?? flag;
  final value = _n(m.group(3)!);
  String? unit;
  (double?, double?)? ref;
  for (final c in cells.skip(i + 1)) {
    var cell = c.trim();
    // Eenheid en referentie in één kolom: "mL/min/1,73 m2 > ."
    final split = RegExp(r'^(.*?)\s+([<>].*)$').firstMatch(cell);
    if (unit == null && split != null && RegExp('[A-Za-z%]').hasMatch(split.group(1)!)) {
      unit = split.group(1);
      cell = split.group(2)!;
    }
    final r = _ref(cell);
    if (r != null) {
      ref ??= r;
    } else if (unit == null && !_number.hasMatch(cell) && RegExp(r'[A-Za-zµ%/]').hasMatch(cell) && cell.length <= 20) {
      unit = cell;
    }
  }
  final marker = labMarkerFor(name);
  // Onbekende regels zonder eenheid of referentie zijn meestal controles of opmerkingen
  if (marker == null && unit == null && ref == null) return null;
  final (low, high) = ref ?? (null, null);
  if (flag == 0) {
    if (low != null && value < low) flag = -1;
    if (high != null && value > high) flag = 1;
  }
  return LabValue(name: name, value: value, marker: marker, unit: unit, comparator: m.group(1), low: low, high: high, flag: flag);
}

/// Regels uit platte tekst (bv. tekstherkenning): kolommen zijn gescheiden door minstens twee spaties of een tab.
List<List<String>> linesFromText(String text) => [
  for (final l in text.split(RegExp(r'\r?\n')))
    if (l.trim().isNotEmpty) l.trim().split(RegExp(r'\s{2,}|\t')).map((c) => c.trim()).where((c) => c.isNotEmpty).toList(),
];
