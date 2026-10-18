import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../nutrition/nutrients.dart';
import '../../nutrition/supplements.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../../i18n.dart';

/// Je supplementen: toevoegen uit de lijst of zelf samenstellen, en kiezen of ze elke dag vanzelf aangevinkt worden.
class SupplementsScreen extends StatelessWidget {
  const SupplementsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final s = context.read<AppState>();
    final picked = await Navigator.of(context).push<Supplement>(MaterialPageRoute(builder: (_) => const _CatalogScreen()));
    if (picked != null) s.addSupplement(picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final list = s.supplements;
    return Scaffold(
      appBar: AppBar(title: Text(tr('My supplements', 'Mijn supplementen'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add_rounded),
        label: Text(tr('Add supplement', 'Supplement toevoegen')),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 104),
        children: [
          Narrow(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Your supplements appear every day under Today: tick them off when you have taken them. If you really take something every day, '
                          'turn on "Tick automatically every day"; if you forget once, untick it that day.',
                      'Je supplementen staan elke dag op Vandaag: vink ze aan als je ze genomen hebt. Neem je iets echt elke dag, '
                          'zet dan "Elke dag vanzelf aanvinken" aan; vergat je het eens, dan vink je het die dag af.',
                    ),
                    style: TextStyle(fontSize: 13, height: 1.45, color: pal.ink2),
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    Panel(
                      shadow: false,
                      child: Text(
                        tr('No supplements yet. Tap "Add supplement".', 'Nog geen supplementen. Tik op "Supplement toevoegen".'),
                        style: TextStyle(color: pal.ink2),
                      ),
                    ),
                  for (final sup in list) ...[
                    Panel(
                      shadow: false,
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      sup.name,
                                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: pal.ink),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      [sup.dose, if (sup.summary.isNotEmpty) sup.summary].join(' · '),
                                      style: TextStyle(fontSize: 12.5, height: 1.4, color: pal.ink3),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: tr('Remove', 'Verwijderen'),
                                icon: Icon(Icons.delete_outline_rounded, color: pal.ink3),
                                onPressed: () => s.removeSupplement(sup),
                              ),
                            ],
                          ),
                          SwitchListTile(
                            contentPadding: const EdgeInsets.only(right: 8),
                            dense: true,
                            title: Text(tr('Tick automatically every day', 'Elke dag vanzelf aanvinken')),
                            value: sup.auto,
                            onChanged: (v) => s.updateSupplement(sup.copyWith(auto: v)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kiezen uit de ingebouwde lijst, of een eigen supplement maken.
class _CatalogScreen extends StatefulWidget {
  const _CatalogScreen();

  @override
  State<_CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<_CatalogScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final mine = {for (final x in context.watch<AppState>().supplements) x.id};
    final list = [
      for (final x in localizedCatalog)
        if (x.name.toLowerCase().contains(_q.toLowerCase()) || x.summary.toLowerCase().contains(_q.toLowerCase())) x,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(tr('Add supplement', 'Supplement toevoegen'))),
      body: Narrow(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: TextField(
                decoration: InputDecoration(
                  hintText: tr('Search, e.g. vitamin D or magnesium', 'Zoek, bv. vitamine D of magnesium'),
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            ListTile(
              leading: Icon(Icons.edit_note_rounded, color: pal.brand),
              title: Text(
                tr('Create your own supplement', 'Eigen supplement maken'),
                style: TextStyle(color: pal.brand, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(tr('Enter the amounts from your label', 'Vul de hoeveelheden van je etiket in')),
              onTap: () async {
                final custom = await Navigator.of(context).push<Supplement>(MaterialPageRoute(builder: (_) => const _CustomScreen()));
                if (custom != null && context.mounted) Navigator.pop(context, custom);
              },
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                children: [
                  for (final x in list)
                    ListTile(
                      enabled: !mine.contains(x.id),
                      title: Text(x.name),
                      subtitle: Text(
                        mine.contains(x.id)
                            ? tr('already in your list', 'staat al in je lijst')
                            : [x.dose, if (x.summary.isNotEmpty) x.summary].join(' · '),
                      ),
                      trailing: mine.contains(x.id) ? Icon(Icons.check_rounded, color: pal.ok) : const Icon(Icons.add_rounded),
                      onTap: () => Navigator.pop(context, x),
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

/// Eigen supplement: naam, dosis en per voedingsstof de hoeveelheid per dosis.
class _CustomScreen extends StatefulWidget {
  const _CustomScreen();

  @override
  State<_CustomScreen> createState() => _CustomScreenState();
}

class _CustomScreenState extends State<_CustomScreen> {
  final _name = TextEditingController();
  final _dose = TextEditingController(text: tr('1 tablet', '1 tablet'));
  final _amounts = <String, TextEditingController>{};

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    for (final c in _amounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addNutrient() async {
    final n = await showModalBottomSheet<Nutrient>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.7,
        child: ListView(
          children: [
            for (final n in nutrients)
              if (n.key != 'energy' && !_amounts.containsKey(n.key))
                ListTile(title: Text(n.name), trailing: Text(n.unit), onTap: () => Navigator.pop(ctx, n)),
          ],
        ),
      ),
    );
    if (n != null) setState(() => _amounts[n.key] = TextEditingController());
  }

  void _save() {
    final values = <String, double>{'energy': 0};
    for (final e in _amounts.entries) {
      final v = double.tryParse(e.value.text.trim().replaceAll(',', '.'));
      if (v != null && v > 0) values[e.key] = v;
    }
    if (_name.text.trim().isEmpty || values.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr('Enter a name and at least one nutrient with an amount.', 'Geef een naam en minstens één voedingsstof met een hoeveelheid.'),
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      Supplement(
        id: 'c${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim(),
        dose: _dose.text.trim().isEmpty ? tr('1 dose', '1 dosis') : _dose.text.trim(),
        nutrients: values,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Custom supplement', 'Eigen supplement')),
        actions: [TextButton(onPressed: _save, child: Text(tr('Save', 'Bewaren')))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(labelText: tr('Name', 'Naam'), hintText: tr('E.g. Magnesium + B6', 'Bv. Magnesium + B6')),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _dose,
                  decoration: InputDecoration(labelText: tr('Dose', 'Dosis'), hintText: tr('E.g. 1 capsule', 'Bv. 1 capsule')),
                ),
                const SizedBox(height: 16),
                Text(
                  tr('Per dose', 'Per dosis'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: pal.ink),
                ),
                const SizedBox(height: 6),
                for (final e in _amounts.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(child: Text(nutrientByKey[e.key]!.name)),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: e.value,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(suffixText: nutrientByKey[e.key]!.unit, isDense: true),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          tooltip: tr('Remove', 'Weghalen'),
                          onPressed: () => setState(() => _amounts.remove(e.key)?.dispose()),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _addNutrient,
                  icon: Icon(Icons.add_rounded),
                  label: Text(tr('Add nutrient', 'Voedingsstof toevoegen')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
