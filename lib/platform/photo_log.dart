/// Foto van je bord naar een zin voor Snel loggen, via de eigen server (/api/photo, een beeldmodel op Cloudflare).
/// De foto wordt eerst op het toestel verkleind (hoogstens 1024 px, JPEG 80) en daarna niet bewaard.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../sync/pro.dart' show PhotoQuota;

/// Langste zijde en JPEG-kwaliteit van wat we opsturen: genoeg om eten te herkennen, klein genoeg voor mobiele data.
const photoMaxSide = 1024;
const photoQuality = 80;

/// Een foto rechtzetten (EXIF), verkleinen tot [photoMaxSide] en als JPEG bewaren. Draait in een aparte isolate.
Uint8List shrinkPhoto(Uint8List data) {
  final src = img.decodeImage(data);
  if (src == null) throw const FormatException('no image');
  final upright = img.bakeOrientation(src);
  final long = upright.width > upright.height ? upright.width : upright.height;
  final small = long <= photoMaxSide
      ? upright
      : upright.width >= upright.height
      ? img.copyResize(upright, width: photoMaxSide, interpolation: img.Interpolation.average)
      : img.copyResize(upright, height: photoMaxSide, interpolation: img.Interpolation.average);
  return img.encodeJpg(small, quality: photoQuality);
}

class PhotoLog {
  /// Zonder [client] een nieuwe verbinding per foto; in tests een nagebootste client.
  PhotoLog([this._client]);
  final http.Client? _client;

  /// Stand van de dagteller die de server bij de laatste foto meestuurde (null = geen teller op de server).
  PhotoQuota? lastQuota;

  /// In de browser naar de eigen site (zelfde herkomst), in de app naar de vaste server.
  static Uri get endpoint => kIsWeb ? Uri.base.resolve('/api/photo') : Uri.https('app.divinenet.online', '/api/photo');

  /// De verkleinde foto opsturen en de zin terugkrijgen (leeg = geen eten gezien). Gooit een [PhotoLogException]
  /// met een code: login, not_configured, quota (gratis foto's van vandaag op, met [PhotoLogException.quota]),
  /// too_many, too_big, bad_image, network of failed.
  Future<String> describe(Uint8List jpeg, {required String token}) async {
    final client = _client ?? http.Client();
    lastQuota = null;
    try {
      final res = await client
          .post(endpoint, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'image/jpeg'}, body: jpeg)
          .timeout(const Duration(seconds: 45));
      final Map j;
      try {
        j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      } on FormatException {
        throw PhotoLogException(res.statusCode == 429 ? 'too_many' : 'failed');
      }
      if (res.statusCode != 200) {
        final code = '${j['error'] ?? 'failed'}';
        throw PhotoLogException(code, quota: code == 'quota' ? PhotoQuota.fromJson(j) : null);
      }
      lastQuota = PhotoQuota.fromJson(j['quota']);
      return ((j['text'] as String?) ?? '').trim();
    } on PhotoLogException {
      rethrow;
    } on TimeoutException {
      throw PhotoLogException('network');
    } on http.ClientException {
      throw PhotoLogException('network');
    } on TypeError {
      throw PhotoLogException('failed');
    } catch (e) {
      // SocketException bestaat niet in de browser: andere fouten bij het versturen tellen als geen verbinding
      throw PhotoLogException(e.runtimeType.toString().contains('Socket') ? 'network' : 'failed');
    } finally {
      if (_client == null) client.close();
    }
  }
}

class PhotoLogException implements Exception {
  PhotoLogException(this.code, {this.quota});
  final String code;

  /// Bij code quota: hoeveel je vandaag gebruikte en hoeveel er mogen.
  final PhotoQuota? quota;

  @override
  String toString() => 'PhotoLogException($code)';
}
