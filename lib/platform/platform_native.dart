/// Gsm (Android) en pc (Linux, Windows).
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/food_db.dart';
import '../data/user_db.dart';
import '../i18n.dart';

const isWeb = false;

/// Barcode scannen met de camera kan op gsm, niet op een pc.
bool get canScanBarcodes => Platform.isAndroid || Platform.isIOS;

/// Alleen nodig in de browser (zie platform_web.dart); hier staat de database gewoon in de app-map.
Future<bool> askPersistentStorage() async => true;

/// Alleen in de browser kan de app twee keer tegelijk open staan (twee tabbladen, zie platform_web.dart).
Future<bool> claimUserDatabase() async => true;

Future<void> takeOverUserDatabase() async {}

/// Alleen op het web: daar volstaat herladen voor een nieuwe versie.
Future<void> reloadApp() async {}

/// Opent de ingebouwde voedingsdatabase (gekopieerd naar de app-map, opnieuw na een update) en de
/// database van de gebruiker.
Future<(FoodDb, UserDb)> openDatabases() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  _moveFromOldName(dir);
  final data = await rootBundle.load(FoodDb.asset);
  final file = File(p.join(dir.path, 'foods.db'));
  if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  }
  final foods = FoodDb(sqlite3.open(file.path, mode: OpenMode.readOnly));
  final user = UserDb(sqlite3.open(p.join(dir.path, 'user.db')));
  return (foods, user);
}

/// Op de pc stond de database eerst in een map met de oude naam (online.divinenet.voedingsapp). Bestaat er nog
/// geen database onder de nieuwe naam, dan die overnemen (de oude map blijft als reserve).
void _moveFromOldName(Directory dir) {
  if (!Platform.isLinux && !Platform.isWindows) return;
  if (File(p.join(dir.path, 'user.db')).existsSync()) return;
  final old = Directory(dir.path.replaceAll('macromatrix', 'voedingsapp'));
  if (old.path == dir.path) return;
  for (final name in ['user.db', 'user.db-wal', 'user.db-shm']) {
    final f = File(p.join(old.path, name));
    if (f.existsSync()) f.copySync(p.join(dir.path, name));
  }
}

/// Alleen de database van de gebruiker (voor taken op de achtergrond, zonder de grote voedingsdatabase).
Future<UserDb> openUserDbOnly() async {
  final dir = await getApplicationSupportDirectory();
  return UserDb(sqlite3.open(p.join(dir.path, 'user.db')));
}

/// Tekstbestand bewaren: op de gsm via "Delen", op de pc in de map Downloads. Geeft een melding terug.
/// [mime] is het soort bestand (CSV of JSON), voor de apps waarmee je deelt.
Future<String?> saveTextFile(String name, String content, {String subject = '', String mime = 'text/csv'}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final file = File(p.join((await getTemporaryDirectory()).path, name));
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mime)],
        subject: subject,
      ),
    );
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, name));
  await file.writeAsString(content);
  return tr('Saved to ${file.path}', 'Opgeslagen in ${file.path}');
}

/// Afbeelding (PNG) delen: op de gsm via "Delen" (Instagram, WhatsApp, ...), op de pc in de map Downloads.
/// Geeft een melding terug als er niet gedeeld werd maar bewaard.
Future<String?> saveImageFile(String name, Uint8List bytes, {String text = ''}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final file = File(p.join((await getTemporaryDirectory()).path, name));
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: text.isEmpty ? null : text,
      ),
    );
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, name));
  await file.writeAsBytes(bytes);
  return tr('Saved to ${file.path}', 'Opgeslagen in ${file.path}');
}
