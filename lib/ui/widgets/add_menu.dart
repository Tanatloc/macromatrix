import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../i18n.dart';
import '../screens/add_food_screen.dart';
import '../screens/body_screen.dart';
import '../screens/diary_screen.dart';
import '../screens/planner_screen.dart';
import '../screens/product_scan_screen.dart';
import '../screens/supplements_screen.dart';
import '../theme.dart';
import 'quick_log.dart';

/// De ronde +-knop in het midden van de navigatie op een gsm.
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

/// Alles wat je kunt toevoegen, als raster van drie kolommen onderaan het scherm. Eten gaat naar de maaltijd die past bij
/// het uur (op een andere dag: de eerste lege maaltijd), op de dag die open staat in je dagboek.
Future<void> showAddMenu(BuildContext context) {
  final p = context.pal;
  final meal = context.read<AppState>().suggestedMeal;
  void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  final items = <(IconData, Color, String, VoidCallback)>[
    (Icons.restaurant_rounded, p.protein, tr('Add food', 'Eten toevoegen'), () => push(AddFoodScreen(meal: meal))),
    (Icons.qr_code_scanner_rounded, p.ink, tr('Scan barcode', 'Barcode scannen'), () => scanBarcodeFor(context, meal)),
    (Icons.bolt_rounded, p.carbs, tr('Quick log', 'Snel loggen'), () => showQuickLog(context, meal: meal)),
    // Foto van je bord: hetzelfde venster als Snel loggen, dat meteen om een foto vraagt
    (Icons.photo_camera_outlined, p.protein, tr('Photo', 'Foto'), () => showQuickLog(context, meal: meal, photo: true)),
    (Icons.directions_run_rounded, p.brand, tr('Exercise', 'Beweging'), () => addExercise(context)),
    (Icons.monitor_weight_outlined, p.fat, tr('Weight', 'Gewicht'), () => push(const BodyScreen(addWeight: true))),
    (Icons.sticky_note_2_outlined, p.fiber, tr('Note', 'Notitie'), () => editNote(context)),
    (Icons.medication_outlined, p.ok, tr('Supplements', 'Supplementen'), () => push(const SupplementsScreen())),
    (Icons.event_note_outlined, p.low, tr('Plan meals', 'Maaltijden plannen'), () => push(const PlannerScreen())),
    (Icons.fact_check_outlined, p.ink2, tr('Check a product', 'Product checken'), () => push(const ProductScanScreen())),
  ];
  // Op een breed scherm (bv. een smal browservenster op een pc) geen uitgerekt gsm-blad: hooguit 560 breed, vaste
  // rijhoogte, en scrollen als het venster te laag is, zodat ook de derde rij bereikbaar blijft (P144)
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        child: GridView(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, mainAxisExtent: 112),
          shrinkWrap: true,
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
