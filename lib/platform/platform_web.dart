/// Browser: sqlite als WebAssembly (web/sqlite3.wasm). De voedingsdatabase staat in het geheugen; de
/// gegevens van de gebruiker in IndexedDB van de browser (tot er accounts met synchronisatie zijn).
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/services.dart';
import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:web/web.dart' as web;

import '../data/food_db.dart';
import '../data/user_db.dart';

const isWeb = true;

/// In de browser kan scannen met de camera (gsm of webcam).
bool get canScanBarcodes => true;

Future<(FoodDb, UserDb)> openDatabases() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));

  // Ingebouwde voedingsdatabase: alleen lezen, in het geheugen
  final memory = InMemoryFileSystem(name: 'voeding-mem');
  final data = await rootBundle.load(FoodDb.asset);
  memory.fileData['/foods.db'] = Uint8Buffer()..addAll(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  sqlite.registerVirtualFileSystem(memory);
  final foods = FoodDb(sqlite.open('/foods.db', vfs: 'voeding-mem', mode: OpenMode.readOnly));

  // Gegevens van de gebruiker: blijvend in de browser
  final idb = await _userFileSystem();
  sqlite.registerVirtualFileSystem(idb, makeDefault: true);
  final user = UserDb(sqlite.open('/user.db'));
  return (foods, user);
}

/// Opslag van de gebruiker in de browser. Vroeger heette die "voedingsapp": bestaat de nieuwe nog niet, dan
/// de database daaruit overnemen (de oude blijft als reserve staan).
Future<IndexedDbFileSystem> _userFileSystem() async {
  final fs = await IndexedDbFileSystem.open(dbName: 'macromatrix');
  if (fs.xAccess('/user.db', 0) != 0) return fs;
  final old = await IndexedDbFileSystem.open(dbName: 'voedingsapp');
  try {
    if (old.xAccess('/user.db', 0) != 0) {
      final src = old.xOpen(Sqlite3Filename('/user.db'), SqlFlag.SQLITE_OPEN_READONLY).file;
      final bytes = Uint8List(src.xFileSize());
      src.xRead(bytes, 0);
      src.xClose();
      final dst = fs.xOpen(Sqlite3Filename('/user.db'), SqlFlag.SQLITE_OPEN_CREATE | SqlFlag.SQLITE_OPEN_READWRITE).file;
      dst.xWrite(bytes, 0);
      dst.xClose();
      await fs.flush();
    }
  } finally {
    await old.close();
  }
  return fs;
}

/// Tekstbestand downloaden via de browser.
Future<String?> saveTextFile(String name, String content, {String subject = ''}) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'text/csv;charset=utf-8'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return null;
}
