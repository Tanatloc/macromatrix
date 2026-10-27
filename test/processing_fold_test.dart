import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/nutrition/processing.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/processing_card.dart';

/// Bewerkt eten op een gsm: openklappen met een tik, dichtklappen met een tik op de titel, zoals andere kaarten.
void main() {
  testWidgets('een tik op de titel klapt de kaart weer dicht', (tester) async {
    const share = ProcessingShare({Nova.unprocessed: 600, Nova.ultra: 200}, 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: SingleChildScrollView(child: ProcessingFold(share: share))),
      ),
    );
    expect(find.byKey(const ValueKey('processing-title')), findsNothing);
    await tester.tap(find.text('Processed food'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('processing-title')), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
    await tester.tap(find.text('Processed food'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('processing-title')), findsNothing);
  });
}
