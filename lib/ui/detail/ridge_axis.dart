import 'dart:math' as math;

/// 距离轴使用 1/2/5 的整步长；为终点标签预留空间。
/// 返回内部刻度，起终点由图表单独标注，单位为米。
List<double> ridgeDistanceTicks(double totalM, double width) {
  if (!totalM.isFinite || totalM <= 0 || width < 100) return const [];
  final target = totalM / math.max(2, (width / 44).floor());
  final scale = math.pow(10, (math.log(target) / math.ln10).floor()).toDouble();
  final step = [1, 2, 5, 10].firstWhere((n) => n * scale >= target) * scale;
  return [
    for (var tick = step; tick < totalM; tick += step)
      if (width * (totalM - tick) / totalM >= 52) tick,
  ];
}
