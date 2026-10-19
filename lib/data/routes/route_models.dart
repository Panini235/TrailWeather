import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';

/// 线路数据来源。区分演示、用户导入、OSM 关系/路径段与手绘规划线路。
enum RouteOrigin {
  demo,
  import,
  osm,
  osmPath,

  /// 仅兼容已保存的旧收藏与离线包；不再提供对应目录、数据或加载入口。
  planet,
  planned,
}

String routeOriginLabel(RouteOrigin o) => switch (o) {
  RouteOrigin.demo => '内置示例（演示数据）',
  RouteOrigin.import => '用户导入',
  RouteOrigin.osm => 'OpenStreetMap 徒步路线关系',
  RouteOrigin.osmPath => 'OpenStreetMap 具名徒步路径段',
  RouteOrigin.planet => '历史线路（原目录已移除）',
  RouteOrigin.planned => '手绘规划线路',
};

/// 航点类型（对标两步路/奥维地图）
enum WaypointType {
  camp, // 营地 ⛺️
  water, // 水源 💧
  danger, // 险段/危险 ⚠️
  pass, // 垭口/峰顶 ⛰️
  exit, // 紧急下撤点 🚪
  poi, // 景观/打卡点 📍
  rest, // 休息点（可带停留时长，计入预计到达时间）
  supply, // 补给点
}

String waypointTypeLabel(WaypointType t) => switch (t) {
  WaypointType.camp => '营地 ⛺️',
  WaypointType.water => '水源 💧',
  WaypointType.danger => '险段 ⚠️',
  WaypointType.pass => '垭口/峰顶 ⛰️',
  WaypointType.exit => '下撤点 🚪',
  WaypointType.poi => '打卡点 📍',
  WaypointType.rest => '休息点 ☕️',
  WaypointType.supply => '补给点 🛒',
};

/// 按名称关键词推断航点类型（导入两步路/奥维等文件时使用；无法判断时为打卡点）。
WaypointType inferWaypointType(String name) {
  final n = name.toLowerCase();
  bool has(List<String> ks) => ks.any(n.contains);
  if (has(['营地', '露营', '扎营', 'camp'])) return WaypointType.camp;
  if (has(['补给', '小卖部', '商店', 'supply', 'shop'])) return WaypointType.supply;
  if (has(['休息', '午餐', '午饭', 'rest', 'lunch'])) return WaypointType.rest;
  if (has(['水源', '取水', '溪', '泉', 'water'])) return WaypointType.water;
  if (has(['下撤', '撤离', '出口', 'exit'])) return WaypointType.exit;
  if (has(['危险', '险', '悬崖', '陡', 'danger'])) return WaypointType.danger;
  if (has(['垭口', '山顶', '顶', '峰', '台', 'pass', 'summit', 'peak'])) {
    return WaypointType.pass;
  }
  return WaypointType.poi;
}

/// 导入文件中的航点上限（防止照片点等大量无关标记淹没线路）。
const int maxImportedWaypoints = 200;

/// 导入时构造航点：只保留有名称的点；跳过起终点类名称与线路同名点；按名称推断类型。
RouteWaypoint? importedWaypoint({
  required String? name,
  required LatLng point,
  double? elevationM,
  String? routeName,
}) {
  final n = name?.trim() ?? '';
  if (n.isEmpty || isEndpointWaypointName(n) || n == routeName?.trim()) {
    return null;
  }
  return RouteWaypoint(
    name: n,
    point: point,
    type: inferWaypointType(n),
    elevationM: elevationM,
  );
}

/// 起终点类名称：与地图上的起终点标记重复，导入时跳过。
bool isEndpointWaypointName(String name) {
  final n = name.trim().toLowerCase();
  return const {'起点', '终点', '起点/终点', 'start', 'end', 'finish'}.contains(n);
}

/// 线路上的关键航点（POI）。
class RouteWaypoint {
  const RouteWaypoint({
    required this.name,
    required this.point,
    required this.type,
    this.desc,
    this.elevationM,
    this.stopMinutes,
  });

  final String name;
  final LatLng point;
  final WaypointType type;
  final String? desc;
  final double? elevationM;

  /// 在此停留的分钟数（休息点等）；计入后续节点的预计到达时间。
  final int? stopMinutes;

  RouteWaypoint copyWith({
    String? name,
    WaypointType? type,
    int? stopMinutes,
  }) => RouteWaypoint(
    name: name ?? this.name,
    point: point,
    type: type ?? this.type,
    desc: desc,
    elevationM: elevationM,
    stopMinutes: stopMinutes ?? this.stopMinutes,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'lat': point.latitude,
    'lon': point.longitude,
    'type': type.name,
    'desc': desc,
    'ele': elevationM,
    'stop': stopMinutes,
  };

  factory RouteWaypoint.fromJson(Map<String, dynamic> json) => RouteWaypoint(
    name: json['name'] as String,
    point: LatLng(
      (json['lat'] as num).toDouble(),
      (json['lon'] as num).toDouble(),
    ),
    type: WaypointType.values.byName(json['type'] as String),
    desc: json['desc'] as String?,
    elevationM: (json['ele'] as num?)?.toDouble(),
    stopMinutes: (json['stop'] as num?)?.toInt(),
  );
}

/// 用于采样与配速分析的连续路径。
///
/// 两步路等导出的多日轨迹常是首尾相接的多段（段间仅相隔几十米）：
/// 首尾间距 ≤ [RouteAnalysisPath.joinGapM] 的相邻段按顺序串联为一条路径分析；
/// 段间的连接距离计入里程（近似）。更远的断开段不自动连线，取最长的串联链。
class RouteAnalysisPath {
  const RouteAnalysisPath({
    required this.points,
    required this.elevations,
    required this.segmentStartIndices,
    required this.coversAllSegments,
  });

