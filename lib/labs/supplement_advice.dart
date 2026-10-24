/// Supplementen naast je bloedwaarden: waar een waarde staat tegenover de normaalwaarden (zonder dosissen of
/// oorzaken: dat bespreek je met je arts), en of al je supplementen samen onder de veilige bovengrens blijven.
library;

import '../i18n.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/supplements.dart';
import 'lab_report.dart';
import 'markers.dart';

enum AdviceKind {
  /// Je neemt te veel of iets wat je niet nodig hebt.
  warning,

  /// Een lage waarde: bespreken met je arts.
  suggest,

  /// Binnen de normaalwaarden.
  fine,
}

class SupplementAdvice {
  const SupplementAdvice(this.kind, this.title, this.text, {this.catalogId, this.labDay, this.nutrient, this.bloodValue, this.bloodLow = false});
  final AdviceKind kind;
  final String title, text;

  /// Supplement uit de ingebouwde lijst om meteen toe te voegen. Advies uit je bloed zet dit niet meer (geen
  /// supplement voorstellen op basis van een bloedwaarde, GP-9).
  final String? catalogId;

  /// Dag van de bloedafname waarop het advies steunt (null bij de bovengrenzen).
  final String? labDay;

  /// Voedingsstof waarover het advies gaat (bv. 'vit_d'), om advies uit je bloed en "te veel" samen te nemen.
  final String? nutrient;

  /// Je bloedwaarde zoals getoond (bv. "49 nmol/L"), en of ze aan de lage kant was.
  final String? bloodValue;
  final bool bloodLow;
}

/// Naam van een voedingsstof midden in een zin: "Vitamine D" wordt "vitamine D", "B6 (pyridoxine)" blijft "B6 …".
String _inSentence(String name) => name
    .split(' ')
    .map((w) => w.contains(RegExp(r'\d')) || (w.length == 1 && w == w.toUpperCase()) || w == w.toUpperCase() ? w : w.toLowerCase())
    .join(' ');

/// Veilige bovengrenzen per dag voor wat uit supplementen komt (EFSA; magnesium: alleen supplementen, 250 mg).
const supplementUpperLimits = <String, double>{
  'vit_d': 100,
  'vit_a': 3000,
  'vit_e': 300,
  'b3': 900,
  'b6': 12,
  'b9': 1000,
  'calcium': 2500,
  'magnesium': 250,
  'zinc': 25,
  'iron': 45,
  'iodine': 600,
  'selenium': 255,
  'copper': 5,
};

/// Wat al je supplementen samen per dag geven, per voedingsstof.
Map<String, double> supplementTotals(List<Supplement> list) {
  final out = <String, double>{};
  for (final s in list) {
    for (final e in s.nutrients.entries) {
      if (e.key == 'energy') continue;
      out[e.key] = (out[e.key] ?? 0) + e.value;
    }
  }
  return out;
}

