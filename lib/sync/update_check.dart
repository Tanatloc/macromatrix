import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../app_version.dart';
import '../data/user_db.dart';

/// Is deze versie nog goed genoeg? Leest `app-version.json` op de website (statisch, los van de server met de
/// gegevens). Staat de versie onder `min_version`, dan toont de app alleen nog "update nodig" en stopt de sync
/// ([Account.paused]): na een verhuis van de server mag een oude versie niet meer naar de oude server schrijven.
///
/// Geen internet of een kapot bestand: de laatst gekende waarde blijft gelden (bewaard in de lokale instelling
/// `_update_check`, die niet gesynchroniseerd wordt). Nog nooit iets gekend: niets blokkeren.
///
/// Voorbeeld van het bestand:
/// `{"min_version": "1.17.0", "android_url": "...", "desktop_url": "..."}`
class UpdateCheck extends ChangeNotifier {
  UpdateCheck(this.db, {http.Client? client, this.current = appVersion}) : _client = client ?? http.Client() {
    final saved = db.setting(_key);
    _min = saved?['min'] as String?;
    _urls = (saved?['urls'] as Map?)?.cast<String, Object?>() ?? const {};
  }

  final UserDb db;
  final String current;
  final http.Client _client;

  static const _key = '_update_check';

  /// Ander adres om te testen (bv. `--dart-define=VERSION_URL=http://localhost:8000/app-version.json`).
  static const _override = String.fromEnvironment('VERSION_URL');

  /// Op het web hetzelfde adres als de app (werkt op elk domein); anders de website.
  static Uri get source =>
      _override.isNotEmpty ? Uri.parse(_override) : (kIsWeb ? Uri.base.resolve('/app-version.json') : Uri.https('macromatrix.eu', '/app-version.json'));

  String? _min;
  Map<String, Object?> _urls = const {};
  Timer? _periodic;
  AppLifecycleListener? _lifecycle;

  String? get minVersion => _min;

  /// Deze versie is te oud: alleen nog het updatescherm.
  bool get required => _min != null && compareVersions(current, _min!) < 0;

  /// Waar de nieuwe versie staat (Android/desktop); op het web volstaat herladen.
  String get updateUrl {
    final key = defaultTargetPlatform == TargetPlatform.android ? 'android_url' : 'desktop_url';
    final u = _urls[key];
    return u is String && u.startsWith('https://') ? u : 'https://github.com/Tanatloc/macromatrix-releases/releases/latest';
  }

  /// Bij de start, bij terugkeren naar de app en elke 6 uur (een tabblad kan dagen open blijven).
  void init() {
    unawaited(check());
    _periodic = Timer.periodic(const Duration(hours: 6), (_) => check());
    try {
      _lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    } catch (_) {
      // Zonder Flutter-binding (tests): niet nodig
    }
  }

  Future<void> check() async {
    try {
      final r = await _client.get(source, headers: {'Cache-Control': 'no-cache'}).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) return;
      final j = jsonDecode(r.body);
      if (j is! Map) return;
      final min = j['min_version'];
      if (min is! String || !_valid.hasMatch(min)) return;
      final urls = {for (final k in const ['android_url', 'desktop_url']) if (j[k] is String) k: j[k]};
      final was = required;
      _min = min;
      _urls = urls;
      db.setSetting(_key, {'min': min, 'urls': urls});
      if (required != was) notifyListeners();
    } catch (_) {
      // Offline of kapot antwoord: de vorige waarde blijft
    }
  }

  @override
  void dispose() {
    _periodic?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}

final _valid = RegExp(r'^\d+(\.\d+){0,2}$');

/// Vergelijkt versies als "1.17.4" (ontbrekende delen tellen als 0; een buildnummer na + telt niet mee).
int compareVersions(String a, String b) {
  List<int> parts(String v) => [for (final p in v.split('+').first.split('.')) int.tryParse(p) ?? 0];
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}
