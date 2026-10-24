import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/nutrition/recipe_line.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/screens/recipe_import_screen.dart';

/// SU-1: een recept importeren leest elke ingrediëntregel als hoeveelheid + product + notities en zoekt het product
/// met de zoeker van Snel loggen, met de echte databank. Eén regel = hoogstens één ingrediënt.

/// BBC Good Food, "Best spaghetti bolognese" (6 porties): de 20 regels zoals de JSON-LD ze geeft, zonder komma's.
const bolognese = [
  '1 tbsp olive oil',
  '4 rashers smoked streaky bacon finely chopped',
  '2 medium onions finely chopped',
  '2 carrots trimmed and finely chopped',
  '2 celery sticks finely chopped',
  '2 garlic cloves finely chopped',
  '2-3 sprigs rosemary leaves picked and finely chopped',
  '500g beef mince',
  '2 x 400g tins plum tomatoes',
  'small pack basil leaves picked, ¾ finely chopped and the rest left whole for garnish',
  '1 tsp dried oregano',
  '2 fresh bay leaves',
  '2 tbsp tomato purée',
  '1 beef stock cube',
  '1 red chilli deseeded and finely chopped (optional)',
  '125ml red wine',
  '6 cherry tomatoes sliced in half',
  '75g parmesan grated, plus extra to serve',
  '400g spaghetti',
  'crusty bread to serve (optional)',
];

/// Een eenvoudige kipcurry (4 porties).
const curry = [
  '2 tbsp sunflower oil',
  '1 onion, finely chopped',
  '3 garlic cloves, crushed',
  'thumb-sized piece of ginger, grated',
  '6 boneless, skinless chicken thighs, cut into chunks',
  '2 tbsp curry powder',
  '1 tsp ground cumin',
  '1 tsp turmeric',
  '1 tin (400 g) chopped tomatoes',
  '400ml can coconut milk',
  '200g basmati rice',
  'small bunch coriander, chopped',
  'salt and pepper, to taste',
  '1 lime, juiced (optional)',
];

/// Griekse salade (4 porties).
const greekSalad = [
  '4 large vine tomatoes, cut into chunks',
  '1 cucumber, peeled, deseeded and chopped',
  '½ red onion, thinly sliced',
  '16 kalamata olives',
  '1 tsp dried oregano',
  '85g feta cheese, cut into chunks',
  '4 tbsp extra virgin olive oil',
  '1 tbsp red wine vinegar',
  'a pinch of salt',
  'freshly ground black pepper',
];

