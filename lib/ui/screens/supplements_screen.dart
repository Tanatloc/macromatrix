import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../labs/supplement_advice.dart';
import '../../nutrition/nutrients.dart';
import '../../nutrition/supplements.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../widgets/supplement_advice_view.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

/// Je supplementen: toevoegen uit de lijst of zelf samenstellen, en kiezen of ze elke dag vanzelf aangevinkt worden.
class SupplementsScreen extends StatelessWidget {
  const SupplementsScreen({super.key});

  Future<void> _add(BuildContext context) async {
    final s = context.read<AppState>();
    final picked = await Navigator.of(context).push<Supplement>(MaterialPageRoute(builder: (_) => const _CatalogScreen()));
    if (picked != null) s.addSupplement(picked);
  }

  /// Een supplement uit je lijst aanpassen (ook een uit de ingebouwde lijst): naam, dosis en hoeveelheden.
  Future<void> _edit(BuildContext context, Supplement sup) async {
    final s = context.read<AppState>();
    final edited = await Navigator.of(context).push<Supplement>(MaterialPageRoute(builder: (_) => _CustomScreen(existing: sup)));
    if (edited != null) s.updateSupplement(edited);
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
                  if (s.supplementAdviceList.isNotEmpty) ...[const SupplementAdvicePanel(), const SizedBox(height: 12)],
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
                                // Tik op naam of samenvatting om aan te passen
                                child: InkWell(
                                  onTap: () => _edit(context, sup),
                                  borderRadius: BorderRadius.circular(8),
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
                              ),
                              IconButton(
                                tooltip: tr('Edit', 'Aanpassen'),
                                icon: Icon(Icons.edit_outlined, color: pal.ink3),
                                onPressed: () => _edit(context, sup),
                              ),
                              IconButton(
                                tooltip: tr('Remove', 'Verwijderen'),
                                icon: Icon(Icons.delete_outline_rounded, color: pal.ink3),
                                onPressed: () {
                                  final index = s.supplements.indexWhere((x) => x.id == sup.id);
                                  s.removeSupplement(sup);
                                  showUndo(context, tr('${sup.name} removed', '${sup.name} verwijderd'), () => s.restoreSupplement(sup, index));
                                },
                              ),
                            ],
                          ),
                          // Material: anders valt het tikeffect weg achter de kaart
                          Material(
                            type: MaterialType.transparency,
                            child: SwitchListTile(
                              contentPadding: const EdgeInsets.only(right: 8),
                              dense: true,
                              title: Text(tr('Tick automatically every day', 'Elke dag vanzelf aanvinken')),
                              value: sup.auto,
                              onChanged: (v) => s.updateSupplement(sup.copyWith(auto: v)),
                            ),
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
    // Hoe vaak elk supplement al in je lijst staat (je mag hetzelfde meermaals toevoegen)
    final mine = <String, int>{};
    for (final x in context.watch<AppState>().supplements) {
      mine[x.baseId] = (mine[x.baseId] ?? 0) + 1;
    }
    // Wat bij je bloedwaarden past, bovenaan
    final advised = {for (final a in context.watch<AppState>().supplementAdviceList) ?a.catalogId};
    final list = [
      for (final x in localizedCatalog)
        if (x.name.toLowerCase().contains(_q.toLowerCase()) || x.summary.toLowerCase().contains(_q.toLowerCase())) x,
    ]..sort((a, b) => (advised.contains(a.id) ? 0 : 1) - (advised.contains(b.id) ? 0 : 1));
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
                      leading: advised.contains(x.id) ? Icon(Icons.bloodtype_rounded, color: pal.high) : null,
                      title: Text(x.name),
                      subtitle: Text(
                        [
                          if (advised.contains(x.id)) tr('fits your blood values', 'past bij je bloedwaarden'),
                          if (mine[x.id] case final n?)
                            n == 1 ? tr('already in your list', 'staat al in je lijst') : tr('$n× in your list', '$n× in je lijst'),
                          x.dose,
                          if (x.summary.isNotEmpty) x.summary,
                        ].join(' · '),
                      ),
                      trailing: mine.containsKey(x.id)
                          ? Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_rounded, color: pal.ok),
                                const SizedBox(width: 4),
                                const Icon(Icons.add_rounded),
                              ],
                            )
                          : const Icon(Icons.add_rounded),
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

