import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/gcj02.dart';

double _distMLatLng(LatLng a, LatLng b) {
  final midLat = (a.latitude + b.latitude) / 2;
  final dLat = (a.latitude - b.latitude) * 111320;
  final dLon =
      (a.longitude - b.longitude) * 111320 * math.cos(midLat * math.pi / 180);
  return math.sqrt(dLat * dLat + dLon * dLon);
}

void main() {
  group('Gcj02 坐标转换', () {
    test('境外坐标恒等返回（不转换）', () {
      const london = LatLng(51.5074, -0.1278);
      expect(Gcj02.wgs84ToGcj02(london), london);
      expect(Gcj02.gcj02ToWgs84(london), london);
      const tokyo = LatLng(35.6762, 139.6503);
      expect(Gcj02.outOfChina(tokyo.latitude, tokyo.longitude), isTrue);
    });

    test('境内坐标存在偏移且量级合理（约 100–700 m）', () {
      const wgs = LatLng(39.9903, 116.1826); // 北京香山附近
      final gcj = Gcj02.wgs84ToGcj02(wgs);
      expect(gcj, isNot(wgs));
      final dist = _distMLatLng(wgs, gcj);
      expect(dist, greaterThan(50));
      expect(dist, lessThan(800));
    });

    test('往返转换误差 < 2 m（迭代逆变换）', () {
      for (final wgs in const [
        LatLng(39.9903, 116.1826), // 北京
        LatLng(30.2345, 120.1234), // 杭州
        LatLng(22.5400, 114.4600), // 深圳
        LatLng(31.2304, 121.4737), // 上海
        LatLng(25.03, 102.72), // 昆明
      ]) {
        final back = Gcj02.gcj02ToWgs84(Gcj02.wgs84ToGcj02(wgs));
        final dist = _distMLatLng(wgs, back);
        expect(dist, lessThan(2), reason: 'wgs=$wgs back=$back 往返偏差 $dist m');
      }
    });

    test('已知参考点：天安门 WGS84→GCJ02 与公开参考值接近', () {
      // 公开参考值（业内常用示例）：WGS84 (39.90733345, 116.39122885)
      // → GCJ02 约 (39.90874462, 116.39749953)。近似算法允许小差异。
      const wgs = LatLng(39.90733345, 116.39122885);
      final gcj = Gcj02.wgs84ToGcj02(wgs);
      expect(gcj.latitude, closeTo(39.90874462, 0.0005));
      expect(gcj.longitude, closeTo(116.39749953, 0.0008));
    });
  });
}
