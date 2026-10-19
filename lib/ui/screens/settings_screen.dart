import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/export.dart';
import '../../data/user_db.dart';
import '../../platform/platform.dart';
import '../../platform/reminders.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/account_card.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/kit.dart';
import '../widgets/macro_schedule.dart';
import 'import_screen.dart';
import 'supplements_screen.dart';
import '../../i18n.dart';
import '../../platform/health_sync.dart';

/// Instellingen: account, weergave, beweging, terugkerende items, gegevens (export en overstappen) en bronnen.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static String _weekdays(int mask) {
    if (mask == 0x7f) return tr('every day', 'elke dag');
    final days = isNl ? ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'] : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return [
      for (var i = 0; i < 7; i++)
        if (mask & (1 << i) != 0) days[i],
    ].join(', ');
  }

  /// De beschrijvingen in de databank zijn Nederlands; in het Engels de landen en licenties vertalen.
  static String _sourceText(String d) => isNl
      ? d
      : d
            .replaceAll('Frankrijk', 'France')
            .replaceAll('Zweden', 'Sweden')
            .replaceAll('Noorwegen', 'Norway')
            .replaceAll('Denemarken', 'Denmark')
            .replaceAll('(VK)', '(UK)')
            .replaceAll('versie', 'version')
            .replaceAll('vrij te gebruiken met bronvermelding', 'free to use with attribution')
            .replaceAll('(VS)', '(US)')
            .replaceAll('publiek domein', 'public domain');

  Future<void> _export() async {
    final s = context.read<AppState>();
    final message = await saveTextFile(
      'macromatrix-diary-${dayKey(DateTime.now())}.csv',
      diaryCsv(s.user),
      subject: tr('Food diary', 'Voedingsdagboek'),
    );
    if (message != null && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Settings', 'Instellingen'))),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Narrow(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [const AccountCard(), const SizedBox(height: 10), const MacroScheduleCard(), const SizedBox(height: 10), _settings(s, pal)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settings(AppState s, Palette pal) {
    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        t,
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.ink),
      ),
    );
    return Panel(
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Reminders.supported) ...[
            title(tr('Reminders', 'Herinneringen')),
            Builder(
              builder: (context) {
                final r = context.read<Reminders>();
                final rs = r.settings;
                final time = '${rs.hour.toString().padLeft(2, '0')}:${rs.minute.toString().padLeft(2, '0')}';
                return Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Remind me to log', 'Herinner me om te loggen')),
                      subtitle: Text(tr('At $time if nothing is logged yet that day', 'Om $time als ik die dag nog niets logde')),
                      value: rs.log,
                      onChanged: (v) async {
                        await r.save(rs.copyWith(log: v));
                        setState(() {});
                      },
                    ),
                    if (rs.log)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          icon: const Icon(Icons.schedule_rounded, size: 18),
                          label: Text(tr('Change time ($time)', 'Tijd wijzigen ($time)')),
                          onPressed: () async {
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay(hour: rs.hour, minute: rs.minute),
                            );
                            if (picked == null) return;
                            await r.save(rs.copyWith(hour: picked.hour, minute: picked.minute));
                            setState(() {});
                          },
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tr('Streak at risk', 'Reeks in gevaar')),
                      subtitle: Text(tr('At 21:30 if your streak would end tonight', 'Om 21:30 als je reeks vanavond zou eindigen')),
                      value: rs.streak,
                      onChanged: (v) async {
                        await r.save(rs.copyWith(streak: v));
                        setState(() {});
                      },
                    ),
                    if (!isAndroidApp)
                      Text(
                        tr(
                          'On this device, reminders appear while the app is open.',
                          'Op dit toestel verschijnen herinneringen zolang de app openstaat.',
                        ),
                        style: TextStyle(fontSize: 12, color: pal.ink3),
                      ),
                  ],
                );
              },
            ),
          ],
          title(tr('Language', 'Taal')),
          Segmented<AppLang>(height: 30, items: [for (final l in AppLang.values) (l, l.label)], selected: appLang.value, onChanged: s.setLanguage),
          title(tr('Appearance', 'Weergave')),
          Segmented<String>(
            height: 30,
            items: [('system', tr('System', 'Zoals toestel')), ('light', tr('Light', 'Licht')), ('dark', tr('Dark', 'Donker'))],
            selected: s.themeMode,
            onChanged: s.setThemeMode,
          ),
          title(tr('Exercise', 'Beweging')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Add burned energy to your goal', 'Verbrande energie bij je doel optellen')),
            subtitle: Text(
              tr(
                'Then set your activity to "Sedentary" or "Lightly active", otherwise your training counts twice.',
                'Zet dan je activiteit op "Zittend" of "Licht actief", anders tel je je training dubbel.',
              ),
            ),
            value: s.settings.addExercise,
            onChanged: (v) => s.saveSettings(s.settings.copyWith(addExercise: v)),
          ),
          if (HealthSync.supported) ...[title('Health Connect'), const _HealthConnectTile()],
          title(tr('Water', 'Water')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Track water', 'Water bijhouden')),
            subtitle: Text(
              tr(
                'Off: water is hidden from your goals, lists and Nutrient Score, so you can focus on food.',
                'Uit: water verdwijnt uit je doelen, lijsten en Nutrient Score, zodat je je op voeding kunt focussen.',
              ),
            ),
            value: s.settings.trackWater,
            onChanged: (v) => s.saveSettings(s.settings.copyWith(trackWater: v)),
          ),
          title(tr('Recurring items', 'Terugkerende items')),
          if (s.repeats().isEmpty)
            Text(
              tr(
                'None yet. Open an item in your diary and tap the repeat icon to have it come back automatically (e.g. your daily vitamin D).',
                'Nog geen. Open een item in je dagboek en tik op het herhaal-icoon om het automatisch te laten terugkomen (bv. je dagelijkse vitamine D).',
              ),
              style: TextStyle(fontSize: 12, color: pal.ink3),
            ),
          for (final r in s.repeats())
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.item.name),
              subtitle: Text('${Meal.values[r.mealIndex].label} · ${_weekdays(r.weekdays)}'),
              trailing: IconButton(icon: Icon(Icons.delete_outline_rounded), tooltip: tr('Stop', 'Stoppen'), onPressed: () => s.deleteRepeat(r)),
            ),
          title(tr('Allergies', 'Allergieën')),
          AllergenPicker(selected: s.allergies, onChanged: s.setAllergies),
          const SizedBox(height: 6),
          Text(allergenNote, style: TextStyle(fontSize: 12, color: pal.ink3)),
          title(tr('Supplements', 'Supplementen')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.medication_outlined),
            title: Text(tr('My supplements', 'Mijn supplementen')),
            subtitle: Text(tr('${s.supplements.length} in your list', '${s.supplements.length} in je lijst')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupplementsScreen())),
          ),
          title(tr('Data', 'Gegevens')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _export,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text(tr('Export diary (CSV)', 'Dagboek exporteren (CSV)')),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text(tr('Import from Cronometer or MyFitnessPal', 'Importeren uit Cronometer of MyFitnessPal')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'All days with date, time, meal, amount and every nutrient. Opens in Excel.',
              'Alle dagen met datum, tijd, maaltijd, hoeveelheid en elke voedingsstof. Opent in Excel.',
            ),
            style: TextStyle(fontSize: 12, color: pal.ink3),
          ),
          title(tr('Sources', 'Bronnen')),
          Text(
            tr('Basic foods (built in, European sources first):', 'Basisvoedingsmiddelen (ingebouwd, Europese bronnen eerst):'),
            style: TextStyle(fontSize: 13, color: pal.ink2),
          ),
          const SizedBox(height: 6),
          for (final (_, description, count) in s.foods.sources().map((x) => (x.$1, _sourceText(x.$2), x.$3)))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                tr('• $description: ${fmtInt(count)} products', '• $description: ${fmtInt(count)} producten'),
                style: TextStyle(fontSize: 12, color: pal.ink3),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            tr(
              'Branded products: Open Food Facts, available under the Open Database License (ODbL).\n'
                  'Reference values: EFSA Dietary Reference Values; essential amino acids: WHO/FAO/UNU 2007.\n'
                  'Fonts: Geist and Geist Mono (SIL Open Font License).\n'
                  'This app does not give medical advice.',
              'Merkproducten: Open Food Facts, beschikbaar onder de Open Database License (ODbL).\n'
                  'Richtwaarden: EFSA Dietary Reference Values; essentiële aminozuren: WHO/FAO/UNU 2007.\n'
                  'Lettertypes: Geist en Geist Mono (SIL Open Font License).\n'
                  'Deze app geeft geen medisch advies.',
            ),
            style: TextStyle(fontSize: 12, height: 1.5, color: pal.ink2),
          ),
        ],
      ),
    );
  }
}

