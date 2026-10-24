/// Een etiket lezen als een barcode nergens gevonden werd (/api/label), en het product daarna (alleen als de
/// gebruiker dat wil) delen met Open Food Facts (/api/off-contribute).
///
/// De server leest de voedingswaardetabel en zet alles om naar waarden per 100 g (kJ → kcal, zout ↔ natrium). De app
/// vult daarmee het formulier voor een eigen product in; de gebruiker kijkt alles na en bewaart het zelf.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/food.dart';
import '../i18n.dart';
import '../sync/pro.dart' show PhotoQuota;
import 'ai_request.dart';

/// Wat de server van het etiket las, al per 100 g (of per 100 ml).
@immutable
class LabelResult {
  const LabelResult({
    this.name,
    this.brand,
    this.perMl = false,
    this.fromPortion = false,
    this.portionSize,
    required this.per100,
    this.warnings = const [],
  });

  final String? name, brand;

  /// Per 100 ml in plaats van 100 g (een drank); in de app geldt dat als 100 g.
  final bool perMl;

  /// Het etiket gaf alleen waarden per portie; de server rekende ze om.
  final bool fromPortion;

  /// Gewicht van één portie als het op het etiket stond.
  final double? portionSize;

  /// Zoals de server ze noemt (energy_kcal, fat, saturated_fat, carbohydrates, sugars, fiber, proteins, salt,
  /// sodium), in g per 100 g en kcal/kJ.
  final Map<String, double> per100;

  /// Wat de server wegliet of verdacht vond (energy_mismatch, dropped_sugars, ...).
  final List<String> warnings;

  static LabelResult? fromJson(Object? j) {
    if (j is! Map || j['per100'] is! Map) return null;
    final per100 = <String, double>{
      for (final e in (j['per100'] as Map).entries)
        if (e.value is num && (e.value as num).isFinite && (e.value as num) >= 0) '${e.key}': (e.value as num).toDouble(),
    };
    String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final portion = j['portion_size'];
    return LabelResult(
      name: text(j['name']),
      brand: text(j['brand']),
      perMl: j['basis'] == '100ml',
      fromPortion: j['from_portion'] == true,
      portionSize: portion is num && portion > 0 ? portion.toDouble() : null,
      per100: per100,
      warnings: [for (final w in (j['warnings'] as List?) ?? const []) '$w'],
    );
  }

  /// De waarden zoals de app ze bewaart (sleutels van nutrients.dart; natrium in mg). Ontbreekt de kcal maar staat
  /// de kJ er wel, dan omgerekend; ontbreekt het natrium maar staat het zout er, dan zout / 2,5.
  Map<String, double> get appPer100 {
    final out = <String, double>{};
    final kcal = per100['energy_kcal'] ?? (per100['energy_kj'] == null ? null : per100['energy_kj']! / 4.184);
    if (kcal != null) out['energy'] = kcal;
    for (final (from, to) in const [
      ('fat', 'fat'),
      ('saturated_fat', 'sfa'),
      ('carbohydrates', 'carbs'),
      ('sugars', 'sugars'),
      ('fiber', 'fiber'),
      ('proteins', 'protein'),
    ]) {
      if (per100[from] case final v?) out[to] = v;
    }
    final sodiumG = per100['sodium'] ?? (per100['salt'] == null ? null : per100['salt']! / 2.5);
    if (sodiumG != null) out['sodium'] = sodiumG * 1000;
    return out;
  }

  /// Een ontwerp voor het formulier van een eigen product (nog niet bewaard).
  Food toFood({String? barcode}) => Food(
    ref: 'label:draft',
    name: name ?? '',
    brand: brand,
    barcode: barcode,
    source: FoodSource.custom,
    per100g: appPer100,
    portions: [if (portionSize != null) Portion(tr('1 serving', '1 portie'), portionSize!)],
  );
}

/// De waarden van een bewaard product terug naar de velden van Open Food Facts (per 100 g; natrium en zout in g).
Map<String, double> offNutriments(Food f) {
  final v = f.per100g;
  final out = <String, double>{};
  void put(String key, double? value, [int digits = 2]) {
    if (value == null || !value.isFinite) return;
    out[key] = double.parse(value.toStringAsFixed(digits));
  }

  put('energy_kcal', v['energy'], 0);
  put('fat', v['fat']);
  put('saturated_fat', v['sfa']);
  put('carbohydrates', v['carbs']);
  put('sugars', v['sugars']);
  put('fiber', v['fiber']);
  put('proteins', v['protein']);
  if (v['sodium'] case final mg?) {
    put('sodium', mg / 1000, 3);
    put('salt', mg / 1000 * 2.5);
  }
  return out;
}

class LabelScan {
  /// Zonder [client] een nieuwe verbinding per verzoek; in tests een nagebootste client.
  LabelScan([this._client]);
  final http.Client? _client;

  /// Stand van de dagteller die de server bij de laatste scan meestuurde (null = geen teller op de server).
  PhotoQuota? lastQuota;

  /// De foto van de tabel (en eventueel de voorkant, voor de naam) opsturen. Gooit een [AiException].
  Future<LabelResult> read(Uint8List label, {Uint8List? front, required String token}) async {
    lastQuota = null;
    final j = await aiSend((c) async {
      final req = http.MultipartRequest('POST', apiEndpoint('/api/label'))
        ..headers['Authorization'] = 'Bearer $token'
        ..files.add(http.MultipartFile.fromBytes('label', label, filename: 'label.jpg'));
      if (front != null) req.files.add(http.MultipartFile.fromBytes('front', front, filename: 'front.jpg'));
      return http.Response.fromStream(await c.send(req));
    }, client: _client);
    lastQuota = PhotoQuota.fromJson(j['quota']);
    final r = LabelResult.fromJson(j);
    if (r == null) throw AiException('unreadable');
    return r;
  }
}

class OffContribute {
  OffContribute([this._client]);
  final http.Client? _client;

  bool? _configured;

  /// Staan de gegevens van het account bij Open Food Facts op de server? Bij een fout: nee (de vraag niet tonen).
  Future<bool> configured() async {
    if (_configured != null) return _configured!;
    try {
      final j = await aiSend((c) => c.get(apiEndpoint('/api/off-contribute')), client: _client, timeout: const Duration(seconds: 10));
      return _configured = j['configured'] == true;
    } on AiException {
      return false;
    }
  }

  /// Het product delen. Gooit een [AiException] (not_configured als het account er niet is).
  Future<void> share(Food food, {required Uint8List? label, Uint8List? front, required String token}) async {
    final code = food.barcode;
    if (code == null || code.isEmpty) throw AiException('bad_barcode');
    try {
      await aiSend((c) async {
        final req = http.MultipartRequest('POST', apiEndpoint('/api/off-contribute'))
          ..headers['Authorization'] = 'Bearer $token'
          ..fields['code'] = code
          ..fields['name'] = food.name
          ..fields['brand'] = food.brand ?? ''
          ..fields['nutriments'] = jsonEncode(offNutriments(food));
        if (label != null) req.files.add(http.MultipartFile.fromBytes('label', label, filename: 'label.jpg'));
        if (front != null) req.files.add(http.MultipartFile.fromBytes('front', front, filename: 'front.jpg'));
        return http.Response.fromStream(await c.send(req));
      }, client: _client);
    } on AiException catch (e) {
      if (e.code == 'not_configured') _configured = false;
      rethrow;
    }
  }
}
