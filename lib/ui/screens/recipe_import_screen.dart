import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/models.dart';
import '../../data/user_db.dart' show Meal;
import '../../i18n.dart';
import '../../nutrition/quick_parse.dart';
import '../../nutrition/recipe_line.dart';
import '../../platform/ai_request.dart';
import '../../platform/recipe_import.dart';
import '../../state/app_state.dart';
import '../../sync/pro.dart';
import '../theme.dart';
import '../widgets/ai_quota_note.dart';
import '../widgets/kit.dart';
import '../widgets/number_input.dart';
import '../widgets/pro_widgets.dart';
import '../widgets/quick_line.dart';
import 'add_food_screen.dart';
import 'label_scan_screen.dart' show aiToken, pickAiPhoto;
import 'recipe_screen.dart';

/// De verbinding met /api/recipe. Te vervangen in tests.
@visibleForTesting
RecipeImport recipeImport = RecipeImport();

/// Eén ingrediënt in de lijst om na te kijken: de regel uit het recept, wat Snel loggen erin vond, of een product dat
/// je zelf koos.
class RecipeImportRow {
  RecipeImportRow(this.text, this.line, {this.check = false, this.counted = true, this.why});
  String text;
  QuickLine? line;

  /// Zelf gekozen product met hoeveelheid (via Zoeken); gaat voor op [line].
  ItemTemplate? picked;

  /// Best nakijken: geen zekere treffer of een geschatte hoeveelheid. Gaat weg zodra je iets aan de regel doet.
  bool check;

  /// Telt mee in het recept. Water, "naar smaak" en een serveersuggestie niet, tot je ze zelf aanzet.
  bool counted;

  /// Waarom nakijken of niet meetellen (zie [RecipeMatch.why]).
  final String? why;

  bool get ready => counted && (picked != null || (line != null && line!.found && line!.grams > 0));

  ItemTemplate? get template {
    if (picked != null) return picked;
    final l = line;
    if (l == null || !l.found || l.grams <= 0) return null;
    return ItemTemplate(
      foodRef: l.food.ref,
      name: l.food.name,
      brand: l.food.brand,
      grams: l.grams,
      quantity: l.portion == null ? l.grams : l.n,
      portionLabel: l.portion?.label,
      per100g: l.food.per100g,
    );
  }
}

/// De regels van een recept omzetten naar rijen (SU-1): elke regel wordt gelezen als hoeveelheid, product en
/// notities ([parseRecipeLine]) en opgezocht met de zoeker van Snel loggen ([matchRecipeLine]). Eén regel geeft
/// hoogstens één rij: "finely chopped" of "salt and pepper" maakt nooit een extra product. Kopjes ("For the sauce") en
/// regels zonder product vallen weg. Zo voor een link en voor een foto.
List<RecipeImportRow> recipeRows(List<String> lines, List<(Food, double, Portion?)> Function(QuickItem) resolve) {
  final rows = <RecipeImportRow>[];
  for (final raw in lines) {
    final m = matchRecipeLine(raw, resolve);
    if (m == null || m.line.food.isEmpty) continue;
    rows.add(
      RecipeImportRow(
        raw.trim(),
        m.options.isEmpty && !m.counted ? null : QuickLine(m.item, m.options),
        check: m.check || (m.counted && m.options.isEmpty),
        counted: m.counted,
        why: m.options.isEmpty && m.counted ? 'none' : m.why,
      ),
    );
  }
  return rows;
}

/// Wat de nagekeken rijen samen geven, per portie.
({double kcal, double protein, double carbs, double fat}) recipeImportPerServing(List<RecipeImportRow> rows, double servings) {
  var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0;
  for (final r in rows) {
    final t = r.ready ? r.template : null;
    if (t == null) continue;
    kcal += (t.per100g['energy'] ?? 0) * t.grams / 100;
    protein += (t.per100g['protein'] ?? 0) * t.grams / 100;
    carbs += (t.per100g['carbs'] ?? 0) * t.grams / 100;
    fat += (t.per100g['fat'] ?? 0) * t.grams / 100;
  }
  final n = servings < 1 ? 1 : servings;
  return (kcal: kcal / n, protein: protein / n, carbs: carbs / n, fat: fat / n);
}

/// Een recept importeren uit een link of een foto van een kookboekpagina (Pro). Daarna kijk je elke regel na (andere
/// treffer, hoeveelheid, weghalen of zelf zoeken), en opent het receptscherm ingevuld om te bewaren. Geeft het
/// bewaarde recept (als product) terug.
class RecipeImportScreen extends StatefulWidget {
  const RecipeImportScreen({super.key});

  @override
  State<RecipeImportScreen> createState() => _RecipeImportScreenState();
}

