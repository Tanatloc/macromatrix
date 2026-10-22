/// Lokale database van de gebruiker: dagboek, eigen producten, bewaarde producten en instellingen.
///
/// Klaar voor synchronisatie met een account: elke rij heeft een UUID, een tijdstip van de laatste
/// wijziging en een "deleted"-vlag in plaats van echt te verwijderen.
library;

import 'dart:convert';

import 'package:sqlite3/common.dart';
import 'package:uuid/uuid.dart';

import '../nutrition/supplements.dart';
import '../nutrition/values.dart';
import 'food.dart';
import 'off_client.dart' show checkEnergy;
import '../i18n.dart';
import '../import/importer.dart';
import '../labs/lab_report.dart';
import '../labs/markers.dart';
import 'models.dart';

enum Meal {
  breakfast('Breakfast', 'Ontbijt'),
  lunch('Lunch', 'Lunch'),
  dinner('Dinner', 'Avondeten'),
  snacks('Snack', 'Snack');

  const Meal(this.en, this.nl);
  final String en, nl;
  String get label => tr(en, nl);

  /// Logische maaltijd voor het huidige uur.
  static Meal forHour(int h) => h < 11
      ? breakfast
      : h < 16
      ? lunch
      : h < 21
      ? dinner
      : snacks;
}

class DiaryEntry {
  const DiaryEntry({
    required this.id,
    required this.day,
    required this.meal,
    required this.foodRef,
    required this.name,
    required this.grams,
    required this.quantity,
    required this.per100g,
    this.brand,
    this.portionLabel,
    this.time,
  });

  final String id;

  /// Tijdstip als "uu:mm", of null.
  final String? time;

  /// Dag als "jjjj-mm-dd".
  final String day;
  final Meal meal;

  /// Verwijzing naar het voedingsmiddel (zie [Food.ref]).
  final String foodRef;
  final String name;
  final String? brand;

  /// Totale hoeveelheid in gram.
  final double grams;

  /// Gekozen portie (null = gram) en hoeveel daarvan.
  final String? portionLabel;
  final double quantity;

  /// Voedingswaarden per 100 g zoals ze waren bij het toevoegen.
  final NutrientMap per100g;

  NutrientMap get amounts => scale(per100g, grams);

  double get kcal => (per100g['energy'] ?? 0) * grams / 100;
}

/// Een tabel die gesynchroniseerd wordt: naam, sleutelkolom en kolommen.
class SyncTable {
  const SyncTable(this.name, this.key, this.columns);
  final String name;
  final String key;
  final List<String> columns;
}

class UserDb {
  /// Opent de gebruikersdatabase en werkt het schema bij. Openen gebeurt per platform (lib/platform/).
  UserDb(this._db) {
    _migrate();
  }