void main() {
  final s = AppState(
    foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
    user: UserDb(sqlite3.openInMemory()),
  );

  String name(RecipeImportRow r) => (r.template?.name ?? r.line?.food.name ?? '').toLowerCase();
  double grams(RecipeImportRow r) => r.template?.grams ?? 0;
  RecipeImportRow row(List<RecipeImportRow> rows, String text) => rows.firstWhere((r) => r.text.startsWith(text));

  group('regels lezen', () {
    test('hoeveelheid, eenheid, product en notities', () {
      final a = parseRecipeLine('2 carrots trimmed and finely chopped')!;
      expect(a.food, 'carrots');
      expect(a.count, 2);
      expect(a.notes.join(' '), contains('finely chopped'));

      final b = parseRecipeLine('2 x 400g tins plum tomatoes')!;
      expect(b.grams, 800);
      expect(b.canned, isTrue);

      final c = parseRecipeLine('1 tin (400 g) chopped tomatoes')!;
      expect(c.grams, 400);
      expect(c.canned, isTrue);
      expect(c.food, 'tomatoes');

      final d = parseRecipeLine('1 ½ tbsp olive oil')!;
      expect(d.count, 1.5);
      expect(d.unit, 'tbsp');

      final e = parseRecipeLine('3/4 cup milk')!;
      expect(e.count, 0.75);
      expect(e.unit, 'cup');

      final f = parseRecipeLine('2-3 sprigs rosemary')!;
      expect(f.count, 2.5);
      expect(f.unit, 'sprig');

      final g = parseRecipeLine('a pinch of salt')!;
      expect(g.unit, 'pinch');
      expect(g.food, 'salt');

      final h = parseRecipeLine('400 g dried spaghetti')!;
      expect(h.grams, 400);
      expect(h.dried, isTrue);

      final i = parseRecipeLine('crusty bread to serve (optional)')!;
      expect(i.food, 'crusty bread');
      expect(i.optional, isTrue);
      expect(i.toServe, isTrue);

      final j = parseRecipeLine('8 oz cheddar (grated)')!;
      expect(j.grams, closeTo(226.8, 0.1));
      expect(j.food, 'cheddar');

      final k = parseRecipeLine('2 garlic cloves finely chopped')!;
      expect(k.food, 'garlic');
      expect(k.unit, 'clove');

      final l = parseRecipeLine('6 boneless, skinless chicken thighs, cut into chunks')!;
      expect(l.food, 'chicken thighs');
      expect(l.count, 6);
    });

    test('kopjes en lege regels zijn geen ingrediënt', () {
      expect(parseRecipeLine('For the bolognese sauce'), isNull);
      expect(parseRecipeLine('To serve:'), isNull);
      expect(parseRecipeLine('To season'), isNull);
      expect(parseRecipeLine('  '), isNull);
    });

    test('"salt and pepper" en "finely chopped" geven nooit een extra regel', () {
      final rows = recipeRows(['salt and pepper', '2 onions, finely chopped', '1 carrot and 1 celery stick, finely chopped'], s.resolveQuick);
      expect(rows, hasLength(3));
      expect(rows.where((r) => name(r).contains('tetrapack') || name(r).contains('chopped')), isEmpty);
    });
  });

  group('BBC spaghetti bolognese (SU-1)', () {
    final rows = recipeRows(bolognese, s.resolveQuick);

    test('20 regels geven 20 ingrediënten, zonder verzonnen extra regels', () {
      expect(rows, hasLength(20));
      expect([for (final r in rows) r.text], bolognese);
    });

    test('zinnige treffers', () {
      expect(name(row(rows, '2 carrots')), allOf(contains('carrot'), contains('raw')));
      expect(name(row(rows, '2 medium onions')), allOf(contains('onion'), contains('raw'), isNot(contains('fried'))));
      expect(grams(row(rows, '2 medium onions')), inInclusiveRange(200, 400));
      expect(name(row(rows, '4 rashers')), contains('bacon'));
      expect(grams(row(rows, '4 rashers')), 100);
      expect(name(row(rows, '2 celery')), contains('celery'));
      expect(name(row(rows, '2 garlic')), contains('garlic'));
      expect(grams(row(rows, '2 garlic')), lessThan(20));
      expect(name(row(rows, '500g beef mince')), allOf(contains('beef'), contains('minc'), contains('raw')));

      final tinned = row(rows, '2 x 400g tins');
      expect(name(tinned), allOf(contains('tomato'), contains('canned')));
      expect(name(tinned), isNot(matches(RegExp(r'pur[ée]e|paste|juice|ravioli|pasta'))));
      expect(grams(tinned), 800);

      final cherry = row(rows, '6 cherry tomatoes');
      expect(name(cherry), allOf(contains('tomato'), contains('cherry')));
      expect(grams(cherry), inInclusiveRange(60, 150));

      final pasta = row(rows, '400g spaghetti');
      expect(name(pasta), allOf(contains('pasta'), matches(RegExp(r'\b(dry|dried|raw)\b')), isNot(contains('boiled'))));
      expect(pasta.template!.kcal, greaterThan(1200));

      expect(name(row(rows, '2 tbsp tomato purée')), contains('tomato'));
      expect(name(row(rows, '125ml red wine')), contains('wine'));
      expect(name(row(rows, '75g parmesan')), contains('parmesan'));
      expect(grams(row(rows, '75g parmesan')), 75);
    });

    test('kruiden: een paar gram', () {
      final basil = row(rows, 'small pack basil');
      expect(name(basil), contains('basil'));
      expect(grams(basil), lessThanOrEqualTo(30));
      expect(basil.template!.kcal, lessThan(15));
      final bay = row(rows, '2 fresh bay leaves');
      expect(grams(bay), lessThanOrEqualTo(2));
      expect(grams(row(rows, '2-3 sprigs rosemary')), lessThanOrEqualTo(5));
      expect(grams(row(rows, '1 tsp dried oregano')), lessThanOrEqualTo(3));
    });

    test('brood "to serve (optional)" telt niet mee, maar staat er wel', () {
      final bread = row(rows, 'crusty bread');
      expect(bread.counted, isFalse);
      expect(bread.ready, isFalse);
    });

    test('nergens een absurde treffer', () {
      for (final r in rows) {
        expect(name(r), isNot(matches(RegExp(r'pork|lamb|potato|ravioli|gherkin|sausage|rape|deep ?fried|tetrapack|duck'))), reason: r.text);
      }
    });

    test('per portie tussen 500 en 750 kcal (6 porties)', () {
      final per = recipeImportPerServing(rows, 6);
      expect(per.kcal, inInclusiveRange(500, 750));
      expect(per.protein, inInclusiveRange(20, 50));
    });

    test('geen regel om na te kijken bij een duidelijke lijst', () {
      expect([
        for (final r in rows)
          if (r.counted && r.check) r.text,
      ], isEmpty);
    });
  });

  group('kipcurry', () {
    final rows = recipeRows(curry, s.resolveQuick);

    test('één rij per regel, zinnige treffers', () {
      expect(rows, hasLength(curry.length));
      expect(name(row(rows, '6 boneless')), allOf(contains('chicken'), contains('thigh'), contains('raw')));
      expect(grams(row(rows, '6 boneless')), inInclusiveRange(450, 750));
      expect(name(row(rows, '1 tin (400 g)')), allOf(contains('tomato'), contains('canned')));
      expect(name(row(rows, '400ml can coconut')), contains('coconut milk'));
      final rice = row(rows, '200g basmati');
      expect(name(rice), allOf(contains('rice'), matches(RegExp(r'\b(dry|raw)\b'))));
      expect(name(row(rows, 'thumb-sized')), contains('ginger'));
      expect(grams(row(rows, 'thumb-sized')), lessThanOrEqualTo(30));
      expect(grams(row(rows, '2 tbsp curry powder')), lessThanOrEqualTo(20));
      expect(row(rows, 'salt and pepper').counted, isFalse);
    });

    test('per portie tussen 500 en 850 kcal (4 porties)', () {
      expect(recipeImportPerServing(rows, 4).kcal, inInclusiveRange(500, 850));
    });
  });

  group('Griekse salade', () {
    final rows = recipeRows(greekSalad, s.resolveQuick);

    test('één rij per regel, zinnige treffers', () {
      expect(rows, hasLength(greekSalad.length));
      expect(name(row(rows, '4 large vine')), allOf(contains('tomato'), contains('raw')));
      expect(name(row(rows, '1 cucumber')), contains('cucumber'));
      expect(name(row(rows, '½ red onion')), allOf(contains('onion'), contains('raw')));
      expect(grams(row(rows, '½ red onion')), inInclusiveRange(40, 120));
      expect(name(row(rows, '16 kalamata')), contains('olive'));
      expect(grams(row(rows, '16 kalamata')), inInclusiveRange(30, 120));
      expect(name(row(rows, '85g feta')), contains('feta'));
      expect(name(row(rows, '4 tbsp extra virgin')), contains('olive oil'));
      expect(grams(row(rows, 'a pinch of salt')), lessThan(2));
      expect(row(rows, 'freshly ground black pepper').counted, isFalse);
    });

    test('per portie tussen 150 en 400 kcal (4 porties)', () {
      expect(recipeImportPerServing(rows, 4).kcal, inInclusiveRange(150, 400));
    });
  });

  test('foto van een kookboekpagina: dezelfde regels, dezelfde treffers', () {
    // De server geeft bij een foto ook gewoon regels tekst: de app zoekt ze op dezelfde manier op
    final fromPhoto = recipeRows(['400 g dried spaghetti', '2 medium onions, finely chopped'], s.resolveQuick);
    expect(name(fromPhoto[0]), allOf(contains('pasta'), isNot(contains('boiled'))));
    expect(name(fromPhoto[1]), allOf(contains('onion'), contains('raw')));
  });

  test('niets gevonden of twijfel: gemarkeerd om na te kijken, niet stil iets absurds', () {
    final rows = recipeRows(['2 tbsp zzqx blorp', '1 pack mystery mix'], s.resolveQuick);
    expect(rows, hasLength(2));
    for (final r in rows) {
      expect(r.check, isTrue, reason: r.text);
    }
  });
}
