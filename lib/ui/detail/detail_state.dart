import '../../data/routes/route_models.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/weather/eta.dart';
import '../../data/weather/risk_rules.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';

/// 时间模式：固定时刻 / 行程。
enum TimeMode { fixed, trip }

/// 线路天气查询参数（作为 FutureProvider family 的 key）。
class RouteWeatherQuery {
  const RouteWeatherQuery({
    required this.routeId,
    required this.providerId,
    required this.mode,
    required this.startUtc,
    required this.endUtc,
    required this.fixedUtc,
    required this.pace,
  });

  final String routeId;
  final String providerId;
  final TimeMode mode;
  final DateTime startUtc;
  final DateTime endUtc;
  final DateTime fixedUtc;
  final PaceConfig pace;

  @override
  bool operator ==(Object other) =>
      other is RouteWeatherQuery &&
      other.routeId == routeId &&
      other.providerId == providerId &&
      other.mode == mode &&
      other.startUtc == startUtc &&
      other.endUtc == endUtc &&
      other.fixedUtc == fixedUtc &&
      other.pace.speedKmh == pace.speedKmh &&
      other.pace.ascentMinPer100m == pace.ascentMinPer100m &&
      other.pace.descentMinPer100m == pace.descentMinPer100m &&
      other.pace.restMinutesTotal == pace.restMinutesTotal;

  @override
  int get hashCode => Object.hash(
    routeId,
    providerId,
    mode,
    startUtc,
    endUtc,
    fixedUtc,
    pace.speedKmh,
    pace.ascentMinPer100m,
    pace.descentMinPer100m,
    pace.restMinutesTotal,
  );
}

/// 节点 + 该节点对应时刻的天气。
class NodeWxRow {
  const NodeWxRow({
    required this.node,
    required this.validUtc,
    required this.point,
    required this.sharedWithPrev,
  });

  final RouteNode node;
  final DateTime validUtc;

  /// 来源对应的查询点预报（可能为 null：来源未覆盖/超范围）。
  final WxPointForecast? point;

  WxHourValue? get wx => point?.hourAt(validUtc);

  /// 与前一节点共享同一查询点（近似网格合并）。
  final bool sharedWithPrev;
}

/// 组装节点行。模式决定有效时刻：
/// - fixed：全部使用同一有效时刻；
/// - trip：使用 computeEtas 的估算到达时间。
List<NodeWxRow> buildNodeRows({
  required List<RouteNode> nodes,
  required RouteWeatherBundle? bundle,
  required TimeMode mode,
  required DateTime fixedUtc,
  required List<DateTime> etas,
}) {
  return [
    for (var i = 0; i < nodes.length; i++)
      NodeWxRow(
        node: nodes[i],
        validUtc: mode == TimeMode.fixed ? fixedUtc : etas[i],
        point: bundle == null
            ? null
            : (bundle.nodeQueryIndex[i] < bundle.result.points.length
                  ? bundle.result.points[bundle.nodeQueryIndex[i]]
                  : null),
        sharedWithPrev:
            i > 0 &&
            bundle != null &&
            bundle.nodeQueryIndex[i] == bundle.nodeQueryIndex[i - 1],
      ),
  ];
}

/// 与上一行是同一条预报：同一查询点（近似网格合并）且同一小时，数据完全相同
/// （缺失时同为缺失）。行程模式下同一网格、不同小时的节点不算重复。
bool sameForecastAsPrev(List<NodeWxRow> rows, int i) =>
    i > 0 &&
    rows[i].sharedWithPrev &&
    _hourOf(rows[i].validUtc) == _hourOf(rows[i - 1].validUtc);

DateTime _hourOf(DateTime t) {
  final u = t.toUtc();
  return DateTime.utc(u.year, u.month, u.day, u.hour);
}

/// 时间线条目：展示 [index] 节点；[folded] 是紧随其后、预报与它相同的普通节点。
class TimelineEntry {
  TimelineEntry(this.index);

  final int index;
  final List<int> folded = [];
}

/// 时间线折叠：连续预报相同的普通节点收进上一条目。
/// 只折叠没有名称的节点（起终点、高点、关键航点总是单独显示），
/// 只在数据完全相同时折叠，不同的数据绝不合并。
List<TimelineEntry> foldTimeline(List<NodeWxRow> rows) {
  final out = <TimelineEntry>[];
  for (var i = 0; i < rows.length; i++) {
    if (out.isNotEmpty &&
        rows[i].node.label == null &&
        sameForecastAsPrev(rows, i)) {
      out.last.folded.add(i);
    } else {
      out.add(TimelineEntry(i));
    }
  }
  return out;
}

/// 线路摘要：按“选定来源”展示，不跨来源拼接。
class RouteWxSummary {
  const RouteWxSummary({
    this.minTempC,
    this.maxTempC,
    this.maxGustMs,
    this.totalPrecipMm,
    this.precipNodeCount = 0,
    this.nodesWithData = 0,
    this.totalNodes = 0,
  });

