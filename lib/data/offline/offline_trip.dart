import 'dart:convert';

import 'package:archive/archive.dart' show getCrc32;
import 'package:latlong2/latlong.dart';

import '../routes/route_models.dart';
import '../routes/route_sampling.dart';
import '../weather/eta.dart';
import '../weather/weather_codec.dart';
import '../weather/weather_models.dart';
import '../weather/weather_repository.dart';

DateTime utcHour(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour);
}

enum OfflineTimeMode { fixed, trip }

/// 下载时的计划快照；route 本身已按选择的行走方向排列。
class OfflineTripPlan {
  const OfflineTripPlan({
    required this.route,
    required this.nodes,
    required this.nodeTimesUtc,
    required this.mode,
    required this.reversed,
    required this.selectedTimeUtc,
    required this.pace,
    required this.startUtc,
    required this.endUtc,
  });

  final HikingRoute route;
  final List<RouteNode> nodes;
  final List<DateTime> nodeTimesUtc;
  final OfflineTimeMode mode;
  final bool reversed;
  final DateTime selectedTimeUtc;
  final PaceConfig pace;
  final DateTime startUtc;
  final DateTime endUtc;

  int get hourCount => endUtc.difference(startUtc).inHours;

  int get outsidePlanCount => nodeTimesUtc
      .where((t) => t.isBefore(startUtc) || !t.isBefore(endUtc))
      .length;

  Map<String, dynamic> toJson() => {
    'route': route.toJson(),
    'nodes': [
      for (final n in nodes)
        {
          'index': n.pointIndex,
          'lat': n.pos.latitude,
          'lon': n.pos.longitude,
          'elevation': n.elevationM,
          'distance': n.distFromStartM,
          'label': n.label,
          'waypoint': n.waypoint?.toJson(),
          if (n.nearbyWaypoints.isNotEmpty)
            'nearby': [for (final w in n.nearbyWaypoints) w.toJson()],
        },
    ],
    'times': [for (final t in nodeTimesUtc) t.toUtc().toIso8601String()],
    'mode': mode.name,
    'reversed': reversed,
    'selected': selectedTimeUtc.toUtc().toIso8601String(),
    'pace': {
      'speed': pace.speedKmh,
      'ascent': pace.ascentMinPer100m,
      'descent': pace.descentMinPer100m,
      'rest': pace.restMinutesTotal,
    },
    'start': startUtc.toUtc().toIso8601String(),
    'end': endUtc.toUtc().toIso8601String(),
  };

  factory OfflineTripPlan.fromJson(Map<String, dynamic> m) {
    final p = m['pace'] as Map<String, dynamic>;
    return OfflineTripPlan(
      route: HikingRoute.fromJson(m['route'] as Map<String, dynamic>),
      nodes: [
        for (final n in m['nodes'] as List)
          RouteNode(
            pointIndex: n['index'] as int,
            pos: LatLng(
              (n['lat'] as num).toDouble(),
              (n['lon'] as num).toDouble(),
            ),
            elevationM: (n['elevation'] as num?)?.toDouble(),
            distFromStartM: (n['distance'] as num).toDouble(),
            label: n['label'] as String?,
            waypoint: n['waypoint'] == null
                ? null
                : RouteWaypoint.fromJson(n['waypoint'] as Map<String, dynamic>),
            // 旧离线包没有该字段。
            nearbyWaypoints: [
              for (final w in (n['nearby'] as List?) ?? const [])
                RouteWaypoint.fromJson(w as Map<String, dynamic>),
            ],
          ),
      ],
      nodeTimesUtc: [
        for (final t in m['times'] as List) DateTime.parse(t as String).toUtc(),
      ],
      mode: OfflineTimeMode.values.byName(m['mode'] as String),
      reversed: m['reversed'] as bool,
      selectedTimeUtc: DateTime.parse(m['selected'] as String).toUtc(),
      pace: PaceConfig(
        speedKmh: (p['speed'] as num).toDouble(),
        ascentMinPer100m: (p['ascent'] as num).toDouble(),
        descentMinPer100m: (p['descent'] as num).toDouble(),
        restMinutesTotal: p['rest'] as int,
      ),
      startUtc: DateTime.parse(m['start'] as String).toUtc(),
      endUtc: DateTime.parse(m['end'] as String).toUtc(),
    );
  }

  void validate() {
    if (![24, 48, 72].contains(hourCount) ||
        startUtc != utcHour(startUtc) ||
        endUtc != utcHour(endUtc) ||
        nodes.isEmpty ||
        nodes.length != nodeTimesUtc.length ||
        route.segments.isEmpty ||
        route.segments.any((s) => s.isEmpty) ||
        route.elevationsM.length != route.flatPoints.length ||
        pace.speedKmh <= 0 ||
        !pace.speedKmh.isFinite ||
        pace.ascentMinPer100m < 0 ||
        pace.descentMinPer100m < 0 ||
        pace.restMinutesTotal < 0) {
      throw const FormatException('离线行程计划不完整');
    }
    final path = route.analysisPath.points;
    for (final n in nodes) {
      if (n.pointIndex < 0 ||
          n.pointIndex >= path.length ||
          path[n.pointIndex] != n.pos ||
          !n.distFromStartM.isFinite) {
        throw const FormatException('离线节点与线路不匹配');
      }
    }
  }
}

class OfflineCoverage {
  const OfflineCoverage(this.expected, this.available, this.coreVariables);
  final int expected;
  final int available;

  /// 温度、降水量、持续风速均存在的节点小时数。0 数值属于有效数据。
  final int coreVariables;
  int get missing => expected - available;
  bool get complete => available == expected;
}

