import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/ai_request.dart';
import 'package:macromatrix/platform/label_scan.dart';
import 'package:macromatrix/platform/recipe_import.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/supporter_tracker.dart' show offSharedCount;
import 'package:macromatrix/ui/screens/custom_food_screen.dart';
import 'package:macromatrix/ui/screens/label_scan_screen.dart';
import 'package:macromatrix/ui/screens/recipe_import_screen.dart';
import 'package:macromatrix/ui/screens/recipe_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/ai_quota_note.dart';

/// Nagebootste server voor Pro met (of zonder) de AI-tellers.
class FakeAiRemote implements ProRemote, AiQuotaRemote {
  ProStatus status = const ProStatus();
  final Map<AiKind, PhotoQuota?> ai = {};
  bool aiMissing = false;

  @override
  Future<ProStatus> mine() async => status;

  @override
  Future<PhotoQuota?> quota() async => null;

  @override
  Future<void> showBadge(bool show) async {}

  @override
  Future<PhotoQuota?> aiQuota(AiKind kind) async {
    if (aiMissing) throw const AiQuotaMissing();
    return ai[kind];
  }
}

/// Een server zonder de AI-tellers (een oudere nabootsing of versie).
class PlainRemote implements ProRemote {
  @override
  Future<ProStatus> mine() async => const ProStatus();
  @override
  Future<PhotoQuota?> quota() async => null;
  @override
  Future<void> showBadge(bool show) async {}
}

final _foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));

AppState newState() => AppState(foods: _foods, user: UserDb(sqlite3.openInMemory()));

Pro newPro(AppState s, ProRemote server) => Pro(Account(s.user, onRemoteChanges: s.reloadFromDisk), remote: () => server);

PhotoQuota q(int used, int limit, {bool pro = false}) => PhotoQuota(used: used, limit: limit, pro: pro, day: utcDayKey(DateTime.now()));

Future<void> pump(WidgetTester tester, AppState s, Pro? pro, Widget home) async {
  tester.view.physicalSize = const Size(412, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: s),
        if (pro != null) ChangeNotifierProvider<Pro>.value(value: pro),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// Een scherm met een knop die [screen] opent en het resultaat bewaart.
class _Opener extends StatefulWidget {
  const _Opener(this.screen, this.onResult);
  final Widget screen;
  final void Function(Object?) onResult;
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async => widget.onResult(await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => widget.screen))),
        child: const Text('open'),
      ),
    ),
  );
}

