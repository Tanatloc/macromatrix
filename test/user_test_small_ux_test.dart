import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/ui/screens/add_food_screen.dart';
import 'package:macromatrix/ui/screens/body_screen.dart';
import 'package:macromatrix/ui/screens/dashboard_screen.dart';
import 'package:macromatrix/ui/screens/food_detail_screen.dart';
import 'package:macromatrix/ui/screens/profile_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/level_card.dart';

/// Kleine bevindingen uit de gebruikerstest: N37, N38, N41, N47, N54, N83, N87.
void main() {
  late FoodDb foods;
  late AppState s;
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });
  setUp(() {
    foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));
    s = AppState(foods: foods, user: UserDb(sqlite3.openInMemory()));
  });

  Widget app(Widget home) => ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
  );

  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('N41 Aanpassen bij een ongewoon gewicht houdt het meetvenster open', (tester) async {
    tall(tester);
    s.addBiometric('weight', 80);
    await tester.pumpWidget(app(const BodyScreen()));
    await tester.pump();
    await tester.tap(find.text('Measurement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '94.3');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Is this right?'), findsOneWidget);
    await tester.tap(find.text('Change it'));
    await tester.pumpAndSettle();
    // Terug in het formulier, met het getal geselecteerd om over te typen
    expect(find.text('Add measurement'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.selection, const TextSelection(baseOffset: 0, extentOffset: 4));
    expect(s.biometrics, hasLength(1));
    await tester.enterText(find.byType(TextField).first, '81');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Add measurement'), findsNothing);
    expect(s.biometrics, hasLength(2));
  });

  testWidgets('N38 + › Gewicht opent meteen het invulvenster; vasten staat onderaan voor wie niet vast', (tester) async {
    tall(tester);
    await tester.pumpWidget(app(const BodyScreen(addWeight: true)));
    await tester.pumpAndSettle();
    expect(find.text('Add measurement'), findsOneWidget);
    expect(find.text('Weight (kg)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    final fasting = tester.getTopLeft(find.text('Fasting')).dy;
    expect(fasting, greaterThan(tester.getTopLeft(find.text('Measurements on this day')).dy));
    // Bezig met vasten: de kaart staat weer bovenaan
    s.startFast(16);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.textContaining('Fasting:')).dy,
      lessThan(tester.getTopLeft(find.text('Measurements on this day')).dy),
    );
  });

  testWidgets('N47 de kop van Eten toevoegen kiest de maaltijd', (tester) async {
    await tester.pumpWidget(app(const AddFoodScreen(meal: Meal.lunch)));
    await tester.pump();
    await tester.tap(find.byTooltip('Choose meal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dinner').last);
    await tester.pumpAndSettle();
    expect(find.text('Dinner'), findsOneWidget);
    expect(find.text('Lunch'), findsNothing);
  });

  testWidgets('N54 wat je net at staat bovenaan Recent gebruikt', (tester) async {
    tall(tester);
    final oats = foods.search('oats', limit: 1).first;
    final banana = foods.search('banana', limit: 1).first;
    s.shiftDay(-1);
    for (var i = 0; i < 4; i++) {
      s.addFood(oats, meal: Meal.breakfast, grams: 60, quantity: 60);
    }
    s.shiftDay(1);
    s.addFood(banana, meal: Meal.snacks, grams: 120, quantity: 120);
    await tester.pumpWidget(app(const AddFoodScreen(meal: Meal.lunch)));
    await tester.pump();
    expect(tester.getTopLeft(find.text(banana.name)).dy, lessThan(tester.getTopLeft(find.text(oats.name)).dy));
  });

  testWidgets('N87 vaste kop toont naam en hoeveelheid na scrollen', (tester) async {
    final apple = foods.search('apple', limit: 1).first;
    await tester.pumpWidget(app(FoodDetailScreen(food: apple, meal: Meal.snacks)));
    await tester.pump();
    final header = find.textContaining('${apple.name} · ');
    expect(header, findsOneWidget);
    double opacity() => tester.widget<AnimatedOpacity>(find.ancestor(of: header, matching: find.byType(AnimatedOpacity)).first).opacity;
    expect(opacity(), 0);
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('N83 Doelen als apart scherm met terugpijl', (tester) async {
    await tester.pumpWidget(app(const ProfileScreen(goalsOnly: true)));
    await tester.pump();
    expect(find.text('Goals'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byType(LevelCard), findsNothing);
  });

  testWidgets('N83 dashboard begint bovenaan als je terugkomt', (tester) async {
    // Laag venster, zodat er zeker iets te scrollen valt
    tester.view.physicalSize = const Size(412, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var active = true;
    late StateSetter set;
    await tester.pumpWidget(
      app(
        StatefulBuilder(
          builder: (context, setState) {
            set = setState;
            return DashboardScreen(active: active);
          },
        ),
      ),
    );
    await tester.pump();
    final list = find.byWidgetPredicate((w) => w is ListView && w.controller != null);
    final scroll = tester.widget<ListView>(list).controller!.position;
    scroll.jumpTo(200);
    await tester.pump();
    expect(scroll.pixels, greaterThan(0));
    set(() => active = false);
    await tester.pump();
    set(() => active = true);
    await tester.pump();
    expect(scroll.pixels, 0);
  });

  testWidgets('N37 Over jou staat bovenaan het Profiel', (tester) async {
    tall(tester);
    final account = Account(s.user, onRemoteChanges: s.reloadFromDisk);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider.value(value: account),
          ChangeNotifierProvider(create: (_) => Friends(s, account)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const ProfileScreen()),
      ),
    );
    await tester.pump();
    expect(find.text('About you'), findsOneWidget);
    expect(tester.getTopLeft(find.text('About you')).dy, lessThan(tester.getTopLeft(find.byType(LevelCard)).dy));
  });
}
