/// Gegevens van de gebruiker naast het dagboek: lichaamsmetingen, beweging, vasten, maaltijden,
/// recepten en terugkerende items.
library;

import 'dart:math' as math;

import '../i18n.dart';
import '../nutrition/values.dart';
import 'food.dart';

// ── Lichaamsmetingen ──

/// Soort meting. Eigen metingen hebben een sleutel `custom:<naam>`.
class BiometricType {
  const BiometricType(this.key, this.labelNl, this._unit, {this.decimals = 1, this.secondLabelNl, this.chartable = true});

  final String key;
  final String labelNl;
  final String _unit;
  final int decimals;

  /// Tweede waarde, bv. de onderdruk bij bloeddruk.
  final String? secondLabelNl;

  String get label => isNl ? labelNl : (_bioEnglish[key] ?? labelNl);
  String get unit => _unit == 'uur' ? tr('h', 'uur') : (_unit == 'steps' ? tr('steps', 'stappen') : _unit);
  String? get secondLabel => secondLabelNl == null ? null : tr('diastolic', secondLabelNl!);
  final bool chartable;

  bool get isCustom => key.startsWith('custom:');

  static const weight = BiometricType('weight', 'Gewicht', 'kg');
  static const builtIn = [
    weight,
    BiometricType('body_fat', 'Vetpercentage', '%'),
    BiometricType('lean_mass', 'Spiermassa', 'kg'),
    BiometricType('body_water', 'Lichaamsvocht', 'kg'),
    BiometricType('waist', 'Buikomtrek', 'cm'),
    BiometricType('blood_pressure', 'Bloeddruk', 'mmHg', decimals: 0, secondLabelNl: 'onderdruk'),
    BiometricType('heart_rate', 'Hartslag in rust', 'bpm', decimals: 0),
    BiometricType('glucose', 'Bloedsuiker', 'mmol/L'),
    BiometricType('ketones', 'Ketonen', 'mmol/L'),
    BiometricType('sleep', 'Slaap', 'uur'),
    BiometricType('steps', 'Stappen', 'steps', decimals: 0),
  ];

  static BiometricType custom(String name, String unit) => BiometricType('custom:$name', name, unit);
}

class Biometric {
  const Biometric({required this.id, required this.day, required this.type, required this.value, this.value2, this.time});
  final String id;
  final String day;
  final String? time;
  final String type;
  final double value;
  final double? value2;
}

// ── Beweging ──

/// Activiteit met een MET-waarde (Compendium of Physical Activities): kcal = MET x kg x uren.
class ExerciseType {
  const ExerciseType(this.nameNl, this.met);
  final String nameNl;
  final double met;
  String get name => isNl ? nameNl : (_exerciseEnglish[nameNl] ?? nameNl);
}

/// Naam van een bewaarde activiteit in de huidige taal. De naam staat als tekst in het dagboek, in de taal van het
/// moment ("Cycling (brisk, 19-22 km/h)"); een activiteit uit de lijst tonen we in de taal die nu gekozen is. Een
/// eigen naam ("Spinning") blijft zoals hij is.
String exerciseNameInLang(String name) {
  if (isNl) {
    for (final e in _exerciseEnglish.entries) {
      if (e.value == name) return e.key;
    }
    return name;
  }
  return _exerciseEnglish[name] ?? name;
}

const _bioEnglish = {
  'weight': 'Weight',
  'body_fat': 'Body fat',
  'lean_mass': 'Lean mass',
  'body_water': 'Body water',
  'waist': 'Waist',
  'blood_pressure': 'Blood pressure',
  'heart_rate': 'Resting heart rate',
  'glucose': 'Blood glucose',
  'ketones': 'Ketones',
  'sleep': 'Sleep',
  'steps': 'Steps',
};

