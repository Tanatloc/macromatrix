import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/models.dart';
import '../../data/off_client.dart';
import '../../data/user_db.dart';
import '../../nutrition/food_groups.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/values.dart';
import '../../platform/platform.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../../nutrition/allergens.dart';
import '../widgets/allergen_banner.dart';
import '../widgets/kit.dart';
import 'custom_food_screen.dart';
import 'food_detail_screen.dart';
import 'recipe_screen.dart';
import 'scan_screen.dart';
import '../widgets/quick_log.dart';
import '../../i18n.dart';

enum _Scope {
  all('All', 'Alles'),
  basic('Basic', 'Basis'),
  brands('Brands', 'Merken'),
  mine('My products', 'Mijn producten'),
  recipes('Recipes', 'Recepten');

  const _Scope(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

/// Zoeken en toevoegen: recent gegeten, maaltijden, recepten, eigen producten, de ingebouwde database en
/// Open Food Facts. Met [pickOnly] om een ingrediënt te kiezen (geeft een [ItemTemplate] terug).
class AddFoodScreen extends StatefulWidget {
  const AddFoodScreen({super.key, required this.meal, this.pickOnly = false, this.forPlan = false, this.scan = false});
  final Meal meal;
  final bool pickOnly;

  /// Meteen de camera openen om een barcode te scannen.
  final bool scan;

  /// Met [pickOnly]: kiezen voor de planner (in plaats van voor een recept).
  final bool forPlan;

  @override
  State<AddFoodScreen> createState() => _AddFoodScreenState();
}

class _AddFoodScreenState extends State<AddFoodScreen> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  List<Food> _local = const [];
  List<Food>? _online;
  bool _loadingOnline = false;
  String? _error;
  _Scope _scope = _Scope.all;

  static bool get _canScan => canScanBarcodes;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    if (widget.scan) WidgetsBinding.instance.addPostFrameCallback((_) => _scan());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _local = q.trim().isEmpty ? const [] : context.read<AppState>().searchLocal(q.trim());
        _online = null;
        _error = null;
      });
      if (_scope == _Scope.brands && q.trim().length >= 3) _searchOnline(q.trim());
    });
  }

  Future<void> _submit(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    if (looksLikeBarcode(q)) return _byBarcode(q);
    if (_scope == _Scope.all || _scope == _Scope.brands) await _searchOnline(q);
  }

  void _setScope(_Scope s) {
    setState(() => _scope = s);
    final q = _query.text.trim();
    if (s == _Scope.brands && q.isNotEmpty && _online == null) _searchOnline(q);
  }

  Future<void> _searchOnline(String q) async {
    setState(() {
      _loadingOnline = true;
      _error = null;
    });
    try {
      final r = await context.read<AppState>().off.search(q);
      if (mounted && _query.text.trim() == q) setState(() => _online = r);
    } on OffException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingOnline = false);
    }
  }

  Future<void> _byBarcode(String code) async {
    final s = context.read<AppState>();
    setState(() {
      _loadingOnline = true;
      _error = null;
    });
    try {
      final food = await s.lookupBarcode(code);
      if (!mounted) return;
      if (food != null) {
        _open(food);
      } else {
        _notFound(code);
      }
    } on OffException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loadingOnline = false);
    }
  }

  void _notFound(String code) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Product not found', 'Product niet gevonden')),
        content: Text(
          tr(
            'Barcode $code is not in Open Food Facts, or has no nutrition values. You can enter it yourself from the packaging.',
            'Barcode $code staat niet in Open Food Facts, of zonder voedingswaarden. Je kunt het zelf invullen met de gegevens van de verpakking.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _createCustom(barcode: code);
            },
            child: Text(tr('Enter it yourself', 'Zelf invullen')),
          ),
        ],
      ),
    );
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
    if (code != null && mounted) await _byBarcode(code);
  }

  Future<void> _createCustom({String? barcode}) async {
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => CustomFoodScreen(barcode: barcode)));
    if (food != null && mounted) _open(food);
  }

  Future<void> _open(Food food) async {
    // Merkproduct: eerst aanvullen met de micronutriënten van het gekoppelde basisproduct
    if (food.source == FoodSource.off) {
      setState(() => _loadingOnline = true);
      food = await context.read<AppState>().completeOff(food);
      if (!mounted) return;
      setState(() => _loadingOnline = false);
    }
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(food: food, meal: widget.meal, pickOnly: widget.pickOnly, forPlan: widget.forPlan),
      ),
    );
    if (!mounted) return;
    if (result is ItemTemplate) Navigator.of(context).pop(result);
    if (result == true) Navigator.of(context).pop();
  }

  Future<void> _newRecipe() async {
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => const RecipeScreen()));
    if (food != null && mounted) _open(food);
  }

  void _addMeal(SavedMeal m) {
    context.read<AppState>().addSavedMeal(m, widget.meal);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(tr('${m.name} added (${m.items.length} items)', '${m.name} toegevoegd (${m.items.length} items)'))));
    Navigator.of(context).pop();
  }

  /// Opnieuw toevoegen met dezelfde hoeveelheid als de vorige keer.
  void _addAgain(DiaryEntry e) {
    final s = context.read<AppState>();
    s.addFood(s.foodFor(e), meal: widget.meal, grams: e.grams, quantity: e.quantity, portionLabel: e.portionLabel);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('${e.name} added to ${widget.meal.label.toLowerCase()}', '${e.name} toegevoegd aan ${widget.meal.label.toLowerCase()}')),
      ),
    );
  }

  Future<void> _deleteMeal(SavedMeal m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete ${m.name}?', '${m.name} verwijderen?')),
        content: Text(
          tr(
            'The saved meal will be removed. What is already in your diary stays.',
            'De opgeslagen maaltijd verdwijnt. Wat al in je dagboek staat, blijft.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete', 'Verwijderen'))),
        ],
      ),
    );
    if (ok == true && mounted) context.read<AppState>().deleteSavedMeal(m);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final q = _query.text.trim();
    final left = (s.targets['energy']?.goal ?? 0) - s.totals['energy'];
    final lows = [
      for (final a in attentionList(s.totals.values, s.targets, limit: 4))
        if (a.$3 == Level.low) a.$1,
    ];

    bool matches(Food f) => searchMatches(f.name, q) || (f.brand != null && searchMatches(f.brand!, q));
    final results = switch (_scope) {
      _Scope.all => _local,
      _Scope.basic => [
        for (final f in _local)
          if (f.source.european || f.source == FoodSource.usda) f,
      ],
      _Scope.brands => _online ?? const <Food>[],
      _Scope.mine => [
        for (final f in s.user.customFoods())
          if (q.isEmpty || matches(f)) f,
      ],
      _Scope.recipes => [
        for (final r in s.recipes())
          if (q.isEmpty || matches(r.toFood())) r.toFood(),
      ],
    };
    final showResults = q.isNotEmpty || _scope == _Scope.mine || _scope == _Scope.recipes;

    Widget card(Food f) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _ResultCard(food: f, lows: lows, onTap: () => _open(f)),
    );
    // Hetzelfde voedingsmiddel uit verschillende landen: één resultaat, de rest onder "Andere bronnen"
    final grouped = _scope == _Scope.all || _scope == _Scope.basic;
    final groups = grouped ? groupFoods(results) : const <FoodGroup>[];

    return Scaffold(
      body: SafeArea(
        child: Narrow(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 16, 6),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug')),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(
                            widget.forPlan
                                ? tr('Plan', 'Plannen')
                                : widget.pickOnly
                                ? tr('Recipe', 'Recept')
                                : tr('Add to', 'Toevoegen aan'),
                          ),
                          Text(
                            widget.pickOnly && !widget.forPlan ? tr('Choose ingredient', 'Ingrediënt kiezen') : widget.meal.label,
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.25, color: p.ink),
                          ),
                        ],
                      ),
                    ),
                    if (!widget.pickOnly)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: p.surface,
                          border: Border.all(color: p.line),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          left >= 0
                              ? tr('${fmtInt(left)} kcal left', '${fmtInt(left)} kcal over')
                              : tr('${fmtInt(-left)} kcal over', '${fmtInt(-left)} kcal te veel'),
                          style: numStyle(12, weight: FontWeight.w400, color: left >= 0 ? p.ink2 : p.high),
                        ),
                      ),
                    if (!widget.pickOnly)
                      IconButton(
                        tooltip: tr('Quick log (speak or type)', 'Snel loggen (inspreken of typen)'),
                        icon: Icon(speechSupported ? Icons.mic_none_rounded : Icons.bolt_rounded, color: p.ink),
                        onPressed: () => showQuickLog(context, meal: widget.meal),
                      ),
                    PopupMenuButton<String>(
                      tooltip: tr('New product or recipe', 'Nieuw product of recept'),
                      icon: Icon(Icons.add_box_outlined, color: p.ink),
                      onSelected: (v) => v == 'recipe' ? _newRecipe() : _createCustom(),
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'custom', child: Text(tr('Own product (from the label)', 'Eigen product (van het etiket)'))),
                        if (!widget.pickOnly) PopupMenuItem(value: 'recipe', child: Text(tr('New recipe', 'Nieuw recept'))),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _query,
                        focusNode: _focus,
                        autofocus: !_canScan,
                        textInputAction: TextInputAction.search,
                        onChanged: _onChanged,
                        onSubmitted: _submit,
                        style: TextStyle(fontSize: 16, color: p.ink),
                        decoration: InputDecoration(
                          hintText: _canScan
                              ? tr('Search for a product', 'Zoek een product')
                              : tr('Search for a product or type a barcode', 'Zoek een product of typ een barcode'),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          suffixIcon: q.isEmpty
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (showResults)
                                      Text(
                                        '${results.length}',
                                        style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                                      ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18),
                                      tooltip: tr('Clear', 'Wissen'),
                                      onPressed: () {
                                        _query.clear();
                                        _onChanged('');
                                      },
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    if (_canScan) ...[
                      const SizedBox(width: 8),
                      SquareButton(
                        icon: Icons.qr_code_scanner_rounded,
                        tooltip: tr('Scan barcode', 'Barcode scannen'),
                        filled: true,
                        size: 52,
                        onPressed: _scan,
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  children: [
                    for (final sc in _Scope.values)
                      if (!(widget.pickOnly && !widget.forPlan && sc == _Scope.recipes))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: PillChip(label: sc.label, selected: _scope == sc, onTap: () => _setScope(sc)),
                        ),
                  ],
                ),
              ),
              if (_loadingOnline) const LinearProgressIndicator(minHeight: 2),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(_error!, style: TextStyle(color: p.high)),
                      ),
                    if (!showResults)
                      ..._idle(s, p)
                    else ...[
                      if (looksLikeBarcode(q))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Panel(
                            shadow: false,
                            radius: 16,
                            onTap: () => _byBarcode(q),
                            padding: const EdgeInsets.all(14),
                            child: Row(
                              children: [
                                const Icon(Icons.qr_code_rounded, size: 20),
                                const SizedBox(width: 10),
                                Text(
                                  tr('Look up barcode $q', 'Barcode $q opzoeken'),
                                  style: TextStyle(fontWeight: FontWeight.w500, color: p.ink),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (lows.isNotEmpty && results.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                          child: Row(
                            children: [
                              const StatusMark(Level.low, size: 8),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  tr(
                                    'Highlighted: what 100 g adds to today\'s shortfalls',
                                    'Gemarkeerd: wat 100 g toevoegt aan je tekorten van vandaag',
                                  ),
                                  style: TextStyle(fontSize: 12, color: p.ink2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (grouped)
                        for (final g in groups)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _GroupCard(group: g, lows: lows, onOpen: _open),
                          )
                      else
                        for (final f in results) card(f),
                      if (results.isEmpty && !_loadingOnline)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                          child: Text(switch (_scope) {
                            _Scope.brands =>
                              _online == null
                                  ? tr('Press Enter to search branded products.', 'Druk op Enter om merkproducten te zoeken.')
                                  : tr('No branded products found.', 'Geen merkproducten gevonden.'),
                            _Scope.mine => tr(
                              'No products of your own found. Create one with the plus at the top right.',
                              'Geen eigen producten gevonden. Maak er een met het plusje rechtsboven.',
                            ),
                            _Scope.recipes => tr(
                              'No recipes found. Create one with the plus at the top right.',
                              'Geen recepten gevonden. Maak er een met het plusje rechtsboven.',
                            ),
                            _ => tr('Nothing found in the built-in database.', 'Niets gevonden in de ingebouwde database.'),
                          }, style: TextStyle(color: p.ink2)),
                        ),
                      if (_scope == _Scope.all) ...[
                        if (_online == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: OutlinedButton.icon(
                              onPressed: _loadingOnline ? null : () => _searchOnline(q),
                              icon: const Icon(Icons.public_rounded, size: 18),
                              label: Text(tr('Also search "$q" in branded products', 'Zoek "$q" ook in merkproducten')),
                            ),
                          )
                        else ...[
                          const SizedBox(height: 8),
                          SectionHeader(tr('Branded products (Open Food Facts)', 'Merkproducten (Open Food Facts)'), trailing: '${_online!.length}'),
                          for (final f in _online!) card(f),
                          if (_online!.isEmpty)
                            Text(tr('No branded products found.', 'Geen merkproducten gevonden.'), style: TextStyle(color: p.ink2)),
                        ],
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Zonder zoekterm: opgeslagen maaltijden en recent gebruikte producten.
  List<Widget> _idle(AppState s, Palette p) {
    final recent = s.user.recent(limit: 25);
    final favorites = s.favorites();
    return [
      if (favorites.isNotEmpty) ...[
        SectionHeader(tr('Favourites', 'Favorieten')),
        Panel(
          shadow: false,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (final (i, f) in favorites.indexed)
                InkWell(
                  onTap: () => _open(f),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star_rounded, size: 18, color: const Color(0xFFE3A956)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                              ),
                              if (f.brand != null && f.brand!.isNotEmpty)
                                Text(
                                  f.brand!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: p.ink3),
                                ),
                            ],
                          ),
                        ),
                        Text(
                          '${fmtInt(f.kcalPer100g)} kcal/100 g',
                          style: numStyle(12, weight: FontWeight.w400, color: p.ink2),
                        ),
                        IconButton(
                          tooltip: tr('Remove from favourites', 'Uit favorieten'),
                          icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
                          onPressed: () => s.toggleFavorite(f),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (!widget.pickOnly && s.savedMeals().isNotEmpty) ...[
        SectionHeader(tr('Saved meals', 'Opgeslagen maaltijden')),
        Panel(
          shadow: false,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (final (i, m) in s.savedMeals().indexed)
                InkWell(
                  onTap: () => _addMeal(m),
                  onLongPress: () => _deleteMeal(m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                              ),
                              Text(
                                m.items.map((i) => i.name).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${fmtInt(m.kcal)} kcal',
                          style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      SectionHeader(
        tr('Recently used', 'Recent gebruikt'),
        trailing: recent.isEmpty || widget.pickOnly ? null : tr('tap + for the same amount', 'tik + voor dezelfde hoeveelheid'),
      ),
      if (recent.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            tr('What you add shows up here so you can pick it again quickly.', 'Wat je toevoegt, verschijnt hier om snel opnieuw te kiezen.'),
            style: TextStyle(color: p.ink2),
          ),
        )
      else
        Panel(
          shadow: false,
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              for (final (i, e) in recent.indexed)
                InkWell(
                  onTap: () => _open(s.foodFor(e)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      border: i == 0 ? null : Border(top: BorderSide(color: p.line)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: p.ink),
                              ),
                              Text(
                                e.portionLabel == null
                                    ? '${fmtInt(e.grams)} g'
                                    : '${fmtDec(e.quantity, e.quantity == e.quantity.roundToDouble() ? 0 : 1)} × ${e.portionLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${fmtInt(e.kcal)} kcal',
                          style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
                        ),
                        if (!widget.pickOnly) ...[
                          const SizedBox(width: 10),
                          StepButton(
                            icon: Icons.add_rounded,
                            tooltip: tr('Add ${e.name} again', '${e.name} opnieuw toevoegen'),
                            size: 36,
                            onTap: () => _addAgain(e),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
    ];
  }
}

/// Is [q] (woorden in willekeurige volgorde) terug te vinden in [text]?
bool searchMatches(String text, String q) {
  final t = text.toLowerCase();
  return q.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).every(t.contains);
}

/// Korte naam voor een label: "Vitamine D" wordt "Vit. D", "B12 (cobalamine)" wordt "B12".
String shortName(Nutrient n) {
  final base = n.name.replaceAll(RegExp(r'\s*\(.*\)'), '');
  if (base.startsWith('Vitamin ')) return 'Vit. ${base.substring(8)}';
  return base.startsWith('Vitamine ') ? 'Vit. ${base.substring(9)}' : base;
}

/// Eén zoekresultaat met eronder, open te klappen, hetzelfde voedingsmiddel uit andere bronnen.
class _GroupCard extends StatefulWidget {
  const _GroupCard({required this.group, required this.lows, required this.onOpen});
  final FoodGroup group;
  final List<Nutrient> lows;
  final void Function(Food) onOpen;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final g = widget.group;
    final card = _ResultCard(food: g.main, lows: widget.lows, onTap: () => widget.onOpen(g.main));
    if (g.others.isEmpty) return card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 8, 2),
            child: Row(
              children: [
                Text(
                  tr('Other sources (${g.others.length})', 'Andere bronnen (${g.others.length})'),
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
                ),
                Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: p.ink3),
              ],
            ),
          ),
        ),
        if (_open)
          for (final f in g.others)
            InkWell(
              onTap: () => widget.onOpen(f),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(
                  children: [
                    SourceBadge(f.source),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        f.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: p.ink),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${fmtInt(f.kcalPer100g)} kcal', style: numStyle(12.5, color: p.ink2)),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.food, required this.lows, required this.onTap});
  final Food food;
  final List<Nutrient> lows;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    final v = withDerived(food.per100g);
    final sub = [if (food.brand != null && food.brand!.isNotEmpty) food.brand!, ?food.localName, food.source.label].join(' · ');

    // Wat 100 g bijdraagt aan je tekorten, waarschuwingen voor limieten, en omega-3 als het opvalt
    final tags = <Tag>[
      for (final h in hitsFor(food, s.allergies))
        Tag(
          h.level == AllergenLevel.traces
              ? tr('Traces: ${h.allergen.label.toLowerCase()}', 'Sporen: ${h.allergen.label.toLowerCase()}')
              : '⚠ ${h.allergen.label}',
          kind: TagKind.warn,
        ),
    ];
    for (final n in lows) {
      final g = s.targets[n.key]?.goal;
      final f = g == null || g <= 0 ? 0 : (v[n.key] ?? 0) / g;
      if (f >= 0.15) tags.add(Tag('+ ${shortName(n)} ${food.estimated.containsKey(n.key) ? '≈ ' : ''}${fmtPct(f.toDouble())}', kind: TagKind.gap));
    }
    for (final k in const ['sodium', 'sfa']) {
      final max = s.targets[k]?.upper;
      if (max != null && (v[k] ?? 0) / max >= 0.25) {
        tags.add(
          Tag(
            tr(
              '${k == 'sodium' ? 'Sodium' : 'Sat. fat'} ${fmtPct((v[k] ?? 0) / max)} of max',
              '${k == 'sodium' ? 'Natrium' : 'Verz. vet'} ${fmtPct((v[k] ?? 0) / max)} van max',
            ),
            kind: TagKind.warn,
          ),
        );
      }
    }
    if ((v['epa_dha'] ?? 0) >= 300) tags.add(Tag('EPA+DHA ${fmtDec((v['epa_dha'] ?? 0) / 1000)} g'));

    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: SourceBadge(food.source)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(
                              children: [
                                if (context.select<AppState, bool>((s) => s.isFavorite(food.ref)))
                                  const WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFE3A956)),
                                    ),
                                  ),
                                TextSpan(text: food.name),
                              ],
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: p.ink),
                          ),
                          Text(
                            sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: p.ink3),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtInt(food.kcalPer100g), style: numStyle(14)),
                        Text('kcal/100 g', style: TextStyle(fontSize: 10.5, color: p.ink3)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                Row(
                  children: [
                    MacroSplitBar(macroSplit(v), width: 72),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        tr(
                          'P ${fmtDec(v['protein'] ?? 0)} · C ${fmtDec(v['carbs'] ?? 0)} · F ${fmtDec(v['fat'] ?? 0)}',
                          'E ${fmtDec(v['protein'] ?? 0)} · K ${fmtDec(v['carbs'] ?? 0)} · V ${fmtDec(v['fat'] ?? 0)}',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: numStyle(11.5, weight: FontWeight.w400, color: p.ink2),
                      ),
                    ),
                  ],
                ),
                if (tags.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 5, runSpacing: 5, children: tags.take(3).toList())],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
