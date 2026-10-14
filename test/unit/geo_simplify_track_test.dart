import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/geo.dart';

void main() {
  group('Geo.simplifyTrack', () {
    test('点数少于目标上限时保持原样', () {
      final pts = [
        const LatLng(30.0, 120.0),
        const LatLng(30.001, 120.001),
        const LatLng(30.002, 120.002),
      ];
      final eles = [100.0, 150.0, 120.0];

      final (outPts, outEles) = Geo.simplifyTrack(
        pts,
        eles,
        targetMaxPoints: 100,
      );
      expect(outPts, hasLength(3));
      expect(outEles, hasLength(3));
      expect(outPts[1], const LatLng(30.001, 120.001));
      expect(outEles[1], 150.0);
    });

    test('点数过大时抽稀至目标点数以内，且点数与高程严格 1:1', () {
      final pts = <LatLng>[];
      final eles = <double?>[];

      for (var i = 0; i < 4000; i++) {
        pts.add(
          LatLng(30.0 + i * 0.0001, 120.0 + (i % 2 == 0 ? 0.00005 : -0.00005)),
        );
        eles.add(200.0 + (i % 100));
      }

      final (outPts, outEles) = Geo.simplifyTrack(
        pts,
        eles,
        targetMaxPoints: 500,
      );
      expect(outPts.length, lessThanOrEqualTo(500));
      expect(outEles.length, outPts.length);
      expect(outPts.first, pts.first);
      expect(outPts.last, pts.last);
      expect(outEles.first, eles.first);
      expect(outEles.last, eles.last);
    });

    test('必须强制保留最高点与最低点', () {
      final pts = <LatLng>[];
      final eles = <double?>[];

      for (var i = 0; i < 2000; i++) {
        pts.add(LatLng(30.0 + i * 0.0001, 120.0));
        if (i == 450) {
          eles.add(8848.0); // 珠峰最高点
        } else if (i == 1200) {
          eles.add(-154.0); // 吐鲁番最低点
        } else {
          eles.add(500.0);
        }
      }

      final (outPts, outEles) = Geo.simplifyTrack(
        pts,
        eles,
        targetMaxPoints: 100,
      );
      expect(outEles.contains(8848.0), isTrue);
      expect(outEles.contains(-154.0), isTrue);
    });
  });
}