const exerciseTypes = [
  ExerciseType('Wandelen (rustig, 4 km/u)', 3.0),
  ExerciseType('Wandelen (stevig, 6 km/u)', 4.3),
  ExerciseType('Hardlopen (8 km/u)', 8.3),
  ExerciseType('Hardlopen (10 km/u)', 9.8),
  ExerciseType('Hardlopen (12 km/u)', 11.8),
  ExerciseType('Fietsen (rustig, 16-19 km/u)', 6.8),
  ExerciseType('Fietsen (stevig, 19-22 km/u)', 8.0),
  ExerciseType('Zwemmen (rustig)', 5.8),
  ExerciseType('Zwemmen (stevig)', 9.8),
  ExerciseType('Krachttraining (gemiddeld)', 3.5),
  // Een krachtsessie bestaat voor een groot deel uit rust tussen de sets: 5 MET in plaats van 6 (75 min bij 84 kg ≈ 525 kcal, niet 630)
  ExerciseType('Krachttraining (intensief)', 5.0),
  ExerciseType('Roeien (ergometer)', 7.0),
  ExerciseType('Crosstrainer', 5.0),
  ExerciseType('Wandeltocht / hiken', 6.0),
  ExerciseType('Voetbal', 7.0),
  ExerciseType('Tennis / padel', 7.3),
  ExerciseType('Yoga', 2.5),
  ExerciseType('Dansen', 5.0),
  ExerciseType('Tuinieren', 3.8),
  ExerciseType('Huishoudelijk werk', 3.3),
];

class Exercise {
  const Exercise({required this.id, required this.day, required this.name, required this.kcal, this.minutes});
  final String id;
  final String day;
  final String name;
  final double? minutes;
  final double kcal;
}

// ── Vasten ──

class Fast {
  const Fast({required this.id, required this.start, required this.goalHours, this.end});
  final String id;
  final DateTime start;
  final DateTime? end;
  final double goalHours;

  bool get running => end == null;
  Duration elapsed([DateTime? now]) => (end ?? now ?? DateTime.now()).difference(start);
}

// ── Opgeslagen maaltijden en terugkerende items ──

/// Eén item zoals het in het dagboek komt (zonder dag en maaltijd).
class ItemTemplate {
  const ItemTemplate({
    required this.foodRef,
    required this.name,
    required this.grams,
    required this.quantity,
    required this.per100g,
    this.brand,
    this.portionLabel,
  });

  final String foodRef;
  final String name;
  final String? brand;
  final double grams;
  final double quantity;
  final String? portionLabel;
  final NutrientMap per100g;

  double get kcal => (per100g['energy'] ?? 0) * grams / 100;

  Food toFood() => Food(ref: foodRef, name: name, brand: brand, source: FoodSource.custom, per100g: per100g);

  Map<String, Object?> toJson() => {
    'foodRef': foodRef,
    'name': name,
    'brand': brand,
    'grams': grams,
    'quantity': quantity,
    'portionLabel': portionLabel,
    'per100g': per100g,
  };

