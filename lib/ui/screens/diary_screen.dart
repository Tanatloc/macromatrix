import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../data/user_db.dart';
import '../../nutrition/insights.dart';
import '../../nutrition/targets.dart';
import '../../nutrition/nutrients.dart';
import '../../platform/platform.dart';
import '../../state/app_state.dart';
import '../theme.dart';
import '../widgets/kit.dart';
import 'add_food_screen.dart';
import 'dashboard_screen.dart';
import 'food_detail_screen.dart';
import 'nutrient_detail_screen.dart';
import 'nutrients_screen.dart';
import 'planner_screen.dart';
import 'profile_screen.dart';
import 'scan_screen.dart';
import 'supplements_screen.dart';
import 'recap_screen.dart';
import 'weekly_report_screen.dart';
import '../../nutrition/allergens.dart';
import '../widgets/allergen_picker.dart';
import '../widgets/bio_tips_view.dart';
import '../widgets/exercise_view.dart';
import '../widgets/challenges_view.dart';
import '../widgets/gap_plan_view.dart';
import '../widgets/guest_nudge.dart';
import '../widgets/info_tip.dart';
import '../widgets/nutrient_row.dart';
import '../../i18n.dart';
import '../widgets/number_input.dart';
import '../widgets/undo.dart';

/// Vandaag: energie en macro's, de 25 vitaminen en mineralen, wat aandacht vraagt, een suggestie,
/// de afgelopen week en de maaltijden.
/// Eén scrollpositie voor Vandaag op elke breedte: wordt het venster smaller of breder, dan zette de andere
/// indeling zich anders terug op een positie van lang geleden, halverwege Lunch of Supplementen (N81).
const _diaryListKey = PageStorageKey('diary-list');

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key, this.onOpenNutrients, this.onOpenProfile, this.onOpenWeek});
  final VoidCallback? onOpenNutrients;
  final VoidCallback? onOpenProfile;

  /// "Laatste 7 dagen": het dashboard op Week (in de shell het tabblad Dashboard).
  final VoidCallback? onOpenWeek;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(valueListenable: _selection, builder: (context, _, _) => _build(context));

  Widget _build(BuildContext context) {
    final s = context.watch<AppState>();
    final empty = !s.entries.any((e) => !e.foodRef.startsWith('supp:'));
    // 'Profiel invullen' en 'Doelen' horen bij de doelen, niet bovenaan het Profiel bij je level (P03)
    // Op een gsm een apart Doelen-scherm met terugpijl, in plaats van halverwege het Profiel te landen (N83)
    final onOpenProfile = this.onOpenProfile == null
        ? null
        : () {
            if (!isDesktop(context)) {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen(goalsOnly: true)));
              return;
            }
            this.onOpenProfile!();
            showProfileGoals();
          };
    if (isDesktop(context)) {
      return _DesktopDiary(empty: empty, onOpenNutrients: onOpenNutrients, onOpenProfile: onOpenProfile, onOpenWeek: onOpenWeek);
    }
    final selected = _selectedIn(s);
    final size = MediaQuery.sizeOf(context);
    // De kop met de dag blijft altijd staan. De samenvatting blijft alleen staan op een hoog scherm (tablet);
    // op een gsm nam ze zo'n 40% van het scherm in en ving ze tikken op, dus daar scrolt ze mee.
    final sticky = size.height >= 900;
    // Op een gsm zit de +-knop in de navigatie onderaan. Vanaf de rail (800) staan Toevoegen en de kalender in de
    // kop: een zwevende knop lag daar over de kcal-kolom, want naast de lijst is er amper rand (N81).
    final wide = size.width >= 800;
    const gap = SizedBox(height: 12);
    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: _SummaryPager(onOpenNutrients: onOpenNutrients, onOpenProfile: onOpenProfile),
    );
    final list = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!s.hasProfile) ...[_ProfileHint(onOpenProfile: onOpenProfile), gap],
          if (empty && s.isToday) ...[const _StartCard(), gap],
          if (s.note.trim().isNotEmpty) ...[const _NoteCard(), gap],
          if (s.planFor(s.day).isNotEmpty) ...[const _PlanCard(), gap],
          if (s.isToday) const ChallengeTodayStrip(),
          if (s.isToday) const _UsualStrip(),
          for (final meal in Meal.values) ...[_MealCard(key: ValueKey('${s.day}-${meal.name}'), meal: meal), const SizedBox(height: 8)],
          const SizedBox(height: 4),
          const _SupplementCard(),
          const SizedBox(height: 8),
          const _ExerciseCard(),
          // Alles wat geen loggen is, komt onder de maaltijden
          if (s.isToday && s.hasProfile && !s.allergiesAsked) ...[const SizedBox(height: 20), const _AllergyAsk()],
          if (s.isToday && WeeklyReportCard.shouldShow(s)) ...[gap, const WeeklyReportCard()],
          if (s.isToday && RecapCard.due(s) != null) ...[gap, const RecapCard()],
          if (s.isToday && GuestNudgeCard.shouldShow(context, s)) ...[gap, const GuestNudgeCard()],
          if (!empty) ...[
            const SizedBox(height: 20),
            const _ForTodayCard(),
            if (s.isToday && s.suggestion != null) ...[gap, _SuggestionCard(suggestion: s.suggestion!)],
            gap,
            _WeekCard(onOpen: onOpenWeek),
          ],
        ],
      ),
    );
    return Scaffold(
      bottomNavigationBar: selected.isEmpty ? null : _SelectionBar(entries: selected),
      body: SafeArea(
        bottom: false,
        child: Narrow(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DayBar(wide: wide),
              if (sticky) summary,
              Expanded(
                child: ListView(
                  // Scrollpositie bewaren over een herbouw (na bewerken, verplaatsen of een notitie opslaan)
                  // Dezelfde sleutel als op een pc: bij een andere indeling geen oude positie van vroeger (N81)
                  key: _diaryListKey,
                  padding: EdgeInsets.only(top: sticky ? 2 : 0, bottom: 24),
                  children: [if (!sticky) summary, list],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kop van het dagboek op een gsm: ‹ dag › in het midden. Tik op de dag voor de kalender;
/// links je reeks, rechts de notitie.
class _DayBar extends StatelessWidget {
  const _DayBar({this.wide = false});

  /// Breed venster (rail): ook een kalenderknop en Toevoegen rechts.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final now = logicalNow();
    final today = DateTime(now.year, now.month, now.day);
    final diff = (s.date.difference(today).inHours / 24).round();
    final title = switch (diff) {
      0 => tr('Today', 'Vandaag'),
      -1 => tr('Yesterday', 'Gisteren'),
      1 => tr('Tomorrow', 'Morgen'),
      _ => toBeginningOfSentenceCase(DateFormat(s.date.year == today.year ? 'EEE d MMM' : 'd MMM yyyy', appLocale).format(s.date)),
    };
    final hasNote = s.note.trim().isNotEmpty;
    // Beide kanten even breed, zodat de dag in het midden blijft. Op een smal scherm (320) smallere kanten en
    // pijlen, anders kromp de dag tot ±13 px (N50).
    final small = !wide && MediaQuery.sizeOf(context).width < 400;
    final side = wide ? 250.0 : (small ? 72.0 : 88.0);
    final arrows = small ? VisualDensity.compact : null;
    return SizedBox(
      height: 58,
      child: Row(
        children: [
          SizedBox(
            width: side,
            child: diff == 0
                ? Padding(
                    padding: EdgeInsets.only(left: small ? 12 : 16),
                    child: const Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(fit: BoxFit.scaleDown, child: StreakFlame()),
                    ),
                  )
                : null,
          ),
          Expanded(
            // De titel krijgt een vaste ruimte tussen de pijlen, zodat die niet verschuiven als de datum langer wordt
            child: Row(
              children: [
                IconButton(
                  visualDensity: arrows,
                  tooltip: tr('Previous day', 'Vorige dag'),
                  icon: Icon(Icons.chevron_left_rounded, color: p.ink),
                  onPressed: () => s.shiftDay(-1),
                ),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => pickDay(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      // Op een smal scherm krimpt de datum liever dan dat hij afgekapt wordt ('Wo 21 o…')
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -0.3),
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: arrows,
                  tooltip: tr('Next day', 'Volgende dag'),
                  icon: Icon(Icons.chevron_right_rounded, color: p.ink),
                  onPressed: () => s.shiftDay(1),
                ),
              ],
            ),
          ),
          SizedBox(
            width: side,
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: wide ? 16 : 8),
                // Met een groter lettertype liever wat kleiner dan over de rand
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (wide)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Pick a day', 'Kies een dag'),
                          icon: Icon(Icons.calendar_today_outlined, size: 20, color: p.ink2),
                          onPressed: () => pickDay(context),
                        ),
                      IconButton(
                        visualDensity: wide ? VisualDensity.compact : null,
                        tooltip: tr('Note for this day', 'Notitie bij deze dag'),
                        icon: Icon(hasNote ? Icons.sticky_note_2_rounded : Icons.sticky_note_2_outlined, color: hasNote ? p.brand : p.ink2),
                        onPressed: () => editNote(context),
                      ),
                      IconButton(
                        visualDensity: wide ? VisualDensity.compact : null,
                        tooltip: tr('Day menu', 'Menu van de dag'),
                        icon: Icon(Icons.more_horiz_rounded, color: p.ink2),
                        onPressed: () => openDayMenu(context),
                      ),
                      if (wide) ...[
                        const SizedBox(width: 6),
                        FilledButton.icon(
                          onPressed: () => openAddFood(context, context.read<AppState>().suggestedMeal),
                          icon: const Icon(Icons.add_rounded),
                          label: Text(tr('Add', 'Toevoegen')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kalender om naar een andere dag te springen.
Future<void> pickDay(BuildContext context) async {
  final s = context.read<AppState>();
  final now = logicalNow();
  final picked = await showDatePicker(
    context: context,
    initialDate: s.date.isAfter(now) ? now : s.date,
    firstDate: DateTime(2000),
    // Niet in de toekomst loggen: tot en met vandaag
    lastDate: now,
    // "Vandaag" in de kalender is de dag van de app (die begint om 3 uur), niet de kalenderdag (SU-13)
    currentDate: now,
    // In de taal van de app, met de week vanaf maandag (N46)
    builder: (ctx, child) => Localizations.override(context: ctx, locale: pickerLocale, child: child!),
  );
  if (picked != null) s.setDate(picked);
}

/// Taal voor de kalender: die van de app, en altijd met de week vanaf maandag. Gewoon 'en' begint op zondag
/// (Amerikaans), dus Brits Engels; in het Nederlands nl_BE in plaats van de Engelse kalender van vroeger (N46).
Locale get pickerLocale => isNl ? const Locale('nl', 'BE') : const Locale('en', 'GB');

/// Een dag in een melding: today/yesterday/tomorrow, anders bv. 'Mon 20 Oct' (met jaar als het een ander jaar is).
String dayName(DateTime d) {
  final now = logicalNow();
  return switch (daysBetween(now, d)) {
    0 => tr('today', 'vandaag'),
    -1 => tr('yesterday', 'gisteren'),
    1 => tr('tomorrow', 'morgen'),
    _ => DateFormat(d.year == now.year ? 'EEE d MMM' : 'EEE d MMM yyyy', appLocale).format(d),
  };
}

bool _isRelative(DateTime d) => daysBetween(logicalNow(), d).abs() <= 1;

/// Gisteren kopiëren naar de gekozen dag: [meal], of zonder maaltijd de hele dag. Staat er al iets, dan eerst
/// vragen; hetzelfde product wordt één regel, en de melding heeft "Ongedaan maken" (N57).
Future<void> copyFromYesterday(BuildContext context, {Meal? meal}) {
  final s = context.read<AppState>();
  return _copyDayWithUndo(
    context,
    from: DateTime(s.date.year, s.date.month, s.date.day - 1),
    to: s.date,
    meal: meal,
    run: () => meal == null ? s.copyDayFromYesterday() : s.copyMealFromYesterday(meal),
  );
}

/// De hele dag [from] kopiëren naar [to] (standaard de gekozen dag), met dezelfde vraag en "Ongedaan maken" als
/// [copyFromYesterday] (N58).
Future<void> copyDay(BuildContext context, {required DateTime from, DateTime? to}) {
  final s = context.read<AppState>();
  final target = to ?? s.date;
  return _copyDayWithUndo(
    context,
    from: from,
    to: target,
    run: () => s.copyDay(from: from, to: target),
  );
}

Future<void> _copyDayWithUndo(
  BuildContext context, {
  required DateTime from,
  required DateTime to,
  Meal? meal,
  required List<AddedEntry> Function() run,
}) async {
  final s = context.read<AppState>();
  final toKey = dayKey(to);
  final toShown = toKey == s.day;
  // Wat er al staat op de dag waarnaar je kopieert (zonder supplementen, die worden niet gekopieerd)
  final onTarget = toShown ? s.entries : s.user.entriesBetween(toKey, toKey);
  final already = onTarget.where((e) => !e.foodRef.startsWith('supp:') && (meal == null || e.meal == meal)).length;
  final fromName = dayName(from), toName = dayName(to);
  if (already > 0) {
    final items = already == 1 ? 'item' : 'items';
    final where = meal != null
        ? meal.label.toLowerCase()
        : toShown
        ? tr('this day', 'deze dag')
        : toName;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          meal != null
              ? tr('${meal.label} already has $already $items', '${meal.label} heeft al $already $items')
              : toShown
              ? tr('This day already has $already $items', 'Deze dag heeft al $already $items')
              : tr(
                  '${toBeginningOfSentenceCase(toName)} already has $already $items',
                  '${toBeginningOfSentenceCase(toName)} heeft al $already $items',
                ),
        ),
        content: Text(
          tr(
            'The items of $fromName are added to $where. A product that is already there gets the amount added, not a second line.',
            'De items van $fromName komen erbij in $where. Een product dat er al staat, krijgt de hoeveelheid erbij, geen tweede regel.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Add anyway', 'Toch toevoegen'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  final added = run();
  if (!context.mounted) return;
  final m = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  if (added.isEmpty) {
    // 'gisteren' zonder 'op', een datum met: "You logged nothing yesterday" / "Op ma 20 okt logde je niets"
    final rel = _isRelative(from);
    final what = meal?.label.toLowerCase();
    m.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(switch ((what, rel)) {
          (null, true) => tr('You logged nothing $fromName.', '${toBeginningOfSentenceCase(fromName)} logde je niets.'),
          (null, false) => tr('You logged nothing on $fromName.', 'Op $fromName logde je niets.'),
          (_, true) => tr('You had no $what $fromName.', '${toBeginningOfSentenceCase(fromName)} had je geen $what.'),
          (_, false) => tr('You had no $what on $fromName.', 'Op $fromName had je geen $what.'),
        }),
      ),
    );
    return;
  }
  final n = added.length;
  final items = n == 1 ? 'item' : 'items';
  var armed = false;
  Timer(const Duration(milliseconds: 500), () => armed = true);
  // Korter dan de gewone melding (4-5 s): ze bedekte anders lang een regel van de maaltijd die je net kopieerde
  m.showSnackBar(
    SnackBar(
      persist: false,
      duration: const Duration(milliseconds: 4500),
      behavior: SnackBarBehavior.floating,
      // Naar de dag die je bekijkt: "van gisteren"; naar een andere dag: "naar morgen"
      content: Text(
        toShown
            ? tr('Copied $n $items from $fromName', '$n $items van $fromName gekopieerd')
            : tr('Copied $n $items to $toName', '$n $items gekopieerd naar $toName'),
      ),
      action: SnackBarAction(
        label: tr('Undo', 'Ongedaan maken'),
        onPressed: () {
          // Een snelle tweede tik op het menu is geen bewuste keuze (zie showUndo)
          if (!armed) return;
          s.undoAdds(added);
        },
      ),
    ),
  );
}

/// 'Kopieer dag van…': een eerdere dag kiezen. Alleen dagen waarop je iets logde zijn te kiezen, de rest staat
/// grijs; standaard gisteren, of anders de laatste gelogde dag daarvoor (N58).
Future<void> pickDayToCopyFrom(BuildContext context) async {
  final s = context.read<AppState>();
  final logged = s.user.loggedDays();
  final earlier = logged.where((d) => d.compareTo(s.day) < 0).toList()..sort();
  if (earlier.isEmpty) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(tr('No earlier day has items yet.', 'Er is nog geen eerdere dag met items.'))));
    return;
  }
  final yesterday = DateTime(s.date.year, s.date.month, s.date.day - 1);
  final picked = await showDatePicker(
    context: context,
    initialDate: logged.contains(dayKey(yesterday)) ? yesterday : DateTime.parse(earlier.last),
    firstDate: DateTime.parse(earlier.first),
    lastDate: yesterday,
    selectableDayPredicate: (d) => logged.contains(dayKey(d)),
    currentDate: logicalNow(),
    helpText: tr('Copy day from', 'Kopieer dag van'),
    builder: (ctx, child) => Localizations.override(context: ctx, locale: pickerLocale, child: child!),
  );
  if (picked != null && context.mounted) await copyDay(context, from: picked);
}

/// 'Kopieer deze dag naar…': standaard de dag erna, maar elke andere dag kan ook (N58).
Future<void> pickDayToCopyTo(BuildContext context) async {
  final s = context.read<AppState>();
  final today = logicalNow();
  final from = s.date;
  final next = DateTime(from.year, from.month, from.day + 1);
  final last = DateTime(today.year, today.month, today.day + 60);
  final picked = await showDatePicker(
    context: context,
    initialDate: next,
    firstDate: DateTime(today.year - 2),
    lastDate: next.isAfter(last) ? next : last,
    selectableDayPredicate: (d) => dayKey(d) != dayKey(from),
    currentDate: today,
    helpText: tr('Copy this day to', 'Kopieer deze dag naar'),
    builder: (ctx, child) => Localizations.override(context: ctx, locale: pickerLocale, child: child!),
  );
  if (picked != null && context.mounted) await copyDay(context, from: from, to: picked);
}

/// Menu van de dag: een hele dag kopiëren, van een eerdere dag, of naar morgen of een andere dag (N58).
Future<void> openDayMenu(BuildContext context) async {
  final s = context.read<AppState>();
  final hasItems = s.entries.any((e) => !e.foodRef.startsWith('supp:'));
  final from = s.date;
  final next = DateTime(from.year, from.month, from.day + 1);
  final v = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.content_copy_rounded),
            title: Text(tr('Copy day from…', 'Kopieer dag van…')),
            subtitle: Text(tr('Pick an earlier day with items', 'Kies een eerdere dag met items')),
            onTap: () => Navigator.pop(ctx, 'from'),
          ),
          if (hasItems) ...[
            ListTile(
              leading: const Icon(Icons.redo_rounded),
              title: Text(tr('Copy this day to ${dayName(next)}', 'Kopieer deze dag naar ${dayName(next)}')),
              onTap: () => Navigator.pop(ctx, 'next'),
            ),
            ListTile(
              leading: const Icon(Icons.event_outlined),
              title: Text(tr('Copy this day to…', 'Kopieer deze dag naar…')),
              onTap: () => Navigator.pop(ctx, 'to'),
            ),
          ],
        ],
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'from':
      await pickDayToCopyFrom(context);
    case 'next':
      await copyDay(context, from: from, to: next);
    case 'to':
      await pickDayToCopyTo(context);
  }
}

/// Vandaag op een pc: links wat je logt (maaltijden, supplementen, beweging), rechts hoe je dag ervoor staat
/// (energie, tips, wat je nog tekortkomt en je week). Toevoegen staat bovenaan in plaats van als zwevende knop.
class _DesktopDiary extends StatelessWidget {
  const _DesktopDiary({required this.empty, this.onOpenNutrients, this.onOpenProfile, this.onOpenWeek});
  final bool empty;
  final VoidCallback? onOpenNutrients;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onOpenWeek;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    const gap = SizedBox(height: 12);
    final selected = _selectedIn(s);
    return Scaffold(
      bottomNavigationBar: selected.isEmpty ? null : _SelectionBar(entries: selected),
      body: LayoutBuilder(
        builder: (context, c) {
          final two = c.maxWidth >= twoColumnWidth;
          final log = <Widget>[
            if (!s.hasProfile) ...[_ProfileHint(onOpenProfile: onOpenProfile), gap],
            if (s.isToday && s.hasProfile && !s.allergiesAsked) ...[const _AllergyAsk(), gap],
            if (s.isToday && WeeklyReportCard.shouldShow(s)) ...[const WeeklyReportCard(), gap],
            if (s.isToday && RecapCard.due(s) != null) ...[const RecapCard(), gap],
            if (s.isToday && GuestNudgeCard.shouldShow(context, s)) ...[const GuestNudgeCard(), gap],
            if (s.note.trim().isNotEmpty) ...[const _NoteCard(), gap],
            if (s.planFor(s.day).isNotEmpty) ...[const _PlanCard(), gap],
            SectionHeader(tr('Meals', 'Maaltijden'), trailing: empty ? null : '${fmtInt(s.totals['energy'])} kcal'),
            if (s.isToday) ...[const ChallengeTodayStrip(), const _UsualStrip(), const SizedBox(height: 8)],
            for (final meal in Meal.values) ...[_MealCard(key: ValueKey('${s.day}-${meal.name}'), meal: meal), const SizedBox(height: 8)],
            const SizedBox(height: 8),
            const _SupplementCard(),
            const SizedBox(height: 10),
            const _ExerciseCard(),
            if (!empty && s.isToday && s.suggestion != null) ...[const SizedBox(height: 16), _SuggestionCard(suggestion: s.suggestion!)],
          ];
          // Rechts: eerst hoe je dag ervoor staat, dan de inzichten
          final summary = <Widget>[
            if (empty) ...[const _BudgetCard(), gap, const _StartCard()] else const _EnergyCard(),
          ];
          final insights = <Widget>[
            if (!empty) ...[const _ForTodayCard(), gap, _ShortfallCard(onOpenNutrients: onOpenNutrients), gap, _WeekCard(onOpen: onOpenWeek)],
          ];
          final status = <Widget>[
            ...summary,
            if (insights.isNotEmpty) ...[gap, ...insights],
          ];
          return ListView(
            key: _diaryListKey,
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              Narrow(
                maxWidth: wideMaxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      add: FilledButton.icon(
                        onPressed: () => openAddFood(context, context.read<AppState>().suggestedMeal),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(tr('Add food', 'Eten toevoegen')),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: two
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 7,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: log),
                                ),
                                const SizedBox(width: 20),
                                Expanded(
                                  flex: 5,
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: status),
                                ),
                              ],
                            )
                          // Eén kolom (bv. 1024 px met de zijbalk): zoals op een gsm eerst de samenvatting, dan de
                          // maaltijden en pas daarna de inzichten, niet de maaltijden helemaal onderaan (N31)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ...summary,
                                gap,
                                ...log,
                                if (insights.isNotEmpty) ...[const SizedBox(height: 20), ...insights],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Op een pc naast je dagboek: je Voedingsscore en de vitaminen en mineralen waar je vandaag nog onder zit.
class _ShortfallCard extends StatelessWidget {
  const _ShortfallCard({this.onOpenNutrients});
  final VoidCallback? onOpenNutrients;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final v = s.totals.values;
    final low = KeyNutrients.shortfalls(v, s.targets, limit: 8);
    final logged = s.entries.any((e) => !e.foodRef.startsWith('supp:'));
    final score = dayScore(v, s.targets, closed: s.dateClosed);
    return Panel(
      shadow: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(
            s.isToday ? tr('Still short today', 'Vandaag nog te weinig') : tr('Still short this day', 'Deze dag nog te weinig'),
            trailing: logged
                ? Text(
                    tr('Nutrient score $score', 'Voedingsscore $score'),
                    style: numStyle(12, weight: FontWeight.w600, color: p.ink2),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          if (low.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                tr('You reach all your vitamins and minerals today.', 'Je haalt vandaag al je vitaminen en mineralen.'),
                style: TextStyle(fontSize: 13.5, color: p.ink2),
              ),
            )
          else
            for (final (i, k) in low.indexed)
              NutrientRow(
                first: i == 0,
                nutrient: nutrientByKey[k]!,
                amount: v[k],
                target: s.targets[k],
                complete: !s.totals.incomplete.contains(k),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: nutrientByKey[k]!))),
              ),
          if (onOpenNutrients != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.dashboard_outlined, size: 18),
                label: Text(tr('All nutrients', 'Alle voedingsstoffen')),
                onPressed: onOpenNutrients,
              ),
            ),
        ],
      ),
    );
  }
}

