import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/location/location_service.dart';
import 'package:trailweather/data/routes/overpass.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';
import 'package:trailweather/ui/map/map_home_screen.dart';
import 'package:trailweather/ui/strings.dart';

class _FakeLocationService implements LocationService {
  int calls = 0;

  @override
  Future<LocationFix> currentPosition({
    void Function(LatLng)? onLastKnown,
  }) async {
    calls++;
    return LocationFix(
      calls == 1
          ? const LatLng(31.2304, 121.4737)
          : const LatLng(30.2741, 120.1551),
    );
  }

  @override
  Future<bool> openSettings(LocationFailureKind kind) async => true;
}

class _FakeRouteSource extends OverpassRouteSource {
  int calls = 0;

  @override
  Future<List<HikingRoute>> fetchRoutesInBBox(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) async {
    calls++;
    return const [];
  }
}

class _FakeWeatherProvider extends WeatherProvider {
  @override
  ProviderCapabilities get caps => ProviderCapabilities(
    providerId: 'open-meteo:best_match',
    vendor: 'Test',
    displayName: '测试天气',
    modelOrNetwork: 'fixture',
    coverage: '测试',
    forecastHorizonDays: 2,
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
    supportedVars: const [WxVar.temperature, WxVar.precip, WxVar.windSpeed],
    minRequestIntervalMs: 0,
    recommendedCacheTtl: const Duration(minutes: 30),
    spatialResolutionNote: '测试网格',
  );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async => [
    for (final point in points)
      WxPointForecast(
        lat: point.latitude,
        lon: point.longitude,
        hours: [
          WxHourValue(
            validFromUtc: startUtc,
            values: {
              for (final variable in WxVar.values) variable: null,
              WxVar.temperature: 18,
              WxVar.precip: 0.4,
              WxVar.windSpeed: 2.5,
            },
          ),
        ],
        provenance: WxProvenance(
          providerId: caps.providerId,
          vendor: caps.vendor,
          modelOrNetwork: caps.modelOrNetwork,
          modelKnown: true,
          requestLat: point.latitude,
          requestLon: point.longitude,
          returnedLat: point.latitude,
          returnedLon: point.longitude,
          locationDetail: '测试网格中心',
          elevationUsedM: null,
          granularity: WxGranularity.grid,
          spatialResolutionNote: caps.spatialResolutionNote,
          dataKind: WxDataKind.forecast,
          fetchedAtUtc: startUtc,
          modelRunUtc: startUtc,
          utcOffsetSeconds: 28800,
          license: 'test',
          attribution: 'test',
          interpolationNote: null,
          elevationAdjustNote: null,
          traceNote: 'fixture',
        ),
      ),
  ];
}

void main() {
  testWidgets('首页自动定位只显示当前位置天气标签，点击才打开面板，不自动请求 OSM', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final location = _FakeLocationService();
    final routes = _FakeRouteSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(preferences),
          locationServiceProvider.overrideWithValue(location),
          overpassRouteSourceProvider.overrideWithValue(routes),
          weatherProvidersProvider.overrideWithValue([_FakeWeatherProvider()]),
        ],
        child: const MaterialApp(home: MapHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(location.calls, 1);
    // 不自动弹出面板，也不自动发 Overpass 请求。
    expect(routes.calls, 0);
    expect(find.text(S.currentLocation), findsNothing);
    expect(find.text('${S.myLocationChip} · 18°C'), findsOneWidget);
    expect(find.text('测试天气'), findsOneWidget);
    // “搜索此区域”不再是首页主按钮。
    expect(find.byTooltip(S.searchThisArea), findsNothing);

    await tester.tap(find.text('${S.myLocationChip} · 18°C'));
    await tester.pumpAndSettle();
    expect(find.text(S.currentLocation), findsOneWidget);
    expect(find.text(S.selectedPointWeather), findsNothing);
    expect(find.textContaining('31.23040, 121.47370'), findsOneWidget);

    // 点击 bottom sheet 外部关闭，定位按钮应恢复为可点击状态。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(find.text(S.currentLocation), findsNothing);

    await tester.tap(find.byTooltip(S.locateMe));
    await tester.pumpAndSettle();

    expect(location.calls, 2);
    expect(routes.calls, 0);
    expect(find.text(S.currentLocation), findsNothing);
    await tester.tap(find.text('${S.myLocationChip} · 18°C'));
    await tester.pumpAndSettle();
    expect(find.text(S.currentLocation), findsOneWidget);
    expect(find.textContaining('30.27410, 120.15510'), findsOneWidget);
  });
}
