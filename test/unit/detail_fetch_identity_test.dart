import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

import '../weather/cache_freshness_test.dart' show WindowProvider;

import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/ui/detail/detail_state.dart';
import 'package:trailweather/ui/detail/route_detail_screen.dart';

void main() {
  final query = RouteWeatherQuery(
    routeId: 'same',
    providerId: 'test',
    mode: TimeMode.fixed,
    startUtc: DateTime.utc(2026, 10, 16),
    endUtc: DateTime.utc(2026, 10, 17),
    fixedUtc: DateTime.utc(2026, 10, 16),
    pace: PaceConfig.defaults,
  );
  RouteNode node(double lat, double distance, {double elevation = 100}) =>
      RouteNode(
        pointIndex: distance == 0 ? 0 : 1,
        pos: LatLng(lat, 120),
        elevationM: elevation,
        distFromStartM: distance,
      );
  DetailFetchKey key(List<RouteNode> nodes) =>
      DetailFetchKey(nodes: nodes, query: query);

  test('同数量同长度线路反向或中间坐标变化不复用天气身份', () {
    final forward = key([node(30, 0), node(31, 1000)]);
    final reverse = key([node(31, 0), node(30, 1000)]);
    final edited = key([node(30, 0), node(30.9, 1000)]);
    expect(forward, isNot(reverse));
    expect(forward, isNot(edited));
    expect({forward: '正向', reverse: '反向', edited: '编辑'}, hasLength(3));
  });

  test('海拔改变会创建新查询；相同节点重建不重复请求', () {
    final a = key([node(30, 0)]);
    final b = key([node(30, 0)]);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(key([node(30, 0, elevation: 1000)])));
  });

  test('真实 family 请求的正反向天气逐节点映射到对应请求坐标', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final provider = WindowProvider();
    final repo = WeatherRepository(
      cache: CacheStore(prefs),
      providers: [provider],
    );
    final container = ProviderContainer(
      overrides: [weatherRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    final weatherQuery = RouteWeatherQuery(
      routeId: query.routeId,
      providerId: 'fake:test',
      mode: query.mode,
      startUtc: query.startUtc,
      endUtc: query.endUtc,
      fixedUtc: query.fixedUtc,
      pace: query.pace,
    );
    final forward = [node(30, 0), node(31, 1000)];
    final reverse = [node(31, 0), node(30, 1000)];
    for (final nodes in [forward, reverse]) {
      final family = detailWeatherProvider(
        DetailFetchKey(nodes: nodes, query: weatherQuery),
      );
      container.listen(family, (_, _) {});
      final bundle = await container.read(family.future);
      for (var i = 0; i < nodes.length; i++) {
        final point = bundle.result.points[bundle.nodeQueryIndex[i]];
        expect(point.provenance.requestLat, nodes[i].pos.latitude);
        expect(point.provenance.requestLon, nodes[i].pos.longitude);
      }
    }
    expect(provider.callCount, 2);
  });

  test('调用方修改原列表不改变已经注册的 family 身份', () {
    final nodes = [node(30, 0), node(31, 1000)];
    final original = key(nodes);
    final hash = original.hashCode;
    nodes.removeLast();
    expect(original.nodes, hasLength(2));
    expect(original.hashCode, hash);
    expect(original, key([node(30, 0), node(31, 1000)]));
  });
}
