import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/models.dart';
import '../../data/user_db.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/portions.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/processing_card.dart';
import '../widgets/allergen_banner.dart';
import '../widgets/kit.dart';
import 'custom_food_screen.dart';
import 'recipe_screen.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

/// Hoeveelheid kiezen en alle voedingsstoffen van één product bekijken, met het effect op je dag.
/// Ook om een dagboekregel te wijzigen, of (met [pickOnly]) om een ingrediënt voor een recept te kiezen.
class FoodDetailScreen extends StatefulWidget {
  const FoodDetailScreen({
    super.key,
    required this.food,
    required this.meal,
    this.entry,
    this.pickOnly = false,
    this.forPlan = false,
    this.initialGrams,
    this.initialPortion,
  });

  final Food food;
  final Meal meal;

  /// Bestaande regel in het dagboek (wijzigen); null = nieuw toevoegen.
  final DiaryEntry? entry;

  /// Niet in het dagboek zetten maar de gekozen hoeveelheid teruggeven als [ItemTemplate].
  final bool pickOnly;

  /// Met [pickOnly]: kiezen voor de planner.
  final bool forPlan;

  /// Voorgestelde hoeveelheid (bv. vanuit een suggestie).
  final double? initialGrams;
  final Portion? initialPortion;

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  late final TextEditingController _qty;
  late Meal _meal = widget.meal;
  late Food _food = widget.food;

  /// null = gram, anders een portie van het product.
  Portion? _portion;

  /// Tijdstip "uu:mm" (optioneel).
  String? _time;

