import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../import/importer.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import '../../i18n.dart';

/// Overstappen: je dagboek, beweging, metingen en notities uit Cronometer of MyFitnessPal overnemen.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportSource _source = ImportSource.cronometer;
  List<(String, Uint8List)> _files = const [];
  ImportBatch? _batch;
  WeightUnit? _unit;
  bool _busy = false;
  (int, int)? _result;
  String? _error;

  Future<void> _pick() async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: tr('Choose your export files', 'Kies je exportbestanden'),
        type: FileType.custom,
        allowedExtensions: const ['csv', 'zip'],
      );
      if (picked.isEmpty || !mounted) return;
      setState(() => _busy = true);
      _files = [for (final f in picked) (f.name, await f.readAsBytes())];
      _unit = null;
      _read();
    } catch (e) {
      setState(() => _error = tr('The files could not be read ($e).', 'De bestanden konden niet gelezen worden ($e).'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _read() => setState(() => _batch = Importer(_source, weightUnit: _unit).read(_files));

  void _import() {
    final b = _batch;
    if (b == null) return;
    setState(() => _busy = true);
    final r = context.read<AppState>().importBatch(b);
    setState(() {
      _busy = false;
      _result = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Narrow(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 16, 6),
                child: Row(
                  children: [
                    IconButton(onPressed: () => Navigator.of(context).maybePop(), icon: Icon(Icons.arrow_back_rounded), tooltip: tr('Back', 'Terug')),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(tr('Switching over', 'Overstappen')),
                          Text(tr('Import data', 'Gegevens importeren'), style: Theme.of(context).textTheme.headlineSmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Narrow(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr(
                        'Bring your diary, exercise, measurements and notes from another app. Your data here stays; '
                            'importing twice creates no duplicates.',
                        'Neem je dagboek, beweging, metingen en notities mee uit een andere app. Je gegevens hier blijven staan; '
                            'twee keer importeren geeft geen dubbels.',
                      ),
                      style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
                    ),
                    const SizedBox(height: 14),
                    Segmented<ImportSource>(
                      items: [for (final s in ImportSource.values) (s, s.label)],
                      selected: _source,
                      onChanged: (s) => setState(() {
                        _source = s;
                        _files = const [];
                        _batch = null;
                        _result = null;
                      }),
                    ),
                    const SizedBox(height: 12),
                    _Steps(source: _source),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                      onPressed: _busy ? null : _pick,
                      icon: const Icon(Icons.upload_file_rounded),
                      label: Text(_files.isEmpty ? tr('Choose files', 'Bestanden kiezen') : tr('Choose other files', 'Andere bestanden kiezen')),
                    ),
                    if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
                    if (_error != null) ...[const SizedBox(height: 12), _box(p, _error!, p.highSoft, p.high)],
                    if (_batch != null && _result == null) ...[const SizedBox(height: 12), _preview(p, _batch!)],
                    if (_result != null) ...[const SizedBox(height: 12), _done(p, _result!)],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _box(Palette p, String text, Color bg, Color fg) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: TextStyle(fontSize: 13, height: 1.45, color: fg)),
  );

  Widget _preview(Palette p, ImportBatch b) {
    final days = b.days.toList()..sort();
    final f = DateFormat('d MMM yyyy', appLocale);
    String range() => days.isEmpty ? '' : '${f.format(DateTime.parse(days.first))} – ${f.format(DateTime.parse(days.last))}';
    final weights = b.biometrics.where((x) => x.type == 'weight').length;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Found', 'Gevonden')),
          const SizedBox(height: 8),
          for (final (name, label, n) in b.files)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(n > 0 ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded, size: 18, color: n > 0 ? p.ok : p.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: p.ink),
                        ),
                        Text(label, style: TextStyle(fontSize: 12, color: p.ink3)),
                      ],
                    ),
                  ),
                  if (n > 0)
                    Text(
                      fmtInt(n),
                      style: numStyle(13, weight: FontWeight.w500, color: p.ink2),
                    ),
                ],
              ),
            ),
          if (!b.isEmpty) ...[
            const SizedBox(height: 10),
            Divider(color: p.line),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (b.entries.isNotEmpty) _stat(p, fmtInt(b.entries.length), tr('diary entries', 'dagboekregels')),
                if (days.isNotEmpty) _stat(p, fmtInt(days.length), tr('days', 'dagen')),
                if (b.exercises.isNotEmpty) _stat(p, fmtInt(b.exercises.length), tr('workouts', 'keer beweging')),
                if (b.biometrics.isNotEmpty) _stat(p, fmtInt(b.biometrics.length), tr('measurements', 'metingen')),
                if (b.notes.isNotEmpty) _stat(p, fmtInt(b.notes.length), 'notities'),
              ],
            ),
            if (days.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                range(),
                style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
              ),
            ],
          ],
          if (b.weightUnitUnknown && weights > 0) ...[
            const SizedBox(height: 14),
            Text(
              tr('Which unit was your weight in ${_source.label}?', 'In welke eenheid stond je gewicht in ${_source.label}?'),
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
            ),
            const SizedBox(height: 6),
            Segmented<WeightUnit>(
              height: 30,
              items: [(WeightUnit.kg, 'kilogram'), (WeightUnit.lb, tr('pounds (lb)', 'pond (lb)'))],
              selected: _unit ?? b.weightUnitUsed,
              onChanged: (u) {
                _unit = u;
                _read();
              },
            ),
          ],
          for (final w in b.warnings) ...[const SizedBox(height: 8), _box(p, w, p.lowSoft, p.low)],
          const SizedBox(height: 14),
          if (b.isEmpty)
            _box(
              p,
              tr(
                'These files contain nothing we can import. Choose the export files from ${_source.label} (see the steps above).',
                'In deze bestanden staat niets wat we kunnen overnemen. Kies de exportbestanden van ${_source.label} (zie de stappen hierboven).',
              ),
              p.sunken,
              p.ink2,
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: _busy ? null : _import,
              child: Text(tr('Import', 'Importeren')),
            ),
        ],
      ),
    );
  }

  Widget _stat(Palette p, String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: p.surface2,
      border: Border.all(color: p.line),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: numStyle(16)),
        Text(label, style: TextStyle(fontSize: 11.5, color: p.ink3)),
      ],
    ),
  );

  Widget _done(Palette p, (int, int) r) => Panel(
    color: p.okSoft,
    borderColor: p.okSoft,
    shadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle_rounded, color: p.ok),
            const SizedBox(width: 8),
            Text(
              tr('Done', 'Klaar'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          tr(
            'Added ${fmtInt(r.$1)} ${r.$1 == 1 ? 'entry' : 'entries'}'
                '${r.$2 > 0 ? ', ${fmtInt(r.$2)} were already there' : ''}. With an account they go to your other devices automatically.',
            '${fmtInt(r.$1)} ${r.$1 == 1 ? 'regel' : 'regels'} toegevoegd'
                '${r.$2 > 0 ? ', ${fmtInt(r.$2)} stonden er al' : ''}. Met een account gaan ze vanzelf naar je andere toestellen.',
          ),
          style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst), child: Text(tr('Go to my diary', 'Naar mijn dagboek'))),
      ],
    ),
  );
}

