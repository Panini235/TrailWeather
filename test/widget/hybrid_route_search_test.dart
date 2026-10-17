import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/geocode.dart';
import 'package:trailweather/data/location/location_service.dart';
import 'package:trailweather/data/routes/overpass.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/map/hybrid_route_search.dart';
import 'package:trailweather/ui/map/map_home_screen.dart';
import 'package:trailweather/ui/map/point_weather_sheet.dart';
import 'package:trailweather/ui/strings.dart';

import '../integration/core_flow_test.dart' show IntegrationFakeProvider;



class _DeniedLocationService implements LocationService {
  @override
  Future<LocationFix> currentPosition({
    void Function(LatLng)? onLastKnown,
    bool requestPermission = true,
  }) async =>
      throw const LocationFailure(LocationFailureKind.denied, '测试中不启用定位');

  @override
  Future<bool> openSettings(LocationFailureKind kind) async => false;
}

class _FakeGeocodeService extends GeocodeService {
  int calls = 0;

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String language = 'zh',
    int count = 8,
  }) async {
    calls++;
    return const [
      PlaceSuggestion(
        name: '香山公园',
        admin: '北京市',
        country: '中国',
        lat: 39.9907,
        lon: 116.1862,
        timezone: 'Asia/Shanghai',
      ),
    ];
  }
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
    return [
      HikingRoute(
        id: 'osm-r-search',
        name: '香山防火道',
        origin: RouteOrigin.osm,
        segments: const [
          [LatLng(39.9907, 116.1862), LatLng(39.995, 116.19)],
        ],
        elevationsM: const [null, null],
        sourceName: 'OpenStreetMap 徒步路线关系',
        sourceLicense: 'ODbL 1.0',
      ),
    ];
  }
}

HikingRoute _localRoute() => HikingRoute(
  id: 'local-xiangshan',
  name: '香山环线',
  origin: RouteOrigin.import,
  segments: const [
    [LatLng(39.99, 116.18), LatLng(40.0, 116.19)],
  ],
  elevationsM: const [100, 180],
  sourceName: '用户导入',
);

void main() {
  testWidgets('混合搜索分组展示线路与地点，不再有外部百度搜索，选地点不自动请求 OSM', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final routes = _FakeRouteSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(preferences),
          locationServiceProvider.overrideWithValue(_DeniedLocationService()),
          geocodeServiceProvider.overrideWithValue(_FakeGeocodeService()),
          overpassRouteSourceProvider.overrideWithValue(routes),
          localRoutesProvider.overrideWithValue([_localRoute()]),
        ],
        child: MaterialApp(
          home: const MapHomeScreen(),
          routes: {
            '/import': (context) =>
                const Scaffold(body: Center(child: Text('导入测试页'))),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '香山');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.textContaining(S.hybridSearchTitle), findsOneWidget);
    expect(find.text(S.directRoutes), findsOneWidget);
    expect(find.text('香山环线'), findsOneWidget);
    expect(find.text(S.placeCandidates), findsOneWidget);
    expect(find.text('香山公园'), findsOneWidget);
    // 跳转百度的外部攻略已移除（docs/redesign-v2.md）。
    expect(find.textContaining('百度'), findsNothing);
    expect(find.text('小红书攻略'), findsNothing);

    final resultsList = find.descendant(
      of: find.byType(HybridRouteSearchResults),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('香山公园'),
      -180,
      scrollable: resultsList,
    );
    await tester.tap(find.text('香山公园'));
    await tester.pumpAndSettle();
    expect(routes.calls, 0);

    await tester.drag(resultsList, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('香山环线'));
    await tester.pumpAndSettle();
    expect(find.text(S.viewDetail), findsOneWidget);
    expect(find.textContaining(S.hybridSearchTitle), findsNothing);
  });

  testWidgets('OSM 区域线路只能从线路列表的次要入口主动加载', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final routes = _FakeRouteSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(preferences),
          locationServiceProvider.overrideWithValue(_DeniedLocationService()),
          overpassRouteSourceProvider.overrideWithValue(routes),
          localRoutesProvider.overrideWithValue(const []),
        ],
        child: const MaterialApp(home: MapHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(routes.calls, 0);
    expect(find.byTooltip(S.searchThisArea), findsNothing);

    await tester.tap(find.byTooltip(S.listButton));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(S.tryOsmArea));
    await tester.pumpAndSettle();
    expect(find.text(S.tryOsmAreaNote), findsOneWidget);
    await tester.tap(find.text(S.tryOsmArea));
    await tester.pumpAndSettle();
    expect(routes.calls, 1);
    expect(find.text('已加载 1 条 OSM 线路。'), findsOneWidget);
  });

  testWidgets('输入经纬度：结果最上方给出坐标，不请求地名搜索，点击打开该点天气', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final geocode = _FakeGeocodeService();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(preferences),
          locationServiceProvider.overrideWithValue(_DeniedLocationService()),
          geocodeServiceProvider.overrideWithValue(geocode),
          overpassRouteSourceProvider.overrideWithValue(_FakeRouteSource()),
          localRoutesProvider.overrideWithValue(const []),
          weatherProvidersProvider.overrideWithValue([
            IntegrationFakeProvider(),
          ]),
        ],
        child: const MaterialApp(home: MapHomeScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '116.17，39.99');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();
    expect(geocode.calls, 0);
    expect(find.textContaining('39.99000, 116.17000'), findsOneWidget);
    expect(find.textContaining(S.coordinateSwappedNote), findsOneWidget);

    await tester.tap(find.textContaining('39.99000, 116.17000'));
    await tester.pumpAndSettle();
    expect(find.byType(PointWeatherSheet), findsOneWidget);
    expect(find.textContaining('39.99000, 116.17000'), findsWidgets);
  });
}
