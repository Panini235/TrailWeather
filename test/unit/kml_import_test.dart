import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/kml_import.dart';

void main() {
  group('KmlImport', () {
    test('解析标准 KML LineString（含高程）', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>测试线路</name>
    <Placemark>
      <name>轨迹段1</name>
      <LineString>
        <coordinates>
          120.0,30.0,100 120.001,30.001,150 120.002,30.002,200
        </coordinates>
      </LineString>
    </Placemark>
  </Document>
</kml>''';

      final r = KmlImport.parse(kml);
      expect(r.segments, hasLength(1));
      expect(r.segments.first, hasLength(3));
      expect(r.segments.first[0], const LatLng(30.0, 120.0));
      expect(r.elevations[1], 150.0);
      expect(r.extractedName, '测试线路');
    });

    test('解析 MultiGeometry 多线段', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml>
  <Placemark>
    <name>多段线</name>
    <MultiGeometry>
      <LineString>
        <coordinates>120.0,30.0 120.001,30.001</coordinates>
      </LineString>
      <LineString>
        <coordinates>120.01,30.01 120.011,30.011</coordinates>
      </LineString>
    </MultiGeometry>
  </Placemark>
</kml>''';

      final r = KmlImport.parse(kml);
      expect(r.segments, hasLength(2));
      expect(r.segments[0], hasLength(2));
      expect(r.segments[1], hasLength(2));
    });

    test('解析 gx:Track 轨迹', () {
      const kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Placemark>
    <name>奥维导出轨迹</name>
    <gx:Track>
      <when>2026-10-14T08:00:00Z</when>
      <gx:coord>120.1 30.1 500</gx:coord>
      <when>2026-10-14T08:01:00Z</when>
      <gx:coord>120.101 30.101 550</gx:coord>
    </gx:Track>
  </Placemark>
</kml>''';

      final r = KmlImport.parse(kml);
      expect(r.segments, hasLength(1));
      expect(r.segments.first, hasLength(2));
      expect(r.elevations[0], 500.0);
      expect(r.elevations[1], 550.0);
    });

    test('异常海拔数据自动置空并保留警告', () {
      const kml = '''<kml><Placemark><LineString><coordinates>
120.0,30.0,99999 120.001,30.001,800
</coordinates></LineString></Placemark></kml>''';

      final r = KmlImport.parse(kml);
      expect(r.segments.first, hasLength(2));
      expect(r.elevations[0], isNull);
      expect(r.elevations[1], 800.0);
      expect(r.warnings.any((w) => w.contains('异常海拔')), isTrue);
    });

    test('超过阈值点数触发自适应抽稀', () {
      final buf = StringBuffer('<kml><Placemark><LineString><coordinates>');
      for (var i = 0; i < 3500; i++) {
        buf.write('${120 + i * 0.0001},${30 + i * 0.0001},${200 + i % 100} ');
      }
      buf.write('</coordinates></LineString></Placemark></kml>');

      final r = KmlImport.parse(buf.toString());
      final total = r.segments.fold<int>(0, (a, s) => a + s.length);
      expect(total, lessThanOrEqualTo(3000));
      expect(r.warnings.any((w) => w.contains('自适应优化')), isTrue);
    });

    test('拒绝非 KML 根元素', () {
      expect(
        () => KmlImport.parse('<gpx></gpx>'),
        throwsA(isA<KmlImportException>()),
      );
    });
  });
}
