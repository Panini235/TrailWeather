import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:latlong2/latlong.dart';

import '../../core/wx_http.dart';
import 'route_models.dart';

/// Overpass API 适配器：按可视区域发现 OSM 徒步路线关系（relation[route=hiking]）。
///
/// 使用边界（对应 OSM/Overpass 公共服务政策）：
/// - 仅在缩放足够（≥11）且用户点击“搜索此区域”时查询；
/// - bbox 跨度限制，不执行全球抓取；返回条数限制；
/// - 多公共镜像轮换，429/5xx 由 WxHttp 退避，不规避配额；
/// - 结果按 ODbL 展示署名；仅在线使用，不做整库复制。
///
/// 几何处理：relation 成员 way 可能乱序、缺失或不连通。
/// 本类按端点哈希贪心串联共享端点的 way；不共享端点的 way 成为独立段，
/// 绝不自动连直线。
class OverpassRouteSource {
  OverpassRouteSource({WxHttp? http})
      : _http = http ?? WxHttp(maxRetries: 1);

  final WxHttp _http;

  static const endpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
  ];

  static const userAgent =
      'TrailWeather/0.1.0 (github.com/Panini235/TrailWeather)';

  /// bbox 跨度上限（约一个城市尺度）。
  static const maxBboxSpan = 0.6;

  /// 单次最多解析的 relation 数。
  static const maxRelations = 30;

  bool bboxAllowed(double minLat, double minLon, double maxLat, double maxLon) {
    final spanLat = maxLat - minLat;
    final spanLon = maxLon - minLon;
    return spanLat > 0 && spanLon > 0 && spanLat <= maxBboxSpan && spanLon <= maxBboxSpan;
  }

  Future<List<HikingRoute>> fetchRoutesInBBox(
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) async {
    if (!bboxAllowed(minLat, minLon, maxLat, maxLon)) {
      throw const OverpassException('当前视野范围过大，请放大地图后再搜索此区域');
    }
    final bbox =
        '$minLat,$minLon,$maxLat,$maxLon';
    final query =
        '[out:json][timeout:25];relation[route=hiking]($bbox);out tags geom $maxRelations;';

    Object? lastErr;
    for (final ep in endpoints) {
      try {
        final uri = Uri.parse('$ep?data=${Uri.encodeQueryComponent(query)}');
        final body = await _http.getText(uri);
        return parseResponse(body);
      } catch (e) {
        lastErr = e;
        // 轮换下一个镜像。
      }
    }
    throw OverpassException('Overpass 服务暂不可用（所有镜像失败）：$lastErr');
  }

  @visibleForTesting
  List<HikingRoute> parseResponse(String body) {
    final dynamic json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw const OverpassException('Overpass 返回了无法解析的内容（服务可能过载）');
    }
    final elements = (json['elements'] as List? ?? const []);
    final routes = <HikingRoute>[];
    for (final el in elements) {
      if (el is! Map<String, dynamic>) continue;
      if (el['type'] != 'relation') continue;
      final route = _relationToRoute(el);
      if (route != null) routes.add(route);
      if (routes.length >= maxRelations) break;
    }
    return routes;
  }

  HikingRoute? _relationToRoute(Map<String, dynamic> el) {
    final members = (el['members'] as List? ?? const []);
    final wayGeoms = <List<LatLng>>[];
    for (final m in members) {
      if (m is! Map<String, dynamic>) continue;
      if (m['type'] != 'way') continue;
      final geometry = m['geometry'];
      if (geometry is! List) continue;
      final pts = <LatLng>[];
      for (final g in geometry) {
        if (g is! Map<String, dynamic>) continue;
        final lat = (g['lat'] as num?)?.toDouble();
        final lon = (g['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
        pts.add(LatLng(lat, lon));
      }
      if (pts.length >= 2) wayGeoms.add(pts);
    }
    if (wayGeoms.isEmpty) return null;
    final segments = assembleSegments(wayGeoms);
    if (segments.isEmpty) return null;

    final tags = (el['tags'] as Map<String, dynamic>?) ?? {};
    final name = (tags['name'] as String?) ?? '未命名徒步路线 ${el['id']}';
    final distanceTag = tags['distance'] as String?;

    final elevations = List<double?>.filled(
      segments.fold<int>(0, (a, s) => a + s.length),
      null,
    ); // Overpass 几何不携带海拔；显示“未知”，不编造。

    return HikingRoute(
      id: 'osm-r${el['id']}',
      name: name,
      origin: RouteOrigin.osm,
      segments: segments,
      elevationsM: elevations,
      sourceName: 'OpenStreetMap 徒步路线关系'
          '${distanceTag == null ? '' : '（标注里程 $distanceTag）'}',
      sourceLicense: 'ODbL 1.0',
      sourceUrl: 'https://www.openstreetmap.org/relation/${el['id']}',
      osmId: (el['id'] as num?)?.toInt(),
    );
  }

  /// 端点贪心拼装：共享端点的 way 连接（必要时反转），其余独立成段。
  /// 相邻 way 之间必须真实共享端点才连接；不补直线。
  @visibleForTesting
  static List<List<LatLng>> assembleSegments(List<List<LatLng>> ways) {
    final remaining = List.of(ways);
    final segments = <List<LatLng>>[];

    String key(LatLng p) =>
        '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

    while (remaining.isNotEmpty) {
      var current = remaining.removeAt(0);
      var extended = true;
      while (extended) {
        extended = false;
        for (var i = 0; i < remaining.length; i++) {
          final w = remaining[i];
          final headKey = key(current.first);
          final tailKey = key(current.last);
          final wHead = key(w.first);
          final wTail = key(w.last);
          if (tailKey == wHead) {
            current = [...current, ...w.skip(1)];
          } else if (tailKey == wTail) {
            current = [...current, ...w.reversed.skip(1)];
          } else if (headKey == wTail) {
            current = [...w, ...current.skip(1)];
          } else if (headKey == wHead) {
            current = [...w.reversed, ...current.skip(1)];
          } else {
            continue;
          }
          remaining.removeAt(i);
          extended = true;
          break;
        }
      }
      if (current.length >= 2) segments.add(current);
    }
    return segments;
  }
}

class OverpassException implements Exception {
  const OverpassException(this.message);
  final String message;

  @override
  String toString() => message;
}
