import 'package:go_router/go_router.dart';

import 'detail/route_detail_screen.dart';
import 'import/import_screen.dart';
import 'map/map_home_screen.dart';
import 'onboarding/onboarding_screen.dart';
import 'paywall/paywall_screen.dart';
import 'planet/planet_screen.dart';
import 'planner/route_planner_screen.dart';
import 'settings/settings_screen.dart';

/// 路由表。routeId 用于从线路目录中查找（本地库/收藏），
/// OSM 线路选中后先落入内存目录再跳转（见 MapHomeScreen._catalog）。
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const MapHomeScreen()),
    GoRoute(
      path: '/route/:routeId',
      builder: (context, state) {
        final route = state.extra as RouteDetailArgs?;
        if (route == null) {
          return const MapHomeScreen();
        }
        return RouteDetailScreen(args: route);
      },
    ),
    GoRoute(
      path: '/settings',
      builder: (context, state) => const SettingsScreen(),
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
    GoRoute(
      path: '/paywall',
      builder: (context, state) {
        final source = state.extra as String?;
        return PaywallScreen(sourceFeature: source);
      },
    ),
  ],
);
