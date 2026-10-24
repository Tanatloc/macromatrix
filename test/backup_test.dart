import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/backup.dart';
import 'package:macromatrix/data/food.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/data/models.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/labs/lab_report.dart';
import 'package:macromatrix/sync/sync_engine.dart';

import 'sync_test.dart' show FakeServer;

const _banana = Food(ref: 'ciqual:13005', name: 'Banana, raw', source: FoodSource.ciqual, per100g: {'energy': 90, 'potassium': 320});
const _oats = ItemTemplate(foodRef: 'ciqual:9310', name: 'Oats', grams: 50, quantity: 50, per100g: {'energy': 370, 'protein': 13.5});

/// Een database met van alles wat een gebruiker kan maken.
UserDb _filled() {
  final db = UserDb(sqlite3.openInMemory());
  db.addEntry(day: '2026-10-20', meal: Meal.breakfast, food: _banana, grams: 120, quantity: 1, portionLabel: 'banana', time: '08:15');
  db.addEntry(day: '2026-10-21', meal: Meal.dinner, food: _banana, grams: 80.5, quantity: 80.5);
  db.saveFood(const Food(ref: 'custom:own-1', name: 'Grandma soup', source: FoodSource.custom, per100g: {'energy': 45, 'fiber': 1.2}));
  db.saveRecipe(const Recipe(ref: 'recipe:r-1', name: 'Porridge', servings: 2, ingredients: [_oats], cookedGrams: 300));
  db.saveMeal('My breakfast', const [_oats], id: 'meal-1', meal: Meal.breakfast);
  final bio = db.addBiometric(day: '2026-10-20', type: 'glucose', value: 5.4, time: '07:00');
  db.setBiometricMoment(bio, 'fasting');
  db.addBiometric(day: '2026-10-20', type: 'blood_pressure', value: 120, value2: 80);
  db.saveLabs('2026-09-01', const [LabValue(name: 'Ferritin', value: 85, unit: 'µg/L', low: 30, high: 400)]);
  db.addExercise(day: '2026-10-20', name: 'Cycling', kcal: 310, minutes: 45);
  db.startFast(DateTime(2026, 10, 20, 20), 16);
  db.saveRepeat(mealIndex: 0, item: _oats, weekdays: 0x7f, startDay: '2026-10-01', id: 'rep-1');
  db.setNote('2026-10-20', 'Slept well');
  db.setSetting('profile', {'weightKg': 78.4, 'heightCm': 182});
  db.setSetting('targets', {
    'overrides': {'protein': 140},
  });
  db.setSetting('supplements', {
    'items': [
      {'name': 'Vitamin D', 'dose': 25},
    ],
  });
  db.setSetting('plan', {'days': {}});
  db.setSetting('shopping', {
    'items': [
      {'name': 'Oats'},
    ],
  });
  db.setSetting('ui', {'lang': 'en', 'theme': 'dark'});
  db.setSetting('_session', {'token': 'secret'});
  db.setSetting('_sync', {'user': 'u', 'cursors': {}});
  return db;
}

