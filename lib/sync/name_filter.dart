/// Een eenvoudig woordfilter voor wat vrienden van je zien: je vriendennaam en de titel van een uitdaging.
///
/// De server weigert hetzelfde (supabase/migrations/20261105100000_moderation.sql, public.text_blocked); hier
/// gebeurt het meteen, zodat je niet op de server moet wachten. Beide lijsten moeten gelijk blijven:
/// test/review_r11_test.dart vergelijkt ze.
///
/// Alleen hele woorden (of een woordbegin uit [blockedStems]), nooit stukjes van een woord: "Scunthorpe",
/// "shiitake" of "catering" mogen gewoon.
library;

import 'package:supabase/supabase.dart';

import '../i18n.dart';

/// Hele woorden (na [normalizeForFilter]) die niet mogen, Engels en Nederlands. Met een spatie: een vaste reeks.
const blockedWords = <String>[
  // Engels
  'shit', 'shits', 'shitty', 'shithead', 'bullshit', 'bitch', 'bitches', 'bitchy', 'asshole', 'assholes',
  'arsehole', 'arseholes', 'dickhead', 'dickheads', 'pussy', 'bastard', 'bastards', 'wanker', 'wankers', 'wanking',
  'twat', 'twats', 'retard', 'retarded', 'retards', 'tranny', 'trannies', 'kike', 'kikes', 'nazi', 'nazis',
  'hitler', 'kkk', 'nigga', 'niggas', 'niggaz', 'rapist', 'rapists', 'pedo', 'paedo', 'pedophile', 'paedophile', 'kys',
  'heil hitler', 'sieg heil', 'white power', 'kill yourself',
  // Nederlands
  'kut', 'kutje', 'kutwijf', 'kutwijven', 'klootzak', 'klootzakken', 'lul', 'hoer', 'hoeren', 'hoerig',
  'hoerenzoon', 'kankerlijer', 'kankerhoer', 'kankerjood', 'kankerwijf', 'kankerzooi', 'kankermongool',
  'kankerhomo', 'kankerneger', 'tering', 'teringlijer', 'tyfus', 'tyfuslijer', 'pleurislijer', 'godverdomme',
  'godverdomse', 'neuk', 'neuken', 'neuker', 'neukt', 'flikker', 'flikkers', 'nikker', 'nikkers', 'mongool',
  'mongolen', 'slet', 'sletten', 'sletje',
];

/// Woordbegin dat niet mag (fuck, fucking, fucker, ...). Alleen stammen waarmee geen gewoon woord begint.
const blockedStems = <String>['fuck', 'motherfuck', 'cunt', 'nigger', 'faggot', 'whore', 'slut', 'cocksuck', 'porn'];

const _from = 'áàâäãåéèêëíìîïóòôöõúùûüçñ013457@\$';
const _to = 'aaaaaaeeeeiiiiooooouuuucnoieastas';

/// Kleine letters, accenten weg, cijfers die als letters gebruikt worden (sh1t, 5hit), drie of meer dezelfde letters
/// na elkaar worden er één (fuuuck), en alles wat geen letter is wordt een spatie. Met een spatie vooraan en
/// achteraan, zodat " woord " een heel woord betekent. Zoals translate/regexp_replace in text_blocked.
String normalizeForFilter(String s) {
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = _from.indexOf(ch);
    b.write(i < 0 ? ch : _to[i]);
  }
  final t = b.toString().replaceAllMapped(RegExp(r'(.)\1\1+'), (m) => m[1]!).replaceAll(RegExp(r'[^a-z]+'), ' ').trim();
  return ' $t ';
}

/// Bevat de tekst een geweigerd woord?
bool textBlocked(String? s) {
  if (s == null || s.trim().isEmpty) return false;
  final t = normalizeForFilter(s);
  return blockedWords.any((w) => t.contains(' $w ')) || blockedStems.any((w) => t.contains(' $w'));
}

/// De melding bij een geweigerde naam.
String get nameNotAllowedText => tr(
  "That name isn't allowed. Choose a name without offensive words; friends can see it.",
  'Die naam mag niet. Kies een naam zonder kwetsende woorden; je vrienden zien hem.',
);

/// De melding bij een geweigerde titel van een uitdaging.
String get titleNotAllowedText => tr(
  "That challenge name isn't allowed. Choose one without offensive words; everyone in the challenge can see it.",
  'Die naam voor de uitdaging mag niet. Kies er een zonder kwetsende woorden; iedereen in de uitdaging ziet hem.',
);

/// Weigerde de server een naam (name_not_allowed) of titel (title_not_allowed)? Dan de vriendelijke melding.
String? moderationMessage(Object e) {
  if (e is! PostgrestException) return null;
  final m = '${e.message} ${e.details ?? ''}';
  if (m.contains('name_not_allowed')) return nameNotAllowedText;
  if (m.contains('title_not_allowed')) return titleNotAllowedText;
  return null;
}
