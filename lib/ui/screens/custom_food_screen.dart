import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/user_db.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../../i18n.dart';

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
  late final _salt = TextEditingController(
    text: _fmt(widget.existing?.per100g['sodium'] == null ? null : widget.existing!.per100g['sodium']! * 2.5 / 1000),
  );
  late final Map<String, TextEditingController> _values = {
    for (final n in nutrients.where((n) => !n.derived)) n.key: TextEditingController(text: _fmt(widget.existing?.per100g[n.key])),
  };
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
    for (final c in [_name, _brand, _barcode, _portionGrams, _salt, ..._values.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final per100g = <String, double>{for (final e in _values.entries) e.key: ?_parse(e.value.text)};
    final salt = _parse(_salt.text);
    if (salt != null) per100g['sodium'] = salt / 2.5 * 1000;
    final portion = _parse(_portionGrams.text);
    final food = Food(
      ref: widget.existing?.ref ?? UserDb.newCustomRef(),
      name: _name.text.trim(),
      brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
      barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
      source: FoodSource.custom,
      per100g: withDerived(per100g),
      portions: [if (portion != null && portion > 0) Portion(tr('1 serving', '1 portie'), portion)],
    );
    context.read<AppState>().saveCustomFood(food);
    Navigator.of(context).pop(food);
  }

  Widget _field(Nutrient n) => TextFormField(
    controller: _values[n.key],
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: n.name, suffixText: n.unit, isDense: true),
    validator: (t) => t == null || t.trim().isEmpty || _parse(t) != null ? null : tr('Not a valid number', 'Geen geldig getal'),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final extra = nutrients.where((n) => !n.derived && !_labelKeys.contains(n.key) && n.key != 'sodium');

    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? tr('Own product', 'Eigen product') : tr('Edit product', 'Product bewerken'))),
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
                        decoration: InputDecoration(labelText: tr('Barcode (optional)', 'Barcode (optioneel)')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _portionGrams,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: tr('Weight of one serving (optional)', 'Gewicht van één portie (optioneel)'),
                    suffixText: 'g',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  tr('Nutrition per 100 g', 'Voedingswaarden per 100 g'),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(tr('As on the label.', 'Zoals op het etiket.'), style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                for (final k in _labelKeys) Padding(padding: const EdgeInsets.only(bottom: 10), child: _field(nutrientByKey[k]!)),
                TextFormField(
                  controller: _salt,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
