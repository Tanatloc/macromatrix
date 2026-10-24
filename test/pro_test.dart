import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:macromatrix/data/food_db.dart';
import 'package:macromatrix/data/user_db.dart';
import 'package:macromatrix/i18n.dart';
import 'package:macromatrix/nutrition/report.dart';
import 'package:macromatrix/platform/photo_log.dart';
import 'package:macromatrix/platform/reminders.dart';
import 'package:macromatrix/state/app_state.dart';
import 'package:macromatrix/sync/account.dart';
import 'package:macromatrix/sync/friends.dart';
import 'package:macromatrix/sync/pro.dart';
import 'package:macromatrix/sync/purchase.dart';
import 'package:macromatrix/ui/screens/friends_screen.dart';
import 'package:macromatrix/ui/screens/pro_screen.dart';
import 'package:macromatrix/ui/screens/recap_screen.dart';
import 'package:macromatrix/ui/screens/settings_screen.dart';
import 'package:macromatrix/ui/theme.dart';
import 'package:macromatrix/ui/widgets/level_card.dart';
import 'package:macromatrix/ui/widgets/pro_widgets.dart';
import 'package:macromatrix/ui/widgets/quick_log.dart';

/// Nagebootste server voor Pro: status, fototeller, of helemaal geen migratie.
class FakeProRemote implements ProRemote {
  ProStatus status = const ProStatus();
  PhotoQuota? photo;
  bool missing = false;
  int quotaCalls = 0;
  bool? badge;

  @override
  Future<ProStatus> mine() async {
    if (missing) throw const ProMissing();
    return status;
  }

  @override
  Future<PhotoQuota?> quota() async {
    quotaCalls++;
    if (missing) throw const ProMissing();
    return photo;
  }

  @override
  Future<void> showBadge(bool show) async {
    if (missing) throw const ProMissing();
    badge = show;
    status = status.copyWith(showBadge: show);
  }
}

PhotoQuota quota(int used, {int limit = 3, bool pro = false}) => PhotoQuota(used: used, limit: limit, pro: pro, day: utcDayKey(DateTime.now()));

final _foods = FoodDb(sqlite3.open('assets/db/foods.db', mode: OpenMode.readOnly));

AppState newState() => AppState(foods: _foods, user: UserDb(sqlite3.openInMemory()));

Pro newPro(AppState s, FakeProRemote server, {PurchaseProvider purchases = const NoPurchaseProvider()}) => Pro(
  Account(s.user, onRemoteChanges: s.reloadFromDisk),
  remote: () => server,
  purchases: purchases,
);

