import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/gcj02.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/ui/map/basemap.dart';
import 'package:trailweather/ui/map/route_camera.dart';

HikingRoute _route(List<List<LatLng>> segments) => HikingRoute(
  id: 'r',
  name: 'r',
  origin: RouteOrigin.import,
  segments: segments,
  elevationsM: [
    for (final s in segments)
      for (final _ in s) null,
  ],
  sourceName: 'test',
);

void main() {
  final osm = Basemap.base('osm');
  final amap = Basemap.base('amap');

  group('routeDisplayBounds', () {
    test('覆盖全部几何段，而不只是最长段', () {
      final route = _route(const [
        [LatLng(30.0, 120.0), LatLng(30.1, 120.1), LatLng(30.2, 120.2)],
        [LatLng(29.5, 121.0), LatLng(29.6, 121.1)],
      ]);
      final b = routeDisplayBounds(route, osm)!;
      expect(b.south, closeTo(29.5, 1e-9));
      expect(b.north, closeTo(30.2, 1e-9));
      expect(b.west, closeTo(120.0, 1e-9));
      expect(b.east, closeTo(121.1, 1e-9));
    });

    test('GCJ-02 底图先转换到显示坐标再取包围盒', () {
      const a = LatLng(30.0, 120.0);
      const c = LatLng(30.2, 120.3);
      final route = _route(const [
        [a, c],
      ]);
      final b = routeDisplayBounds(route, amap)!;
      final da = Gcj02.wgs84ToGcj02(a);
      final dc = Gcj02.wgs84ToGcj02(c);
      expect(b.south, closeTo(da.latitude, 1e-9));
      expect(b.west, closeTo(da.longitude, 1e-9));
      expect(b.north, closeTo(dc.latitude, 1e-9));
      expect(b.east, closeTo(dc.longitude, 1e-9));
      // 偏移真实存在，不能直接用 WGS-84 包围盒。
      expect((b.south - a.latitude).abs(), greaterThan(1e-4));
    });

    test('单点线路扩展为非零包围盒，避免无穷缩放', () {
      final route = _route(const [
        [LatLng(30.0, 120.0)],
      ]);
      final b = routeDisplayBounds(route, osm)!;
      expect(b.north - b.south, greaterThan(0));
      expect(b.east - b.west, greaterThan(0));
      expect(b.contains(const LatLng(30.0, 120.0)), isTrue);
    });

    test('无几何返回 null', () {
      expect(routeDisplayBounds(_route(const [[]]), osm), isNull);
      expect(routeCameraFit(_route(const [[]]), osm), isNull);
    });
  });
}
