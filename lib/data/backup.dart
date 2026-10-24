/// Volledige back-up: alles wat de gebruiker in de app maakte, in één JSON-bestand, en dat bestand weer inlezen.
///
/// Opbouw (versie [backupFormat]):
/// ```json
/// {"app": "MacroMatrix", "kind": "backup", "format": 1, "exported_at": "2026-10-24T10:00:00.000Z",
///  "tables": {"diary": [{"id": "…", "day": "2026-10-24", …}], "foods": […], "settings": […], …}}
/// ```
/// Per tabel uit [UserDb.backupTables] de rijen met dezelfde kolomnamen als in de database (zonder `synced` en
/// zonder verwijderde rijen). Onbekende tabellen en kolommen worden bij het inlezen genegeerd, zodat een back-up
/// van een nieuwere versie met hetzelfde formaat nog werkt; een hoger formaatnummer weigeren we.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../i18n.dart';
import 'user_db.dart';

/// Versie van het bestandsformaat. Ophogen als oudere versies van de app een nieuw bestand niet meer goed lezen.
const backupFormat = 1;

/// Een fout of onbruikbaar bestand, met een uitleg voor de gebruiker.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Een gelezen en gecontroleerde back-up.
class Backup {
  const Backup({required this.format, required this.exportedAt, required this.tables});

  final int format;
  final DateTime? exportedAt;
  final Map<String, List<Map<String, Object?>>> tables;

  int count(String table) => tables[table]?.length ?? 0;
  int get total => tables.values.fold(0, (a, rows) => a + rows.length);
}

/// Alles van de gebruiker als JSON-tekst.
String backupJson(UserDb db, {DateTime? now}) => jsonEncode({
  'app': 'MacroMatrix',
  'kind': 'backup',
  'format': backupFormat,
  'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
  'tables': {for (final t in UserDb.backupTables) t: db.backupRows(t)},
});

/// Kolommen met JSON erin: die moeten ook leesbaar zijn, anders loopt de app later vast op die rij.
const _jsonColumns = {'settings': 'value', 'foods': 'nutrients', 'diary': 'nutrients', 'meals': 'items', 'repeats': 'item'};

/// Een bestand lezen en controleren, zonder iets te veranderen. Gooit een [BackupException] als het geen (heel)
/// MacroMatrix-back-up is.
Backup readBackup(UserDb db, Uint8List bytes) {
  Object? root;
  try {
    var text = utf8.decode(bytes);
    if (text.startsWith('﻿')) text = text.substring(1);
    root = jsonDecode(text);
  } catch (_) {
    throw BackupException(
      tr(
        'This file cannot be read: it is not a MacroMatrix backup, or it is damaged or incomplete.',
        'Dit bestand is niet leesbaar: het is geen MacroMatrix-back-up, of het is beschadigd of onvolledig.',
      ),
    );
  }
  if (root is! Map || root['app'] != 'MacroMatrix' || root['kind'] != 'backup') {
    throw BackupException(
      tr(
        'This file is not a MacroMatrix backup. Choose a file made with "Export everything".',
        'Dit bestand is geen MacroMatrix-back-up. Kies een bestand gemaakt met "Alles exporteren".',
      ),
    );
  }
  final format = root['format'];
  if (format is! int || format < 1) {
    throw BackupException(tr('This backup has no valid format version.', 'Deze back-up heeft geen geldige formaatversie.'));
  }
  if (format > backupFormat) {
    throw BackupException(
      tr(
        'This backup was made by a newer version of MacroMatrix. Update the app and try again.',
        'Deze back-up is gemaakt met een nieuwere versie van MacroMatrix. Werk de app bij en probeer opnieuw.',
      ),
    );
  }
  final rawTables = root['tables'];
  if (rawTables is! Map) throw BackupException(tr('This backup contains no data.', 'Deze back-up bevat geen gegevens.'));

  BackupException damaged(String table, int i, String column) => BackupException(
    tr(
      'This backup is damaged: row ${i + 1} of "$table" has an invalid "$column". Nothing was changed.',
      'Deze back-up is beschadigd: rij ${i + 1} van "$table" heeft een ongeldige "$column". Er is niets veranderd.',
    ),
  );

  final tables = <String, List<Map<String, Object?>>>{};
  for (final table in UserDb.backupTables) {
    final raw = rawTables[table];
    if (raw == null) continue;
    if (raw is! List) throw damaged(table, 0, table);
    final cols = db.backupColumns(table);
    final key = UserDb.backupKey(table);
    final rows = <Map<String, Object?>>[];
    final seen = <Object?>{};
    for (var i = 0; i < raw.length; i++) {
      final r = raw[i];
      if (r is! Map) throw damaged(table, i, table);
      final row = <String, Object?>{};
      for (final c in cols) {
        final v = r[c.name];
        // Tijdstip, verwijderd-vlag en sleutel vullen we zelf in of controleren we hieronder
        if (v == null) {
          if (c.required && c.name != 'updated_at' && c.name != 'deleted') throw damaged(table, i, c.name);
          if (r.containsKey(c.name)) row[c.name] = null;
          continue;
        }
        final ok = switch (c.type) {
          'INTEGER' => v is int || v is bool || (v is double && v == v.roundToDouble()),
          'REAL' => v is num,
          _ => v is String,
        };
        if (!ok) throw damaged(table, i, c.name);
        row[c.name] = v is double && c.type == 'INTEGER' ? v.toInt() : v;
      }
      final k = row[key];
      if (k is! String || k.isEmpty || !seen.add(k)) throw damaged(table, i, key);
      if (_jsonColumns[table] case final col? when row[col] != null) {
        try {
          final decoded = jsonDecode(row[col] as String);
          if (table != 'meals' && table != 'repeats' && decoded is! Map) throw const FormatException();
        } catch (_) {
          throw damaged(table, i, col);
        }
      }
      if (table == 'diary' && (row['meal'] is! int || (row['meal'] as int) < 0 || (row['meal'] as int) >= Meal.values.length)) {
        throw damaged(table, i, 'meal');
      }
      // Sessie en synchronisatie horen niet in een back-up; zo'n rij zou je account of cursors kunnen verstoren
      if (table == 'settings' && (row['key'] as String).startsWith('_')) continue;
      rows.add(row);
    }
    tables[table] = rows;
  }
  final at = root['exported_at'];
  return Backup(format: format, exportedAt: at is String ? DateTime.tryParse(at) : null, tables: tables);
}
