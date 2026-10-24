import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/backup.dart';
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
import '../widgets/pro_widgets.dart';
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
    final entries = s.user.entriesBetween('0000-01-01', '9999-12-31');
    final days = {for (final e in entries) e.day}.length;
    final message = await saveTextFile(
      'macromatrix-diary-${dayKey(DateTime.now())}.csv',
      diaryCsv(s.user, values: s.entryValues),
      subject: tr('Food diary', 'Voedingsdagboek'),
    );
    // Altijd een bevestiging, ook als de browser het bestand stil downloadt
    final done = days == 1 ? tr('1 day exported', '1 dag geëxporteerd') : tr('$days days exported', '$days dagen geëxporteerd');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message == null ? done : '$done. $message')));
  }

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  /// Alles in één JSON-bestand (zie data/backup.dart), op dezelfde manier bewaard of gedeeld als de CSV.
  Future<void> _exportAll() async {
    final s = context.read<AppState>();
    final message = await saveTextFile(
      'macromatrix-backup-${dayKey(DateTime.now())}.json',
      backupJson(s.user),
      subject: tr('MacroMatrix backup', 'MacroMatrix-back-up'),
      mime: 'application/json',
    );
    if (message != null && mounted) _snack(message);
  }

  /// Een back-up inlezen: eerst controleren, dan tonen wat erin zit en kiezen tussen samenvoegen en vervangen.
  Future<void> _restore() async {
    final s = context.read<AppState>();
    final Backup backup;
    try {
      final picked = await FilePicker.pickFiles(
        dialogTitle: tr('Choose a MacroMatrix backup', 'Kies een MacroMatrix-back-up'),
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (picked.isEmpty || !mounted) return;
      backup = readBackup(s.user, await picked.first.readAsBytes());
    } on BackupException catch (e) {
      if (mounted) _problem(e.message);
      return;
    } catch (e) {
      if (mounted) _problem(tr('The file could not be read ($e).', 'Het bestand kon niet gelezen worden ($e).'));
      return;
    }
    if (!mounted) return;
    final replace = await _askRestore(backup);
    if (replace == null || !mounted) return;
    final (restored, skipped) = s.user.restoreRows(backup.tables, replace: replace);
    s.reloadFromDisk();
    _snack(
      replace
          ? tr('Backup restored: $restored items.', 'Back-up teruggezet: $restored items.')
          : tr(
              'Backup merged: $restored items added, $skipped already here.',
              'Back-up samengevoegd: $restored items toegevoegd, $skipped stonden er al.',
            ),
    );
  }

  void _problem(String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Cannot restore this file', 'Dit bestand kan niet teruggezet worden')),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('OK', 'OK')))],
    ),
  );

  /// Vraagt wat er moet gebeuren: true = vervangen, false = samenvoegen, null = niets.
  Future<bool?> _askRestore(Backup b) async {
    final at = b.exportedAt;
    final parts = [
      if (b.count('diary') > 0) tr('${fmtInt(b.count('diary'))} diary items', '${fmtInt(b.count('diary'))} dagboekregels'),
      if (b.count('foods') > 0) tr('${fmtInt(b.count('foods'))} own and saved foods', '${fmtInt(b.count('foods'))} eigen en bewaarde producten'),
      if (b.count('meals') > 0) tr('${fmtInt(b.count('meals'))} saved meals', '${fmtInt(b.count('meals'))} opgeslagen maaltijden'),
      if (b.count('biometrics') > 0) tr('${fmtInt(b.count('biometrics'))} measurements', '${fmtInt(b.count('biometrics'))} metingen'),
      if (b.count('exercise') > 0) tr('${fmtInt(b.count('exercise'))} workouts', '${fmtInt(b.count('exercise'))} keer beweging'),
      if (b.count('labs') > 0) tr('${fmtInt(b.count('labs'))} blood values', '${fmtInt(b.count('labs'))} bloedwaarden'),
      if (b.count('settings') > 0) tr('your settings, targets, plan and supplements', 'je instellingen, doelen, planning en supplementen'),
    ];
    final choice = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Restore from backup?', 'Back-up terugzetten?')),
        content: Text(
          [
            if (at != null)
              tr(
                'Backup from ${DateFormat('d MMMM y, HH:mm', appLocale).format(at.toLocal())}.',
                'Back-up van ${DateFormat('d MMMM y, HH:mm', appLocale).format(at.toLocal())}.',
              ),
            parts.isEmpty ? tr('This backup is empty.', 'Deze back-up is leeg.') : '${tr('It contains', 'Erin staan')} ${parts.join(', ')}.',
            '',
            tr(
              'Merge: adds everything from the backup that is missing here. Nothing here is overwritten.',
              'Samenvoegen: voegt alles uit de back-up toe wat hier ontbreekt. Niets van hier wordt overschreven.',
            ),
            tr(
              'Replace: removes what is here now and puts the backup in its place.',
              'Vervangen: wist wat hier nu staat en zet de back-up in de plaats.',
            ),
            tr('With an account, the result also goes to your other devices.', 'Met een account gaat het resultaat ook naar je andere toestellen.'),
          ].join('\n'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: ctx.pal.high),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Replace', 'Vervangen')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Merge', 'Samenvoegen'))),
        ],
      ),
    );
    if (choice != true || !mounted) return choice;
    // Vervangen wist gegevens: nog één keer bevestigen
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Replace all your data?', 'Al je gegevens vervangen?')),
        content: Text(
          tr(
            'Your current diary, foods, measurements and everything else are removed and replaced by the backup. '
                'Tip: first use "Export everything" to keep a copy of what is here now.',
            'Je huidige dagboek, producten, metingen en al de rest worden gewist en vervangen door de back-up. '
                'Tip: gebruik eerst "Alles exporteren" om een kopie te bewaren van wat hier nu staat.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.pal.high),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Replace', 'Vervangen')),
          ),
        ],
      ),
    );
    return sure == true ? true : null;
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
                children: [
                  _language(s, pal),
                  const SizedBox(height: 10),
                  const AccountCard(),
                  const SizedBox(height: 10),
                  const ProTile(),
                  const SizedBox(height: 10),
                  const MacroScheduleCard(),
                  const SizedBox(height: 10),
                  _settings(s, pal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Taal helemaal bovenaan: wie de app in de verkeerde taal krijgt, moet ze vinden zonder te scrollen (N01). De
  /// titel staat in beide talen, want je leest misschien de andere.
  Widget _language(AppState s, Palette pal) => Panel(
    shadow: false,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isNl ? 'Taal · Language' : 'Language · Taal',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: pal.ink),
        ),
        const SizedBox(height: 6),
        Segmented<AppLang>(height: 30, items: [for (final l in AppLang.values) (l, l.label)], selected: appLang.value, onChanged: s.setLanguage),
      ],
    ),
  );

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
                              // 24-uursnotatie, net als de rest van de app (geen AM/PM)
                              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
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
          title(tr('Appearance', 'Weergave')),
          Segmented<String>(
            height: 30,
            items: [('system', tr('System', 'Zoals toestel')), ('light', tr('Light', 'Licht')), ('dark', tr('Dark', 'Donker'))],
            selected: s.themeMode,
            onChanged: s.setThemeMode,
          ),
          const SizedBox(height: 12),
          const AccentPicker(),
          title(tr('Diary', 'Dagboek')),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('New day starts at', 'Nieuwe dag begint om')),
            subtitle: Text(
              tr(
                'Up late? Until this time, what you eat still counts for the day before, including its Nutrient score.',
                'Laat op? Tot dit uur telt wat je eet nog voor de dag ervoor, ook voor de Voedingsscore.',
              ),
            ),
            trailing: DropdownButton<int>(
              value: dayStartHour,
              underline: const SizedBox.shrink(),
              items: [for (var h = 0; h <= 5; h++) DropdownMenuItem(value: h, child: Text(h == 0 ? tr('midnight', 'middernacht') : '0$h:00'))],
              onChanged: (h) => h == null ? null : s.setDayStart(h),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Keep an eye on sugar', 'Let op suiker')),
            subtitle: Text(
              tr(
                'Handy with diabetes: carbs, sugars and free sugars first on Today, and sugar per day in the week overview.',
                'Handig bij diabetes: koolhydraten, suikers en vrije suikers eerst bij Vandaag, en suiker per dag in het weekoverzicht.',
              ),
            ),
            value: s.sugarFocus,
            onChanged: s.setSugarFocus,
          ),
          title(tr('Exercise', 'Beweging')),
          // Gewone ListTile met losse schakelaar: onderaan het scherm zette een tik ergens op de brede rij
          // hem per ongeluk om; nu wisselt alleen de schakelaar zelf.
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Add burned energy to your goal', 'Verbrande energie bij je doel optellen')),
            subtitle: Text(
              tr(
                'Only what you burn above your activity level is added (that level already includes some exercise), so training never counts twice. Also with a custom energy goal.',
                'Alleen wat je verbrandt boven je activiteitsniveau komt erbij (dat niveau rekent al wat beweging in), zodat een training nooit dubbel telt. Ook bij een eigen energiedoel.',
              ),
            ),
            trailing: Switch(
              value: s.settings.addExercise,
              onChanged: (v) => s.saveSettings(s.settings.copyWith(addExercise: v)),
            ),
          ),
          if (HealthSync.supported) ...[title('Health Connect'), const _HealthConnectTile()],
          title(tr('Water', 'Water')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Track water', 'Water bijhouden')),
            subtitle: Text(
              tr(
                'Off: water is hidden from your goals, lists and Nutrient score, so you can focus on food.',
                'Uit: water verdwijnt uit je doelen, lijsten en Voedingsscore, zodat je je op voeding kunt focussen.',
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
          // Even brede knoppen onder elkaar, met de uitleg direct onder de knop waar ze bij hoort.
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(tr('Export diary (CSV)', 'Dagboek exporteren (CSV)')),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'All days with date, time, meal, amount and every nutrient. Opens in Excel.',
              'Alle dagen met datum, tijd, maaltijd, hoeveelheid en elke voedingsstof. Opent in Excel.',
            ),
            style: TextStyle(fontSize: 12, color: pal.ink3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _exportAll,
              icon: const Icon(Icons.archive_outlined, size: 18),
              label: Text(tr('Export everything (backup)', 'Alles exporteren (back-up)')),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'One file with your diary, own foods, recipes, meals, measurements, supplements, blood values, exercise, '
                  'plan, shopping list and settings. Keep it somewhere safe.',
              'Eén bestand met je dagboek, eigen producten, recepten, maaltijden, metingen, supplementen, bloedwaarden, '
                  'beweging, planning, boodschappenlijst en instellingen. Bewaar het op een veilige plek.',
            ),
            style: TextStyle(fontSize: 12, color: pal.ink3),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: Text(tr('Restore from backup', 'Back-up terugzetten')),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportScreen())),
              icon: const Icon(Icons.upload_rounded, size: 18),
              label: Text(tr('Import from Cronometer or MyFitnessPal', 'Importeren uit Cronometer of MyFitnessPal')),
            ),
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
              'No access. Install Health Connect and allow MacroMatrix to read steps, weight, body composition and exercise.',
              'Geen toegang. Installeer Health Connect en geef MacroMatrix toestemming om stappen, gewicht, lichaamssamenstelling en beweging te lezen.',
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

