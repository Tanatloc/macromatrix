/// "Weekly coach" in het weekrapport: een korte samenvatting van je week met 2 à 3 tips, geschreven door een
/// tekstmodel (/api/coach). De eerste functie in vroege toegang: supporters nu, iedereen een paar weken later.
///
/// De app stuurt alleen cijfers (zie lib/nutrition/coach.dart). Wat terugkomt, bewaart de app per week op dit toestel,
/// zodat het rapport opnieuw openen niets kost; "Write again" mag binnen de dagteller.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase/supabase.dart' show SupabaseClient;

import '../../i18n.dart';
import '../../nutrition/coach.dart';
import '../../nutrition/nutrients.dart' show nutrientByKey;
import '../../nutrition/report.dart';
import '../../platform/ai_request.dart';
import '../../platform/coach_request.dart';
import '../../state/app_state.dart';
import '../../sync/account.dart';
import '../../sync/ai_report.dart';
import '../../sync/features.dart';
import '../../sync/pro.dart' show PhotoQuota, utcDayKey;
import '../theme.dart';
import 'ai_quota_note.dart' show aiErrorText;
import 'feature_gate.dart';
import 'kit.dart';
import 'pro_widgets.dart';

/// De verbinding met /api/coach. Te vervangen in tests.
@visibleForTesting
CoachRequest coachRequest = CoachRequest();

/// Het token van je account, of null als je niet ingelogd bent. Te vervangen in tests.
String? Function(BuildContext context) coachToken = (context) => context.read<Account?>()?.accessToken;

/// Meldingen van een AI-tekst (ai_report). Te vervangen in tests.
@visibleForTesting
AiReporter coachReporter = const AiReporter();

/// De Supabase-verbinding voor een melding, of null zonder account. Te vervangen in tests.
SupabaseClient? Function(BuildContext context) coachClient = (context) => context.read<Account?>()?.client;

/// Op true zodra de server zegt dat de coach er (nog) niet is (migratie niet uitgevoerd of geen model): dan verbergt
/// het weekrapport hem tot de app opnieuw start.
@visibleForTesting
bool coachUnavailable = false;

/// Hoeveel weken de app bewaart.
const _keepWeeks = 8;

/// Wat de coach per week schreef en de laatste stand van de teller, alleen op dit toestel (instelling '_coach').
class CoachCache {
  CoachCache(this.s);
  final AppState s;

  Map<String, Object?> get _raw => s.user.setting('_coach') ?? const {};

  CoachResult? result(DateTime monday) => CoachResult.fromJson((_raw['weeks'] as Map?)?[dayKey(monday)]);

  /// De stand van de teller, of null als die van een vorige dag is (vandaag begin je opnieuw).
  PhotoQuota? quota(DateTime now) {
    final q = _raw['quota'];
    if (q is! Map || q['day'] is! String || q['limit'] is! num) return null;
    final p = PhotoQuota(used: (q['used'] as num?)?.toInt() ?? 0, limit: (q['limit'] as num).toInt(), pro: q['pro'] == true, day: q['day'] as String);
    return p.day == utcDayKey(now) ? p : null;
  }

  void save({DateTime? monday, CoachResult? result, PhotoQuota? quota}) {
    final weeks = {...?(_raw['weeks'] as Map?)?.cast<String, Object?>()};
    if (monday != null && result != null) weeks[dayKey(monday)] = result.toJson();
    final keep = (weeks.keys.toList()..sort()).reversed.take(_keepWeeks).toSet();
    weeks.removeWhere((k, _) => !keep.contains(k));
    final q = quota ?? _raw['quota'];
    s.user.setSetting('_coach', {
      'weeks': weeks,
      if (quota != null) 'quota': {'used': quota.used, 'limit': quota.limit, 'pro': quota.pro, 'day': quota.day} else 'quota': ?q,
    });
  }
}

/// Wat het paneel naar /api/coach stuurt: de week, met voorstellen uit het Orakel voor je grootste tekorten en, als
/// de coach vorige week schreef, die tips met hoe die stoffen veranderden.
@visibleForTesting
Future<Map<String, Object?>> coachWeekFor(AppState s, CoachCache cache, WeeklyReport r) async {
  // Eerst een beeld tekenen (het draaiende wieltje), dan pas het Orakel: dat rekent op deze draad
  await Future<void>.delayed(Duration.zero);
  final sw = Stopwatch()..start();
  final options = s.coachOptions(coachGapKeys(r.avg), goals: r.goals);
  if (kDebugMode) debugPrint('coach: voorstellen voor ${options.length} stoffen in ${sw.elapsedMilliseconds} ms');
  final m = r.monday;
  final previous = cache.result(DateTime(m.year, m.month, m.day - 7));
  return coachWeek(r, diet: s.preferences, allergies: s.allergies, options: options, lastWeek: coachLastWeek(r, previous));
}