/// Hoeveel IU (internationale eenheden) één eenheid van de voedingsstof is, voor etiketten die nog IU gebruiken:
/// vitamine D 1 µg = 40 IU, vitamine A (retinol) 1 µg = 3,33 IU, vitamine E 1 mg = 1,49 IU (natuurlijk
/// alfa-tocoferol; synthetisch is 1 mg = 2,22 IU, maar we rekenen met de natuurlijke vorm en zeggen dat ook).
const iuPerUnit = {'vit_d': 40.0, 'vit_a': 3.33, 'vit_e': 1.49};

/// IU omrekenen naar de eenheid van de voedingsstof (µg of mg); null als die voedingsstof geen IU kent.
double? fromIu(String key, double iu) => switch (iuPerUnit[key]) {
  final f? => iu / f,
  null => null,
};

/// Naam die de dosis volgt: "Vitamine D3 25 µg (1000 IE)" wordt bij 50 µg "Vitamine D3 50 µg (2000 IE)" (N71).
/// Alleen een hoeveelheid die precies één keer in de naam staat, wordt aangepast; een eigen naam zonder
/// hoeveelheid blijft zoals ze is.
String renameForDose(String name, Map<String, double> before, Map<String, double> after) {
  var out = name;
  String swap(String s, double old, double now, String unit, int decimals) {
    final number = RegExp.escape(fmtNum(old, decimals)).replaceAll(RegExp(r'[.,]'), '[.,]');
    final re = RegExp('(?<![\\d.,])$number(?![\\d])(\\s*)($unit)');
    final hits = re.allMatches(s).toList();
    if (hits.length != 1) return s;
    final m = hits.single;
    return s.replaceRange(m.start, m.end, '${fmtNum(now, decimals)}${m.group(1)}${m.group(2)}');
  }

  for (final e in before.entries) {
    final unit = nutrientByKey[e.key]?.unit;
    final now = after[e.key];
    if (unit == null || e.key == 'energy' || now == null || now <= 0 || now == e.value) continue;
    out = swap(out, e.value, now, RegExp.escape(unit), 3);
    if (iuPerUnit[e.key] case final f?) out = swap(out, e.value * f, now * f, 'IE|IU', 0);
  }
  return out;
}

/// Een ruime maar realistische bovengrens voor wat een supplement per dosis kan bevatten (in de eigen eenheid).
double supplementCap(String key) {
  const high = {'vit_a', 'vit_d', 'vit_k', 'b9', 'b12', 'biotin', 'b7', 'iodine', 'selenium', 'chromium', 'molybdenum'};
  final unit = nutrientByKey[key]?.unit ?? 'mg';
  if (high.contains(key) || unit == 'µg') return 100000; // µg
  if (unit == 'g') return 500;
  return 10000; // mg: ruim boven elke zinnige dosis
}

/// Eigen supplement: naam, dosis en per voedingsstof de hoeveelheid per dosis. Met [existing] een supplement uit
/// je lijst aanpassen (id, vanzelf aanvinken en startdag blijven).
class _CustomScreen extends StatefulWidget {
  const _CustomScreen({this.existing});
  final Supplement? existing;

  @override
  State<_CustomScreen> createState() => _CustomScreenState();
}

