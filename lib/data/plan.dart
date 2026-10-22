import 'models.dart';
import 'user_db.dart';

/// Een product in de planner: wat je bij welke maaltijd wil eten.
class PlannedItem {
  const PlannedItem(this.meal, this.item);
  final Meal meal;
  final ItemTemplate item;

  Map<String, Object?> toJson() => {'meal': meal.index, ...item.toJson()};

  factory PlannedItem.fromJson(Map<String, Object?> j) =>
      PlannedItem(Meal.values[((j['meal'] as num?)?.toInt() ?? 0).clamp(0, Meal.values.length - 1)], ItemTemplate.fromJson(j));
}

/// Een regel op de boodschappenlijst.
class ShoppingItem {
  const ShoppingItem({required this.name, this.grams, this.reason, this.done = false});
  final String name;

  /// Hoeveelheid uit de planner, of null bij iets wat je zelf toevoegde.
  final double? grams;

  /// Waarom het op de lijst staat, bv. "magnesium".
  final String? reason;
  final bool done;

  ShoppingItem toggled() => ShoppingItem(name: name, grams: grams, reason: reason, done: !done);

  Map<String, Object?> toJson() => {'name': name, 'grams': grams, 'reason': reason, 'done': done};

  factory ShoppingItem.fromJson(Map<String, Object?> j) => ShoppingItem(
    name: j['name'] as String? ?? '',
    grams: (j['grams'] as num?)?.toDouble(),
    reason: j['reason'] as String?,
    done: j['done'] == true,
  );
}