/// Inhoud van alle tabellen, zonder tijdstip van wijziging (dat wordt bij het terugzetten "nu").
Map<String, List<Map<String, Object?>>> _content(UserDb db) => {
  for (final t in UserDb.backupTables)
    t: [
      for (final r in db.backupRows(t)) {...r}..remove('updated_at'),
    ],
};

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  testWidgets('Instellingen > Gegevens: Alles exporteren en Back-up terugzetten naast de CSV', (tester) async {
    final s = AppState(
      foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
      user: UserDb(sqlite3.openInMemory()),
    );
    tester.view.physicalSize = const Size(412, 5000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: s),
          ChangeNotifierProvider.value(value: Account(s.user, onRemoteChanges: s.reloadFromDisk)),
          Provider.value(value: Reminders(s)),
        ],
        child: MaterialApp(theme: buildTheme(Brightness.light), home: const SettingsScreen()),
      ),
    );
    await tester.pump();
    final csv = tester.getTopLeft(find.text('Export diary (CSV)')).dy;
    final all = tester.getTopLeft(find.text('Export everything (backup)')).dy;
    final restore = tester.getTopLeft(find.text('Restore from backup')).dy;
    expect(csv < all && all < restore, isTrue);
  });

  test('elke tabel van de gebruiker zit in de back-up', () {
    final raw = sqlite3.openInMemory();
    final db = UserDb(raw);
    final tables = {
      for (final r in raw.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'")) r['name'] as String,
    };
    expect(tables, UserDb.backupTables.toSet());
    db.close();
  });

  test('exporteren, wissen en terugzetten geeft dezelfde gegevens', () {
    final db = _filled();
    final before = _content(db);
    final json = backupJson(db);
    expect(json, isNot(contains('secret')), reason: 'sessie hoort niet in de back-up');
    expect(before['biometric_moments'], hasLength(1));
    expect(before['labs'], hasLength(1));

    db.wipeUserData();
    expect(db.backupRows('diary'), isEmpty);

    final backup = readBackup(db, _bytes(json));
    expect(backup.format, backupFormat);
    expect(backup.count('diary'), 2);
    final (restored, skipped) = db.restoreRows(backup.tables, replace: true);
    expect(skipped, 0);
    expect(restored, backup.total);
    expect(_content(db), before);
    // Ook de app leest het weer gewoon
    expect(db.entriesFor('2026-10-20').single.time, '08:15');
    expect(db.recipe('recipe:r-1')?.cookedGrams, 300);
    expect(db.setting('_session'), {'token': 'secret'}, reason: 'de sessie blijft staan');
  });

  test('vervangen haalt weg wat niet in de back-up zat', () {
    final db = _filled();
    final json = backupJson(db);
    db.addEntry(day: '2026-10-22', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    db.addExercise(day: '2026-10-22', name: 'Run', kcal: 400);
    db.setNote('2026-10-22', 'Later note');
    db.restoreRows(readBackup(db, _bytes(json)).tables, replace: true);
    expect(db.entriesFor('2026-10-22'), isEmpty);
    expect(db.exerciseFor('2026-10-22'), isEmpty);
    expect(db.note('2026-10-22'), '');
    expect(db.entriesFor('2026-10-20'), hasLength(1));
  });

  test('samenvoegen voegt toe wat ontbreekt en laat de rest staan', () {
    final source = _filled();
    final json = backupJson(source);

    final db = UserDb(sqlite3.openInMemory());
    db.addEntry(day: '2026-10-22', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    db.setSetting('profile', {'weightKg': 75});
    db.setNote('2026-10-20', 'My own note');
    final backup = readBackup(db, _bytes(json));
    final (added, kept) = db.restoreRows(backup.tables, replace: false);
    expect(kept, 2, reason: 'profiel en notitie stonden er al');
    expect(added, backup.total - 2);
    expect(db.entriesFor('2026-10-22'), hasLength(1));
    expect(db.entriesFor('2026-10-20'), hasLength(1));
    expect(db.setting('profile'), {'weightKg': 75});
    expect(db.setting('targets'), {
      'overrides': {'protein': 140},
    });
    expect(db.note('2026-10-20'), 'My own note');
    expect(db.labs(), hasLength(1));

    // Nog eens samenvoegen geeft geen dubbels
    final (again, _) = db.restoreRows(backup.tables, replace: false);
    expect(again, 0);
    expect(db.entriesFor('2026-10-20'), hasLength(1));
  });

  test('samenvoegen zet een verwijderde rij terug', () {
    final db = _filled();
    final json = backupJson(db);
    final e = db.entriesFor('2026-10-20').single;
    db.deleteEntry(e.id);
    expect(db.entriesFor('2026-10-20'), isEmpty);
    db.restoreRows(readBackup(db, _bytes(json)).tables, replace: false);
    expect(db.entriesFor('2026-10-20').single.id, e.id);
  });

  test('met een account gaat wat teruggezet is naar de server en naar andere toestellen', () async {
    final server = FakeServer();
    Future<SyncResult> sync(UserDb db) => SyncEngine(db, server, userId: 'user-1').run();
    final a = _filled();
    await sync(a);
    final json = backupJson(a);
    // Na de back-up nog iets bijgekomen, dat gesynchroniseerd is
    a.addEntry(day: '2026-10-23', meal: Meal.lunch, food: _banana, grams: 100, quantity: 100);
    await sync(a);
    final b = UserDb(sqlite3.openInMemory());
    await sync(b);
    expect(b.entriesFor('2026-10-23'), hasLength(1));

    a.restoreRows(readBackup(a, _bytes(json)).tables, replace: true);
    expect(a.hasDirtyRows, isTrue);
    final r = await sync(a);
    expect(r.pushed, greaterThan(0));
    expect(a.hasDirtyRows, isFalse);

    await sync(b);
    expect(b.entriesFor('2026-10-23'), isEmpty, reason: 'vervangen verwijdert ook op het andere toestel');
    expect(b.entriesFor('2026-10-20'), hasLength(1));
    expect(b.setting('profile'), {'weightKg': 78.4, 'heightCm': 182});
    expect(b.labs(), isEmpty, reason: 'bloedwaarden blijven op het toestel');
  });

  group('een fout bestand wordt geweigerd zonder iets te veranderen', () {
    late UserDb db;
    late String good;
    setUp(() {
      db = _filled();
      good = backupJson(db);
    });

    void rejects(String text, Matcher message) {
      expect(() => readBackup(db, _bytes(text)), throwsA(isA<BackupException>().having((e) => e.message, 'message', message)));
    }

    test('afgebroken of geen JSON', () {
      rejects(good.substring(0, good.length ~/ 2), contains('cannot be read'));
      rejects('date;time;meal\n2026-10-20;08:00;Breakfast', contains('cannot be read'));
      expect(() => readBackup(db, Uint8List.fromList([0xff, 0xfe, 0x00])), throwsA(isA<BackupException>()));
    });

    test('ander JSON-bestand of nieuwer formaat', () {
      rejects('{"hello": "world"}', contains('not a MacroMatrix backup'));
      rejects('[1, 2, 3]', contains('not a MacroMatrix backup'));
      final m = jsonDecode(good) as Map<String, Object?>;
      rejects(jsonEncode({...m, 'format': backupFormat + 1}), contains('newer version'));
      rejects(jsonEncode({...m, 'format': 'one'}), contains('format version'));
      rejects(jsonEncode({...m, 'tables': null}), contains('no data'));
    });

    test('beschadigde rij', () {
      Map<String, Object?> copy() => jsonDecode(good) as Map<String, Object?>;
      final m1 = copy();
      ((m1['tables'] as Map)['diary'] as List)[1] = {...(((m1['tables'] as Map)['diary'] as List)[1] as Map), 'grams': 'lots'};
      rejects(jsonEncode(m1), allOf(contains('row 2'), contains('diary'), contains('grams')));
      final m2 = copy();
      ((m2['tables'] as Map)['foods'] as List)[0] = {...(((m2['tables'] as Map)['foods'] as List)[0] as Map), 'nutrients': '{broken'};
      rejects(jsonEncode(m2), contains('nutrients'));
      final m3 = copy();
      ((m3['tables'] as Map)['diary'] as List)[0] = {...(((m3['tables'] as Map)['diary'] as List)[0] as Map), 'meal': 9};
      rejects(jsonEncode(m3), contains('meal'));
      final m4 = copy();
      (((m4['tables'] as Map)['exercise'] as List)[0] as Map).remove('name');
      rejects(jsonEncode(m4), contains('name'));
      final m5 = copy();
      (m5['tables'] as Map)['diary'] = 'nope';
      rejects(jsonEncode(m5), contains('diary'));
    });

    test('sessie-instellingen uit een bestand worden genegeerd', () {
      final m = jsonDecode(good) as Map<String, Object?>;
      ((m['tables'] as Map)['settings'] as List).add({'key': '_session', 'value': '{"token":"evil"}', 'updated_at': 1});
      final b = readBackup(db, _bytes(jsonEncode(m)));
      db.restoreRows(b.tables, replace: true);
      expect(db.setting('_session'), {'token': 'secret'});
    });
  });
}
