import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/main.dart';
import 'package:macromatrix/ui/screens/diary_screen.dart';

void main() {
  test('opgeslagen maaltijd met een maaltijdnaam gaat naar die maaltijd', () {
    expect(mealInName('Ontbijt'), Meal.breakfast);
    expect(mealInName('Breakfast with eggs'), Meal.breakfast);
    expect(mealInName('Lunch box'), Meal.lunch);
    expect(mealInName('Avondeten met vis'), Meal.dinner);
    expect(mealInName('Snacks'), Meal.snacks);
    expect(mealInName('Kipcurry'), isNull);
    // Geen halve woorden: 'Lunchroom-salade' blijft zonder maaltijd
    expect(mealInName('Lunchroomsalade'), isNull);
  });

  testWidgets('Escape sluit een volledig scherm, maar niet het eerste', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => EscapeToClose(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Scaffold(body: TextField(autofocus: true))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    // Typen in het tekstveld werkt gewoon
    await tester.enterText(find.byType(TextField), 'abc');
    expect(find.text('abc'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('open'), findsOneWidget);

    // Op het eerste scherm doet Escape niets
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });
}
