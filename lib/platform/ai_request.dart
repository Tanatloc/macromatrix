/// Gedeeld voor de AI-functies op de eigen server (/api/label, /api/recipe, /api/off-contribute): het adres, het
/// versturen en het omzetten van fouten naar een code die de app kan tonen.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../sync/pro.dart' show PhotoQuota;

/// In de browser naar de eigen site (zelfde herkomst), in de app naar de vaste server.
Uri apiEndpoint(String path) => kIsWeb ? Uri.base.resolve(path) : Uri.https('app.divinenet.online', path);

/// Een fout van de server of de verbinding. [code]: login, not_configured, quota, pro_required, too_many, too_big,
/// bad_image, bad_url, unreadable, no_per100, implausible, no_recipe, timeout, fetch_failed, not_html, network of
/// failed. Bij quota de stand van de teller in [quota].
class AiException implements Exception {
  AiException(this.code, {this.quota});
  final String code;
  final PhotoQuota? quota;

  @override
  String toString() => 'AiException($code)';
}

/// Een verzoek versturen en het JSON-antwoord teruggeven. Gooit een [AiException] bij elke fout.
Future<Map> aiSend(Future<http.Response> Function(http.Client client) send, {http.Client? client, Duration timeout = const Duration(seconds: 60)}) async {
  final c = client ?? http.Client();
  try {
    final res = await send(c).timeout(timeout);
    final Map j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
    } on FormatException {
      throw AiException(res.statusCode == 429 ? 'too_many' : 'failed');
    }
    if (res.statusCode != 200) {
      final code = '${j['error'] ?? 'failed'}';
      throw AiException(code, quota: code == 'quota' ? PhotoQuota.fromJson(j) : null);
    }
    return j;
  } on AiException {
    rethrow;
  } on TimeoutException {
    throw AiException('network');
  } on http.ClientException {
    throw AiException('network');
  } on TypeError {
    throw AiException('failed');
  } catch (e) {
    // SocketException bestaat niet in de browser: andere fouten bij het versturen tellen als geen verbinding
    throw AiException(e.runtimeType.toString().contains('Socket') ? 'network' : 'failed');
  } finally {
    if (client == null) c.close();
  }
}
