import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/routes/geojson_import.dart';
import 'package:trailweather/data/routes/route_file_import.dart';

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="GPSBabel">
  <wpt lat="39.05" lon="113.65"><ele>2510</ele></wpt>
  <trk><name>五台山测试</name><trkseg>
    <trkpt lat="39.050" lon="113.650"><ele>2500</ele></trkpt>
    <trkpt lat="39.051" lon="113.651"><ele>2520</ele></trkpt>
    <trkpt lat="39.052" lon="113.652"><ele>2540</ele></trkpt>
  </trkseg></trk>
</gpx>''';

const _kml = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
  <Document><name>KML 测试</name>
    <Placemark><name>起点</name><Point><coordinates>113.65,39.05,2500</coordinates></Point></Placemark>
    <Placemark><gx:Track>
      <when>2026-05-30T00:00:00Z</when><when>2026-05-30T00:01:00Z</when>
      <gx:coord>113.650 39.050 2500</gx:coord><gx:coord>113.651 39.051 2520</gx:coord>
    </gx:Track></Placemark>
  </Document>
</kml>''';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _kmz(String kml, {String name = 'doc.kml'}) {
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('files/icon.png', [1, 2, 3]))
    ..addFile(ArchiveFile.bytes(name, utf8.encode(kml)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  group('RouteFileImport 按内容识别格式', () {
    test('GPX（含 CRLF 与 BOM）', () {
      final r = RouteFileImport.fromBytes(
        _bytes('﻿${_gpx.replaceAll('\n', '\r\n')}'),
        'track.gpx',
      );
      expect(r.route.name, '五台山测试');
      expect(r.route.flatPoints, hasLength(3));
      expect(r.route.elevationsM.last, 2540);
    });

    test('KML gx:Track，扩展名异常（"xxx.kml 2"）也能识别', () {
      final r = RouteFileImport.fromBytes(_bytes(_kml), '2026 五台山.kml 2');
      expect(r.route.flatPoints, hasLength(2));
      expect(r.route.sourceName, contains('KML'));
    });

    test('KMZ：解压 doc.kml', () {
      final r = RouteFileImport.fromBytes(_kmz(_kml), 'track.kmz');
      expect(r.route.flatPoints, hasLength(2));
      expect(r.route.elevationsM.first, 2500);
    });

    test('KMZ：无 doc.kml 时取第一个 .kml', () {
      final r = RouteFileImport.fromBytes(
        _kmz(_kml, name: 'tracks/a.KML'),
        'track.kmz',
      );
      expect(r.route.flatPoints, hasLength(2));
    });

    test('KMZ 内无 KML 时给出明确错误', () {
      final archive = Archive()..addFile(ArchiveFile.bytes('a.txt', [65]));
      final zip = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(
        () => RouteFileImport.fromBytes(zip, 'x.kmz'),
        throwsA(
          isA<RouteImportException>().having(
            (e) => e.message,
            'message',
            contains('未找到 .kml'),
          ),
        ),
      );
    });

    test('GeoJSON', () {
      final r = RouteFileImport.fromBytes(
        _bytes(
          '{"type":"LineString","coordinates":[[120,30],[120.001,30.001]]}',
        ),
        'a.geojson',
      );
      expect(r.route.flatPoints, hasLength(2));
    });

    test('无法识别的格式与空文件', () {
      expect(
        () => RouteFileImport.fromBytes(_bytes('hello'), 'a.txt'),
        throwsA(isA<RouteImportException>()),
      );
      expect(
        () => RouteFileImport.fromBytes(Uint8List(0), 'a.gpx'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('解析器异常统一转换为 RouteImportException', () {
      expect(
        () => RouteFileImport.fromText('<gpx><broken', 'a.gpx'),
        throwsA(isA<RouteImportException>()),
      );
    });

    test('逐点重复告警合并计数', () {
      final pts = [
        for (var i = 0; i < 5; i++)
          '<trkpt lat="30.00$i" lon="120.00$i"><ele>99999</ele></trkpt>',
      ].join();
      final r = RouteFileImport.fromText(
        '<gpx><trk><trkseg>$pts</trkseg></trk></gpx>',
        'a.gpx',
      );
      expect(r.warnings, hasLength(1));
      expect(r.warnings.single, contains('共 5 处'));
    });

    test('isolate 入口函数可直接调用', () {
      final r = importRouteFile((bytes: _bytes(_gpx), fileName: 'a.gpx'));
      expect(r.route.flatPoints, hasLength(3));
    });
  });

  test('GeoJSON 超长轨迹自适应抽稀而非拒绝', () {
    final coords = [
      for (var i = 0; i < 6000; i++)
        '[${120 + i * 0.0001},${30 + (i % 7) * 0.00003}]',
    ].join(',');
    final (segs, eles) = GeoJsonImport.parse(
      '{"type":"LineString","coordinates":[$coords]}',
    );
    final total = segs.fold<int>(0, (a, s) => a + s.length);
    expect(total, lessThanOrEqualTo(GeoJsonImport.autoSimplifyThreshold));
    expect(eles, hasLength(total));
  });
}
