/// Voedingsvoorkeuren en beperkingen. Suggesties en "beste bronnen" laten producten weg die er niet bij passen.
///
/// Herkenning gebeurt op de naam (Engels, Frans, Zweeds en Noors, de talen van de databanken). Dat is een
/// benadering: een allergie of medisch dieet controleer je altijd op het etiket.
library;

import '../data/food.dart';
import '../i18n.dart';

enum DietPref {
  pescatarian('Pescatarian', 'Pescotarisch'),
  vegetarian('Vegetarian', 'Vegetarisch'),
  vegan('Vegan', 'Veganistisch'),
  lactoseFree('Lactose-free', 'Lactosevrij'),
  glutenFree('Gluten-free', 'Glutenvrij'),
  noNuts('No nuts', 'Geen noten'),
  noPork('No pork', 'Geen varkensvlees'),
  noAlcohol('No alcohol', 'Geen alcohol'),
  lowSugar('Low sugar', 'Weinig suiker'),
  carnivore('Carnivore', 'Carnivore'),
  animalBased('Animal-based', 'Animal-based');

  const DietPref(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);
}

const _meat = [
  'beef', 'pork', 'chicken', 'turkey', 'lamb', 'mutton', 'veal', 'ham', 'bacon', 'sausage', 'salami', 'duck', 'goose', //
  'venison', 'rabbit', 'horse', 'meat', 'chorizo', 'prosciutto', 'frankfurter', 'pepperoni', 'jerky', 'gelatin', //
  'lard', 'tallow', 'boeuf', 'bœuf', 'porc', 'poulet', 'dinde', 'agneau', 'veau', 'jambon', 'saucisse', 'canard', 'viande', //
  'kyckling', 'kalv', 'lamm', 'korv', 'skinka', 'fläsk', 'nötkött', 'storfe', 'svin', 'kylling', 'pølse', 'skinke', 'kjøtt', //
];
const _fish = [
  'fish', 'salmon', 'tuna', 'cod', 'herring', 'mackerel', 'sardine', 'sardines', 'anchovy', 'trout', 'shrimp', 'prawn', //
  'crab', 'lobster', 'mussel', 'mussels', 'oyster', 'clam', 'squid', 'octopus', 'scallop', 'roe', 'caviar', 'pollock', //
  'haddock', 'plaice', 'sole', 'eel', 'saithe', 'halibut', 'poisson', 'saumon', 'thon', 'cabillaud', 'hareng', 'maquereau', //
  'crevette', 'moule', 'huître', 'crabe', 'fisk', 'lax', 'sill', 'torsk', 'makrill', 'räkor', 'laks', 'sild', 'makrell', 'reker', //
];
const _dairy = [
  'milk', 'cheese', 'yogurt', 'yoghurt', 'butter', 'cream', 'whey', 'casein', 'kefir', 'skyr', 'quark', 'curd', 'ghee', //
  'lait', 'fromage', 'yaourt', 'beurre', 'crème', 'mjölk', 'ost', 'smör', 'grädde', 'melk', 'smør', 'fløte', //
];
const _egg = ['egg', 'eggs', 'oeuf', 'œuf', 'oeufs', 'ägg'];
const _honey = ['honey', 'miel', 'honung', 'honning'];
const _gluten = [
  'wheat', 'barley', 'rye', 'spelt', 'bread', 'pasta', 'couscous', 'bulgur', 'semolina', 'cracker', 'biscuit', 'cake', //
  'pizza', 'beer', 'seitan', 'malt', 'blé', 'orge', 'seigle', 'pain', 'pâtes', 'vete', 'råg', 'bröd', 'hvete', 'bygg', 'rug', 'brød', //
];
const _nuts = [
  'nut', 'nuts', 'almond', 'almonds', 'walnut', 'walnuts', 'hazelnut', 'hazelnuts', 'cashew', 'cashews', 'pistachio', //
  'pistachios', 'pecan', 'pecans', 'macadamia', 'peanut', 'peanuts', 'amande', 'noix', 'noisette', 'cacahuète', 'pistache', //
  'mandel', 'mandlar', 'nøtt', 'nøtter', 'peanøtt', 'jordnöt', //
];
const _pork = ['pork', 'ham', 'bacon', 'prosciutto', 'salami', 'chorizo', 'lard', 'gelatin', 'porc', 'jambon', 'fläsk', 'skinka', 'svin', 'skinke'];
const _alcohol = ['beer', 'wine', 'liquor', 'vodka', 'whisky', 'whiskey', 'rum', 'gin', 'liqueur', 'cider', 'vin', 'bière', 'öl', 'øl'];

