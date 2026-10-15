import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/geo.dart';
import 'package:trailweather/data/routes/gpx_import.dart';
import 'package:trailweather/data/routes/kml_import.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/ui/map/route_marks.dart';

/// 向东的直线段：每点相隔约 0.001° 经度（约 85 m @ 40°N）。
List<LatLng> _east(double lat, double lon0, int n) => [
  for (var i = 0; i < n; i++) LatLng(lat, lon0 + i * 0.001),
];

HikingRoute _route(
  List<List<LatLng>> segs, {
  List<RouteWaypoint> wps = const [],
}) {
  final n = segs.fold<int>(0, (a, s) => a + s.length);
  return HikingRoute(
    id: 'r',
    name: '测试线路',
    origin: RouteOrigin.import,
    segments: segs,
    elevationsM: [for (var i = 0; i < n; i++) 1000.0 + i],
    sourceName: 'test',
    waypoints: wps,
  );
}

void main() {
  group('反向行走与环线', () {
    test('reversed 互换起终点，海拔整体倒序，航点不变', () {
      final wp = RouteWaypoint(
        name: '营地',
        point: const LatLng(40, 116.002),
        type: WaypointType.camp,
      );
      final r = _route([_east(40, 116, 3), _east(40, 116.003, 3)], wps: [wp]);
      final rev = r.reversed();
      expect(rev.flatPoints.first, r.flatPoints.last);
      expect(rev.flatPoints.last, r.flatPoints.first);
      expect(rev.elevationsM, r.elevationsM.reversed.toList());
      expect(identical(rev.waypoints.single, wp), isTrue);
      expect(rev.reversed().flatPoints, r.flatPoints);
    });

    test('起终点 200 m 内为环线', () {
      final loop = _route([
        [
          const LatLng(40, 116),
          const LatLng(40.01, 116),
          const LatLng(40.01, 116.01),
          const LatLng(40.0005, 116.0005),
        ],
      ]);
      expect(loop.isLoop, isTrue);
      expect(_route([_east(40, 116, 10)]).isLoop, isFalse);
    });
  });

  group('分析路径：多日轨迹首尾相接的段要串联（五台山 KML 三段间隔 12 m / 34 m）', () {
    test('间隔很小的三段全部串联', () {
      final a = _east(40, 116.000, 5);
      final b = _east(40, 116.0041, 5); // 与 a 末端相距约 9 m
      final c = _east(40, 116.0082, 5);
      final path = _route([a, b, c]).analysisPath;
      expect(path.coversAllSegments, isTrue);
      expect(path.points, hasLength(15));
      expect(path.elevations, hasLength(15));
      expect(path.segmentStartIndices, [0, 5, 10]);
    });

    test('相距超过 1 km 的断开段不串联，取最长链并标记未覆盖', () {
      final a = _east(40, 116.0, 20);
      final far = _east(40.2, 116.0, 5); // 约 22 km 外
      final path = _route([a, far]).analysisPath;
      expect(path.coversAllSegments, isFalse);
      expect(path.points, a);
      expect(path.elevations.first, 1000.0);
    });
  });

  group('航点：吸附、采样与停留时长', () {
    test('航点吸附为节点并带名称；偏离超过 300 m 的不进入时间线', () {
      final pts = _east(40, 116, 40);
      final near = RouteWaypoint(
        name: '休息亭',
        point: const LatLng(40.0002, 116.020),
        type: WaypointType.rest,
        stopMinutes: 30,
      );
      final far = RouteWaypoint(
        name: '远处',
        point: const LatLng(40.05, 116.02),
        type: WaypointType.poi,
      );
      final snapped = snapWaypoints(pts, [near, far]);
      expect(snapped.keys, [20]);
      final nodes = sampleRoute(
        points: pts,
        elevations: List.filled(pts.length, null),
        spacingM: 100000, // 只保留关键点
        waypointsAt: snapped,
      );
      expect(nodes.map((n) => n.label), ['起点', '休息亭', '终点']);
      expect(nodes[1].waypoint, same(near));
    });

    test('休息点停留时长计入之后节点的预计到达时间', () {
      final pts = _east(40, 116, 40);
      final wp = RouteWaypoint(
        name: '午餐',
        point: pts[20],
        type: WaypointType.rest,
        stopMinutes: 45,
      );
      List<DateTime> etas(Map<int, RouteWaypoint> at) => computeEtas(
        nodes: sampleRoute(
          points: pts,
          elevations: List.filled(pts.length, null),
          spacingM: 100000,
          waypointsAt: at,
        ),
        startUtc: DateTime.utc(2026, 10, 18, 0),
      );
      final without = etas({20: wp.copyWith(stopMinutes: 0)});
      final with45 = etas({20: wp});
      expect(with45[1], without[1]); // 到达休息点的时间不变
      expect(with45[2].difference(without[2]), const Duration(minutes: 45));
    });
  });

  group('导入航点：只要有名称的点，跳过起终点与线路同名点', () {
    test('GPX', () {
      final r = GpxImport.parse('''<gpx>
  <wpt lat="40" lon="116.001"><name>东台营地</name><ele>2800</ele></wpt>
  <wpt lat="40" lon="116.002"><ele>2800</ele></wpt>
  <wpt lat="40" lon="116.003"><name>起点</name></wpt>
  <wpt lat="40" lon="116.004"><name><![CDATA[五台山]]></name></wpt>
  <trk><name>五台山</name><trkseg>
    <trkpt lat="40" lon="116"/><trkpt lat="40" lon="116.01"/>
  </trkseg></trk>
</gpx>''');
      expect(r.waypoints.map((w) => w.name), ['东台营地']);
      expect(r.waypoints.single.type, WaypointType.camp);
      expect(r.waypoints.single.elevationM, 2800);
      expect(GpxImport.toRoute(r, fileName: 'a.gpx').waypoints, hasLength(1));
    });

    test('只有 wpt 没有轨迹时，wpt 合成路线而不重复作为航点', () {
      final r = GpxImport.parse('''<gpx>
  <wpt lat="40" lon="116"><name>A</name></wpt>
  <wpt lat="40" lon="116.01"><name>B</name></wpt>
</gpx>''');
      expect(r.segments, hasLength(1));
      expect(r.waypoints, isEmpty);
    });

    test('KML Point 地标', () {
      final r = KmlImport.parse('''<kml><Document><name>2026 五台山</name>
  <Placemark><name><![CDATA[起点]]></name><Point><coordinates>116,40,2500</coordinates></Point></Placemark>
  <Placemark><name>北台取水点</name><Point><coordinates>116.005, 40, 3000</coordinates></Point></Placemark>
  <Placemark><name>轨迹</name><LineString><coordinates>116,40 116.01,40</coordinates></LineString></Placemark>
</Document></kml>''');
      expect(r.waypoints.map((w) => w.name), ['北台取水点']);
      expect(r.waypoints.single.type, WaypointType.water);
      expect(r.waypoints.single.point, const LatLng(40, 116.005));
    });

    test('名称推断类型', () {
      expect(inferWaypointType('二号营地'), WaypointType.camp);
      expect(inferWaypointType('补给小卖部'), WaypointType.supply);
      expect(inferWaypointType('午餐休息'), WaypointType.rest);
      expect(inferWaypointType('北台'), WaypointType.pass);
      expect(inferWaypointType('查票点'), WaypointType.poi);
    });

    test('航点 JSON 往返保留停留时长与新类型', () {
      const w = RouteWaypoint(
        name: '补给',
        point: LatLng(40, 116),
        type: WaypointType.supply,
        stopMinutes: 20,
      );
      final back = RouteWaypoint.fromJson(w.toJson());
      expect(back.type, WaypointType.supply);
      expect(back.stopMinutes, 20);
    });
  });

  group('方向箭头', () {
    test('向东线路：箭头数量正确、方位约 90°、按里程等分', () {
      final marks = routeDirectionMarks([_east(40, 116, 50)], count: 4);
      expect(marks, hasLength(4));
      for (final (_, bearing) in marks) {
        expect(bearing, closeTo(90, 1));
      }
      expect(marks.first.$1.longitude, lessThan(marks.last.$1.longitude));
    });

    test('bearingDeg 正北为 0', () {
      expect(
        Geo.bearingDeg(const LatLng(40, 116), const LatLng(40.1, 116)),
        closeTo(0, 0.01),
      );
    });
  });
}