/// Wat het paneel toont.
enum CoachAccess {
  /// Niet tonen: te weinig dagen, de server kent de coach niet, of de functie staat nog uit.
  hidden,

  /// Nog in vroege toegang en je bent geen supporter.
  locked,

  /// Je kan een samenvatting laten schrijven.
  open,
}

/// Mag je de coach nu gebruiken, volgens de vlaggen en de week? [features] null (bv. in tests zonder account): de
/// standaard, en die staat uit.
CoachAccess coachAccess(WeeklyReport r, Features? features) {
  if (r.days < coachMinDays || coachUnavailable || features == null || !features.available) return CoachAccess.hidden;
  if (features.has(coachFeature)) return CoachAccess.open;
  return features.inEarlyAccess.any((f) => f.id == coachFeature) ? CoachAccess.locked : CoachAccess.hidden;
}

class CoachPanel extends StatefulWidget {
  const CoachPanel({super.key, required this.report});
  final WeeklyReport report;

  @override
  State<CoachPanel> createState() => _CoachPanelState();
}

class _CoachPanelState extends State<CoachPanel> {
  bool _busy = false;
  String? _error;

  Future<void> _write(AppState s, CoachCache cache) async {
    final token = coachToken(context);
    if (token == null) {
      setState(() => _error = aiErrorText('login'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final week = await coachWeekFor(s, cache, widget.report);
    try {
      final r = await coachRequest.write(week, token: token);
      // Waar de voorstellen over gingen, voor de terugblik van volgende week
      final focus = [
        for (final k in coachGapKeys(widget.report.avg))
          if (week['options'] case final Map o when o.containsKey(nutrientByKey[k]?.name)) k,
      ];
      cache.save(monday: widget.report.monday, result: r.withFocus(focus), quota: coachRequest.lastQuota);
    } on AiException catch (e) {
      if (coachRequest.lastQuota case final q?) cache.save(quota: q);
      if (e.code == 'not_configured') coachUnavailable = true;
      _error = _errorText(e.code);
    }
    if (mounted) setState(() => _busy = false);
  }

  /// De tekst melden (vlagje onder de coach, Google Play-beleid voor generatieve AI): eerst een korte vraag met een
  /// optionele notitie, dan naar ai_report met de samenvatting, de tips, de week en het model.
  Future<void> _report(CoachResult result) async {
    // null: geannuleerd; anders de (eventueel lege) notitie
    final extra = await showDialog<String>(context: context, builder: (_) => const _ReportDialog());
    if (extra == null || !mounted) return;
    final text = [result.summary, '', for (final (i, t) in result.tips.indexed) '${i + 1}. $t'].join('\n');
    final meta = 'week ${dayKey(widget.report.monday)} · model ${result.model ?? 'unknown'} · lang ${result.lang}';
    final r = await coachReporter.report(coachClient(context), kind: 'coach', text: text, note: extra.isEmpty ? meta : '$meta\n$extra');
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(switch (r) {
          AiReportResult.reported => tr("Thanks, we'll look at it.", 'Bedankt, we bekijken het.'),
          AiReportResult.limit => tr(
            "You've sent a lot of reports today. Try again tomorrow.",
            'Je stuurde vandaag al veel meldingen. Probeer morgen opnieuw.',
          ),
          AiReportResult.failed => tr("Couldn't send the report. Try again later.", 'De melding kon niet weg. Probeer later opnieuw.'),
        }),
      ),
    );
  }

  static String _errorText(String code) => switch (code) {
    'quota' => tr("That was today's last one. You can write it again tomorrow.", 'Dat was de laatste voor vandaag. Morgen kan het weer.'),
    'too_many' => tr('You asked a few times this hour. Try again later.', 'Je vroeg het dit uur al een paar keer. Probeer later opnieuw.'),
    'network' || 'timeout' => tr(
      "Couldn't reach the coach. Check your connection and try again.",
      'De coach was niet bereikbaar. Kijk je verbinding na en probeer opnieuw.',
    ),
    'login' => aiErrorText('login'),
    _ => tr("Couldn't write a summary this time. Try again in a moment.", 'Er kwam deze keer geen samenvatting. Probeer zo meteen opnieuw.'),
  };

  @override
  Widget build(BuildContext context) {
    final features = featuresOf(context);
    final access = coachAccess(widget.report, features);
    if (access == CoachAccess.hidden) return const SizedBox.shrink();
    final s = context.watch<AppState>();
    final p = context.pal;
    final cache = CoachCache(s);
    final early = features?.isEarly(coachFeature) ?? false;

    final range =
        '${DateFormat('d MMM', appLocale).format(widget.report.monday)} – '
        '${DateFormat('d MMM', appLocale).format(widget.report.monday.plusDays(6))}';
    final title = Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(color: p.brand, shape: BoxShape.circle),
          child: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: p.onBrand),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Weekly coach', 'Wekelijkse coach'),
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: p.ink),
              ),
              Text(range, style: TextStyle(fontSize: 12, color: p.ink3)),
            ],
          ),
        ),
        if (early) const EarlyAccessChip(),
      ],
    );

    if (access == CoachAccess.locked) {
      final from = features!.inEarlyAccess.firstWhere((f) => f.id == coachFeature).publicFrom;
      final date = from == null ? null : DateFormat('d MMMM', appLocale).format(from.toLocal());
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Panel(
          key: const ValueKey('coach-locked'),
          shadow: false,
          onTap: () => openProScreen(context),
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Een slotje: een tik opent de Supporter-pagina, niet de coach zelf (SP-9)
              Row(
                children: [
                  Expanded(child: title),
                  Icon(Icons.lock_outline_rounded, size: 18, color: p.ink3),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                date == null
                    ? tr(
                        'A short summary of your week with a few tips. Supporters get this first.',
                        'Een korte samenvatting van je week met een paar tips. Supporters krijgen dit eerst.',
                      )
                    : tr(
                        'A short summary of your week with a few tips. Supporters get this first; for everyone from $date.',
                        'Een korte samenvatting van je week met een paar tips. Supporters krijgen dit eerst; voor iedereen vanaf $date.',
                      ),
                style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2),
              ),
            ],
          ),
        ),
      );
    }

    final result = cache.result(widget.report.monday);
    final quota = cache.quota(DateTime.now());
    final spent = quota != null && !quota.allowed;
    // In een andere taal geschreven dan de app nu toont (SU-3): niet stil laten staan, maar zeggen en opnieuw aanbieden
    final otherLang = result != null && result.lang != (isNl ? 'nl' : 'en');
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Panel(
        key: const ValueKey('coach-panel'),
        shadow: false,
        color: result == null ? null : p.brandSoft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            const SizedBox(height: 6),
            if (result == null && !_busy)
              Text(
                tr(
                  'A short look back at this week from your numbers, with two or three things to try next week.',
                  'Een korte terugblik op deze week vanuit je cijfers, met twee of drie dingen om volgende week te proberen.',
                ),
                style: TextStyle(fontSize: 13, height: 1.4, color: p.ink2),
              ),
            if (result != null) ...[
              const SizedBox(height: 6),
              _CoachStats(report: widget.report),
              const SizedBox(height: 12),
              if (otherLang)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    key: const ValueKey('coach-other-lang'),
                    onTap: spent || _busy ? null : () => _write(s, cache),
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Icon(Icons.translate_rounded, size: 16, color: p.brand),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result.lang == 'nl'
                                ? tr('Written in Dutch. Write it again in English?', 'Geschreven in het Nederlands. Opnieuw schrijven in het Engels?')
                                : tr(
                                    'Written in English. Write it again in Dutch?',
                                    'Geschreven in het Engels. Opnieuw schrijven in het Nederlands?',
                                  ),
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: p.brand),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Text(
                result.summary,
                key: const ValueKey('coach-summary'),
                style: TextStyle(fontSize: 14.5, height: 1.5, color: p.ink),
              ),
              const SizedBox(height: 12),
              Text(
                tr('For next week', 'Voor volgende week'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: p.ink3),
              ),
              const SizedBox(height: 6),
              for (final (i, t) in result.tips.indexed)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: p.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: p.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: p.brandSoft, shape: BoxShape.circle),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: p.brand),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(t, style: TextStyle(fontSize: 13.5, height: 1.4, color: p.ink)),
                      ),
                    ],
                  ),
                ),
            ],
            if (_busy)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 10),
                    Text(tr('Writing…', 'Even schrijven…'), style: TextStyle(fontSize: 13, color: p.ink2)),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  key: const ValueKey('coach-error'),
                  style: TextStyle(fontSize: 12.5, color: p.ink2),
                ),
              ),
            if (!_busy) ...[
              const SizedBox(height: 6),
              if (spent && _error == null)
                Text(
                  key: const ValueKey('coach-spent'),
                  tr(
                    "You've used today's summaries. You can write it again tomorrow.",
                    'Je samenvattingen van vandaag zijn op. Morgen kan het weer.',
                  ),
                  style: TextStyle(fontSize: 12.5, color: p.ink3),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: result == null
                    ? FilledButton.tonalIcon(
                        key: const ValueKey('coach-write'),
                        onPressed: spent ? null : () => _write(s, cache),
                        icon: const Icon(Icons.edit_note_rounded, size: 18),
                        label: Text(tr('Write my summary', 'Schrijf mijn samenvatting')),
                      )
                    : TextButton.icon(
                        key: const ValueKey('coach-again'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: spent ? null : () => _write(s, cache),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(tr('Write again', 'Opnieuw schrijven')),
                      ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    tr(
                      "Written by AI from your week's numbers. It can be wrong; it isn't medical advice.",
                      'Geschreven door AI op basis van de cijfers van je week. Het kan fout zijn; het is geen medisch advies.',
                    ),
                    style: TextStyle(fontSize: 11.5, color: p.ink3),
                  ),
                ),
                // Melden (Google Play-beleid voor generatieve AI), alleen als er een tekst staat
                if (result != null)
                  IconButton(
                    key: const ValueKey('coach-report'),
                    tooltip: tr('Report this text', 'Deze tekst melden'),
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    color: p.ink3,
                    onPressed: () => _report(result),
                    icon: const Icon(Icons.outlined_flag_rounded),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// De vraag of je de tekst wil melden, met een optionele notitie. Geeft de notitie terug, of null bij annuleren.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Report this text?', 'Deze tekst melden?')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(
            "Is something wrong, harmful or offensive? We'll get this text so we can look at it.",
            'Klopt er iets niet, of is het schadelijk of kwetsend? Wij krijgen deze tekst en bekijken hem.',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('coach-report-note'),
          controller: _note,
          maxLength: 500,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(hintText: tr("What's wrong? (optional)", 'Wat is er mis? (mag leeg)')),
        ),
      ],
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel', 'Annuleren'))),
      FilledButton(
        key: const ValueKey('coach-report-send'),
        onPressed: () => Navigator.pop(context, _note.text.trim()),
        child: Text(tr('Report', 'Melden')),
      ),
    ],
  );
}

