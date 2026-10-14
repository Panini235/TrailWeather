import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';

/// 线路数据来源。区分已有徒步路线、路径数据、用户导入线路。
enum RouteOrigin { demo, import, osm, osmPath }

String routeOriginLabel(RouteOrigin o) => switch (o) {
      RouteOrigin.demo => '内置示例（演示数据）',
      RouteOrigin.import => '用户导入',
      RouteOrigin.osm => 'OpenStreetMap 徒步路线关系',
      RouteOrigin.osmPath => 'OpenStreetMap 具名徒步路径段',
    };

/// 一条徒步线路。
///
/// 几何按“连续段”组织：OSM 路线关系可能包含多段、缺失或不连通几何，
/// OSM 路径数据则只代表具名路径段、不是完整规划路线；段与段之间绝不自动连直线；
/// GPX 也可能包含多个 trkseg。
class HikingRoute {
  HikingRoute({
    required this.id,
    required this.name,
    required this.origin,
    required this.segments,
    required this.elevationsM,
    required this.sourceName,
    this.sourceLicense,
    this.sourceUrl,
    this.importedAtUtc,
    this.osmId,
    this.isDemo = false,
  })  : assert(segments.isNotEmpty),
        assert(
            elevationsM.length == segments.fold<int>(0, (a, s) => a + s.length),
            '海拔数组长度必须等于所有段点数之和');

  final String id;
  final String name;
  final RouteOrigin origin;

  /// 连续段列表，每段内几何连续；段间不保证连通。
  final List<List<LatLng>> segments;

  /// 与展平后（按段顺序连接索引）的点一一对应；缺失为 null。
  final List<double?> elevationsM;

  final String sourceName;
  final String? sourceLicense;
  final String? sourceUrl;
  final DateTime? importedAtUtc;
  final int? osmId;

  /// 演示数据标记：UI 必须持续显示“演示”标签，不得混入真实数据不说明。
  final bool isDemo;

  List<LatLng> get flatPoints => [for (final s in segments) ...s];

  /// 最长连续段（行程模式基于它计算，并明确标注）。
  List<LatLng> get mainSegment {
    var best = segments.first;
    for (final s in segments) {
      if (s.length > best.length) best = s;
    }
    return best;
  }

  List<double?> get mainSegmentElevations {
    var offset = 0;
    for (final s in segments) {
      if (identical(s, mainSegment)) {
        return elevationsM.sublist(offset, offset + s.length);
      }
      offset += s.length;
    }
    return const [];
  }

  double get totalDistanceM {
    var total = 0.0;
    for (final s in segments) {
      total += Geo.cumulativeDistancesM(s).last;
    }
    return total;
  }

  /// 累计爬升；海拔缺失时返回 null（显示“未知”，不编造）。
  double? get totalAscentM => Geo.totalAscentM(elevationsM);

  (double, double) get latRange => Geo.minMaxLat(flatPoints);
  (double, double) get lonRange => Geo.minMaxLon(flatPoints);

  bool intersectsBBox(
      double minLat, double minLon, double maxLat, double maxLon) {
    for (final p in flatPoints) {
      if (p.latitude >= minLat &&
          p.latitude <= maxLat &&
          p.longitude >= minLon &&
          p.longitude <= maxLon) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'origin': origin.name,
        'segments': [
          for (final s in segments)
            [
              for (final p in s) [p.latitude, p.longitude],
            ],
        ],
        'elevationsM': elevationsM.map((e) => e).toList(),
        'sourceName': sourceName,
        'sourceLicense': sourceLicense,
        'sourceUrl': sourceUrl,
        'importedAtUtc': importedAtUtc?.toIso8601String(),
        'osmId': osmId,
        'isDemo': isDemo,
      };

  static HikingRoute fromJson(Map<String, dynamic> map) => HikingRoute(
        id: map['id'] as String,
        name: map['name'] as String,
        origin: RouteOrigin.values.byName(map['origin'] as String),
        segments: [
          for (final seg in (map['segments'] as List))
            [
              for (final pt in (seg as List))
                LatLng((pt as List)[0] as double, pt[1] as double),
            ],
        ],
        elevationsM: [
          for (final e in (map['elevationsM'] as List)) e as double?,
        ],
        sourceName: map['sourceName'] as String,
        sourceLicense: map['sourceLicense'] as String?,
        sourceUrl: map['sourceUrl'] as String?,
        importedAtUtc: map['importedAtUtc'] == null
            ? null
            : DateTime.parse(map['importedAtUtc'] as String),
        osmId: map['osmId'] as int?,
        isDemo: (map['isDemo'] as bool?) ?? false,
      );

  String encode() => jsonEncode(toJson());

  static HikingRoute decode(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