Future<void> pump(WidgetTester tester, AppState s, Pro? pro, Widget home, {Friends? friends, Account? account}) async {
  tester.view.physicalSize = const Size(412, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: s),
        if (pro != null) ChangeNotifierProvider<Pro>.value(value: pro),
        if (friends != null) ChangeNotifierProvider<Friends>.value(value: friends),
        if (account != null) ChangeNotifierProvider<Account>.value(value: account),
      ],
      child: MaterialApp(theme: buildTheme(Brightness.light), home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// Een betaling die wel werkt (zoals later Google Play): de server zet Pro daarna aan.
class _WorkingStore extends PurchaseProvider {
  _WorkingStore(this.server);
  final FakeProRemote server;
  ProPlan? bought;

  @override
  bool get available => true;

  @override
  Future<PurchaseOutcome> subscribe(ProPlan plan) async {
    bought = plan;
    server.status = ProStatus(until: DateTime.now().add(const Duration(days: 30)), source: 'play');
    return PurchaseOutcome.done;
  }

  @override
  Future<PurchaseOutcome> restore() async => PurchaseOutcome.done;
}

void main() {
  setUpAll(() async {
    setAppLang(AppLang.en);
    await initializeDateFormatting(appLocale);
  });

  group('Pro-dienst', () {
    test('status van de server, bewaard op het toestel', () async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime.now().add(const Duration(days: 3)), source: 'manual');
      final pro = newPro(s, server);
      expect(pro.isPro, isFalse);
      await pro.refresh();
      expect(pro.isPro, isTrue);
      expect(pro.supporter, isTrue);
      // Een nieuwe start zonder internet: de bewaarde status geldt nog
      final again = Pro(Account(s.user, onRemoteChanges: () {}));
      expect(again.isPro, isTrue);
      expect(again.status.source, 'manual');
    });

    test('afgelopen Pro telt niet meer', () async {
      final s = newState();
      final server = FakeProRemote()..status = ProStatus(until: DateTime.now().subtract(const Duration(minutes: 1)));
      final pro = newPro(s, server);
      await pro.refresh();
      expect(pro.isPro, isFalse);
      expect(pro.supporter, isFalse);
    });

    test('zonder migratie: geen Pro, geen teller, geen fouten', () async {
      final s = newState();
      final server = FakeProRemote()..missing = true;
      final pro = newPro(s, server);
      await pro.refresh();
      expect(pro.available, isFalse);
      expect(pro.isPro, isFalse);
      expect(pro.quota, isNull);
      // Daarna wordt de teller niet meer gevraagd
      final calls = server.quotaCalls;
      await pro.refreshQuota();
      expect(server.quotaCalls, calls);
      expect(await pro.restore(), isFalse);
      expect(await pro.setShowBadge(false), isFalse);
    });

    test('een stand van gisteren geldt vandaag niet meer', () {
      final old = PhotoQuota(used: 3, limit: 3, day: utcDayKey(DateTime.now().subtract(const Duration(days: 1))));
      final now = old.on(DateTime.now());
      expect(now.used, 0);
      expect(now.allowed, isTrue);
      expect(PhotoQuota.fromJson({'allowed': false, 'used': 3, 'limit': 3, 'pro': false})!.left, 0);
      expect(PhotoQuota.fromJson(null), isNull);
      expect(PhotoQuota.fromJson({'error': 'x'}), isNull);
    });

    test('debug: Pro op dit toestel aan en uit zetten', () async {
      final s = newState();
      final pro = newPro(s, FakeProRemote());
      expect(pro.isPro, isFalse);
      pro.setDebugPro(true);
      expect(pro.isPro, isTrue);
      pro.setDebugPro(false);
      expect(pro.isPro, isFalse);
      pro.setDebugPro(null);
      expect(pro.debugPro, isNull);
    });

    test('prijzen en de naad voor betalen', () async {
      expect(ProPlan.monthly.price, '€2.99');
      expect(ProPlan.yearly.price, '€19.99');
      expect(yearlySavingPercent, 44);
      const none = NoPurchaseProvider();
      expect(none.available, isFalse);
      expect(await none.subscribe(ProPlan.yearly), PurchaseOutcome.unavailable);
      expect(await none.restore(), PurchaseOutcome.unavailable);
      final s = newState();
      final server = FakeProRemote();
      final store = _WorkingStore(server);
      final pro = newPro(s, server, purchases: store);
      expect(await pro.subscribe(ProPlan.monthly), PurchaseOutcome.done);
      expect(store.bought, ProPlan.monthly);
      expect(pro.isPro, isTrue);
    });
  });

  group('PhotoLog en de dagteller', () {
    final jpeg = Uint8List.fromList(List.filled(2000, 7));

    test('429 quota geeft de stand mee', () async {
      final log = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'error': 'quota', 'used': 3, 'limit': 3, 'pro': false}), 429)));
      try {
        await log.describe(jpeg, token: 't');
        fail('geen fout');
      } on PhotoLogException catch (e) {
        expect(e.code, 'quota');
        expect(e.quota!.used, 3);
        expect(e.quota!.allowed, isFalse);
      }
    });

    test('een geslaagde foto geeft de nieuwe stand mee; een oude server zonder teller niet', () async {
      var body = {
        'text': '1 apple',
        'quota': {'used': 2, 'limit': 3, 'pro': false},
      };
      final log = PhotoLog(MockClient((_) async => http.Response(jsonEncode(body), 200)));
      expect(await log.describe(jpeg, token: 't'), '1 apple');
      expect(log.lastQuota!.left, 1);
      body = {'text': '1 apple'};
      await log.describe(jpeg, token: 't');
      expect(log.lastQuota, isNull);
    });
  });

  group('fototeller in Snel loggen', () {
    testWidgets('PhotoQuotaNote: nog over, op (met Pro-knop), Pro, onbekend', (tester) async {
      final s = newState();
      Future<void> note(PhotoQuota? q, bool pro) => pump(
        tester,
        s,
        null,
        Scaffold(
          body: PhotoQuotaNote(quota: q, pro: pro),
        ),
      );

      await note(quota(1), false);
      expect(find.text('2 of 3 free photos left today'), findsOneWidget);

      await note(quota(3), false);
      expect(find.byKey(const ValueKey('photo-quota-out')), findsOneWidget);
      expect(find.textContaining('used your 3 free photos'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-quota-pro')), findsOneWidget);

      await note(quota(5, limit: 50, pro: true), true);
      expect(find.byKey(const ValueKey('photo-quota-left')), findsNothing);
      expect(find.byKey(const ValueKey('photo-quota-out')), findsNothing);

      await note(quota(50, limit: 50, pro: true), true);
      expect(find.textContaining('the most we allow in one day'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-quota-pro')), findsNothing);

      await note(null, false);
      expect(find.byKey(const ValueKey('photo-quota-left')), findsNothing);
      expect(find.byKey(const ValueKey('photo-quota-out')), findsNothing);

      // De Pro-knop opent het Pro-scherm
      await note(quota(3), false);
      await tester.tap(find.byKey(const ValueKey('photo-quota-pro')));
      await tester.pumpAndSettle();
      expect(find.byType(ProScreen), findsOneWidget);
    });

    late Future<Uint8List?> Function(BuildContext) oldPick;
    late PhotoLog oldLog;
    late String? Function(BuildContext) oldToken;
    setUp(() {
      oldPick = pickPlatePhoto;
      oldLog = photoLog;
      oldToken = photoToken;
      photoToken = (_) => 'token';
    });
    tearDown(() {
      pickPlatePhoto = oldPick;
      photoLog = oldLog;
      photoToken = oldToken;
    });

    Future<void> openSheet(WidgetTester tester, AppState s, Pro pro, {bool photo = false}) async {
      await pump(
        tester,
        s,
        pro,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showQuickLog(context, meal: Meal.lunch, photo: photo),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('stand bij het openen, en bijgewerkt na een foto', (tester) async {
      final s = newState();
      final server = FakeProRemote()..photo = quota(0);
      final pro = newPro(s, server);
      pickPlatePhoto = (_) async => Uint8List.fromList(List.filled(2000, 7));
      photoLog = PhotoLog(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'text': '1 apple',
              'quota': {'used': 1, 'limit': 3, 'pro': false},
            }),
            200,
          ),
        ),
      );
      await openSheet(tester, s, pro);
      expect(find.text('3 of 3 free photos left today'), findsOneWidget);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.text('2 of 3 free photos left today'), findsOneWidget);
    });

    testWidgets('op voor vandaag: geen foto gevraagd, vriendelijke uitleg met Pro-knop', (tester) async {
      final s = newState();
      final server = FakeProRemote()..photo = quota(3);
      final pro = newPro(s, server);
      var asked = 0;
      pickPlatePhoto = (_) async {
        asked++;
        return Uint8List.fromList(List.filled(2000, 7));
      };
      await openSheet(tester, s, pro, photo: true);
      expect(asked, 0);
      expect(find.byKey(const ValueKey('photo-quota-out')), findsOneWidget);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(asked, 0);
      expect(find.textContaining("Couldn't read the photo"), findsNothing);
    });

    testWidgets('de server zegt quota (andere toestel): uitleg in plaats van een gewone fout', (tester) async {
      final s = newState();
      final server = FakeProRemote()..photo = quota(2);
      final pro = newPro(s, server);
      pickPlatePhoto = (_) async => Uint8List.fromList(List.filled(2000, 7));
      photoLog = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'error': 'quota', 'used': 3, 'limit': 3, 'pro': false}), 429)));
      await openSheet(tester, s, pro);
      expect(find.text('1 of 3 free photos left today'), findsOneWidget);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('photo-quota-out')), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-quota-pro')), findsOneWidget);
      expect(find.textContaining("Couldn't read the photo"), findsNothing);
    });

    testWidgets('zonder migratie: geen teller in beeld, foto werkt zoals vroeger', (tester) async {
      final s = newState();
      final server = FakeProRemote()..missing = true;
      final pro = newPro(s, server);
      pickPlatePhoto = (_) async => Uint8List.fromList(List.filled(2000, 7));
      photoLog = PhotoLog(MockClient((_) async => http.Response(jsonEncode({'text': '1 apple'}), 200)));
      await openSheet(tester, s, pro);
      expect(find.byKey(const ValueKey('photo-quota-left')), findsNothing);
      await tester.tap(find.byTooltip('Photo of your meal'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Estimated from your photo'), findsOneWidget);
      expect(find.byKey(const ValueKey('photo-quota-left')), findsNothing);
      expect(find.byKey(const ValueKey('photo-quota-out')), findsNothing);
    });
  });

  group('Pro-scherm', () {
    testWidgets('gratis: wat gratis blijft, wat Pro toevoegt, prijzen, Binnenkort en herstellen', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeProRemote()..photo = quota(1));
      await pump(tester, s, pro, const ProScreen());
      expect(find.text('Free plan'), findsOneWidget);
      expect(find.text('Always free'), findsOneWidget);
      expect(find.text('Logging with a photo: 3 photos per day'), findsOneWidget);
      expect(find.text('Friends, battles and challenges'), findsOneWidget);
      expect(find.text('Quick log by typing or with your voice'), findsOneWidget);
      expect(find.text('What Pro adds'), findsOneWidget);
      expect(find.textContaining('up to 50 a day'), findsOneWidget);
      expect(find.text('Why Pro?'), findsOneWidget);
      expect(find.textContaining('costs real computing'), findsOneWidget);
      expect(find.text('€2.99'), findsOneWidget);
      expect(find.text('€19.99'), findsOneWidget);
      expect(find.text('Photos today: 1 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pro-plan-monthly')));
      await tester.pump();
      expect(find.text('Subscribe · €2.99 / month'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Coming soon'), findsOneWidget);

      // Herstellen vraagt de server: niets gevonden
      await tester.tap(find.byKey(const ValueKey('pro-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('No Pro found'), findsOneWidget);
    });

    testWidgets('herstellen vindt Pro dat met de hand toegekend werd', (tester) async {
      final s = newState();
      final server = FakeProRemote();
      final pro = newPro(s, server);
      await pump(tester, s, pro, const ProScreen());
      server.status = ProStatus(until: DateTime(2099, 3, 1), source: 'manual');
      await tester.tap(find.byKey(const ValueKey('pro-restore')));
      await tester.pumpAndSettle();
      expect(find.text('Pro is active on this account.'), findsOneWidget);
      expect(find.text('You are a supporter'), findsOneWidget);
      expect(find.textContaining('Pro until 1 March 2099'), findsOneWidget);
      expect(find.byKey(const ValueKey('pro-prices')), findsNothing);
      // Badge verbergen voor vrienden
      await tester.tap(find.byKey(const ValueKey('pro-show-badge')));
      await tester.pumpAndSettle();
      expect(server.badge, isFalse);
      expect(pro.supporter, isFalse);
    });

    testWidgets('zonder Pro-dienst of migratie: geen crash, uitleg blijft', (tester) async {
      final s = newState();
      await pump(tester, s, null, const ProScreen());
      expect(find.text('Always free'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-subscribe')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Coming soon'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pro-restore')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Log in first'), findsOneWidget);

      final pro = newPro(s, FakeProRemote()..missing = true);
      await pump(tester, s, pro, const ProScreen());
      expect(find.text('Pro is not available yet.'), findsOneWidget);
      expect(find.text('Free plan'), findsOneWidget);
    });

    testWidgets('bereikbaar vanuit Instellingen', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeProRemote());
      await pump(
        tester,
        s,
        pro,
        Provider.value(value: Reminders(s), child: const SettingsScreen()),
        account: pro.account,
      );
      await tester.tap(find.byKey(const ValueKey('pro-tile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProScreen), findsOneWidget);
    });

    testWidgets('debug-schakelaar zet Pro aan op dit toestel', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeProRemote());
      await pump(tester, s, pro, const ProScreen());
      expect(find.byKey(const ValueKey('pro-debug')), findsOneWidget);
      await tester.tap(find.text('Pro').last);
      await tester.pumpAndSettle();
      expect(pro.isPro, isTrue);
      expect(find.text('You are a supporter'), findsOneWidget);
      pro.setDebugPro(null);
    });
  });

  group('extra kleuren', () {
    test('alleen met Pro wordt een andere kleur gebruikt', () {
      expect(effectiveAccent('ocean', pro: false), defaultAccent);
      expect(effectiveAccent('ocean', pro: true), 'ocean');
      expect(effectiveAccent('bestaat-niet', pro: true), defaultAccent);
      final ocean = buildTheme(Brightness.light, accent: 'ocean').extension<Palette>()!;
      expect(ocean.brand, accentById('ocean').light);
      expect(ocean.ink, Palette.light.ink);
      expect(buildTheme(Brightness.dark, accent: 'plum').extension<Palette>()!.brand, accentById('plum').dark);
      expect(buildTheme(Brightness.light).extension<Palette>()!.brand, Palette.light.brand);
      expect(accents.where((a) => !a.pro).map((a) => a.id), [defaultAccent]);
    });

    testWidgets('zonder Pro: slotje, een tik opent Pro en verandert niets', (tester) async {
      final s = newState();
      await pump(tester, s, newPro(s, FakeProRemote()), const Scaffold(body: AccentPicker()));
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(accents.length - 1));
      expect(find.byType(ProTag), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accent-ocean')));
      await tester.pumpAndSettle();
      expect(s.accent, defaultAccent);
      expect(find.byType(ProScreen), findsOneWidget);
    });

    testWidgets('met Pro: kiezen kan; loopt Pro af, dan terug naar petrol (keuze blijft bewaard)', (tester) async {
      final s = newState();
      final pro = newPro(s, FakeProRemote())..setDebugPro(true);
      await pump(tester, s, pro, const Scaffold(body: AccentPicker()));
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
      await tester.tap(find.byKey(const ValueKey('accent-plum')));
      await tester.pumpAndSettle();
      expect(s.accent, 'plum');
      expect(effectiveAccent(s.accent, pro: pro.isPro), 'plum');
      pro.setDebugPro(false);
      expect(effectiveAccent(s.accent, pro: pro.isPro), defaultAccent);
      expect(s.accent, 'plum');
      pro.setDebugPro(null);
    });
  });

  group('Supporter-badge', () {
    test('uit friend_list_v2; oude friend_list zonder kolom geeft geen badge', () {
      final row = {'other': 'a', 'name': 'An', 'state': 'friend', 'level': 3};
      expect(Friend.fromRow(row).supporter, isFalse);
      expect(Friend.fromRow({...row, 'supporter': true}).supporter, isTrue);
    });

    testWidgets('in de ranglijst naast de naam', (tester) async {
      final s = newState();
      Widget tile(bool supporter) => Scaffold(
        body: RankTile(
          row: RankRow(name: 'An', avatar: null, level: 3, supporter: supporter),
          place: 1,
          byLevel: false,
        ),
      );
      await pump(tester, s, null, tile(true));
      expect(find.byKey(const ValueKey('supporter-badge')), findsOneWidget);
      await pump(tester, s, null, tile(false));
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
    });

    testWidgets('op je Profiel (levelkaart) alleen met Pro en badge aan', (tester) async {
      final s = newState();
      final server = FakeProRemote();
      final pro = newPro(s, server);
      await pump(tester, s, pro, const Scaffold(body: SingleChildScrollView(child: LevelCard())));
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
      server.status = ProStatus(until: DateTime.now().add(const Duration(days: 30)));
      await pro.refresh();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('supporter-badge')), findsOneWidget);
      await pro.setShowBadge(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('supporter-badge')), findsNothing);
    });
  });

  group('uitgebreid jaaroverzicht', () {
    AppState logged() {
      final s = newState();
      final now = logicalNow();
      final apple = _foods.search('apple', limit: 1).first, bread = _foods.search('bread', limit: 1).first;
      for (var i = 0; i < 6; i++) {
        s.setDate(DateTime(now.year, now.month, now.day).subtract(Duration(days: i)));
        s.addFood(apple, meal: Meal.breakfast, grams: 150, quantity: 1);
        if (i.isEven) s.addFood(bread, meal: Meal.lunch, grams: 70, quantity: 1);
      }
      return s;
    }

    testWidgets('gratis: precies het gewone jaaroverzicht', (tester) async {
      final s = logged();
      final now = logicalNow();
      await pump(tester, s, newPro(s, FakeProRemote()), RecapScreen(from: DateTime(now.year), year: true));
      expect(find.text('Month by month'), findsOneWidget);
      expect(find.text('Your top 5'), findsOneWidget);
      expect(find.byKey(const ValueKey('recap-heatmap')), findsNothing);
      expect(find.byKey(const ValueKey('recap-records')), findsNothing);
      expect(find.byType(ProTag), findsNothing);
    });

    testWidgets('Pro: heatmap per maand, top 10 en records; een maandoverzicht blijft gewoon', (tester) async {
      final s = logged();
      final now = logicalNow();
      final pro = newPro(s, FakeProRemote())..setDebugPro(true);
      await pump(tester, s, pro, RecapScreen(from: DateTime(now.year), year: true));
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('recap-heatmap')), findsOneWidget);
      expect(find.text('Nutrients month by month'), findsOneWidget);
      expect(find.byKey(const ValueKey('recap-records')), findsOneWidget);
      expect(find.text('Best day'), findsOneWidget);
      // Alleen 2 verschillende producten: de lijst blijft even kort
      expect(find.textContaining('Your top'), findsOneWidget);

      await pump(tester, s, pro, RecapScreen(from: DateTime(now.year, now.month), year: false));
      expect(find.byKey(const ValueKey('recap-heatmap')), findsNothing);
      expect(find.text('Your top 5'), findsOneWidget);
      pro.setDebugPro(null);
    });

    test('recapExtras: 12 maanden per stof, top 10 en records', () {
      final s = logged();
      final x = s.recapExtras(logicalNow().year)!;
      expect(x.monthNutrients.keys, isNotEmpty);
      for (final v in x.monthNutrients.values) {
        expect(v.length, 12);
      }
      expect(x.monthNutrients['fiber']![logicalNow().month - 1], isNotNull);
      expect(x.topFoods.length, lessThanOrEqualTo(10));
      expect(x.records.map((r) => r.kind), contains(RecapRecordKind.bestScore));
      expect(s.recapExtras(logicalNow().year - 5), isNull);
    });
  });
}
