import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../i18n.dart';
import '../../labs/lab_report.dart';
import '../../labs/markers.dart';
import '../../labs/pdf_text.dart';
import '../../nutrition/insights.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';

Level _level(int status) => switch (status) {
  -1 => Level.low,
  1 => Level.high,
  _ => Level.ok,
};

String _date(String day) => DateFormat('d MMM yyyy', appLocale).format(DateTime.parse(day));

String _shown(LabValue v) => '${v.comparator ?? ''}${fmtNum(v.value, v.marker?.decimals ?? 2)} ${v.unit ?? v.marker?.unit ?? ''}'.trim();

String _ref(LabValue v) => switch ((v.low, v.high)) {
  (final l?, final h?) => '${fmtNum(l, 2)} – ${fmtNum(h, 2)}',
  (null, final h?) => '< ${fmtNum(h, 2)}',
  (final l?, null) => '> ${fmtNum(l, 2)}',
  _ => '',
};

/// Bloedwaarden: je labo-verslag inlezen (PDF) of zelf invullen, met per stof wat het betekent voor je eten.
/// Alles blijft op dit toestel.
class LabsScreen extends StatelessWidget {
  const LabsScreen({super.key});

  static Future<void> importPdf(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: tr('Choose your lab report', 'Kies je labo-verslag'),
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (picked.isEmpty) return;
      final report = parseLabReport(await pdfTableLines(await picked.first.readAsBytes()));
      if (report.values.isEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'No blood values found in this file. Is it a scan (photo)? Only PDFs with text can be read for now.',
                'Geen bloedwaarden gevonden in dit bestand. Is het een scan (foto)? Voorlopig kunnen alleen PDF\'s met tekst gelezen worden.',
              ),
            ),
          ),
        );
        return;
      }
      await nav.push(MaterialPageRoute(builder: (_) => LabReviewScreen(report: report)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(tr('The file could not be read ($e).', 'Het bestand kon niet gelezen worden ($e).'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final all = s.labResults;
    final latest = s.latestLabs(months: 1200);
    final lastDay = all.isEmpty ? null : all.first.day;
    final others = [
      for (final r in all)
        if (r.day == lastDay && r.value.marker == null) r,
    ];
    final off = [
      for (final r in latest.values)
        if (r.value.status != 0) r,
    ];

    Widget privacy() => Text(
      tr(
        'Your blood values stay on this device: they are not sent to the server or synced. This is information, not a diagnosis: discuss values outside the reference range with your doctor.',
        'Je bloedwaarden blijven op dit toestel: ze gaan niet naar de server en worden niet gesynchroniseerd. Dit is uitleg, geen diagnose: bespreek waarden buiten de normaalwaarden met je arts.',
      ),
      style: TextStyle(fontSize: 11.5, height: 1.4, color: p.ink3),
    );

    final buttons = Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
            label: Text(tr('Read PDF', 'PDF inlezen')),
            onPressed: () => importPdf(context),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.edit_rounded, size: 18),
            label: Text(tr('Enter yourself', 'Zelf invullen')),
            onPressed: () => _addManually(context),
          ),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Blood values', 'Bloedwaarden'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (all.isEmpty)
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Icon(Icons.bloodtype_outlined, size: 36, color: p.brand),
                          const SizedBox(height: 10),
                          Text(
                            tr('Link your blood test to your eating', 'Koppel je bloedafname aan je eten'),
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            tr(
                              'Read the PDF of your lab report (for example from Helena or your hospital app) or enter values yourself. MacroMatrix then shows what they mean for your eating, and your weekly report gives advice that fits your blood.',
                              'Lees de PDF van je labo-verslag in (bijvoorbeeld uit Helena of je ziekenhuis-app) of vul waarden zelf in. MacroMatrix toont dan wat ze betekenen voor je eten, en je weekrapport geeft advies dat bij je bloed past.',
                            ),
                            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                          ),
                          const SizedBox(height: 14),
                          buttons,
                        ],
                      ),
                    )
                  else ...[
                    buttons,
                    const SizedBox(height: 12),
                    Panel(
                      shadow: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PanelTitle(
                            tr('Latest blood test', 'Laatste bloedafname'),
                            subtitle: _date(lastDay!),
                            trailing: IconButton(
                              tooltip: tr('Delete this blood test', 'Deze bloedafname verwijderen'),
                              icon: Icon(Icons.delete_outline_rounded, color: p.ink3),
                              onPressed: () => _deleteDay(context, lastDay),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            off.isEmpty
                                ? tr('All values the app knows are within range.', 'Alle waarden die de app kent, zijn in orde.')
                                : tr(
                                    '${off.length} ${off.length == 1 ? 'value' : 'values'} outside the range: ${off.map((r) => '${r.value.marker!.name} ${r.value.status < 0 ? 'low' : 'high'}').join(', ')}. Tap a value for what it means for your eating.',
                                    '${off.length} ${off.length == 1 ? 'waarde' : 'waarden'} buiten de normaal: ${off.map((r) => '${r.value.marker!.name} ${r.value.status < 0 ? 'laag' : 'hoog'}').join(', ')}. Tik op een waarde voor wat ze betekent voor je eten.',
                                  ),
                            style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
                          ),
                        ],
                      ),
                    ),
                    for (final g in LabGroup.values)
                      if (latest.values.where((r) => r.value.marker!.group == g).toList() case final rows when rows.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Panel(
                          shadow: false,
                          padding: const EdgeInsets.fromLTRB(18, 14, 12, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              PanelTitle(g.label),
                              const SizedBox(height: 4),
                              for (final r in rows) _LabRow(r, onTap: () => _openMarker(context, r.value.marker!)),
                            ],
                          ),
                        ),
                      ],
                    if (others.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Panel(
                        shadow: false,
                        padding: const EdgeInsets.fromLTRB(18, 6, 12, 6),
                        child: Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          // Material: het tikeffect van de lijst moet boven de kaart getekend worden
                          child: Material(
                            type: MaterialType.transparency,
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              title: Text(
                                tr('Other values on this report (${others.length})', 'Andere waarden op dit verslag (${others.length})'),
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                              ),
                              subtitle: Text(tr('Not linked to eating', 'Niet gekoppeld aan voeding'), style: TextStyle(fontSize: 12, color: p.ink3)),
                              children: [for (final r in others) _LabRow(r, showDate: false)],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 14),
                  privacy(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _deleteDay(BuildContext context, String day) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete blood test?', 'Bloedafname verwijderen?')),
        content: Text(tr('All values of ${_date(day)} are removed.', 'Alle waarden van ${_date(day)} worden verwijderd.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete', 'Verwijderen'))),
        ],
      ),
    );
    if (ok == true && context.mounted) context.read<AppState>().deleteLabDay(day);
  }

  static void _openMarker(BuildContext context, LabMarker m) =>
      showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _MarkerSheet(m));

  static Future<void> _addManually(BuildContext context) async {
    var marker = labMarkers.first;
    var unit = marker.unit;
    var day = DateTime.now();
    final value = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final units = [marker.unit, ...marker.convert.keys];
          return AlertDialog(
            title: Text(tr('Add blood value', 'Bloedwaarde toevoegen')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<LabMarker>(
                    initialValue: marker,
                    isExpanded: true,
                    decoration: InputDecoration(labelText: tr('What', 'Wat')),
                    items: [
                      for (final m in labMarkers)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m.name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (m) => setD(() {
                      marker = m!;
                      unit = m.unit;
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: value,
                          autofocus: true,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(labelText: tr('Value', 'Waarde')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (units.length > 1)
                        DropdownButton<String>(
                          value: unit,
                          items: [for (final u in units) DropdownMenuItem(value: u, child: Text(u))],
                          onChanged: (u) => setD(() => unit = u!),
                        )
                      else
                        Text(marker.unit),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(DateFormat('d MMM yyyy', appLocale).format(day)),
                    onPressed: () async {
                      final d = await showDatePicker(context: ctx, initialDate: day, firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (d != null) setD(() => day = d);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Save', 'Bewaren'))),
            ],
          );
        },
      ),
    );
    final v = double.tryParse(value.text.trim().replaceAll(',', '.'));
    if (saved != true || v == null || !context.mounted) return;
    context.read<AppState>().saveLabs(day, [LabValue(name: marker.name, marker: marker, value: v, unit: unit)]);
  }
}

class _LabRow extends StatelessWidget {
  const _LabRow(this.r, {this.onTap, this.showDate = true});
  final LabResult r;
  final VoidCallback? onTap;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final v = r.value;
    final level = _level(v.status);
    final ref = _ref(v);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            StatusMark(level, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.marker?.name ?? v.name, style: TextStyle(fontSize: 14, color: p.ink)),
                  if (ref.isNotEmpty || showDate)
                    Text(
                      [if (ref.isNotEmpty) '${tr('normal', 'normaal')} $ref', if (showDate) _date(r.day)].join(' · '),
                      style: TextStyle(fontSize: 11.5, color: p.ink3),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_shown(v), style: numStyle(13.5, color: v.status == 0 ? p.ink : p.textOf(level))),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

/// Eén stof: wat ze betekent voor je eten, en alle uitslagen van vroeger.
class _MarkerSheet extends StatelessWidget {
  const _MarkerSheet(this.m);
  final LabMarker m;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final history = [
      for (final r in s.labResults)
        if (r.value.marker?.key == m.key) r,
    ];
    final last = history.firstOrNull?.value;
    final text = last == null || last.status == 0 ? null : (last.status < 0 ? m.lowText : m.highText);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              m.name,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: p.ink),
            ),
            const SizedBox(height: 10),
            if (last != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.softOf(_level(last.status)), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  text == null ? tr('Your last value is within range.', 'Je laatste waarde is in orde.') : tr(text.$1, text.$2),
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink),
                ),
              ),
            const SizedBox(height: 12),
            PanelTitle(tr('History', 'Verloop')),
            for (final r in history)
              Dismissible(
                key: ValueKey(r.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16),
                  color: p.highSoft,
                  child: Icon(Icons.delete_outline_rounded, color: p.high),
                ),
                onDismissed: (_) => context.read<AppState>().deleteLab(r.id),
                child: _LabRow(r),
              ),
            const SizedBox(height: 4),
            Text(
              tr('Swipe a value to the left to delete it.', 'Veeg een waarde naar links om ze te verwijderen.'),
              style: TextStyle(fontSize: 11.5, color: p.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wat uit de PDF gelezen werd, nakijken voor het bewaard wordt: datum en welke waarden.
class LabReviewScreen extends StatefulWidget {
  const LabReviewScreen({super.key, required this.report});
  final LabReport report;

  @override
  State<LabReviewScreen> createState() => _LabReviewScreenState();
}

class _LabReviewScreenState extends State<LabReviewScreen> {
  late DateTime _day = widget.report.date ?? DateTime.now();
  late final Set<int> _on = {for (final (i, _) in widget.report.values.indexed) i};

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final values = widget.report.values;
    final known = [
      for (final (i, v) in values.indexed)
        if (v.marker != null) (i, v),
    ];
    final other = [
      for (final (i, v) in values.indexed)
        if (v.marker == null) (i, v),
    ];

    Widget row(int i, LabValue v) => Material(
      type: MaterialType.transparency,
      child: CheckboxListTile(
        value: _on.contains(i),
        onChanged: (on) => setState(() => on == true ? _on.add(i) : _on.remove(i)),
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: Row(
          children: [
            Expanded(
              child: Text(v.marker?.name ?? v.name, style: TextStyle(fontSize: 14, color: p.ink)),
            ),
            if (v.status != 0) ...[StatusMark(_level(v.status), size: 9), const SizedBox(width: 6)],
            Text(_shown(v), style: numStyle(13.5, color: v.status == 0 ? p.ink : p.textOf(_level(v.status)))),
          ],
        ),
        subtitle: _ref(v).isEmpty ? null : Text('${tr('normal', 'normaal')} ${_ref(v)}', style: TextStyle(fontSize: 11.5, color: p.ink3)),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(tr('Check your values', 'Kijk je waarden na'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _on.isEmpty
                ? null
                : () {
                    context.read<AppState>().saveLabs(_day, [for (final i in _on.toList()..sort()) values[i]]);
                    Navigator.of(context).pop();
                  },
            child: Text(tr('Save ${_on.length} values', '${_on.length} waarden bewaren')),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Narrow(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr(
                      'Found ${values.length} values, of which ${known.length} the app links to your eating. Check that they match your report.',
                      '${values.length} waarden gevonden, waarvan de app er ${known.length} aan je eten koppelt. Kijk na of ze overeenkomen met je verslag.',
                    ),
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: p.ink2),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(tr('Blood test of ', 'Bloedafname van ') + DateFormat('d MMMM yyyy', appLocale).format(_day)),
                    onPressed: () async {
                      final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (d != null) setState(() => _day = d);
                    },
                  ),
                  const SizedBox(height: 12),
                  Panel(
                    shadow: false,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [PanelTitle(tr('Linked to eating', 'Gekoppeld aan voeding')), for (final (i, v) in known) row(i, v)],
                    ),
                  ),
                  if (other.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Panel(
                      shadow: false,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PanelTitle(tr('Other values', 'Andere waarden'), subtitle: tr('Kept for your overview', 'Bewaard voor je overzicht')),
                          for (final (i, v) in other) row(i, v),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    tr(
                      'Your name and national register number are not read or saved. Your values stay on this device.',
                      'Je naam en rijksregisternummer worden niet gelezen of bewaard. Je waarden blijven op dit toestel.',
                    ),
                    style: TextStyle(fontSize: 11.5, color: p.ink3),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
