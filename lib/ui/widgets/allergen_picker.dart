import 'package:flutter/material.dart';

import '../../i18n.dart';
import '../../nutrition/allergens.dart';
import '../theme.dart';

/// Keuze uit de 14 EU-allergenen. Alleen wat je aanduidt, geeft meldingen.
class AllergenPicker extends StatelessWidget {
  const AllergenPicker({super.key, required this.selected, required this.onChanged});
  final Set<Allergen> selected;
  final ValueChanged<Set<Allergen>> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in Allergen.values)
          () {
            final on = selected.contains(a);
            return FilterChip(
              label: Text(
                a.label,
                style: TextStyle(color: on ? p.high : p.ink, fontWeight: on ? FontWeight.w600 : null),
              ),
              selected: on,
              showCheckmark: true,
              selectedColor: p.highSoft,
              checkmarkColor: p.high,
              side: BorderSide(color: on ? p.high : p.line),
              onSelected: (v) => onChanged(v ? {...selected, a} : ({...selected}..remove(a))),
            );
          }(),
      ],
    );
  }
}

/// Uitleg onder de keuze.
String get allergenNote => tr(
  'You only get warnings for what you select. With scanned products the app checks the allergen list and ingredients from Open Food Facts; for other foods only the name. Always check the label.',
  'Je krijgt alleen meldingen voor wat je aanduidt. Bij gescande producten controleert de app de allergenen en ingrediënten van Open Food Facts; bij andere producten alleen de naam. Controleer altijd het etiket.',
);
