/// Supplementen afstemmen op je bloedwaarden: wat je (niet) nodig hebt, welke dosis gangbaar is, en of al je
/// supplementen samen onder de veilige bovengrens blijven. Uitleg, geen voorschrift: bij een tekort hoort een arts.
library;

import '../i18n.dart';
import '../nutrition/nutrients.dart';
import '../nutrition/supplements.dart';
import 'lab_report.dart';

enum AdviceKind {
  /// Je neemt te veel of iets wat je niet nodig hebt.
  warning,

  /// Een tekort: een supplement kan helpen.
  suggest,

  /// In orde: geen (hoge dosis) nodig.
  fine,
}

class SupplementAdvice {
  const SupplementAdvice(this.kind, this.title, this.text, {this.catalogId, this.labDay});
  final AdviceKind kind;
  final String title, text;

  /// Supplement uit de ingebouwde lijst dat past, om meteen toe te voegen.
  final String? catalogId;

  /// Dag van de bloedafname waarop het advies steunt (null bij de bovengrenzen).
  final String? labDay;
}

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

  // ── Vitamine D (ng/mL): < 20 tekort, 20–30 te weinig, 30–100 goed, > 100 te veel ──
  if (value('vit_d') case final d?) {
    final taking = totals['vit_d'] ?? 0;
    final shown = '${fmtGrouped(d, 0)} ng/mL';
    if (d > 100) {
      out.add(
        SupplementAdvice(
          AdviceKind.warning,
          tr('Vitamin D: stop supplements', 'Vitamine D: stop met supplementen'),
          tr(
            'Your vitamin D is very high ($shown). Stop vitamin D supplements and discuss this with your doctor.',
            'Je vitamine D is zeer hoog ($shown). Stop met vitamine D-supplementen en bespreek dit met je arts.',
          ),
          labDay: day('vit_d'),
        ),
      );
    } else if (d < 20) {
      out.add(
        SupplementAdvice(
          AdviceKind.suggest,
          tr('Vitamin D: deficiency', 'Vitamine D: tekort'),
          tr(
            'Your vitamin D is low ($shown). Usually 25 µg (1000 IU) a day is advised${taking > 0 ? '; you now take ${amount('vit_d')}' : ''}. Ask your doctor whether a higher starting dose is needed and retest after 3 months.',
            'Je vitamine D is laag ($shown). Meestal is 25 µg (1000 IE) per dag aangeraden${taking > 0 ? '; je neemt nu ${amount('vit_d')}' : ''}. Vraag je arts of een hogere startdosis nodig is en laat na 3 maanden opnieuw meten.',
          ),
          catalogId: taking >= 25 ? null : 'vitd25',
          labDay: day('vit_d'),
        ),
      );
    } else if (d < 30) {
      out.add(
        SupplementAdvice(
          AdviceKind.suggest,
          tr('Vitamin D: on the low side', 'Vitamine D: aan de lage kant'),
          tr(
            'Your vitamin D is somewhat low ($shown). 10–25 µg (400–1000 IU) a day, especially from October to March, usually brings it above 30.${taking >= 10 ? ' You already take ${amount('vit_d')}.' : ''}',
            'Je vitamine D is wat laag ($shown). 10–25 µg (400–1000 IE) per dag, zeker van oktober tot maart, brengt het meestal boven 30.${taking >= 10 ? ' Je neemt al ${amount('vit_d')}.' : ''}',
          ),
          catalogId: taking >= 10 ? null : 'vitd10',
          labDay: day('vit_d'),
        ),
      );
    } else {
      out.add(
        SupplementAdvice(
          taking > 50 ? AdviceKind.warning : AdviceKind.fine,
          tr('Vitamin D: fine', 'Vitamine D: in orde'),
          taking > 50
              ? tr(
                  'Your vitamin D is fine ($shown), so you do not need a high dose: ${amount('vit_d')} a day is more than necessary. 10–25 µg is enough to keep it there.',
                  'Je vitamine D is in orde ($shown), dus je hebt geen hoge dosis nodig: ${amount('vit_d')} per dag is meer dan nodig. 10–25 µg volstaat om het zo te houden.',
                )
              : tr(
                  'Your vitamin D is fine ($shown): no high dose needed. In winter, 10 µg (400 IU) a day helps to keep it there.',
                  'Je vitamine D is in orde ($shown): geen hoge dosis nodig. In de winter helpt 10 µg (400 IE) per dag om het zo te houden.',
                ),
          labDay: day('vit_d'),
        ),
      );
    }
  }

  // ── IJzer (ferritine µg/L): een supplement alleen bij een tekort, en dan met de arts (de oorzaak telt) ──
  if (value('ferritin') case final f?) {
    final taking = totals['iron'] ?? 0;
    final shown = '${fmtGrouped(f, 0)} µg/L';
    if (f < 30) {
      out.add(
        SupplementAdvice(
          AdviceKind.suggest,
          tr('Iron: low stores', 'IJzer: lage voorraad'),
          tr(
            'Your ferritin is low ($shown). Ask your doctor about the cause and whether you need iron tablets (often 14–28 mg a day or every other day). Take them with vitamin C, not with tea, coffee or dairy.',
            'Je ferritine is laag ($shown). Vraag je arts naar de oorzaak en of je ijzertabletten nodig hebt (vaak 14–28 mg per dag of om de dag). Neem ze met vitamine C, niet met thee, koffie of zuivel.',
          ),
          catalogId: taking > 0 ? null : 'fe14',
          labDay: day('ferritin'),
        ),
      );
    } else if (taking > 0) {
      out.add(
        SupplementAdvice(
          f > 200 ? AdviceKind.warning : AdviceKind.fine,
          tr('Iron: not needed', 'IJzer: niet nodig'),
          f > 200
              ? tr(
                  'Your ferritin is high ($shown) and you take ${amount('iron')} iron. Stop the iron and talk to your doctor: too much iron harms your liver.',
                  'Je ferritine is hoog ($shown) en je neemt ${amount('iron')} ijzer. Stop met het ijzer en spreek met je arts: te veel ijzer beschadigt je lever.',
                )
              : tr(
                  'Your iron stores are fine ($shown). You probably do not need the ${amount('iron')} iron from your supplements.',
                  'Je ijzervoorraad is in orde ($shown). De ${amount('iron')} ijzer uit je supplementen heb je waarschijnlijk niet nodig.',
                ),
          labDay: day('ferritin'),
        ),
      );
    }
  }

  // ── B12 (ng/L): < 200 tekort, 200–300 grensgebied ──
  if (value('b12') case final b?) {
    final taking = totals['b12'] ?? 0;
    final shown = '${fmtGrouped(b, 0)} ng/L';
    if (b < 300) {
      out.add(
        SupplementAdvice(
          AdviceKind.suggest,
          b < 200 ? tr('Vitamin B12: deficiency', 'Vitamine B12: tekort') : tr('Vitamin B12: borderline', 'Vitamine B12: grensgebied'),
          tr(
            'Your B12 is ${b < 200 ? 'low' : 'on the low side'} ($shown). A tablet of 100 µg a day (or 1000 µg a few times a week) is a common, safe dose. With a clear deficiency, your doctor may first give injections.',
            'Je B12 is ${b < 200 ? 'laag' : 'aan de lage kant'} ($shown). Een tablet van 100 µg per dag (of 1000 µg enkele keren per week) is een gangbare, veilige dosis. Bij een duidelijk tekort geeft je arts soms eerst spuiten.',
          ),
          catalogId: taking >= 100 ? null : 'b12_100',
          labDay: day('b12'),
        ),
      );
    } else if (taking >= 500) {
      out.add(
        SupplementAdvice(
          AdviceKind.fine,
          tr('Vitamin B12: fine', 'Vitamine B12: in orde'),
          tr(
            'Your B12 is fine ($shown). If you eat animal products, ${amount('b12')} a day is more than you need; plant-based eaters do need B12.',
            'Je B12 is in orde ($shown). Eet je dierlijke producten, dan is ${amount('b12')} per dag meer dan nodig; wie plantaardig eet, heeft B12 wel nodig.',
          ),
          labDay: day('b12'),
        ),
      );
    }
  }

  // ── Foliumzuur (µg/L) ──
  if (value('folate') case final v? when v < 3.9) {
    out.add(
      SupplementAdvice(
        AdviceKind.suggest,
        tr('Folate: low', 'Foliumzuur: laag'),
        tr(
          'Your folate is low (${fmtGrouped(v)} µg/L). 400 µg folic acid a day helps, together with more green vegetables and legumes.',
          'Je foliumzuur is laag (${fmtGrouped(v)} µg/L). 400 µg foliumzuur per dag helpt, samen met meer groene groenten en peulvruchten.',
        ),
        catalogId: (totals['b9'] ?? 0) >= 400 ? null : 'folic',
        labDay: day('folate'),
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
          'Your magnesium is low (${fmtGrouped(v, 2)} mmol/L). 200 mg a day (citrate or bisglycinate) is a common dose; more than 250 mg from supplements can upset your stomach.',
          'Je magnesium is laag (${fmtGrouped(v, 2)} mmol/L). 200 mg per dag (citraat of bisglycinaat) is een gangbare dosis; meer dan 250 mg uit supplementen kan je maag van streek maken.',
        ),
        catalogId: (totals['magnesium'] ?? 0) >= 200 ? null : 'mg200',
        labDay: day('magnesium'),
      ),
    );
  }

  // ── Alles samen: boven de veilige bovengrens? ──
  for (final e in supplementUpperLimits.entries) {
    final total = totals[e.key] ?? 0;
    if (total <= e.value) continue;
    final n = nutrientByKey[e.key];
    if (n == null) continue;
    final from = [
      for (final s in supplements)
        if ((s.nutrients[e.key] ?? 0) > 0) s.name,
    ];
    out.add(
      SupplementAdvice(
        AdviceKind.warning,
        tr('${n.name}: too much', '${n.name}: te veel'),
        tr(
          'Your supplements together give ${amount(e.key)} ${inSentence(n.name)} a day, above the safe upper limit of ${fmtGrouped(e.value)} ${n.unit}${from.length > 1 ? ' (${from.join(', ')})' : ''}. Leave one out or take a lower dose.',
          'Je supplementen samen geven ${amount(e.key)} ${inSentence(n.name)} per dag, boven de veilige bovengrens van ${fmtGrouped(e.value)} ${n.unit}${from.length > 1 ? ' (${from.join(', ')})' : ''}. Laat er één weg of neem een lagere dosis.',
        ),
      ),
    );
  }

  // Waarschuwingen eerst, dan tekorten, dan wat in orde is
  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out;
}
