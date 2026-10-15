import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/onboarding/onboarding_screen.dart';
import 'package:trailweather/ui/theme.dart';

void main() {
  for (final importRoute in [false, true]) {
    testWidgets('首次引导直接进入${importRoute ? '导入' : '示例'}并记住完成状态，无付费引导', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(
        initialLocation: '/onboarding',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('示例线路首页')),
          ),
          GoRoute(
            path: '/import',
            builder: (_, _) => const Scaffold(body: Text('线路导入页')),
          ),
          GoRoute(
            path: '/onboarding',
            builder: (_, _) => const OnboardingScreen(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [prefsProvider.overrideWithValue(prefs)],
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('出发前，看懂沿途天气'), findsOneWidget);
      expect(find.textContaining('离线行程包尚未提供'), findsOneWidget);
      expect(find.textContaining('Pro'), findsNothing);
      expect(find.textContaining('试用'), findsNothing);
      final action = find.text(importRoute ? '导入我的线路' : '先看示例线路');
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(find.text(importRoute ? '线路导入页' : '示例线路首页'), findsOneWidget);
      expect(
        prefs.getString('settings.v1'),
        contains('"hasCompletedOnboarding":true'),
      );
      if (importRoute) {
        router.pop();
        await tester.pumpAndSettle();
        expect(find.text('示例线路首页'), findsOneWidget);
        expect(find.byType(OnboardingScreen), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
