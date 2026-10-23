import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
import '../../data/models.dart';
import '../../data/user_db.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../widgets/nutrient_row.dart';
import 'add_food_screen.dart';
import 'food_detail_screen.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';

/// Recept maken of bewerken: ingrediënten met hun hoeveelheid, aantal porties en (optioneel) het gewicht na
/// bereiding. Het recept wordt een voedingsmiddel dat je zoals elk product kunt toevoegen.
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, this.existing});
  final Recipe? existing;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _servings = TextEditingController(text: _fmt(widget.existing?.servings ?? 1));
  late final _cooked = TextEditingController(text: widget.existing?.cookedGrams == null ? '' : _fmt(widget.existing!.cookedGrams!));
  late final List<ItemTemplate> _items = [...?widget.existing?.ingredients];

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.dec;
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void dispose() {
    _name.dispose();
    _servings.dispose();
    _cooked.dispose();
    super.dispose();
  }

  Recipe get _recipe => Recipe(
    ref: widget.existing?.ref ?? 'recipe:nieuw',
    name: _name.text.trim(),
    servings: (_parse(_servings.text) ?? 1).clamp(1, 1000).toDouble(),
    cookedGrams: _parse(_cooked.text),
    ingredients: _items,
  );

  Future<void> _addIngredient() async {
    final t = await Navigator.of(context)
        .push<ItemTemplate>(MaterialPageRoute(builder: (_) => const AddFoodScreen(meal: Meal.lunch, pickOnly: true)));
    if (t != null) setState(() => _items.add(t));
  }

  /// Een ingrediënt aanpassen: het detailscherm met de huidige hoeveelheid, en de regel vervangen door wat terugkomt.
  Future<void> _editIngredient(int i) async {
    final s = context.read<AppState>();
    final item = _items[i];
    // Het volledige product (met porties); niet meer gevonden: terugvallen op wat in het recept staat
    final ref = item.foodRef;
    final food = (FoodDb.isDbRef(ref) ? s.foods.byRef(ref) : s.user.food(ref)) ?? item.toFood();
    // Met de portie van het recept: het detailscherm rekent de grammen om naar het aantal porties
    final portion = item.portionLabel == null ? null : food.portions.where((p) => p.label == item.portionLabel).firstOrNull;
    final t = await Navigator.of(context).push<ItemTemplate>(
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(food: food, meal: Meal.lunch, pickOnly: true, initialGrams: item.grams, initialPortion: portion),
      ),
    );
    if (t != null && mounted && i < _items.length) setState(() => _items[i] = t);
  }

  void _save() {
    if (_name.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Give the recipe a name and at least one ingredient.', 'Geef het recept een naam en minstens één ingrediënt.'))),
      );
      return;
    }
    final r = Recipe(
      ref: widget.existing?.ref ?? UserDb.newRecipeRef(),
      name: _recipe.name,
      servings: _recipe.servings,
      cookedGrams: _recipe.cookedGrams,
      ingredients: _items,
    );
    context.read<AppState>().saveRecipe(r);
    Navigator.of(context).pop(r.toFood());
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final recipe = _recipe;
    final perServing = withDerived({for (final e in recipe.totals.entries) e.key: e.value / recipe.servings});

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? tr('New recipe', 'Nieuw recept') : tr('Edit recipe', 'Recept bewerken'))),
      bottomNavigationBar: SafeArea(
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _save,
                child: Text(tr('Save recipe', 'Recept opslaan')),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: tr('Recipe name', 'Naam van het recept')),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _servings,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: decimalInput,
                      onTap: selectAllOnTap(_servings),
                      decoration: InputDecoration(labelText: tr('Number of servings', 'Aantal porties')),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _cooked,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: decimalInput,
                      onTap: selectAllOnTap(_cooked),
                      decoration: InputDecoration(
                        labelText: tr('Weight after cooking', 'Gewicht na bereiding'),
                        hintText: tr('Weigh the pot contents', 'Weeg de inhoud van de pot'),
                        // Als icoon blijft de eenheid altijd zichtbaar (suffixText verschijnt pas bij het typen)
                        suffixIcon: const Padding(padding: EdgeInsetsDirectional.only(end: 12), child: Text('g')),
                        suffixIconConstraints: const BoxConstraints(),
                        helperText: tr('Optional (raw: ${recipe.rawGrams.round()} g)', 'Optioneel (rauw: ${recipe.rawGrams.round()} g)'),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Veel mensen zien het veld over het hoofd: zeg wat het doet (water dat pasta opneemt of soep verliest)
              Text(
                tr(
                  'Pasta, rice and legumes absorb water while cooking; soups and sauces lose some. Weigh the finished dish and enter '
                      'the weight after cooking: then a portion you weigh on your plate has the right nutrients. Leave it empty to use the raw weight.',
                  'Pasta, rijst en peulvruchten nemen bij het koken water op; soep en saus verliezen er wat. Weeg het klare gerecht en vul '
                      'het gewicht na bereiding in: dan klopt een portie die je op je bord weegt. Laat het leeg om met het rauwe gewicht te rekenen.',
                ),
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(tr('Ingredients', 'Ingrediënten'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(onPressed: _addIngredient, icon: Icon(Icons.add), label: Text(tr('Add', 'Toevoegen'))),
                ],
              ),
              if (_items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    tr('Tap an ingredient to change its amount.', 'Tik op een ingrediënt om de hoeveelheid aan te passen.'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              Card(
                child: Column(
                  children: [
                    if (_items.isEmpty) ListTile(title: Text(tr('No ingredients yet.', 'Nog geen ingrediënten.'))),
                    for (final (i, item) in _items.indexed)
                      ListTile(
                        dense: true,
                        onTap: () => _editIngredient(i),
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          item.portionLabel == null
                              ? '${_fmt(item.grams)} g'
                              : '${_fmt(item.quantity)} × ${item.portionLabel} (${_fmt(item.grams)} g)',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${item.kcal.round()} kcal'),
                            IconButton(
                              tooltip: tr('Remove', 'Verwijderen'),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _items.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (_items.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  '${tr('Per serving', 'Per portie')} (${(recipe.totalGrams / recipe.servings).round()} g): ${(perServing['energy'] ?? 0).round()} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                NutrientPanel(values: perServing, targets: s.targets, onlyWithData: true, single: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