  /// Begintoestand bij het wijzigen van een bestaande regel, om te zien of er iets veranderd is (P68).
  late final ({String qty, String? portion, Meal meal, String? time}) _initial;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _time = e?.time;
    if (e != null) {
      // Portie bestaat niet meer: terugvallen op gram (een geschatte portie zoals "1 slice (≈35 g)" telt mee)
      _portion = e.portionLabel == null
          ? null
          : [..._food.portions, ...everydayPortions(_food)].where((p) => p.label == e.portionLabel).firstOrNull;
      _qty = TextEditingController(text: _fmt(_portion == null ? e.grams : e.quantity));
    } else if (widget.initialGrams != null) {
      _portion = widget.initialPortion;
      // Met een portie: het aantal porties dat bij de meegegeven grammen hoort (2 sneetjes, niet altijd 1)
      _qty = TextEditingController(text: _fmt(_portion == null ? widget.initialGrams! : widget.initialGrams! / _portion!.grams));
    } else {
      // Geen portie in de databank: begin bij de gewone portie (1 sneetje, 1 glas, 1 stuk) als die er is
      _portion = _food.portions.firstOrNull ?? everydayPortions(_food).firstOrNull;
      _qty = TextEditingController(text: _portion == null ? '100' : '1');
    }
    _initial = (qty: _qty.text, portion: _portion?.label, meal: _meal, time: _time);
  }

  /// Alleen bij het wijzigen van een bestaande regel: is er iets aangepast dat verloren zou gaan?
  bool get _dirty =>
      widget.entry != null &&
      (_qty.text != _initial.qty || _portion?.label != _initial.portion || _meal != _initial.meal || _time != _initial.time);

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Discard change?', 'Wijziging weggooien?')),
        content: Text(tr('You changed this entry but didn\'t save it.', 'Je hebt deze regel aangepast maar niet bewaard.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Keep editing', 'Verder bewerken'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Discard', 'Weggooien'))),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _qty.dispose();
    super.dispose();
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.round().toString() : double.parse(v.toStringAsFixed(2)).toString().dec;

  double get _quantity => double.tryParse(_qty.text.replaceAll(',', '.')) ?? 0;
  double get _grams => _portion == null ? _quantity : _quantity * _portion!.grams;

  void _setQuantity(double v) => setState(() => _qty.text = _fmt(math.max(0, v)));

  /// Plus en min: per portie (per halve onder 2), in gram per 10 tot 100 g en daarboven per 25 (P19).
  void _stepBy({required bool up}) => _setQuantity(stepQuantity(_quantity, up: up, portion: _portion != null));

  /// Andere eenheid kiezen (N43): naar gram rekent de hoeveelheid om (3 kommen skyr = 450 g, niet 100 g); een portie
  /// begint op 1. Nog eens op de gekozen eenheid tikken verandert niets.
  void _choose(Portion? p) {
    if (p?.label == _portion?.label) return;
    setState(() {
      final grams = _grams;
      _portion = p;
      _qty.text = _fmt(p == null ? (grams > 0 ? grams.roundToDouble() : 100) : 1);
    });
  }

  /// Al aan het bewaren: een dubbele tik op Toevoegen voegt niets dubbel toe.
  bool _saving = false;

  Future<void> _save() async {
    final s = context.read<AppState>();
    if (_grams <= 0 || _saving) return;
    _saving = true;
    try {
      await _saveChecked(s);
    } finally {
      _saving = false;
    }
  }

  Future<void> _saveChecked(AppState s) async {
    // Een vergeten komma of cijfers tussen het oude getal maken van 100 g snel 100 kg: eerst vragen
    final kcal = (_food.per100g['energy'] ?? 0) * _grams / 100;
    if (_grams > 2000 || kcal > 3000) {
      final amount = _grams >= 1000 ? '${fmtNum(_grams / 1000, 2)} kg' : '${_fmt(_grams)} g';
      final ok = await confirmUnusual(
        context,
        tr(
          '$amount of ${_food.name} is ${fmtInt(kcal)} kcal. Is that the right amount?',
          '$amount ${_food.name} is ${fmtInt(kcal)} kcal. Is dat de juiste hoeveelheid?',
        ),
      );
      if (!ok || !mounted) return;
    }
    final quantity = _portion == null ? _grams : _quantity;
    if (widget.pickOnly) {
      Navigator.of(context).pop(
        ItemTemplate(
          foodRef: _food.ref,
          name: _food.name,
          brand: _food.brand,
          grams: _grams,
          quantity: quantity,
          portionLabel: _portion?.label,
          per100g: _food.per100g,
        ),
      );
      return;
    }
    final e = widget.entry;
    if (e == null) {
      _add(s, quantity);
      return;
    }
    s.updateEntry(e, meal: _meal, grams: _grams, quantity: quantity, portionLabel: _portion?.label, time: _time);
    Navigator.of(context).pop(true);
  }

  /// Nieuw toevoegen, met dezelfde korte melding en Ongedaan maken als bij Recent en Snel loggen (N62). Staat het
  /// product al in deze maaltijd, dan wordt het bijgeteld; in een andere eenheid (250 g naast 1 kom) in gram.
  /// Ongedaan maken draait alleen deze toevoeging terug.
  void _add(AppState s, double quantity) {
    final grams = _grams;
    final label = _portion?.label;
    final meal = _meal.label.toLowerCase();
    final unit = switch (_portion) {
      final EverydayPortion x => x.short,
      final x? => x.label,
      null => '',
    };
    final amount = _portion == null ? '${_fmt(grams)} g' : (quantity == 1 ? unit : '${_fmt(quantity)} × $unit');
    final messenger = ScaffoldMessenger.of(context);
    final String message;
    final VoidCallback undo;

    final same = s.user.mergeTarget(day: s.day, meal: _meal, food: _food, portionLabel: label, time: _time);
    final other = same == null
        ? s.user.mergeTarget(day: s.day, meal: _meal, food: _food, portionLabel: label, time: _time, otherUnit: true)
        : null;
    final row = other == null ? null : s.entries.where((x) => x.id == other.id).firstOrNull;
    if (row != null) {
      // Zelfde product in een andere eenheid: samen in één regel, in gram
      final total = row.grams + grams;
      s.updateEntry(row, meal: row.meal, grams: total, quantity: total, portionLabel: null, time: row.time);
      undo = () =>
          s.updateEntry(row, meal: row.meal, grams: row.grams, quantity: row.quantity, portionLabel: row.portionLabel, time: row.time);
      message = tr(
        '${_food.name}: $amount added to $meal (now ${_fmt(total)} g in one line)',
        '${_food.name}: $amount bijgeteld bij $meal (nu ${_fmt(total)} g in één regel)',
      );
    } else {
      final added = s.addFood(_food, meal: _meal, grams: grams, quantity: quantity, portionLabel: label, time: _time);
      undo = () => s.undoAdds([added]);
      if (added.merged) {
        final now = _portion == null ? '${_fmt(added.prevGrams! + grams)} g' : _fmt(added.prevQuantity! + quantity);
        message = tr('${_food.name}: $amount added to $meal (now $now)', '${_food.name}: $amount bijgeteld bij $meal (nu $now)');
      } else {
        message = tr('${_food.name} ($amount) added to $meal', '${_food.name} ($amount) toegevoegd aan $meal');
      }
    }
    Navigator.of(context).pop(true);
    showUndo(null, message, undo, messenger: messenger);
  }

  Future<void> _pickTime() async {
    final now = TimeOfDay.now();
    final initial = _time == null ? now : TimeOfDay(hour: int.parse(_time!.substring(0, 2)), minute: int.parse(_time!.substring(3)));
    final t = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t != null) setState(() => _time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
  }

  /// Bestaande herhalingen van dit item (zelfde product, zelfde maaltijd).
  List<RepeatItem> _repeatsOf(AppState s) {
    final e = widget.entry;
    if (e == null) return const [];
    return s.repeats().where((r) => r.item.foodRef == e.foodRef && r.mealIndex == e.meal.index).toList();
  }

  /// Dit item automatisch laten terugkomen op gekozen weekdagen, met een hoeveelheid die je hier nog kunt aanpassen.
  Future<void> _repeat() async {
    final s = context.read<AppState>();
    var mask = 0x7f;
    const days = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
    final unitGrams = _portion?.grams ?? 1;
    final amount = TextEditingController(text: _fmt(_portion == null ? _grams : _quantity));
    double qty() => double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    final existing = _repeatsOf(s);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Repeat automatically', 'Automatisch herhalen')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(
                  'From tomorrow, ${widget.entry!.name} is added to your ${widget.entry!.meal.label.toLowerCase()} automatically, in this amount:',
                  '${widget.entry!.name} komt vanaf morgen vanzelf in je dagboek bij ${widget.entry!.meal.label.toLowerCase()}, in deze hoeveelheid:',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: decimalInput,
                      decoration: InputDecoration(isDense: true, labelText: tr('Amount', 'Hoeveelheid')),
                      onChanged: (_) => setD(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_portion == null ? 'g' : '× ${_portion!.label}  (= ${_fmt(qty() * unitGrams)} g)', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              if (existing.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  tr(
                    'This item already repeats (${existing.length}×). This adds another one; manage them under Settings → Recurring items.',
                    'Dit item wordt al herhaald (${existing.length}×). Dit voegt er nog een toe; beheren kan in Instellingen → Terugkerende items.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: ctx.pal.ink3),
                ),
              ],
              const SizedBox(height: 12),
              Text(tr('On:', 'Op:')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    PillChip(
                      label: days[i],
                      selected: mask & (1 << i) != 0,
                      onTap: () => setD(() => mask = mask & (1 << i) != 0 ? mask & ~(1 << i) : mask | (1 << i)),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(onPressed: mask == 0 || qty() <= 0 ? null : () => Navigator.pop(ctx, true), child: Text(tr('Repeat', 'Herhalen'))),
          ],
        ),
      ),
    );
    // Niet meteen dispose(): het veld leeft nog tijdens de sluitanimatie van het venster
    final q = qty();
    if (ok == true && mounted) {
      // Herhalen met de gekozen hoeveelheid (en de portie die nu gekozen is)
      final e = widget.entry!;
      s.addRepeat(
        DiaryEntry(
          id: e.id,
          day: e.day,
          meal: e.meal,
          foodRef: _food.ref,
          name: _food.name,
          brand: _food.brand,
          grams: q * unitGrams,
          quantity: _portion == null ? q * unitGrams : q,
          portionLabel: _portion?.label,
          per100g: _food.per100g,
          time: e.time,
        ),
        mask,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Repeating. Manage it under Settings → Recurring items.', 'Wordt herhaald. Beheren kan in Profiel → Terugkerende items.')),
        ),
      );
    }
  }

  Future<void> _editRecipe() async {
    final recipe = context.read<AppState>().user.recipe(_food.ref);
    if (recipe == null) return;
    final updated = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => RecipeScreen(existing: recipe)));
    if (updated != null && mounted) _replaceFood(updated);
  }

  Future<void> _editCustom() async {
    final updated = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => CustomFoodScreen(existing: _food)));
    if (updated != null && mounted) _replaceFood(updated);
  }

  /// Na het bewerken van een recept of eigen product: de oude portie (bv. "1/4 van het recept = 240 g") hoort niet
  /// meer bij het nieuwe product (N59). Het scherm begint opnieuw op 1 verse portie; bij het wijzigen van een
  /// dagboekregel blijft het aantal porties staan, in de nieuwe portie.
  void _replaceFood(Food updated) => setState(() {
    final hadPortion = _portion != null;
    _food = updated;
    final fresh = updated.portions.firstOrNull ?? everydayPortions(updated).firstOrNull;
    if (hadPortion && fresh != null) {
      _qty.text = _fmt(widget.entry != null ? _quantity : 1);
      _portion = fresh;
    } else if (hadPortion) {
      // Geen portie meer: de grammen van wat er stond
      _qty.text = _fmt(_grams > 0 ? _grams : 100);
      _portion = null;
    }
    // In gram: die grammen blijven gelden
  });

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    // Met de vrije suikers erbij, geschat zoals in de dagtotalen (label, ingrediënten van een recept, of de naam)
    final per100 = s.per100gWithSugars(_food);
    final amounts = scale(per100, _grams);
    final editing = widget.entry != null;
    final repeating = editing && _repeatsOf(s).isNotEmpty;
    final kcal = amounts['energy'] ?? 0;

    // Uitleg bij geschatte waarden: uit welk product in welke databank ze komen. "~bron:id" = vergelijkbaar product
    // (geschaald), "~~head:x" of "~~cat:x" = gemiddelde van vergelijkbare producten (zie tool/build_foods.py)
    String bare(String ref) => ref.replaceFirst(RegExp(r'^~+'), '');
    final donors = <String, Food?>{
      for (final ref in _food.estimated.values.toSet())
        if (!ref.startsWith('~~')) ref: s.foods.byRef(bare(ref)),
    };
    String donorName(String ref) =>
        '${donors[ref]?.source.labelWithCountry ?? tr('another database', 'een andere databank')}${donors[ref] == null ? '' : ' ("${donors[ref]!.name}")'}';
    final fromLabel = _food.source == FoodSource.off;
    final estimates = {
      for (final MapEntry(key: k, value: ref) in _food.estimated.entries)
        k: fromLabel
            ? tr(
                'Estimated: not on the label. Taken from the comparable basic product in ${donorName(ref)}, '
                    'adjusted to the protein and fat content of this product.',
                'Geschat: staat niet op het etiket. Overgenomen van het vergelijkbare basisproduct in ${donorName(ref)}, '
                    'aangepast aan het eiwit- en vetgehalte van dit product.',
              )
            : ref.startsWith('~~')
            ? tr(
                'Estimated: missing in ${_food.source.label}. This is the average of comparable products '
                    '(${ref.substring(ref.indexOf(':') + 1)}), adjusted to the water, fat and protein content of this product.',
                'Geschat: ontbreekt in ${_food.source.label}. Dit is het gemiddelde van vergelijkbare producten '
                    '(${ref.substring(ref.indexOf(':') + 1)}), aangepast aan het water-, vet- en eiwitgehalte van dit product.',
              )
            : ref.startsWith('~')
            ? tr(
                'Estimated: missing in ${_food.source.label}. Taken from a comparable product in ${donorName(ref)}, '
                    'adjusted to the water, fat and protein content of this product.',
                'Geschat: ontbreekt in ${_food.source.label}. Overgenomen van een vergelijkbaar product in ${donorName(ref)}, '
                    'aangepast aan het water-, vet- en eiwitgehalte van dit product.',
              )
            : tr(
                'Estimated: missing in ${_food.source.label} and filled in from the same food in ${donorName(ref)}.',
                'Geschat: ontbreekt in ${_food.source.label} en is aangevuld uit hetzelfde voedingsmiddel in ${donorName(ref)}.',
              ),
    };
    final measured = _food.per100g.keys.where((k) => k != 'energy' && !_food.estimated.containsKey(k)).length;

    final ctaLabel = widget.forPlan
        ? tr('Add to plan (${_meal.label.toLowerCase()})', 'In plan zetten (${_meal.label.toLowerCase()})')
        : widget.pickOnly
        ? tr('Add to recipe', 'Toevoegen aan recept')
        : editing
        ? tr('Save', 'Opslaan')
        : tr('Add to ${_meal.label.toLowerCase()}', 'Toevoegen aan ${_meal.label.toLowerCase()}');

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: p.bg,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: SafeArea(
          child: Narrow(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _grams > 0 ? _save : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(ctaLabel, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15.5)),
                    ),
                    const SizedBox(width: 10),
                    Opacity(
                      opacity: 0.7,
                      child: Text('${fmtInt(kcal)} kcal', style: numStyle(14, weight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        // Terug-knop en acties staan vast boven de lijst, zodat ze niet wegscrollen
        child: Column(
          children: [
            Narrow(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 16, 4),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug')),
                    const Spacer(),
                    SquareButton(
                      icon: s.isFavorite(_food.ref) ? Icons.star_rounded : Icons.star_outline_rounded,
                      tooltip: s.isFavorite(_food.ref)
                          ? tr('Remove from favourites', 'Uit favorieten')
                          : tr('Add to favourites', 'Aan favorieten toevoegen'),
                      onPressed: () => s.toggleFavorite(_food),
                    ),
                    const SizedBox(width: 6),
                    if (_food.source == FoodSource.custom && s.user.food(_food.ref) != null) ...[
                      SquareButton(icon: Icons.edit_outlined, tooltip: tr('Edit product', 'Product bewerken'), onPressed: _editCustom),
                      const SizedBox(width: 6),
                    ],
                    if (_food.source == FoodSource.recipe) ...[
                      SquareButton(icon: Icons.edit_outlined, tooltip: tr('Edit recipe', 'Recept bewerken'), onPressed: _editRecipe),
                      const SizedBox(width: 6),
                    ],
                    if (editing) ...[
                      SquareButton(
                        // Gevuld (en ander icoon) als dit item al automatisch terugkomt
                        icon: repeating ? Icons.repeat_on_rounded : Icons.repeat_rounded,
                        filled: repeating,
                        tooltip: repeating
                            ? tr('Already repeats · add another repeat', 'Wordt al herhaald · nog een herhaling toevoegen')
                            : tr('Repeat automatically', 'Automatisch herhalen'),
                        onPressed: _repeat,
                      ),
                      const SizedBox(width: 6),
                      SquareButton(
                        icon: Icons.delete_outline_rounded,
                        tooltip: tr('Remove from diary', 'Verwijderen uit dagboek'),
                        onPressed: () {
                          final e = widget.entry!;
                          final messenger = ScaffoldMessenger.of(context);
                          s.deleteEntry(e);
                          Navigator.of(context).pop(true);
                          showUndo(null, tr('${e.name} removed', '${e.name} verwijderd'), () => s.restoreEntries([e]), messenger: messenger);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  Narrow(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_food.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 22)),
                                if (_food.brand != null && _food.brand!.isNotEmpty) Text(_food.brand!, style: TextStyle(fontSize: 14, color: p.ink2)),
                                if (_food.localName != null) Text(_food.localName!, style: TextStyle(fontSize: 13.5, color: p.ink2)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    SourceBadge(_food.source),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(sourceLine(_food), style: TextStyle(fontSize: 13, color: p.ink2)),
                                    ),
                                    IconButton(
                                      tooltip: tr('About this data', 'Over deze gegevens'),
                                      visualDensity: VisualDensity.compact,
                                      icon: Icon(Icons.info_outline_rounded, size: 20, color: p.ink3),
                                      onPressed: () => showDialog<void>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(tr('About this data', 'Over deze gegevens')),
                                          content: Text(
                                            [
                                              _food.source.citation,
                                              '$measured ${fromLabel ? tr('values from the label', 'waarden van het etiket') : tr('measured values', 'gemeten waarden')}',
                                              if (_food.estimated.isNotEmpty)
                                                tr(
                                                  '${_food.estimated.length} values estimated from a similar food (marked ≈)',
                                                  '${_food.estimated.length} waarden geschat uit een gelijkaardig product (met ≈)',
                                                ),
                                              if (_food.barcode != null) tr('Barcode ${_food.barcode}', 'Barcode ${_food.barcode}'),
                                            ].join('\n'),
                                          ),
                                          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close', 'Sluiten')))],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (s.novaFor(_food.ref, food: _food) case final nova?)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Row(
                                      children: [
                                        LegendItem.box(novaColor(p, nova), w: 10, h: 10, radius: 3),
                                        const SizedBox(width: 8),
                                        Text(
                                          tr('${nova.label} (NOVA ${nova.group})', '${nova.label} (NOVA ${nova.group})'),
                                          style: TextStyle(fontSize: 13, color: p.ink2),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          AllergenBanner(food: _food),
                          const SizedBox(height: 4),
                          // Eerst hoeveel en bij welke maaltijd, daarna wat het bijdraagt
                          _amountPanel(p),
                          const SizedBox(height: 10),
                          _MacroTiles(amounts: amounts, targets: s.targets),
                          if (!widget.pickOnly) ...[const SizedBox(height: 10), _ImpactPanel(added: amounts, editing: widget.entry)],
                          const SizedBox(height: 10),
                          _ValuesPanel(
                            amounts: amounts,
                            per100: per100,
                            grams: _grams,
                            targets: s.targets,
                            estimates: estimates,
                            sourceLabel: _food.source.label,
                            fromLabel: fromLabel,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ));
  }

  Widget _amountPanel(Palette p) {
    final options = <(Portion?, String, String)>[
      (null, tr('Grams', 'Gram'), ''),
      // Porties uit de databank, aangevuld met gewone porties (sneetje, glas, kom ...) als geschatting (P19)
      for (final x in portionOptions(_food)) x is EverydayPortion ? (x, x.short, '≈${_fmt(x.grams)} g') : (x, x.label, '${_fmt(x.grams)} g'),
    ];
    // Op label: geschatte porties worden bij elke opbouw opnieuw gemaakt
    bool selected(Portion? x) => x == null ? _portion == null : _portion?.label == x.label;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StepButton(icon: Icons.remove_rounded, tooltip: tr('Less', 'Minder'), size: 44, onTap: () => _stepBy(up: false)),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    IntrinsicWidth(
                      child: TextField(
                        controller: _qty,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: decimalInput,
                        onTap: selectAllOnTap(_qty),
                        style: numStyle(40, color: p.ink),
                        decoration: const InputDecoration(
                          isDense: true,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                        ),
                        onChanged: (_) => setState(() {}),
                        // Enter bevestigt het getal en sluit het toetsenbord; toevoegen doe je bewust met de knop (P67)
                        onSubmitted: (_) => FocusScope.of(context).unfocus(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        _portion == null ? 'g' : '× ${_portion!.label}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: p.ink2),
                      ),
                    ),
                  ],
                ),
              ),
              StepButton(icon: Icons.add_rounded, tooltip: tr('More', 'Meer'), size: 44, onTap: () => _stepBy(up: true)),
            ],
          ),
          if (_portion != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '= ${_fmt(_grams)} g',
                textAlign: TextAlign.center,
                style: numStyle(12, weight: FontWeight.w400, color: p.ink3),
              ),
            ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (i, (x, label, sub)) in options.indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _PortionButton(
                    label: label,
                    sub: sub,
                    selected: selected(x),
                    onTap: () => _choose(x),
                  ),
                ],
              ],
            ),
          ),
          if (!widget.pickOnly) ...[
            const SizedBox(height: 10),
            Segmented<Meal>(
              height: 30,
              fontSize: 12.5,
              items: [for (final m in Meal.values) (m, m.label)],
              selected: _meal,
              onChanged: (m) => setState(() => _meal = m),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: p.ink2, padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded, size: 16),
                label: Text(_time == null ? tr('Add time', 'Tijdstip toevoegen') : tr('At $_time', 'Om $_time')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PortionButton extends StatelessWidget {
  const _PortionButton({required this.label, required this.sub, required this.selected, required this.onTap});
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: selected ? p.ink : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? p.ink : p.lineStrong),
      ),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88, maxWidth: 180),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: selected ? p.bg : p.ink),
                ),
                // Ook zonder tweede regel even hoog, zodat de knoppen niet verspringen (N43)
                Text(sub.isEmpty ? ' ' : sub, style: TextStyle(fontSize: 11, color: (selected ? p.bg : p.ink).withValues(alpha: 0.8))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MacroTiles extends StatelessWidget {
  const _MacroTiles({required this.amounts, required this.targets});
  final NutrientMap amounts;
  final Map<String, Target> targets;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    String share(String k) {
      final g = targets[k]?.goal;
      return g == null || g <= 0 ? '' : fmtPct((amounts[k] ?? 0) / g);
    }

    // Een leeg veld (eigen product zonder eiwit ingevuld) is onbekend, geen 0 g (N72)
    String sub(String k) {
      if (!amounts.containsKey(k)) return tr('unknown', 'onbekend');
      final pct = share(k);
      return pct.isEmpty ? tr('no goal', 'geen doel') : tr('$pct of goal', '$pct van doel');
    }

    String grams(String k) => amounts[k] == null ? '–' : '${fmtDec(amounts[k]!)} g';

    final tiles = [
      ('kcal', amounts['energy'] == null ? '–' : fmtInt(amounts['energy']!), sub('energy'), p.ink),
      (tr('Protein', 'Eiwit'), grams('protein'), sub('protein'), p.protein),
      (tr('Carbs', 'Koolh.'), grams('carbs'), sub('carbs'), p.carbs),
      (tr('Fat', 'Vet'), grams('fat'), sub('fat'), p.fat),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, value, sub, color)) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Panel(
                shadow: false,
                radius: 14,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        LegendItem.box(color, w: 6, h: 6),
                        const SizedBox(width: 5),
                        Text(label, style: TextStyle(fontSize: 11, color: p.ink2)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(value, style: numStyle(19)),
                    ),
                    Text(sub, style: TextStyle(fontSize: 11, color: p.ink3)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Effect op vandaag: hoe ver je nu staat (grijs) en wat dit product toevoegt (merkkleur), voor de stoffen
/// waar het het meest verschil maakt. De balk loopt tot 200% van het doel; het streepje is 100%.
class _ImpactPanel extends StatelessWidget {
  const _ImpactPanel({required this.added, this.editing});
  final NutrientMap added;

  /// Bij wijzigen telt de huidige regel niet mee in "al gegeten".
  final DiaryEntry? editing;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final own = editing == null ? const <String, double>{} : s.entryValues(editing!);
    final totals = s.totals.values;
    double before(String k) => math.max(0, (totals[k] ?? 0) - (own[k] ?? 0));

    final rows = <(Nutrient, double, double, bool)>[];
    // Sporenelementen die bijna niemand bewust opvolgt: alleen tonen als dit product er echt veel van levert
    const obscure = {'fluoride', 'molybdenum', 'chloride', 'chromium', 'manganese', 'copper'};
    // Minder bekende stoffen komen na de gewone vitaminen en mineralen (N70: molybdeen, ALA of fluoride bovenaan)
    const minor = {...obscure, 'ala', 'la', 'phosphorus', 'b5', 'b7', 'choline'};
    // Boven de veilige bovengrens (UL): sleutel -> die grens (N70: groen bij 935% molybdeen)
    final overMax = <String, double>{};
    // Suiker telt als vrije suikers (zoals in de dagscore): de suiker van heel fruit of gewone melk kleurt niets
    // rood (N63). Met "Let op suiker" staat die regel altijd bovenaan, ook als het product geen vrije suiker heeft (N28).
    final freeTarget = s.targets['free_sugars']?.upper;
    final useFree = freeTarget != null && added.containsKey('free_sugars');
    final sugarFirst = s.sugarFocus && useFree;
    (Nutrient, double, double, bool)? sugarRow;
    for (final n in nutrients) {
      if (useFree && n.key == 'sugars') continue;
      if (sugarFirst && n.key == 'free_sugars') {
        sugarRow = (n, before(n.key) / freeTarget, (before(n.key) + added[n.key]!) / freeTarget, true);
        continue;
      }
      // Geen aminozuren (eiwit staat al in de tegels erboven, en threonine of leucine zegt bijna niemand iets)
      if (n.group == NutrientGroup.general || n.group == NutrientGroup.protein || const {'carbs', 'fat'}.contains(n.key)) continue;
      final t = s.targets[n.key];
      final add = added[n.key] ?? 0;
      if (t == null || add <= 0) continue;
      if (t.goal != null) {
        final over = t.upper != null && before(n.key) + add > t.upper!;
        // Een obscure stof die al boven de grens zat, alleen tonen als dit product er merkbaar bij doet
        if (obscure.contains(n.key) && add / t.goal! < 0.5 && !(over && add / t.upper! >= 0.05)) continue;
        if (over) overMax[n.key] = t.upper!;
        rows.add((n, before(n.key) / t.goal!, (before(n.key) + add) / t.goal!, false));
      } else if (t.upper != null) {
        final after = (before(n.key) + add) / t.upper!;
        // Limieten alleen tonen als ze ertoe doen
        if (after > 0.5 && add / t.upper! >= 0.05) rows.add((n, before(n.key) / t.upper!, after, true));
      }
    }
    // Eerst wat je dichter bij je doel brengt (tot 100%); wat al ruim gehaald is, komt pas daarna
    double gain((Nutrient, double, double, bool) r) => math.min(1.0, r.$3) - math.min(1.0, r.$2);
    int byGain((Nutrient, double, double, bool) a, (Nutrient, double, double, bool) b) {
      final g = gain(b).compareTo(gain(a));
      return g != 0 && (gain(a) > 0.02 || gain(b) > 0.02) ? g : (b.$3 - b.$2).compareTo(a.$3 - a.$2);
    }

    // Eerst de gewone stoffen, dan de minder bekende; wat boven de veilige bovengrens gaat, staat er altijd bij
    bool open((Nutrient, double, double, bool) r) => !r.$4 && !overMax.containsKey(r.$1.key);
    final goals = [
      ...rows.where((r) => open(r) && !minor.contains(r.$1.key)).toList()..sort(byGain),
      ...rows.where((r) => open(r) && minor.contains(r.$1.key)).toList()..sort(byGain),
    ];
    final over = (rows.where((r) => overMax.containsKey(r.$1.key)).toList()..sort((a, b) => b.$3.compareTo(a.$3))).take(2).toList();
    final limits = rows.where((r) => r.$4).toList()..sort((a, b) => b.$3.compareTo(a.$3));
    final room = math.max(3, (limits.isEmpty ? 5 : 4) - over.length);
    final shown = [?sugarRow, ...goals.take(room), ...over, ...limits.take(sugarRow == null ? 1 : 0)];
    // Suiker zonder vrije suikers: zeggen waarom de balk niet groeit
    final natural = useFree && (added['free_sugars'] ?? 0) < 0.05 && (added['sugars'] ?? 0) >= 1;
    if (shown.isEmpty) return const SizedBox.shrink();

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            s.isToday ? tr('Effect on today', 'Effect op vandaag') : tr('Effect on this day', 'Effect op deze dag'),
            trailing: Wrap(
              spacing: 10,
              children: [
                LegendItem(swatch: LegendItem.box(p.ink3, w: 10, h: 6), label: tr('already eaten', 'al gegeten')),
                LegendItem(swatch: LegendItem.box(p.brand, w: 10, h: 6), label: tr('this product', 'dit product')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final (n, b, a, limit) in shown)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: p.line)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          limit ? tr('${n.name} (max)', '${n.name} (max)') : n.name,
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                        ),
                        if (overMax[n.key] case final max?)
                          Text(
                            tr(
                              'Above the safe upper limit of ${formatAmount(max, n)} ${n.unit}',
                              'Boven de veilige bovengrens van ${formatAmount(max, n)} ${n.unit}',
                            ),
                            style: TextStyle(fontSize: 11, color: p.high),
                          ),
                        if (natural && n.key == 'free_sugars')
                          Text(
                            tr(
                              'Its ${fmtInt(added['sugars']!)} g sugar is natural (whole fruit, plain milk) and does not count',
                              'De ${fmtInt(added['sugars']!)} g suiker is natuurlijk (heel fruit, gewone melk) en telt niet mee',
                            ),
                            style: TextStyle(fontSize: 11, color: p.ink3),
                          ),
                        const SizedBox(height: 6),
                        _BeforeAfterBar(
                          before: b,
                          after: a,
                          addColor: (limit && a > 1) || overMax.containsKey(n.key) ? p.highFill : p.brand,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 88,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          a > 9.99 ? '>999%' : (a < 1 && (a * 100).round() >= 100 ? '99%' : fmtPct(a)),
                          style: numStyle(13, color: limit || overMax.containsKey(n.key) ? (a > 1 ? p.high : p.ink) : (a >= 1 ? p.ok : p.low)),
                        ),
                        Text(
                          tr('was ${fmtPct(b)}', 'was ${fmtPct(b)}'),
                          style: numStyle(10.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BeforeAfterBar extends StatelessWidget {
  const _BeforeAfterBar({required this.before, required this.after, required this.addColor});
  final double before;
  final double after;
  final Color addColor;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    double x(double f) => math.min(1, f / 2);
    return SizedBox(
      height: 13,
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 7,
                decoration: BoxDecoration(color: p.track, borderRadius: BorderRadius.circular(4)),
              ),
              Positioned(
                left: w * x(before),
                width: math.max(0, w * (x(after) - x(before))),
                height: 7,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: addColor,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                  ),
                ),
              ),
              Container(
                width: w * x(before),
                height: 7,
                decoration: BoxDecoration(
                  color: p.ink3,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(4)),
                ),
              ),
              Positioned(
                left: w / 2 - 1,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: p.ink),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Alle waarden van deze hoeveelheid (of per 100 g) in twee kolommen, met het deel van je dagdoel.
/// Volgorde zoals op een etiket; aminozuren in een eigen, ingeklapt blok onderaan.
class _ValuesPanel extends StatefulWidget {
  const _ValuesPanel({
    required this.amounts,
    required this.per100,
    required this.grams,
    required this.targets,
    required this.estimates,
    required this.sourceLabel,
    required this.fromLabel,
  });
  final NutrientMap amounts;

  /// Dezelfde waarden per 100 g, als vaste referentie om producten te vergelijken.
  final NutrientMap per100;
  final double grams;
  final Map<String, Target> targets;
  final Map<String, String> estimates;
  final String sourceLabel;
  final bool fromLabel;

  @override
  State<_ValuesPanel> createState() => _ValuesPanelState();
}

class _ValuesPanelState extends State<_ValuesPanel> {
  bool _all = false;
  bool _per100 = false;
  bool _amino = false;

  /// Eerst de regels van een voedingsetiket, in die volgorde; daarna de rest van vet en koolhydraten.
  static const _labelOrder = ['energy', 'fat', 'sfa', 'carbs', 'sugars', 'free_sugars', 'fiber', 'protein', 'salt'];
  static const _moreFatsCarbs = [
    'mufa',
    'pufa',
    'omega3',
    'ala',
    'epa_dha',
    'epa',
    'dpa',
    'dha',
    'omega6',
    'la',
    'aa',
    'trans',
    'cholesterol',
    'starch',
  ];

  /// Voedingsstoffen in etiketvolgorde, zonder aminozuren: etiket, meer vet/koolhydraten, vitaminen,
  /// mineralen (zonder zout, dat staat al bovenaan), en tot slot de overige stoffen.
  static List<Nutrient> get _ordered {
    final byKey = {for (final n in nutrients) n.key: n};
    final first = [..._labelOrder, ..._moreFatsCarbs].map((k) => byKey[k]).whereType<Nutrient>().toList();
    final taken = first.map((n) => n.key).toSet();
    Iterable<Nutrient> group(NutrientGroup g) => nutrients.where((n) => n.group == g && !taken.contains(n.key));
    return [
      ...first,
      ...group(NutrientGroup.vitamins),
      ...group(NutrientGroup.minerals),
      ...group(NutrientGroup.general),
      ...group(NutrientGroup.carbs),
      ...group(NutrientGroup.fats),
      ...group(NutrientGroup.other),
    ];
  }

  static List<Nutrient> get _aminoAcids => [
    for (final n in nutrients)
      if (n.group == NutrientGroup.protein && n.key != 'protein') n,
  ];

  /// Uitleg bij een geschatte waarde, in een venster (een tooltip bij tikken werkte niet betrouwbaar).
  void _showEstimate(Nutrient n, String text) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${n.name} ≈'),
      content: Text(text),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Close', 'Sluiten')))],
    ),
  );

  Widget _cell(Nutrient n, NutrientMap values) {
    final p = context.pal;
    final v = values[n.key];
    final t = widget.targets[n.key];
    final ref = t?.goal ?? t?.upper;
    final est = widget.estimates[n.key];
    final cell = Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: p.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              est == null ? n.name : '${n.name} ≈',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: p.ink2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            v == null ? '–' : '${formatAmount(v, n)} ${n.unit}',
            style: numStyle(12, weight: FontWeight.w500, color: p.ink, style: est == null ? null : FontStyle.italic),
          ),
          SizedBox(
            width: 38,
            child: Text(
              v == null || ref == null || ref <= 0 ? '' : fmtPct(v / ref),
              textAlign: TextAlign.right,
              style: numStyle(11, weight: FontWeight.w400, color: t?.isLimit == true && v != null && v > ref! ? p.high : p.ink3),
            ),
          ),
        ],
      ),
    );
    return est == null ? cell : InkWell(onTap: () => _showEstimate(n, est), child: cell);
  }

  /// Cellen in twee kolommen (of één op smalle schermen), kolom per kolom gevuld.
  Widget _grid(List<Widget> cells) => LayoutBuilder(
    builder: (context, c) {
      // Twee kolommen pas als de namen er voluit in passen (anders "Carbohydrat…" op een gsm)
      final cols = c.maxWidth >= 520 ? 2 : 1;
      final rows = (cells.length / cols).ceil();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var col = 0; col < cols; col++) ...[
            if (col > 0) const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var r = 0; r < rows; r++)
                    if (col * rows + r < cells.length) cells[col * rows + r],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final values = _per100 ? widget.per100 : widget.amounts;
    bool show(Nutrient n) => _all || values.containsKey(n.key);
    final cells = [
      for (final n in _ordered)
        if (show(n)) _cell(n, values),
    ];
    final amino = [
      for (final n in _aminoAcids)
        if (show(n)) _cell(n, values),
    ];

    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            _per100 ? tr('Per 100 g', 'Per 100 g') : tr('Per ${fmtInt(widget.grams)} g', 'Per ${fmtInt(widget.grams)} g'),
            trailing: Text(tr('% of your daily goal', '% van je dagdoel'), style: TextStyle(fontSize: 12, color: p.ink3)),
          ),
          const SizedBox(height: 8),
          // Altijd ook per 100 g, als vaste referentie
          Segmented<bool>(
            height: 30,
            fontSize: 12.5,
            items: [(false, tr('This amount', 'Deze hoeveelheid')), (true, tr('Per 100 g', 'Per 100 g'))],
            selected: _per100,
            onChanged: (v) => setState(() => _per100 = v),
          ),
          const SizedBox(height: 6),
          _grid(cells),
          if (amino.isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _amino = !_amino),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Amino acids (${amino.length})', 'Aminozuren (${amino.length})'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink2),
                      ),
                    ),
                    Icon(_amino ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 20, color: p.ink3),
                  ],
                ),
              ),
            ),
            if (_amino) _grid(amino),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0)),
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? tr('Known values only', 'Alleen bekende waarden') : tr('Show all nutrients', 'Alle voedingsstoffen tonen')),
            ),
          ),
          if (widget.estimates.isNotEmpty)
            Text(
              widget.fromLabel
                  ? tr(
                      '≈ estimated: not on the label, taken from the comparable basic product (linked by Open Food Facts). '
                          'Tap a value for the source.',
                      '≈ geschat: staat niet op het etiket en komt uit het vergelijkbare basisproduct (gekoppeld door Open Food Facts). '
                          'Tik op een waarde voor de bron.',
                    )
                  : tr(
                      '≈ estimated: missing in ${widget.sourceLabel}, filled in from the same or a comparable food. '
                          'Tap a value for the source.',
                      '≈ geschat: ontbreekt in ${widget.sourceLabel}, aangevuld uit hetzelfde of een vergelijkbaar voedingsmiddel. '
                          'Tik op een waarde voor de bron.',
                    ),
              style: TextStyle(fontSize: 11.5, height: 1.45, color: p.ink3),
            ),
        ],
      ),
    );
  }
}

/// Bron in gewone woorden, bv. "Branded product (label)" of "French food table".
String sourceLine(Food f) => switch (f.source) {
  FoodSource.off => tr('Branded product · values from the label', 'Merkproduct · waarden van het etiket'),
  FoodSource.custom => tr('Your own product', 'Je eigen product'),
  FoodSource.recipe => tr('Your recipe', 'Je recept'),
  FoodSource.usda when f.ref.startsWith('fdc:') => tr('Branded product (US)', 'Merkproduct (VS)'),
  _ => tr('Official food table · ${f.source.country}', 'Officiële voedingstabel · ${f.source.country}'),
};
