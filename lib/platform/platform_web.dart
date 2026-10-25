/// Browser: sqlite als WebAssembly (web/sqlite3.wasm). De voedingsdatabase staat in het geheugen; de
/// gegevens van de gebruiker in IndexedDB van de browser (blijft na herladen; met een account ook op de server).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sqlite3/wasm.dart';
import 'package:typed_data/typed_buffers.dart';
import 'package:web/web.dart' as web;

import '../data/food_db.dart';
import '../data/user_db.dart';
import '../i18n.dart';

const isWeb = true;

/// In de browser kan scannen met de camera (gsm of webcam).
bool get canScanBarcodes => true;

/// Staat grafische versnelling (WebGL) aan? LibreWolf zet het standaard uit; Flutter tekent dan met de processor en de
/// app voelt traag aan (zie lib/ui/widgets/webgl_tip.dart). Bij twijfel ja: liever geen tip dan een verkeerde.
bool get graphicsAccelerated {
  try {
    final c = web.document.createElement('canvas') as web.HTMLCanvasElement;
    return c.getContext('webgl2') != null || c.getContext('webgl') != null;
  } catch (_) {
    return true;
  }
}

/// De browser vragen om de opslag van deze site niet zelf op te ruimen als de schijf vol raakt. Zonder account
/// staan je gegevens alleen hier, dus dan vragen we dat. Wissen via de browserinstellingen blijft altijd mogelijk.
Future<bool> askPersistentStorage() async {
  try {
    final storage = web.window.navigator.storage;
    if ((await storage.persisted().toDart).toDart) return true;
    return (await storage.persist().toDart).toDart;
  } catch (_) {
    // Oude browser of geen toestemming: dan blijft het gewone (best-effort) bewaren
    return false;
  }
}

// ── Eén tabblad tegelijk ──
//
// De database van de gebruiker staat in IndexedDB, maar sqlite werkt in het geheugen van het tabblad en schrijft de
// gewijzigde stukken later weg, zonder afspraak met andere tabbladen. Twee tabbladen tegelijk overschrijven zo
// elkaars stukken en maken de database stuk. Daarom houdt één tabblad een "Web Lock" vast zolang het open is; een
// tweede tabblad toont een melding (zie lib/ui/screens/other_tab_screen.dart) en kan vragen om het over te nemen.

const _lockName = 'macromatrix-user-db';

/// Het slot wordt vastgehouden tot het tabblad sluit of herlaadt (deze Future eindigt nooit).
final _hold = Completer<void>();

web.BroadcastChannel? _channel;

/// De opslag van de gebruiker, om ze weg te schrijven voor het tabblad verdwijnt.
IndexedDbFileSystem? _userFs;

/// Kan deze browser Web Locks? Zonder (oude browser, geen https): zoals vroeger, zonder bescherming.
bool get _hasLocks => web.window.navigator.has('locks') && web.window.navigator.locks.has('request');

Future<bool> _requestLock({required bool ifAvailable}) async {
  if (!_hasLocks) return true;
  final granted = Completer<bool>();
  try {
    web.window.navigator.locks.request(
      _lockName,
      web.LockOptions(mode: 'exclusive', ifAvailable: ifAvailable),
      ((web.Lock? lock) {
        if (lock == null) {
          granted.complete(false);
          return null;
        }
        granted.complete(true);
        _listenForRelease();
        return _hold.future.toJS;
      }).toJS,
    );
  } catch (_) {
    return true;
  }
  return granted.future;
}

/// De database voor dit tabblad claimen. False: ze is al open in een ander tabblad.
Future<bool> claimUserDatabase() => _requestLock(ifAvailable: true);

/// "Hier gebruiken": het andere tabblad vragen om de database vrij te geven (het schrijft alles weg en herlaadt) en
/// wachten tot dat gebeurd is, of tot het andere tabblad gesloten werd.
Future<void> takeOverUserDatabase() async {
  try {
    final c = web.BroadcastChannel(_lockName);
    c.postMessage('release'.toJS);
    c.close();
  } catch (_) {}
  await _requestLock(ifAvailable: false);
}

/// Een ander tabblad wil de database: alles wegschrijven en herladen. Het slot gaat vrij zodra deze pagina weg is;
/// na het herladen toont dit tabblad zelf de melding.
void _listenForRelease() {
  if (_channel != null) return;
  try {
    _channel = web.BroadcastChannel(_lockName)
      ..onmessage = ((web.MessageEvent e) {
        if ((e.data as JSString?)?.toDart == 'release') unawaited(_releaseAndReload());
      }).toJS;
  } catch (_) {}
}

