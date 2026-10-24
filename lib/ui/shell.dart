import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nutrition/levels.dart';
import '../platform/health_sync.dart';
import '../platform/home_widget_sync.dart';
import 'widgets/quick_log.dart';
import '../state/app_state.dart';
import '../sync/friends.dart';

import 'screens/oracle_screen.dart';
import 'screens/planner_screen.dart';
import 'screens/shopping_screen.dart';
import 'screens/body_screen.dart';
import 'screens/diary_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/product_scan_screen.dart';
import 'screens/labs_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/supplements_screen.dart';
import 'theme.dart';
import 'widgets/add_menu.dart';
import 'widgets/tap_guard.dart';
import 'widgets/avatar.dart';
import 'widgets/kit.dart';
import 'widgets/logo.dart';
import '../i18n.dart';

/// Hoofdscherm met vijf tabbladen (Lichaam zit onder Profiel). Op een gsm onderaan, op een tablet als smalle rail
/// links, en op een pc als zijbalk met namen en snelkoppelingen. Op een pc opent alles binnen het tabblad, zodat de
/// zijbalk blijft staan.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _index = 0;
  late final AppState _state = context.read<AppState>();

  @override
  void initState() {
    super.initState();
    _state.addListener(_checkLevel);
    _state.addListener(_checkStreak);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkLevel();
      HealthSync(_state).sync();
      HomeWidgetSync.update(_state);
      HomeWidgetSync.launchUri().then(_fromWidget);
    });
    _state.addListener(_updateWidget);
    _widgetClicks = HomeWidgetSync.clicks.listen(_fromWidget);
    _lifecycle = AppLifecycleListener(onResume: () => HealthSync(_state).sync());
  }

  AppLifecycleListener? _lifecycle;
  StreamSubscription<Uri?>? _widgetClicks;
  Timer? _widgetTimer;

  /// Widget bijwerken, hoogstens om de 2 seconden.
  void _updateWidget() {
    _widgetTimer?.cancel();
    _widgetTimer = Timer(const Duration(seconds: 2), () => HomeWidgetSync.update(_state));
  }

  /// Geopend via het widget: "Snel loggen" of gewoon Vandaag.
  void _fromWidget(Uri? uri) {
    if (uri == null || !mounted) return;
    setState(() => _index = _tab.value = 0);
    if (uri.host == 'quicklog') showQuickLog(context);
  }

  @override
  void dispose() {
    _state.removeListener(_checkLevel);
    _state.removeListener(_checkStreak);
    _lifecycle?.dispose();
    _state.removeListener(_updateWidget);
    _widgetClicks?.cancel();
    _widgetTimer?.cancel();
    _tab.dispose();
    _dashboardToDay.dispose();
    super.dispose();
  }

  /// Level omhoog? Dan een melding. Het laatst getoonde level staat lokaal, zodat een nieuw toestel niet alle
  /// levels van vroeger opnieuw meldt.
  static const _milestones = [7, 14, 30, 50, 100, 150, 200, 250, 300, 365, 500, 730, 1000];

  /// Mijlpaal in je reeks bereikt? Dan een feestelijke melding (één keer per mijlpaal, per toestel).
  void _checkStreak() {
    final n = _state.streak.current;
    final seen = (_state.user.setting('_streak_seen')?['n'] as int?) ?? 0;
    final hit = _milestones.where((m) => m <= n && m > seen).lastOrNull;
    if (hit == null) {
      if (n < seen) _state.user.setSetting('_streak_seen', {'n': n});
      return;
    }
    _state.user.setSetting('_streak_seen', {'n': hit});
    if (seen == 0 && n > 30 || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A00), size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(tr('$hit days in a row! Keep that fire burning.', '$hit dagen op rij! Houd dat vuur brandend.'))),
          ],
        ),
      ),
    );
  }

  void _checkLevel() {
    final level = _state.level.level;
    final seen = _state.user.setting('_level_seen')?['level'] as int?;
    if (seen == level) return;
    _state.user.setSetting('_level_seen', {'level': level});
    if (seen == null || level < seen || !mounted) return;
    final stars = starsFor(level) > starsFor(seen);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: Row(
          children: [
            LevelAvatar(avatar: _state.avatar, level: level, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                stars
                    ? tr('Level $level! You earned a new star.', 'Level $level! Je verdiende een nieuwe ster.')
                    : tr('Level up: you are now level $level!', 'Level omhoog: je bent nu level $level!'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static List<(IconData, IconData, String)> get _items => [
    (Icons.wb_sunny_outlined, Icons.wb_sunny_rounded, tr('Today', 'Vandaag')),
    (Icons.dashboard_outlined, Icons.dashboard_rounded, 'Dashboard'),
    (Icons.qr_code_scanner_rounded, Icons.qr_code_scanner_rounded, 'Scan'),
    (Icons.group_outlined, Icons.group_rounded, tr('Friends', 'Vrienden')),
    (Icons.person_outline_rounded, Icons.person_rounded, tr('Profile', 'Profiel')),
  ];

  /// Eén navigator per tabblad, zodat schermen die je opent naast de zijbalk blijven. Ze staan op elke breedte in
  /// dezelfde [_tabsKey]-boom: wordt het venster smaller of breder dan [desktopWidth], dan verandert alleen de
  /// zijbalk of de balk onderaan, en blijft een scherm dat in een tabblad openstaat gewoon staan.
  final _navigators = [for (var i = 0; i < 5; i++) GlobalKey<NavigatorState>()];
  final _tabsKey = GlobalKey();

  /// Houden bij of een tabblad een scherm open heeft, voor de terugknop (zie [_routesChanged]).
  late final _observers = [for (var i = 0; i < 5; i++) _TabObserver(_routesChanged)];

  /// Ook in een tabblad na het sluiten van een scherm heel even geen tikken (N03, zie tap_guard.dart).
  late final _guards = [for (var i = 0; i < 5; i++) tapGuard.observer()];
  bool _routesDirty = false;

  /// Een scherm geopend of gesloten in een tabblad: na dit beeld opnieuw bouwen, zodat de terugknop van het
  /// toestel eerst dat scherm sluit en pas daarna de app.
  void _routesChanged() {
    if (_routesDirty) return;
    _routesDirty = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _routesDirty = false;
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Het actieve tabblad voor de schermen in die navigators: die bouwen niet mee als de shell herbouwt.
  late final _tab = ValueNotifier(_index);

  /// Gaat af als het dagboek "Alle voedingsstoffen" opent: het dashboard toont dan die dag, niet een week of maand.
  final _dashboardToDay = ValueNotifier(0);

  /// Dashboard openen op de dag die in het dagboek gekozen is.
  void _openDayNutrients() {
    _navigators[1].currentState?.popUntil((r) => r.isFirst);
    _dashboardToDay.value++;
    _go(1);
  }

  void _go(int i) {
    // Een tabblad brengt je altijd naar het begin ervan (op een pc heeft elk tabblad zijn eigen navigator, en een
    // scherm dat daar nog openstond, verraste je als je via de zijbalk terugkwam). De staat van dat beginscherm
    // zelf (bv. week of maand op het dashboard) blijft bewaard.
    _navigators[i].currentState?.popUntil((r) => r.isFirst);
    // Het tabblad Vandaag brengt je ook echt naar vandaag, niet naar de dag die je laatst bekeek
    if (i == 0) context.read<AppState>().goToToday();
    setState(() => _index = _tab.value = i);
  }

  /// De snelkoppeling waarvan het scherm nu openstaat in het tabblad Profiel: die is dan het enige gemarkeerde
  /// item in de zijbalk, niet ook nog Profiel.
  int? _shortcut;
  Route<void>? _shortcutRoute;

  /// Snelkoppeling in de zijbalk: opent het scherm in het tabblad Profiel.
  void _open(int shortcut, Widget screen) {
    final nav = _navigators[4].currentState;
    nav?.popUntil((r) => r.isFirst);
    final route = MaterialPageRoute<void>(builder: (_) => screen);
    _shortcutRoute = route;
    setState(() {
      _index = _tab.value = 4;
      _shortcut = shortcut;
    });
    nav?.push(route);
    // Terug (pijltje, Escape of Profiel in de zijbalk): weer Profiel markeren
    route.popped.then((_) {
      if (mounted && identical(_shortcutRoute, route)) setState(() => _shortcut = _shortcutRoute = null);
    });
  }

  /// De beginschermen van de vijf tabbladen, met [tab] het actieve tabblad.
  List<Widget> _pagesFor(int tab) => [
    DiaryScreen(onOpenNutrients: _openDayNutrients, onOpenProfile: () => _go(4)),
    DashboardScreen(showDay: _dashboardToDay),
    const ProductScanScreen(),
    FriendsScreen(active: tab == 3),
    const ProfileScreen(),
  ];

  /// Tabbladicoon, met openstaande vriendschapsverzoeken en uitdagingen als bolletje op Vrienden.
  Widget Function(int i, IconData d) _icons(BuildContext context) {
    final requests = context.select<Friends, int>(
      (f) => f.list.where((x) => x.state == FriendState.incoming).length + f.battles.where((b) => b.pending && !b.challengedByMe).length,
    );
    return (i, d) => i == 3 && requests > 0 ? Badge(label: Text('$requests'), child: Icon(d)) : Icon(d);
  }

  /// Het beginscherm van tabblad [i]. Op een gsm staat de balk onderaan hierin, zodat een scherm dat je in het
  /// tabblad opent er volledig overheen schuift, net als vroeger.
  Widget _tabRoot(int i) => ValueListenableBuilder(
    valueListenable: _tab,
    builder: (context, tab, _) => Scaffold(
      body: _pagesFor(tab)[i],
      bottomNavigationBar: MediaQuery.sizeOf(context).width >= _railWidth
          ? null
          // Gsm: een ronde + in het midden (in plaats van het tabblad Scan, dat in het +-menu zit)
          : _PhoneBar(
              items: [
                for (final j in [0, 1, 3, 4]) (j, _items[j]),
              ],
              index: tab,
              icon: _icons(context),
              onSelect: _go,
              onAdd: () {
                if (_index != 0) _go(0);
                // Binnen het tabblad Vandaag, zodat wat je opent ook blijft staan als het venster breder wordt
                showAddMenu(_navigators[0].currentContext ?? this.context);
              },
            ),
    ),
  );

  /// De grote titel van Vandaag, maar als aanpassing van de gewone titelstijl: knoppen animeren hun thema, en dat
  /// lukt niet tussen een stijl die erft en een die dat niet doet (bij het smaller of breder maken van het venster).
  static TextStyle? _bigTitle(ThemeData theme) {
    final h = theme.textTheme.headlineMedium;
    return theme.appBarTheme.titleTextStyle?.copyWith(
      fontSize: h?.fontSize,
      fontWeight: h?.fontWeight,
      letterSpacing: h?.letterSpacing,
      height: h?.height,
      color: h?.color,
    );
  }

  /// Vanaf deze breedte (tot [desktopWidth]) een smalle rail links in plaats van de balk onderaan.
  static const _railWidth = 800.0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final theme = Theme.of(context);
    final icon = _icons(context);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= desktopWidth;

    // De tabbladen met hun navigators. Door [_tabsKey] verhuist deze boom mee als de indeling verandert, in plaats
    // van opnieuw gemaakt te worden.
    final tabs = PopScope(
      key: _tabsKey,
      // Terugknop van het toestel: eerst het scherm sluiten dat in het tabblad openstaat
      canPop: !(_navigators[_index].currentState?.canPop() ?? false),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigators[_index].currentState?.maybePop();
      },
      // Schermen met een titelbalk (snelkoppelingen, details) krijgen op een pc dezelfde grote titel als Vandaag
      // en Profiel, zodat de kop niet per scherm verspringt
      child: Theme(
        data: desktop
            ? theme.copyWith(appBarTheme: theme.appBarTheme.copyWith(titleTextStyle: _bigTitle(theme), toolbarHeight: 76, titleSpacing: 8))
            : theme,
        child: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _navigators.length; i++)
              // Een tabblad dat niet zichtbaar is, mag geen sneltoetsen of focus pakken
              TickerMode(
                enabled: i == _index,
                child: Navigator(
                  key: _navigators[i],
                  observers: [_observers[i], _guards[i]],
                  onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabRoot(i)),
                ),
              ),
          ],
        ),
      ),
    );

    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            _SideBar(
              items: _items,
              index: _index == 4 && _shortcut != null ? -1 : _index,
              shortcut: _index == 4 ? _shortcut : null,
              icon: icon,
              onSelect: _go,
              shortcuts: [
                (Icons.event_note_outlined, tr('Meal planner', 'Maaltijdplanner'), () => _open(0, const PlannerScreen())),
                (Icons.shopping_cart_outlined, tr('Shopping list', 'Boodschappenlijst'), () => _open(1, const ShoppingScreen())),
                (Icons.travel_explore_rounded, tr('Oracle', 'Orakel'), () => _open(2, const OracleScreen())),
                (Icons.monitor_weight_outlined, tr('Body', 'Lichaam'), () => _open(3, const BodyScreen())),
                (Icons.bloodtype_outlined, tr('Blood values', 'Bloedwaarden'), () => _open(4, const LabsScreen())),
                (Icons.medication_outlined, tr('Supplements', 'Supplementen'), () => _open(5, const SupplementsScreen())),
                (Icons.settings_outlined, tr('Settings', 'Instellingen'), () => _open(6, const SettingsScreen())),
              ],
            ),
            Expanded(child: tabs),
          ],
        ),
      );
    }

    if (width >= _railWidth) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final (i, (o, s, l)) in _items.indexed) NavigationRailDestination(icon: icon(i, o), selectedIcon: icon(i, s), label: Text(l)),
              ],
            ),
            VerticalDivider(width: 1, color: p.line),
            Expanded(child: tabs),
          ],
        ),
      );
    }
    // Gsm: de balk onderaan zit in het beginscherm van elk tabblad (zie [_tabRoot]). Geen Scaffold eromheen, zodat
    // meldingen onderaan boven die balk verschijnen en niet erover.
    return tabs;
  }
}