const _organ = [
  'liver', 'heart', 'kidney', 'tongue', 'tripe', 'marrow', 'broth', 'gizzard', 'sweetbread', 'offal', 'foie', 'rognon', //
  'coeur', 'langue', 'lever', 'njure', 'hjärta', 'nyre', 'hjerte', //
];
// Plantaardig of bewerkt: valt buiten carnivore. Ook categorieën van de databanken (bv. "Vegetables and Vegetable Products").
const _plants = [
  'vegetable', 'vegetables', 'fruit', 'fruits', 'legume', 'legumes', 'bean', 'beans', 'lentil', 'lentils', 'pea', 'peas', //
  'chickpea', 'chickpeas', 'soy', 'soya', 'tofu', 'tempeh', 'grain', 'grains', 'cereal', 'cereals', 'rice', 'oat', 'oats', //
  'corn', 'maize', 'flour', 'potato', 'potatoes', 'tomato', 'tomatoes', 'salad', 'lettuce', 'spinach', 'cabbage', 'onion', //
  'garlic', 'carrot', 'carrots', 'apple', 'banana', 'orange', 'berries', 'berry', 'grape', 'grapes', 'juice', 'sugar', 'sweets', //
  'candy', 'chocolate', 'cocoa', 'jam', 'syrup', 'honey', 'seed', 'seeds', 'oil', 'margarine', 'baked', 'snacks', 'soda', //
  'légume', 'légumes', 'riz', 'pomme', 'sucre', 'farine', 'huile', 'grönsaker', 'frukt', 'ris', 'potatis', 'socker', 'mjöl', //
  'olja', 'grønnsaker', 'poteter', 'sukker', 'mel', 'olje', 'havre', 'bönor', 'bønner', //
];
// Animal-based laat granen, peulvruchten, noten, zaden, zaadoliën en de meeste groenten weg; fruit, honing en
// ahornsiroop mogen wel. Een paar "zachte" groenten (pompoen, komkommer, courgette, avocado, olijf) ook.
const _animalBasedOut = [
  'vegetable', 'vegetables', 'legume', 'legumes', 'bean', 'beans', 'lentil', 'lentils', 'pea', 'peas', 'chickpea', 'chickpeas', //
  'soy', 'soya', 'tofu', 'tempeh', 'grain', 'grains', 'cereal', 'cereals', 'rice', 'oat', 'oats', 'corn', 'maize', 'flour', //
  'seed', 'seeds', 'margarine', 'sunflower', 'rapeseed', 'canola', 'cottonseed', 'safflower', 'potato', 'potatoes', 'tomato', //
  'tomatoes', 'spinach', 'kale', 'lettuce', 'broccoli', 'cabbage', 'cauliflower', 'eggplant', 'aubergine', 'candy', 'soda', //
  'légume', 'légumes', 'riz', 'farine', 'grönsaker', 'ris', 'mjöl', 'grønnsaker', 'mel', 'havre', 'bönor', 'bønner', //
];
final _softPlants = RegExp(r'squash|pumpkin|cucumber|zucchini|courgette|avocado|olive');
final _seedOil = RegExp(r'(vegetable|sunflower|rapeseed|canola|soybean|soy|corn|cottonseed|safflower|grapeseed|peanut) oil');

final _plantDairy = RegExp(
  r'(peanut|almond|cashew|cocoa|nut|seed|sesame|coconut|soy|soya|oat|rice|hazelnut|shea) (butter|milk|cream|drink|yogurt|yoghurt)',
);
final _lactoseFree = RegExp(r'lactose[- ]?free|sans lactose|laktosfri|laktosefri');

/// Past dit product bij alle gekozen voorkeuren?
bool fitsPreferences(Food f, Set<DietPref> prefs) {
  if (prefs.isEmpty) return true;
  final full = '${f.name} ${f.localName ?? ''} ${f.category ?? ''}'.toLowerCase();
  Set<String> tokens(String s) => s.split(RegExp(r'[^a-zà-ÿœæøå]+')).toSet();
  final words = tokens(full);
  // Plantaardige "melk" en "boter" (pindakaas, amandelmelk, kokosroom) zijn geen zuivel
  final dairyWords = tokens(full.replaceAll(_plantDairy, ' '));
  bool any(List<String> list, [Set<String>? w]) => list.any((w ?? words).contains);
  bool dairy() => any(_dairy, dairyWords);
  final v = f.per100g;
  for (final p in prefs) {
    final excluded = switch (p) {
      DietPref.pescatarian => any(_meat),
      DietPref.vegetarian => any(_meat) || any(_fish),
      DietPref.vegan => any(_meat) || any(_fish) || dairy() || any(_egg) || any(_honey),
      DietPref.lactoseFree => dairy() && !_lactoseFree.hasMatch(full),
      DietPref.glutenFree => any(_gluten),
      DietPref.noNuts => any(_nuts),
      DietPref.noPork => any(_pork),
      DietPref.noAlcohol => any(_alcohol) || (v['alcohol'] ?? 0) > 0.5,
      DietPref.lowSugar => (v['sugars'] ?? 0) > 15,
      // Alleen dierlijk: vlees, orgaanvlees, vis, eieren en zuivel, zonder plantaardige of suikerhoudende producten
      DietPref.carnivore => !(any(_meat) || any(_fish) || any(_egg) || any(_organ) || dairy()) || any(_plants) || any(_nuts),
      DietPref.animalBased => (any(_animalBasedOut) || any(_nuts) || _seedOil.hasMatch(full)) && !_softPlants.hasMatch(full),
    };
    if (excluded) return false;
  }
  return true;
}
