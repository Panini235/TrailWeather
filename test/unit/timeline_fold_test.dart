import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/offline/offline_trip.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/ui/detail/detail_state.dart';

/// 向东的直线段：每点相隔约 0.001° 经度（约 85 m @ 40°N）。
List<LatLng> _east(int n) => [
  for (var i = 0; i < n; i++) LatLng(40, 116 + i * 0.001),
];

RouteWaypoint _wp(String name, LatLng at, WaypointType type, {int? stop}) =>
    RouteWaypoint(name: name, point: at, type: type, stopMinutes: stop);

NodeWxRow _row(
  int i, {
  String? label,
  bool shared = true,
  int hour = 8,
  int minute = 0,
}) => NodeWxRow(
  node: RouteNode(
    pointIndex: i,
    pos: LatLng(40, 116 + i * 0.01),
    elevationM: null,
    distFromStartM: i * 1500.0,
    label: label,
  ),
  validUtc: DateTime.utc(2026, 10, 18, hour, minute),
  point: null,
  sharedWithPrev: shared,
);

/// 条目形状：“展示下标:[折叠下标]”。
List<String> _shape(List<TimelineEntry> t) => [
  for (final e in t) '${e.index}:${e.folded}',
];

void main() {
  group('航点分级：关键航点是节点，普通航点挂到最近的节点', () {
    test('营地是独立节点；打卡点、水源不占节点，按沿线距离归到最近节点', () {
      final pts = _east(41);
      final camp = _wp('二号营地', pts[30], WaypointType.camp);
      final view = _wp('观景台', pts[12], WaypointType.poi);
      final water = _wp('溪水', pts[3], WaypointType.water);
      final nodes = sampleRoute(
        points: pts,
        elevations: List.filled(pts.length, null),
        spacingM: 100000, // 只保留关键点
        waypointsAt: {30: camp, 12: view, 3: water},
      );
      expect(nodes.map((n) => n.label), ['起点', '二号营地', '终点']);
      expect(nodes[1].waypoint, same(camp));
      // 下标 12 离起点（0）比离营地（30）近。
      expect(nodes[0].nearbyWaypoints.map((w) => w.name), ['溪水', '观景台']);
      expect(nodes[1].nearbyWaypoints, isEmpty);
      expect(nodes[2].nearbyWaypoints, isEmpty);
    });

    test('设了停留时长的普通航点仍是独立节点（停留计入到达时间）', () {
      final pts = _east(41);
      final shop = _wp('小卖部', pts[20], WaypointType.supply, stop: 20);
      final nodes = sampleRoute(
        points: pts,
        elevations: List.filled(pts.length, null),
        spacingM: 100000,
        waypointsAt: {20: shop},
      );
      expect(nodes.map((n) => n.label), ['起点', '小卖部', '终点']);
      final etas = computeEtas(
        nodes: nodes,
        startUtc: DateTime.utc(2026, 10, 18),
      );
      final plain = computeEtas(
        nodes: sampleRoute(
          points: pts,
          elevations: List.filled(pts.length, null),
          spacingM: 100000,
          waypointsAt: {20: shop.copyWith(stopMinutes: 0)},
        ),
        startUtc: DateTime.utc(2026, 10, 18),
      );
      expect(etas.last.difference(plain.last), const Duration(minutes: 20));
    });

    test('大量普通航点不突破节点上限，也不会丢', () {
      final pts = _east(401); // 约 34 km
      final marks = {
        for (var i = 1; i < 400; i += 2)
          i: _wp('岔路 $i', pts[i], WaypointType.poi),
      };
      final nodes = sampleRoute(
        points: pts,
        elevations: List.filled(pts.length, null),
        maxNodes: 12,
        waypointsAt: marks,
      );
      expect(nodes.length, lessThanOrEqualTo(12));
      expect(nodes.every((n) => n.waypoint == null), isTrue);
      expect(
        nodes.fold<int>(0, (a, n) => a + n.nearbyWaypoints.length),
        marks.length,
      );
    });

    test('分级规则', () {
      const at = LatLng(40, 116);
      for (final t in [
        WaypointType.camp,
        WaypointType.pass,
        WaypointType.danger,
        WaypointType.exit,
        WaypointType.rest,
      ]) {
        expect(isKeyWaypoint(_wp('x', at, t)), isTrue, reason: t.name);
      }
      for (final t in [
        WaypointType.poi,
        WaypointType.water,
        WaypointType.supply,
      ]) {
        expect(isKeyWaypoint(_wp('x', at, t)), isFalse, reason: t.name);
        expect(isKeyWaypoint(_wp('x', at, t, stop: 10)), isTrue);
      }
    });

    test('离线包保存挂在节点上的普通航点；旧包没有该字段也能读', () {
      final pts = _east(41);
      final nodes = sampleRoute(
        points: pts,
        elevations: List.filled(pts.length, null),
        spacingM: 100000,
        waypointsAt: {12: _wp('观景台', pts[12], WaypointType.poi)},
      );
      final plan = OfflineTripPlan(
        route: HikingRoute(
          id: 'o',
          name: '离线',
          origin: RouteOrigin.import,
          segments: [pts],
          elevationsM: List.filled(pts.length, null),
          sourceName: 'test',
        ),
        nodes: nodes,
        nodeTimesUtc: [for (final _ in nodes) DateTime.utc(2026, 10, 18, 8)],
        mode: OfflineTimeMode.fixed,
        reversed: false,
        selectedTimeUtc: DateTime.utc(2026, 10, 18, 8),
        pace: PaceConfig.defaults,
        startUtc: DateTime.utc(2026, 10, 18, 8),
        endUtc: DateTime.utc(2026, 10, 18, 9),
      );
      final json = plan.toJson();
      final back = OfflineTripPlan.fromJson(json);
      expect(back.nodes.first.nearbyWaypoints.single.name, '观景台');
      expect(back.nodes.last.nearbyWaypoints, isEmpty);

      for (final n in json['nodes'] as List) {
        (n as Map<String, dynamic>).remove('nearby');
      }
      expect(OfflineTripPlan.fromJson(json).nodes.first.nearbyWaypoints, []);
    });
  });

  group('时间线折叠：只折叠同一网格、同一小时的普通节点', () {
    test('固定时刻：同网格的普通节点收进上一条；起终点不折叠', () {
      final rows = [
        _row(0, label: '起点', shared: false),
        _row(1),
        _row(2),
        _row(3, shared: false), // 进入新网格
        _row(4),
        _row(5, label: '终点'),
      ];
      expect(_shape(foldTimeline(rows)), ['0:[1, 2]', '3:[4]', '5:[]']);
    });

    test('行程模式：同网格但到达小时不同的节点不折叠', () {
      final rows = [
        _row(0, label: '起点', shared: false, hour: 8, minute: 0),
        _row(1, hour: 8, minute: 25),
        _row(2, hour: 8, minute: 50),
        _row(3, hour: 9, minute: 15),
        _row(4, hour: 9, minute: 40),
        _row(5, label: '终点', hour: 10, minute: 5),
      ];
      expect(sameForecastAsPrev(rows, 3), isFalse);
      expect(_shape(foldTimeline(rows)), ['0:[1, 2]', '3:[4]', '5:[]']);
    });

    test('中间的营地不折叠，之后相同的普通节点收进营地这一条', () {
      final rows = [
        _row(0, label: '起点', shared: false),
        _row(1),
        _row(2, label: '营地'),
        _row(3),
        _row(4, label: '终点'),
      ];
      expect(_shape(foldTimeline(rows)), ['0:[1]', '2:[3]', '4:[]']);
    });

    test('数据未到（不知道是否同网格）时不折叠', () {
      final rows = [for (var i = 0; i < 4; i++) _row(i, shared: false)];
      expect(foldTimeline(rows).every((e) => e.folded.isEmpty), isTrue);
    });
  });
}
