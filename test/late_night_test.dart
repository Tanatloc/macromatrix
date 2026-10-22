import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:macromatrix/day_clock.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/levels.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/day_charts.dart';

void main() {
  setUpAll(() async {
    setAppLang(AppLang.nl);
    await initializeDateFormatting(appLocale);
  });
  tearDown(() => dayStartHour = 3);

  test('vóór het begin van de dag is het nog gisteren', () {
    dayStartHour = 3;
    final shifted = logicalNow();
    final now = DateTime.now();
    expect(now.difference(shifted).inMinutes, closeTo(180, 1));
    dayStartHour = 0;
    expect(now.difference(logicalNow()).inMinutes, closeTo(0, 1));
  });

  test('laat op: wat je na middernacht voor gisteren logt, telt nog voor XP', () {
    dayStartHour = 3;
    // Om 2 uur 's nachts, twee kalenderdagen later, zit je nog in de dag erna
    final late = DateTime(2026, 10, 17, 2).millisecondsSinceEpoch;
    expect(countsForXp(id: 'abc', day: '2026-10-15', createdAtMs: late), isTrue);
    final morning = DateTime(2026, 10, 17, 9).millisecondsSinceEpoch;
    expect(countsForXp(id: 'abc', day: '2026-10-15', createdAtMs: morning), isFalse);
    dayStartHour = 0;
    expect(countsForXp(id: 'abc', day: '2026-10-15', createdAtMs: late), isFalse);
  });

  testWidgets('energie: een dag met beweging wordt aan zijn eigen, hoger doel getoetst', (tester) async {
    tester.view.physicalSize = const Size(360, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final days = [for (var i = 0; i < 3; i++) DateTime(2026, 10, 10 + i)];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          // Dag 2: 2400 kcal gegeten, maar 500 kcal verbrand → doel 2500, dus op doel
          body: EnergyBars(days: days, values: const [2000, 2400, 2400], goal: 2000, goals: const [2000, 2500, 2000]),
        ),
      ),
    );
    final p = tester.element(find.byType(EnergyBars)).pal;
    expect(energyColor(p, 2000, 2000), p.okFill);
    expect(energyColor(p, 2400, 2500), p.okFill);
    expect(energyColor(p, 2400, 2000), p.highFill);
    expect(find.text('doel van die dag (incl. beweging)'), findsOneWidget);
    // Zonder keuze toont de regel boven de grafiek de laatste dag; tik op dag 2 voor zijn doel met beweging
    String detail() => tester.widgetList<RichText>(find.byType(RichText)).map((t) => t.text.toPlainText()).firstWhere((t) => t.contains('kcal'));
    expect(detail(), contains('/ 2.000 kcal'));
    await tester.tapAt(tester.getCenter(find.byType(CustomPaint).last));
    await tester.pump();
    expect(detail(), contains('/ 2.500 kcal'));
    expect(detail(), contains('500 beweging'));
  });
}