  factory ItemTemplate.fromJson(Map<String, Object?> j) => ItemTemplate(
    foodRef: j['foodRef'] as String,
    name: j['name'] as String,
    brand: j['brand'] as String?,
    grams: (j['grams'] as num).toDouble(),
    quantity: (j['quantity'] as num).toDouble(),
    portionLabel: j['portionLabel'] as String?,
    per100g: (j['per100g'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
  );
}

class SavedMeal {
  const SavedMeal({required this.id, required this.name, required this.items, this.mealIndex});
  final String id;
  final String name;
  final List<ItemTemplate> items;

  /// Maaltijd waarbij hij opgeslagen werd (index in Meal), of null bij oudere maaltijden.
  final int? mealIndex;

  double get kcal => items.fold(0, (a, i) => a + i.kcal);
}

/// Item dat automatisch in het dagboek komt op bepaalde weekdagen (bv. een dagelijkse vitaminepil).
class RepeatItem {
  const RepeatItem({required this.id, required this.mealIndex, required this.item, required this.weekdays, required this.startDay});
  final String id;
  final int mealIndex;
  final ItemTemplate item;

  /// Bitmasker: bit 0 = maandag ... bit 6 = zondag.
  final int weekdays;
  final String startDay;

  bool appliesTo(DateTime d) => weekdays & (1 << (d.weekday - 1)) != 0;
}

// ── Recepten ──

class Recipe {
  const Recipe({required this.ref, required this.name, required this.servings, required this.ingredients, this.cookedGrams});

  /// `recipe:<uuid>`
  final String ref;
  final String name;
  final double servings;
  final List<ItemTemplate> ingredients;

  /// Gewicht na bereiding (vocht verdampt of komt erbij); null = som van de ingrediënten.
  final double? cookedGrams;

  double get rawGrams => ingredients.fold(0, (a, i) => a + i.grams);
  double get totalGrams => cookedGrams ?? rawGrams;

  /// Voedingswaarden van het hele recept, en per 100 g van het eindresultaat.
  ///
  /// Met een gewicht na bereiding is het verschil met het rauwe gewicht water: kookwater dat linzen of pasta opnemen
  /// komt erbij, wat een saus inkookt gaat eraf (N76: een portie dal had maar 5 g water).
  NutrientMap get totals {
    final t = <String, double>{};
    for (final i in ingredients) {
      for (final e in scale(i.per100g, i.grams).entries) {
        t[e.key] = (t[e.key] ?? 0) + e.value;
      }
    }
    if (cookedGrams case final cooked? when ingredients.isNotEmpty) {
      final delta = cooked - rawGrams;
      if (delta > 0) {
        t['water'] = (t['water'] ?? 0) + delta;
      } else if (t['water'] case final w?) {
        // Er kan niet meer water verdampen dan er was
        t['water'] = math.max(0, w + delta);
      }
    }
    return t;
  }

  /// Hetzelfde product nog eens toevoegen telt bij de regel die er al staat, zoals in het dagboek (N75). Met dezelfde
  /// portie komen de porties erbij; met een andere portie of in gram wordt het één regel in gram. Geeft de plaats van
  /// de samengevoegde regel terug, of null als [add] een nieuwe regel werd.
  static int? addIngredient(List<ItemTemplate> items, ItemTemplate add) {
    final i = items.indexWhere((x) => x.foodRef == add.foodRef && _sameValues(x.per100g, add.per100g));
    if (i < 0) {
      items.add(add);
      return null;
    }
    final old = items[i];
    final samePortion = old.portionLabel == add.portionLabel;
    final grams = old.grams + add.grams;
    items[i] = ItemTemplate(
      foodRef: old.foodRef,
      name: old.name,
      brand: old.brand,
      grams: grams,
      quantity: samePortion ? old.quantity + add.quantity : grams,
      portionLabel: samePortion ? old.portionLabel : null,
      per100g: old.per100g,
    );
    return i;
  }

  static bool _sameValues(NutrientMap a, NutrientMap b) => a.length == b.length && a.entries.every((e) => b[e.key] == e.value);

  /// Als voedingsmiddel, zodat een recept overal gebruikt kan worden zoals een product.
  Food toFood() {
    final total = totalGrams;
    final per100g = total <= 0 ? <String, double>{} : {for (final e in totals.entries) e.key: e.value / total * 100};
    return Food(
      ref: ref,
      name: name,
      source: FoodSource.recipe,
      per100g: per100g,
      portions: [
        if (servings > 0 && total > 0)
          Portion(tr('1 serving (1/${_fmt(servings)} of the recipe)', '1 portie (1/${_fmt(servings)} van het recept)'), total / servings),
      ],
    );
  }

  Map<String, Object?> toJson() => {
    'servings': servings,
    'cookedGrams': cookedGrams,
    'ingredients': [for (final i in ingredients) i.toJson()],
  };

  static Recipe fromJson(String ref, String name, Map<String, Object?> j) => Recipe(
    ref: ref,
    name: name,
    servings: (j['servings'] as num).toDouble(),
    cookedGrams: (j['cookedGrams'] as num?)?.toDouble(),
    ingredients: [for (final i in j['ingredients'] as List) ItemTemplate.fromJson((i as Map).cast<String, Object?>())],
  );
}

String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.dec;

const _exerciseEnglish = {
  'Wandelen (rustig, 4 km/u)': 'Walking (easy, 4 km/h)',
  'Wandelen (stevig, 6 km/u)': 'Walking (brisk, 6 km/h)',
  'Hardlopen (8 km/u)': 'Running (8 km/h)',
  'Hardlopen (10 km/u)': 'Running (10 km/h)',
  'Hardlopen (12 km/u)': 'Running (12 km/h)',
  'Fietsen (rustig, 16-19 km/u)': 'Cycling (easy, 16-19 km/h)',
  'Fietsen (stevig, 19-22 km/u)': 'Cycling (brisk, 19-22 km/h)',
  'Zwemmen (rustig)': 'Swimming (easy)',
  'Zwemmen (stevig)': 'Swimming (vigorous)',
  'Krachttraining (gemiddeld)': 'Strength training (moderate)',
  'Krachttraining (intensief)': 'Strength training (intense)',
  'Roeien (ergometer)': 'Rowing (ergometer)',
  'Crosstrainer': 'Elliptical trainer',
  'Wandeltocht / hiken': 'Hiking',
  'Voetbal': 'Football',
  'Tennis / padel': 'Tennis / padel',
  'Yoga': 'Yoga',
  'Dansen': 'Dancing',
  'Tuinieren': 'Gardening',
  'Huishoudelijk werk': 'Housework',
};