  static const joinGapM = 1000.0;

  final List<LatLng> points;
  final List<double?> elevations;

  /// 每个原始段在 [points] 中的起始下标（第一个为 0）；多日轨迹的段边界常是分天处。
  final List<int> segmentStartIndices;

  /// 是否包含了线路的全部段（否则界面需提示“仅分析最长连续部分”）。
  final bool coversAllSegments;
}

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
    this.region,
    this.category,
    this.seasonDesc,
    this.durationDesc,
    this.description,
    this.waypoints = const [],
  }) : assert(segments.isNotEmpty),
       assert(
         elevationsM.length == segments.fold<int>(0, (a, s) => a + s.length),
         '海拔数组长度必须等于所有段点数之和',
       );

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

  /// 地区/国家（如 "法国 · 意大利 · 瑞士"、"中国西藏"）
  final String? region;

  /// 地貌类别（如 "snow", "forest", "glacier", "canyon", "coast", "peak", "volcano", "meadow"）
  final String? category;

  /// 适宜季节描述（如 "6–9 月"）
  final String? seasonDesc;

  /// 耗时天数（如 "10–11 天"、"单日 6 小时"）
  final String? durationDesc;

  /// 线路背景与走法描述
  final String? description;

  /// 沿途关键航点（营地、水源、危险点、垭口等）
  final List<RouteWaypoint> waypoints;

  List<LatLng> get flatPoints => [for (final s in segments) ...s];

  /// 起终点相距 200 m 以内视为环线。
  bool get isLoop {
    final pts = flatPoints;
    return pts.length > 2 && Geo.distanceM(pts.first, pts.last) <= 200;
  }

  /// 反向行走：段顺序与段内点序全部倒置，海拔随之倒置（展平后恰为整体倒序）；航点不变。
  HikingRoute reversed() => copyWith(
    segments: [for (final s in segments.reversed) s.reversed.toList()],
    elevationsM: elevationsM.reversed.toList(),
  );

  HikingRoute copyWith({
    List<List<LatLng>>? segments,
    List<double?>? elevationsM,
    List<RouteWaypoint>? waypoints,
  }) => HikingRoute(
    id: id,
    name: name,
    origin: origin,
    segments: segments ?? this.segments,
    elevationsM: elevationsM ?? this.elevationsM,
    sourceName: sourceName,
    sourceLicense: sourceLicense,
    sourceUrl: sourceUrl,
    importedAtUtc: importedAtUtc,
    osmId: osmId,
    isDemo: isDemo,
    region: region,
    category: category,
    seasonDesc: seasonDesc,
    durationDesc: durationDesc,
    description: description,
    waypoints: waypoints ?? this.waypoints,
  );

  /// 分析路径：串联首尾相接的段，取最长链（见 [RouteAnalysisPath]）。
  RouteAnalysisPath get analysisPath {
    final offsets = <int>[];
    var off = 0;
    for (final s in segments) {
      offsets.add(off);
      off += s.length;
    }
    List<double?> eleOf(int i) =>
        elevationsM.sublist(offsets[i], offsets[i] + segments[i].length);

    // 按顺序把相邻且首尾相接的段分成若干链。
    final chains = <List<int>>[];
    for (var i = 0; i < segments.length; i++) {
      if (chains.isNotEmpty &&
          Geo.distanceM(segments[i - 1].last, segments[i].first) <=
              RouteAnalysisPath.joinGapM) {
        chains.last.add(i);
      } else {
        chains.add([i]);
      }
    }
    double chainLen(List<int> c) {
      var l = 0.0;
      for (final i in c) {
        l += Geo.cumulativeDistancesM(segments[i]).last;
      }
      return l;
    }

    var best = chains.first;
    for (final c in chains) {
      if (chainLen(c) > chainLen(best)) best = c;
    }
    final points = <LatLng>[];
    final eles = <double?>[];
    final starts = <int>[];
    for (final i in best) {
      starts.add(points.length);
      points.addAll(segments[i]);
      eles.addAll(eleOf(i));
    }
    return RouteAnalysisPath(
      points: points,
      elevations: eles,
      segmentStartIndices: starts,
      coversAllSegments: best.length == segments.length,
    );
  }

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
    double minLat,
    double minLon,
    double maxLat,
    double maxLon,
  ) {
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
    'region': region,
    'category': category,
    'seasonDesc': seasonDesc,
    'durationDesc': durationDesc,
    'description': description,
    'waypoints': [for (final w in waypoints) w.toJson()],
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
    elevationsM: [for (final e in (map['elevationsM'] as List)) e as double?],
    sourceName: map['sourceName'] as String,
    sourceLicense: map['sourceLicense'] as String?,
    sourceUrl: map['sourceUrl'] as String?,
    importedAtUtc: map['importedAtUtc'] == null
        ? null
        : DateTime.parse(map['importedAtUtc'] as String),
    osmId: map['osmId'] as int?,
    isDemo: (map['isDemo'] as bool?) ?? false,
    region: map['region'] as String?,
    category: map['category'] as String?,
    seasonDesc: map['seasonDesc'] as String?,
    durationDesc: map['durationDesc'] as String?,
    description: map['description'] as String?,
    waypoints:
        (map['waypoints'] as List?)
            ?.map((w) => RouteWaypoint.fromJson(w as Map<String, dynamic>))
            .toList() ??
        const [],
  );

  String encode() => jsonEncode(toJson());

  static HikingRoute decode(String raw) =>
      fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
