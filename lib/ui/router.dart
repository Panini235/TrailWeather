import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'detail/route_detail_screen.dart';
import 'departure/departure_screen.dart';
import 'import/import_screen.dart';
import 'import/incoming_file_listener.dart';
import 'map/map_home_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'offline/offline_screens.dart';
import 'planet/planet_screen.dart';
import 'planner/route_planner_screen.dart';
import 'settings/settings_screen.dart';
import 'strings.dart';
import 'trips/trips_screen.dart';

/// 路由表（docs/redesign-v2.md）。
///
/// 底部导航三个分支：行程（首页）/ 地图 / 设置，各自保留状态（indexedStack）。
/// 详情、导入、规划等页面是顶层路由，压在整个外壳之上（不显示底部导航）。
/// 线路通过 `extra`（RouteDetailArgs）传入；缺失时（如 Web 刷新）回到首页。
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const TripsScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/map',
              builder: (context, state) => const MapHomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/route/:routeId',
      redirect: (context, state) => state.extra is RouteDetailArgs ? null : '/',
      builder: (context, state) =>
          RouteDetailScreen(args: state.extra! as RouteDetailArgs),
    ),
    GoRoute(
      path: '/departures',
      redirect: (context, state) => state.extra is DepartureArgs ? null : '/',
      builder: (context, state) =>
          DepartureScreen(args: state.extra! as DepartureArgs),
    ),
    GoRoute(
      path: '/offline',
      builder: (context, state) => const OfflineTripsScreen(),
    ),
    GoRoute(
      path: '/offline/new',
      redirect: (context, state) =>
          state.extra is OfflineDownloadArgs ? null : '/offline',
      builder: (context, state) =>
          OfflineDownloadScreen(args: state.extra! as OfflineDownloadArgs),
    ),
    GoRoute(
      path: '/offline/:id',
      builder: (context, state) =>
          OfflineTripScreen(id: state.pathParameters['id']!),
    ),
    GoRoute(path: '/import', builder: (context, state) => const ImportScreen()),
    GoRoute(
      path: '/planet',
      builder: (context, state) => const PlanetTrailsScreen(),
    ),
    GoRoute(
      path: '/planner',
      builder: (context, state) => const RoutePlannerScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    // 暂缓商业化期间，旧链接也不能进入付费墙。
    GoRoute(path: '/paywall', redirect: (context, state) => '/'),
  ],
);

/// 底部导航外壳。
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IncomingFileListener(child: shell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) =>
            shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.route), label: S.tabTrips),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            label: S.tabMap,
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: S.tabSettings,
          ),
        ],
      ),
    );
  }
}
