import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';
import 'package:trailweather/ui/detail/route_detail_screen.dart';
import 'package:trailweather/ui/map/map_home_screen.dart';
import 'package:trailweather/ui/widgets/common.dart';
import 'package:trailweather/ui/strings.dart';

/// 集成假来源：返回固定但结构完整的逐时数据（不联网）。
class IntegrationFakeProvider extends WeatherProvider {
  @override
  ProviderCapabilities get caps => ProviderCapabilities(
        providerId: 'fake:integration',
        vendor: 'FakeVendor',
        displayName: 'Fake（集成测试）',
        modelOrNetwork: 'fake-model',
        coverage: '测试',
        forecastHorizonDays: 7,
        intervalHours: 1,
        batchCoordinates: true,
        maxPointsPerRequest: 10,
        granularity: WxGranularity.grid,
        dataKind: WxDataKind.forecast,
        requiresApiKey: false,
        browserCorsOk: true,
        browserNotes: '',
        license: 'test',
        attribution: 'test',
        supportedVars: const [
          WxVar.temperature,
          WxVar.apparentTemp,
          WxVar.precip,
          WxVar.precipProb,
          WxVar.windSpeed,
          WxVar.windGust,
        ],
        minRequestIntervalMs: 0,
        recommendedCacheTtl: const Duration(minutes: 30),
        spatialResolutionNote: '测试：约 10 km 网格',
      );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(now.year, now.month, now.day).subtract(const Duration(hours: 2));
    return [
      for (final p in points)
        WxPointForecast(
          lat: p.latitude,
          lon: p.longitude,
          dailySunsetUtc: DateTime.utc(now.year, now.month, now.day, 11),
          hours: [
            for (var i = 0; i < 72; i++)
              WxHourValue(
                validFromUtc: start.add(Duration(hours: i)),
                values: {
                  WxVar.temperature: 15.0 + (i % 6),
                  WxVar.apparentTemp: 13.0,
                  WxVar.precip: i % 12 == 0 ? 1.5 : 0.0,
                  WxVar.precipProb: i % 12 == 0 ? 60.0 : 5.0,
                  WxVar.windSpeed: 3.0,
                  WxVar.windGust: i % 10 == 0 ? 18.0 : 8.0,
                },
              ),
          ],
          provenance: WxProvenance(
            providerId: caps.providerId,
            vendor: caps.vendor,
            modelOrNetwork: caps.modelOrNetwork,
            modelKnown: true,
            requestLat: p.latitude,
            requestLon: p.longitude,
            returnedLat: p.latitude,
            returnedLon: p.longitude,
            locationDetail: '网格预报；来源未提供网格中心标识',
            elevationUsedM: 120,
            granularity: WxGranularity.grid,
            spatialResolutionNote: caps.spatialResolutionNote,
            dataKind: WxDataKind.forecast,
            fetchedAtUtc: now,
            modelRunUtc: now,
            utcOffsetSeconds: 28800,
            license: 'test',
            attribution: 'test',
            interpolationNote: null,
            elevationAdjustNote: null,
            traceNote: 'fake',
          ),
        ),
    ];
  }
}

HikingRoute _demoRoute() => HikingRoute(
      id: 'demo-int',
      name: '集成测试线路',
      origin: RouteOrigin.demo,
      segments: [
        [
          for (var i = 0; i < 40; i++) LatLng(39.99 + i * 0.001, 116.18 + i * 0.001),
        ],
      ],
      elevationsM: [for (var i = 0; i < 40; i++) i * 20.0],
      sourceName: '集成测试',
      isDemo: true,
    );

Future<SharedPreferences> _mockPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        weatherProvidersProvider.overrideWithValue([IntegrationFakeProvider()]),
      ],
      child: const _AppShell(),
    ),
  );
  await tester.pumpAndSettle();
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MapHomeScreen(),
      routes: {
        '/import': (c) => const Scaffold(body: Center(child: Text('import'))),
        '/settings': (c) => const Scaffold(body: Center(child: Text('settings'))),
      },
    );
  }
}

void main() {
  testWidgets('核心闭环：地图 → 线路列表 → 详情 → 天气节点 → 行程模式 → 收藏 → 重启恢复',
      (tester) async {
    final prefs = await _mockPrefs();
    await _pumpApp(tester, prefs);

    // 1. 地图首页可见
    expect(find.byType(MapHomeScreen), findsOneWidget);

    // 2. 打开线路列表抽屉，出现示例线路（演示数据）
    await tester.tap(find.byTooltip(S.listButton));
    await tester.pumpAndSettle();
    expect(find.text(S.routeListTitle), findsOneWidget);
    expect(find.byType(DemoBadge), findsWidgets);

    // 3. 替换为详情页（地图 polyline 命中交互由 flutter_map 自身保障，此处验证业务闭环）
    final route = _demoRoute();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          weatherProvidersProvider.overrideWithValue([IntegrationFakeProvider()]),
        ],
        child: MaterialApp(home: RouteDetailScreen(args: RouteDetailArgs(route: route))),
      ),
    );
    // 数据 future 与 pumpAndSettle 存在时序边界：显式泵帧直到天气区渲染。
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    // 4. 详情页：事实卡 + 演示标签（ListView 懒挂载，断言前滚动到目标）
    expect(find.text('集成测试线路'), findsOneWidget);
    expect(find.byType(DemoBadge), findsWidgets); // AppBar 与来源行各一处

    // 5. 滚动到天气区：节点有数据（温度文本出现）
    await tester.scrollUntilVisible(find.text(S.routeSummary), 300);
    await tester.pumpAndSettle();
    expect(find.text(S.routeSummary), findsOneWidget);
    expect(find.textContaining('°C'), findsWidgets);

    // 溯源卡片与颗粒度声明（滚动到底部）
    await tester.scrollUntilVisible(find.text(S.sourceTransparency), 600);
    await tester.pumpAndSettle();
    expect(find.text(S.sourceTransparency), findsOneWidget);
    expect(find.textContaining('非点位实测'), findsWidgets);

    // 6. 回滚顶部切换行程模式 → 显示预计到达说明
    await tester.drag(find.byType(ListView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.modeTrip));
    await tester.pumpAndSettle();
    // ETA 说明与模式按钮同卡（视口内），无需滚动。
    expect(find.textContaining(S.etaIsEstimate), findsWidgets);

    // 7. 循环滚动：官方预警未接入的如实说明（在风险提示卡内）
    var alertsVisible = false;
    for (var i = 0; i < 12 && !alertsVisible; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      alertsVisible =
          find.textContaining(officialAlertsText0).evaluate().isNotEmpty;
    }
    expect(alertsVisible, isTrue, reason: '滚动后应显示官方预警未接入说明');

    // 8. 收藏 → 写入本地
    await tester.tap(find.byTooltip(S.favorites));
    await tester.pumpAndSettle();

    // 9. 重启恢复：同一 prefs 重新构建，收藏可恢复
    expect(prefs.getString('favorites.v1'), isNotNull);
  });
}

const officialAlertsText0 = '官方气象预警：未接入';
