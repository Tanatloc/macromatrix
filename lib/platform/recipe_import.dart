/// Een recept importeren uit een link of een foto van een kookboekpagina (/api/recipe, alleen Pro).
///
/// De server geeft de naam, het aantal porties en de ingrediënten als regels tekst (bij een link de JSON-LD
/// recipeIngredient zoals die op de pagina staat). De app leest en zoekt elke regel met nutrition/recipe_line.dart;
/// [cleanRecipeLine] blijft voor de zoekterm bij "Zoeken".
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../sync/pro.dart' show PhotoQuota;
import 'ai_request.dart';

/// Wat de server van het recept las.
@immutable
class RecipeDraft {
  const RecipeDraft({this.name, this.servings, required this.ingredients, this.source});
  final String? name;
  final int? servings;
  final List<String> ingredients;

  /// jsonld, ai of photo.
  final String? source;

  static RecipeDraft? fromJson(Object? j) {
    if (j is! Map || j['ingredients'] is! List) return null;
    final lines = [
      for (final l in j['ingredients'] as List)
        if (l is String && l.trim().isNotEmpty) l.trim(),
    ];
    if (lines.isEmpty) return null;
    final s = j['servings'];
    return RecipeDraft(
      name: j['name'] is String && (j['name'] as String).trim().isNotEmpty ? (j['name'] as String).trim() : null,
      servings: s is num && s >= 1 && s <= 1000 ? s.round() : null,
      ingredients: lines,
      source: j['source'] as String?,
    );
  }
}

const _fractions = {'½': 0.5, '¼': 0.25, '¾': 0.75, '⅓': 1 / 3, '⅔': 2 / 3, '⅛': 0.125, '⅕': 0.2, '⅙': 1 / 6};

String _num(double v) {
  final r = double.parse(v.toStringAsFixed(2));
  return r == r.roundToDouble() ? '${r.round()}' : '$r';
}

/// Een ingrediëntregel van een recept opkuisen voor de parser van Snel loggen:
/// "1 ½ cups flour, sifted" → "1.5 cups flour", "8 oz cheddar (grated)" → "227 g cheddar",
/// "1 (400 g) can tomatoes" → "400 g tomatoes", "salt, to taste" → "salt".
String cleanRecipeLine(String line) {
  var t = line.trim().replaceAll(RegExp(r'^[-–•*▢☐□·]+\s*'), '');
  // Breuken als teken ("1½", "1 ½", "½")
  t = t.replaceAllMapped(RegExp('(\\d+)?\\s*([${_fractions.keys.join()}])'), (m) {
    final whole = m.group(1) == null ? 0 : int.parse(m.group(1)!);
    return '${_num(whole + _fractions[m.group(2)]!)} ';
  });
  // Breuken als tekst ("1 1/2", "3/4")
  t = t.replaceAllMapped(RegExp(r'(?:(\d+)\s+)?(\d+)\s*/\s*(\d+)'), (m) {
    final whole = m.group(1) == null ? 0 : int.parse(m.group(1)!);
    final d = int.parse(m.group(3)!);
    if (d == 0) return m.group(0)!;
    return _num(whole + int.parse(m.group(2)!) / d);
  });
  // Een bereik ("2-3 tomatoes"): het eerste getal
  t = t.replaceFirstMapped(RegExp(r'^(\d+(?:[.,]\d+)?)\s*(?:-|–|to|tot)\s*\d+(?:[.,]\d+)?'), (m) => m.group(1)!);
  // Een gewicht tussen haakjes ("1 (400 g) can tomatoes") gaat voor op het aantal blikken
  final inParens = RegExp(r'\((\d+(?:[.,]\d+)?)\s*(g|gr|ml|kg|l|cl)\)', caseSensitive: false).firstMatch(t);
  t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  if (inParens != null && !RegExp(r'^\d+(?:[.,]\d+)?\s*(g|gr|ml|kg|l|cl)\b', caseSensitive: false).hasMatch(t.trim())) {
    final rest = t.trim().replaceFirst(RegExp(r'^1\s+'), '').replaceFirst(RegExp(r'^(cans?|tins?|jars?|packs?|blik(je)?|pot(je)?|pak(je)?)\s+(of\s+)?', caseSensitive: false), '');
    if (!RegExp(r'^\d').hasMatch(rest)) t = '${inParens.group(1)} ${inParens.group(2)!.toLowerCase()} $rest';
  }
  // Ounces en ponden naar gram
  t = t.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*(fl\.?\s*oz|oz|ounces?|lbs?|pounds?)\b\.?', caseSensitive: false), (m) {
    final n = double.parse(m.group(1)!.replaceAll(',', '.'));
    final u = m.group(2)!.toLowerCase();
    if (u.startsWith('fl')) return '${_num((n * 29.57).roundToDouble())} ml';
    if (u.startsWith('l') || u.startsWith('p')) return '${_num((n * 453.6).roundToDouble())} g';
    return '${_num((n * 28.35).roundToDouble())} g';
  });
  // Alles na de eerste komma (geen decimale komma): "fijngehakt", "to taste", "plus extra"
  t = t.replaceFirst(RegExp(r'(?<!\d),(?!\d).*$'), '');
  // "butter or margarine": het eerste
  t = t.replaceFirst(RegExp(r'\s+or\s+.*$', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'\b(to taste|naar smaak|optional|optioneel|for serving|om te serveren)\b', caseSensitive: false), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'[\s.;:]+$'), '').trim();
}

class RecipeImport {
  RecipeImport([this._client]);
  final http.Client? _client;

  /// Stand van de dagteller die de server meestuurde.
  PhotoQuota? lastQuota;

  /// Een recept uit een link. Gooit een [AiException] (pro_required zonder Pro).
  Future<RecipeDraft> fromLink(String url, {required String token}) => _send(
    (c) => c.post(
      apiEndpoint('/api/recipe'),
      headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
      body: jsonEncode({'url': url.trim()}),
    ),
  );

  /// Een recept uit een verkleinde JPEG van een kookboekpagina.
  Future<RecipeDraft> fromPhoto(Uint8List jpeg, {required String token}) => _send(
    (c) => c.post(apiEndpoint('/api/recipe'), headers: {'Authorization': 'Bearer $token', 'Content-Type': 'image/jpeg'}, body: jpeg),
  );

  Future<RecipeDraft> _send(Future<http.Response> Function(http.Client) send) async {
    lastQuota = null;
    final j = await aiSend(send, client: _client);
    lastQuota = PhotoQuota.fromJson(j['quota']);
    final d = RecipeDraft.fromJson(j);
    if (d == null) throw AiException('no_recipe');
    return d;
  }
}