Future<void> openAddFood(BuildContext context, Meal meal) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AddFoodScreen(meal: meal)));

/// ISO-weeknummer.
int isoWeek(DateTime d) {
  // In UTC rekenen: anders scheelt de overgang naar zomertijd een uur en valt de deling een dag te kort
  final day = DateTime.utc(d.year, d.month, d.day);
  final thursday = day.plusDays(4 - day.weekday);
  return thursday.difference(DateTime.utc(thursday.year)).inDays ~/ 7 + 1;
}

class _Header extends StatelessWidget {
  const _Header({this.add});

  /// Knop om eten toe te voegen (op een pc, in plaats van de zwevende knop).
  final Widget? add;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final now = logicalNow();
    final today = DateTime(now.year, now.month, now.day);
    final diff = (s.date.difference(today).inHours / 24).round();
    final title = switch (diff) {
      0 => tr('Today', 'Vandaag'),
      -1 => tr('Yesterday', 'Gisteren'),
      1 => tr('Tomorrow', 'Morgen'),
      _ => toBeginningOfSentenceCase(DateFormat('EEE d MMM', appLocale).format(s.date)),
    };
    final eyebrow = diff.abs() <= 1
        ? '${DateFormat('EEEE', appLocale).format(s.date)} · week ${isoWeek(s.date)}'
        : '${DateFormat('yyyy', appLocale).format(s.date)} · week ${isoWeek(s.date)}';
    return PageHeader(
      eyebrow: eyebrow,
      title: title,
      titleBadge: diff == 0 ? const StreakFlame() : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquareButton(
            icon: s.note.trim().isEmpty ? Icons.sticky_note_2_outlined : Icons.sticky_note_2_rounded,
            tooltip: tr('Note for this day', 'Notitie bij deze dag'),
            onPressed: () => editNote(context),
          ),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.chevron_left_rounded, tooltip: tr('Previous day', 'Vorige dag'), onPressed: () => s.shiftDay(-1)),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.calendar_today_outlined, tooltip: tr('Pick a day', 'Kies een dag'), onPressed: () => pickDay(context)),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.chevron_right_rounded, tooltip: tr('Next day', 'Volgende dag'), onPressed: () => s.shiftDay(1)),
          const SizedBox(width: 6),
          SquareButton(icon: Icons.more_horiz_rounded, tooltip: tr('Day menu', 'Menu van de dag'), onPressed: () => openDayMenu(context)),
          if (add != null) ...[const SizedBox(width: 12), SizedBox(height: 40, child: add)],
        ],
      ),
    );
  }
}

