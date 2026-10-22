import 'package:flutter/material.dart';

import '../../data/user_db.dart' show Meal;
import '../../i18n.dart';
import '../screens/add_food_screen.dart';
import '../screens/body_screen.dart';
import '../screens/diary_screen.dart';
import '../screens/planner_screen.dart';
import '../screens/product_scan_screen.dart';
import '../screens/supplements_screen.dart';
import '../theme.dart';
import 'quick_log.dart';

/// De ronde +-knop in het midden van de navigatie op een gsm (zoals Cronometer).
class AddButton extends StatelessWidget {
  const AddButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Tooltip(
      message: tr('Add', 'Toevoegen'),
      child: Material(
        color: p.brand,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(width: 54, height: 54, child: Icon(Icons.add_rounded, size: 32, color: p.onBrand)),
        ),
      ),
    );
  }
}

/// Alles wat je kunt toevoegen, als raster van 3 × 3 onderaan het scherm. Eten gaat naar de maaltijd die past bij
/// het uur, op de dag die open staat in je dagboek.
Future<void> showAddMenu(BuildContext context) {
  final p = context.pal;
  final meal = Meal.forHour(DateTime.now().hour);
  void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  final items = <(IconData, Color, String, VoidCallback)>[
    (Icons.restaurant_rounded, p.protein, tr('Add food', 'Eten toevoegen'), () => push(AddFoodScreen(meal: meal))),
    (Icons.qr_code_scanner_rounded, p.ink, tr('Scan barcode', 'Barcode scannen'), () => push(AddFoodScreen(meal: meal, scan: true))),
    (Icons.bolt_rounded, p.carbs, tr('Quick log', 'Snel loggen'), () => showQuickLog(context, meal: meal)),
    (Icons.directions_run_rounded, p.brand, tr('Exercise', 'Beweging'), () => addExercise(context)),
    (Icons.monitor_weight_outlined, p.fat, tr('Weight', 'Gewicht'), () => push(const BodyScreen())),
    (Icons.sticky_note_2_outlined, p.fiber, tr('Note', 'Notitie'), () => editNote(context)),
    (Icons.medication_outlined, p.ok, tr('Supplements', 'Supplementen'), () => push(const SupplementsScreen())),
    (Icons.event_note_outlined, p.low, tr('Plan meals', 'Maaltijden plannen'), () => push(const PlannerScreen())),
    (Icons.fact_check_outlined, p.ink2, tr('Check a product', 'Product checken'), () => push(const ProductScanScreen())),
  ];
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          mainAxisSpacing: 4,
          childAspectRatio: 1.15,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (icon, color, label, onTap) in items)
              InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(ctx);
                  onTap();
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(color: ctx.pal.sunken, shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ctx.pal.ink),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
