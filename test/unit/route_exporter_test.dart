import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/gpx_import.dart';
import 'package:trailweather/data/routes/kml_import.dart';
import 'package:trailweather/data/routes/route_exporter.dart';
import 'package:trailweather/data/routes/route_models.dart';

void main() {
  group('RouteExporter & Roundtrip Import', () {
    final sampleRoute = HikingRoute(
      id: 'test-planned-1',
      name: '香山后山至八大处经典环线',
      origin: RouteOrigin.planned,
      segments: [
        [
          const LatLng(39.991, 116.191),
          const LatLng(39.992, 116.192),
          const LatLng(39.993, 116.193),
        ],
      ],
      elevationsM: [300.0, 450.0, 520.0],
      sourceName: '手绘规划',
      description: '适合周末轻装徒步，沿途有泉水补给',
      waypoints: [
        const RouteWaypoint(
          name: '好汉坡营地',
          point: LatLng(39.992, 116.192),
          type: WaypointType.camp,
          desc: '平整林间空地',
          elevationM: 450.0,
        ),
      ],
    );

    test('导出标准 GPX 并成功往返解析', () {
      final gpx = RouteExporter.toGpx(sampleRoute);
      expect(gpx.contains('<gpx'), isTrue);
      expect(gpx.contains('香山后山至八大处经典环线'), isTrue);
      expect(gpx.contains('好汉坡营地'), isTrue);

      final parsed = GpxImport.parse(gpx);
      expect(parsed.segments, hasLength(1));
      expect(parsed.segments.first, hasLength(3));
      expect(parsed.elevations[1], 450.0);
    });

    test('导出标准 KML 并成功往返解析', () {
      final kml = RouteExporter.toKml(sampleRoute);
      expect(kml.contains('<kml'), isTrue);
      expect(kml.contains('<LineString>'), isTrue);
      expect(kml.contains('好汉坡营地'), isTrue);

      final parsed = KmlImport.parse(kml);
      expect(parsed.segments, hasLength(1));
      expect(parsed.segments.first, hasLength(3));
      expect(parsed.elevations[1], 450.0);
      expect(parsed.extractedName, '香山后山至八大处经典环线');
    });
  });
}