class _ProfileHint extends StatelessWidget {
  const _ProfileHint({this.onOpenProfile});
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Panel(
      shadow: false,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      onTap: onOpenProfile,
      child: Row(
        children: [
          Icon(Icons.tune_rounded, color: p.brand),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('Fill in your profile', 'Vul je profiel in'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                ),
                Text(
                  tr('Then your energy, vitamin and mineral goals will be right.', 'Dan kloppen je doelen voor energie, vitaminen en mineralen.'),
                  style: TextStyle(fontSize: 13, color: p.ink2),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.brand),
        ],
      ),
    );
  }
}

// ── Energie ──

class _EnergyCard extends StatelessWidget {
  const _EnergyCard({this.bare = false, this.macros = true});

  /// Zonder kaart eromheen (als pagina in de samenvatting).
  final bool bare;

  /// Met de macro's eronder (de samenvatting op een gsm toont die op een eigen pagina).
  final bool macros;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final eaten = s.totals['energy'];
    final budget = s.targets['energy']?.goal ?? 2000;
    final burned = s.exerciseKcalInGoal;
    final left = budget - eaten;
    // Tot 10% boven je doel is nog binnen de marge: geen rood, zoals in de weekgrafiek
    final over = left < 0 && !withinEnergyMargin(eaten, budget);
    final extra = left < 0 && !over;

