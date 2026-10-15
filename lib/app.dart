import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/settings/settings_repository.dart';
import 'ui/router.dart';
import 'ui/strings.dart';
import 'ui/theme.dart';

/// 路由器必须在 App 生命周期内只创建一次：放在 build 里会在任何设置变化
/// （如切换深色模式）时重建，导致导航栈被重置回首页。
final appRouterProvider = Provider<GoRouter>((ref) => buildRouter());

class TrailWeatherApp extends ConsumerWidget {
  const TrailWeatherApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: S.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
