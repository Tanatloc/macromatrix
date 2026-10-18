import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../nutrition/levels.dart';
import '../platform/health_sync.dart';
import '../platform/home_widget_sync.dart';
import 'widgets/quick_log.dart';
import '../state/app_state.dart';
import '../sync/friends.dart';

import 'screens/diary_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/friends_screen.dart';
import 'screens/product_scan_screen.dart';
import 'screens/profile_screen.dart';
import 'theme.dart';
import 'widgets/avatar.dart';
import '../i18n.dart';

/// Hoofdscherm met vijf tabbladen (Lichaam zit onder Profiel). Op een smal scherm (gsm) onderaan, op een breed scherm (pc) links.
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
    setState(() => _index = 0);
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

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final pages = [
      DiaryScreen(onOpenNutrients: () => _go(1), onOpenProfile: () => _go(4)),
      const DashboardScreen(),
      const ProductScanScreen(),
      FriendsScreen(active: _index == 3),
      const ProfileScreen(),
    ];
    // Openstaande vriendschapsverzoeken en uitdagingen als bolletje op het tabblad Vrienden
    final requests = context.select<Friends, int>(
      (f) => f.list.where((x) => x.state == FriendState.incoming).length + f.battles.where((b) => b.pending && !b.challengedByMe).length,
    );
    Widget icon(int i, IconData d) => i == 3 && requests > 0 ? Badge(label: Text('$requests'), child: Icon(d)) : Icon(d);
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final body = IndexedStack(index: _index, children: pages);

    if (wide) {
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
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: p.line)),
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _go,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [for (final (i, (o, s, l)) in _items.indexed) NavigationDestination(icon: icon(i, o), selectedIcon: icon(i, s), label: l)],
        ),
      ),
    );
  }
}