/// Kleur van de app: petrol (standaard, gratis) of een extra kleur met Pro. Zonder Pro staan de extra kleuren er
/// met een slotje; een tik opent het Pro-scherm.
class AccentPicker extends StatelessWidget {
  const AccentPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final pal = context.pal;
    final isPro = proOf(context)?.isPro ?? false;
    final current = effectiveAccent(s.accent, pro: isPro);
    final b = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(tr('Colour', 'Kleur'), style: TextStyle(fontSize: 13, color: pal.ink2)),
            const SizedBox(width: 8),
            const ProTag(),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            for (final a in accents)
              Builder(
                builder: (context) {
                  final locked = a.pro && !isPro;
                  final on = a.id == current;
                  return Semantics(
                    button: true,
                    selected: on,
                    label: locked ? tr('${a.name} (Pro)', '${a.name} (Pro)') : a.name,
                    child: Tooltip(
                      message: locked ? tr('${a.name} · with Pro', '${a.name} · met Pro') : a.name,
                      child: InkResponse(
                        key: ValueKey('accent-${a.id}'),
                        radius: 24,
                        onTap: () => locked ? openProScreen(context) : s.setAccent(a.id),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: a.brandFor(b),
                            shape: BoxShape.circle,
                            border: Border.all(color: on ? pal.ink : Colors.transparent, width: 2.5),
                          ),
                          alignment: Alignment.center,
                          child: on
                              ? Icon(Icons.check_rounded, size: 18, color: b == Brightness.dark ? a.darkOn : Colors.white)
                              : locked
                              ? Icon(
                                  Icons.lock_outline_rounded,
                                  size: 15,
                                  color: (b == Brightness.dark ? a.darkOn : Colors.white).withValues(alpha: 0.9),
                                )
                              : null,
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
