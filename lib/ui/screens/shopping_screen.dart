import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/plan.dart';
import '../../i18n.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/tap_guard.dart';
import '../widgets/undo.dart';

/// Boodschappenlijst: zelf iets toevoegen, alles uit je planner, en producten voor de stoffen die je vaak tekortkomt.
class ShoppingScreen extends StatefulWidget {
  const ShoppingScreen({super.key});

  @override
  State<ShoppingScreen> createState() => _ShoppingScreenState();
}

class _ShoppingScreenState extends State<ShoppingScreen> {
  final _removeGuard = RemoveGuard();
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addTyped(AppState s) {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    s.addShopping(t);
    _input.clear();
  }

  static String _amount(double g) => g >= 1000 ? '${fmtDec(g / 1000, 1)} kg' : '${fmtInt(g)} g';

  Future<void> _copy(List<ShoppingItem> items) async {
    final text = [
      for (final i in items)
        if (!i.done) '- ${i.name}${i.grams == null ? '' : ' (${_amount(i.grams!)})'}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('List copied.', 'Lijst gekopieerd.'))));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final items = s.shopping;
    final open = [
      for (final (i, x) in items.indexed)
        if (!x.done) (i, x),
    ];
    final done = [
      for (final (i, x) in items.indexed)
        if (x.done) (i, x),
    ];
    final planDays = s.plannedDays;
    final tips = s.shoppingTips();
    final onList = {for (final x in items) x.name.toLowerCase()};

    void toggle(int i) => s.saveShopping([...items]..[i] = items[i].toggled());
    void remove(int i) {
      if (!_removeGuard.allow()) return;
      final before = [...items];
      s.saveShopping([...items]..removeAt(i));
      showUndo(context, tr('Removed from list', 'Van de lijst gehaald'), () => s.saveShopping(before));
    }

    Widget row((int, ShoppingItem) e) {
      final (i, x) = e;
      return Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Checkbox(value: x.done, onChanged: (_) => toggle(i)),
            Expanded(
              child: InkWell(
                onTap: () => toggle(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        x.name,
                        style: TextStyle(fontSize: 14.5, color: x.done ? p.ink3 : p.ink, decoration: x.done ? TextDecoration.lineThrough : null),
                      ),
                      if (x.grams != null || x.reason != null)
                        Text(
                          [if (x.grams != null) _amount(x.grams!), if (x.reason != null) tr('for ${x.reason}', 'voor ${x.reason}')].join(' · '),
                          style: TextStyle(fontSize: 11.5, color: p.ink3),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: tr('Remove', 'Verwijderen'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
              onPressed: () => remove(i),
            ),
          ],
        ),
      );
    }

    final list = Panel(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(isDense: true, hintText: tr('Add something…', 'Iets toevoegen…')),
                    onSubmitted: (_) => _addTyped(s),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: () => _addTyped(s), child: Text(tr('Add', 'Toevoegen'))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(tr('Your list is empty.', 'Je lijst is leeg.'), style: TextStyle(color: p.ink2)),
            ),
          for (final e in open) row(e),
          if (done.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Row(
                children: [
                  Expanded(child: Eyebrow(tr('In the cart', 'In je kar'))),
                  TextButton(
                    onPressed: () => s.saveShopping([
                      for (final x in items)
                        if (!x.done) x,
                    ]),
                    child: Text(tr('Clear ticked', 'Afgevinkte wissen')),
                  ),
                ],
              ),
            ),
            for (final e in done) row(e),
          ],
        ],
      ),
    );

    final ideas = <Widget>[
      if (planDays.isNotEmpty) ...[
        Panel(
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PanelTitle(tr('From your planner', 'Uit je planner')),
              const SizedBox(height: 4),
              Text(
                planDays.length == 1
                    ? tr('1 planned day.', '1 geplande dag.')
                    : tr('${planDays.length} planned days. Products are added up.', '${planDays.length} geplande dagen. Producten worden opgeteld.'),
                style: TextStyle(fontSize: 13, color: p.ink2),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () {
                    final n = s.shoppingFromPlans(planDays);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$n products added.', '$n producten toegevoegd.'))));
                  },
                  icon: const Icon(Icons.event_note_outlined, size: 18),
                  label: Text(tr('Add everything from my plans', 'Alles uit mijn plannen toevoegen')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
      Panel(
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PanelTitle(
              tr('For what you often miss', 'Voor wat je vaak tekortkomt'),
              subtitle: tr('based on the last 14 days', 'op basis van de laatste 14 dagen'),
            ),
            const SizedBox(height: 6),
            if (tips.isEmpty)
              Text(
                tr(
                  'No big shortfalls, or not enough days logged yet. Keep it up!',
                  'Geen grote tekorten, of nog niet genoeg dagen gelogd. Ga zo door!',
                ),
                style: TextStyle(fontSize: 13, color: p.ink2),
              ),
            for (final (n, share, foods) in tips) ...[
              const SizedBox(height: 6),
              Text(
                tr('${n.name}: on average ${fmtPct(share)} of your goal', '${n.name}: gemiddeld ${fmtPct(share)} van je doel'),
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final f in foods)
                    ActionChip(
                      avatar: Icon(onList.contains(f.name.toLowerCase()) ? Icons.check_rounded : Icons.add_rounded, size: 16),
                      label: Text(f.name, style: const TextStyle(fontSize: 12.5)),
                      onPressed: onList.contains(f.name.toLowerCase()) ? null : () => s.addShopping(f.name, reason: n.name.toLowerCase()),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Shopping list', 'Boodschappenlijst')),
        actions: [
          if (open.isNotEmpty)
            IconButton(tooltip: tr('Copy list', 'Lijst kopiëren'), icon: const Icon(Icons.copy_rounded), onPressed: () => _copy(items)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            maxWidth: isDesktop(context) ? wideMaxWidth : 760,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SplitColumns(leftFlex: 6, rightFlex: 5, left: [list], right: ideas),
            ),
          ),
        ],
      ),
    );
  }
}
