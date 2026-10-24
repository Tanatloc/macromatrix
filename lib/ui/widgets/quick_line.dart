/// Eén regel van Snel loggen (en van een geïmporteerd recept): wat er gezegd of gelezen werd, de treffers en de
/// hoeveelheid die je met + en − aanpast.
library;

import '../../data/food.dart';
import '../../i18n.dart';
import '../../nutrition/portions.dart' show stepQuantity;
import '../../nutrition/quick_parse.dart';
import 'kit.dart' show fmtDec, fmtInt;

class QuickLine {
  QuickLine(this.item, this.options) {
    _reset();
  }
  final QuickItem item;
  final List<(Food, double, Portion?)> options;
  int choice = 0;

  /// De hoeveelheid die je met + en − aanpast: gram als het om een gewicht gaat, anders het aantal
  /// (stuks, sneetjes, porties).
  double n = 0;

  bool get found => options.isNotEmpty;
  (Food, double, Portion?) get pick => options[choice];
  Food get food => pick.$1;
  Portion? get portion => pick.$3;

  /// Een gewicht als je er een noemde, of als er geen aantal of portie is ("ham" = 100 g).
  bool get byWeight => item.grams != null || (item.count == null && portion == null);

  /// Gewicht van één stuk of portie van de gekozen treffer.
  double get _per => pick.$2 / (item.count ?? 1);
  double get grams => byWeight ? n : n * _per;
  double get kcal => (food.per100g['energy'] ?? 0) * grams / 100;
  double get protein => (food.per100g['protein'] ?? 0) * grams / 100;

  /// Zoals op het productscherm: boven 2 kg of 3.000 kcal eerst vragen (N65).
  bool get unusual => grams > 2000 || kcal > 3000;

  void _reset() => n = !found ? 0 : (byWeight ? pick.$2 : (item.count ?? 1));

  /// Een andere treffer: het aantal blijft, een geschat gewicht past zich aan het nieuwe product aan.
  void select(int i) {
    final was = byWeight;
    choice = i;
    if (byWeight != was || (byWeight && item.grams == null)) _reset();
  }

  void step({required bool up}) {
    final next = stepQuantity(n, up: up, portion: !byWeight);
    if (next > 0) n = next;
  }

  String get amountLabel {
    final g = bigNum(grams);
    if (byWeight) return '$g g';
    // "1 stuk (≈35 g)" draagt zijn grammen al: niet nog eens "(35 g)" erachter; bij meer dan één het totaal
    if (portion != null) {
      final label = portionInLang(portion!.label);
      final hasGrams = RegExp(r'\d\s*(g|ml)\)').hasMatch(label);
      if (n == 1) return hasGrams ? label : '$label ($g g)';
      return hasGrams ? '${countLabel(n)} × $label = $g g' : '${countLabel(n)} × $label ($g g)';
    }
    return n == 1 ? '≈$g g' : '${countLabel(n)} × ≈${fmtInt(_per)} g = $g g';
  }
}

String countLabel(double n) => n == n.roundToDouble() ? '${n.round()}' : fmtDec(n);

/// Een getal dat nergens meer in past ("1000 bananas"), ingekort.
String bigNum(double v) => v > 99999 ? '> ${fmtInt(99999)}' : fmtInt(v);