/// Meldt elke wijziging in de schermen van een tabblad.
class _TabObserver extends NavigatorObserver {
  _TabObserver(this.onChange);
  final VoidCallback onChange;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => onChange();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => onChange();
}

/// Navigatie onderaan op een gsm: twee tabbladen, de +-knop, twee tabbladen.
class _PhoneBar extends StatelessWidget {
  const _PhoneBar({required this.items, required this.index, required this.icon, required this.onSelect, required this.onAdd});
  final List<(int, (IconData, IconData, String))> items;
  final int index;
  final Widget Function(int i, IconData d) icon;
  final void Function(int) onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tab((int, (IconData, IconData, String)) item) {
      final (i, (o, sel, label)) = item;
      final on = i == index;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            onTap: () => onSelect(i),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(size: 24, color: on ? p.ink : p.ink3),
                  child: icon(i, on ? sel : o),
                ),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? p.ink : p.ink3),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Row(
            children: [
              tab(items[0]),
              tab(items[1]),
              Expanded(
                child: Center(child: AddButton(onPressed: onAdd)),
              ),
              tab(items[2]),
              tab(items[3]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zijbalk op een pc: logo, de vijf tabbladen met hun naam, snelkoppelingen, en onderaan je level en reeks.
class _SideBar extends StatelessWidget {
  const _SideBar({
    required this.items,
    required this.index,
    required this.shortcut,
    required this.icon,
    required this.onSelect,
    required this.shortcuts,
  });

  final List<(IconData, IconData, String)> items;

  /// Het gemarkeerde tabblad (-1: geen, want een snelkoppeling staat open).
  final int index;

  /// De snelkoppeling die openstaat, of null.
  final int? shortcut;
  final Widget Function(int i, IconData d) icon;
  final void Function(int) onSelect;
  final List<(IconData, String, VoidCallback)> shortcuts;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final s = context.watch<AppState>();
    final level = s.level.level;
    final streak = s.streak.current;
    // Laag venster (bv. een laptop met de browserbalken): alles iets compacter
    final low = MediaQuery.sizeOf(context).height < 760;
    return Container(
      width: 236,
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(right: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, low ? 14 : 22, 16, low ? 14 : 22),
              child: Row(
                children: [
                  const MatrixLogo(size: 34),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'MacroMatrix',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: p.ink, letterSpacing: -0.3),
                    ),
                  ),
                ],
              ),
            ),
            // In een laag venster scrollen de tabbladen en snelkoppelingen, zodat je level onderaan heel blijft
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, (o, sel, label)) in items.indexed)
                      _SideItem(icon: icon(i, i == index ? sel : o), label: label, selected: i == index, onTap: () => onSelect(i)),
                    Padding(padding: EdgeInsets.fromLTRB(22, low ? 14 : 22, 16, 8), child: Eyebrow(tr('Shortcuts', 'Snel naar'))),
                    for (final (j, (ic, label, onTap)) in shortcuts.indexed)
                      _SideItem(icon: Icon(ic), label: label, selected: j == shortcut, onTap: onTap, small: true),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(low ? 8 : 12),
              child: Material(
                color: p.surface2,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelect(4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        LevelAvatar(avatar: s.avatar, level: level, size: 38),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Level $level',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: p.ink),
                              ),
                              Text(
                                streak > 0
                                    ? (streak == 1 ? tr('1 day in a row', '1 dag op rij') : tr('$streak days in a row', '$streak dagen op rij'))
                                    : tr('Log today to start a streak', 'Log vandaag voor een reeks'),
                                style: TextStyle(fontSize: 12, color: p.ink2),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        if (streak > 0) const Icon(Icons.local_fire_department_rounded, color: Color(0xFFFF8A00), size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({required this.icon, required this.label, required this.selected, required this.onTap, this.small = false});
  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1.5),
      child: Material(
        color: selected ? p.sunken : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: SizedBox(
            height: small ? 38 : 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                IconTheme(
                  data: IconThemeData(size: small ? 20 : 22, color: selected ? p.ink : p.ink2),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: small ? 13.5 : 14.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? p.ink : p.ink2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