/// 独立于普通缓存的原始预报快照；读取永远不调用网络或修改获取时间。
class OfflineTrip {
  const OfflineTrip({
    required this.id,
    required this.plan,
    required this.bundle,
    required this.queryPoints,
    required this.sourceName,
    required this.freshFor,
    required this.savedAtUtc,
    this.modelOverlapNote,
  });

  final String id;
  final OfflineTripPlan plan;
  final RouteWeatherBundle bundle;
  final List<LatLng> queryPoints;
  final String sourceName;
  final String? modelOverlapNote;
  final Duration freshFor;
  final DateTime savedAtUtc;

  DateTime get oldestFetchedAtUtc => bundle.result.points.fold(
    bundle.result.fetchedAtUtc,
    (old, p) => p.provenance.fetchedAtUtc.isBefore(old)
        ? p.provenance.fetchedAtUtc
        : old,
  );
  bool needsUpdate(DateTime now) =>
      !now.toUtc().isBefore(oldestFetchedAtUtc.add(freshFor));
  bool windowEnded(DateTime now) => !now.toUtc().isBefore(plan.endUtc);

  WxPointForecast? pointFor(int nodeIndex) {
    final qi = bundle.nodeQueryIndex[nodeIndex];
    return qi >= 0 && qi < bundle.result.points.length
        ? bundle.result.points[qi]
        : null;
  }

  WxHourValue? hourFor(int nodeIndex, DateTime time) {
    final utc = time.toUtc();
    if (utc.isBefore(plan.startUtc) || !utc.isBefore(plan.endUtc)) return null;
    return pointFor(nodeIndex)?.hourAt(utc);
  }

  OfflineCoverage get coverage {
    var available = 0;
    var core = 0;
    for (var n = 0; n < plan.nodes.length; n++) {
      final byHour = {
        for (final h in pointFor(n)?.displayHours ?? <WxHourValue>[])
          h.validFromUtc: h,
      };
      for (var i = 0; i < plan.hourCount; i++) {
        final h = byHour[plan.startUtc.add(Duration(hours: i))];
        if (h == null) continue;
        if (h.values.values.any((v) => v != null)) available++;
        if ([
          WxVar.temperature,
          WxVar.precip,
          WxVar.windSpeed,
        ].every((v) => h.values[v] != null)) {
          core++;
        }
      }
    }
    return OfflineCoverage(plan.nodes.length * plan.hourCount, available, core);
  }

  void validate() {
    validateOfflineId(id);
    plan.validate();
    if (bundle.nodeQueryIndex.length != plan.nodes.length ||
        queryPoints.isEmpty ||
        bundle.nodeQueryIndex.any((i) => i < 0 || i >= queryPoints.length) ||
        bundle.result.points.length > queryPoints.length ||
        freshFor <= Duration.zero) {
      throw const FormatException('离线预报的节点映射不完整');
    }
    for (var i = 0; i < bundle.result.points.length; i++) {
      final p = bundle.result.points[i];
      final prov = p.provenance;
      if (prov.providerId != bundle.result.providerId ||
          (prov.requestLat - queryPoints[i].latitude).abs() > 0.000001 ||
          (prov.requestLon - queryPoints[i].longitude).abs() > 0.000001 ||
          p.hours.any((h) => h.validFromUtc != utcHour(h.validFromUtc)) ||
          p.hours.map((h) => h.validFromUtc).toSet().length != p.hours.length) {
        throw const FormatException('来源返回坐标或时次与离线请求不匹配');
      }
    }
  }

  /// CRC32 用于发现意外损坏，不是签名或来源真实性认证。
  String encode() {
    validate();
    final payload = jsonEncode({
      'id': id,
      'plan': plan.toJson(),
      'weather': WeatherCodec.encode(bundle.result),
      'mapping': bundle.nodeQueryIndex,
      'shared': bundle.sharedGridNote,
      'queries': [
        for (final p in queryPoints) [p.latitude, p.longitude],
      ],
      'source': sourceName,
      'overlap': modelOverlapNote,
      'ttl': freshFor.inSeconds,
      'saved': savedAtUtc.toUtc().toIso8601String(),
    });
    final bytes = utf8.encode(payload);
    return jsonEncode({
      'version': 1,
      'bytes': bytes.length,
      'crc32': getCrc32(bytes),
      'payload': payload,
    });
  }

  static OfflineTrip decode(String raw) {
    try {
      final envelope = jsonDecode(raw) as Map<String, dynamic>;
      final payload = envelope['payload'] as String;
      final bytes = utf8.encode(payload);
      if (envelope['version'] != 1 ||
          envelope['bytes'] != bytes.length ||
          envelope['crc32'] != getCrc32(bytes)) {
        throw const FormatException('离线包版本不支持或校验失败');
      }
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final weather = WeatherCodec.decode(m['weather'] as String);
      if (weather == null) throw const FormatException('离线预报损坏');
      final trip = OfflineTrip(
        id: m['id'] as String,
        plan: OfflineTripPlan.fromJson(m['plan'] as Map<String, dynamic>),
        bundle: RouteWeatherBundle(
          result: weather,
          nodeQueryIndex: (m['mapping'] as List).cast<int>(),
          sharedGridNote: m['shared'] as String?,
        ),
        queryPoints: [
          for (final p in m['queries'] as List)
            LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        sourceName: m['source'] as String,
        modelOverlapNote: m['overlap'] as String?,
        freshFor: Duration(seconds: m['ttl'] as int),
        savedAtUtc: DateTime.parse(m['saved'] as String).toUtc(),
      );
      trip.validate();
      return trip;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('离线包无法读取');
    }
  }
}

void validateOfflineId(String id) {
  if (!RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(id)) {
    throw const FormatException('无效的离线包标识');
  }
}