  final CommonDatabase _db;
  static const _uuid = Uuid();

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version < 1) {
      _db.execute('''
        CREATE TABLE foods (
          id TEXT PRIMARY KEY,
          source TEXT NOT NULL,
          name TEXT NOT NULL,
          brand TEXT,
          barcode TEXT,
          nutrients TEXT NOT NULL,
          portions TEXT,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX foods_barcode ON foods(barcode);
        CREATE TABLE diary (
          id TEXT PRIMARY KEY,
          day TEXT NOT NULL,
          meal INTEGER NOT NULL,
          food_ref TEXT NOT NULL,
          name TEXT NOT NULL,
          brand TEXT,
          grams REAL NOT NULL,
          portion_label TEXT,
          quantity REAL NOT NULL,
          nutrients TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX diary_day ON diary(day);
        CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL);
        PRAGMA user_version = 1;
      ''');
    }
    if (version < 2) {
      _db.execute('''
        ALTER TABLE foods ADD COLUMN extra TEXT;
        ALTER TABLE diary ADD COLUMN time TEXT;
        ALTER TABLE diary ADD COLUMN repeat_id TEXT;
        CREATE TABLE meals (id TEXT PRIMARY KEY, name TEXT NOT NULL, items TEXT NOT NULL,
          updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE biometrics (id TEXT PRIMARY KEY, day TEXT NOT NULL, time TEXT, type TEXT NOT NULL,
          value REAL NOT NULL, value2 REAL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX biometrics_type ON biometrics(type, day);
        CREATE TABLE notes (day TEXT PRIMARY KEY, text TEXT NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE exercise (id TEXT PRIMARY KEY, day TEXT NOT NULL, name TEXT NOT NULL, minutes REAL,
          kcal REAL NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX exercise_day ON exercise(day);
        CREATE TABLE fasts (id TEXT PRIMARY KEY, start INTEGER NOT NULL, "end" INTEGER, goal_hours REAL NOT NULL,
          updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        CREATE TABLE repeats (id TEXT PRIMARY KEY, meal INTEGER NOT NULL, item TEXT NOT NULL, weekdays INTEGER NOT NULL,
          start_day TEXT NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
        PRAGMA user_version = 2;
      ''');
    }
    if (version < 3) {
      // Synchronisatie: "synced" = 0 zolang een rij nog naar de server moet. Elke gewone wijziging zet hem
      // terug op 0 (trigger); alleen de synchronisatie zelf zet hem op 1.
      final sql = StringBuffer();
      for (final t in syncTables) {
        sql
          ..writeln('ALTER TABLE ${t.name} ADD COLUMN synced INTEGER NOT NULL DEFAULT 0;')
          ..writeln(
            'CREATE TRIGGER ${t.name}_dirty AFTER UPDATE ON ${t.name} WHEN NEW.synced = 1 AND OLD.synced = 1 '
            'BEGIN UPDATE ${t.name} SET synced = 0 WHERE rowid = NEW.rowid; END;',
          );
      }
      sql.writeln('PRAGMA user_version = 3;');
      _db.execute(sql.toString());
    }
    if (version < 4) {
      // Bloedwaarden: alleen op dit toestel (niet in [syncTables]), want het zijn gevoelige gezondheidsgegevens
      _db.execute('''
        CREATE TABLE labs (id TEXT PRIMARY KEY, day TEXT NOT NULL, name TEXT NOT NULL, marker TEXT, value REAL NOT NULL,
          unit TEXT, comparator TEXT, low REAL, high REAL, flag INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL,
          deleted INTEGER NOT NULL DEFAULT 0);
        CREATE INDEX labs_marker ON labs(marker, day);
        PRAGMA user_version = 4;
      ''');
    }
  }

  // ── Synchronisatie ──

  /// Tabellen die met de server gesynchroniseerd worden, met hun sleutel en kolommen (zelfde namen op de server).
  static const syncTables = [
    SyncTable('settings', 'key', ['key', 'value', 'updated_at']),
    SyncTable('foods', 'id', ['id', 'source', 'name', 'brand', 'barcode', 'nutrients', 'portions', 'extra', 'updated_at', 'deleted']),
    SyncTable('diary', 'id', [
      'id', 'day', 'meal', 'food_ref', 'name', 'brand', 'grams', 'portion_label', 'quantity', 'nutrients', //
      'created_at', 'updated_at', 'deleted', 'time', 'repeat_id',
    ]),
    SyncTable('meals', 'id', ['id', 'name', 'items', 'updated_at', 'deleted']),
    SyncTable('biometrics', 'id', ['id', 'day', 'time', 'type', 'value', 'value2', 'updated_at', 'deleted']),
    SyncTable('notes', 'day', ['day', 'text', 'updated_at']),
    SyncTable('exercise', 'id', ['id', 'day', 'name', 'minutes', 'kcal', 'updated_at', 'deleted']),
    SyncTable('fasts', 'id', ['id', 'start', 'end', 'goal_hours', 'updated_at', 'deleted']),
    SyncTable('repeats', 'id', ['id', 'meal', 'item', 'weekdays', 'start_day', 'updated_at', 'deleted']),
  ];

  /// Instellingen die op dit toestel blijven: weergave, en alles wat met "_" begint (sessie, synchronisatie).
  static bool isLocalSetting(String key) => key == 'ui' || key.startsWith('_');

  static String _cols(SyncTable t) => t.columns.map((c) => '"$c"').join(', ');

  /// Wijzigingen die nog naar de server moeten.
  List<Map<String, Object?>> dirtyRows(SyncTable t, {int limit = 500}) => [
    for (final r in _db.select(
      'SELECT ${_cols(t)} FROM ${t.name} WHERE synced = 0${t.name == 'settings' ? " AND key != 'ui' AND key NOT LIKE '\\_%' ESCAPE '\\'" : ''} LIMIT ?',
      [limit],
    ))
      {for (final c in t.columns) c: r[c]},
  ];

  /// Is er iets wat nog naar de server moet?
  bool get hasDirtyRows => syncTables.any((t) => dirtyRows(t, limit: 1).isNotEmpty);

  /// Rijen als verstuurd markeren, maar alleen als ze intussen niet opnieuw gewijzigd zijn.
  void markSynced(SyncTable t, List<Map<String, Object?>> rows) => transaction(() {
    for (final r in rows) {
      _db.execute('UPDATE ${t.name} SET synced = 1 WHERE "${t.key}" = ? AND updated_at = ?', [r[t.key], r['updated_at']]);
    }
  });

  /// Een rij van de server overnemen als die nieuwer is dan wat hier staat (laatste wijziging wint).
  bool applyRemote(SyncTable t, Map<String, Object?> row) {
    final key = row[t.key];
    if (key == null || (t.name == 'settings' && isLocalSetting(key as String))) return false;
    final local = _db.select('SELECT updated_at FROM ${t.name} WHERE "${t.key}" = ?', [key]);
    final remoteAt = (row['updated_at'] as num?)?.toInt() ?? 0;
    if (local.isNotEmpty && (local.first['updated_at'] as num).toInt() >= remoteAt) return false;
    _db.execute('INSERT OR REPLACE INTO ${t.name} (${_cols(t)}, synced) VALUES (${List.filled(t.columns.length + 1, '?').join(', ')})', [
      for (final c in t.columns) _localValue(row[c]),
      1,
    ]);
    return true;
  }

  /// Waarden van de server terugzetten naar wat SQLite verwacht (true/false wordt 1/0).
  static Object? _localValue(Object? v) => v is bool ? (v ? 1 : 0) : v;

  /// Alles van dit toestel wissen, behalve de weergave-instelling en de sessie (die beheert het account zelf).
  void wipeUserData() => transaction(() {
    for (final t in syncTables) {
      _db.execute(t.name == 'settings' ? "DELETE FROM settings WHERE key NOT IN ('ui', '_session')" : 'DELETE FROM ${t.name}');
    }
    _db.execute('DELETE FROM labs');
  });

  /// Gegevens uit een andere app bewaren. Regels die er al zijn (zelfde vaste id) worden overgeslagen; notities
  /// worden aangevuld. Geeft (toegevoegd, al aanwezig) terug.
  (int, int) importBatch(ImportBatch batch) {
    var added = 0, skipped = 0;
    void count() => _db.updatedRows > 0 ? added++ : skipped++;
    final now = _now();
    transaction(() {
      for (final e in batch.entries) {
        _db.execute(
          'INSERT OR IGNORE INTO diary (id, day, meal, food_ref, name, brand, grams, portion_label, quantity, nutrients, created_at, updated_at, time) '
          'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
          [e.id, e.day, e.meal, e.foodRef, e.name, e.brand, e.grams, e.portionLabel, e.quantity, encodeNutrients(e.per100g), now, now, e.time],
        );
        count();
      }
      for (final x in batch.exercises) {
        _db.execute('INSERT OR IGNORE INTO exercise (id, day, name, minutes, kcal, updated_at) VALUES (?,?,?,?,?,?)', [
          x.id,
          x.day,
          x.name,
          x.minutes,
          x.kcal,
          now,
        ]);
        count();
      }
      for (final b in batch.biometrics) {
        _db.execute('INSERT OR IGNORE INTO biometrics (id, day, time, type, value, value2, updated_at) VALUES (?,?,?,?,?,?,?)', [
          b.id,
          b.day,
          b.time,
          b.type,
          b.value,
          b.value2,
          now,
        ]);
        count();
      }
      for (final MapEntry(key: day, value: text) in batch.notes.entries) {
        final old = note(day);
        if (old.contains(text)) {
          skipped++;
          continue;
        }
        setNote(day, old.trim().isEmpty ? text : '$old\n$text');
        added++;
      }
    });
    return (added, skipped);
  }

  /// Meerdere schrijfacties als één geheel.
  void transaction(void Function() body) {
    _db.execute('BEGIN');
    try {
      body();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Meldt elke wijziging aan de database (ook van de synchronisatie zelf).
  Stream<void> get changes => _db.updates.map((_) {});

  // ── Dagboek ──

  DiaryEntry _entry(Row r) => DiaryEntry(
    id: r['id'] as String,
    day: r['day'] as String,
    meal: Meal.values[r['meal'] as int],
    foodRef: r['food_ref'] as String,
    name: r['name'] as String,
    brand: r['brand'] as String?,
    grams: (r['grams'] as num).toDouble(),
    portionLabel: r['portion_label'] as String?,
    quantity: (r['quantity'] as num).toDouble(),
    per100g: decodeNutrients(r['nutrients'] as String),
    time: r['time'] as String?,
  );

  List<DiaryEntry> entriesFor(String day) => [
    for (final r in _db.select('SELECT * FROM diary WHERE day = ? AND deleted = 0 ORDER BY meal, created_at', [day])) _entry(r),
  ];

  /// Alle regels tussen twee dagen (inclusief), voor trends.
  /// Alle dagboekregels met het moment waarop ze gelogd werden (ms), voor XP.
  List<(DiaryEntry, int)> entriesWithCreatedAt() => [
    for (final r in _db.select('SELECT * FROM diary WHERE deleted = 0 ORDER BY day')) (_entry(r), (r['created_at'] as num).toInt()),
  ];

  /// Alle dagen waarop iets gelogd is.
  Set<String> loggedDays() => {
    for (final r in _db.select('SELECT DISTINCT day FROM diary WHERE deleted = 0 AND food_ref NOT LIKE \'supp:%\'')) r['day'] as String,
  };

  List<DiaryEntry> entriesBetween(String from, String to) => [
    for (final r in _db.select('SELECT * FROM diary WHERE day BETWEEN ? AND ? AND deleted = 0 ORDER BY day', [from, to])) _entry(r),
  ];

  /// Nieuwe regel in het dagboek. Geeft de id terug.
  String addEntry({
    required String day,
    required Meal meal,
    required Food food,
    required double grams,
    required double quantity,
    String? portionLabel,
    String? time,
    String? repeatId,
    String? id,
  }) {
    id ??= _uuid.v4();
    final now = _now();
    _db.execute(
      'INSERT INTO diary (id, day, meal, food_ref, name, brand, grams, portion_label, quantity, nutrients, created_at, updated_at, time, repeat_id) '
      'VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [id, day, meal.index, food.ref, food.name, food.brand, grams, portionLabel, quantity, encodeNutrients(food.per100g), now, now, time, repeatId],
    );
    return id;
  }

  /// Een opgeslagen item (uit een maaltijd of herhaling) in het dagboek zetten.
  String addTemplate(String day, Meal meal, ItemTemplate t, {String? time, String? repeatId, String? id}) => addEntry(
    day: day,
    meal: meal,
    food: Food(ref: t.foodRef, name: t.name, brand: t.brand, source: FoodSource.custom, per100g: t.per100g),
    grams: t.grams,
    quantity: t.quantity,
    portionLabel: t.portionLabel,
    time: time,
    repeatId: repeatId,
    id: id,
  );

  void updateEntry(String id, {required Meal meal, required double grams, required double quantity, String? portionLabel, String? time}) {
    _db.execute('UPDATE diary SET meal = ?, grams = ?, quantity = ?, portion_label = ?, time = ?, updated_at = ? WHERE id = ?', [
      meal.index,
      grams,
      quantity,
      portionLabel,
      time,
      _now(),
      id,
    ]);
  }

  /// Supplement op [day] aan- of afvinken. Eén vaste regel per supplement en dag (ook na afvinken blijft ze bestaan,
  /// als gewiste regel), zodat automatisch aanvinken een bewuste keuze niet ongedaan maakt.
  void setSupplementTaken(String day, Supplement s, bool taken) {
    final id = s.entryId(day);
    if (_db.select('SELECT 1 FROM diary WHERE id = ?', [id]).isNotEmpty) {
      _db.execute('UPDATE diary SET deleted = ?, nutrients = ?, name = ?, portion_label = ?, updated_at = ? WHERE id = ?', [
        taken ? 0 : 1,
        encodeNutrients(s.nutrients),
        s.name,
        s.dose,
        _now(),
        id,
      ]);
    } else if (taken) {
      addEntry(
        day: day,
        meal: Meal.breakfast,
        food: Food(ref: s.ref, name: s.name, source: FoodSource.custom, per100g: s.nutrients),
        grams: 100,
        quantity: 1,
        portionLabel: s.dose,
        id: id,
      );
    }
  }

  /// Of er voor dit supplement op [day] al een regel bestaat (ook een afgevinkte).
  bool hasSupplementRow(String day, Supplement s) => _db.select('SELECT 1 FROM diary WHERE id = ?', [s.entryId(day)]).isNotEmpty;

  void deleteEntry(String id) => _db.execute('UPDATE diary SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  void restoreEntry(String id) => _db.execute('UPDATE diary SET deleted = 0, updated_at = ? WHERE id = ?', [_now(), id]);

  /// Een maaltijd van een andere dag kopiëren (bv. "ontbijt van gisteren").
  int copyMeal({required String fromDay, required Meal meal, required String toDay}) {
    final rows = _db.select('SELECT * FROM diary WHERE day = ? AND meal = ? AND deleted = 0 AND food_ref NOT LIKE \'supp:%\'', [fromDay, meal.index]);
    final now = _now();
    for (final r in rows) {
      _db.execute(
        'INSERT INTO diary (id, day, meal, food_ref, name, brand, grams, portion_label, quantity, nutrients, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          _uuid.v4(),
          toDay,
          meal.index,
          r['food_ref'],
          r['name'],
          r['brand'],
          r['grams'],
          r['portion_label'],
          r['quantity'],
          r['nutrients'],
          now,
          now,
        ],
      );
    }
    return rows.length;
  }

  /// Laatst gebruikte voedingsmiddelen (één regel per product), nieuwste eerst.
  List<DiaryEntry> recent({int limit = 40}) => [
    for (final r in _db.select(
      '''
          SELECT * FROM (
            SELECT *, rowid AS rid, ROW_NUMBER() OVER (PARTITION BY food_ref ORDER BY created_at DESC, rowid DESC) AS n
            FROM diary WHERE deleted = 0 AND food_ref NOT LIKE 'supp:%'
          ) WHERE n = 1
          ORDER BY created_at DESC, rid DESC LIMIT ?''',
      [limit],
    ))
      _entry(r),
  ];

  // ── Eigen en bewaarde producten ──

  /// Merkproducten die bewaard werden voor de energiecontrole bestond (kJ in het kcal-veld).
  NutrientMap _fixEnergy(NutrientMap n) {
    final e = checkEnergy(n['energy'], protein: n['protein'], carbs: n['carbs'], fat: n['fat'], fiber: n['fiber']);
    return e == null ? n : {...n, 'energy': e};
  }

  Food _food(Row r) {
    if (r['source'] == 'recipe') return _recipe(r).toFood();
    // Bij merkproducten: koppeling met een basisproduct en welke waarden daaruit geschat zijn
    final extra = r['extra'] == null ? const <String, Object?>{} : (jsonDecode(r['extra'] as String) as Map).cast<String, Object?>();
    return Food(
      ref: r['id'] as String,
      name: r['name'] as String,
      brand: r['brand'] as String?,
      barcode: r['barcode'] as String?,
      source: FoodSource.values.byName(r['source'] as String),
      per100g: r['source'] == 'off' ? _fixEnergy(decodeNutrients(r['nutrients'] as String)) : decodeNutrients(r['nutrients'] as String),
      portions: decodePortions(r['portions'] as String?),
      proxyRef: extra['proxy'] as String?,
      estimated: ((extra['estimated'] as Map?) ?? const {}).cast<String, String>(),
      nova: (extra['nova'] as num?)?.toInt(),
    );
  }

  /// Bewaart een product (eigen product of opgezocht in Open Food Facts), zodat het offline blijft werken.
  void saveFood(Food f) {
    final extra = f.proxyRef == null && f.estimated.isEmpty && f.nova == null
        ? null
        : jsonEncode({'proxy': f.proxyRef, 'estimated': f.estimated, if (f.nova != null) 'nova': f.nova});
    _db.execute(
      'INSERT OR REPLACE INTO foods (id, source, name, brand, barcode, nutrients, portions, extra, updated_at, deleted) VALUES (?,?,?,?,?,?,?,?,?,0)',
      [f.ref, f.source.name, f.name, f.brand, f.barcode, encodeNutrients(f.per100g), encodePortions(f.portions), extra, _now()],
    );
  }

  /// Ontbrekende waarden aanvullen in dagboekregels van dit product (bv. nadat een merkproduct is aangevuld
  /// uit zijn basisproduct). Bestaande waarden blijven ongewijzigd. Geeft het aantal bijgewerkte regels terug.
  /// Alle voedingsmiddelen die in het dagboek voorkomen.
  List<String> diaryFoodRefs() => [for (final r in _db.select('SELECT DISTINCT food_ref FROM diary WHERE deleted = 0')) r['food_ref'] as String];

  /// Dagboekregels van een ingebouwd product gelijkzetten met de nieuwste waarden (na een update van de database:
  /// verbeterde of aangevulde waarden gelden dan ook voor wat je eerder at). Geeft het aantal gewijzigde regels.
  int replaceDiarySnapshots(String foodRef, NutrientMap per100g) {
    final encoded = encodeNutrients(per100g);
    var n = 0;
    for (final r in _db.select('SELECT id, nutrients FROM diary WHERE food_ref = ? AND deleted = 0', [foodRef])) {
      if (r['nutrients'] == encoded) continue;
      _db.execute('UPDATE diary SET nutrients = ?, updated_at = ? WHERE id = ?', [encoded, _now(), r['id']]);
      n++;
    }
    return n;
  }

  int fillDiarySnapshots(String foodRef, NutrientMap per100g) {
    var n = 0;
    for (final r in _db.select('SELECT id, nutrients FROM diary WHERE food_ref = ? AND deleted = 0', [foodRef])) {
      final old = decodeNutrients(r['nutrients'] as String);
      final merged = {...per100g, ...old};
      if (merged.length == old.length) continue;
      _db.execute('UPDATE diary SET nutrients = ?, updated_at = ? WHERE id = ?', [encodeNutrients(merged), _now(), r['id']]);
      n++;
    }
    return n;
  }

  Food? food(String ref) {
    final rows = _db.select('SELECT * FROM foods WHERE id = ? AND deleted = 0', [ref]);
    return rows.isEmpty ? null : _food(rows.first);
  }

  Food? foodByBarcode(String barcode) {
    final rows = _db.select('SELECT * FROM foods WHERE barcode = ? AND deleted = 0 ORDER BY source = \'custom\' DESC LIMIT 1', [barcode]);
    return rows.isEmpty ? null : _food(rows.first);
  }

  /// Bewaarde merkproducten die nog niet gekoppeld zijn aan een basisproduct (van voor die functie).
  List<Food> offFoodsWithoutProxy() => [
    for (final r in _db.select("SELECT * FROM foods WHERE source = 'off' AND deleted = 0 AND (extra IS NULL OR extra NOT LIKE '%proxy%')")) _food(r),
  ];

  List<Food> customFoods() => [
    for (final r in _db.select("SELECT * FROM foods WHERE source = 'custom' AND deleted = 0 ORDER BY name COLLATE NOCASE")) _food(r),
  ];

  // ── Recepten (bewaard als voedingsmiddel met de ingrediënten erbij) ──

  Recipe _recipe(Row r) => Recipe.fromJson(r['id'] as String, r['name'] as String, (jsonDecode(r['extra'] as String) as Map).cast<String, Object?>());

  static String newRecipeRef() => 'recipe:${_uuid.v4()}';

  void saveRecipe(Recipe recipe) {
    final f = recipe.toFood();
    _db.execute(
      'INSERT OR REPLACE INTO foods (id, source, name, brand, barcode, nutrients, portions, extra, updated_at, deleted) VALUES (?,?,?,?,?,?,?,?,?,0)',
      [f.ref, 'recipe', f.name, null, null, encodeNutrients(f.per100g), encodePortions(f.portions), jsonEncode(recipe.toJson()), _now()],
    );
  }

  Recipe? recipe(String ref) {
    final rows = _db.select("SELECT * FROM foods WHERE id = ? AND source = 'recipe' AND deleted = 0", [ref]);
    return rows.isEmpty ? null : _recipe(rows.first);
  }

  List<Recipe> recipes() => [
    for (final r in _db.select("SELECT * FROM foods WHERE source = 'recipe' AND deleted = 0 ORDER BY name COLLATE NOCASE")) _recipe(r),
  ];

  // ── Opgeslagen maaltijden ──

  SavedMeal _meal(Row r) => SavedMeal(
    id: r['id'] as String,
    name: r['name'] as String,
    items: [for (final i in jsonDecode(r['items'] as String) as List) ItemTemplate.fromJson((i as Map).cast<String, Object?>())],
  );

  List<SavedMeal> savedMeals() => [for (final r in _db.select('SELECT * FROM meals WHERE deleted = 0 ORDER BY name COLLATE NOCASE')) _meal(r)];

  void saveMeal(String name, List<ItemTemplate> items, {String? id}) =>
      _db.execute('INSERT OR REPLACE INTO meals (id, name, items, updated_at, deleted) VALUES (?,?,?,?,0)', [
        id ?? _uuid.v4(),
        name,
        jsonEncode([for (final i in items) i.toJson()]),
        _now(),
      ]);

  void deleteMeal(String id) => _db.execute('UPDATE meals SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  // ── Terugkerende items ──

  List<RepeatItem> repeats() => [
    for (final r in _db.select('SELECT * FROM repeats WHERE deleted = 0 ORDER BY meal'))
      RepeatItem(
        id: r['id'] as String,
        mealIndex: r['meal'] as int,
        item: ItemTemplate.fromJson((jsonDecode(r['item'] as String) as Map).cast<String, Object?>()),
        weekdays: r['weekdays'] as int,
        startDay: r['start_day'] as String,
      ),
  ];

  void saveRepeat({required int mealIndex, required ItemTemplate item, required int weekdays, required String startDay, String? id}) => _db.execute(
    'INSERT OR REPLACE INTO repeats (id, meal, item, weekdays, start_day, updated_at, deleted) VALUES (?,?,?,?,?,?,0)',
    [id ?? _uuid.v4(), mealIndex, jsonEncode(item.toJson()), weekdays, startDay, _now()],
  );

  void deleteRepeat(String id) => _db.execute('UPDATE repeats SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  /// Zet de terugkerende items van een dag in het dagboek, als dat nog niet gebeurd is.
  /// Ook een item dat de gebruiker daarna verwijderde, telt als gebeurd (het komt niet terug).
  int applyRepeats(String day, DateTime date) {
    var added = 0;
    for (final r in repeats()) {
      if (day.compareTo(r.startDay) < 0 || !r.appliesTo(date)) continue;
      final done = _db.select('SELECT 1 FROM diary WHERE day = ? AND repeat_id = ? LIMIT 1', [day, r.id]);
      if (done.isNotEmpty) continue;
      // Vaste id per herhaling en dag: twee toestellen maken zo dezelfde regel en geen dubbele
      addTemplate(day, Meal.values[r.mealIndex], r.item, repeatId: r.id, id: '${r.id}:$day');
      added++;
    }
    return added;
  }

  // ── Lichaamsmetingen ──

  Biometric _bio(Row r) => Biometric(
    id: r['id'] as String,
    day: r['day'] as String,
    time: r['time'] as String?,
    type: r['type'] as String,
    value: (r['value'] as num).toDouble(),
    value2: (r['value2'] as num?)?.toDouble(),
  );

  void addBiometric({required String day, required String type, required double value, double? value2, String? time}) => _db.execute(
    'INSERT INTO biometrics (id, day, time, type, value, value2, updated_at) VALUES (?,?,?,?,?,?,?)',
    [_uuid.v4(), day, time, type, value, value2, _now()],
  );

  /// Meting met een vaste id (bv. uit Health Connect): bijwerken als ze bestaat, maar niet terugzetten als je
  /// ze zelf verwijderde. Geeft true als er iets veranderde.
  bool upsertBiometric({required String id, required String day, required String type, required double value, String? time}) {
    final old = _db.select('SELECT value, deleted FROM biometrics WHERE id = ?', [id]);
    if (old.isNotEmpty && (old.first['deleted'] == 1 || (old.first['value'] as num).toDouble() == value)) return false;
    _db.execute('INSERT OR REPLACE INTO biometrics (id, day, time, type, value, value2, updated_at, deleted) VALUES (?,?,?,?,?,NULL,?,0)', [
      id,
      day,
      time,
      type,
      value,
      _now(),
    ]);
    return true;
  }

  void deleteBiometric(String id) => _db.execute('UPDATE biometrics SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  List<Biometric> biometricsFor(String day) => [
    for (final r in _db.select('SELECT * FROM biometrics WHERE day = ? AND deleted = 0 ORDER BY type, time', [day])) _bio(r),
  ];

  List<Biometric> biometricHistory(String type, {String? from}) => [
    for (final r in _db.select('SELECT * FROM biometrics WHERE type = ? AND deleted = 0 AND day >= ? ORDER BY day, time', [type, from ?? '0000']))
      _bio(r),
  ];

  /// Soorten metingen die de gebruiker ooit gebruikte (voor eigen metingen).
  List<String> biometricTypesUsed() => [for (final r in _db.select('SELECT DISTINCT type FROM biometrics WHERE deleted = 0')) r['type'] as String];

  // ── Bloedwaarden ──

  /// Uitslagen van één afname bewaren. Dezelfde uitslag opnieuw inlezen vervangt de oude (vaste id per dag, naam
  /// en eenheid), dus een verslag twee keer inlezen geeft geen dubbels.
  void saveLabs(String day, List<LabValue> values) => transaction(() {
    final now = _now();
    for (final v in values) {
      _db.execute(
        'INSERT OR REPLACE INTO labs (id, day, name, marker, value, unit, comparator, low, high, flag, updated_at, deleted) '
        'VALUES (?,?,?,?,?,?,?,?,?,?,?,0)',
        [labId(day, v), day, v.name, v.marker?.key, v.value, v.unit, v.comparator, v.low, v.high, v.flag, now],
      );
    }
  });

  static String labId(String day, LabValue v) => '$day:${normalizeLabName(v.name)}:${v.unit ?? ''}';

  void deleteLab(String id) => _db.execute('UPDATE labs SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  void deleteLabDay(String day) => _db.execute('UPDATE labs SET deleted = 1, updated_at = ? WHERE day = ?', [_now(), day]);

  /// Alle uitslagen, nieuwste afname eerst.
  List<LabResult> labs() => [
    for (final r in _db.select('SELECT * FROM labs WHERE deleted = 0 ORDER BY day DESC, rowid'))
      LabResult(
        id: r['id'] as String,
        day: r['day'] as String,
        value: LabValue(
          name: r['name'] as String,
          marker: labMarkerByKey[r['marker']],
          value: (r['value'] as num).toDouble(),
          unit: r['unit'] as String?,
          comparator: r['comparator'] as String?,
          low: (r['low'] as num?)?.toDouble(),
          high: (r['high'] as num?)?.toDouble(),
          flag: r['flag'] as int,
        ),
      ),
  ];

  // ── Notities ──

  String note(String day) {
    final rows = _db.select('SELECT text FROM notes WHERE day = ?', [day]);
    return rows.isEmpty ? '' : rows.first['text'] as String;
  }

  void setNote(String day, String text) => _db.execute('INSERT OR REPLACE INTO notes (day, text, updated_at) VALUES (?,?,?)', [day, text, _now()]);

  // ── Beweging ──

  List<Exercise> exerciseFor(String day) => [
    for (final r in _db.select('SELECT * FROM exercise WHERE day = ? AND deleted = 0 ORDER BY rowid', [day]))
      Exercise(
        id: r['id'] as String,
        day: r['day'] as String,
        name: r['name'] as String,
        minutes: (r['minutes'] as num?)?.toDouble(),
        kcal: (r['kcal'] as num).toDouble(),
      ),
  ];

  /// Verbrande kcal per dag tussen twee dagen (voor trends).
  Map<String, double> exerciseKcalBetween(String from, String to) => {
    for (final r in _db.select('SELECT day, SUM(kcal) AS k FROM exercise WHERE day BETWEEN ? AND ? AND deleted = 0 GROUP BY day', [from, to]))
      r['day'] as String: (r['k'] as num).toDouble(),
  };

  void addExercise({required String day, required String name, required double kcal, double? minutes}) => _db.execute(
    'INSERT INTO exercise (id, day, name, minutes, kcal, updated_at) VALUES (?,?,?,?,?,?)',
    [_uuid.v4(), day, name, minutes, kcal, _now()],
  );

  /// Beweging met een vaste id (bv. een workout uit Health Connect), alleen als ze nog niet bestaat of verwijderd werd.
  bool insertExerciseOnce({required String id, required String day, required String name, required double kcal, double? minutes}) {
    if (_db.select('SELECT 1 FROM exercise WHERE id = ?', [id]).isNotEmpty) return false;
    _db.execute('INSERT INTO exercise (id, day, name, minutes, kcal, updated_at) VALUES (?,?,?,?,?,?)', [id, day, name, minutes, kcal, _now()]);
    return true;
  }

  void updateExercise(String id, {required String name, required double kcal, double? minutes}) {
    _db.execute('UPDATE exercise SET name = ?, minutes = ?, kcal = ?, updated_at = ? WHERE id = ?', [name, minutes, kcal, _now(), id]);
  }

  void deleteExercise(String id) => _db.execute('UPDATE exercise SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  // ── Vasten ──

  Fast _fast(Row r) => Fast(
    id: r['id'] as String,
    start: DateTime.fromMillisecondsSinceEpoch(r['start'] as int),
    end: r['end'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['end'] as int),
    goalHours: (r['goal_hours'] as num).toDouble(),
  );

  Fast? currentFast() {
    final rows = _db.select('SELECT * FROM fasts WHERE "end" IS NULL AND deleted = 0 ORDER BY start DESC LIMIT 1');
    return rows.isEmpty ? null : _fast(rows.first);
  }

  List<Fast> recentFasts({int limit = 10}) => [
    for (final r in _db.select('SELECT * FROM fasts WHERE "end" IS NOT NULL AND deleted = 0 ORDER BY start DESC LIMIT ?', [limit])) _fast(r),
  ];

  void startFast(DateTime start, double goalHours) => _db.execute('INSERT INTO fasts (id, start, goal_hours, updated_at) VALUES (?,?,?,?)', [
    _uuid.v4(),
    start.millisecondsSinceEpoch,
    goalHours,
    _now(),
  ]);

  void endFast(String id, DateTime end) =>
      _db.execute('UPDATE fasts SET "end" = ?, updated_at = ? WHERE id = ?', [end.millisecondsSinceEpoch, _now(), id]);

  void deleteFast(String id) => _db.execute('UPDATE fasts SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), id]);

  List<Food> searchSaved(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final where = List.filled(words.length, "(lower(name) LIKE ? OR lower(coalesce(brand, '')) LIKE ?)").join(' AND ');
    return [
      for (final r in _db.select('SELECT * FROM foods WHERE deleted = 0 AND $where ORDER BY source = \'custom\' DESC, name LIMIT 30', [
        for (final w in words) ...['%$w%', '%$w%'],
      ]))
        _food(r),
    ];
  }

  void deleteFood(String ref) => _db.execute('UPDATE foods SET deleted = 1, updated_at = ? WHERE id = ?', [_now(), ref]);

  static String newCustomRef() => 'custom:${_uuid.v4()}';

  // ── Instellingen ──

  Map<String, Object?>? setting(String key) {
    final rows = _db.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : (jsonDecode(rows.first['value'] as String) as Map).cast<String, Object?>();
  }

  void setSetting(String key, Map<String, Object?> value) =>
      _db.execute('INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?,?,?)', [key, jsonEncode(value), _now()]);

  void deleteSetting(String key) => _db.execute('DELETE FROM settings WHERE key = ?', [key]);

  void close() => _db.close();
}