class _RecipeImportScreenState extends State<RecipeImportScreen> {
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _servings = TextEditingController();
  bool _busy = false;
  String? _error;

  /// null = nog niets geïmporteerd
  List<RecipeImportRow>? _rows;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) proOf(context, listen: false)?.refreshAiQuota(AiKind.recipe);
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _servings.dispose();
    super.dispose();
  }

  Future<void> _import({required bool photo}) async {
    if (_busy) return;
    final token = aiToken(context);
    if (token == null) {
      setState(() => _error = aiErrorText('login', kind: AiKind.recipe));
      return;
    }
    final pro = proOf(context, listen: false);
    final s = context.read<AppState>();
    RecipeDraft draft;
    try {
      if (photo) {
        final jpeg = await pickAiPhoto(context, title: tr('Photo of the recipe', 'Foto van het recept'));
        if (jpeg == null || !mounted) return;
        setState(() {
          _busy = true;
          _error = null;
        });
        draft = await recipeImport.fromPhoto(jpeg, token: token);
      } else {
        final url = _url.text.trim();
        if (url.isEmpty) return;
        setState(() {
          _busy = true;
          _error = null;
        });
        draft = await recipeImport.fromLink(url.contains('://') ? url : 'https://$url', token: token);
      }
      final q = recipeImport.lastQuota;
      if (q != null) pro?.noteAiQuota(AiKind.recipe, q);
    } on AiException catch (e) {
      if (e.quota != null) pro?.noteAiQuota(AiKind.recipe, e.quota!);
      if (mounted) {
        setState(() {
          _busy = false;
          _error = aiErrorText(e.code, kind: AiKind.recipe);
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = aiErrorText('bad_image', kind: AiKind.recipe);
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _name.text = draft.name ?? '';
      _servings.text = '${draft.servings ?? 1}';
      _rows = recipeRows(draft.ingredients, s.resolveQuick);
    });
  }

  Future<void> _search(RecipeImportRow row) async {
    final query = row.line?.item.query ?? parseRecipeLine(row.text)?.food ?? cleanRecipeLine(row.text);
    final t = await Navigator.of(context).push<ItemTemplate>(
      MaterialPageRoute(builder: (_) => AddFoodScreen(meal: Meal.lunch, pickOnly: true, initialQuery: query)),
    );
    if (t != null && mounted) {
      _touch(row, () {
        row.picked = t;
        row.counted = true;
      });
    }
  }

  Future<void> _editText(RecipeImportRow row) async {
    final c = TextEditingController(text: row.text);
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Change ingredient', 'Ingrediënt aanpassen')),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('e.g. 200 g flour', 'bv. 200 g bloem')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tr('OK', 'OK'))),
        ],
      ),
    );
    c.dispose();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final s = context.read<AppState>();
    final rows = _rows!;
    final i = rows.indexOf(row);
    if (i < 0) return;
    setState(() => rows.replaceRange(i, i + 1, recipeRows([text.trim()], s.resolveQuick)));
  }

  Future<void> _create() async {
    final rows = _rows ?? const [];
    final items = [for (final r in rows) ?r.template];
    final servings = _servingCount;
    final draft = Recipe(ref: 'recipe:import', name: _name.text.trim(), servings: servings, ingredients: items);
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => RecipeScreen(draft: draft)));
    if (food != null && mounted) Navigator.of(context).pop(food);
  }

  /// Waarom een regel nagekeken moet worden of niet meetelt, in gewone woorden.
  String? _reason(RecipeImportRow row) {
    if (!row.counted) {
      return switch (row.why) {
        'water' => tr('Not counted: water has no nutrients', 'Niet meegeteld: water heeft geen voedingsstoffen'),
        'taste' => tr('Not counted: to taste, no amount', 'Niet meegeteld: naar smaak, geen hoeveelheid'),
        'serve' => tr('Not counted: served on the side', 'Niet meegeteld: om erbij te serveren'),
        _ => tr('Not counted', 'Niet meegeteld'),
      };
    }
    if (!row.check) return null;
    return switch (row.why) {
      'amount' => tr('Check this: the amount is a guess', 'Kijk dit na: de hoeveelheid is geschat'),
      'none' => tr('Check this: nothing found', 'Kijk dit na: niets gevonden'),
      _ => tr('Check this: not sure this is the right product', 'Kijk dit na: niet zeker of dit het juiste product is'),
    };
  }

  /// Iets aanpassen aan een regel = nagekeken.
  void _touch(RecipeImportRow row, VoidCallback change) => setState(() {
    change();
    row.check = false;
  });

  Widget _row(RecipeImportRow row) {
    final p = context.pal;
    final l = row.line;
    final picked = row.picked;
    final String title, sub;
    if (picked != null) {
      title = picked.name;
      sub = '${picked.grams < 1 ? '<1' : fmtInt(picked.grams)} g · ${fmtInt(picked.kcal)} kcal';
    } else if (l != null && l.found) {
      title = l.food.name;
      sub = '${l.grams < 1 ? '<1 g' : l.amountLabel} · ${bigNum(l.kcal)} kcal';
    } else {
      title = row.counted ? tr('Nothing found', 'Niets gevonden') : (l?.item.query ?? row.text);
      sub = tr('Tap Search to pick a product', 'Tik op Zoeken om een product te kiezen');
    }
    final reason = _reason(row);
    final check = row.counted && row.check;
    final active = row.ready;
    final i = _rows!.indexOf(row);
    return Container(
      key: ValueKey('recipe-row-$i'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      decoration: BoxDecoration(
        color: check ? p.highSoft : null,
        border: Border.all(color: check ? p.high : p.line, width: check ? 1.5 : 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${row.text}"', style: TextStyle(fontSize: 12, color: p.ink3), maxLines: 2, overflow: TextOverflow.ellipsis),
          if (reason != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  Icon(check ? Icons.error_outline_rounded : Icons.remove_circle_outline_rounded, size: 14, color: check ? p.high : p.ink3),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      reason,
                      key: check ? ValueKey('recipe-check-$i') : null,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: check ? p.high : p.ink3),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: active ? p.ink : p.ink3)),
                    Text(sub, style: TextStyle(fontSize: 12, color: active ? p.ink2 : p.ink3)),
                  ],
                ),
              ),
              if (row.counted && picked == null && l != null && l.found) ...[
                IconButton(
                  tooltip: tr('Less', 'Minder'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  onPressed: () => _touch(row, () => l.step(up: false)),
                ),
                IconButton(
                  tooltip: tr('More', 'Meer'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => _touch(row, () => l.step(up: true)),
                ),
              ],
              IconButton(
                tooltip: tr('Remove', 'Weghalen'),
                icon: Icon(Icons.close_rounded, color: p.ink3),
                onPressed: () => setState(() => _rows!.remove(row)),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              if (!row.counted && (picked != null || (l != null && l.found)))
                TextButton(
                  key: ValueKey('recipe-count-$i'),
                  onPressed: () => _touch(row, () => row.counted = true),
                  child: Text(tr('Count it', 'Meetellen')),
                ),
              if (row.counted && picked == null && l != null && l.options.length > 1)
                PopupMenuButton<int>(
                  tooltip: tr('Other match', 'Andere treffer'),
                  itemBuilder: (_) => [
                    for (final (i, o) in l.options.indexed)
                      PopupMenuItem(
                        value: i,
                        child: Text(
                          '${o.$1.name} · ${fmtInt((o.$1.per100g['energy'] ?? 0) * o.$2 / 100)} kcal',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onSelected: (i) => _touch(row, () => l.select(i)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Text(tr('Other', 'Andere'), style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.ink2)),
                  ),
                ),
              TextButton(onPressed: () => _search(row), child: Text(tr('Search', 'Zoeken'))),
              TextButton(onPressed: () => _editText(row), child: Text(tr('Edit text', 'Tekst aanpassen'))),
            ],
          ),
        ],
      ),
    );
  }

  double get _servingCount => (double.tryParse(_servings.text.trim().replaceAll(',', '.')) ?? 1).clamp(1, 1000).toDouble();

  /// Wat het recept per portie geeft, live terwijl je nakijkt (SU-1: vóór het bewaren een totaal zien).
  Widget _totals({Key? key}) {
    final p = context.pal;
    final rows = _rows!;
    final per = recipeImportPerServing(rows, _servingCount);
    final toCheck = rows.where((r) => r.counted && r.check).length;
    Widget macro(String label, double v, Color c) => Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text('${fmtInt(v)} g $label', style: TextStyle(fontSize: 12.5, color: p.ink2)),
        ],
      ),
    );
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(color: p.surface2, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Per serving', 'Per portie'), style: TextStyle(fontSize: 12.5, color: p.ink3)),
          Text(
            '${fmtInt(per.kcal)} kcal',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.ink),
          ),
          const SizedBox(height: 4),
          Wrap(
            runSpacing: 4,
            children: [
              macro(tr('protein', 'eiwit'), per.protein, p.protein),
              macro(tr('carbs', 'koolhydraten'), per.carbs, p.carbs),
              macro(tr('fat', 'vet'), per.fat, p.fat),
            ],
          ),
          if (toCheck > 0) ...[
            const SizedBox(height: 6),
            Text(
              toCheck == 1
                  ? tr('1 line to check: it is marked below.', '1 regel om na te kijken: die is hieronder gemarkeerd.')
                  : tr('$toCheck lines to check: they are marked below.', '$toCheck regels om na te kijken: die zijn hieronder gemarkeerd.'),
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.high),
            ),
          ],
        ],
      ),
    );
  }

  Widget _input(Pro? pro) {
    final p = context.pal;
    final allowed = pro?.canUse(AiKind.recipe) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            'Paste a link to a recipe, or take a photo of a cookbook page. We read the ingredients and look each one up, '
                'like Quick log. You check everything before the recipe is saved.',
            'Plak een link naar een recept, of neem een foto van een bladzijde uit een kookboek. We lezen de ingrediënten en zoeken '
                'ze op zoals bij Snel loggen. Jij kijkt alles na voor het recept bewaard wordt.',
          ),
          style: TextStyle(fontSize: 14, height: 1.4, color: p.ink2),
        ),
        AiQuotaNote(kind: AiKind.recipe, quota: pro?.aiQuota(AiKind.recipe), pro: pro?.isPro ?? false),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('recipe-url'),
          controller: _url,
          enabled: allowed && !_busy,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: tr('Link to the recipe', 'Link naar het recept'), hintText: 'https://…'),
          onSubmitted: (_) => _import(photo: false),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          key: const ValueKey('recipe-from-link'),
          onPressed: allowed && !_busy ? () => _import(photo: false) : null,
          icon: const Icon(Icons.link_rounded),
          label: Text(tr('Get the recipe', 'Recept ophalen')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('recipe-from-photo'),
          onPressed: allowed && !_busy ? () => _import(photo: true) : null,
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(tr('Photo of a cookbook page', 'Foto van een kookboekpagina')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (_busy) ...[const SizedBox(height: 14), const Center(child: CircularProgressIndicator())],
        const SizedBox(height: 12),
        Text(
          tr(
            'The page or photo is read by an AI model on Cloudflare and is not stored.',
            'De pagina of foto wordt gelezen door een AI-model bij Cloudflare en niet bewaard.',
          ),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: p.ink3),
        ),
      ],
    );
  }

  Widget _review() {
    final p = context.pal;
    final rows = _rows!;
    final ready = rows.where((r) => r.ready).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('recipe-import-name'),
          controller: _name,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: tr('Recipe name', 'Naam van het recept')),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('recipe-import-servings'),
          controller: _servings,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: decimalInput,
          decoration: InputDecoration(labelText: tr('Number of servings', 'Aantal porties')),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _totals(key: const ValueKey('recipe-import-totals')),
        const SizedBox(height: 16),
        Text(
          tr('Check the ingredients', 'Kijk de ingrediënten na'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink),
        ),
        Text(
          tr(
            'Each line was looked up for you. Change the amount, pick another match, search yourself or remove it. '
                'Herbs and spices count for a few grams.',
            'Elke regel werd voor je opgezocht. Pas de hoeveelheid aan, kies een andere treffer, zoek zelf of haal ze weg. '
                'Kruiden en specerijen tellen voor een paar gram.',
          ),
          style: TextStyle(fontSize: 12.5, color: p.ink2),
        ),
        const SizedBox(height: 10),
        for (final r in rows) _row(r),
        const SizedBox(height: 8),
        _totals(),
        const SizedBox(height: 10),
        FilledButton(
          key: const ValueKey('recipe-import-create'),
          onPressed: ready == 0 ? null : _create,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: Text(tr('Make recipe with $ready ingredients', 'Recept maken met $ready ingrediënten')),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pro = proOf(context);
    final p = context.pal;
    // Een nagekeken import gaat niet zomaar verloren met Terug: eerst vragen (SU-14)
    return PopScope(
      canPop: _rows == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: _scaffold(pro, p),
    );
  }

  Future<void> _confirmLeave() async {
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Discard this import?', 'Deze import weggooien?')),
        content: Text(tr('The ingredients you checked will be lost.', 'De ingrediënten die je nakeek, gaan verloren.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: Text(tr('Keep editing', 'Verder nakijken'))),
          FilledButton(key: const ValueKey('recipe-import-discard'), onPressed: () => Navigator.pop(d, true), child: Text(tr('Discard', 'Weggooien'))),
        ],
      ),
    );
    if (ok == true && mounted) nav.pop();
  }

  Widget _scaffold(Pro? pro, Palette p) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Import recipe', 'Recept importeren'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Narrow(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_rows == null) _input(pro) else _review(),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!, key: const ValueKey('recipe-import-error'), style: TextStyle(fontSize: 13, color: p.high)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