    TextStyle label([bool strong = false]) => TextStyle(fontSize: 13, color: strong ? p.ink : p.ink2, fontWeight: strong ? FontWeight.w600 : null);
    Widget ledger(String name, String value, {Color? dot, Color? color, bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(name, style: label(strong))),
          Text(
            value,
            style: numStyle(13, weight: strong ? FontWeight.w600 : FontWeight.w400, color: color ?? p.ink),
          ),
        ],
      ),
    );

    final remaining = s.macrosRemaining;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 124,
              height: 124,
              child: CustomPaint(
                painter: _EnergyRing(eaten: eaten, budget: budget, burned: burned, p: p),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (burned > 0) ...[_BurnedPill(burned: burned), const SizedBox(height: 3)],
                      Text(fmtInt(left.abs()), style: numStyle(30, color: over ? p.high : p.ink, height: 1)),
                      const SizedBox(height: 4),
                      Text(
                        over ? tr('kcal over goal', 'kcal te veel') : (extra ? tr('kcal extra', 'kcal extra') : tr('kcal left', 'kcal te gaan')),
                        style: TextStyle(fontSize: 12, color: p.ink2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  ledger(tr('Goal', 'Doel'), fmtInt(budget - burned)),
                  // Ook beweging die niet bij het doel komt, met waarom: anders lijkt een training te verdwijnen (N17)
                  if (burned > 0 || s.burnedKcal >= 1)
                    InkWell(
                      onTap: () => openDayExercise(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ledger(tr('Exercise', 'Beweging'), '+${fmtInt(burned)}', dot: p.brand, color: p.brand),
                          if (s.burnedKcal - burned >= 1)
                            Padding(
                              padding: const EdgeInsets.only(left: 12, bottom: 2),
                              child: Text(
                                !s.settings.addExercise || s.adaptiveTdee != null
                                    ? tr('${fmtInt(s.burnedKcal)} kcal, not added', '${fmtInt(s.burnedKcal)} kcal, telt niet mee')
                                    : tr(
                                        '${fmtInt(s.burnedKcal - burned)} of ${fmtInt(s.burnedKcal)} kcal is in your activity level',
                                        '${fmtInt(s.burnedKcal - burned)} van ${fmtInt(s.burnedKcal)} kcal zit in je activiteitsniveau',
                                      ),
                                key: const ValueKey('exercise-in-activity'),
                                style: TextStyle(fontSize: 11, height: 1.3, color: p.ink3),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ledger(tr('Eaten', 'Gegeten'), fmtSigned(-eaten), dot: p.ink),
                  Divider(height: 10, color: p.line),
                  ledger(
                    over ? tr('Over goal', 'Te veel') : (extra ? tr('Extra, within margin', 'Extra, binnen marge') : tr('Left', 'Te gaan')),
                    fmtInt(left.abs()),
                    strong: true,
                    color: over ? p.high : null,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (macros) ...[
          const SizedBox(height: 16),
          Divider(color: p.line),
          const SizedBox(height: 4),
          // Gegeten of nog te gaan: één tik wisselt (en blijft onthouden)
          Row(
            children: [
              Expanded(child: Eyebrow(tr('Macros', 'Macro\'s'))),
              SizedBox(
                width: 156,
                child: Segmented<bool>(
                  height: 26,
                  fontSize: 11.5,
                  items: [(false, tr('Eaten', 'Gegeten')), (true, tr('To go', 'Nog te gaan'))],
                  selected: remaining,
                  onChanged: s.setMacrosRemaining,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Dezelfde rijen als de Doelen-pagina op een gsm: eiwit, koolhydraten, vet, en met "Let op suiker" de suikergrens
          for (final (key, name) in [
            ('protein', tr('Protein', 'Eiwit')),
            ('carbs', tr('Carbs', 'Koolhydraten')),
            ('fat', tr('Fat', 'Vet')),
            if (s.sugarFocus)
              if (s.targets['sugars']?.upper != null)
                ('sugars', tr('Sugars', 'Suikers'))
              else if (s.targets['free_sugars']?.upper != null)
                ('free_sugars', tr('Free sugars', 'Vrije suikers')),
          ])
            _MacroLine(name: name, amount: s.totals[key], target: s.targets[key], color: key.contains('sugars') ? p.macro('carbs') : p.macro(key), remaining: remaining),
        ],
      ],
    );
    return bare ? body : Panel(padding: const EdgeInsets.fromLTRB(18, 18, 18, 16), child: body);
  }
}

class _MacroLine extends StatelessWidget {
  const _MacroLine({required this.name, required this.amount, required this.target, required this.color, this.remaining = false});
  final String name;
  final double amount;
  final Target? target;
  final Color color;

  /// Toon wat er nog bij mag in plaats van wat je at.
  final bool remaining;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final goal = target?.goal ?? target?.upper ?? 0;
    // Boven het doel is alleen een waarschuwing bij een doel-om-ongeveer-te-halen (energie/koolh./vet) of een
    // bovengrens. Eiwit en vezels zijn "minstens": erboven is prima, niet rood "te veel".
    final tooMuch = levelOf(amount, target) == Level.high;
    final over = amount > goal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Row(
              children: [
                LegendItem.box(color, w: 7, h: 7),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // Te veel kleurt de balk rood, zoals op gsm en in het Dashboard (NW-15)
            child: Bar(fraction: goal <= 0 ? 0 : amount / goal, color: tooMuch ? p.highFill : color),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 86,
            child: Text.rich(
              remaining
                  ? TextSpan(
                      children: [
                        TextSpan(
                          text: over ? '+${fmtInt(amount - goal)}' : fmtInt(goal - amount),
                          style: TextStyle(color: tooMuch ? p.high : p.ink, fontWeight: FontWeight.w500),
                        ),
                        TextSpan(
                          text: over
                              ? (tooMuch ? tr(' g over', ' g te veel') : tr(' g extra', ' g extra'))
                              : tr(' g to go', ' g nog'),
                        ),
                      ],
                    )
                  : TextSpan(
                      children: [
                        TextSpan(
                          text: fmtInt(amount),
                          style: TextStyle(color: p.ink, fontWeight: FontWeight.w500),
                        ),
                        TextSpan(text: ' / ${fmtInt(goal)} g'),
                      ],
                    ),
              textAlign: TextAlign.right,
              style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              goal <= 0 ? '' : fmtPct(amount / goal),
              textAlign: TextAlign.right,
              style: numStyle(12, weight: FontWeight.w400, color: p.ink3),
            ),
          ),
        ],
      ),
    );
  }
}

/// "+337" in de ring: wat beweging vandaag bij je budget legt. Tik erop voor de activiteiten.
class _BurnedPill extends StatelessWidget {
  const _BurnedPill({required this.burned});
  final double burned;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.brandSoft,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => openDayExercise(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 2, 7, 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department_rounded, size: 12, color: p.brand),
              const SizedBox(width: 2),
              Text('+${fmtInt(burned)}', style: numStyle(11.5, color: p.brand)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ring van het energiebudget: gegeten in inkt; het deel dat beweging erbij gaf in de merkkleur;
/// wat je over het budget gaat in groen binnen ±10%, daarna in rood.
class _EnergyRing extends CustomPainter {
  _EnergyRing({required this.eaten, required this.budget, required this.burned, required this.p});
  final double eaten;
  final double budget;
  final double burned;
  final Palette p;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 9.0;
    final rect = (Offset.zero & size).deflate(stroke / 2 + 1);
    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = c;
    const start = -math.pi / 2;
    canvas.drawArc(rect, 0, math.pi * 2, false, arc(p.track)..strokeCap = StrokeCap.butt);
    if (budget <= 0) return;
    final b = (burned / budget).clamp(0, 1).toDouble();
    if (b > 0.01) canvas.drawArc(rect, start + math.pi * 2 * (1 - b), math.pi * 2 * b, false, arc(p.brand.withValues(alpha: 0.55)));
    final f = eaten / budget;
    if (f > 0) canvas.drawArc(rect, start, math.pi * 2 * math.min(1, f), false, arc(p.ink));
    // Erboven: binnen de marge van 10% groen, daarna rood (dezelfde regel als de weekgrafiek)
    if (f > 1) {
      canvas.drawArc(rect, start, math.pi * 2 * math.min(1, f - 1), false, arc(withinEnergyMargin(eaten, budget) ? p.okFill : p.highFill));
    }
  }

  @override
  bool shouldRepaint(_EnergyRing old) => old.eaten != eaten || old.budget != budget || old.burned != burned || old.p != p;
}

// ── Micronutriënten ──

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.suggestion});
  final Suggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    final x = suggestion;
    final amount = x.portion == null ? '${fmtInt(x.grams)} g' : '${x.portion!.label} (${fmtInt(x.grams)} g)';
    final meal = s.adviceMeal;
    return Panel(
      shadow: false,
      color: p.brandSoft,
      borderColor: p.brandSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_outlined, size: 13, color: p.brand),
              const SizedBox(width: 6),
              Eyebrow(
                x.mine ? tr('Biggest win · from what you eat', 'Grootste winst · uit wat je eet') : tr('Biggest win today', 'Grootste winst vandaag'),
                color: p.brand,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: amount,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: tr(' ${x.food.name} takes your ', ' ${x.food.name} brengt je ')),
                TextSpan(
                  text: tr(
                    '${inSentence(x.nutrient.name)} from ${fmtPct(x.before)} to ${fmtPct(x.after)}',
                    '${inSentence(x.nutrient.name)} van ${fmtPct(x.before)} naar ${fmtPct(x.after)}',
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (x.extra != null)
                  TextSpan(
                    text: tr(
                      ' and adds ${fmtPct(x.extra!.$2)} of your ${inSentence(x.extra!.$1.name)}',
                      ' en geeft ${fmtPct(x.extra!.$2)} van je ${inSentence(x.extra!.$1.name)} erbij',
                    ),
                  ),
                const TextSpan(text: '.'),
              ],
            ),
            style: TextStyle(fontSize: 15, height: 1.45, color: p.ink),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: p.brand,
                  foregroundColor: p.onBrand,
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontFamily: kSans, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FoodDetailScreen(food: x.food, meal: meal, initialGrams: x.grams, initialPortion: x.portion),
                  ),
                ),
                child: Text(tr('Add to ${meal.label.toLowerCase()}', 'Toevoegen aan ${meal.label.toLowerCase()}')),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: x.nutrient))),
                child: Text(tr('Other sources', 'Andere bronnen')),
              ),
            ],
          ),
          if (s.preferences.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              tr('Taking into account: ', 'Rekening gehouden met: ') + s.preferences.map((e) => e.label.toLowerCase()).join(', '),
              style: TextStyle(fontSize: 11.5, color: p.ink2),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Afgelopen 7 dagen ──

class _WeekCard extends StatelessWidget {
  const _WeekCard({this.onOpen});

  /// Het dashboard op Week openen; zonder (los dagboek) komt het als eigen scherm met een terugpijl.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final to = s.date;
    final from = to.plusDays(-6);
    final daily = s.dailyTotals(from, to);
    final days = [for (var i = 0; i < 7; i++) dayKey(from.plusDays(i))];
    // Elke dag met het doel dat toen gold (vroegere dagen zijn bevroren), niet met het doel van nu
    final perDay = s.targetsBetween(from, to);
    final targets = s.targetsForDate(to);
    List<double?> series(String key) => [for (final d in days) daily[d]?[key]];
    double goalOn(String d, String key) => perDay[d]?[key]?.goal ?? targets[key]?.goal ?? 0;
    final loggedDays = [
      for (final d in days)
        if (daily[d] != null) d,
    ];

    final energyGoal = targets['energy']?.goal ?? 2000;
    final proteinGoal = targets['protein']?.goal ?? 0;
    final kcal = series('energy');
    final protein = series('protein');
    final inBand = loggedDays.where((d) => (daily[d]!['energy'] - goalOn(d, 'energy')).abs() <= goalOn(d, 'energy') * 0.1).length;
    final proteinOk = loggedDays.where((d) => daily[d]!['protein'] >= goalOn(d, 'protein')).length;
    final logged = loggedDays.length;
    final proteinGoalText = goalNowEarlier([
      for (final d in days)
        if (daily[d] != null || d == days.last) goalOn(d, 'protein'),
    ], (g) => '${fmtInt(g)} g');

    return Panel(
      onTap: onOpen ?? () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DashboardScreen(startOnWeek: true))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelTitle(tr('Last 7 days', 'Laatste 7 dagen'), trailing: Icon(Icons.chevron_right_rounded, size: 18, color: p.ink3)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Spark(
                  label: tr('Energy avg.', 'Energie gem.'),
                  unit: 'kcal',
                  values: kcal,
                  target: energyGoal,
                  color: p.ink,
                  note: tr(
                    '$inBand of $logged ${logged == 1 ? 'day' : 'days'} within ±10%',
                    '$inBand van $logged ${logged == 1 ? 'dag' : 'dagen'} binnen ±10%',
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _Spark(
                  label: tr('Protein avg.', 'Eiwit gem.'),
                  unit: 'g',
                  values: protein,
                  target: proteinGoal,
                  color: p.protein,
                  note: tr(
                    'Goal $proteinGoalText · $proteinOk of $logged days',
                    'Doel $proteinGoalText · $proteinOk van $logged dagen',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Spark extends StatelessWidget {
  const _Spark({required this.label, required this.unit, required this.values, required this.target, required this.color, required this.note});
  final String label;
  final String unit;
  final List<double?> values;
  final double target;
  final Color color;
  final String note;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final known = values.whereType<double>().toList();
    final avg = known.isEmpty ? 0.0 : known.reduce((a, b) => a + b) / known.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(known.isEmpty ? '–' : fmtInt(avg), style: numStyle(20)),
            const SizedBox(width: 4),
            Text(unit, style: TextStyle(fontSize: 12, color: p.ink3)),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          width: double.infinity,
          child: CustomPaint(
            painter: _SparkPainter(values: values, target: target, color: color, guide: p.lineStrong),
          ),
        ),
        const SizedBox(height: 4),
        Text(note, style: TextStyle(fontSize: 11.5, color: p.ink3)),
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.values, required this.target, required this.color, required this.guide});
  final List<double?> values;
  final double target;
  final Color color;
  final Color guide;

  @override
  void paint(Canvas canvas, Size size) {
    final known = values.whereType<double>().toList();
    final all = [...known, target];
    final maxV = all.reduce(math.max) * 1.08;
    final minV = all.reduce(math.min) * 0.85;
    double y(double v) => maxV == minV ? size.height / 2 : size.height - (v - minV) / (maxV - minV) * size.height;
    final step = values.length <= 1 ? 0.0 : size.width / (values.length - 1);
    // Doellijn, gestippeld
    final ty = y(target);
    final dash = Paint()
      ..color = guide
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, ty), Offset(math.min(x + 3, size.width), ty), dash);
    }
    final path = Path();
    var started = false;
    Offset? last;
    for (final (i, v) in values.indexed) {
      if (v == null) continue;
      final o = Offset(i * step, y(v));
      started ? path.lineTo(o.dx, o.dy) : path.moveTo(o.dx, o.dy);
      started = true;
      last = o;
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    if (last != null) canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparkPainter old) => old.values != values || old.target != target || old.color != color;
}

// ── Lege dag ──

class _BudgetCard extends StatelessWidget {
  const _BudgetCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final t = s.targets;
    return Panel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 64,
            child: CustomPaint(painter: _EnergyRing(eaten: 0, budget: 1, burned: 0, p: p)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(s.isToday ? tr('Budget today', 'Budget vandaag') : 'Budget'),
                const SizedBox(height: 2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(fmtInt(t['energy']?.goal ?? 0), style: numStyle(26)),
                    const SizedBox(width: 5),
                    Text('kcal', style: TextStyle(fontSize: 13, color: p.ink2)),
                  ],
                ),
                Text(
                  tr(
                    '${fmtInt(t['protein']?.goal ?? 0)} g protein · ${fmtInt(t['carbs']?.goal ?? 0)} g carbs · ${fmtInt(t['fat']?.goal ?? 0)} g fat',
                    '${fmtInt(t['protein']?.goal ?? 0)} g eiwit · ${fmtInt(t['carbs']?.goal ?? 0)} g koolh. · ${fmtInt(t['fat']?.goal ?? 0)} g vet',
                  ),
                  style: numStyle(12, weight: FontWeight.w400, color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Waar een opgeslagen maaltijd heen gaat: de maaltijd waarbij hij bewaard werd, anders wat in de naam staat,
/// anders [fallback] (volgens het uur).
Meal savedMealTarget(SavedMeal m, Meal fallback) {
  final i = m.mealIndex;
  return i != null && i >= 0 && i < Meal.values.length ? Meal.values[i] : mealInName(m.name) ?? fallback;
}

/// Maaltijd die in de naam van een opgeslagen maaltijd staat ('Ontbijt', 'Lunch met eieren', 'Snacks'), of null.
/// Ook in een oude, aan elkaar geplakte naam ('DinnerChicken stir fry', N20).
@visibleForTesting
Meal? mealInName(String name) {
  final words = _unglue(name).toLowerCase().split(RegExp(r'[^a-zà-ÿ]+'));
  for (final w in words) {
    switch (w) {
      case 'breakfast' || 'ontbijt':
        return Meal.breakfast;
      case 'lunch' || 'middagmaal':
        return Meal.lunch;
      case 'dinner' || 'avondeten' || 'avondmaal' || 'diner' || 'supper':
        return Meal.dinner;
      case 'snack' || 'snacks' || 'tussendoortje':
        return Meal.snacks;
    }
  }
  return null;
}

/// Een kleine letter vlak voor een hoofdletter ('DinnerChicken') krijgt een spatie ertussen.
String _unglue(String name) => name.replaceAllMapped(RegExp(r'([a-zà-ÿ])([A-ZÀ-Ý])'), (m) => '${m[1]} ${m[2]}');

/// Naam van een opgeslagen maaltijd zonder de maaltijd die er vroeger vooraan aan plakte: 'BreakfastWeekday
/// porridge' wordt 'Weekday porridge' (P142, N20). Een gewone naam ('Lunch met eieren') blijft zoals hij is.
@visibleForTesting
String savedMealName(String name) {
  final m = RegExp(r'^(Breakfast|Lunch|Dinner|Snacks?|Ontbijt|Middagmaal|Avondeten|Avondmaal|Diner|Tussendoortje)(?=[A-ZÀ-Ý])')
      .firstMatch(name.trim());
  return m == null ? name.trim() : name.trim().substring(m.end);
}

/// Titel van een opgeslagen maaltijd op zijn kaart: de maaltijd waar hij heen gaat en de naam, gescheiden
/// ('Dinner · Chicken stir fry'). Heet hij gewoon zoals de maaltijd, dan alleen die.
@visibleForTesting
String savedMealTitle(SavedMeal m, Meal target) {
  final name = savedMealName(m.name);
  return name.toLowerCase() == target.label.toLowerCase() || mealInName(name) == target ? name : '${target.label} · $name';
}

class _StartCard extends StatelessWidget {
  const _StartCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final meal = context.read<AppState>().suggestedMeal;
    final yesterday = s.user
        .entriesFor(dayKey(s.date.plusDays(-1)))
        .where((e) => e.meal == meal && !e.foodRef.startsWith('supp:'))
        .toList();
    final saved = s.savedMeals();
    final yesterdayAll = s.user.entriesFor(dayKey(s.date.plusDays(-1))).where((e) => !e.foodRef.startsWith('supp:')).toList();

    Widget action({required IconData icon, required String title, required String sub, String meta = '', required VoidCallback onTap}) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: p.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: p.line),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: p.sunken, borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, size: 18, color: p.ink),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.ink2),
                      ),
                    ],
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    style: numStyle(12.5, weight: FontWeight.w400, color: p.ink3),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (var i = 0; i < 25; i++)
                  Opacity(
                    opacity: 1 - i * 0.025,
                    child: Panel(dashed: true, radius: 5, padding: EdgeInsets.zero, child: const SizedBox(width: 20, height: 22)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('Start your day', 'Begin je dag'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: p.ink),
          ),
          const SizedBox(height: 6),
          Text(
            tr(
              'After your first meal you\'ll see how close you are to all 25 vitamins and minerals, right here on Today.',
              'Na je eerste maaltijd zie je hier meteen hoe dicht je bij alle 25 vitaminen en mineralen zit.',
            ),
            style: TextStyle(fontSize: 14, height: 1.5, color: p.ink2),
          ),
          const SizedBox(height: 8),
          for (final m in saved.take(2))
            action(
              icon: Icons.restaurant_menu_rounded,
              title: savedMealTitle(m, savedMealTarget(m, meal)),
              sub: m.items.map((i) => i.name).join(' · '),
              meta: '${fmtInt(m.kcal)} kcal',
              onTap: () {
                // Een opgeslagen 'Ontbijt' hoort bij het ontbijt, ook als je het om 12 uur logt (P60, N20)
                final target = savedMealTarget(m, meal);
                final name = savedMealName(m.name);
                final added = s.addSavedMeal(m, target);
                showUndo(
                  context,
                  tr('$name added to ${target.label.toLowerCase()}', '$name toegevoegd aan ${target.label.toLowerCase()}'),
                  () => s.undoAdds(added),
                );
              },
            ),
          if (yesterday.isNotEmpty)
            action(
              icon: Icons.copy_rounded,
              title: tr('Yesterday\'s ${meal.label.toLowerCase()}', '${meal.label} van gisteren'),
              sub: tr(
                'Copy ${yesterday.length} ${yesterday.length == 1 ? 'item' : 'items'}',
                '${yesterday.length} ${yesterday.length == 1 ? 'item' : 'items'} kopiëren',
              ),
              meta: '${fmtInt(yesterday.fold<double>(0, (a, e) => a + e.kcal))} kcal',
              onTap: () => copyFromYesterday(context, meal: meal),
            ),
          if (yesterdayAll.map((e) => e.meal).toSet().length > 1)
            action(
              icon: Icons.content_copy_rounded,
              title: tr('Same as yesterday', 'Zoals gisteren'),
              sub: tr('Copy all ${yesterdayAll.length} items of yesterday', 'Alle ${yesterdayAll.length} items van gisteren kopiëren'),
              meta: '${fmtInt(yesterdayAll.fold<double>(0, (a, e) => a + e.kcal))} kcal',
              onTap: () => copyFromYesterday(context),
            ),
          if (canScanBarcodes)
            action(
              icon: Icons.qr_code_scanner_rounded,
              title: tr('Scan barcode', 'Barcode scannen'),
              sub: tr('Look up a branded product', 'Merkproduct opzoeken'),
              onTap: () async {
                final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScanScreen()));
                if (code == null || !context.mounted) return;
                final food = await s.lookupBarcode(code);
                if (food != null && context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => FoodDetailScreen(food: food, meal: meal),
                    ),
                  );
                }
              },
            )
          else
            action(
              icon: Icons.search_rounded,
              title: tr('Search', 'Zoeken'),
              sub: tr('Basic foods, brands and recipes', 'Basisvoedingsmiddelen, merken en recepten'),
              onTap: () => openAddFood(context, meal),
            ),
        ],
      ),
    );
  }
}

