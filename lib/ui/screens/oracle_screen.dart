import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/values.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'food_detail_screen.dart';

/// Voedingsgroepen uit de ingebouwde databank, in een volgorde die je kent uit de winkel.
const oracleGroups = <(String, String, String)>[
  ('vegetable', 'Vegetables', 'Groenten'),
  ('fruit', 'Fruit', 'Fruit'),
  ('legume', 'Legumes', 'Peulvruchten'),
  ('nut/seed', 'Nuts and seeds', 'Noten en zaden'),
  ('cereal', 'Grains', 'Granen'),
  ('bread', 'Bread', 'Brood'),
  ('pasta', 'Pasta', 'Pasta'),
  ('rice', 'Rice', 'Rijst'),
  ('potato/tuber', 'Potatoes', 'Aardappelen'),
  ('breakfast cereal', 'Breakfast cereals', 'Ontbijtgranen'),
  ('dairy', 'Dairy', 'Zuivel'),
  ('egg', 'Eggs', 'Eieren'),
  ('meat', 'Meat', 'Vlees'),
  ('poultry', 'Poultry', 'Gevogelte'),
  ('offal', 'Offal', 'Orgaanvlees'),
  ('processed meat', 'Cold cuts', 'Vleeswaren'),
  ('fish', 'Fish', 'Vis'),
  ('shellfish', 'Shellfish', 'Schaal- en schelpdieren'),
  ('soy product', 'Soy', 'Soja'),
  ('meat substitute', 'Meat substitutes', 'Vleesvervangers'),
  ('mushroom', 'Mushrooms', 'Paddenstoelen'),
  ('herb/spice', 'Herbs and spices', 'Kruiden'),
  ('oil/fat', 'Oils and fats', 'Oliën en vetten'),
  ('beverage', 'Drinks', 'Dranken'),
  ('dish', 'Dishes', 'Gerechten'),
  ('soup', 'Soups', 'Soepen'),
  ('bakery', 'Pastry', 'Gebak'),
  ('dessert', 'Desserts', 'Desserts'),
  ('snack', 'Snacks', 'Snacks'),
  ('sugar/sweets', 'Sweets', 'Snoep en suiker'),
  ('sauce/condiment', 'Sauces', 'Sauzen'),
];

/// Orakel: zoek de voedingsmiddelen die het rijkst zijn aan één voedingsstof, per 100 g, per 100 kcal of per portie,
/// eventueel alleen in bepaalde voedingsgroepen.
class OracleScreen extends StatefulWidget {
  const OracleScreen({super.key, this.nutrient = 'potassium'});
  final String nutrient;

  @override
  State<OracleScreen> createState() => _OracleScreenState();
}

class _OracleScreenState extends State<OracleScreen> {
  late String _key = nutrientByKey.containsKey(widget.nutrient) ? widget.nutrient : 'potassium';
  OracleRank _rank = OracleRank.per100g;
  int _limit = 25;
  final Set<String> _groups = {};
  bool _everyday = true;

  /// Alle stoffen uit de lijst (afgeleide stoffen staan ook in de databank of worden er in SQL uit berekend).
  static const _searchable = nutrients;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final n = nutrientByKey[_key]!;
    final results = s.oracle(_key, rank: _rank, limit: _limit, groups: _groups, everyday: _everyday);
    final goal = s.targets[_key]?.goal;
    final top = results.isEmpty ? 1.0 : results.first.$2;

