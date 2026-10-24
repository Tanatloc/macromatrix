import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/user_db.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/processing.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';

/// Eigen product invullen, met de waarden van het etiket (per 100 g).
class CustomFoodScreen extends StatefulWidget {
  const CustomFoodScreen({super.key, this.barcode, this.existing});
  final String? barcode;
  final Food? existing;

  @override
  State<CustomFoodScreen> createState() => _CustomFoodScreenState();
}

/// Velden zoals op een Europees etiket, in die volgorde. Zout wordt omgerekend naar natrium.
const _labelKeys = ['energy', 'fat', 'sfa', 'carbs', 'sugars', 'fiber', 'protein'];

class _CustomFoodScreenState extends State<CustomFoodScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _brand = TextEditingController(text: widget.existing?.brand ?? '');
  late final _barcode = TextEditingController(text: widget.existing?.barcode ?? widget.barcode ?? '');
  late final _portionGrams = TextEditingController(text: _fmt(widget.existing?.portions.firstOrNull?.grams));

  /// Naam van die portie ("1 pot", "1 reep"); leeg = "1 portie".
  late final _portionName = TextEditingController(
    text: switch (widget.existing?.portions.firstOrNull?.label) {
      final l? when !_defaultPortionNames.contains(l) => l,
      _ => '',
    },
  );
  static const _defaultPortionNames = {'1 serving', '1 portie'};

  /// Verwerkingsgraad die je zelf kiest; null = weet ik niet (dan raden we niets uit de naam, N72).
  late Nova? _nova = Nova.of(widget.existing?.nova);
  late final _salt = TextEditingController(
    text: _fmt(widget.existing?.per100g['sodium'] == null ? null : widget.existing!.per100g['sodium']! * 2.5 / 1000),
  );
  late final Map<String, TextEditingController> _values = {
    for (final n in nutrients.where((n) => !n.derived)) n.key: TextEditingController(text: _fmt(widget.existing?.per100g[n.key])),
  };

  /// Vrije of toegevoegde suikers, als je het weet (staat soms op het etiket). Leeg = schatten uit de naam.
  late final _freeSugars = TextEditingController(text: _fmt(widget.existing?.per100g['free_sugars']));
  bool _showAll = false;

  static String _fmt(double? v) => v == null ? '' : (v == v.roundToDouble() ? '${v.round()}' : double.parse(v.toStringAsFixed(3)).toString().dec);
  static double? _parse(String s) => s.trim().isEmpty ? null : double.tryParse(s.trim().replaceAll(',', '.'));

  @override
  void initState() {
    super.initState();
    // Toon meteen alle velden als het bestaande product meer heeft dan het etiket
    _showAll = widget.existing?.per100g.keys.any((k) => !_labelKeys.contains(k) && k != 'sodium' && !(nutrientByKey[k]?.derived ?? true)) ?? false;
  }

  @override
  void dispose() {
    for (final c in [_name, _brand, _barcode, _portionGrams, _portionName, _salt, _freeSugars, ..._values.values]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _delete() async {
    final f = widget.existing!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete ${f.name}?', '${f.name} verwijderen?')),
        content: Text(
          tr(
            'The product disappears from your list. What is already in your diary stays.',
            'Het product verdwijnt uit je lijst. Wat al in je dagboek staat, blijft.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete', 'Verwijderen'))),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<AppState>().deleteCustomFood(f);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _save() {
    final invalid = _form.currentState!.validateGranularly();
    if (invalid.isNotEmpty) {
      // De bovenste fout in beeld brengen, ruim boven de knop Opslaan (stond er half achter, N29)
      final first = invalid.map((f) => f.context).reduce((a, b) => _top(a) <= _top(b) ? a : b);
      Scrollable.ensureVisible(first, alignment: 0.3, duration: const Duration(milliseconds: 250));
      return;
    }
    final per100g = <String, double>{for (final e in _values.entries) e.key: ?_parse(e.value.text)};
    final salt = _parse(_salt.text);
    if (salt != null) per100g['sodium'] = salt / 2.5 * 1000;
    if (_parse(_freeSugars.text) case final free?) per100g['free_sugars'] = free;
    final portion = _parse(_portionGrams.text);
    final portionName = _portionName.text.trim();
    final food = Food(
      ref: widget.existing?.ref ?? UserDb.newCustomRef(),
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      source: FoodSource.custom,
      per100g: withDerived(per100g),
      portions: [if (portion != null && portion > 0) Portion(portionName.isEmpty ? tr('1 serving', '1 portie') : portionName, portion)],
      nova: _nova?.group,
    );
    context.read<AppState>().saveCustomFood(food);
    Navigator.of(context).pop(food);
  }

  /// Bovenkant van een veld op het scherm, om de bovenste fout te vinden.
  static double _top(BuildContext c) => switch (c.findRenderObject()) {
    final RenderBox b when b.attached => b.localToGlobal(Offset.zero).dy,
    _ => double.infinity,
  };

  /// Een deel kan niet groter zijn dan het geheel: suikers horen bij de koolhydraten, verzadigd vet bij het vet (N29).
  static const _partOf = {'sugars': 'carbs', 'sfa': 'fat'};

  /// Per 100 g kan een macro nooit boven 100 g, en kcal nooit boven ~900; negatief kan nooit.
  static double _maxFor(String key) => switch (key) {
    'energy' => 900,
    'protein' || 'fat' || 'carbs' || 'sugars' || 'fiber' || 'sfa' => 100,
    _ => 1e6,
  };

  Widget _field(Nutrient n) => TextFormField(
    controller: _values[n.key],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: decimalInput,
    onTap: selectAllOnTap(_values[n.key]!),
    decoration: InputDecoration(labelText: n.name, suffixText: n.unit, isDense: true),
    validator: (t) {
      if (t == null || t.trim().isEmpty) return null;
      final v = _parse(t);
      if (v == null) return tr('Not a valid number', 'Geen geldig getal');
      if (v < 0) return tr('Cannot be negative', 'Kan niet negatief zijn');
      if (v > _maxFor(n.key)) return tr('At most ${fmtNum(_maxFor(n.key))} per 100 g', 'Hoogstens ${fmtNum(_maxFor(n.key))} per 100 g');
      if (_partOf[n.key] case final whole?) {
        final max = _parse(_values[whole]!.text);
        if (max != null && v > max + 1e-9) {
          final name = nutrientByKey[whole]!.name.toLowerCase();
          return tr('At most the $name (${fmtNum(max)} g)', 'Hoogstens de $name (${fmtNum(max)} g)');
        }
      }
      return null;
    },
  );

  /// Onder de suikers: het deel dat vrij of toegevoegd is. Ingevuld gaat het voor op de schatting uit de naam.
  Widget _freeSugarsField() => TextFormField(
    controller: _freeSugars,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: decimalInput,
    onTap: selectAllOnTap(_freeSugars),
    decoration: InputDecoration(
      labelText: tr('of which free/added sugars (optional)', 'waarvan vrije/toegevoegde suikers (optioneel)'),
      helperText: tr('Leave empty and we estimate it from the name.', 'Laat leeg en we schatten het uit de naam.'),
      suffixText: 'g',
      isDense: true,
    ),
    validator: (t) {
      if (t == null || t.trim().isEmpty) return null;
      final v = _parse(t);
      if (v == null) return tr('Not a valid number', 'Geen geldig getal');
      if (v < 0) return tr('Cannot be negative', 'Kan niet negatief zijn');
      final sugars = _parse(_values['sugars']!.text);
      if (sugars != null && v > sugars + 1e-9) return tr('At most the sugars (${fmtNum(sugars)} g)', 'Hoogstens de suikers (${fmtNum(sugars)} g)');
      if (v > 100) return tr('At most 100 per 100 g', 'Hoogstens 100 per 100 g');
      return null;
    },
  );

  /// Een paar voorbeelden per groep, zodat je zonder NOVA-kennis kunt kiezen.
  static String _novaExample(Nova n) => switch (n) {
    Nova.unprocessed => tr('fruit, plain yoghurt, oats', 'fruit, natuuryoghurt, havermout'),
    Nova.culinary => tr('oil, butter, sugar, honey', 'olie, boter, suiker, honing'),
    Nova.processed => tr('cheese, bread, canned beans', 'kaas, brood, bonen in blik'),
    Nova.ultra => tr('soft drinks, sweets, flavoured yoghurt', 'frisdrank, snoep, smaakjesyoghurt'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = nutrients.where((n) => !n.derived && !_labelKeys.contains(n.key) && n.key != 'sodium');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? tr('Own product', 'Eigen product') : tr('Edit product', 'Product bewerken')),
        actions: [
          if (widget.existing != null && widget.existing!.source == FoodSource.custom)
            IconButton(icon: const Icon(Icons.delete_outline_rounded), tooltip: tr('Delete', 'Verwijderen'), onPressed: _delete),
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
                child: Text(tr('Save', 'Opslaan')),
              ),
            ),
          ),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: tr('Name', 'Naam')),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (t) => t == null || t.trim().isEmpty ? tr('Give the product a name', 'Geef het product een naam') : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brand,
                        decoration: InputDecoration(labelText: tr('Brand (optional)', 'Merk (optioneel)')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _barcode,
                        keyboardType: TextInputType.number,
                        inputFormatters: wholeInput,
                        decoration: InputDecoration(labelText: tr('Barcode (optional)', 'Barcode (optioneel)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _portionGrams,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: decimalInput,
                        onTap: selectAllOnTap(_portionGrams),
                        decoration: InputDecoration(
                          labelText: tr('Weight of one serving (optional)', 'Gewicht van één portie (optioneel)'),
                          suffixText: 'g',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _portionName,
                        decoration: InputDecoration(
                          labelText: tr('Serving name (optional)', 'Naam van de portie (optioneel)'),
                          hintText: tr('1 pot', '1 potje'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Zelf kiezen hoe bewerkt het is; zonder keuze toont het product geen groep (N72)
                DropdownButtonFormField<Nova?>(
                  initialValue: _nova,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('How processed is it? (optional)', 'Hoe bewerkt is het? (optioneel)'),
                    helperText: tr('Leave it on "Don\'t know" if you are not sure.', 'Laat op "Weet ik niet" als je twijfelt.'),
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Don\'t know', 'Weet ik niet'))),
                    for (final n in Nova.values)
                      DropdownMenuItem(value: n, child: Text('${n.label} · ${_novaExample(n)}', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _nova = v),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('Nutrition per 100 g', 'Voedingswaarden per 100 g'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(tr('As on the label.', 'Zoals op het etiket.'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final k in _labelKeys) ...[
                  Padding(padding: const EdgeInsets.only(bottom: 10), child: _field(nutrientByKey[k]!)),
                  if (k == 'sugars') Padding(padding: const EdgeInsets.only(bottom: 10), child: _freeSugarsField()),
                ],
                TextFormField(
                  controller: _salt,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: decimalInput,
                  onTap: selectAllOnTap(_salt),
                  decoration: InputDecoration(labelText: tr('Salt', 'Zout'), suffixText: 'g', isDense: true),
                ),
                const SizedBox(height: 12),
                if (!_showAll)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _showAll = true),
                    icon: const Icon(Icons.expand_more),
                    label: Text(tr('Vitamins, minerals and more', 'Vitaminen, mineralen en meer')),
                  )
                else
                  for (final g in NutrientGroup.values)
                    if (extra.where((n) => n.group == g).toList() case final list when list.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
                        child: Text(g.label, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      for (final n in list) Padding(padding: const EdgeInsets.only(bottom: 10), child: _field(n)),
                    ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
