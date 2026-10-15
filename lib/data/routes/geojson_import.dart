import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import 'route_models.dart';

/// GeoJSON（LineString / MultiLineString / Feature / FeatureCollection）导入。
///
/// 坐标格式为 [lon, lat, (ele?)]——注意 GeoJSON 经度在前。
/// 全部字段视为不可信输入：类型、范围、结构逐项校验。
class GeoJsonImport {
  static const maxInputBytes = 30 * 1024 * 1024; // 与 GPX/KML 一致
  static const autoSimplifyThreshold = 3000; // 超过则自适应抽稀，不拒绝文件

  static (List<List<LatLng>>, List<double?>) parse(String input) {
    if (input.length > maxInputBytes) {
      throw const GeoJsonImportException('文件超过 30 MB 大小限制');
    }
    final dynamic json;
    try {
      json = jsonDecode(input);
    } on FormatException catch (e) {
      throw GeoJsonImportException('JSON 解析失败：${e.message}');
    }

    final segments = <List<LatLng>>[];
    final elevations = <double?>[];

    void takeLine(dynamic coords) {
      if (coords is! List) {
        throw const GeoJsonImportException('coordinates 必须是数组');
      }
      final seg = <LatLng>[];
      final segEle = <double?>[];
      for (final c in coords) {
        if (c is! List || c.length < 2) {
          throw const GeoJsonImportException('坐标需为 [经度, 纬度] 数组');
        }
        final lon = (c[0] is num) ? (c[0] as num).toDouble() : null;
        final lat = (c[1] is num) ? (c[1] as num).toDouble() : null;
        if (lat == null || lon == null) {
          throw const GeoJsonImportException('坐标必须是数字');
        }
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
          throw const GeoJsonImportException('存在超出范围的坐标');
        }
        final ele = (c.length >= 3 && c[2] is num)
            ? (c[2] as num).toDouble()
            : null;
        seg.add(LatLng(lat, lon));
        segEle.add(ele);
      }
      if (seg.length >= 2) {
        segments.add(seg);
        elevations.addAll(segEle);
      }
    }

    void takeObject(Map<String, dynamic> m) {
      final type = m['type'];
      if (type == 'Feature') {
        final geom = m['geometry'];
        if (geom is Map<String, dynamic>) takeObject(geom);
        return;
      }
      if (type == 'FeatureCollection') {
        final fs = m['features'];
        if (fs is List) {
          for (final f in fs) {
            if (f is Map<String, dynamic>) takeObject(f);
          }
        }
        return;
      }
      if (type == 'LineString') {
        takeLine(m['coordinates']);
        return;
      }
      if (type == 'MultiLineString') {
        final lines = m['coordinates'];
        if (lines is List) {
          for (final l in lines) {
            takeLine(l);
          }
        }
        return;
      }
      // 其他类型（点/面等）不支持，静默跳过几何类型，由调用方检查是否为空。
    }

    if (json is Map<String, dynamic>) {
      takeObject(json);
    } else if (json is List) {
      // GeometryCollection
      for (final g in json) {
        if (g is Map<String, dynamic>) takeObject(g);
      }
    }

    final total = segments.fold<int>(0, (a, s) => a + s.length);
    if (segments.isEmpty) {
      throw const GeoJsonImportException('未找到 LineString/MultiLineString 几何');
    }
    if (total <= autoSimplifyThreshold) return (segments, elevations);

    // 超长轨迹：按段占比分配点数后抽稀（保留峰顶与关键转折），与 GPX/KML 行为一致。
    final newSegs = <List<LatLng>>[];
    final newEles = <double?>[];
    var offset = 0;
    for (final seg in segments) {
      final segEle = elevations.sublist(offset, offset + seg.length);
      offset += seg.length;
      final target = (seg.length / total * autoSimplifyThreshold).round().clamp(
        2,
        autoSimplifyThreshold,
      );
      final (pts, eles) = Geo.simplifyTrack(
        seg,
        segEle,
        targetMaxPoints: target,
      );
      newSegs.add(pts);
      newEles.addAll(eles);
    }
    return (newSegs, newEles);
  }

  static HikingRoute toRoute(String input, {required String fileName}) {
    final (segments, elevations) = parse(input);
    return HikingRoute(
      id: 'import-${DateTime.now().millisecondsSinceEpoch}',
      name: _guessName(fileName, input),
      origin: RouteOrigin.import,
      segments: segments,
      elevationsM: elevations,
      sourceName: '用户导入 GeoJSON：$fileName',
      importedAtUtc: DateTime.now().toUtc(),
    );
  }

  static String _guessName(String fileName, String input) {
    final base = fileName.split('/').last;
    final noExt = base.contains('.')
        ? base.substring(0, base.lastIndexOf('.'))
        : base;
    if (noExt.isNotEmpty) return noExt;
    try {
      final m = jsonDecode(input) as Map<String, dynamic>;
      final props = m['properties'];
      if (props is Map<String, dynamic>) {
        final n = props['name'];
        if (n is String && n.isNotEmpty) return n;
      }
    } catch (_) {}
    return '导入线路';
  }
}

class GeoJsonImportException implements Exception {
  const GeoJsonImportException(this.message);
  final String message;

  @override
  String toString() => message;
}
