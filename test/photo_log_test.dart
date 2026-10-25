import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/platform/photo_log.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/quick_log.dart';

/// Loggen met een foto: verkleinen op het toestel, de server (nagebootst) en de zin in de lijst van Snel loggen.
void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  final fakeJpeg = Uint8List.fromList(List.filled(2000, 7));

  group('shrinkPhoto', () {
    test('verkleint een grote foto tot 1024 px aan de langste zijde, als JPEG', () {
      final big = img.Image(width: 3000, height: 2000);
      final out = shrinkPhoto(img.encodePng(big));
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
      final back = img.decodeJpg(out)!;
      expect(back.width, 1024);
      expect(back.height, closeTo(683, 1));
    });

    test('staand beeld: de hoogte wordt 1024; een kleine foto blijft even groot', () {
      final tall = img.decodeJpg(shrinkPhoto(img.encodeJpg(img.Image(width: 1500, height: 2400))))!;
      expect(tall.height, 1024);
      final small = img.decodeJpg(shrinkPhoto(img.encodeJpg(img.Image(width: 640, height: 480))))!;
      expect((small.width, small.height), (640, 480));
    });

    test('geen afbeelding geeft een FormatException', () {
      expect(() => shrinkPhoto(Uint8List.fromList([1, 2, 3])), throwsFormatException);
    });
  });

  group('PhotoLog.describe', () {
    test('stuurt de JPEG met het token en geeft de zin terug', () async {
      late http.Request sent;
      final log = PhotoLog(
        MockClient((req) async {
          sent = req;
          return http.Response(jsonEncode({'text': ' 2 eggs, 1 slice of bread '}), 200);
        }),
      );
      expect(await log.describe(fakeJpeg, token: 'abc'), '2 eggs, 1 slice of bread');
      expect(sent.method, 'POST');
      expect(sent.url.path, '/api/photo');
      expect(sent.headers['Authorization'], 'Bearer abc');
      expect(sent.headers['Content-Type'], startsWith('image/jpeg'));
      expect(sent.bodyBytes, fakeJpeg);
    });

    Future<String> codeFor(http.Response Function() reply) async {
      try {
        await PhotoLog(MockClient((_) async => reply())).describe(fakeJpeg, token: 't');
        return 'ok';
      } on PhotoLogException catch (e) {
        return e.code;
      }
    }

    test('foutcodes van de server komen door', () async {
      expect(await codeFor(() => http.Response('{"error":"login"}', 401)), 'login');
      expect(await codeFor(() => http.Response('{"error":"not_configured"}', 503)), 'not_configured');
      expect(await codeFor(() => http.Response('{"error":"too_many"}', 429)), 'too_many');
      expect(await codeFor(() => http.Response('<html>Bad gateway</html>', 502)), 'failed');
    });

    test('geen verbinding geeft network', () async {
      final log = PhotoLog(MockClient((_) async => throw http.ClientException('offline')));
      expect(() => log.describe(fakeJpeg, token: 't'), throwsA(isA<PhotoLogException>().having((e) => e.code, 'code', 'network')));
    });
  });

  group('in het venster van Snel loggen', () {
    late Future<Uint8List?> Function(BuildContext) oldPick;
    late PhotoLog oldLog;
    late String? Function(BuildContext) oldToken;
    setUp(() {
      oldPick = pickPlatePhoto;
      oldLog = photoLog;
      oldToken = photoToken;
      pickPlatePhoto = (_) async => fakeJpeg;
      photoToken = (_) => 'token';
    });
    tearDown(() {
      pickPlatePhoto = oldPick;
      photoLog = oldLog;
      photoToken = oldToken;
    });

    Future<AppState> open(WidgetTester tester, {bool photo = false}) async {
      final s = AppState(
        foods: FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly)),
        user: UserDb(sqlite3.openInMemory()),
      );
      tester.view.physicalSize = const Size(412, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: s,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showQuickLog(context, meal: Meal.lunch, photo: photo),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return s;
    }

    testWidgets('de zin van de foto komt in de lijst, met de melding dat het geschat is', (tester) async {
      photoLog = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'text': '2 eggs, 1 apple'}), 200)));
      final s = await open(tester);
      expect(find.textContaining('Estimated from your photo'), findsNothing);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, '2 eggs, 1 apple'), findsOneWidget);
      expect(find.textContaining('Estimated from your photo'), findsOneWidget);
      expect(find.byTooltip('Remove'), findsNWidgets(2));
      // Nakijken met dezelfde knoppen als Snel loggen: één regel weghalen, dan toevoegen
      await tester.tap(find.byTooltip('Remove').last);
      await tester.pump();
      await tester.tap(find.text('Add 1 to lunch'));
      await tester.pumpAndSettle();
      expect(s.entriesFor(Meal.lunch).single.grams, 112); // 2 × 56 g (gekookt ei, Matvaretabellen)
    });

    testWidgets('een typisch antwoord van de server geeft één regel per product', (tester) async {
      const sentence = '150 g spaghetti bolognese, 1 slice of bread, 1 glass of orange juice';
      photoLog = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'text': sentence}), 200)));
      await open(tester);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove'), findsNWidgets(3));
      expect(find.textContaining('nothing found'), findsNothing);
    });

    testWidgets('vanuit het +-menu vraagt het venster meteen een foto', (tester) async {
      var asked = 0;
      pickPlatePhoto = (_) async {
        asked++;
        return fakeJpeg;
      };
      photoLog = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'text': '150 g rice'}), 200)));
      await open(tester, photo: true);
      expect(asked, 1);
      expect(find.byTooltip('Remove'), findsOneWidget);
      expect(find.textContaining('150 g'), findsWidgets);
      expect(find.textContaining('Estimated from your photo'), findsOneWidget);
    });

    testWidgets('niet ingelogd: vriendelijke melding, geen foto gevraagd', (tester) async {
      var asked = false;
      pickPlatePhoto = (_) async {
        asked = true;
        return fakeJpeg;
      };
      photoToken = (_) => null;
      await open(tester, photo: true);
      expect(asked, isFalse);
      expect(find.textContaining('needs an account'), findsOneWidget);
    });

    testWidgets('fouten van de server: vriendelijke meldingen, de lijst blijft leeg', (tester) async {
      var reply = http.Response('{"error":"not_configured"}', 503);
      photoLog = PhotoLog(MockClient((_) async => reply));
      await open(tester);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not available yet'), findsOneWidget);

      reply = http.Response('{"error":"too_many"}', 429);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('a lot of photos this hour'), findsOneWidget);

      reply = http.Response(jsonEncode({'text': ''}), 200);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No food found in that photo'), findsOneWidget);
      expect(find.textContaining('Total'), findsNothing);
    });

    testWidgets('geen verbinding: melding over internet', (tester) async {
      photoLog = PhotoLog(MockClient((_) async => throw http.ClientException('offline')));
      await open(tester);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No connection'), findsOneWidget);
    });
  });
}
