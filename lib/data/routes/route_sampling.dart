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
  });

  /// 在展平几何中的索引。
  final int pointIndex;
  final LatLng pos;

  /// 轨迹海拔（可能为 null = 该轨迹无海拔数据）。
  final double? elevationM;
  final double distFromStartM;

  /// 起点名/终点/高点等标注（可空）。
  final String? label;

  /// 吸附到此节点的航点（营地、休息点等）；决定图标、名称与停留时长。
  final RouteWaypoint? waypoint;

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
/// 3. 其余按 spacingM 等距采样；
/// 4. 上限 maxNodes，超出时均匀抽稀但保留关键点。
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
  // 航点（营地/休息点等）必为节点：用户关心的位置一定查天气。
  keyIdx.addAll(waypointsAt.keys.where((i) => i >= 0 && i < points.length));

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

  String? labelOf(int i) {
    final wp = waypointsAt[i];
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
        waypoint: waypointsAt[i],
      ),
  ];
}

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
