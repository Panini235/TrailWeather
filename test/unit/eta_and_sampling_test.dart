import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/eta.dart';

RouteNode _node(double distKm, double? ele, {String? label, int idx = 0}) =>
    RouteNode(
      pointIndex: idx,
      pos: LatLng(0, distKm / 111),
      elevationM: ele,
      distFromStartM: distKm * 1000,
      label: label,
    );

void main() {
  group('computeEtas', () {
    test('平地 4 km/h 无爬升无休息', () {
      final nodes = [_node(0, 100), _node(2, 100), _node(4, 100)];
      final start = DateTime.utc(2026, 10, 13, 22, 0); // 跨午夜场景起点
      final etas = computeEtas(
        nodes: nodes,
        startUtc: start,
        pace: const PaceConfig(
          speedKmh: 4,
          ascentMinPer100m: 0,
          descentMinPer100m: 0,
        ),
      );
      expect(etas.length, 3);
      expect(etas[0], start);
      expect(etas[1], start.add(const Duration(minutes: 30)));
      expect(etas[2], start.add(const Duration(minutes: 60)));
      // 跨午夜：22:00 + 60min = 次日 23:00? 不：22:00+1h=23:00 同日；改断言
      expect(etas[2].day, 13);
    });

    test('跨午夜正确', () {
      final nodes = [_node(0, 0), _node(4, 0)];
      final start = DateTime.utc(2026, 10, 13, 23, 30);
      final etas = computeEtas(
        nodes: nodes,
        startUtc: start,
        pace: const PaceConfig(
          speedKmh: 4,
          ascentMinPer100m: 0,
          descentMinPer100m: 0,
        ),
      );
      expect(etas[1], DateTime.utc(2026, 10, 14, 0, 30));
      expect(etas[1].day, 14);
    });

    test('爬升加时', () {
      final nodes = [_node(0, 0), _node(1, 200)]; // 1km + 200m 上升
      final etas = computeEtas(
        nodes: nodes,
        startUtc: DateTime.utc(2026, 1, 1),
        pace: const PaceConfig(
          speedKmh: 6,
          ascentMinPer100m: 12,
          descentMinPer100m: 6,
        ),
      );
      // 1km/6km/h = 10min + 2*12min = 34min
      expect(etas[1].difference(etas[0]).inMinutes, 34);
    });

    test('海拔缺失不计爬升加时', () {
      final nodes = [_node(0, null), _node(1, null)];
      final etas = computeEtas(
        nodes: nodes,
        startUtc: DateTime.utc(2026, 1, 1),
        pace: const PaceConfig(
          speedKmh: 6,
          ascentMinPer100m: 60,
          descentMinPer100m: 30,
        ),
      );
      expect(etas[1].difference(etas[0]).inMinutes, 10);
    });

    test('休息按距离比例分摊', () {
      final nodes = [_node(0, 0), _node(5, 0), _node(10, 0)];
      final etas = computeEtas(
        nodes: nodes,
        startUtc: DateTime.utc(2026, 1, 1),
        pace: const PaceConfig(
          speedKmh: 10,
          ascentMinPer100m: 0,
          descentMinPer100m: 0,
          restMinutesTotal: 60,
        ),
      );
      // 每段 30min 步行 + 30min 分摊休息
      expect(etas[1].difference(etas[0]).inMinutes, 60);
      expect(etas[2].difference(etas[0]).inMinutes, 120);
    });
  });

  group('sampleRoute', () {
    List<LatLng> line(int n, {double stepDeg = 0.01}) => [
      for (var i = 0; i < n; i++) LatLng(0, i * stepDeg),
    ];

    test('起终点必含', () {
      final pts = line(50);
      final eles = List<double?>.filled(50, 100);
      final nodes = sampleRoute(
        points: pts,
        elevations: eles,
        spacingM: 1500,
        maxNodes: 24,
      );
      expect(nodes.first.pointIndex, 0);
      expect(nodes.last.pointIndex, 49);
      expect(nodes.first.label, '起点');
      expect(nodes.last.label, '终点');
    });

    test('高点必含并标注', () {
      final pts = line(50);
      final eles = List<double?>.filled(50, 100.0);
      eles[25] = 900;
      final nodes = sampleRoute(
        points: pts,
        elevations: eles,
        spacingM: 1500,
        maxNodes: 24,
      );
      final high = nodes.where((n) => n.label == '高点').toList();
      expect(high, isNotEmpty);
      expect(high.first.pointIndex, 25);
    });

    test('maxNodes 上限生效且保留关键点', () {
      final pts = line(500);
      final eles = List<double?>.filled(500, 10.0);
      eles[300] = 999;
      final nodes = sampleRoute(
        points: pts,
        elevations: eles,
        spacingM: 200,
        maxNodes: 10,
      );
      expect(nodes.length, lessThanOrEqualTo(10));
      expect(nodes.first.pointIndex, 0);
      expect(nodes.last.pointIndex, 499);
      expect(nodes.any((n) => n.pointIndex == 300), isTrue);
    });

    test('空保护', () {
      expect(
        sampleRoute(
          points: const [],
          elevations: const [],
          spacingM: 1500,
          maxNodes: 5,
        ),
        isEmpty,
      );
    });
  });
}