/// Advies uit je laatste bloedwaarden ([labs] per stof, zie AppState.latestLabs) en je supplementen.
List<SupplementAdvice> supplementAdvice({required Map<String, LabResult> labs, required List<Supplement> supplements}) {
  final totals = supplementTotals(supplements);
  final out = <SupplementAdvice>[];
  String unit(String k) => nutrientByKey[k]?.unit ?? '';
  String amount(String k) => '${fmtGrouped(totals[k] ?? 0)} ${unit(k)}';
  double? value(String key) => labs[key]?.value.standard;
  String? day(String key) => labs[key]?.day;

  // Uit je bloed: alleen waar je waarde staat tegenover de normaalwaarden, en dat je arts beslist wat ze voor jou
  // betekent en of een supplement zin heeft. Geen dosissen en geen oorzaken: dat zou op medisch advies lijken
  // (Google Play, gezondheidsapps). Wat je zelf al neemt, tonen we wel, als feit.
  String doctor() => tr(
    'A low value can have several causes. Talk to your doctor about what it means for you and whether a supplement makes sense.',
    'Een lage waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent en of een supplement zinvol is.',
  );
  String doctorHigh() => tr(
    'A high value can have several causes. Talk to your doctor about what it means for you, and mention the supplements you take.',
    'Een hoge waarde kan verschillende oorzaken hebben. Bespreek met je arts wat ze voor jou betekent, en vertel welke supplementen je neemt.',
  );
  String takingText(String key) =>
      (totals[key] ?? 0) > 0 ? tr(' Your supplements now give ${amount(key)} a day.', ' Je supplementen geven nu ${amount(key)} per dag.') : '';

  // ── Vitamine D: grenzen in nmol/L (< 25 erg laag, 25–50 laag, 50–75 aan de lage kant, > 250 hoog), getoond in
  // de eenheid van je verslag (N22). Labo's mikken vaak op 75 of meer.
  if (labs['vit_d'] case final r? when r.value.standard != null) {
    final nmol = r.value.standard! / 0.4;
    final inNmol = normalizeUnit(r.value.unit ?? '') == 'nmol/l';
    String vd(double n) => inNmol ? fmtNum(n, 0) : fmtNum(n * 0.4, 0);
    final u = inNmol ? 'nmol/L' : 'ng/mL';
    final shown = '${inNmol ? fmtNum(r.value.value, 0) : fmtNum(r.value.standard!, 0)} $u';
    final bands = tr(
      'For reference: below ${vd(25)} $u is considered very low, ${vd(25)}–${vd(50)} low; most labs aim for ${vd(75)} $u or more.',
      'Ter vergelijking: onder ${vd(25)} $u geldt als erg laag, ${vd(25)}–${vd(50)} als laag; de meeste labo\'s mikken op ${vd(75)} $u of meer.',
    );
    SupplementAdvice add(AdviceKind kind, String title, String text) =>
        SupplementAdvice(kind, title, text, labDay: r.day, nutrient: 'vit_d', bloodValue: shown, bloodLow: nmol < 75);
    if (nmol > 250) {
      out.add(
        add(
          AdviceKind.warning,
          tr('Vitamin D: high', 'Vitamine D: hoog'),
          tr(
            'Your vitamin D ($shown) is above the reference range.${takingText('vit_d')} ${doctorHigh()}',
            'Je vitamine D ($shown) ligt boven de normaalwaarden.${takingText('vit_d')} ${doctorHigh()}',
          ),
        ),
      );
    } else if (nmol < 75) {
      final title = nmol < 25
          ? tr('Vitamin D: very low', 'Vitamine D: erg laag')
          : nmol < 50
          ? tr('Vitamin D: low', 'Vitamine D: laag')
          : tr('Vitamin D: on the low side', 'Vitamine D: aan de lage kant');
      out.add(
        add(
          AdviceKind.suggest,
          title,
          tr(
            'Your vitamin D is $shown. $bands${takingText('vit_d')} ${doctor()}',
            'Je vitamine D is $shown. $bands${takingText('vit_d')} ${doctor()}',
          ),
        ),
      );
    } else {
      out.add(
        add(
          AdviceKind.fine,
          tr('Vitamin D: within range', 'Vitamine D: binnen de normaalwaarden'),
          tr(
            'Your vitamin D ($shown) is within the reference range.${takingText('vit_d')}',
            'Je vitamine D ($shown) ligt binnen de normaalwaarden.${takingText('vit_d')}',
          ),
        ),
      );
    }
  }

  // ── Ferritine (µg/L): laag, of hoog terwijl je ijzer neemt ──
  if (value('ferritin') case final f?) {
    final taking = totals['iron'] ?? 0;
    final shown = '${fmtGrouped(f, 0)} µg/L';
    if (f < 30) {
      out.add(
        SupplementAdvice(
          AdviceKind.suggest,
          tr('Ferritin: low', 'Ferritine: laag'),
          tr(
            'Your ferritin ($shown) is below the reference range.${takingText('iron')} ${doctor()}',
            'Je ferritine ($shown) ligt onder de normaalwaarden.${takingText('iron')} ${doctor()}',
          ),
          labDay: day('ferritin'),
          nutrient: 'iron',
          bloodValue: shown,
          bloodLow: true,
        ),
      );
    } else if (taking > 0) {
      out.add(
        SupplementAdvice(
          f > 200 ? AdviceKind.warning : AdviceKind.fine,
          f > 200 ? tr('Ferritin: high', 'Ferritine: hoog') : tr('Ferritin: within range', 'Ferritine: binnen de normaalwaarden'),
          f > 200
              ? tr(
                  'Your ferritin ($shown) is on the high side, and your supplements give ${amount('iron')} iron a day. ${doctorHigh()}',
                  'Je ferritine ($shown) is aan de hoge kant, en je supplementen geven ${amount('iron')} ijzer per dag. ${doctorHigh()}',
                )
              : tr(
                  'Your ferritin ($shown) is within the reference range. Your supplements give ${amount('iron')} iron a day; ask your doctor or pharmacist whether you still need it.',
                  'Je ferritine ($shown) ligt binnen de normaalwaarden. Je supplementen geven ${amount('iron')} ijzer per dag; vraag je arts of apotheker of je dat nog nodig hebt.',
                ),
          labDay: day('ferritin'),
          nutrient: 'iron',
          bloodValue: shown,
        ),
      );
    }
  }

  // ── B12 (ng/L): < 200 laag, 200–300 aan de lage kant ──
  if (value('b12') case final b? when b < 300) {
    out.add(
      SupplementAdvice(
        AdviceKind.suggest,
        b < 200 ? tr('Vitamin B12: low', 'Vitamine B12: laag') : tr('Vitamin B12: on the low side', 'Vitamine B12: aan de lage kant'),
        tr(
          'Your B12 is ${fmtGrouped(b, 0)} ng/L.${takingText('b12')} ${doctor()}',
          'Je B12 is ${fmtGrouped(b, 0)} ng/L.${takingText('b12')} ${doctor()}',
        ),
        labDay: day('b12'),
      ),
    );
  }

  // ── Foliumzuur (µg/L) ──
  if (value('folate') case final v? when v < 3.9) {
    out.add(
      SupplementAdvice(
        AdviceKind.suggest,
        tr('Folate: low', 'Foliumzuur: laag'),
        tr(
          'Your folate (${fmtGrouped(v)} µg/L) is below the reference range.${takingText('b9')} ${doctor()}',
          'Je foliumzuur (${fmtGrouped(v)} µg/L) ligt onder de normaalwaarden.${takingText('b9')} ${doctor()}',
        ),
        labDay: day('folate'),
        nutrient: 'b9',
        bloodValue: '${fmtNum(v)} µg/L',
        bloodLow: true,
      ),
    );
  }

  // ── Magnesium (mmol/L) ──
  if (value('magnesium') case final v? when v < 0.7) {
    out.add(
      SupplementAdvice(
        AdviceKind.suggest,
        tr('Magnesium: low', 'Magnesium: laag'),
        tr(
          'Your magnesium (${fmtGrouped(v, 2)} mmol/L) is below the reference range.${takingText('magnesium')} ${doctor()}',
          'Je magnesium (${fmtGrouped(v, 2)} mmol/L) ligt onder de normaalwaarden.${takingText('magnesium')} ${doctor()}',
        ),
        labDay: day('magnesium'),
        nutrient: 'magnesium',
        bloodValue: '${fmtNum(v, 2)} mmol/L',
        bloodLow: true,
      ),
    );
  }

  // ── Alles samen: boven de veilige bovengrens? Advies uit je bloed over dezelfde stof gaat erin op: geen
  // "Vitamine D: tekort" naast "Vitamine D: te veel", wel "je bloedwaarde was laag, maar dit is te veel" (N71) ──
  for (final e in supplementUpperLimits.entries) {
    final total = totals[e.key] ?? 0;
    if (total <= e.value) continue;
    final n = nutrientByKey[e.key];
    if (n == null) continue;
    final from = [
      for (final s in supplements)
        if ((s.nutrients[e.key] ?? 0) > 0) s.name,
    ];
    final blood = out.where((a) => a.nutrient == e.key && a.kind != AdviceKind.warning).firstOrNull;
    if (blood != null) out.remove(blood);
    final context = switch (blood) {
      SupplementAdvice(bloodValue: final v?, bloodLow: true) => tr(
        ' Your blood value was low ($v). Even so, this is above the safe upper limit: talk to your doctor about what suits you.',
        ' Je bloedwaarde was laag ($v). Toch is dit boven de veilige bovengrens: bespreek met je arts wat bij je past.',
      ),
      SupplementAdvice(bloodValue: final v?) => tr(' Your blood value is $v.', ' Je bloedwaarde is $v.'),
      _ => '',
    };
    final name = _inSentence(n.name);
    out.add(
      SupplementAdvice(
        AdviceKind.warning,
        tr('${n.name}: too much', '${n.name}: te veel'),
        tr(
          'Your supplements together give ${amount(e.key)} $name a day, above the safe upper limit of ${fmtGrouped(e.value)} ${n.unit}${from.length > 1 ? ' (${from.join(', ')})' : ''}. Leave one out or take a lower dose.$context',
          'Je supplementen samen geven ${amount(e.key)} $name per dag, boven de veilige bovengrens van ${fmtGrouped(e.value)} ${n.unit}${from.length > 1 ? ' (${from.join(', ')})' : ''}. Laat er één weg of neem een lagere dosis.$context',
        ),
        labDay: blood?.labDay,
        nutrient: e.key,
      ),
    );
  }

  // Waarschuwingen eerst, dan tekorten, dan wat in orde is
  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out;
}
