import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../i18n.dart';
import '../../nutrition/allergens.dart';
import '../../state/app_state.dart';
import '../theme.dart';

List<AllergenHit> hitsFor(Food f, Set<Allergen> mine) => allergenHits(
  mine,
  name: '${f.name} ${f.brand ?? ''}',
  label: LabelInfo(allergens: f.allergenTags, traces: f.traceTags, ingredients: f.ingredients),
);

/// Rode (bevat) of oranje (kan sporen bevatten / op naam) melding voor jouw allergenen. Zonder ingestelde
/// allergie toont ze niets; rood blijft voor wat het etiket echt meldt, een gok op naam is oranje (N91).
class AllergenBanner extends StatelessWidget {
  const AllergenBanner({super.key, required this.food});
  final Food food;

  @override
  Widget build(BuildContext context) {
    final mine = context.select<AppState, Set<Allergen>>((s) => s.allergies);
    final hits = hitsFor(food, mine);
    if (hits.isEmpty) return const SizedBox.shrink();
    final p = context.pal;
    Color fg(AllergenHit h) => h.level == AllergenLevel.contains ? Colors.white : p.low;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final h in hits)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: h.level == AllergenLevel.contains ? p.high : p.lowSoft,
              borderRadius: BorderRadius.circular(12),
              border: h.level == AllergenLevel.contains ? null : Border.all(color: p.lowFill),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: fg(h)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(switch (h.level) {
                    AllergenLevel.contains => tr('Contains ${h.allergen.label.toLowerCase()}', 'Bevat ${h.allergen.label.toLowerCase()}'),
                    AllergenLevel.traces => tr(
                      'May contain traces of ${h.allergen.label.toLowerCase()}',
                      'Kan sporen van ${h.allergen.label.toLowerCase()} bevatten',
                    ),
                    AllergenLevel.name => tr(
                      'Probably contains ${h.allergen.label.toLowerCase()} (based on the name, check the label)',
                      'Bevat waarschijnlijk ${h.allergen.label.toLowerCase()} (op basis van de naam, controleer het etiket)',
                    ),
                  }, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: fg(h))),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
