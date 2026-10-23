/// Biobeschikbaarheid: hoeveel je lichaam echt opneemt hangt af van combinaties. Deze regels kijken per maaltijd
/// (en per dag) naar wat je at en geven een tip of een pluim.
///
/// Bronnen (samengevat): EFSA-adviezen over ijzer en calcium; Hallberg & Hulthén 2000 (vitamine C en thee/koffie bij
/// non-heemijzer); Heaney 2001 (calcium-opname per portie); Weaver 1999 (oxalaat in spinazie); Gibson 2006
/// (fytaat en zink). Geen medisch advies.
library;

import '../data/user_db.dart';
import '../i18n.dart';
import 'targets.dart';
import 'values.dart';

enum TipKind { warn, good }

class BioTip {
  const BioTip(this.kind, this.title, this.text, {this.meal, this.meals = const [], this.weight = 1});
  final TipKind kind;
  final String title, text;
  final Meal? meal;

  /// Alle maaltijden waarvoor deze tip geldt, na samenvoegen van dezelfde tip over meerdere maaltijden.
  final List<Meal> meals;

  /// Maaltijden van deze tip (leeg voor een dagtip).
  List<Meal> get allMeals => meals.isNotEmpty ? meals : [?meal];

  /// Bv. "Lunch" of "Breakfast, dinner", zodat tips van verschillende maaltijden niet tegenstrijdig lijken.
  String? get mealLabel {
    final ms = allMeals;
    if (ms.isEmpty) return null;
    final s = ms.map((m) => m.label.toLowerCase()).join(', ');
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Hoe belangrijk (hoger = eerst tonen).
  final double weight;
}

final _coffeeTea = RegExp(r'\b(coffee|espresso|cappuccino|latte|tea|koffie|thee|café|thé)\b', caseSensitive: false);
final _animalIron = RegExp(
  r'\b(beef|veal|lamb|pork|meat|liver|kidney|chicken|turkey|duck|fish|salmon|tuna|sardine|mackerel|herring|mussel|oyster|clam|shrimp|rund|varken|kip|vis|vlees|lever)\b',
  caseSensitive: false,
);
final _phytate = RegExp(
  r'\b(whole[- ]?(wheat|grain|meal)|bran|oat|oats|oatmeal|muesli|beans?|lentils?|chickpeas?|soy|soya|quinoa|rye|volkoren|havermout|bonen|linzen|kikkererwten)\b',
  caseSensitive: false,
);
final _sourdoughOrSoaked = RegExp(r'\b(sourdough|sprouted|desem|gekiemd|fermented)\b', caseSensitive: false);
final _spinach = RegExp(r'\b(spinach|spinazie|chard|rhubarb|snijbiet|rabarber)\b', caseSensitive: false);

double _sum(Iterable<DiaryEntry> es, String key) => es.fold(0.0, (a, e) => a + (withDerived(e.amounts)[key] ?? 0));

/// Tips voor een dag. [targets] voor de doelen (zink, calcium).
List<BioTip> bioTips(List<DiaryEntry> entries, Map<String, Target> targets) {
  final tips = <BioTip>[];
  final food = entries.where((e) => !e.foodRef.startsWith('supp:')).toList();
  if (food.isEmpty) return tips;

  for (final meal in Meal.values) {
    final m = food.where((e) => e.meal == meal).toList();
    if (m.isEmpty) continue;
    final iron = _sum(m, 'iron');
    final plantIron = _sum(m.where((e) => !_animalIron.hasMatch(e.name)), 'iron');
    final vitC = _sum(m, 'vit_c');
    final calcium = _sum(m, 'calcium');
    final fat = _sum(m, 'fat');
    final hasCoffeeTea = m.any((e) => _coffeeTea.hasMatch(e.name));
    final label = meal.label.toLowerCase();

    // Non-heemijzer en vitamine C
    if (plantIron >= 2 && !hasCoffeeTea) {
      if (vitC < 25) {
        tips.add(
          BioTip(
            TipKind.warn,
            tr('Add vitamin C for iron', 'Voeg vitamine C toe voor ijzer'),
            tr(
              'Your $label has ${fmt1(plantIron)} mg iron from plant foods but little vitamin C. A bell pepper, kiwi, orange or some lemon juice can increase iron absorption 2 to 3 times.',
              'Je $label bevat ${fmt1(plantIron)} mg ijzer uit plantaardige voeding maar weinig vitamine C. Een paprika, kiwi, sinaasappel of wat citroensap kan de ijzeropname 2 à 3 keer verhogen.',
            ),
            meal: meal,
            weight: 3,
          ),
        );
      } else {
        tips.add(
          BioTip(
            TipKind.good,
            tr('Iron + vitamin C', 'IJzer + vitamine C'),
            tr(
              'Good combination in your $label: the vitamin C helps you absorb the plant iron.',
              'Goede combinatie in je $label: de vitamine C helpt je het plantaardige ijzer op te nemen.',
            ),
            meal: meal,
          ),
        );
      }
    }
    // Koffie of thee bij een ijzerrijke maaltijd
    if (hasCoffeeTea && iron >= 2) {
      tips.add(
        BioTip(
          TipKind.warn,
          tr('Coffee or tea with iron', 'Koffie of thee bij ijzer'),
          tr(
            'Coffee and tea in your $label can reduce iron absorption by up to 60%. Drink them at least an hour before or after the meal.',
            'Koffie en thee bij je $label kunnen de ijzeropname tot 60% verminderen. Drink ze minstens een uur voor of na de maaltijd.',
          ),
          meal: meal,
          weight: 2.5,
        ),
      );
    }
    // Calcium en ijzer samen
    if (calcium >= 300 && iron >= 3) {
      tips.add(
        BioTip(
          TipKind.warn,
          tr('Calcium and iron together', 'Calcium en ijzer samen'),
          tr(
            'Your $label combines a lot of calcium (${calcium.round()} mg) with iron. Calcium hinders iron absorption; if you are low in iron, have dairy at a different meal.',
            'Je $label combineert veel calcium (${calcium.round()} mg) met ijzer. Calcium remt de ijzeropname; heb je weinig ijzer, eet zuivel dan bij een andere maaltijd.',
          ),
          meal: meal,
          weight: 1.5,
        ),
      );
    }
    // Te veel calcium in één keer
    if (calcium > 600) {
      tips.add(
        BioTip(
          TipKind.warn,
          tr('Spread your calcium', 'Spreid je calcium'),
          tr(
            'Your body absorbs calcium best in portions up to about 500 mg. Your $label has ${calcium.round()} mg; spread some of it over the day.',
            'Je lichaam neemt calcium het best op in porties tot ongeveer 500 mg. Je $label bevat ${calcium.round()} mg; spreid een deel over de dag.',
          ),
          meal: meal,
          weight: 1.2,
        ),
      );
    }
    // Vetoplosbare vitamines zonder vet
    final vitK = _sum(m, 'vit_k'), carotene = _sum(m, 'beta_carotene'), vitD = _sum(m, 'vit_d');
    if ((vitK >= 60 || carotene >= 2000 || vitD >= 5) && fat < 5) {
      tips.add(
        BioTip(
          TipKind.warn,
          tr('Add a little fat', 'Voeg wat vet toe'),
          tr(
            'Vitamins A, D, E and K need fat to be absorbed. Your $label has only ${fmt1(fat)} g fat: a drizzle of olive oil, some nuts or avocado helps.',
            'Vitamine A, D, E en K heb je vet nodig om ze op te nemen. Je $label heeft maar ${fmt1(fat)} g vet: een scheut olijfolie, wat noten of avocado helpt.',
          ),
          meal: meal,
          weight: 2,
        ),
      );
    }
  }

  // Calcium uit spinazie wordt slecht opgenomen (oxalaat)
  final calciumDay = _sum(food, 'calcium');
  final spinachCalcium = _sum(food.where((e) => _spinach.hasMatch(e.name)), 'calcium');
  if (calciumDay > 0 && spinachCalcium / calciumDay > 0.3) {
    tips.add(
      BioTip(
        TipKind.warn,
        tr('Calcium from spinach', 'Calcium uit spinazie'),
        tr(
          'A large share of today\'s calcium comes from spinach or chard. Their oxalate binds calcium, so only about 5% is absorbed. Count on dairy, tofu, kale or broccoli instead.',
          'Een groot deel van je calcium vandaag komt uit spinazie of snijbiet. Het oxalaat daarin bindt calcium, waardoor maar ongeveer 5% wordt opgenomen. Reken liever op zuivel, tofu, boerenkool of broccoli.',
        ),
        weight: 1.5,
      ),
    );
  }

  // Zink en fytaat
  final zincDay = _sum(food, 'zinc');
  final zincGoal = targets['zinc']?.goal;
  final phytateZinc = _sum(food.where((e) => _phytate.hasMatch(e.name) && !_sourdoughOrSoaked.hasMatch(e.name)), 'zinc');
  if (zincGoal != null && zincDay < zincGoal && zincDay > 0 && phytateZinc / zincDay > 0.5) {
    tips.add(
      BioTip(
        TipKind.warn,
        tr('Zinc and phytate', 'Zink en fytaat'),
        tr(
          'Most of your zinc comes from whole grains or legumes, whose phytate reduces absorption. Soaking or sprouting legumes and choosing sourdough bread helps.',
          'Het meeste zink komt uit volkoren of peulvruchten; het fytaat daarin vermindert de opname. Peulvruchten weken of laten kiemen en desembrood kiezen helpt.',
        ),
        weight: 1.3,
      ),
    );
  }

  final merged = _mergeSameTips(tips)..sort((a, b) => b.weight.compareTo(a.weight));
  return merged;
}

/// Dezelfde tip bij meerdere maaltijden wordt één tip met alle maaltijden, in plaats van identieke titels onder
/// elkaar. De uitleg per maaltijd blijft staan (die noemt telkens de maaltijd en de hoeveelheid).
List<BioTip> _mergeSameTips(List<BioTip> tips) {
  final groups = <(TipKind, String), List<BioTip>>{};
  for (final t in tips) {
    groups.putIfAbsent((t.kind, t.title), () => []).add(t);
  }
  return [
    for (final g in groups.values)
      if (g.length == 1)
        g.first
      else
        BioTip(
          g.first.kind,
          g.first.title,
          g.map((t) => t.text).toSet().join('\n\n'),
          meal: g.first.meal,
          meals: [for (final t in g) ...t.allMeals],
          weight: g.map((t) => t.weight).reduce((a, b) => a > b ? a : b),
        ),
  ];
}

String fmt1(double v) => fmtNum(v);
