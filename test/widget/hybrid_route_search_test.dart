import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/external_url_launcher.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/geocode.dart';
import 'package:trailweather/data/location/location_service.dart';
import 'package:trailweather/data/routes/overpass.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/map/hybrid_route_search.dart';
import 'package:trailweather/ui/map/map_home_screen.dart';
import 'package:trailweather/ui/strings.dart';

class _DeniedLocationService implements LocationService {
  @override
  Future<LatLng> currentPosition() async =>
      throw const LocationFailure(LocationFailureKind.denied, '测试中不启用定位');

  @override
  Future<bool> openSettings(LocationFailureKind kind) async => false;
}

class _FakeGeocodeService extends GeocodeService {
  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    String language = 'zh',
    int count = 8,
  }) async => const [
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

class _FakeExternalLauncher implements ExternalUrlLauncher {
  Uri? opened;

  @override
  Future<bool> open(Uri uri) async {
    opened = uri;
    return true;
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
  testWidgets('混合搜索分组展示线路、地点、外部攻略并加载附近 OSM 线路', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final external = _FakeExternalLauncher();
    final routes = _FakeRouteSource();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(preferences),
          locationServiceProvider.overrideWithValue(_DeniedLocationService()),
          geocodeServiceProvider.overrideWithValue(_FakeGeocodeService()),
          externalUrlLauncherProvider.overrideWithValue(external),
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
    expect(find.text(S.externalGuides), findsOneWidget);
    expect(find.text('小红书攻略'), findsOneWidget);
    expect(find.text('两步路轨迹'), findsOneWidget);

    await tester.tap(find.text('小红书攻略'));
    await tester.pumpAndSettle();
    expect(external.opened, isNotNull);
    expect(external.opened!.host, 'www.baidu.com');
    expect(external.opened!.queryParameters['wd'], contains('xiaohongshu.com'));

    final resultsList = find.descendant(
      of: find.byType(HybridRouteSearchResults),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('六只脚线路'),
      180,
      scrollable: resultsList,
    );
    expect(find.text('六只脚线路'), findsOneWidget);
    expect(find.text(S.importOwnedTrack), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('香山公园'),
      -180,
      scrollable: resultsList,
    );
    await tester.tap(find.text('香山公园'));
    await tester.pumpAndSettle();
    expect(routes.calls, 1);
    expect(find.text('香山防火道'), findsOneWidget);

    await tester.drag(resultsList, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.tap(find.text('香山环线'));
    await tester.pumpAndSettle();
    expect(find.text(S.viewDetail), findsOneWidget);
    expect(find.textContaining(S.hybridSearchTitle), findsNothing);
  });
}
