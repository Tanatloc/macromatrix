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

/// Opent de ingebouwde voedingsdatabase (gekopieerd naar de app-map, opnieuw na een update) en de
/// database van de gebruiker.
Future<(FoodDb, UserDb)> openDatabases() async {
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  final data = await rootBundle.load(FoodDb.asset);
  final file = File(p.join(dir.path, 'foods.db'));
  if (!file.existsSync() || file.lengthSync() != data.lengthInBytes) {
    await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  }
  final foods = FoodDb(sqlite3.open(file.path, mode: OpenMode.readOnly));
  final user = UserDb(sqlite3.open(p.join(dir.path, 'user.db')));
  return (foods, user);
}

/// Alleen de database van de gebruiker (voor taken op de achtergrond, zonder de grote voedingsdatabase).
Future<UserDb> openUserDbOnly() async {
  final dir = await getApplicationSupportDirectory();
  return UserDb(sqlite3.open(p.join(dir.path, 'user.db')));
}

/// Tekstbestand bewaren: op de gsm via "Delen", op de pc in de map Downloads. Geeft een melding terug.
Future<String?> saveTextFile(String name, String content, {String subject = ''}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final file = File(p.join((await getTemporaryDirectory()).path, name));
    await file.writeAsString(content);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], subject: subject));
    return null;
  }
  final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path, name));
  await file.writeAsString(content);
  return tr('Saved to ${file.path}', 'Opgeslagen in ${file.path}');
}