// ── Maaltijden ──

class _MealCard extends StatefulWidget {
  const _MealCard({super.key, required this.meal});
  final Meal meal;

  @override
  State<_MealCard> createState() => _MealCardState();
}

class _MealCardState extends State<_MealCard> {
  bool _open = true;

  Meal get meal => widget.meal;

  Future<void> _menu(String v) async {
    final s = context.read<AppState>();
    if (v == 'save') {
      final name = await _askName(context, meal);
      if (name != null && name.isNotEmpty) {
        s.saveMealFromDiary(name, meal);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                tr(
                  '"$name" saved. You\'ll find it under Add → Saved meals.',
                  '"$name" opgeslagen. Je vindt het bij Toevoegen → Opgeslagen maaltijden.',
                ),
              ),
            ),
          );
        }
      }
    }
    if (v == 'select') {
      _selection.value = {..._selection.value, for (final e in s.entriesFor(meal)) e.id};
    }
    if (v == 'copy' && mounted) await copyFromYesterday(context, meal: meal);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final entries = s.entriesFor(meal);

    // + en … zijn elk een eigen knop van 44 × 44 met ruimte ertussen. Zonder vaste maat liep de onzichtbare tikzone
    // van … over de + heen, en won … de tik op het midden van de + (N27).
    final buttonStyle = IconButton.styleFrom(
      minimumSize: const Size.square(kMinTapTarget),
      maximumSize: const Size.square(kMinTapTarget),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
    final add = IconButton(
      tooltip: tr('Add to ${meal.label.toLowerCase()}', 'Toevoegen aan ${meal.label.toLowerCase()}'),
      style: buttonStyle,
      icon: Icon(Icons.add_rounded, size: 20, color: entries.isEmpty ? p.ink2 : p.brand),
      onPressed: () => openAddFood(context, meal),
    );
    final menu = PopupMenuButton<String>(
      tooltip: tr('More', 'Meer'),
      icon: Icon(Icons.more_horiz_rounded, size: 20, color: p.ink3),
      style: buttonStyle,
      padding: EdgeInsets.zero,
      onSelected: _menu,
      itemBuilder: (_) => [
        PopupMenuItem(value: 'copy', child: Text(tr('Copy from yesterday', 'Kopieer van gisteren'))),
        if (entries.isNotEmpty) PopupMenuItem(value: 'save', child: Text(tr('Save as meal', 'Opslaan als maaltijd'))),
        if (entries.isNotEmpty) PopupMenuItem(value: 'select', child: Text(tr('Select all', 'Alles selecteren'))),
      ],
    );

    if (entries.isEmpty) {
      return Panel(
        dashed: true,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
        onTap: () => openAddFood(context, meal),
        child: Row(
          children: [
            Expanded(
              child: Text(
                meal.label,
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
              ),
            ),
            // Op een smal scherm met grote tekst korten we dit in, niet de knoppen
            Flexible(
              child: Text(
                tr('Nothing logged yet', 'Nog niets gelogd'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: p.ink2),
              ),
            ),
            const SizedBox(width: 2),
            add,
            const SizedBox(width: 8),
            menu,
          ],
        ),
      );
    }

    final kcal = entries.fold<double>(0, (a, e) => a + e.kcal);
    final times = entries.map((e) => e.time).whereType<String>().toList()..sort();
    final split = macroSplit(s.totalsFor(meal).values);

    return Panel(
      shadow: false,
      radius: 16,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        meal.label,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      if (times.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(
                          times.first,
                          style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                        ),
                      ],
                      const Spacer(),
                      Text(
                        fmtInt(kcal),
                        style: numStyle(13.5, weight: FontWeight.w500, color: p.ink),
                      ),
                      const SizedBox(width: 2),
                      add,
                      const SizedBox(width: 8),
                      menu,
                    ],
                  ),
                  if (!_open) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        entries.map((e) => e.name).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: p.ink2),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  Padding(padding: const EdgeInsets.only(right: 10), child: MacroSplitBar(split)),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_open
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final e in entries) _EntryRow(entry: e),
                      Divider(color: p.line),
                      TextButton.icon(
                        style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.fromLTRB(14, 6, 14, 10)),
                        onPressed: () => openAddFood(context, meal),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(tr('Add to ${meal.label.toLowerCase()}', 'Toevoegen aan ${meal.label.toLowerCase()}')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry});
  final DiaryEntry entry;

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    final e = entry;
    final selecting = _selection.value.isNotEmpty;
    final selected = _selection.value.contains(e.id);
    void toggle() {
      // Een melding onderaan zou over de selectiebalk vallen
      if (!selecting) ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _toggleSelected(e.id);
    }

    final row = InkWell(
      onTap: selecting
          ? toggle
          : () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => FoodDetailScreen(food: s.foodFor(e), meal: e.meal, entry: e),
              ),
            ),
      onLongPress: toggle,
      child: Container(
        padding: EdgeInsets.fromLTRB(selecting ? 4 : 14, 9, 16, 9),
        decoration: BoxDecoration(
          color: selected ? p.brandSoft : null,
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            if (selecting) Checkbox(value: selected, visualDensity: VisualDensity.compact, onChanged: (_) => toggle()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: p.ink),
                  ),
                  Text(
                    [?e.time, ?e.brand, _amountLabel(e)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: numStyle(11.5, weight: FontWeight.w400, color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              fmtInt(e.kcal),
              style: numStyle(12.5, weight: FontWeight.w400, color: p.ink2),
            ),
          ],
        ),
      ),
    );
    if (selecting) return row;

    // Veeg naar links: verwijderen. Veeg naar rechts: acties (verplaatsen, kopiëren, favoriet ...).
    return Dismissible(
      key: ValueKey(e.id),
      background: Container(
        color: p.brandSoft,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Icon(Icons.more_horiz_rounded, color: p.brand),
      ),
      secondaryBackground: Container(
        color: p.highSoft,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline_rounded, color: p.high),
      ),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.endToStart) return true;
        await _entryActions(context, [e]);
        return false;
      },
      onDismissed: (_) => _deleteWithUndo(context, [e]),
      child: row,
    );
  }

  static String _amountLabel(DiaryEntry e) {
    final g = '${_trim(e.grams)} g';
    final label = e.portionLabel == null ? null : portionInLang(e.portionLabel!);
    if (label == null) return g;
    // Een geschatte portie draagt haar grammen al in de naam ("1 slice (≈35 g)"): niet nog eens "(35 g)" erachter
    final hasGrams = RegExp(r'\d\s*(g|ml)\)').hasMatch(label);
    if (e.quantity == 1) return hasGrams ? label : '$label ($g)';
    return hasGrams ? '${_trim(e.quantity)} × $label · $g' : '${_trim(e.quantity)} × $label ($g)';
  }
}

String _trim(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).dec;

Future<String?> _askName(BuildContext context, Meal meal) {
  // Leeg beginnen met de maaltijd als hint: zo plakt een getypte naam niet aan 'Ontbijt' (P142),
  // en een lege naam wordt de (vertaalde) maaltijdnaam in plaats van 'Breakfast'.
  final c = TextEditingController();
  String result() => c.text.trim().isEmpty ? meal.label : c.text.trim();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Save meal', 'Maaltijd opslaan')),
      content: TextField(
        controller: c,
        autofocus: true,
        decoration: InputDecoration(labelText: tr('Name', 'Naam'), hintText: tr('e.g. ${meal.label} with eggs', 'bv. ${meal.label} met eieren')),
        onSubmitted: (_) => Navigator.pop(ctx, result()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, result()), child: Text(tr('Save', 'Opslaan'))),
      ],
    ),
  );
}

// ── Beweging en notitie ──

