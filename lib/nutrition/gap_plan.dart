/// "Wat moet ik nog eten?": 2 à 3 concrete producten die samen de grootste tekorten van vandaag zo goed mogelijk
/// aanvullen, binnen de energie die je nog over hebt.
///
/// Werkwijze (gulzig): kies telkens het product en de hoeveelheid die het meest van de resterende tekorten vult
/// (per stof hoogstens tot 100% van het doel), met een kleine straf voor veel kcal en zonder een bovengrens te
/// overschrijden. Daarna worden de totalen bijgewerkt en zoekt het volgende product verder.
library;

import 'dart:math' as math;

import '../data/food.dart';
import 'insights.dart';
import 'nutrients.dart';
import 'targets.dart';
import 'values.dart';

class PlanItem {
  const PlanItem({required this.food, required this.grams, this.portion, required this.kcal, required this.fills});
  final Food food;
  final double grams;
  final Portion? portion;
  final double kcal;

  /// Voedingsstoffen die het vooral aanvult: (stof, deel van het doel vóór, na).
  final List<(Nutrient, double, double)> fills;
}

class GapPlan {
  const GapPlan(this.items, this.before, this.after);
  final List<PlanItem> items;

  /// Nutrient Score vóór en na het plan.
  final int before, after;
  double get kcal => items.fold(0, (a, i) => a + i.kcal);
}

final _measure = RegExp(r'\b(cup|cups|tbsp|tsp|oz|fl|ml|dl|l|quart|pint)\b', caseSensitive: false);
final _notAFood = RegExp(
  r'\b(oil|supplement|powder|extract|fortified|infant|babyfood|yeast extract|spice|spices|salt|seasoning|herbs?)\b',
  caseSensitive: false,
);

/// Gedroogde kruiden en specerijen: rijk per 100 g, maar niemand eet er 50 g van.
final _herb = RegExp(
  r'\b(basil|oregano|thyme|rosemary|sage|parsley|dill|cumin|paprika|turmeric|cinnamon|curry|coriander|marjoram|tarragon|chervil|bay|clove|nutmeg|ginger|pepper|mustard seed|fenugreek|savory|spearmint|peppermint|chili)\b',
  caseSensitive: false,
);

/// Geen alledaags eten: rauw vlees of rauwe vis, en droge, ongekookte basisproducten (zemelen, meel, kiemen).
final _rawAnimal = RegExp(
  r'\b(beef|pork|veal|lamb|chicken|turkey|duck|kidney|liver|heart|tongue|tripe|fish|cod|salmon|herring|mackerel|meat|offal|sweetbread)\b.*\braw\b|\braw\b.*\b(beef|pork|veal|lamb|chicken|turkey|kidney|liver|heart|meat)\b',
  caseSensitive: false,
);
final _unprepared = RegExp(
  r'\b(bran|flour|meal|germ|dehydrated|unenriched|dry, raw|dry form|uncooked|unprepared|concentrate)\b',
  caseSensitive: false,
);
final _organ = RegExp(r'\b(liver|kidney|heart|tongue|tripe|offal|sweetbread|giblets|gizzard)\b', caseSensitive: false);

bool _isHerb(Food f) =>
    (f.category ?? '').toLowerCase().contains('spice') ||
    (f.category ?? '').toLowerCase().contains('herb') ||
    (_herb.hasMatch(f.name) && RegExp(r'\b(dried|ground|powder)\b', caseSensitive: false).hasMatch(f.name));

/// Iets wat je gewoon op je bord legt: geen recept, olie, supplement, kruid, rauw vlees of droog basisproduct.
bool isEverydayFood(Food f) =>
    f.source != FoodSource.recipe && !_notAFood.hasMatch(f.name) && !_isHerb(f) && !_rawAnimal.hasMatch(f.name) && !_unprepared.hasMatch(f.name);

/// Hoeveelheden om te proberen: een herkenbare portie, en 100 g of 50 g.
List<(double, Portion?)> _amounts(Food f) {
  final portion = f.portions.where((p) => p.grams >= 30 && p.grams <= 250 && !_measure.hasMatch(p.label)).firstOrNull;
  return [if (portion != null) (portion.grams, portion), (100, null), (50, null)];
}

/// Plan voor de rest van de dag, of null als er geen noemenswaardige tekorten zijn.
/// [mine] zijn producten die je vaak eet; die krijgen een kleine voorkeur.
GapPlan? planGaps({
  required NutrientMap totals,
  required Map<String, Target> targets,
  required double kcalLeft,
  required List<Food> candidates,
  Set<String> mine = const {},
  int maxItems = 3,
}) {
  final now = Map<String, double>.of(totals);
  final keys = [
    for (final k in stripKeys)
      if (targets[k]?.goal != null) k,
  ];
  double remaining(String k) => math.max(0, 1 - (now[k] ?? 0) / targets[k]!.goal!);
  if (keys.every((k) => remaining(k) < 0.15)) return null;

  final before = completenessScore(totals, targets);
  var budget = math.max(kcalLeft, 250.0);
  final items = <PlanItem>[];
  final used = <String>{};
  final pool = [
    for (final f in candidates)
      if (isEverydayFood(f)) f,
  ];

  for (var round = 0; round < maxItems; round++) {
    (Food, double, Portion?, double, NutrientMap)? best;
    var bestScore = 0.0;
    for (final f in pool) {
      if (used.contains(f.ref)) continue;
      final v = withDerived(f.per100g);
      for (final (g, portion) in _amounts(f)) {
        final kcal = (v['energy'] ?? 0) * g / 100;
        if (kcal > budget || kcal > 500) continue;
        var filled = 0.0, over = false;
        for (final k in keys) {
          final add = (v[k] ?? 0) * g / 100;
          if (add <= 0) continue;
          final t = targets[k]!;
          // Niet boven een bovengrens, en geen extreme hoeveelheden (bv. lever: vitamine A ver boven je doel)
          if ((t.upper != null && (now[k] ?? 0) + add > t.upper!) || (now[k] ?? 0) + add > t.goal! * 5) {
            over = true;
            break;
          }
          filled += math.min(add / t.goal!, remaining(k));
        }
        if (over) continue;
        var score = filled / (1 + kcal / 400);
        if (mine.contains(f.ref)) score *= 1.5;
        if (_organ.hasMatch(f.name)) score *= 0.6;
        if (f.source.european) score *= 1.1;
        if (score > bestScore) {
          bestScore = score;
          best = (f, g, portion, kcal, v);
        }
      }
    }
    if (best == null || bestScore < 0.12) break;
    final (f, g, portion, kcal, v) = best;
    final fills = <(Nutrient, double, double)>[];
    for (final k in keys) {
      final add = (v[k] ?? 0) * g / 100;
      final t = targets[k]!.goal!;
      final b = (now[k] ?? 0) / t;
      if (add / t >= 0.1 && b < 1) fills.add((nutrientByKey[k]!, b, ((now[k] ?? 0) + add) / t));
    }
    fills.sort((a, b) => (b.$3 - b.$2).compareTo(a.$3 - a.$2));
    for (final e in v.entries) {
      now[e.key] = (now[e.key] ?? 0) + e.value * g / 100;
    }
    items.add(PlanItem(food: f, grams: g, portion: portion, kcal: kcal, fills: fills.take(3).toList()));
    used.add(f.ref);
    budget -= kcal;
  }
  if (items.isEmpty) return null;
  return GapPlan(items, before, completenessScore(now, targets));
}
