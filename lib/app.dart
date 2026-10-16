import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/semantics.dart' show SemanticsHandle;
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

class TrailWeatherApp extends ConsumerStatefulWidget {
  const TrailWeatherApp({super.key});

  @override
  ConsumerState<TrailWeatherApp> createState() => _TrailWeatherAppState();
}

class _TrailWeatherAppState extends ConsumerState<TrailWeatherApp> {
  SemanticsHandle? _webSemantics;

  @override
  void initState() {
    super.initState();
    // Web 首屏就提供可访问的控件语义，让键盘和读屏用户能直接操作。
    if (kIsWeb) _webSemantics = WidgetsBinding.instance.ensureSemantics();
  }

  @override
  void dispose() {
    _webSemantics?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp.router(
      title: kIsWeb ? '${S.appTitle}｜徒步天气与行前规划' : S.appTitle,
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
