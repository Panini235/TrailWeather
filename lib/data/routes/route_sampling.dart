import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import 'route_models.dart';

/// 线路上的一个天气采样节点。
class RouteNode {
  const RouteNode({
    required this.pointIndex,
    required this.pos,
    required this.elevationM,
    required this.distFromStartM,
    this.label,
    this.waypoint,
    this.nearbyWaypoints = const [],
  });

  /// 在展平几何中的索引。
  final int pointIndex;
  final LatLng pos;

  /// 轨迹海拔（可能为 null = 该轨迹无海拔数据）。
  final double? elevationM;
  final double distFromStartM;

  /// 起点名/终点/高点等标注（可空）。
  final String? label;

  /// 吸附到此节点的关键航点（营地、休息点等）；决定图标、名称与停留时长。
  final RouteWaypoint? waypoint;

  /// 挂在此节点上的普通航点（打卡点、水源、补给点），按沿线距离就近归属。
  /// 它们不单独查询天气，界面只显示名称；天气是本节点的预报。
  final List<RouteWaypoint> nearbyWaypoints;

  String describe() {
    final ele = elevationM == null
        ? '海拔未知'
        : '海拔 ${elevationM!.toStringAsFixed(0)} m';
    final d = (distFromStartM / 1000).toStringAsFixed(1);
    return '${label == null ? '' : '$label · '}距起点 $d km · $ele';
  }
}

/// 线路采样：决定“在哪些点查天气”。
///
/// 重要边界（必须向用户传达）：
/// - 线路采样密度 ≠ 天气空间精度。采样间距只是工程参数；
/// - 不为每个轨迹顶点发请求；
/// - 依据来源分辨率与配额调整间距与上限。
///
/// 规则：
/// 1. 必含起点、终点；
/// 2. 有海拔数据时必含最高点（常见风险位置）；
/// 3. 关键航点（见 [isKeyWaypoint]）必为节点；普通航点不占节点，挂到最近的节点上；
/// 4. 其余按 spacingM 等距采样；
/// 5. 上限 maxNodes，超出时均匀抽稀但保留关键点。
List<RouteNode> sampleRoute({
  required List<LatLng> points,
  required List<double?> elevations,
  double spacingM = 1500,
  int maxNodes = 24,
  Map<int, RouteWaypoint> waypointsAt = const {},
}) {
  assert(points.length == elevations.length);
  if (points.isEmpty) return const [];
  final cum = Geo.cumulativeDistancesM(points);
  final total = cum.last;
  if (total == 0) {
    return [
      RouteNode(
        pointIndex: 0,
        pos: points.first,
        elevationM: elevations.first,
        distFromStartM: 0,
        label: '起点',
      ),
    ];
  }

  // 关键索引：起终点 + 最高点（海拔有效时）
  final keyIdx = <int>{0, points.length - 1};
  double? maxEle;
  var maxIdx = -1;
  for (var i = 0; i < elevations.length; i++) {
    final e = elevations[i];
    if (e != null && (maxEle == null || e > maxEle)) {
      maxEle = e;
      maxIdx = i;
    }
  }
  if (maxIdx >= 0) keyIdx.add(maxIdx);
  // 关键航点（营地/垭口/休息点等）必为节点：用户关心的位置一定查天气。
  final keyWaypoints = <int, RouteWaypoint>{};
  final minorWaypoints = <(int, RouteWaypoint)>[];
  for (final MapEntry(key: i, value: wp) in waypointsAt.entries) {
    if (i < 0 || i >= points.length) continue;
    if (isKeyWaypoint(wp)) {
      keyWaypoints[i] = wp;
    } else {
      minorWaypoints.add((i, wp));
    }
  }
  keyIdx.addAll(keyWaypoints.keys);

  final selected = <int>{...keyIdx};
  var nextAt = 0.0;
  for (var i = 0; i < points.length; i++) {
    if (cum[i] >= nextAt) {
      selected.add(i);
      nextAt += spacingM;
    }
  }

  var list = selected.toList()..sort();

  // 上限抽稀：均匀跳过非关键点。
  if (list.length > maxNodes) {
    final keep = <int>{...keyIdx};
    final nonKey = list.where((i) => !keyIdx.contains(i)).toList();
    final need = maxNodes - keep.length;
    if (need > 0 && nonKey.isNotEmpty) {
      final step = nonKey.length / need;
      for (var j = 0; j < need; j++) {
        keep.add(nonKey[(j * step).floor().clamp(0, nonKey.length - 1)]);
      }
    }
    list = keep.toList()..sort();
  }

  // 普通航点按沿线距离归到最近的节点（距离相同时归前一个）。
  final nearby = <int, List<RouteWaypoint>>{};
  minorWaypoints.sort((a, b) => a.$1.compareTo(b.$1));
  for (final (i, wp) in minorWaypoints) {
    var best = list.first;
    for (final j in list) {
      if ((cum[j] - cum[i]).abs() < (cum[best] - cum[i]).abs()) best = j;
    }
    (nearby[best] ??= []).add(wp);
  }

  String? labelOf(int i) {
    final wp = keyWaypoints[i];
    if (wp != null) return wp.name;
    if (i == 0) return '起点';
    if (i == points.length - 1) return '终点';
    if (i == maxIdx) return '高点';
    return null;
  }

  return [
    for (final i in list)
      RouteNode(
        pointIndex: i,
        pos: points[i],
        elevationM: elevations[i],
        distFromStartM: cum[i],
        label: labelOf(i),
        waypoint: keyWaypoints[i],
        nearbyWaypoints: List.unmodifiable(nearby[i] ?? const []),
      ),
  ];
}

/// 航点分级：是否作为独立的天气节点。
///
/// 关键航点（营地、垭口/峰顶、险段、下撤点、休息点，以及设了停留时长的任何航点）
/// 必为节点，不受节点上限约束；停留时长计入预计到达时间，所以必须落在自己的节点上。
/// 普通航点（打卡点、水源、补给点）只挂到最近的节点上显示名称：两步路等导出的轨迹
/// 常在每个路口、拍照点都打标记，逐个成为节点只会得到大量同网格的重复预报。
bool isKeyWaypoint(RouteWaypoint wp) =>
    wp.stopMinutes != null ||
    switch (wp.type) {
      WaypointType.camp ||
      WaypointType.pass ||
      WaypointType.danger ||
      WaypointType.exit ||
      WaypointType.rest => true,
      WaypointType.poi || WaypointType.water || WaypointType.supply => false,
    };

/// 航点吸附到路径上最近的点（偏离超过 [maxOffsetM] 的航点不进入沿途时间线，
/// 仍可在地图上显示）。多个航点落到同一点时保留先出现的那个。
Map<int, RouteWaypoint> snapWaypoints(
  List<LatLng> points,
  List<RouteWaypoint> waypoints, {
  double maxOffsetM = 300,
}) {
  final out = <int, RouteWaypoint>{};
  if (points.isEmpty) return out;
  for (final wp in waypoints) {
    var best = -1;
    var bestD = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final d = Geo.distanceM(points[i], wp.point);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best >= 0 && bestD <= maxOffsetM) out.putIfAbsent(best, () => wp);
  }
  return out;
}
