// Tip in de webapp als WebGL uit staat (LibreWolf): één keer, en weg na OK (lib/ui/widgets/webgl_tip.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/ui/widgets/webgl_tip.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  setUp(() => setAppLang(AppLang.en));

  Future<void> show(WidgetTester tester, UserDb db, {required bool accelerated}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => maybeShowWebGlTip(context, db, accelerated: accelerated),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
  }

  testWidgets('WebGL uit: de tip met de uitleg voor LibreWolf; na OK niet meer', (tester) async {
    final db = UserDb(sqlite3.openInMemory());
    await show(tester, db, accelerated: false);
    expect(find.textContaining('graphics acceleration turned off'), findsOneWidget);
    expect(find.textContaining('webgl.disabled = false'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('webgl-tip-ok')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('webgl-tip')), findsNothing);
    // Volgende keer (zelfde browser): niet opnieuw, en de keuze blijft op dit toestel
    await show(tester, db, accelerated: false);
    expect(find.byKey(const ValueKey('webgl-tip')), findsNothing);
    expect(UserDb.isLocalSetting('_webgl_tip'), isTrue);
  });

  testWidgets('WebGL aan (of de app op Android/desktop): geen tip', (tester) async {
    await show(tester, UserDb(sqlite3.openInMemory()), accelerated: true);
    expect(find.byKey(const ValueKey('webgl-tip')), findsNothing);
  });
}
