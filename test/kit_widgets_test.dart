import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/nutrition/targets.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/kit.dart';

Widget _app(Widget child) => MaterialApp(
  theme: buildTheme(Brightness.light),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('kleine knoppen: tikzone minstens 44 px, knop zelf even groot', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_app(StepButton(icon: Icons.add, tooltip: 'plus', onTap: () => taps++)));
    final size = tester.getSize(find.byType(StepButton));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));
    expect(tester.getSize(find.descendant(of: find.byType(StepButton), matching: find.byType(Material))), const Size(32, 32));
    // Tik in de doorzichtige rand telt ook
    final r = tester.getRect(find.byType(StepButton));
    await tester.tapAt(r.topLeft + const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 1);

    await tester.pumpWidget(_app(SquareButton(icon: Icons.add, tooltip: 'plus', onPressed: () => taps++)));
    expect(tester.getSize(find.byType(SquareButton)).width, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(SquareButton));
    await tester.pump(const Duration(milliseconds: 500));
    expect(taps, 2);
  });

  testWidgets('PillChip met vinkje verandert niet van breedte', (tester) async {
    Future<Size> sizeOf(bool selected) async {
      await tester.pumpWidget(_app(PillChip(label: 'Groenten', selected: selected, check: true, onTap: () {})));
      return tester.getSize(find.byType(PillChip));
    }

    expect(await sizeOf(false), await sizeOf(true));
  });

  test('overloopstaart groeit met de overschrijding', () {
    final at150 = RangeBar.overflowTailWidth(1.0, 200);
    final at300 = RangeBar.overflowTailWidth(2.0, 200);
    final at1000 = RangeBar.overflowTailWidth(1000 / 150, 200);
    expect(at300, greaterThan(at150));
    expect(at1000, greaterThan(at300));
    expect(RangeBar.overflowTailWidth(1000, 200), lessThanOrEqualTo(60));
  });

  testWidgets('RangeBar bouwt boven 150%', (tester) async {
    await tester.pumpWidget(_app(const SizedBox(width: 200, child: RangeBar(amount: 300, target: Target(goal: 100)))));
    expect(tester.takeException(), isNull);
  });
}
