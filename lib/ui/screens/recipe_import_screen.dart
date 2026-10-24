import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/food.dart';
import '../../data/models.dart';
import '../../data/user_db.dart' show Meal;
import '../../i18n.dart';
import '../../nutrition/quick_parse.dart';
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
  RecipeImportRow(this.text, this.line);
  String text;
  QuickLine? line;

  /// Zelf gekozen product met hoeveelheid (via Zoeken); gaat voor op [line].
  ItemTemplate? picked;

  bool get ready => picked != null || (line != null && line!.found && line!.grams > 0);

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

/// De regels van een recept omzetten naar rijen: opkuisen, dezelfde parser en zoeker als Snel loggen. Een regel met
/// twee producten ("salt and pepper") geeft twee rijen; een regel zonder product één rij zonder treffer.
List<RecipeImportRow> recipeRows(List<String> lines, List<(Food, double, Portion?)> Function(QuickItem) resolve) {
  final rows = <RecipeImportRow>[];
  for (final raw in lines) {
    final clean = cleanRecipeLine(raw);
    if (clean.isEmpty) continue;
    final items = parseQuick(clean);
    if (items.isEmpty) {
      rows.add(RecipeImportRow(raw, null));
      continue;
    }
    for (final q in items) {
      rows.add(RecipeImportRow(raw, QuickLine(q, resolve(q))));
    }
  }
  return rows;
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
    final query = row.line?.item.query ?? cleanRecipeLine(row.text);
    final t = await Navigator.of(context).push<ItemTemplate>(
      MaterialPageRoute(builder: (_) => AddFoodScreen(meal: Meal.lunch, pickOnly: true, initialQuery: query)),
    );
    if (t != null && mounted) setState(() => row.picked = t);
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
    final servings = (double.tryParse(_servings.text.trim().replaceAll(',', '.')) ?? 1).clamp(1, 1000).toDouble();
    final draft = Recipe(ref: 'recipe:import', name: _name.text.trim(), servings: servings, ingredients: items);
    final food = await Navigator.of(context).push<Food>(MaterialPageRoute(builder: (_) => RecipeScreen(draft: draft)));
    if (food != null && mounted) Navigator.of(context).pop(food);
  }

  Widget _row(RecipeImportRow row) {
    final p = context.pal;
    final l = row.line;
    final picked = row.picked;
    final String title, sub;
    if (picked != null) {
      title = picked.name;
      sub = '${fmtInt(picked.grams)} g · ${fmtInt(picked.kcal)} kcal';
    } else if (l != null && l.found) {
      title = l.food.name;
      sub = '${l.amountLabel} · ${bigNum(l.kcal)} kcal';
    } else {
      title = tr('Nothing found', 'Niets gevonden');
      sub = tr('Tap Search to pick a product', 'Tik op Zoeken om een product te kiezen');
    }
    final found = row.ready;
    return Container(
      key: ValueKey('recipe-row-${_rows!.indexOf(row)}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"${row.text}"', style: TextStyle(fontSize: 12, color: p.ink3), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: found ? p.ink : p.ink3)),
                    Text(sub, style: TextStyle(fontSize: 12, color: p.ink2)),
                  ],
                ),
              ),
              if (picked == null && l != null && l.found) ...[
                IconButton(
                  tooltip: tr('Less', 'Minder'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                  onPressed: () => setState(() => l.step(up: false)),
                ),
                IconButton(
                  tooltip: tr('More', 'Meer'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  onPressed: () => setState(() => l.step(up: true)),
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
              if (picked == null && l != null && l.options.length > 1)
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
                  onSelected: (i) => setState(() => l.select(i)),
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
        ),
        const SizedBox(height: 16),
        Text(
          tr('Check the ingredients', 'Kijk de ingrediënten na'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.ink),
        ),
        Text(
          tr(
            'Each line was looked up for you. Change the amount, pick another match, search yourself or remove it.',
            'Elke regel werd voor je opgezocht. Pas de hoeveelheid aan, kies een andere treffer, zoek zelf of haal ze weg.',
          ),
          style: TextStyle(fontSize: 12.5, color: p.ink2),
        ),
        const SizedBox(height: 10),
        for (final r in rows) _row(r),
        const SizedBox(height: 8),
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
