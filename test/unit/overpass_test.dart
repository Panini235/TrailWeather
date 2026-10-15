import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/overpass.dart';

void main() {
  group('assembleSegments', () {
    test('顺序 way 直接连接', () {
      final segs = OverpassRouteSource.assembleSegments([
        [const LatLng(0, 0), const LatLng(0, 0.001)],
        [const LatLng(0, 0.001), const LatLng(0, 0.002)],
      ]);
      expect(segs, hasLength(1));
      expect(segs.first, hasLength(3));
    });

    test('乱序 way 贪心连接（含反转）', () {
      final segs = OverpassRouteSource.assembleSegments([
        [const LatLng(0, 0.001), const LatLng(0, 0.002)], // 在前
        [const LatLng(0, 0.001), const LatLng(0, 0.0)], // 需反转接前段
      ]);
      expect(segs, hasLength(1));
      expect(segs.first, hasLength(3)); // 连成一整段
      // 端点集合覆盖两条 way 的全部端点
      final pts = segs.first.toSet();
      expect(pts, contains(const LatLng(0, 0.0)));
      expect(pts, contains(const LatLng(0, 0.002)));
    });

    test('不共享端点的 way 独立成段，绝不连直线', () {
      final segs = OverpassRouteSource.assembleSegments([
        [const LatLng(0, 0), const LatLng(0, 0.001)],
        [const LatLng(1, 1), const LatLng(1, 1.001)], // 完全不相连
      ]);
      expect(segs, hasLength(2));
    });

    test('近似共享但不相等的端点视为不连通', () {
      final segs = OverpassRouteSource.assembleSegments([
        [const LatLng(0, 0), const LatLng(0, 0.001000)],
        [const LatLng(0, 0.001001), const LatLng(0, 0.002)],
      ]);
      expect(segs, hasLength(2)); // 端点不同（1e-6 度差异）→ 不合并
    });
  });

  group('bboxAllowed', () {
    final src = OverpassRouteSource();
    test('小 bbox 允许', () {
      expect(src.bboxAllowed(39.96, 116.10, 40.05, 116.25), isTrue);
    });

    test('过大 bbox 拒绝（不执行全球抓取）', () {
      expect(src.bboxAllowed(-80, -170, 80, 170), isFalse);
      expect(src.bboxAllowed(0, 0, 2, 2), isFalse); // 超过 0.6 跨度
    });

    test('倒置 bbox 拒绝', () {
      expect(src.bboxAllowed(40, 116, 39, 117), isFalse);
    });
  });

  group('parseResponse', () {
    test('解析 relation（含 tags 与多 way 几何）', () {
      const body = '''
{
  "elements": [
    {
      "type": "relation",
      "id": 12345,
      "tags": {"name": "香山防火道", "route": "hiking", "distance": "12 km"},
      "members": [
        {"type": "way", "role": "", "geometry": [
          {"lat": 39.99, "lon": 116.18}, {"lat": 39.99, "lon": 116.19}
        ]},
        {"type": "way", "role": "", "geometry": [
          {"lat": 39.99, "lon": 116.19}, {"lat": 40.00, "lon": 116.20}
        ]},
        {"type": "node", "role": "sign", "geometry": [{"lat": 39.99, "lon": 116.185}]}
      ]
    }
  ]
}
''';
      final routes = OverpassRouteSource().parseResponse(body);
      expect(routes, hasLength(1));
      final r = routes.first;
      expect(r.name, '香山防火道');
      expect(r.osmId, 12345);
      expect(r.origin.name, 'osm');
      expect(r.segments, hasLength(1)); // 两个 way 首尾相接 → 1 段
      expect(r.flatPoints, hasLength(3));
      expect(r.sourceLicense, 'ODbL 1.0');
      expect(r.elevationsM.every((e) => e == null), isTrue); // 无海拔→未知，不编造
      expect(r.sourceName, contains('OpenStreetMap'));
    });

    test('解析具名 way 为路径段而非完整徒步路线', () {
      const body = '''
{
  "elements": [
    {
      "type": "way",
      "id": 67890,
      "tags": {"name": "龙脊步道", "highway": "path"},
      "geometry": [
        {"lat": 30.10, "lon": 120.10},
        {"lat": 30.11, "lon": 120.11}
      ]
    }
  ]
}
''';
      final routes = OverpassRouteSource().parseResponse(body);
      expect(routes, hasLength(1));
      final route = routes.single;
      expect(route.id, 'osm-w67890');
      expect(route.origin.name, 'osmPath');
      expect(route.sourceName, contains('不是完整规划路线'));
      expect(route.sourceUrl, 'https://www.openstreetmap.org/way/67890');
      expect(route.elevationsM.every((e) => e == null), isTrue);
    });

    test('非 relation/way 元素跳过', () {
      const body = '''
{"elements": [{"type": "node", "id": 1, "lat": 1, "lon": 1}]}
''';
      expect(OverpassRouteSource().parseResponse(body), isEmpty);
    });

    test('损坏响应抛 OverpassException', () {
      expect(
        () => OverpassRouteSource().parseResponse('<html>504</html>'),
        throwsA(isA<OverpassException>()),
      );
    });
  });
}
