import 'package:flutter_test/flutter_test.dart';
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
