import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/routes/geojson_import.dart';
import 'package:trailweather/data/routes/gpx_import.dart';

void main() {
  group('CacheStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('写入后可读取，TTL 过期可感知', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheStore(prefs);
      await cache.write(CacheNs.weather, 'k', 'v1', const Duration(minutes: 30));
      final hit = await cache.read(CacheNs.weather, 'k');
      expect(hit, isNotNull);
      expect(hit!.payload, 'v1');
      expect(hit.isExpired, isFalse);

      await cache.write(CacheNs.weather, 'k2', 'v2', Duration.zero);
      final expired = await cache.read(CacheNs.weather, 'k2');
      expect(expired, isNotNull); // stale-while-revalidate：仍可读
      expect(expired!.isExpired, isTrue);
    });

    test('命名空间隔离与清除', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheStore(prefs);
      await cache.write(CacheNs.weather, 'a', '1', const Duration(hours: 1));
      await cache.write(CacheNs.routes, 'a', '2', const Duration(hours: 1));
      expect(await cache.entryCount(CacheNs.weather), 1);
      expect(await cache.entryCount(CacheNs.routes), 1);
      await cache.clearNamespace(CacheNs.weather);
      expect(await cache.entryCount(CacheNs.weather), 0);
      expect(await cache.entryCount(CacheNs.routes), 1);
    });

    test('LRU 超限淘汰', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheStore(prefs, maxEntriesPerNamespace: 3);
      for (var i = 0; i < 5; i++) {
        await cache.write(CacheNs.weather, 'k$i', 'v$i', const Duration(hours: 1));
      }
      expect(await cache.entryCount(CacheNs.weather), lessThanOrEqualTo(3));
    });

    test('缓存键版本字段存在于 weather repo（间接行为在 repo 测试覆盖）', () async {
      final prefs = await SharedPreferences.getInstance();
      final cache = CacheStore(prefs);
      await cache.write('ns', 'key', '{}', const Duration(minutes: 1));
      expect(cache.approxSizeBytes('ns'), greaterThan(0));
    });
  });

  group('GpxImport', () {
    test('解析正常轨迹（含海拔）', () {
      const gpx = '''
<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="t">
  <trk><name>测试</name>
    <trkseg>
      <trkpt lat="30.0" lon="120.0"><ele>100</ele></trkpt>
      <trkpt lat="30.001" lon="120.001"><ele>110</ele></trkpt>
      <trkpt lat="30.002" lon="120.002"><ele>90</ele></trkpt>
    </trkseg>
  </trk>
</gpx>
''';
      final r = GpxImport.parse(gpx);
      expect(r.segments, hasLength(1));
      expect(r.segments.first, hasLength(3));
      expect(r.elevations[1], 110);
    });

    test('多个 trkseg 分段', () {
      const gpx = '''
<gpx version="1.1">
  <trk>
    <trkseg>
      <trkpt lat="1" lon="1"/><trkpt lat="1.001" lon="1"/>
    </trkseg>
    <trkseg>
      <trkpt lat="2" lon="2"/><trkpt lat="2.001" lon="2"/>
    </trkseg>
  </trk>
</gpx>
''';
      final r = GpxImport.parse(gpx);
      expect(r.segments, hasLength(2));
    });

    test('拒绝非 GPX 根元素', () {
      expect(() => GpxImport.parse('<foo><bar/></foo>'),
          throwsA(isA<GpxImportException>()));
    });

    test('拒绝损坏 XML', () {
      expect(() => GpxImport.parse('<gpx><unclosed>'),
          throwsA(isA<GpxImportException>()));
    });

    test('拒绝超范围坐标', () {
      const gpx = '''
<gpx><trk><trkseg>
<trkpt lat="95" lon="120"/><trkpt lat="30" lon="120"/>
</trkseg></trk></gpx>
''';
      expect(() => GpxImport.parse(gpx), throwsA(isA<GpxImportException>()));
    });

    test('拒绝异常海拔', () {
      const gpx = '''
<gpx><trk><trkseg>
<trkpt lat="30" lon="120"><ele>9000</ele></trkpt><trkpt lat="30.1" lon="120"/>
</trkseg></trk></gpx>
''';
      expect(() => GpxImport.parse(gpx), throwsA(isA<GpxImportException>()));
    });

    test('超过点数上限拒绝', () {
      final buf = StringBuffer('<gpx><trk><trkseg>');
      for (var i = 0; i < 5001; i++) {
        buf.write('<trkpt lat="30" lon="120"/>');
      }
      buf.write('</trkseg></trk></gpx>');
      expect(() => GpxImport.parse(buf.toString()),
          throwsA(isA<GpxImportException>()));
    });

    test('无海拔则 elevations 全 null', () {
      const gpx = '''
<gpx><trk><trkseg>
<trkpt lat="30" lon="120"/><trkpt lat="30.001" lon="120"/>
</trkseg></trk></gpx>
''';
      final r = GpxImport.parse(gpx);
      expect(r.elevations.every((e) => e == null), isTrue);
    });
  });

  group('GeoJsonImport', () {
    test('LineString 且经度在前', () {
      const json = '''
{"type":"LineString","coordinates":[[120.0,30.0],[120.001,30.001],[120.002,30.002]]}
''';
      final (segs, eles) = GeoJsonImport.parse(json);
      expect(segs.first.first, const LatLng(30.0, 120.0));
      expect(eles.every((e) => e == null), isTrue);
    });

    test('FeatureCollection + 第三位海拔', () {
      const json = '''
{"type":"FeatureCollection","features":[
 {"type":"Feature","geometry":{"type":"LineString","coordinates":[[120,30,100],[120.001,30.001,120]]}}
]}
''';
      final (segs, eles) = GeoJsonImport.parse(json);
      expect(segs, hasLength(1));
      expect(eles[1], 120);
    });

    test('MultiLineString 多段', () {
      const json = '''
{"type":"MultiLineString","coordinates":[[[1,1],[1.001,1]],[[2,2],[2.001,2]]]}
''';
      final (segs, _) = GeoJsonImport.parse(json);
      expect(segs, hasLength(2));
    });

    test('拒绝损坏 JSON', () {
      expect(() => GeoJsonImport.parse('{broken'),
          throwsA(isA<GeoJsonImportException>()));
    });

    test('拒绝超范围坐标', () {
      const json = '{"type":"LineString","coordinates":[[200,30],[1,1]]}';
      expect(() => GeoJsonImport.parse(json),
          throwsA(isA<GeoJsonImportException>()));
    });

    test('不含线几何时拒绝', () {
      const json = '{"type":"Point","coordinates":[1,2]}';
      expect(() => GeoJsonImport.parse(json),
          throwsA(isA<GeoJsonImportException>()));
    });
  });
}
