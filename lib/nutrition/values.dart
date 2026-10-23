/// Rekenen met voedingswaarden: afgeleide totalen, schalen naar een hoeveelheid en optellen.
library;

import '../i18n.dart';
import 'nutrients.dart';

typedef NutrientMap = Map<String, double>;

double? _sum(NutrientMap n, List<String> keys, {double factor = 1}) {
  final present = keys.where(n.containsKey).toList();
  if (present.isEmpty) return null;
  return present.fold<double>(0, (a, k) => a + n[k]!) * factor;
}

/// Vult afgeleide waarden aan die een bron zelf niet gaf, zoals omega-3 uit ALA, EPA, DPA en DHA.
NutrientMap withDerived(NutrientMap source) {
  final n = Map.of(source);
  void derive(String key, List<String> parts, {double factor = 1}) {
    if (n.containsKey(key)) return;
    final v = _sum(n, parts, factor: factor);
    if (v != null) n[key] = v;
  }

  derive('omega3', ['ala', 'epa', 'dpa', 'dha']);
  derive('omega6', ['la', 'aa']);
  derive('epa_dha', ['epa', 'dha'], factor: 1000); // g -> mg
  derive('met_cys', ['methionine', 'cystine']);
  derive('phe_tyr', ['phenylalanine', 'tyrosine']);
  // Zout zoals op het etiket: natrium (mg) x 2,5 / 1000 = gram zout
  if (n['sodium'] case final na? when !n.containsKey('salt')) n['salt'] = na * 2.5 / 1000;
  return n;
}

/// Waarden per 100 g omzetten naar een hoeveelheid in gram.
NutrientMap scale(NutrientMap per100g, double grams) => {for (final e in per100g.entries) e.key: e.value * grams / 100};

/// Som van de voedingswaarden van een dag (of maaltijd), met per stof hoeveel items geen gegevens hadden.
class NutrientTotals {
  NutrientTotals(this.values, this.missing, this.missingEnergy, this.items);

  /// Opgetelde hoeveelheden.
  final NutrientMap values;

  /// Aantal items zonder waarde voor deze stof.
  final Map<String, int> missing;

  /// Energie (kcal) uit items zonder waarde voor deze stof.
  final Map<String, double> missingEnergy;

  /// Aantal items dat meetelt.
  final int items;

  double operator [](String key) => values[key] ?? 0;

  /// Onvolledig = meer dan 10% van de energie komt uit producten zonder gegevens voor deze stof.
  /// Het echte totaal ligt dan waarschijnlijk merkbaar hoger.
  bool isComplete(String key) {
    final total = values['energy'] ?? 0;
    final gap = missingEnergy[key] ?? 0;
    if (total <= 0) return (missing[key] ?? 0) == 0;
    return gap / total <= 0.1;
  }

  /// Stoffen waarvan het totaal onvolledig is (zie [isComplete]).
  Set<String> get incomplete => {
    for (final n in nutrients)
      if (!isComplete(n.key)) n.key,
  };

  static NutrientTotals sumOf(Iterable<NutrientMap> amounts) {
    final values = <String, double>{};
    final missing = <String, int>{};
    final missingEnergy = <String, double>{};
    var items = 0;
    for (final a in amounts) {
      items++;
      final kcal = a['energy'] ?? 0;
      for (final n in nutrients) {
        final v = a[n.key];
        if (v == null) {
          missing[n.key] = (missing[n.key] ?? 0) + 1;
          missingEnergy[n.key] = (missingEnergy[n.key] ?? 0) + kcal;
        } else {
          values[n.key] = (values[n.key] ?? 0) + v;
        }
      }
    }
    return NutrientTotals(values, missing, missingEnergy, items);
  }
}

/// Getal netjes tonen met de decimalen van de voedingsstof (nl-BE: komma als decimaalteken).
String formatAmount(double value, Nutrient n) {
  var d = n.displayDecimals;
  // Kleine hoeveelheden met wat meer precisie, zodat er geen "0" staat bij sporen
  if (value != 0 && value.abs() < 1 && d < 2) d = 2;
  return fmtNum(value, d);
}