class _CustomScreenState extends State<_CustomScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _dose = TextEditingController(text: widget.existing?.dose ?? tr('1 tablet', '1 tablet'));
  late final _amounts = <String, TextEditingController>{
    for (final e in (widget.existing?.nutrients ?? const <String, double>{}).entries)
      if (e.key != 'energy' && nutrientByKey[e.key] != null) e.key: TextEditingController(text: _fmt(e.value)),
  };

  /// Voedingsstoffen waarvan je de hoeveelheid in IU invult (vitamine A, D, E).
  final _iu = <String>{};

  /// Na een poging om te bewaren: bij het veld zelf tonen wat er ontbreekt.
  bool _tried = false;

  /// Zelf aan de naam getypt: dan volgt ze de dosis niet meer.
  bool _nameTouched = false;

  /// Naam zoals ze was, die de nieuwe dosis volgt zolang je ze zelf niet aanpast.
  void _followDose() {
    final old = widget.existing;
    if (old == null || _nameTouched) return;
    final now = {for (final k in _amounts.keys) k: ?_value(k)};
    final name = renameForDose(old.name, old.nutrients, now);
    if (name != _name.text) _name.text = name;
  }

  /// Andere eenheid gekozen (µg/mg of IU): het getal omrekenen, zodat de hoeveelheid dezelfde blijft (N71).
  void _setIu(String key, bool iu) {
    if (iu == _iu.contains(key)) return;
    final c = _amounts[key]!;
    final v = parseNum(c.text);
    final f = iuPerUnit[key]!;
    setState(() {
      iu ? _iu.add(key) : _iu.remove(key);
      if (v != null) c.text = _fmt(iu ? v * f : v / f);
    });
  }

  static String _fmt(double v) => v == v.roundToDouble() ? '${v.round()}' : fmtNum(v, 3);

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
    var q = '';
    final n = await showModalBottomSheet<Nutrient>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final lower = q.trim().toLowerCase();
          final list = [
            for (final n in nutrients)
              if (n.key != 'energy' && !_amounts.containsKey(n.key) && (lower.isEmpty || n.name.toLowerCase().contains(lower))) n,
          ];
          return Padding(
            // Het toetsenbord mag de zoekbalk niet bedekken
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: SizedBox(
              height: MediaQuery.sizeOf(ctx).height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: tr('Search, e.g. zinc or B12', 'Zoek, bv. zink of B12'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                      onChanged: (v) => setS(() => q = v),
                    ),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? Center(child: Text(tr('Nothing found', 'Niets gevonden')))
                        : ListView(
                            children: [
                              for (final n in list) ListTile(title: Text(n.name), trailing: Text(n.unit), onTap: () => Navigator.pop(ctx, n)),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (n != null) setState(() => _amounts[n.key] = TextEditingController());
  }

  /// Ingevulde hoeveelheid in de eenheid van de voedingsstof (IU omgerekend), of null als het veld leeg of ongeldig is.
  double? _value(String key) {
    final v = parseNum(_amounts[key]!.text);
    if (v == null) return null;
    return _iu.contains(key) ? fromIu(key, v) : v;
  }

  /// Melding bij het veld zelf, al tijdens het typen: te veel per dosis (geen 999999 mg, dat ontregelt de score).
  String? _capError(String key) {
    final v = _value(key);
    final cap = supplementCap(key);
    if (v == null || v <= cap) return null;
    final unit = nutrientByKey[key]!.unit;
    return tr('At most ${fmtNum(cap)} $unit per dose', 'Hoogstens ${fmtNum(cap)} $unit per dosis');
  }

  bool get _noName => _name.text.trim().isEmpty;
  bool get _noAmount => !_amounts.keys.any((k) => (_value(k) ?? 0) > 0);

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_noName || _noAmount || _amounts.keys.any((k) => _capError(k) != null)) return;
    final values = <String, double>{'energy': 0};
    for (final k in _amounts.keys) {
      final v = _value(k);
      if (v != null && v > 0) values[k] = v;
    }
    // Boven de veilige bovengrens per dag: eerst vragen, zoals bij eten (40.000 IE vitamine D is meestal een tikfout
    // of de verkeerde eenheid)
    final over = [
      for (final e in values.entries)
        if (supplementUpperLimits[e.key] case final limit? when e.value > limit) (e.key, e.value, limit),
    ];
    if (over.isNotEmpty) {
      String line(String k, double v, double limit) {
        final n = nutrientByKey[k]!;
        final iu = iuPerUnit[k] == null ? '' : ' (${fmtNum(v * iuPerUnit[k]!, 0)} ${tr('IU', 'IE')})';
        return tr(
          '${n.name}: ${fmtNum(v, 3)} ${n.unit}$iu per dose is above the safe upper limit of ${fmtNum(limit)} ${n.unit} a day.',
          '${n.name}: ${fmtNum(v, 3)} ${n.unit}$iu per dosis is meer dan de veilige bovengrens van ${fmtNum(limit)} ${n.unit} per dag.',
        );
      }

      final lines = [for (final (k, v, limit) in over) line(k, v, limit)];
      final ok = await confirmUnusual(
        context,
        '${lines.join('\n')}\n\n${tr('Check the amount and the unit on the label.', 'Kijk de hoeveelheid en de eenheid op het etiket na.')}',
      );
      if (!ok || !mounted) return;
    }
    final old = widget.existing;
    Navigator.pop(
      context,
      Supplement(
        id: old?.id ?? 'c${DateTime.now().millisecondsSinceEpoch}',
        name: _name.text.trim(),
        dose: _dose.text.trim().isEmpty ? tr('1 dose', '1 dosis') : _dose.text.trim(),
        nutrients: values,
        auto: old?.auto ?? false,
        since: old?.since,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? tr('Custom supplement', 'Eigen supplement') : tr('Edit supplement', 'Supplement aanpassen')),
      ),
      // Grote knop onderaan, zoals bij een recept of eigen product (N71)
      bottomNavigationBar: SafeArea(
        child: Narrow(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _save,
              child: Text(tr('Save', 'Opslaan')),
            ),
          ),
        ),
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
                  onChanged: (_) => setState(() => _nameTouched = true),
                  decoration: InputDecoration(
                    labelText: tr('Name', 'Naam'),
                    hintText: tr('E.g. Magnesium + B6', 'Bv. Magnesium + B6'),
                    errorText: _tried && _noName ? tr('Give the supplement a name', 'Geef het supplement een naam') : null,
                  ),
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
                for (final key in _amounts.keys.toList()) _amountRow(key),
                if (_tried && _noAmount)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _amounts.isEmpty
                          ? tr(
                              'Add at least one nutrient with the amount from the label.',
                              'Voeg minstens één voedingsstof toe met de hoeveelheid van het etiket.',
                            )
                          : tr('Fill in an amount for at least one nutrient.', 'Vul bij minstens één voedingsstof een hoeveelheid in.'),
                      style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.error),
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

  Widget _amountRow(String key) {
    final c = _amounts[key]!;
    final n = nutrientByKey[key]!;
    final canIu = iuPerUnit.containsKey(key);
    final iu = _iu.contains(key);
    final converted = iu ? _value(key) : null;
    final unitStyle = TextStyle(fontSize: 14, color: context.pal.ink2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(padding: const EdgeInsets.only(top: 10), child: Text(n.name)),
          ),
          SizedBox(
            width: 150,
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: decimalInput,
              onTap: selectAllOnTap(c),
              onChanged: (_) => setState(_followDose),
              decoration: InputDecoration(
                isDense: true,
                // Eenheid als icoon: altijd zichtbaar, ook in een leeg veld. Bij A, D en E kies je µg/mg of IU.
                suffixIcon: canIu
                    ? PopupMenuButton<bool>(
                        tooltip: tr('Unit', 'Eenheid'),
                        initialValue: iu,
                        onSelected: (v) => _setIu(key, v),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: false, child: Text(n.unit)),
                          PopupMenuItem(value: true, child: Text(tr('IU', 'IE'))),
                        ],
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 4, end: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(iu ? tr('IU', 'IE') : n.unit, style: unitStyle),
                              const Icon(Icons.arrow_drop_down_rounded, size: 20),
                            ],
                          ),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
                        child: Text(n.unit, style: unitStyle),
                      ),
                suffixIconConstraints: const BoxConstraints(minHeight: 36),
                errorText: _capError(key),
                errorMaxLines: 3,
                // Wat de IU in de eigen eenheid is; vitamine E rekent met natuurlijk alfa-tocoferol
                helperText: converted == null
                    ? null
                    : '= ${fmtNum(converted, n.unit == 'µg' ? 1 : 2)} ${n.unit}${key == 'vit_e' ? tr(' (natural form)', ' (natuurlijke vorm)') : ''}',
                helperMaxLines: 2,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: tr('Remove', 'Weghalen'),
            onPressed: () => setState(() {
              _amounts.remove(key)?.dispose();
              _iu.remove(key);
            }),
          ),
        ],
      ),
    );
  }
}