/// Drie cijfers uit je week (niet van de AI): je score, je energie tegenover je doel en je grootste tekort.
class _CoachStats extends StatelessWidget {
  const _CoachStats({required this.report});
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final r = report;
    // Labels en onderschriften mogen op twee regels (SU-7: "goal 1,857 kc…" op een smalle gsm); alle tegels even hoog
    Widget tile(String label, String value, String? sub, {Color? subColor}) => Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: p.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.25, color: p.ink3),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: numStyle(17, color: p.ink)),
            ),
            if (sub != null)
              Text(
                sub,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, height: 1.25, color: subColor ?? p.ink3),
              ),
          ],
        ),
      ),
    );
    final change = r.change;
    // Het laagste aandeel onder je doel (niet wat erboven zit, zoals te veel energie)
    final gaps = [...r.worst.where((w) => w.$2 < 1)]..sort((a, b) => a.$2.compareTo(b.$2));
    final gap = gaps.isEmpty ? null : gaps.first;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tile(
            tr('Score', 'Score'),
            '${r.score}',
            change == null || change == 0 ? null : '${change > 0 ? '▲' : '▼'} ${change.abs()}',
            subColor: change == null ? null : (change > 0 ? p.ok : p.high),
          ),
          const SizedBox(width: 8),
          tile(
            tr('Energy', 'Energie'),
            r.kcalAvg == null ? '–' : fmtInt(r.kcalAvg!),
            r.kcalGoal == null ? null : tr('goal ${fmtInt(r.kcalGoal!)} kcal', 'doel ${fmtInt(r.kcalGoal!)} kcal'),
          ),
          const SizedBox(width: 8),
          tile(tr('Biggest gap', 'Grootste tekort'), gap == null ? '–' : fmtPct(gap.$2), gap?.$1.name),
        ],
      ),
    );
  }
}
