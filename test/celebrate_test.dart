import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/celebrate.dart';

/// Feestmeldingen (reeks, level, badge): bovenaan, verdwijnen vanzelf (ook met een knop), en wachten op elkaar.
void main() {
  testWidgets('bovenaan, vanzelf weg, in volgorde, knop werkt', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var shared = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showCelebration(context, leading: const Icon(Icons.star), text: 'New badge', actionLabel: 'Share', onAction: () => shared++);
                showCelebration(context, leading: const Icon(Icons.star), text: 'Level up');
              },
              child: const Text('go'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('New badge'), findsOneWidget);
    expect(find.text('Level up'), findsNothing);
    // Bovenaan het scherm
    expect(tester.getTopLeft(find.text('New badge')).dy, lessThan(120));
    // Met een knop toch vanzelf weg na een paar seconden; dan de volgende
    await tester.pump(celebrationDuration);
    await tester.pumpAndSettle();
    expect(find.text('New badge'), findsNothing);
    expect(find.text('Level up'), findsOneWidget);
    await tester.pump(celebrationDuration);
    await tester.pumpAndSettle();
    expect(find.text('Level up'), findsNothing);

    // Knop: actie en weg
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, 1);
    expect(find.text('New badge'), findsNothing);
    await tester.pump(celebrationDuration);
    await tester.pumpAndSettle();
  });
}