/// De pagina herladen (nieuwe versie van de webapp), na het wegschrijven van de gegevens.
Future<void> reloadApp() => _releaseAndReload();

Future<void> _releaseAndReload() async {
  try {
    await _userFs?.flush();
  } catch (_) {}
  web.window.location.reload();
}

/// Bij het verlaten of verbergen van de pagina meteen wegschrijven (de browser kan het tabblad daarna bevriezen).
void _flushWhenHidden() {
  void flush() {
    try {
      unawaited(_userFs?.flush());
    } catch (_) {}
  }

  web.window.addEventListener('pagehide', ((web.Event _) => flush()).toJS);
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.hidden) flush();
    }).toJS,
  );
}

Future<(FoodDb, UserDb)> openDatabases() async {
  final sqlite = await WasmSqlite3.loadFromUrl(Uri.base.resolve('sqlite3.wasm'));

  // Ingebouwde voedingsdatabase: alleen lezen, in het geheugen
  final memory = InMemoryFileSystem(name: 'voeding-mem');
  memory.fileData['/foods.db'] = Uint8Buffer()..addAll(await _foodDbBytes());
  sqlite.registerVirtualFileSystem(memory);
  final foods = FoodDb(sqlite.open('/foods.db', vfs: 'voeding-mem', mode: OpenMode.readOnly));

  // Gegevens van de gebruiker: blijvend in de browser
  final idb = _userFs = await _userFileSystem();
  _flushWhenHidden();
  sqlite.registerVirtualFileSystem(idb, makeDefault: true);
  final user = UserDb(sqlite.open('/user.db'));
  return (foods, user);
}

/// De voedingsdatabase. Op de website staat ze gecomprimeerd (46 MB wordt ± 7 MB, zie tool/build_site.sh) en
/// pakt de browser ze zelf uit; een browser zonder DecompressionStream haalt de stukken van 20 MiB (Cloudflare Pages:
/// max. 25 MiB per bestand). Lokaal (flutter run) als één bestand.
Future<Uint8List> _foodDbBytes() async {
  final base = Uri.base.resolve('assets/${FoodDb.asset}');
  final packed = await _gunzipped('$base.gz');
  if (packed != null) return packed;
  final parts = await web.window.fetch('$base.parts'.toJS).toDart;
  if (parts.ok) {
    final n = int.tryParse((await parts.text().toDart).toDart.trim()) ?? 0;
    if (n > 0) {
      final out = BytesBuilder(copy: false);
      for (var i = 0; i < n; i++) {
        final r = await web.window.fetch('$base.$i'.toJS).toDart;
        if (!r.ok) throw StateError('Voedingsdatabase deel $i: HTTP ${r.status}');
        out.add((await r.arrayBuffer().toDart).toDart.asUint8List());
      }
      return out.takeBytes();
    }
  }
  final data = await rootBundle.load(FoodDb.asset);
  return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Een gzip-bestand ophalen en in de browser uitpakken. Null als het er niet is of de browser het niet kan.
Future<Uint8List?> _gunzipped(String url) async {
  try {
    if (!globalContext.has('DecompressionStream')) return null;
    final r = await web.window.fetch(url.toJS).toDart;
    if (!r.ok) return null;
    final raw = (await r.arrayBuffer().toDart).toDart.asUint8List();
    // Heeft de server het al uitgepakt (Content-Encoding), dan is het meteen de database
    if (raw.length > 16 && ascii.decode(raw.sublist(0, 15), allowInvalid: true) == 'SQLite format 3') return raw;
    if (raw.length < 2 || raw[0] != 0x1f || raw[1] != 0x8b) return null;
    final unzip = web.DecompressionStream('gzip');
    final stream = web.Blob([raw.toJS].toJS).stream().pipeThrough(web.ReadableWritablePair(readable: unzip.readable, writable: unzip.writable));
    return (await web.Response(stream).arrayBuffer().toDart).toDart.asUint8List();
  } catch (_) {
    // Kapotte download of oude browser: dan de stukken
    return null;
  }
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
Future<String?> saveTextFile(String name, String content, {String subject = '', String mime = 'text/csv'}) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: '$mime;charset=utf-8'));
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

/// Afbeelding (PNG) downloaden via de browser.
Future<String?> saveImageFile(String name, Uint8List bytes, {String text = ''}) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return tr('Image downloaded', 'Afbeelding gedownload');
}