/// Beweging van de dag: verbrande energie telt (standaard) mee in je energiedoel.
/// Beweging toevoegen aan de gekozen dag: een activiteit en de duur, of zelf de kcal.
Future<void> addExercise(BuildContext context) async {
  final s = context.read<AppState>();
  // Leeg beginnen: de vorige activiteit staat klaar als "Opnieuw"-knop, niet al ingevuld (N66)
  final recent = s.recentExercises;
  Object? choice;
  final minutes = TextEditingController(text: '30');
  final kcal = TextEditingController();
  final name = TextEditingController();
  double? parse(TextEditingController c) => parseNum(c.text);
  ExerciseType? type() => choice is ExerciseType ? choice as ExerciseType : null;
  double estimate() => (type()?.met ?? 0) * s.currentWeight * (parse(minutes) ?? 0) / 60;
  // Ingevuld via "Opnieuw": die kcal schaalt mee met de duur, tot je de kcal zelf intypt
  Exercise? base;
  var kcalTyped = false;
  // Even na het openen van de activiteitenlijst: tikken op de velden eronder negeren (N30)
  var picking = false;
  String? activityError, minutesError, kcalError;
  final other = otherExercise(s);

  final ok = await showDialog<bool>(
    context: context,
    // Niet sluiten bij een tik naast het venster: je zou je ingevulde beweging verliezen (P10)
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) {
        void fillFrom(Exercise e) => setD(() {
          final t = exerciseTypes.where((t) => t.name == exerciseNameInLang(e.name)).firstOrNull;
          choice = t ?? _otherExercise;
          name.text = t == null ? e.name : '';
          minutes.text = e.minutes == null ? '' : fmtNum(e.minutes!, 0);
          kcal.text = '${e.kcal.round()}';
          base = e;
          kcalTyped = false;
          activityError = minutesError = kcalError = null;
        });

        Future<void> submit() async {
          final m = parse(minutes);
          final burned = parse(kcal) ?? estimate();
          activityError = choice == null && parse(kcal) == null ? tr('Choose an activity', 'Kies een activiteit') : null;
          minutesError = exerciseMinutesError(m, otherMinutes: other.minutes);
          kcalError = activityError != null
              ? null
              : burned <= 0
              ? tr('Enter how long or how many kcal you burned', 'Vul in hoe lang of hoeveel kcal je verbrandde')
              : exerciseKcalError(burned, m, otherKcal: other.kcal);
          if (activityError != null || minutesError != null || kcalError != null) return setD(() {});
          // Ongewone duur of verbranding: vragen terwijl het venster open blijft; "Aanpassen" laat je het getal
          // verbeteren in plaats van alles te sluiten (N41)
          if (!await confirmExercise(ctx, m, burned)) {
            if (ctx.mounted) selectAllOnTap((m ?? 0) > 300 ? minutes : kcal)();
            return;
          }
          if (ctx.mounted) Navigator.pop(ctx, true);
        }

        return AlertDialog(
          title: Text(tr('Add exercise', 'Beweging toevoegen')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (recent.isNotEmpty) ...[
                  Text(tr('Again', 'Opnieuw'), style: TextStyle(fontSize: 12.5, color: ctx.pal.ink3)),
                  const SizedBox(height: 6),
                  // Een tik vult de velden in; toevoegen doe je zelf, zodat je de duur nog kunt aanpassen (N19)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final e in recent)
                        ChoiceChip(
                          selected: base?.id == e.id,
                          showCheckmark: false,
                          label: Text(
                            e.minutes == null ? '${exerciseNameInLang(e.name)} · ${fmtInt(e.kcal)} kcal' : '${exerciseNameInLang(e.name)} · ${fmtNum(e.minutes!, 0)} min',
                            overflow: TextOverflow.ellipsis,
                          ),
                          onSelected: (_) => fillFrom(e),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<Object>(
                  initialValue: choice,
                  isExpanded: true,
                  hint: Text(tr('Choose an activity', 'Kies een activiteit')),
                  decoration: InputDecoration(labelText: tr('Activity', 'Activiteit'), errorText: activityError),
                  items: [
                    for (final t in exerciseTypes)
                      DropdownMenuItem(
                        value: t,
                        child: Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                    DropdownMenuItem(value: _otherExercise, child: Text(tr('Other (enter kcal yourself)', 'Andere (zelf kcal invullen)'))),
                  ],
                  onTap: () {
                    setD(() => picking = true);
                    Future<void>.delayed(const Duration(milliseconds: 450), () {
                      if (ctx.mounted) setD(() => picking = false);
                    });
                  },
                  onChanged: (v) => setD(() {
                    if (v == choice) return;
                    choice = v;
                    activityError = kcalError = null;
                    // Andere activiteit: de oude kcal past niet meer, tenzij je die zelf intypte (N30)
                    if (!kcalTyped) {
                      kcal.clear();
                      base = null;
                    }
                    if (v != _otherExercise) name.clear();
                  }),
                ),
                const SizedBox(height: 12),
                IgnorePointer(
                  ignoring: picking,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (choice == _otherExercise) ...[
                        TextField(
                          controller: name,
                          decoration: InputDecoration(labelText: tr('Name, e.g. "Spinning"', 'Naam, bv. "Spinning"')),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: minutes,
                        keyboardType: TextInputType.number,
                        inputFormatters: wholeInput,
                        onTap: selectAllOnTap(minutes),
                        decoration: InputDecoration(labelText: tr('Duration', 'Duur'), suffixText: 'min', errorText: minutesError, errorMaxLines: 3),
                        onChanged: (_) => setD(() {
                          minutesError = kcalError = null;
                          final m = parse(minutes), b = base, old = b?.minutes;
                          if (!kcalTyped && b != null && old != null && old > 0 && m != null) kcal.text = '${(b.kcal * m / old).round()}';
                        }),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: kcal,
                        keyboardType: TextInputType.number,
                        inputFormatters: wholeInput,
                        onTap: selectAllOnTap(kcal),
                        onChanged: (v) => setD(() {
                          kcalTyped = v.trim().isNotEmpty;
                          if (!kcalTyped) base = null;
                          kcalError = activityError = null;
                        }),
                        decoration: InputDecoration(
                          labelText: tr('Burned (empty = estimate)', 'Verbrand (leeg = schatting)'),
                          suffixText: 'kcal',
                          errorText: kcalError,
                          errorMaxLines: 3,
                          helperText: type() == null
                              ? null
                              : tr(
                                  'Estimate: ${estimate().round()} kcal (at ${fmtDec(s.currentWeight)} kg)',
                                  'Schatting: ${estimate().round()} kcal (bij ${fmtDec(s.currentWeight)} kg)',
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Cancel', 'Annuleren'))),
            FilledButton(onPressed: submit, child: Text(tr('Add', 'Toevoegen'))),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
  final m = parse(minutes);
  final burned = parse(kcal) ?? estimate();
  final label = type()?.name ?? (name.text.trim().isEmpty ? tr('Exercise', 'Beweging') : name.text.trim());
  if (!context.mounted) return;
  final before = {for (final x in s.exercise) x.id};
  s.addExercise(label, burned, minutes: m);
  // De beweging staat onderaan Vandaag, vaak buiten beeld: zeg dat ze erbij staat, met Ongedaan maken
  final added = s.exercise.where((x) => !before.contains(x.id)).firstOrNull;
  if (added == null || !context.mounted) return;
  final what = m == null || m <= 0 ? '$label · ${fmtInt(burned)} kcal' : '$label · ${fmtNum(m, 0)} min';
  showUndo(context, tr('$what added', '$what toegevoegd'), () => s.deleteExercise(added));
}

/// Keuze "Andere" in de activiteitenlijst (null betekent: nog niets gekozen).
const _otherExercise = Object();

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: PanelTitle(
              tr('Exercise', 'Beweging'),
              trailing: s.burnedKcal > 0
                  ? Text(
                      '${fmtInt(s.burnedKcal)} kcal',
                      style: numStyle(13, weight: FontWeight.w500, color: p.brand),
                    )
                  : null,
            ),
          ),
          for (final e in s.exercise) Padding(padding: const EdgeInsets.only(right: 4), child: ExerciseRow(e)),
          if (s.adaptiveTdee != null && s.exercise.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 10),
              child: Text(
                tr(
                  'Your goal follows your estimated expenditure; your usual activity is already included, so this is not added.',
                  'Je doel volgt je geschatte verbruik; daar zit je gewone beweging al in, dus dit komt er niet bij.',
                ),
                style: TextStyle(fontSize: 11.5, color: p.ink3),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 6)),
              onPressed: () => addExercise(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(tr('Add exercise', 'Beweging toevoegen')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Notitie bij de gekozen dag bewerken (onderaan het scherm).
Future<void> editNote(BuildContext context) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => const _NoteSheet());

class _NoteSheet extends StatefulWidget {
  const _NoteSheet();

  @override
  State<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends State<_NoteSheet> {
  late final _c = TextEditingController(text: context.read<AppState>().note);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(
              'Note for ${s.isToday ? 'today' : DateFormat('EEEE d MMMM', appLocale).format(s.date)}',
              'Notitie bij ${s.isToday ? 'vandaag' : DateFormat('EEEE d MMMM', appLocale).format(s.date)}',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _c,
            autofocus: true,
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: tr(
                'How did you feel, how did you sleep, anything special you ate, ...',
                'Hoe voelde je je, hoe sliep je, iets bijzonders gegeten, ...',
              ),
            ),
            onChanged: s.setNote,
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Done', 'Klaar'))),
        ],
      ),
    );
  }
}

/// De notitie van de dag, als er een is. Tik om te bewerken.
class _NoteCard extends StatelessWidget {
  const _NoteCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      onTap: () => editNote(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.sticky_note_2_outlined, size: 18, color: p.ink3),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.note,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, height: 1.4, color: p.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Je supplementen van de dag om aan te vinken.
class _SupplementCard extends StatelessWidget {
  const _SupplementCard();

  void _manage(BuildContext context) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SupplementsScreen()));

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final list = s.supplements;
    if (list.isEmpty) {
      return Panel(
        shadow: false,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => _manage(context),
        child: Row(
          children: [
            Icon(Icons.medication_outlined, size: 20, color: p.ink3),
            const SizedBox(width: 10),
            Expanded(
              child: Text(tr('Add supplements', 'Supplementen toevoegen'), style: TextStyle(fontSize: 14, color: p.ink2)),
            ),
            Icon(Icons.chevron_right_rounded, color: p.ink3),
          ],
        ),
      );
    }
    final taken = list.where(s.supplementTaken).length;
    return Panel(
      shadow: false,
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.medication_outlined, size: 20, color: p.ink),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr('Supplements', 'Supplementen'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
              Text(tr('$taken of ${list.length}', '$taken van ${list.length}'), style: TextStyle(fontSize: 12.5, color: p.ink3)),
              TextButton(onPressed: () => _manage(context), child: Text(tr('Manage', 'Beheren'))),
            ],
          ),
          for (final sup in list)
            // Material: anders valt het tikeffect weg achter de kaart
            Material(
              type: MaterialType.transparency,
              child: CheckboxListTile(
                contentPadding: const EdgeInsets.only(right: 8),
                controlAffinity: ListTileControlAffinity.leading,
                value: s.supplementTaken(sup),
                onChanged: (v) => s.setSupplementTaken(sup, v ?? false),
                title: Text(sup.name, style: TextStyle(fontSize: 14, color: p.ink)),
                subtitle: Text(sup.dose, style: TextStyle(fontSize: 12, color: p.ink3)),
              ),
            ),
        ],
      ),
    );
  }
}

/// "Usually for breakfast": wat je meestal eet op dit moment van de dag, met één tik toe te voegen.
/// Er staat een plan klaar voor deze dag: met één tik in het dagboek.
class _PlanCard extends StatelessWidget {
  const _PlanCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final items = s.planFor(s.day);
    final kcal = items.fold(0.0, (a, i) => a + i.item.kcal);
    return Panel(
      shadow: false,
      color: p.brandSoft,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.event_note_outlined, size: 20, color: p.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(
                    'Planned for this day: ${items.length} items, ${fmtInt(kcal)} kcal',
                    'Gepland voor deze dag: ${items.length} items, ${fmtInt(kcal)} kcal',
                  ),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 4,
            children: [
              TextButton(
                onPressed: () {
                  final n = s.logPlan(s.day);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$n items added.', '$n items toegevoegd.'))));
                },
                child: Text(tr('Put in diary', 'In dagboek zetten')),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlannerScreen(day: s.date))),
                child: Text(tr('View plan', 'Plan bekijken')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsualStrip extends StatelessWidget {
  const _UsualStrip();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final meal = context.read<AppState>().suggestedMeal;
    if (s.entriesFor(meal).isNotEmpty) return const SizedBox.shrink();
    final usual = s.usualFor(meal);
    if (usual.isEmpty) return const SizedBox.shrink();
    String amount(DiaryEntry e) => e.portionLabel == null
        ? '${fmtInt(e.grams)} g'
        : '${e.quantity == e.quantity.roundToDouble() ? e.quantity.round() : fmtDec(e.quantity, 2)} × ${portionInLang(e.portionLabel!)}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Panel(
        shadow: false,
        radius: 16,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.schedule_rounded, size: 18, color: p.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr('Usually for ${meal.label.toLowerCase()}', 'Meestal bij je ${meal.label.toLowerCase()}'),
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: p.ink),
                  ),
                ),
                if (usual.length > 1)
                  TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                    onPressed: () {
                      final added = [for (final e in usual) s.addAgain(e, meal)];
                      showUndo(
                        context,
                        tr(
                          '${added.length} items added to ${meal.label.toLowerCase()}',
                          '${added.length} items toegevoegd aan ${meal.label.toLowerCase()}',
                        ),
                        () => s.undoAdds(added),
                      );
                    },
                    child: Text(tr('Add all', 'Alles toevoegen')),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in usual)
                  ActionChip(
                    avatar: Icon(Icons.add_rounded, size: 18, color: p.brand),
                    label: Text('${e.name.split(',').first} · ${amount(e)}', overflow: TextOverflow.ellipsis),
                    onPressed: () {
                      final added = s.addAgain(e, meal);
                      showUndo(
                        context,
                        tr('${e.name} added to ${meal.label.toLowerCase()}', '${e.name} toegevoegd aan ${meal.label.toLowerCase()}'),
                        () => s.undoAdds([added]),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Je reeks naast de titel: oranje vlam met het aantal dagen. Grijs en omlijnd als je vandaag nog niets
/// logde en je reeks vanavond zou eindigen.
class StreakFlame extends StatelessWidget {
  const StreakFlame({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final streak = s.streak;
    final loggedToday = s.user.loggedDays().contains(dayKey(logicalNow()));
    final atRisk = !loggedToday && streak.current > 0;
    if (streak.current == 0) return const SizedBox.shrink();
    // Een tik legt de reeks uit (N39)
    return InfoTip(
      title: tr('Your streak', 'Je reeks'),
      message: [
        tr('You logged ${streak.current} days in a row.', 'Je logde ${streak.current} dagen op rij.'),
        if (atRisk)
          tr('You haven\'t logged anything today yet. Log something today to keep your streak.', 'Je logde vandaag nog niets. Log vandaag iets om je reeks te houden.')
        else
          tr('Log something every day to keep it going.', 'Log elke dag iets om ze te houden.'),
        tr('Longest streak: ${streak.longest} days.', 'Langste reeks: ${streak.longest} dagen.'),
      ].join('\n\n'),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 4, 11, 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: atRisk ? null : const LinearGradient(colors: [Color(0xFFFF8A00), Color(0xFFE5482D)]),
          color: atRisk ? p.surface2 : null,
          border: atRisk ? Border.all(color: p.carbs, width: 1.5) : null,
          boxShadow: atRisk ? null : [BoxShadow(color: const Color(0xFFFF6A00).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.local_fire_department_rounded, size: 20, color: atRisk ? p.carbs : Colors.white),
            const SizedBox(width: 3),
            Text('${streak.current}', style: numStyle(16, color: atRisk ? p.carbs : Colors.white)),
            // Geen uitroepteken meer: dat las als een waarschuwing en paste niet naast twee cijfers. De omlijnde, grijze
            // stijl toont al dat je vandaag nog moet loggen; een tik legt het uit (N39).
          ],
        ),
      ),
    );
  }
}

/// Eén keer vragen naar allergieën (voor wie zijn account aanmaakte voor deze vraag bestond).
class _AllergyAsk extends StatelessWidget {
  const _AllergyAsk();

  @override
  Widget build(BuildContext context) {
    final s = context.read<AppState>();
    final p = context.pal;
    return Panel(
      shadow: false,
      radius: 16,
      color: p.highSoft,
      borderColor: p.highSoft,
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      onTap: () {
        var picked = <Allergen>{};
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setSheet) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(tr('Your allergies', 'Je allergieën'), style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Text(
                      tr('Select only what you react to, e.g. just peanuts.', 'Duid alleen aan waarop je reageert, bv. enkel pinda.'),
                      style: TextStyle(fontSize: 13, color: ctx.pal.ink2),
                    ),
                    const SizedBox(height: 12),
                    AllergenPicker(selected: picked, onChanged: (v) => setSheet(() => picked = v)),
                    const SizedBox(height: 10),
                    Text(allergenNote, style: TextStyle(fontSize: 11.5, color: ctx.pal.ink3)),
                    const SizedBox(height: 14),
                    FilledButton(
                      onPressed: () {
                        s.setAllergies(picked);
                        Navigator.pop(ctx);
                      },
                      child: Text(picked.isEmpty ? tr('I have no allergies', 'Ik heb geen allergieën') : tr('Save', 'Bewaren')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: Row(
        children: [
          Icon(Icons.health_and_safety_outlined, color: p.high),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              tr('Do you have food allergies? Set them for warnings.', 'Heb je voedselallergieën? Stel ze in voor waarschuwingen.'),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
            ),
          ),
          IconButton(
            tooltip: tr('No allergies', 'Geen allergieën'),
            icon: Icon(Icons.close_rounded, size: 18, color: p.ink3),
            onPressed: () => s.setAllergies({}),
          ),
        ],
      ),
    );
  }
}

/// Eén kaart met de tips van de dag: wat je nog kunt eten en een tip voor de opname.
class _ForTodayCard extends StatelessWidget {
  const _ForTodayCard();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final hasTips = s.bioTipsToday.isNotEmpty;
    if (!s.isToday && !hasTips) return const SizedBox.shrink();
    return Panel(
      shadow: false,
      radius: 16,
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Eyebrow(s.isToday ? tr('For today', 'Voor vandaag') : tr('Tips', 'Tips')),
            ),
            if (s.isToday) const GapPlanButton(bare: true),
            if (s.isToday && hasTips) Divider(height: 1, indent: 14, endIndent: 14, color: p.line),
            if (hasTips) const BioTipLine(bare: true),
          ],
        ),
      ),
    );
  }
}