/// Hoe je je gegevens uit de andere app haalt.
class _Steps extends StatelessWidget {
  const _Steps({required this.source});
  final ImportSource source;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final steps = switch (source) {
      ImportSource.cronometer => [
        tr('On a computer, go to cronometer.com and log in.', 'Ga op een computer naar cronometer.com en log in.'),
        tr('Open Settings → Account and look for "Export Data".', 'Open Settings (instellingen) → Account en zoek "Export Data".'),
        tr(
          'Choose "All time" and download each type: Food & Recipe Entries (your diary), Exercises, Biometrics and Notes. You get a CSV file per type.',
          'Kies "All time" en download elk type: Food & Recipe Entries (je dagboek), Exercises, Biometrics en Notes. Je krijgt per type een CSV-bestand.',
        ),
        tr('Choose all those files at once below.', 'Kies hieronder al die bestanden tegelijk.'),
      ],
      ImportSource.myfitnesspal => [
        tr('On a computer, go to myfitnesspal.com and log in.', 'Ga op een computer naar myfitnesspal.com en log in.'),
        tr(
          'Open Settings → Account (or Privacy) and choose "Download your data". With Premium you can also use Reports → Export Data.',
          'Open Settings → Account (of Privacy) en kies "Download your data". Met Premium kan het ook via Reports → Export Data.',
        ),
        tr(
          'Within a few hours you get an email with a ZIP file. Download it.',
          'Je krijgt binnen een paar uur een mail met een ZIP-bestand. Download het.',
        ),
        tr('Choose that ZIP file below; no need to unzip it.', 'Kies hieronder dat ZIP-bestand; uitpakken hoeft niet.'),
      ],
    };
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('How to get your data out of ${source.label}', 'Zo haal je je gegevens uit ${source.label}')),
          const SizedBox(height: 10),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.brandSoft, borderRadius: BorderRadius.circular(999)),
                    child: Text('${i + 1}', style: numStyle(11.5, color: p.brand)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s, style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink)),
                  ),
                ],
              ),
            ),
          Text(
            source == ImportSource.cronometer
                ? tr(
                    'Every product comes along with all its nutrients. The menus may be named slightly differently in your version.',
                    'Elk product komt mee met al zijn voedingsstoffen. De menu\'s kunnen in jouw versie iets anders heten.',
                  )
                : tr(
                    'If your export only has a total per meal, it comes in as one entry per meal. The menus may be named slightly differently in your version.',
                    'Zit in je export alleen een totaal per maaltijd, dan komt dat als één regel per maaltijd binnen. De menu\'s kunnen in jouw versie iets anders heten.',
                  ),
            style: TextStyle(fontSize: 12, height: 1.45, color: p.ink3),
          ),
        ],
      ),
    );
  }
}
