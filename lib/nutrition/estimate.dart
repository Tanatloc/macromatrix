/// Ontbrekende voedingswaarden schatten uit een vergelijkbaar basisproduct (bv. skyr uit "yoghurt, natuur").
///
/// Een etiket vermeldt meestal alleen energie, vet, verzadigd vet, koolhydraten, suikers, eiwit en zout.
/// De rest nemen we over van het basisproduct, met twee correcties:
///  - aminozuren schalen mee met het eiwit (skyr heeft ~2,5 keer zoveel eiwit als yoghurt);
///  - vetzuren, cholesterol en vetoplosbare vitaminen schalen mee met het vet (magere skyr heeft bijna geen
///    vitamine A).
/// Waarden die op het etiket staan, worden nooit vervangen.
library;

import 'values.dart';

const _protein = {
  'histidine', 'isoleucine', 'leucine', 'lysine', 'methionine', 'cystine', 'met_cys', //
  'phenylalanine', 'tyrosine', 'phe_tyr', 'threonine', 'tryptophan', 'valine',
};

const _fat = {
  'sfa', 'mufa', 'pufa', 'trans', 'cholesterol', 'omega3', 'ala', 'epa', 'dpa', 'dha', 'epa_dha', 'omega6', 'la', 'aa', //
  'vit_a', 'vit_d', 'vit_e', 'vit_k', 'vit_k2', 'beta_carotene', 'lycopene', 'lutein_zeaxanthin',
};

/// Deze komen altijd van het etiket (of ontbreken): niet schatten.
const _labelOnly = {'energy', 'protein', 'carbs', 'fat', 'sugars'};

double _ratio(double? own, double? donor) {
  if (own == null || donor == null) return 1;
  if (donor < 0.1) return 1; // basisproduct zonder (veel) vet of eiwit: niet schalen
  return (own / donor).clamp(0, 5).toDouble();
}

/// Vult [own] aan met waarden uit [donor]. Geeft de aangevulde waarden terug en per geschatte stof [donorRef].
(NutrientMap, Map<String, String>) estimateMissing(NutrientMap own, NutrientMap donor, String donorRef) {
  final values = Map.of(own);
  final estimated = <String, String>{};
  final proteinRatio = _ratio(own['protein'], donor['protein']);
  final fatRatio = _ratio(own['fat'], donor['fat']);
  for (final e in donor.entries) {
    if (values.containsKey(e.key) || _labelOnly.contains(e.key)) continue;
    final factor = _protein.contains(e.key) ? proteinRatio : (_fat.contains(e.key) ? fatRatio : 1.0);
    values[e.key] = e.value * factor;
    estimated[e.key] = donorRef;
  }
  return (values, estimated);
}