// ── Samenvatting bovenaan: veeg tussen energie, uitgelichte stoffen en je score ──

class _SummaryPager extends StatelessWidget {
  const _SummaryPager({this.onOpenNutrients, this.onOpenProfile});
  final VoidCallback? onOpenNutrients;
  final VoidCallback? onOpenProfile;

  static const pages = 4;

  /// Alle pagina's even hoog, zodat het dagboek eronder niet verspringt als je veegt.
  static const height = 198.0;

  static List<String> get _labels => [tr('Goals', 'Doelen'), tr('Energy', 'Energie'), tr('Highlighted', 'Uitgelicht'), tr('Score', 'Score')];

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final page = s.summaryPage.clamp(0, pages - 1);
    void go(int i) => s.setSummaryPage((i + pages) % pages);
    final body = switch (page) {
      1 => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_PageTitle(tr('Energy balance', 'Energiebalans')), const SizedBox(height: 14), const _EnergyCard(bare: true, macros: false)],
      ),
      2 => const _HighlightedPage(),
      3 => _ScorePage(onOpenNutrients: onOpenNutrients),
      _ => _GoalsPage(onOpenProfile: onOpenProfile),
    };
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 200) return;
          go(page + (v < 0 ? 1 : -1));
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              // Groter lettertype: meer plaats; wat dan nog niet past, valt weg in plaats van over de rand te lopen
              height: MediaQuery.textScalerOf(context).scale(height),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                layoutBuilder: (current, previous) => Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
                child: SingleChildScrollView(key: ValueKey(page), physics: const NeverScrollableScrollPhysics(), child: body),
              ),
            ),
            // Tabs met de naam van elke pagina in plaats van kleine bolletjes: groot genoeg om te raken (N50)
            Row(
              children: [
                for (var i = 0; i < pages; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == page,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => go(i),
                        child: SizedBox(
                          height: 44,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _labels[i],
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: i == page ? FontWeight.w700 : FontWeight.w500,
                                    color: i == page ? p.ink : p.ink3,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: i == page ? 22 : 0,
                                height: 3,
                                decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(2)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Kopregel van een pagina in de samenvatting: een label in hoofdletters links, iets rechts.
class _PageTitle extends StatelessWidget {
  const _PageTitle(this.label, {this.onTap, this.trailing});
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Eyebrow(label),
                if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: p.ink3),
              ],
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Doelen: energie en de drie macro's als "Eiwit - 105 / 205 g … 51%" met een balk eronder.
/// Rechtsboven wissel je tussen wat je at en wat er nog bij mag.
class _GoalsPage extends StatelessWidget {
  const _GoalsPage({this.onOpenProfile});
  final VoidCallback? onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final remaining = s.macrosRemaining;
    Widget row(String key, String name, String unit, Color color) {
      final v = s.totals[key];
      final t = s.targets[key];
      // Een eigen "hoogstens" (bv. koolhydraten of suikers bij diabetes) toont als maximum
      final limit = t?.isLimit ?? false;
      final goal = t?.goal ?? t?.upper ?? 0;
      final over = goal > 0 && v > goal;
      // Rood "te veel" alleen bij een doel-om-ongeveer (energie/koolh./vet) boven 110% of boven een bovengrens;
      // eiwit erboven is prima.
      final tooMuch = levelOf(v, t) == Level.high;
      final value = !remaining
          ? '${fmtInt(v)} / ${limit ? 'max ' : ''}${fmtInt(goal)} $unit'
          : limit
          ? (over
                ? tr('${fmtInt(v - goal)} $unit over your max', '${fmtInt(v - goal)} $unit boven je max')
                : tr('${fmtInt(goal - v)} $unit left', 'nog ${fmtInt(goal - v)} $unit ruimte'))
          : over
          ? (tooMuch
                ? tr('${fmtInt(v - goal)} $unit over', '${fmtInt(v - goal)} $unit te veel')
                : tr('${fmtInt(v - goal)} $unit extra', '${fmtInt(v - goal)} $unit extra'))
          : tr('${fmtInt(goal - v)} $unit to go', 'nog ${fmtInt(goal - v)} $unit');
      return Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                        ),
                        TextSpan(
                          text: '  $value',
                          style: numStyle(13, weight: FontWeight.w400, color: remaining && tooMuch ? p.high : p.ink2),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ),
                Text(
                  goal <= 0 ? '' : fmtPct(v / goal),
                  style: numStyle(12.5, weight: FontWeight.w500, color: tooMuch ? p.high : p.ink2),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Energie binnen ±10% groen, zoals in de weekgrafiek en de ring
            Bar(
              fraction: goal <= 0 ? 0 : v / goal,
              color: tooMuch ? p.highFill : (key == 'energy' && withinEnergyMargin(v, goal) ? p.okFill : color),
              height: 8,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageTitle(
          tr('Goals', 'Doelen'),
          onTap: onOpenProfile,
          trailing: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => s.setMacrosRemaining(!remaining),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Eyebrow(remaining ? tr('To go', 'Nog te gaan') : tr('Eaten', 'Gegeten')),
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz_rounded, size: 16, color: p.brand),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        row('energy', tr('Energy', 'Energie'), 'kcal', p.ink),
        row('protein', tr('Protein', 'Eiwit'), 'g', p.macro('protein')),
        row('carbs', tr('Carbs', 'Koolhydraten'), 'g', p.macro('carbs')),
        row('fat', tr('Fat', 'Vet'), 'g', p.macro('fat')),
        // "Let op suiker": ook de suikergrens hier, met je eigen grens voor alle suikers als je die hebt
        if (s.sugarFocus)
          if (s.targets['sugars']?.upper != null)
            row('sugars', tr('Sugars', 'Suikers'), 'g', p.macro('carbs'))
          else if (s.targets['free_sugars']?.upper != null)
            row('free_sugars', tr('Free sugars', 'Vrije suikers'), 'g', p.macro('carbs')),
      ],
    );
  }
}

/// Score: je Voedingsscore en de twee stoffen waar je het verst onder zit.
class _ScorePage extends StatelessWidget {
  const _ScorePage({this.onOpenNutrients});
  final VoidCallback? onOpenNutrients;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScoreCard(bare: true),
        const SizedBox(height: 6),
        for (final (i, k) in KeyNutrients.shortfalls(s.totals.values, s.targets, limit: 2).indexed)
          NutrientRow(
            first: i == 0,
            nutrient: nutrientByKey[k]!,
            amount: s.totals.values[k],
            target: s.targets[k],
            complete: !s.totals.incomplete.contains(k),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: nutrientByKey[k]!))),
          ),
      ],
    );
  }
}

