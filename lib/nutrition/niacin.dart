/// B3 als niacine-equivalenten (NE) voor producten waarvan alleen de voorgevormde niacine bekend is.
///
/// Het B3-doel staat in NE (EFSA: 1,6 mg NE per MJ): niacine plus wat het lichaam uit tryptofaan maakt
/// (60 mg tryptofaan = 1 mg NE). De ingebouwde databank rekent B3 al zo om (tool/build_foods.py, `niacin_ne`).
/// Een etiket (Open Food Facts, USDA Branded via de barcode) en een eigen product geven alleen de voorgevormde niacine:
/// tegenover het NE-doel telt zo'n product te laag (een eiwitreep met 30 g eiwit mist zo ~6 mg NE).
///
/// Daarom tellen we bij die producten de tryptofaan erbij: de gemeten tryptofaan als die er is, anders geschat als
/// 1,2 % van het eiwit (12 mg per g eiwit; de mediaan in de databank is 1,17 %, vlees, vis, zuivel en granen 1-1,5 %).
/// Per g eiwit is dat 12 / 60 = 0,2 mg NE. Alleen als de niacine en het eiwit (of de tryptofaan) bekend zijn, en
/// gemarkeerd als geschat ([neFromProtein]). Het gebeurt bij het tellen, niet in de bewaarde waarden: wat je op het
/// etiket invulde, blijft zoals het is, en een product wordt nooit twee keer omgerekend.
library;

import 'values.dart';

/// Tryptofaan als deel van het eiwit, in mg per g eiwit.
const tryptophanMgPerProteinG = 12.0;

/// mg tryptofaan per mg niacine-equivalent.
const tryptophanMgPerNe = 60.0;

/// Herkomst in `Food.estimated` voor B3 = niacine van het etiket + tryptofaan / 60 (begint met `~~`: geen product).
const neFromProtein = '~~ne:tryptophan';

/// Geeft deze verwijzing alleen voorgevormde niacine? Merkproducten (Open Food Facts `off:`, USDA Branded `fdc:`)
/// en eigen producten (`custom:`). Niet de ingebouwde databank (al in NE), supplementen (nicotinamide, geen eiwit)
/// en recepten (die tellen per ingrediënt, zie `AppState`).
bool labelNiacinRef(String ref) => ref.startsWith('off:') || ref.startsWith('fdc:') || ref.startsWith('custom:');

/// mg NE uit tryptofaan per 100 g, of null als B3 of het eiwit (en de tryptofaan) onbekend is.
double? tryptophanNe(NutrientMap n) {
  if (n['b3'] == null) return null;
  final trp = n['tryptophan']; // g
  if (trp != null) return trp * 1000 / tryptophanMgPerNe;
  final protein = n['protein'];
  if (protein == null || protein < 0) return null;
  return protein * tryptophanMgPerProteinG / tryptophanMgPerNe;
}

/// B3 als NE voor een product met alleen voorgevormde niacine ([labelNiacinRef]). [estimated] is wat al geschat is:
/// komt B3 zelf al uit een basisproduct van de databank (dus al NE), dan verandert er niets.
/// Geeft de waarden en de schattingen terug; ongewijzigd als het niet van toepassing is.
(NutrientMap, Map<String, String>) withNiacinEquivalents(NutrientMap n, String ref, {Map<String, String> estimated = const {}}) {
  if (!labelNiacinRef(ref) || estimated.containsKey('b3')) return (n, estimated);
  final extra = tryptophanNe(n);
  if (extra == null || extra <= 0) return (n, estimated);
  // Met gemeten tryptofaan is het geen schatting meer, maar gewoon de definitie
  final measured = n.containsKey('tryptophan') && !estimated.containsKey('tryptophan');
  return ({...n, 'b3': n['b3']! + extra}, measured ? estimated : {...estimated, 'b3': neFromProtein});
}