    return Scaffold(
      appBar: AppBar(title: Text(tr('Ask the Oracle', 'Vraag het Orakel'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            maxWidth: isDesktop(context) ? wideMaxWidth : 760,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Find the foods richest in one nutrient. Your preferences and allergies are taken into account.',
                      'Zoek de voedingsmiddelen die het rijkst zijn aan één voedingsstof. Je voorkeuren en allergieën tellen mee.',
                    ),
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                  ),
                  const SizedBox(height: 12),
                  Panel(child: _controls(p)),
                  const SizedBox(height: 12),
                  Panel(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PanelTitle(
                          tr(
                            'Top ${results.length}: ${n.name.toLowerCase()} ${_rank.label}',
                            'Top ${results.length}: ${n.name.toLowerCase()} ${_rank.label}',
                          ),
                          subtitle: goal == null || goal <= 0
                              ? null
                              : tr(
                                  '% = share of your daily goal (${formatAmount(goal, n)} ${n.unit})',
                                  '% = deel van je dagdoel (${formatAmount(goal, n)} ${n.unit})',
                                ),
                        ),
                        const SizedBox(height: 6),
                        if (results.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Text(
                              tr(
                                'Nothing found. Choose more groups or turn off "Everyday foods only".',
                                'Niets gevonden. Kies meer groepen of zet "Alleen gewone voedingsmiddelen" uit.',
                              ),
                              style: TextStyle(color: p.ink2),
                            ),
                          ),
                        for (final (i, (f, v)) in results.indexed) _row(p, i + 1, f, v, top, n, goal),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls(Palette p) {
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.ink),
      ),
    );

    final nutrientField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(tr('Search nutrient', 'Voedingsstof')),
        DropdownButtonFormField<String>(
          initialValue: _key,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true),
          menuMaxHeight: 420,
          items: [
            for (final n in _searchable)
              DropdownMenuItem(
                value: n.key,
                child: Text('${n.name} (${n.unit})', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (k) => setState(() => _key = k ?? _key),
        ),
      ],
    );
    final rankField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(tr('Ranked by', 'Gerangschikt')),
        Segmented<OracleRank>(
          height: 36,
          items: [for (final r in OracleRank.values) (r, r.label)],
          selected: _rank,
          onChanged: (r) => setState(() => _rank = r),
        ),
      ],
    );
    final topField = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(tr('Show the top', 'Toon de top')),
        Segmented<int>(
          height: 36,
          items: const [(10, '10'), (25, '25'), (50, '50'), (100, '100')],
          selected: _limit,
          onChanged: (v) => setState(() => _limit = v),
        ),
      ],
    );
    final everyday = SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: _everyday,
      onChanged: (v) => setState(() => _everyday = v),
      title: Text(tr('Everyday foods only', 'Alleen gewone voedingsmiddelen'), style: const TextStyle(fontSize: 14)),
      subtitle: Text(
        tr('No raw meat, dried herbs, powders or rare products', 'Geen rauw vlees, gedroogde kruiden, poeders of zeldzame producten'),
        style: TextStyle(fontSize: 12, color: p.ink3),
      ),
    );
    final groups = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: label(tr('Food groups', 'Voedingsgroepen'))),
            if (_groups.isNotEmpty)
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                onPressed: () => setState(_groups.clear),
                child: Text(tr('All groups', 'Alle groepen')),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            PillChip(label: tr('All', 'Alles'), selected: _groups.isEmpty, height: 30, onTap: () => setState(_groups.clear)),
            for (final (g, en, nl) in oracleGroups)
              PillChip(
                label: tr(en, nl),
                selected: _groups.contains(g),
                check: true,
                height: 30,
                onTap: () => setState(() => _groups.contains(g) ? _groups.remove(g) : _groups.add(g)),
              ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        // Breed: links de keuzes en rechts de groepen
        if (c.maxWidth >= 760) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    nutrientField,
                    const SizedBox(height: 16),
                    rankField,
                    const SizedBox(height: 16),
                    topField,
                    const SizedBox(height: 8),
                    everyday,
                  ],
                ),
              ),
              const SizedBox(width: 28),
              Expanded(child: groups),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            nutrientField,
            const SizedBox(height: 14),
            rankField,
            const SizedBox(height: 14),
            topField,
            const SizedBox(height: 6),
            everyday,
            const SizedBox(height: 8),
            groups,
          ],
        );
      },
    );
  }

  Widget _row(Palette p, int rank, Food f, double v, double top, Nutrient n, double? goal) {
    final portion = _rank == OracleRank.perPortion ? AppState.oraclePortion(f) : null;
    final portionLabel = portion == null ? null : (f.portions.where((x) => x.grams == portion).firstOrNull?.label ?? '100 g');
    final kcal = f.per100g['energy'];
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FoodDetailScreen(food: f, meal: Meal.forHour(DateTime.now().hour)),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: Text(
                '$rank',
                style: numStyle(13, weight: FontWeight.w500, color: p.ink3),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SourceBadge(f.source),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: p.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: top <= 0 ? 0 : (v / top).clamp(0, 1),
                      minHeight: 5,
                      color: p.brand,
                      backgroundColor: p.track,
                    ),
                  ),
                  if (portionLabel != null || kcal != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        [?portionLabel, if (kcal != null) tr('${fmtInt(kcal)} kcal per 100 g', '${fmtInt(kcal)} kcal per 100 g')].join(' · '),
                        style: TextStyle(fontSize: 11.5, color: p.ink3),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 92,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${formatAmount(v, n)} ${n.unit}', style: numStyle(14, color: p.ink)),
                  if (goal != null && goal > 0)
                    Text(
                      fmtPct(v / goal),
                      style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