/// 8 voedingsstoffen die je zelf kiest, compact in twee kolommen.
class _HighlightedPage extends StatelessWidget {
  const _HighlightedPage();

  Future<void> _choose(BuildContext context) async {
    final s = context.read<AppState>();
    final chosen = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HighlightPicker(initial: s.highlighted),
    );
    if (chosen != null) s.setHighlighted(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = context.pal;
    final keys = s.highlighted;
    Widget cell(String k) {
      final n = nutrientByKey[k]!;
      final t = s.targets[k];
      final v = s.totals.values[k] ?? 0;
      final goal = t?.goal ?? t?.upper;
      final level = levelOf(v, t);
      return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NutrientDetailScreen(nutrient: n))),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      n.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: p.ink),
                    ),
                  ),
                  Text(goal == null || goal <= 0 ? '–' : fmtPct(v / goal), style: numStyle(12, color: p.fillOf(level))),
                ],
              ),
              const SizedBox(height: 4),
              Bar(fraction: goal == null || goal <= 0 ? 0 : v / goal, color: p.fillOf(level)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PageTitle(
          tr('Highlighted', 'Uitgelicht'),
          trailing: TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
            onPressed: () => _choose(context),
            child: Text(tr('Choose', 'Kiezen')),
          ),
        ),
        for (var i = 0; i < keys.length; i += 2)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cell(keys[i])),
              const SizedBox(width: 18),
              Expanded(child: i + 1 < keys.length ? cell(keys[i + 1]) : const SizedBox()),
            ],
          ),
      ],
    );
  }
}

class _HighlightPicker extends StatefulWidget {
  const _HighlightPicker({required this.initial});
  final List<String> initial;

  @override
  State<_HighlightPicker> createState() => _HighlightPickerState();
}

class _HighlightPickerState extends State<_HighlightPicker> {
  late final _chosen = [...widget.initial];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Highlighted nutrients', 'Uitgelichte voedingsstoffen'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: p.ink),
                      ),
                      Text(
                        tr('Choose up to 8 (${_chosen.length}/8)', 'Kies er tot 8 (${_chosen.length}/8)'),
                        style: TextStyle(fontSize: 12.5, color: p.ink2),
                      ),
                    ],
                  ),
                ),
                FilledButton(onPressed: () => Navigator.pop(context, _chosen), child: Text(tr('Save', 'Opslaan'))),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              children: [
                for (final n in nutrients)
                  if (n.key != 'energy')
                    CheckboxListTile(
                      value: _chosen.contains(n.key),
                      title: Text(n.name),
                      subtitle: Text(n.group.label, style: TextStyle(fontSize: 11.5, color: p.ink3)),
                      onChanged: (v) => setState(() {
                        if (v == true && _chosen.length < 8) _chosen.add(n.key);
                        if (v == false) _chosen.remove(n.key);
                      }),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Selectie en acties op regels ──

/// Geselecteerde dagboekregels (lang drukken op een regel), om ze samen te verplaatsen, kopiëren of verwijderen.
final _selection = ValueNotifier<Set<String>>(const {});

void _toggleSelected(String id) {
  final now = {..._selection.value};
  if (!now.remove(id)) now.add(id);
  _selection.value = now;
}

/// Geselecteerde regels die op de getoonde dag staan (een andere dag kiezen laat de selectie vallen).
List<DiaryEntry> _selectedIn(AppState s) {
  if (_selection.value.isEmpty) return const [];
  final list = [
    for (final e in s.entries)
      if (_selection.value.contains(e.id)) e,
  ];
  if (list.isEmpty) WidgetsBinding.instance.addPostFrameCallback((_) => _selection.value = const {});
  return list;
}

void _deleteWithUndo(BuildContext context, List<DiaryEntry> entries) {
  final s = context.read<AppState>();
  s.deleteEntries(entries);
  showUndo(
    context,
    entries.length == 1
        ? tr('${entries.first.name} removed', '${entries.first.name} verwijderd')
        : tr('${entries.length} items removed', '${entries.length} items verwijderd'),
    () => s.restoreEntries(entries),
  );
}

Future<Meal?> _pickMeal(BuildContext context, {required String title}) => showModalBottomSheet<Meal>(
  context: context,
  builder: (ctx) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
        for (final m in Meal.values)
          ListTile(leading: const Icon(Icons.restaurant_outlined), title: Text(m.label), onTap: () => Navigator.pop(ctx, m)),
      ],
    ),
  ),
);

Future<void> _copyToDay(BuildContext context, List<DiaryEntry> entries) async {
  final s = context.read<AppState>();
  final today = logicalNow();
  final day = await showDatePicker(
    context: context,
    initialDate: s.date,
    firstDate: DateTime(today.year - 2),
    lastDate: DateTime(today.year, today.month, today.day + 30),
    currentDate: today,
    // Kort, zodat de titel niet afgekapt wordt; taal van de app en week vanaf maandag (N46)
    helpText: tr('Copy to', 'Kopiëren naar'),
    builder: (ctx, child) => Localizations.override(context: ctx, locale: pickerLocale, child: child!),
  );
  if (day == null || !context.mounted) return;
  final n = s.copyEntriesTo(entries, day);
  _selection.value = const {};
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        tr('$n copied to ${DateFormat('d MMMM', appLocale).format(day)}.', '$n gekopieerd naar ${DateFormat('d MMMM', appLocale).format(day)}.'),
      ),
    ),
  );
}

Future<void> _move(BuildContext context, List<DiaryEntry> entries) async {
  final s = context.read<AppState>();
  final meal = await _pickMeal(context, title: tr('Move to', 'Verplaatsen naar'));
  if (meal == null) return;
  s.moveEntries(entries, meal);
  _selection.value = const {};
}

Future<void> _saveAsMeal(BuildContext context, List<DiaryEntry> entries) async {
  final s = context.read<AppState>();
  final name = await _askName(context, entries.first.meal);
  if (name == null || name.isEmpty || !context.mounted) return;
  s.saveMealFromEntries(name, entries);
  _selection.value = const {};
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(tr('"$name" saved under Add → Saved meals.', '"$name" opgeslagen bij Toevoegen → Opgeslagen maaltijden.'))));
}

/// Wat een selectie bijdraagt: kcal, macro's en de belangrijkste stoffen tegenover je dagdoel.
Future<void> _nutritionOf(BuildContext context, List<DiaryEntry> entries) {
  final s = context.read<AppState>();
  final totals = s.totalsOf(entries);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            entries.length == 1 ? entries.first.name : tr('${entries.length} items', '${entries.length} items'),
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: ctx.pal.ink),
          ),
          Text(
            tr('${fmtInt(totals['energy'])} kcal · share of your daily goal', '${fmtInt(totals['energy'])} kcal · deel van je dagdoel'),
            style: TextStyle(fontSize: 13, color: ctx.pal.ink2),
          ),
          const SizedBox(height: 12),
          KeyNutrients(values: totals.values, targets: s.targets, incomplete: totals.incomplete, isToday: s.isToday),
        ],
      ),
    ),
  );
}

/// Acties voor één regel (veeg naar rechts) of een selectie.
Future<void> _entryActions(BuildContext context, List<DiaryEntry> entries) async {
  final s = context.read<AppState>();
  final single = entries.length == 1 ? entries.first : null;
  final food = single == null ? null : s.foodFor(single);
  final v = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                single?.name ?? tr('${entries.length} items', '${entries.length} items'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${fmtInt(entries.fold(0.0, (a, e) => a + e.kcal))} kcal'),
            ),
            if (single != null)
              ListTile(leading: const Icon(Icons.edit_outlined), title: Text(tr('Edit', 'Bewerken')), onTap: () => Navigator.pop(ctx, 'edit')),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outline),
              title: Text(tr('Move to another meal', 'Naar andere maaltijd')),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            if (!s.isToday)
              ListTile(
                leading: const Icon(Icons.today_outlined),
                title: Text(tr('Copy to today', 'Kopiëren naar vandaag')),
                onTap: () => Navigator.pop(ctx, 'today'),
              ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: Text(tr('Copy to another day', 'Kopiëren naar andere dag')),
              onTap: () => Navigator.pop(ctx, 'copy'),
            ),
            ListTile(
              leading: const Icon(Icons.insights_outlined),
              title: Text(tr('Nutrition', 'Voedingswaarden')),
              onTap: () => Navigator.pop(ctx, 'info'),
            ),
            if (single == null)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined),
                title: Text(tr('Save as meal', 'Opslaan als maaltijd')),
                onTap: () => Navigator.pop(ctx, 'save'),
              ),
            if (food != null)
              ListTile(
                leading: Icon(s.isFavorite(food.ref) ? Icons.star_rounded : Icons.star_outline_rounded),
                title: Text(
                  s.isFavorite(food.ref) ? tr('Remove from favourites', 'Uit favorieten') : tr('Add to favourites', 'Aan favorieten toevoegen'),
                ),
                onTap: () => Navigator.pop(ctx, 'fav'),
              ),
            if (single != null)
              ListTile(
                leading: const Icon(Icons.checklist_rounded),
                title: Text(tr('Select more', 'Meer selecteren')),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: ctx.pal.high),
              title: Text(tr('Remove', 'Verwijderen'), style: TextStyle(color: ctx.pal.high)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    ),
  );
  if (v == null || !context.mounted) return;
  switch (v) {
    case 'edit':
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FoodDetailScreen(food: food!, meal: single!.meal, entry: single),
        ),
      );
    case 'move':
      await _move(context, entries);
    case 'today':
      final n = s.copyEntriesTo(entries, logicalNow());
      _selection.value = const {};
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('$n copied to today.', '$n gekopieerd naar vandaag.'))));
    case 'copy':
      await _copyToDay(context, entries);
    case 'info':
      await _nutritionOf(context, entries);
    case 'save':
      await _saveAsMeal(context, entries);
    case 'fav':
      s.toggleFavorite(food!);
    case 'select':
      _toggleSelected(single!.id);
    case 'delete':
      _selection.value = const {};
      _deleteWithUndo(context, entries);
  }
}

/// Onderaan zolang je regels geselecteerd hebt: hoeveel, samen hoeveel kcal, en de acties.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.entries});
  final List<DiaryEntry> entries;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final kcal = entries.fold(0.0, (a, e) => a + e.kcal);
    Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: p.ink),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
    return Material(
      color: p.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: tr('Stop selecting', 'Selectie stoppen'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _selection.value = const {},
                  ),
                  Expanded(
                    child: Text(
                      tr('${entries.length} selected · ${fmtInt(kcal)} kcal', '${entries.length} geselecteerd · ${fmtInt(kcal)} kcal'),
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: p.ink),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  action(Icons.insights_outlined, tr('Nutrition', 'Waarden'), () => _nutritionOf(context, entries)),
                  action(Icons.drive_file_move_outline, tr('Move', 'Verplaatsen'), () => _move(context, entries)),
                  action(Icons.copy_rounded, tr('Copy', 'Kopiëren'), () => _copyToDay(context, entries)),
                  action(Icons.bookmark_add_outlined, tr('Save meal', 'Als maaltijd'), () => _saveAsMeal(context, entries)),
                  action(Icons.delete_outline_rounded, tr('Remove', 'Verwijderen'), () {
                    _selection.value = const {};
                    _deleteWithUndo(context, entries);
                  }),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
