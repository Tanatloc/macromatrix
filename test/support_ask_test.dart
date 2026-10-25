// Vragen om Supporter te worden (lib/ui/widgets/support_ask.dart): alleen na 7 dagen op rij, hoogstens één keer
// per 30 dagen, nooit in de eerste 7 dagen op dit toestel, alleen als kopen kan, en nooit meer na "Niet meer vragen".
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/ui/widgets/support_ask.dart';

void main() {
  setUpAll(() => setAppLang(AppLang.en));
  final start = DateTime(2026, 11, 1, 12);
  DateTime day(int n) => start.add(Duration(days: n));

  UserDb fresh() {
    final db = UserDb(sqlite3.openInMemory());
    noteFirstUse(db, now: start);
    return db;
  }

  bool ask(UserDb db, int d, {int streak = 7, bool isPro = false, bool canBuy = true}) =>
      shouldAskSupport(db, streak: streak, isPro: isPro, canBuy: canBuy, now: day(d));

  test('niet in de eerste 7 dagen op dit toestel, ook niet met een lange reeks uit een import', () {
    final db = fresh();
    expect(ask(db, 0, streak: 120), isFalse);
    expect(ask(db, 6), isFalse);
    expect(ask(db, 7), isTrue);
  });

  test('alleen vanaf 7 dagen op rij, niet als supporter, niet als kopen hier niet kan', () {
    final db = fresh();
    expect(ask(db, 10, streak: 6), isFalse);
    expect(ask(db, 10, isPro: true), isFalse);
    expect(ask(db, 10, canBuy: false), isFalse);
    expect(ask(db, 10), isTrue);
  });

  test('zonder bewaard begin: eerst het begin onthouden, nog niet vragen', () {
    final db = UserDb(sqlite3.openInMemory());
    expect(shouldAskSupport(db, streak: 30, isPro: false, canBuy: true, now: day(0)), isFalse);
    expect(shouldAskSupport(db, streak: 30, isPro: false, canBuy: true, now: day(8)), isTrue);
  });

  testWidgets('gevraagd: dan 30 dagen niet; "Niet meer vragen" is voor altijd', (tester) async {
    final db = fresh();
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    askSupport(ctx, db, streak: 7, now: day(10));
    await tester.pumpAndSettle();
    expect(find.text('7 days in a row!'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('support-ask-later')));
    await tester.pumpAndSettle();
    expect(ask(db, 20), isFalse);
    expect(ask(db, 40), isTrue);
    askSupport(ctx, db, streak: 14, now: day(40));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('support-ask-never')));
    await tester.pumpAndSettle();
    expect(ask(db, 400), isFalse);
  });

  test('de instelling blijft op dit toestel (wordt niet gesynchroniseerd)', () {
    final db = fresh();
    expect([for (final t in UserDb.syncTables) ...db.dirtyRows(t)].where((r) => r['key'] == supportAskKey), isEmpty);
  });
}