const _labelJson = {
  'name': 'Granola',
  'brand': 'Acme',
  'basis': '100g',
  'from_portion': false,
  'portion_size': 45,
  'per100': {
    'energy_kcal': 454,
    'energy_kj': 1900,
    'fat': 18,
    'saturated_fat': 3,
    'carbohydrates': 60,
    'sugars': 20,
    'fiber': 7,
    'proteins': 9,
    'salt': 0.3,
    'sodium': 0.12,
  },
  'warnings': <String>[],
};

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  setUp(() {
    aiToken = (_) => 'tok';
    pickAiPhoto = (context, {required title}) async => Uint8List(2000);
  });

  group('Etiket naar het formulier', () {
    test('waarden per 100 g naar de sleutels van de app (natrium in mg)', () {
      final r = LabelResult.fromJson(_labelJson)!;
      final v = r.appPer100;
      expect(v['energy'], 454);
      expect(v['sfa'], 3);
      expect(v['carbs'], 60);
      expect(v['protein'], 9);
      expect(v['fiber'], 7);
      expect(v['sodium'], closeTo(120, 1e-9));
      final f = r.toFood(barcode: '5449000000996');
      expect(f.source, FoodSource.custom);
      expect(f.barcode, '5449000000996');
      expect(f.name, 'Granola');
      expect(f.brand, 'Acme');
      expect(f.portions.single.grams, 45);
    });

    test('alleen kJ of alleen zout: omgerekend', () {
      final r = LabelResult.fromJson({
        'basis': '100ml',
        'per100': {'energy_kj': 418.4, 'salt': 1.0, 'fat': 'x'},
      })!;
      expect(r.perMl, isTrue);
      expect(r.appPer100['energy'], closeTo(100, 1e-9));
      expect(r.appPer100['sodium'], closeTo(400, 1e-9));
      expect(r.appPer100.containsKey('fat'), isFalse);
      expect(LabelResult.fromJson({'name': 'x'}), isNull);
    });

    test('terug naar Open Food Facts: per 100 g, natrium en zout in g', () {
      final f = LabelResult.fromJson(_labelJson)!.toFood(barcode: '5449000000996');
      final n = offNutriments(f);
      expect(n['energy_kcal'], 454);
      expect(n['saturated_fat'], 3);
      expect(n['carbohydrates'], 60);
      expect(n['proteins'], 9);
      expect(n['sodium'], 0.12);
      expect(n['salt'], 0.3);
    });

    test('uitleg: per portie omgerekend en per 100 ml', () {
      final t = labelNotice(LabelResult(fromPortion: true, perMl: true, per100: const {}, warnings: const ['dropped_sugars']));
      expect(t, contains('per serving'));
      expect(t, contains('100 ml'));
      expect(t, contains('left empty'));
    });

    testWidgets('het formulier opent ingevuld en bewaart een eigen product met de barcode', (tester) async {
      final s = newState();
      final r = LabelResult.fromJson(_labelJson)!;
      Object? result;
      await pump(
        tester,
        s,
        null,
        _Opener(CustomFoodScreen(prefill: r.toFood(barcode: '5449000000996'), notice: labelNotice(r)), (v) => result = v),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Own product'), findsOneWidget);
      expect(find.byKey(const ValueKey('custom-food-notice')), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Granola'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '454'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '0.3'), findsOneWidget);
      // Geen verwijderknop: het is nog geen bestaand product
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final saved = result as Food;
      expect(saved.ref, startsWith('custom:'));
      expect(saved.barcode, '5449000000996');
      expect(saved.per100g['sodium'], closeTo(120, 1e-6));
      expect(s.user.customFoods().single.name, 'Granola');
    });
  });

  group('Etiket scannen', () {
    testWidgets('lezen, nakijken, bewaren en delen met Open Food Facts', (tester) async {
      final s = newState();
      final server = FakeAiRemote()..ai[AiKind.label] = q(0, 1);
      final pro = newPro(s, server);
      final shared = <http.BaseRequest>[];
      labelScan = LabelScan(MockClient((req) async => jsonResponse({..._labelJson, 'quota': {'used': 1, 'limit': 1, 'pro': false}})));
      offContribute = OffContribute(
        MockClient((req) async {
          if (req.method == 'GET') return jsonResponse({'configured': true});
          shared.add(req);
          return jsonResponse({'ok': true, 'images': 1});
        }),
      );
      Object? result;
      await pump(tester, s, pro, _Opener(const LabelScanScreen(barcode: '5449000000996'), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ai-quota-left')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-read')));
      await tester.pumpAndSettle();
      // Het formulier, ingevuld
      expect(find.widgetWithText(TextFormField, 'Granola'), findsOneWidget);
      expect(pro.aiQuota(AiKind.label)!.allowed, isFalse);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Share this product with Open Food Facts so others can find it?'), findsOneWidget);
      expect(find.textContaining('ODbL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('off-share-yes')));
      await tester.pumpAndSettle();
      expect(shared, hasLength(1));
      expect(offSharedCount(s.user), 1);
      expect((result as Food).name, 'Granola');
      expect(s.user.customFoods(), hasLength(1));
    });

    testWidgets('Open Food Facts niet ingesteld (not_configured): geen vraag, product wel bewaard', (tester) async {
      final s = newState();
      labelScan = LabelScan(MockClient((req) async => jsonResponse(_labelJson)));
      offContribute = OffContribute(MockClient((req) async => jsonResponse({'configured': false})));
      Object? result;
      await pump(tester, s, null, _Opener(const LabelScanScreen(barcode: '5449000000996'), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-read')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Open Food Facts so others'), findsNothing);
      expect(result, isA<Food>());
    });

    test('not_configured bij het delen: daarna niet meer gevraagd', () async {
      final c = OffContribute(
        MockClient((req) async => req.method == 'GET' ? jsonResponse({'configured': true}) : jsonResponse({'error': 'not_configured'}, 503)),
      );
      expect(await c.configured(), isTrue);
      final f = LabelResult.fromJson(_labelJson)!.toFood(barcode: '5449000000996');
      await expectLater(c.share(f, label: null, token: 't'), throwsA(isA<AiException>().having((e) => e.code, 'code', 'not_configured')));
      expect(await c.configured(), isFalse);
      // Een storing bij de vraag: niet tonen
      expect(await OffContribute(MockClient((req) async => http.Response('oops', 500))).configured(), isFalse);
    });

    testWidgets('gratis scan van vandaag op: uitleg met Pro, en de knop staat uit', (tester) async {
      final s = newState();
      final server = FakeAiRemote()..ai[AiKind.label] = q(1, 1);
      final pro = newPro(s, server);
      await pump(tester, s, pro, const LabelScanScreen(barcode: '5449000000996'));
      expect(find.text('Free label scan used today, back tomorrow, or become a supporter.'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-quota-pro-label')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('label-read'))).onPressed, isNull);
    });

    testWidgets('migratie ontbreekt: geen teller, scannen werkt gewoon', (tester) async {
      final s = newState();
      final server = FakeAiRemote()..aiMissing = true;
      final pro = newPro(s, server);
      labelScan = LabelScan(MockClient((req) async => jsonResponse(_labelJson)));
      offContribute = OffContribute(MockClient((req) async => jsonResponse({'configured': false})));
      await pump(tester, s, pro, const LabelScanScreen(barcode: '5449000000996'));
      expect(pro.aiAvailable, isFalse);
      expect(find.byKey(const ValueKey('ai-quota-left')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-read')));
      await tester.pumpAndSettle();
      expect(find.text('Own product'), findsOneWidget);
    });

    testWidgets('quota-antwoord van de server: stand onthouden, de uitleg in beeld', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeAiRemote());
      labelScan = LabelScan(MockClient((req) async => jsonResponse({'error': 'quota', 'used': 1, 'limit': 1, 'pro': false}, 429)));
      await pump(tester, s, pro, const LabelScanScreen(barcode: '5449000000996'));
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-read')));
      await tester.pumpAndSettle();
      expect(pro.aiQuota(AiKind.label)!.used, 1);
      expect(find.text('Free label scan used today, back tomorrow, or become a supporter.'), findsOneWidget);
      expect(find.byKey(const ValueKey('label-error')), findsNothing);
    });

    testWidgets('etiket onleesbaar: een duidelijke melding', (tester) async {
      final s = newState();
      labelScan = LabelScan(MockClient((req) async => jsonResponse({'error': 'no_per100'}, 422)));
      await pump(tester, s, null, const LabelScanScreen(barcode: '5449000000996'));
      await tester.tap(find.byKey(const ValueKey('label-photo-table')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('label-read')));
      await tester.pumpAndSettle();
      expect(find.textContaining('only shows values per serving'), findsOneWidget);
    });
  });

  group('Pro-dienst: AI-tellers', () {
    test('grenzen, debug-Pro en een server zonder tellers', () async {
      final s = newState();
      final server = FakeAiRemote()
        ..ai[AiKind.label] = q(1, 1)
        ..ai[AiKind.recipe] = q(0, 0);
      final pro = newPro(s, server);
      await pro.refreshAiQuota(AiKind.label);
      await pro.refreshAiQuota(AiKind.recipe);
      expect(pro.canUse(AiKind.label), isFalse);
      expect(pro.canUse(AiKind.recipe), isFalse);
      // Debug-Pro: de grenzen van Pro, en recepten importeren kan
      pro.setDebugPro(true);
      expect(pro.aiQuota(AiKind.label)!.limit, AiKind.label.pro);
      expect(pro.canUse(AiKind.label), isTrue);
      expect(pro.aiQuota(AiKind.recipe)!.limit, 20);
      expect(pro.canUse(AiKind.recipe), isTrue);
      pro.setDebugPro(null);
      expect(pro.canUse(AiKind.recipe), isFalse);

      // Een server zonder AI-tellers: niets gevraagd, etiket mag (de server beslist)
      final plain = newPro(newState(), PlainRemote());
      await plain.refreshAiQuota(AiKind.label);
      expect(plain.aiQuota(AiKind.label), isNull);
      expect(plain.canUse(AiKind.label), isTrue);
      expect(plain.canUse(AiKind.recipe), isFalse);

      // Migratie ontbreekt
      final missing = newPro(newState(), FakeAiRemote()..aiMissing = true);
      await missing.refreshAiQuota(AiKind.recipe);
      expect(missing.aiAvailable, isFalse);
      expect(AiKind.recipe.proOnly, isTrue);
      expect(AiKind.label.limitFor(false), 1);
    });

    testWidgets('AiQuotaNote: alle standen', (tester) async {
      Future<void> show(Widget w) => tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: Scaffold(body: w)));
      await show(AiQuotaNote(kind: AiKind.label, quota: q(1, 1), pro: false));
      expect(find.text('Free label scan used today, back tomorrow, or become a supporter.'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-quota-pro-label')), findsOneWidget);
      await show(AiQuotaNote(kind: AiKind.label, quota: q(0, 1), pro: false));
      expect(find.text('1 of 1 free label scan left today'), findsOneWidget);
      await show(AiQuotaNote(kind: AiKind.label, quota: q(30, 30, pro: true), pro: true));
      expect(find.textContaining('30 label scans today'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-quota-pro-label')), findsNothing);
      await show(AiQuotaNote(kind: AiKind.label, quota: q(3, 30, pro: true), pro: true));
      expect(find.byType(Container), findsNothing);
      await show(const AiQuotaNote(kind: AiKind.recipe, quota: null, pro: false));
      expect(find.textContaining('is for supporters'), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-quota-pro-recipe')), findsOneWidget);
      await show(const AiQuotaNote(kind: AiKind.recipe, quota: null, pro: true));
      expect(find.textContaining('is for supporters'), findsNothing);
    });
  });

  group('Recept importeren', () {
    test('regels opkuisen voor de parser', () {
      expect(cleanRecipeLine('1 ½ cups flour, sifted'), '1.5 cups flour');
      expect(cleanRecipeLine('1 1/2 tbsp olive oil'), '1.5 tbsp olive oil');
      expect(cleanRecipeLine('3/4 cup milk'), '0.75 cup milk');
      expect(cleanRecipeLine('8 oz cheddar (grated)'), '227 g cheddar');
      expect(cleanRecipeLine('1 lb minced beef'), '454 g minced beef');
      expect(cleanRecipeLine('1 (400 g) can chopped tomatoes'), '400 g chopped tomatoes');
      expect(cleanRecipeLine('salt, to taste'), 'salt');
      expect(cleanRecipeLine('2-3 carrots'), '2 carrots');
      expect(cleanRecipeLine('• 200 g butter or margarine'), '200 g butter');
      expect(cleanRecipeLine('1,5 kg potatoes'), '1,5 kg potatoes');
    });

    test('RecipeDraft uit het antwoord van de server', () {
      final d = RecipeDraft.fromJson({
        'name': ' Soup ',
        'servings': 4,
        'ingredients': ['800 g tomatoes', '', 3],
        'source': 'jsonld',
      })!;
      expect(d.name, 'Soup');
      expect(d.servings, 4);
      expect(d.ingredients, ['800 g tomatoes']);
      expect(RecipeDraft.fromJson({'ingredients': []}), isNull);
    });

    test('regels opzoeken zoals Snel loggen', () {
      final s = newState();
      final rows = recipeRows(['200 g flour', '2 eggs', 'salt and pepper', '(optional)'], s.resolveQuick);
      // Eén regel = hoogstens één rij (SU-1): "salt and pepper" is één regel, "(optional)" geen ingrediënt
      expect(rows, hasLength(3));
      expect(rows[0].ready, isTrue);
      expect(rows[0].template!.grams, 200);
      expect(rows[1].line!.item.count, 2);
      expect(rows[1].template!.grams, greaterThan(60));
      expect(rows[2].text, 'salt and pepper');
      // Naar smaak zonder hoeveelheid: staat er, telt niet mee
      expect(rows[2].counted, isFalse);
      expect(rows[2].ready, isFalse);
    });

    testWidgets('link → nakijken → recept met porties ingevuld', (tester) async {
      final s = newState();
      final server = FakeAiRemote()
        ..status = ProStatus(until: DateTime.now().add(const Duration(days: 30)))
        ..ai[AiKind.recipe] = q(0, 20, pro: true);
      final pro = newPro(s, server);
      await pro.refresh();
      String? sentUrl;
      recipeImport = RecipeImport(
        MockClient((req) async {
          sentUrl = (jsonDecode(req.body) as Map)['url'] as String;
          return jsonResponse({
            'name': 'Pancakes',
            'servings': 4,
            'ingredients': ['200 g flour', '2 eggs', '300 ml milk'],
            'source': 'jsonld',
            'quota': {'allowed': true, 'used': 1, 'limit': 20, 'pro': true},
          });
        }),
      );
      Object? result;
      await pump(tester, s, pro, _Opener(const RecipeImportScreen(), (v) => result = v));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('recipe-url')), 'example.com/pancakes');
      await tester.tap(find.byKey(const ValueKey('recipe-from-link')));
      await tester.pumpAndSettle();
      expect(sentUrl, 'https://example.com/pancakes');
      expect(pro.aiQuota(AiKind.recipe)!.used, 1);
      expect(find.text('Check the ingredients'), findsOneWidget);
      expect(find.text('"300 ml milk"'), findsOneWidget);
      // Het totaal per portie staat er al vóór het bewaren, en verandert mee met het aantal porties
      final totals = find.byKey(const ValueKey('recipe-import-totals'));
      expect(totals, findsOneWidget);
      String perServing() => tester.widget<Text>(find.descendant(of: totals, matching: find.textContaining('kcal')).first).data!;
      final four = perServing();
      await tester.enterText(find.byKey(const ValueKey('recipe-import-servings')), '2');
      await tester.pumpAndSettle();
      expect(perServing(), isNot(four));
      await tester.enterText(find.byKey(const ValueKey('recipe-import-servings')), '4');
      await tester.pumpAndSettle();
      expect(perServing(), four);
      // Eén regel weghalen
      await tester.tap(find.descendant(of: find.byKey(const ValueKey('recipe-row-2')), matching: find.byIcon(Icons.close_rounded)));
      await tester.pumpAndSettle();
      expect(find.text('"300 ml milk"'), findsNothing);
      expect(find.text('Make recipe with 2 ingredients'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recipe-import-create')));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeScreen), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Pancakes'), findsOneWidget);
      expect(find.widgetWithText(TextField, '4'), findsOneWidget);
      await tester.tap(find.text('Save recipe'));
      await tester.pumpAndSettle();
      final saved = s.recipes().single;
      expect(saved.name, 'Pancakes');
      expect(saved.servings, 4);
      expect(saved.ingredients, hasLength(2));
      expect(result, isA<Food>());
    });

    testWidgets('nakijken: twijfel gemarkeerd, serveersuggestie telt pas mee na Meetellen (SU-1)', (tester) async {
      final s = newState();
      final server = FakeAiRemote()
        ..status = ProStatus(until: DateTime.now().add(const Duration(days: 30)))
        ..ai[AiKind.recipe] = q(0, 20, pro: true);
      final pro = newPro(s, server);
      await pro.refresh();
      recipeImport = RecipeImport(
        MockClient(
          (req) async => jsonResponse({
            'name': 'Soup',
            'servings': 2,
            'ingredients': ['400 g carrots', '1 pack zzqx blorp', 'crusty bread to serve (optional)'],
            'source': 'jsonld',
            'quota': {'allowed': true, 'used': 1, 'limit': 20, 'pro': true},
          }),
        ),
      );
      await pump(tester, s, pro, const RecipeImportScreen());
      await tester.enterText(find.byKey(const ValueKey('recipe-url')), 'example.com/soup');
      await tester.tap(find.byKey(const ValueKey('recipe-from-link')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-check-0')), findsNothing);
      expect(find.byKey(const ValueKey('recipe-check-1')), findsOneWidget);
      expect(find.text('1 line to check: it is marked below.'), findsNWidgets(2));
      expect(find.text('Not counted: served on the side'), findsOneWidget);
      // De twijfelregel telt mee (zichtbaar in het totaal) maar staat gemarkeerd; het brood nog niet
      expect(find.text('Make recipe with 2 ingredients'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recipe-count-2')));
      await tester.pumpAndSettle();
      expect(find.text('Not counted: served on the side'), findsNothing);
      expect(find.text('Make recipe with 3 ingredients'), findsOneWidget);
    });

    testWidgets('zonder Pro: de uitleg met de Pro-knop, en de knoppen staan uit', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeAiRemote());
      await pump(tester, s, pro, const RecipeImportScreen());
      expect(find.byKey(const ValueKey('ai-quota-pro-recipe')), findsOneWidget);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('recipe-from-link'))).onPressed, isNull);
      expect(tester.widget<ButtonStyleButton>(find.byKey(const ValueKey('recipe-from-photo'))).onPressed, isNull);
    });

    testWidgets('debug-Pro maakt het lokaal vrij; pro_required van de server (migratie ontbreekt) netjes gemeld', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeAiRemote()..aiMissing = true);
      pro.setDebugPro(true);
      recipeImport = RecipeImport(MockClient((req) async => jsonResponse({'error': 'pro_required'}, 403)));
      await pump(tester, s, pro, const RecipeImportScreen());
      expect(find.byKey(const ValueKey('ai-quota-pro-recipe')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('recipe-from-photo')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('recipe-import-error')), findsOneWidget);
      expect(find.textContaining("couldn't confirm that this account is a supporter"), findsOneWidget);
    });

    testWidgets('het receptscherm heeft een knop Importeren', (tester) async {
      final s = newState();
      await pump(tester, s, null, const RecipeScreen());
      expect(find.byKey(const ValueKey('recipe-import')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('recipe-import')));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeImportScreen), findsOneWidget);
    });
  });
}
