import '../../data/routes/route_sampling.dart';

/// 徒步配速模型（可配置、假设透明）。
///
/// 模型：每段耗时 = 平距/速度 + 爬升×上升系数 + 下降×下降系数；
/// 总休息时长按距离比例分摊到各节点。
/// 这是估算，不是导航保证；所有假设在 UI 中展示。
class PaceConfig {
  const PaceConfig({
    this.speedKmh = 3.6,
    this.ascentMinPer100m = 12.0,
    this.descentMinPer100m = 6.0,
    this.restMinutesTotal = 0,
  });

  /// 平地行走速度（km/h）。
  final double speedKmh;

  /// 每上升 100 m 额外耗时（分钟，Naismith 式修正）。
  final double ascentMinPer100m;

  /// 每下降 100 m 额外耗时（分钟）。
  final double descentMinPer100m;

  /// 全程休息总时长（分钟）。
  final int restMinutesTotal;

  static const defaults = PaceConfig();

  List<String> assumptionNotes() => [
    '平地速度 $speedKmh km/h',
    '每上升 100 m 加时 $ascentMinPer100m 分钟、每下降 100 m 加时 $descentMinPer100m 分钟',
    '休息共 $restMinutesTotal 分钟，按距离比例分摊',
    '预计到达时间为估算，不构成导航保证',
  ];
}

/// 计算各节点的预计到达时间（UTC）。
///
/// 时间运算全部使用 UTC（跨午夜、跨时区、夏令时安全）；
/// 展示时再按线路当地偏移或设备时区格式化。
/// 若海拔缺失，地形加时不计（并在 UI 注明“无海拔数据，未计入爬升影响”）。
List<DateTime> computeEtas({
  required List<RouteNode> nodes,
  required DateTime startUtc,
  PaceConfig pace = PaceConfig.defaults,
}) {
  if (nodes.isEmpty) return const [];
  final out = <DateTime>[startUtc];
  var elapsedMin = 0.0;
  for (var i = 1; i < nodes.length; i++) {
    final segDistKm =
        (nodes[i].distFromStartM - nodes[i - 1].distFromStartM) / 1000;
    var segMin = segDistKm / pace.speedKmh * 60;
    final e0 = nodes[i - 1].elevationM;
    final e1 = nodes[i].elevationM;
    if (e0 != null && e1 != null) {
      final d = e1 - e0;
      if (d > 0) {
        segMin += d / 100 * pace.ascentMinPer100m;
      } else {
        segMin += (-d) / 100 * pace.descentMinPer100m;
      }
    }
    // 休息按距离比例分摊。
    segMin +=
        pace.restMinutesTotal *
        (segDistKm *
                1000 /
                ((nodes.last.distFromStartM == 0
                    ? 1
                    : nodes.last.distFromStartM)))
            .clamp(0.0, 1.0);
    elapsedMin += segMin;
    out.add(
      startUtc.add(Duration(milliseconds: (elapsedMin * 60 * 1000).round())),
    );
  }
  return out;
}
