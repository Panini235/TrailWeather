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
  final double? totalPrecipMm;
  final int precipNodeCount;
  final int nodesWithData;
  final int totalNodes;

  bool get hasAnyData => nodesWithData > 0;
}

RouteWxSummary summarizeRows(List<NodeWxRow> rows) {
  double? minT, maxT, maxG, totalP;
  var precipNodes = 0;
  var withData = 0;
  var precipSeen = false;
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
    if (p != null) {
      precipSeen = true;
      if (p > 0.1) precipNodes++;
      totalP = (totalP ?? 0) + p;
    }
  }
  return RouteWxSummary(
    minTempC: minT,
    maxTempC: maxT,
    maxGustMs: maxG,
    totalPrecipMm: precipSeen ? totalP : null,
    precipNodeCount: precipNodes,
    nodesWithData: withData,
    totalNodes: rows.length,
  );
}

/// 采样 + ETA（行程模式）使用的节点序列：基于最长连续段。
List<RouteNode> nodesForRoute(
  HikingRoute route, {
  required double spacingKm,
  required int maxNodes,
}) {
  return sampleRoute(
    points: route.mainSegment,
    elevations: route.mainSegmentElevations,
    spacingM: spacingKm * 1000,
    maxNodes: maxNodes,
  );
}

/// 详情页风险提示输入。
List<NodeWeatherEntry> rowsToEntries(List<NodeWxRow> rows) => [
  for (final r in rows) NodeWeatherEntry(weather: r.wx, validUtc: r.validUtc),
];
