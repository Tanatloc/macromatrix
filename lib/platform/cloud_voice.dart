/// Spraak naar tekst via de eigen server (Whisper op Cloudflare), voor toestellen zonder bruikbare
/// spraakherkenning, zoals GrapheneOS. Neemt een korte WAV op (16 kHz mono) en stuurt die naar /api/voice.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class CloudVoice {
  final _rec = AudioRecorder();
  String? _path;

  /// Eerder gemerkt dat dit toestel geen eigen spraakherkenning heeft: dan meteen zo.
  static bool needed = false;

  Future<bool> start() async {
    if (!await _rec.hasPermission()) return false;
    // In de browser negeert de recorder het pad en geeft hij bij stop een blob-adres terug
    _path = kIsWeb ? 'quicklog.wav' : '${(await getTemporaryDirectory()).path}/quicklog.wav';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1), path: _path!);
    return true;
  }

  Future<void> cancel() async {
    if (await _rec.isRecording()) await _rec.stop();
  }

  /// Stoppen en de tekst ophalen. Gooit een [CloudVoiceException] met een code (login, network, failed).
  Future<String> stopAndTranscribe({required String token, required String lang}) async {
    final path = await _rec.stop() ?? _path;
    if (path == null) return '';
    final file = kIsWeb ? null : File(path);
    try {
      final bytes = kIsWeb ? (await http.get(Uri.parse(path))).bodyBytes : await file!.readAsBytes();
      final uri = kIsWeb
          ? Uri.base.resolve('/api/voice').replace(queryParameters: {'lang': lang})
          : Uri.https('macromatrix.eu', '/api/voice', {'lang': lang});
      final res = await http
          .post(uri, headers: {'Authorization': 'Bearer $token', 'Content-Type': 'audio/wav'}, body: bytes)
          .timeout(const Duration(seconds: 40));
      final j = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      if (res.statusCode != 200) throw CloudVoiceException('${j['error'] ?? 'failed'}');
      return (j['text'] as String?) ?? '';
    } on SocketException {
      throw CloudVoiceException('network');
    } on FormatException {
      throw CloudVoiceException('failed');
    } finally {
      if (file != null && file.existsSync()) file.deleteSync();
    }
  }

  void dispose() => _rec.dispose();
}

class CloudVoiceException implements Exception {
  CloudVoiceException(this.code);
  final String code;
}
