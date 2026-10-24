import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/user_db.dart';
import '../../i18n.dart';
import '../../nutrition/nutrients.dart';
import '../../state/app_state.dart';
import '../../state/week_menu_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'shopping_screen.dart';

/// "Plan mijn week": een voorstel voor een paar dagen, gebaseerd op wat je zelf eet, met een paar gewone producten
/// die je gewone tekorten aanvullen. Je kunt regels omwisselen of weglaten en het daarna in de planner en op je
/// boodschappenlijst zetten.
class WeekMenuScreen extends StatefulWidget {
  const WeekMenuScreen({super.key, this.start});

  /// Eerste dag van het plan; standaard morgen.
  final DateTime? start;

  @override
  State<WeekMenuScreen> createState() => _WeekMenuScreenState();
}

class _WeekMenuScreenState extends State<WeekMenuScreen> {
  WeekMenuPlanner? _planner;
  WeekMenu? _menu;
  int _days = 7;
  int _seed = 0;
  Set<Meal> _meals = {...Meal.values};
  late DateTime _start;

  static DateTime get _today {
    final n = logicalNow();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    final s = widget.start;
    _start = s == null ? DateTime(_today.year, _today.month, _today.day + 1) : DateTime(s.year, s.month, s.day);
    // Eerst het scherm tonen, dan rekenen (het opzoeken van producten duurt even)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = context.read<AppState>();
      _planner = state.weekMenuPlanner();
      _meals = {...state.mealPattern().usual};
      _make();
    });
  }

  void _make() {
    final p = _planner;
    if (p == null || _meals.isEmpty) {
      setState(() => _menu = null);
      return;
    }
    setState(() => _menu = context.read<AppState>().proposeWeekMenu(p, start: _start, count: _days, meals: _meals, seed: _seed));
  }

  void _shuffle() {
    _seed++;
    _make();
  }

  static String _dayLabel(DateTime d) {
    final diff = daysBetween(_today, d);
    if (diff == 0) return tr('Today', 'Vandaag');
    if (diff == 1) return tr('Tomorrow', 'Morgen');
    final s = DateFormat('EEEE d MMMM', appLocale).format(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  static String _amount(MenuItem i) {
    final p = i.portion;
    if (p == null) return '${fmtInt(i.grams)} g';
    final q = i.quantity;
    return '${fmtNum(q)} × ${portionInLang(p.label)}';
  }

  static String _names(Iterable<String> keys) => [
    for (final k in keys)
      if (nutrientByKey[k] case final n?) inSentence(n.name),
  ].join(', ');

  Future<void> _use() async {
    final s = context.read<AppState>();
    final menu = _menu!;
    final overlap = menu.days.any((d) => s.planFor(dayKey(d.date)).any((x) => menu.meals.contains(x.meal)));
    if (overlap) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Replace your plan?', 'Je plan vervangen?')),
          content: Text(
            tr(
              'Some of these days already have planned meals. They will be replaced by this plan; other meals stay.',
              'Voor sommige dagen staan al maaltijden gepland. Die worden vervangen door dit plan; andere maaltijden blijven staan.',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Replace', 'Vervangen'))),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    s.useWeekMenu(menu);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('Plan saved for ${menu.days.length} days.', 'Plan bewaard voor ${menu.days.length} dagen.')),
        action: SnackBarAction(label: tr('Shopping list', 'Boodschappen'), onPressed: () => _toShopping(s, messenger)),
      ),
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  void _toShopping(AppState s, ScaffoldMessengerState messenger) {
    final n = s.shoppingFromMenu(_menu!);
    messenger.showSnackBar(
      SnackBar(
        content: Text(tr('$n products on your shopping list.', '$n producten op je boodschappenlijst.')),
        action: SnackBarAction(
          label: tr('Open', 'Openen'),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShoppingScreen())),
        ),
      ),
    );
  }

  Future<void> _swap(int day, int index) async {
    final planner = _planner!, menu = _menu!;
    final d = menu.days[day];
    final options = planner.alternatives(d, index, meals: menu.meals);
    final p = context.pal;
    final pick = await showModalBottomSheet<MenuItem>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                tr('Swap ${d.items[index].food.food.name}', '${d.items[index].food.food.name} omwisselen'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
              ),
            ),
            if (options.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('No other good options for this meal.', 'Geen andere goede keuzes voor deze maaltijd.'),
                  style: TextStyle(color: p.ink2),
                ),
              ),
            for (final o in options)
              ListTile(
                title: Text(o.food.food.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  [_amount(o), if (o.reasons.isNotEmpty) tr('for ${_names(o.reasons)}', 'voor ${_names(o.reasons)}')].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${fmtInt(o.kcal)} kcal',
                  style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
                ),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (pick == null || !mounted) return;
    setState(() => _menu = menu.withDay(day, planner.replace(d, index, pick)));
  }

  void _remove(int day, int index) {
    final menu = _menu!;
    setState(() => _menu = menu.withDay(day, _planner!.remove(menu.days[day], index)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final menu = _menu;
    final planner = _planner;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Plan my week', 'Plan mijn week')),
        actions: [
          if (planner != null) IconButton(tooltip: tr('Shuffle', 'Opnieuw schudden'), icon: const Icon(Icons.shuffle_rounded), onPressed: _shuffle),
        ],
      ),
      body: planner == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                            'A proposal built from what you usually eat, with a few everyday foods for nutrients you are often low in. Swap or remove anything, then use it.',
                            'Een voorstel op basis van wat je meestal eet, met een paar gewone producten voor stoffen waar je vaak te weinig van hebt. Wissel om of laat weg wat je wilt, en gebruik het dan.',
                          ),
                          style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                        ),
                        const SizedBox(height: 12),
                        _settings(p),
                        const SizedBox(height: 10),
                        if (menu == null)
                          Panel(
                            child: Text(
                              tr('Choose at least one meal to plan.', 'Kies minstens één maaltijd om te plannen.'),
                              style: TextStyle(color: p.ink2),
                            ),
                          )
                        else ...[
                          _summary(p, planner, menu),
                          const SizedBox(height: 10),
                          for (final (i, d) in menu.days.indexed) ...[_day(p, planner, i, d), const SizedBox(height: 10)],
                          Center(
                            child: TextButton.icon(
                              onPressed: _shuffle,
                              icon: const Icon(Icons.shuffle_rounded, size: 18),
                              label: Text(tr('Shuffle', 'Opnieuw schudden')),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
      // Altijd in beeld, ook onder een lange week
      bottomNavigationBar: menu == null
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: p.surface,
                  border: Border(top: BorderSide(color: p.line)),
                ),
                child: Narrow(
                  maxWidth: isDesktop(context) ? wideMaxWidth : 760,
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _use,
                          icon: const Icon(Icons.event_available_rounded, size: 18),
                          label: Text(tr('Use this plan', 'Dit plan gebruiken'), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _toShopping(context.read<AppState>(), ScaffoldMessenger.of(context)),
                          icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                          label: Text(tr('Shopping list', 'Boodschappen'), overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _settings(Palette p) {
    Widget label(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        t,
        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2),
      ),
    );
    final tomorrow = DateTime(_today.year, _today.month, _today.day + 1);
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label(tr('Days', 'Dagen')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final n in const [3, 5, 7])
                PillChip(
                  label: tr('$n days', '$n dagen'),
                  selected: _days == n,
                  onTap: () {
                    _days = n;
                    _make();
                  },
                ),
              PillChip(
                label: tr('From today', 'Vanaf vandaag'),
                selected: _start == _today,
                onTap: () {
                  _start = _today;
                  _make();
                },
              ),
              PillChip(
                label: tr('From tomorrow', 'Vanaf morgen'),
                selected: _start == tomorrow,
                onTap: () {
                  _start = tomorrow;
                  _make();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          label(tr('Meals', 'Maaltijden')),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final m in Meal.values)
                PillChip(
                  label: m.label,
                  check: true,
                  selected: _meals.contains(m),
                  onTap: () {
                    _meals = _meals.contains(m) ? ({..._meals}..remove(m)) : {..._meals, m};
                    _make();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summary(Palette p, WeekMenuPlanner planner, WeekMenu menu) {
    double avg(String k) => menu.days.fold(0.0, (a, d) => a + (d.share(k) ?? 1)) / menu.days.length;
    final focus = (planner.input.focus.keys.toList()..sort((a, b) => planner.input.focus[b]!.compareTo(planner.input.focus[a]!))).take(4).toList();
    final e = (avg('energy') * 100).round(), pr = (avg('protein') * 100).round();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('${menu.days.length} days', '${menu.days.length} dagen')),
          const SizedBox(height: 6),
          Text(
            tr('On average $e% of your energy and $pr% of your protein goal.', 'Gemiddeld $e% van je energie en $pr% van je eiwitdoel.'),
            style: TextStyle(fontSize: 13.5, color: p.ink),
          ),
          if (focus.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              tr(
                'Extra attention for what you are often low in: ${_names(focus)}.',
                'Extra aandacht voor wat je vaak te weinig hebt: ${_names(focus)}.',
              ),
              style: TextStyle(fontSize: 13, color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }

  Widget _day(Palette p, WeekMenuPlanner planner, int index, MenuDay d) {
    final check = planner.check(d);
    final goal = d.targets['energy']?.goal ?? 0;
    final pGoal = d.targets['protein']?.goal ?? 0;
    final e = d.share('energy') ?? 1;
    // Stoffen om te tonen: wat je vaak te weinig hebt eerst, dan wat nog laag is
    final keys = <String>{
      ...(planner.input.focus.keys.toList()..sort((a, b) => planner.input.focus[b]!.compareTo(planner.input.focus[a]!))).take(4),
      ...check.low.take(3),
      ...check.reached.take(2),
    }.take(6);
    final notes = <String>[
      if (!check.energyOk)
        tr(
          'Energy is ${(e * 100).round()}% of your goal; adjust portions to taste.',
          'Energie is ${(e * 100).round()}% van je doel; pas de porties naar smaak aan.',
        ),
      if (!check.proteinOk) tr('Protein stays below your goal with these foods.', 'Eiwit blijft onder je doel met deze producten.'),
      if (check.hard.isNotEmpty)
        tr(
          'Hard to reach with food alone: ${_names(check.hard)}. A supplement can help; ask your doctor or dietitian.',
          'Moeilijk te halen met alleen eten: ${_names(check.hard)}. Een supplement kan helpen; vraag het je arts of diëtist.',
        ),
      if (check.low.any((k) => !check.hard.contains(k)))
        tr(
          'Still low: ${_names(check.low.where((k) => !check.hard.contains(k)))}.',
          'Nog laag: ${_names(check.low.where((k) => !check.hard.contains(k)))}.',
        ),
    ];

    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelTitle(
                  _dayLabel(d.date),
                  trailing: Text('${fmtInt(d.kcal)} / ${fmtInt(goal)} kcal', style: numStyle(13, color: p.ink)),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: goal <= 0 ? 0 : (d.kcal / goal).clamp(0, 1),
                    minHeight: 6,
                    color: check.energyOk ? p.brand : p.high,
                    backgroundColor: p.track,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Protein ${fmtInt(d.protein)} / ${fmtInt(pGoal)} g', 'Eiwit ${fmtInt(d.protein)} / ${fmtInt(pGoal)} g'),
                  style: numStyle(12.5, weight: FontWeight.w500, color: check.proteinOk ? p.ink2 : p.high),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final k in keys)
                      if (nutrientByKey[k] case final n?) _chip(p, n.name, d.share(k) ?? 0),
                  ],
                ),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(note, style: TextStyle(fontSize: 12.5, height: 1.4, color: p.ink2)),
                  ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          for (final meal in Meal.values)
            if (d.items.any((x) => x.meal == meal)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 2),
                child: Text(
                  meal.label,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              for (final (i, x) in d.items.indexed)
                if (x.meal == meal) _row(p, index, i, x),
            ],
        ],
      ),
    );
  }

  Widget _chip(Palette p, String name, double share) {
    final ok = share >= 0.9, low = share < 0.7;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: ok ? p.okSoft : (low ? p.lowSoft : p.sunken), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '$name ${(share * 100).round()}%',
        style: numStyle(11.5, weight: FontWeight.w500, color: ok ? p.ok : (low ? p.low : p.ink2)),
      ),
    );
  }

  Widget _row(Palette p, int day, int index, MenuItem x) {
    final sub = [_amount(x), if (x.reasons.isNotEmpty) tr('for ${_names(x.reasons)}', 'voor ${_names(x.reasons)}')].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  x.food.food.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: p.ink),
                ),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: p.ink3),
                ),
              ],
            ),
          ),
          Text(
            '${fmtInt(x.kcal)} kcal',
            style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
          ),
          IconButton(
            tooltip: tr('Swap', 'Omwisselen'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.swap_horiz_rounded, size: 18, color: p.ink3),
            onPressed: () => _swap(day, index),
          ),
          IconButton(
            tooltip: tr('Remove', 'Verwijderen'),
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => _remove(day, index),
          ),
        ],
      ),
    );
  }
}
