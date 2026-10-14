import 'route_models.dart';

/// 线路导出工具（导出标准 GPX / KML 文件，供两步路、奥维互动地图、Google Earth、佳明手表等使用）。
class RouteExporter {
  /// 导出为标准 GPX 1.1 格式 XML 文本。
  static String toGpx(HikingRoute route) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln(
      '<gpx version="1.1" creator="TrailWeather" xmlns="http://www.topografix.com/GPX/1/1">',
    );
    buf.writeln('  <metadata>');
    buf.writeln('    <name>${_escapeXml(route.name)}</name>');
    buf.writeln('    <time>${DateTime.now().toUtc().toIso8601String()}</time>');
    buf.writeln('  </metadata>');

    // 导出航点 (Waypoints)
    for (final wp in route.waypoints) {
      buf.write(
        '  <wpt lat="${wp.point.latitude}" lon="${wp.point.longitude}">',
      );
      if (wp.elevationM != null) {
        buf.write('<ele>${wp.elevationM!.toStringAsFixed(1)}</ele>');
      }
      buf.write('<name>${_escapeXml(wp.name)}</name>');
      buf.write(
        '<desc>${_escapeXml(wp.desc ?? waypointTypeLabel(wp.type))}</desc>',
      );
      buf.writeln('</wpt>');
    }

    // 导出轨迹 (Track)
    buf.writeln('  <trk>');
    buf.writeln('    <name>${_escapeXml(route.name)}</name>');
    var eleIndex = 0;
    for (final seg in route.segments) {
      buf.writeln('    <trkseg>');
      for (final pt in seg) {
        final ele = eleIndex < route.elevationsM.length
            ? route.elevationsM[eleIndex]
            : null;
        eleIndex++;
        buf.write('      <trkpt lat="${pt.latitude}" lon="${pt.longitude}">');
        if (ele != null) {
          buf.write('<ele>${ele.toStringAsFixed(1)}</ele>');
        }
        buf.writeln('</trkpt>');
      }
      buf.writeln('    </trkseg>');
    }
    buf.writeln('  </trk>');
    buf.writeln('</gpx>');
    return buf.toString();
  }

  /// 导出为标准 KML 格式 XML 文本（奥维互动地图/Google Earth/两步路兼容）。
  static String toKml(HikingRoute route) {
    final buf = StringBuffer();
    buf.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buf.writeln('<kml xmlns="http://www.opengis.net/kml/2.2">');
    buf.writeln('  <Document>');
    buf.writeln('    <name>${_escapeXml(route.name)}</name>');
    if (route.description != null && route.description!.isNotEmpty) {
      buf.writeln(
        '    <description>${_escapeXml(route.description!)}</description>',
      );
    }

    // 导出航点
    for (final wp in route.waypoints) {
      buf.writeln('    <Placemark>');
      buf.writeln('      <name>${_escapeXml(wp.name)}</name>');
      buf.writeln(
        '      <description>${_escapeXml(wp.desc ?? waypointTypeLabel(wp.type))}</description>',
      );
      buf.writeln('      <Point>');
      final alt = wp.elevationM != null
          ? ',${wp.elevationM!.toStringAsFixed(1)}'
          : ',0';
      buf.writeln(
        '        <coordinates>${wp.point.longitude},${wp.point.latitude}$alt</coordinates>',
      );
      buf.writeln('      </Point>');
      buf.writeln('    </Placemark>');
    }

    // 导出线段 (LineString)
    var eleIndex = 0;
    for (var i = 0; i < route.segments.length; i++) {
      final seg = route.segments[i];
      buf.writeln('    <Placemark>');
      buf.writeln(
        '      <name>${_escapeXml(route.name)} - 轨迹段 ${i + 1}</name>',
      );
      buf.writeln('      <LineString>');
      buf.writeln('        <coordinates>');
      final coordBuf = StringBuffer();
      for (final pt in seg) {
        final ele = eleIndex < route.elevationsM.length
            ? route.elevationsM[eleIndex]
            : null;
        eleIndex++;
        final alt = ele != null ? ',${ele.toStringAsFixed(1)}' : ',0';
        coordBuf.write('${pt.longitude},${pt.latitude}$alt ');
      }
      buf.writeln('          ${coordBuf.toString().trim()}');
      buf.writeln('        </coordinates>');
      buf.writeln('      </LineString>');
      buf.writeln('    </Placemark>');
    }

    buf.writeln('  </Document>');
    buf.writeln('</kml>');
    return buf.toString();
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