/// Health Connect aan- of uitzetten, met wanneer het laatst werd overgenomen.
class _HealthConnectTile extends StatefulWidget {
  const _HealthConnectTile();

  @override
  State<_HealthConnectTile> createState() => _HealthConnectTileState();
}

class _HealthConnectTileState extends State<_HealthConnectTile> {
  bool _busy = false;

  Future<void> _toggle(HealthSync h, bool on) async {
    if (!on) return setState(h.disable);
    setState(() => _busy = true);
    final ok = await h.enable();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'No access. Install Health Connect and allow MacroMatrix to read steps, weight and exercise.',
              'Geen toegang. Installeer Health Connect en geef MacroMatrix toestemming om stappen, gewicht en beweging te lezen.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _syncNow(HealthSync h) async {
    setState(() => _busy = true);
    final n = await h.sync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(n == 0 ? tr('Everything is up to date.', 'Alles is al bijgewerkt.') : tr('$n items updated.', '$n items bijgewerkt.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = HealthSync(context.watch<AppState>());
    final pal = context.pal;
    final last = h.lastSync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Import from Health Connect', 'Overnemen uit Health Connect')),
          subtitle: Text(
            tr(
              'Steps, workouts and weight from your watch, scale or other apps, automatically. Workouts count as exercise.',
              'Stappen, workouts en gewicht van je horloge, weegschaal of andere apps, automatisch. Workouts tellen als beweging.',
            ),
          ),
          value: h.enabled,
          onChanged: _busy ? null : (v) => _toggle(h, v),
        ),
        if (h.enabled)
          Row(
            children: [
              Expanded(
                child: Text(
                  last == null
                      ? tr('Not imported yet', 'Nog niets overgenomen')
                      : tr(
                          'Last import: ${DateFormat('d MMM HH:mm', appLocale).format(last)}',
                          'Laatst overgenomen: ${DateFormat('d MMM HH:mm', appLocale).format(last)}',
                        ),
                  style: TextStyle(fontSize: 12, color: pal.ink3),
                ),
              ),
              TextButton(onPressed: _busy ? null : () => _syncNow(h), child: Text(tr('Import now', 'Nu overnemen'))),
            ],
          ),
      ],
    );
  }
}