  final double? minTempC;
  final double? maxTempC;
  final double? maxGustMs;

  /// 见 [routePrecipMm]：按小时取沿途最大值后累加（估算），非逐节点求和。
  final double? totalPrecipMm;
  final int precipNodeCount;
  final int nodesWithData;
  final int totalNodes;

  bool get hasAnyData => nodesWithData > 0;
}

RouteWxSummary summarizeRows(List<NodeWxRow> rows) {
  double? minT, maxT, maxG;
  var precipNodes = 0;
  var withData = 0;
  final precipSamples = <(DateTime, double?)>[];
  for (final r in rows) {
    final w = r.wx;
    if (w == null) continue;
    withData++;
    final t = w.values[WxVar.temperature];
    if (t != null) {
      if (minT == null || t < minT) minT = t;
      if (maxT == null || t > maxT) maxT = t;
    }
    final g = w.values[WxVar.windGust];
    if (g != null && (maxG == null || g > maxG)) maxG = g;
    final p = w.values[WxVar.precip];
    if (p != null && p > 0.1) precipNodes++;
    precipSamples.add((r.validUtc, p));
  }
  return RouteWxSummary(
    minTempC: minT,
    maxTempC: maxT,
    maxGustMs: maxG,
    totalPrecipMm: routePrecipMm(precipSamples),
    precipNodeCount: precipNodes,
    nodesWithData: withData,
    totalNodes: rows.length,
  );
}

/// 采样 + ETA（行程模式）使用的节点序列：基于分析路径（首尾相接的段已串联），
/// 航点吸附后必为节点。
List<RouteNode> nodesForRoute(
  HikingRoute route, {
  required double spacingKm,
  required int maxNodes,
}) {
  final path = route.analysisPath;
  return sampleRoute(
    points: path.points,
    elevations: path.elevations,
    spacingM: spacingKm * 1000,
    maxNodes: maxNodes,
    waypointsAt: snapWaypoints(path.points, route.waypoints),
  );
}

/// 详情页风险提示输入。
List<NodeWeatherEntry> rowsToEntries(List<NodeWxRow> rows) => [
  for (final r in rows)
    NodeWeatherEntry(
      weather: r.wx,
      validUtc: r.validUtc,
      elevationM: r.node.elevationM,
    ),
];

/// 选定日期（设备时区）全天的沿途降水概况。
class DayPrecipSummary {
  const DayPrecipSummary({
    required this.maxDayMm,
    required this.firstWetUtc,
    required this.lastWetUtc,
    required this.maxProb,
    required this.minHoursCovered,
  });

  /// 沿途各查询点全天降水合计的最大值；全部缺失为 null（不当作 0）。
  final double? maxDayMm;

  /// 有降水（≥0.1 mm）的最早 / 最晚小时起点（UTC）；无降水为 null。
  final DateTime? firstWetUtc;
  final DateTime? lastWetUtc;

  /// 全天最大降水概率（集合预报）；未提供为 null。
  final double? maxProb;

  /// 各点实际覆盖的小时数最小值（< 24 表示来源未覆盖全天）。
  final int minHoursCovered;
}

/// 全天降水：每个查询点按来源时间语义合计全天，再取沿途最大。
///
/// [precedingHour]：Open-Meteo 的降水标在“上一小时结束”时刻（t 表示 t−1h~t），
/// 全天取 (00:00, 24:00]；其他来源按“该小时起”取 [00:00, 24:00)。
DayPrecipSummary summarizeDayPrecip({
  required List<WxPointForecast> points,
  required DateTime dayStartUtc,
  required bool precedingHour,
}) {
  final dayEnd = dayStartUtc.add(const Duration(hours: 24));
  double? maxDay;
  double? maxProb;
  DateTime? first;
  DateTime? last;
  var minCovered = points.isEmpty ? 0 : 24;
  for (final p in points) {
    var sum = 0.0;
    var covered = 0;
    for (final h in p.hours) {
      final t = h.validFromUtc;
      final inDay = precedingHour
          ? t.isAfter(dayStartUtc) && !t.isAfter(dayEnd)
          : !t.isBefore(dayStartUtc) && t.isBefore(dayEnd);
      if (!inDay) continue;
      final prob = h.values[WxVar.precipProb];
      if (prob != null && (maxProb == null || prob > maxProb)) maxProb = prob;
      final mm = h.values[WxVar.precip];
      if (mm == null) continue;
      covered++;
      sum += mm;
      if (mm >= 0.1) {
        final start = precedingHour ? t.subtract(const Duration(hours: 1)) : t;
        if (first == null || start.isBefore(first)) first = start;
        if (last == null || start.isAfter(last)) last = start;
      }
    }
    if (covered < minCovered) minCovered = covered;
    if (covered > 0 && (maxDay == null || sum > maxDay)) maxDay = sum;
  }
  return DayPrecipSummary(
    maxDayMm: maxDay,
    firstWetUtc: first,
    lastWetUtc: last,
    maxProb: maxProb,
    minHoursCovered: minCovered,
  );
}
