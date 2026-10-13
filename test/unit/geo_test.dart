import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/geo.dart';

void main() {
  group('Geo.distanceM', () {
    test('同一坐标距离为 0', () {
      expect(Geo.distanceM(const LatLng(30, 120), const LatLng(30, 120)), 0);
    });

    test('经度 1° 在赤道约 111 km', () {
      final d = Geo.distanceM(const LatLng(0, 0), const LatLng(0, 1));
      expect(d, closeTo(111195, 500));
    });

    test('纬度 1° 约 111 km', () {
      final d = Geo.distanceM(const LatLng(0, 0), const LatLng(1, 0));
      expect(d, closeTo(110575, 500));
    });
  });

  group('Geo.cumulativeDistancesM', () {
    test('首元素为 0，单调递增', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 0.01),
        const LatLng(0, 0.02),
      ];
      final cum = Geo.cumulativeDistancesM(pts);
      expect(cum[0], 0);
      expect(cum[1], greaterThan(1000));
      expect(cum[2], greaterThan(cum[1]));
    });
  });

  group('Geo.simplify', () {
    test('保留端点并移除共线中间点', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0, 0.001),
        const LatLng(0, 0.002),
      ];
      final out = Geo.simplify(pts, 50);
      expect(out.length, 2);
      expect(out.first, pts.first);
      expect(out.last, pts.last);
    });

    test('保留偏离点', () {
      final pts = [
        const LatLng(0, 0),
        const LatLng(0.01, 0.01),
        const LatLng(0, 0.02),
      ];
      final out = Geo.simplify(pts, 100);
      expect(out.length, 3);
    });
  });

  group('Geo.totalAscentM', () {
    test('只累计上升', () {
      expect(Geo.totalAscentM([100, 200, 150, 300]), 350.0);
    });

    test('任一海拔缺失返回 null（不编造）', () {
      expect(Geo.totalAscentM([100, null, 300]), isNull);
    });

    test('空保护', () {
      expect(Geo.totalAscentM([null]), isNull);
    });
  });
}
