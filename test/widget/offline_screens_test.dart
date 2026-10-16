import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/app.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/offline/offline_providers.dart';
import 'package:trailweather/data/offline/offline_repository.dart';
import 'package:trailweather/data/offline/offline_store_prefs.dart';
import 'package:trailweather/data/offline/offline_trip.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_repository.dart';
import 'package:trailweather/ui/offline/offline_screens.dart';
import 'package:trailweather/ui/strings.dart';

import '../support/offline_fixtures.dart';

void main() {
  late SharedPreferences prefs;
  late OfflineWeatherFixture source;
  late OfflineTripRepository repository;
  late OfflineTrip trip;
  late WeatherRepository weather;
  final now = DateTime.utc(2026, 10, 17, 1);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    source = OfflineWeatherFixture()..missingHours = {0};
    weather = WeatherRepository(cache: CacheStore(prefs), providers: [source]);
    repository = OfflineTripRepository(
      store: PreferencesOfflineTripStore(prefs),
      weather: () => weather,
      now: () => now,
    );
    trip = await repository.download(
      plan: offlinePlan(),
      providerId: source.caps.providerId,
    );
  });

  Future<void> pumpOffline(
    WidgetTester tester,
    Widget screen, {
    bool dark = false,
    double scale = 2,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final offline = OfflineTripRepository(
      store: PreferencesOfflineTripStore(prefs),
      weather: () => throw StateError('离线界面禁止访问天气服务'),
      now: () => now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          offlineRepositoryProvider.overrideWithValue(offline),
          weatherNowProvider.overrideWithValue(() => now),
          weatherRepositoryProvider.overrideWith(
            (_) => throw StateError('不能初始化天气仓库'),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final dark in [false, true]) {
    testWidgets('离线阅读：360px / 2倍文字 / ${dark ? '深色' : '浅色'}，缺口与旧数据可见，不请求天气或地图', (
      tester,
    ) async {
      await pumpOffline(tester, OfflineTripScreen(id: trip.id), dark: dark);
      expect(find.text('离线测试线路'), findsOneWidget);
      expect(find.text(S.demoLabel), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('旧预报：'), 250);
      expect(find.textContaining('旧预报：'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('覆盖不全：'), 250);
      expect(find.textContaining('覆盖不全：'), findsOneWidget);
      await tester.scrollUntilVisible(find.byTooltip('前一小时'), 300);
      // now=01:00，向前一小时选择已知缺口 00:00。
      await tester.tap(find.byTooltip('前一小时'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('此来源未提供该时次预报，不能判断天气。').first,
        250,
      );
      expect(find.text('此来源未提供该时次预报，不能判断天气。'), findsWidgets);
      await tester.scrollUntilVisible(find.byTooltip('后一小时'), -250);
      await tester.tap(find.byTooltip('后一小时'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text(S.notProvided).first, 250);
      expect(find.text(S.notProvided), findsWidgets);
      expect(find.byType(FlutterMap), findsNothing);
      expect(source.calls, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('独立列表读取正常包与损坏包，损坏项可见且不请求天气', (tester) async {
    await PreferencesOfflineTripStore(prefs).write('broken', 'broken');
    await pumpOffline(tester, const OfflineTripsScreen(), scale: 1);
    expect(find.text('离线测试线路'), findsOneWidget);
    expect(find.text('离线包无法读取'), findsOneWidget);
    expect(find.textContaining('演示线路'), findsOneWidget);
    expect(source.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页入口 → 列表 → 离线详情，模拟重启时不初始化天气仓库', (tester) async {
    await prefs.setString('settings.v1', '{"hasCompletedOnboarding":true}');
    final offline = OfflineTripRepository(
      store: PreferencesOfflineTripStore(prefs),
      weather: () => throw StateError('禁止天气网络'),
      now: () => now,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          offlineRepositoryProvider.overrideWithValue(offline),
          sampleRoutesProvider.overrideWith((_) async => []),
          weatherNowProvider.overrideWithValue(() => now),
          weatherRepositoryProvider.overrideWith(
            (_) => throw StateError('不能初始化天气仓库'),
          ),
        ],
        child: const TrailWeatherApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线行程包'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('离线测试线路'));
    await tester.pumpAndSettle();
    expect(find.text('离线查看'), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    expect(source.calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('下载可选时段，失败后重试成功打开已校验包，浏览页面不额外请求', (tester) async {
    await prefs.setString('settings.v1', '{"hasCompletedOnboarding":true}');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          offlineRepositoryProvider.overrideWithValue(repository),
          weatherRepositoryProvider.overrideWithValue(weather),
          weatherProvidersProvider.overrideWithValue([source]),
          weatherNowProvider.overrideWithValue(() => now),
          sampleRoutesProvider.overrideWith((_) async => []),
        ],
        child: const TrailWeatherApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    unawaited(
      container
          .read(appRouterProvider)
          .push(
            '/offline/new',
            extra: OfflineDownloadArgs(
              plan: offlinePlan(),
              providerId: source.caps.providerId,
            ),
          ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('24 小时'));
    await tester.pumpAndSettle();
    source.fail = true;
    await tester.scrollUntilVisible(find.text('下载并校验'), 250);
    await tester.tap(find.text('下载并校验'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('重新下载'), 250);
    expect(find.text('重新下载'), findsOneWidget);
    expect((await repository.list()), hasLength(1));
    source.fail = false;
    await tester.tap(find.text('重新下载'));
    await tester.pumpAndSettle();
    expect(find.text('离线查看'), findsOneWidget);
    expect(
      (await repository.list()).any((e) => e.trip?.plan.hourCount == 24),
      isTrue,
    );
    expect(source.calls, 3);
    expect(tester.takeException(), isNull);
  });
}
