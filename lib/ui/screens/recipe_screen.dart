import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LengthLimitingTextInputFormatter;
import 'package:provider/provider.dart';

import '../../data/food_db.dart';
import '../../data/models.dart';
import '../../data/user_db.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../widgets/kit.dart';
import '../widgets/nutrient_row.dart';
import '../../data/food.dart';
import 'add_food_screen.dart';
import 'food_detail_screen.dart';
import 'recipe_import_screen.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/tap_guard.dart';
import '../widgets/undo.dart';

/// Recept maken of bewerken: ingrediënten met hun hoeveelheid, aantal porties en (optioneel) het gewicht na
/// bereiding. Het recept wordt een voedingsmiddel dat je zoals elk product kunt toevoegen.
class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key, this.existing, this.draft});
  final Recipe? existing;

  /// Een nieuw recept, al ingevuld (bv. geïmporteerd uit een link of foto). Wordt bij Opslaan een nieuw recept.
  final Recipe? draft;

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  /// Waar de velden mee beginnen: het bestaande recept, of het ingevulde ontwerp.
  Recipe? get _src => widget.existing ?? widget.draft;
  late final _name = TextEditingController(text: _src?.name ?? '');
  late final _servings = TextEditingController(text: _fmt(_src?.servings ?? 1));
  late final _cooked = TextEditingController(text: _src?.cookedGrams == null ? '' : _fmt(_src!.cookedGrams!));
  late final List<ItemTemplate> _items = [...?_src?.ingredients];
  final _removeGuard = RemoveGuard();

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v'.dec;
  static double? _parse(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

  /// Aantal porties: minstens 1 (0 of leeg werd vroeger stil 1 portie, N59).
  String? get _servingsError {
    final v = _parse(_servings.text);
    if (v == null || v < 1) return tr('At least 1 portion', 'Minstens 1 portie');
    if (v > 1000) return tr('At most 1000 portions', 'Hoogstens 1000 porties');
    return null;
  }

  /// Gewicht na bereiding: leeg mag (dan het rauwe gewicht), anders meer dan 0 en niet absurd hoog. Koken kan het
  /// gewicht ruim verdubbelen (pasta, peulvruchten), maar 100 kg pot voor 690 g ingrediënten kan niet (N59).
  String? get _cookedError {
    if (_cooked.text.trim().isEmpty) return null;
    final v = _parse(_cooked.text);
    if (v == null || v <= 0) return tr('Enter a weight above 0 g', 'Vul een gewicht boven 0 g in');
    final raw = _recipe.rawGrams;
    if (raw > 0 && v > raw * _maxCookedFactor) {
      final max = fmtInt(raw * _maxCookedFactor);
      return tr('At most $max g for these ingredients', 'Hoogstens $max g voor deze ingrediënten');
    }
    return null;
  }

  /// Gewicht na bereiding als veelvoud van het rauwe gewicht: daarbuiten weigeren, en buiten 0,3–3× eerst vragen.
  static const _maxCookedFactor = 20.0;

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
    cookedGrams: switch (_parse(_cooked.text)) {
      final c? when c > 0 => c,
      _ => null,
    },
    ingredients: _items,
  );

  Future<void> _addIngredient() async {
    final t = await Navigator.of(context)
        .push<ItemTemplate>(MaterialPageRoute(builder: (_) => const AddFoodScreen(meal: Meal.lunch, pickOnly: true)));
    if (t == null || !mounted) return;
    // Hetzelfde product nog eens: bij de regel die er al staat, met Ongedaan maken (N75)
    final before = [..._items];
    final into = Recipe.addIngredient(_items, t);
    setState(() {});
    if (into == null) return;
    final merged = _items[into];
    showUndo(context, tr('Added to ${merged.name}: now ${_fmt(merged.grams)} g', 'Bij ${merged.name} geteld: nu ${_fmt(merged.grams)} g'), () {
      if (mounted) setState(() => _items..clear()..addAll(before));
    });
  }

  /// Een ingrediënt aanpassen: het detailscherm met de huidige hoeveelheid, en de regel vervangen door wat terugkomt.
  Future<void> _editIngredient(int i) async {
    final s = context.read<AppState>();
    final item = _items[i];
    // Het volledige product (met porties); niet meer gevonden: terugvallen op wat in het recept staat
    final ref = item.foodRef;
    final food = (FoodDb.isDbRef(ref) ? s.foods.byRef(ref) : s.user.food(ref)) ?? item.toFood();
    // Met de portie van het recept: het detailscherm rekent de grammen om naar het aantal porties
    final portion = item.portionLabel == null ? null : food.portions.where((p) => samePortion(p.label, item.portionLabel)).firstOrNull;
    final t = await Navigator.of(context).push<ItemTemplate>(
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(food: food, meal: Meal.lunch, pickOnly: true, initialGrams: item.grams, initialPortion: portion),
      ),
    );
    if (t != null && mounted && i < _items.length) setState(() => _items[i] = t);
  }

  Future<void> _import() async {
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => const RecipeImportScreen()));
    if (food != null && mounted) Navigator.of(context).pop(food);
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Give the recipe a name and at least one ingredient.', 'Geef het recept een naam en minstens één ingrediënt.'))),
      );
      return;
    }
    final error = _servingsError ?? _cookedError;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    // Ongewoon gewicht na bereiding (minder dan 0,3× of meer dan 3× rauw): eerst vragen
    final cooked = _parse(_cooked.text);
    final raw = _recipe.rawGrams;
    if (cooked != null && raw > 0 && (cooked < raw * 0.3 || cooked > raw * 3)) {
      final portion = cooked / (_parse(_servings.text) ?? 1);
      final ok = await confirmUnusual(
        context,
        tr(
          'Weight after cooking ${fmtInt(cooked)} g for ${fmtInt(raw)} g of ingredients, so one portion is ${fmtInt(portion)} g. '
              'Is that right?',
          'Gewicht na bereiding ${fmtInt(cooked)} g voor ${fmtInt(raw)} g ingrediënten, dus één portie is ${fmtInt(portion)} g. '
              'Klopt dat?',
        ),
      );
      if (!ok || !mounted) return;
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
    final perServing = withDerived({for (final e in s.recipeTotalsWithSugars(recipe).entries) e.key: e.value / recipe.servings});

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? tr('New recipe', 'Nieuw recept') : tr('Edit recipe', 'Recept bewerken')),
        actions: [
          // Een nieuw, leeg recept: ook importeren uit een link of foto (Pro)
          if (widget.existing == null && widget.draft == null && _items.isEmpty)
            TextButton.icon(
              key: const ValueKey('recipe-import'),
              onPressed: _import,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(tr('Import', 'Importeren')),
            ),
        ],
      ),
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
                // Grens van de server (langer wordt niet gesynchroniseerd)
                inputFormatters: [LengthLimitingTextInputFormatter(UserDb.maxNameLength)],
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
                      decoration: InputDecoration(labelText: tr('Number of servings', 'Aantal porties'), errorText: _servingsError),
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
                        helperText: tr('Optional (raw: ${fmtInt(recipe.rawGrams)} g)', 'Optioneel (rauw: ${fmtInt(recipe.rawGrams)} g)'),
                        errorText: _cookedError,
                        errorMaxLines: 2,
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
                              ? '${fmtInt(item.grams)} g'
                              : '${fmtDec(item.quantity, 2)} × ${portionInLang(item.portionLabel!)} (${fmtInt(item.grams)} g)',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${fmtInt(item.kcal)} kcal'),
                            IconButton(
                              tooltip: tr('Remove', 'Verwijderen'),
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                if (!_removeGuard.allow()) return;
                                final removed = _items[i];
                                setState(() => _items.removeAt(i));
                                showUndo(context, tr('Ingredient removed', 'Ingrediënt verwijderd'), () {
                                  if (mounted) setState(() => _items.insert(i.clamp(0, _items.length), removed));
                                });
                              },
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
                  '${tr('Per serving', 'Per portie')} (${fmtInt(recipe.totalGrams / recipe.servings)} g): ${fmtInt(perServing['energy'] ?? 0)} kcal',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                // Eerst de macro's op één regel; water, alcohol en cafeïne pas onderaan (N80)
                const SizedBox(height: 4),
                Text(
                  [
                    '${tr('Protein', 'Eiwit')} ${fmtDec(perServing['protein'] ?? 0)} g',
                    '${tr('Carbs', 'Koolhydraten')} ${fmtDec(perServing['carbs'] ?? 0)} g',
                    '${tr('Sugars', 'Suikers')} ${fmtDec(perServing['sugars'] ?? 0)} g',
                    '${tr('Fat', 'Vet')} ${fmtDec(perServing['fat'] ?? 0)} g',
                  ].join(' · '),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                NutrientPanel(
                  values: perServing,
                  targets: s.targets,
                  onlyWithData: true,
                  single: true,
                  groups: [...NutrientGroup.values.where((g) => g != NutrientGroup.general), NutrientGroup.general],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
