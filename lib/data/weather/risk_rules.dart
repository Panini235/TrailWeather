import 'weather_models.dart';

/// 自行计算的天气提示（透明、可测试的规则）。
///
/// 边界：
/// - 这些不是官方预警，UI 必须与“官方预警”分开显示；
/// - 官方预警未接入时显示“未接入”，不得显示“无预警”；
/// - 关键数据缺失时提示“信息不足”，不得默认安全；
/// - 不输出无依据的“安全分数”。
enum HintLevel { info, caution, warning }

class WxHint {
  const WxHint({
    required this.id,
    required this.title,
    required this.detail,
    required this.basis,
    required this.level,
  });

  final String id;
  final String title;
  final String detail;

  /// 规则依据（阈值与数据来源说明）。
  final String basis;
  final HintLevel level;
}

class NodeWeatherEntry {
  const NodeWeatherEntry({required this.weather, required this.validUtc});

  /// 可为 null（该节点该时次无数据：超范围/缺失）。
  final WxHourValue? weather;
  final DateTime validUtc;
}

/// 官方预警占位说明（未接入时如实标注）。
const String officialAlertsNotAvailable =
    '官方气象预警：未接入。本页提示为 App 自行计算的阈值参考，不能替代官方预警与户外安全判断。';

/// 计算沿途提示。规则与阈值全部显式给出。
List<WxHint> computeHints({required List<NodeWeatherEntry> entries}) {
  final hints = <WxHint>[];
  final withData = entries.where((e) => e.weather != null).toList();
  if (entries.isEmpty) {
    return const [];
  }
  if (withData.isEmpty) {
    return const [
      WxHint(
        id: 'insufficient',
        title: '信息不足',
        detail: '选定时间没有可用天气数据，无法给出沿途提示。',
        basis: '关键数据缺失时不做任何安全性默认。',
        level: HintLevel.info,
      ),
    ];
  }

  double? maxGust;
  double? maxPrecipProb;
  double? minTemp;
  double? maxTemp;
  var totalPrecip = 0.0;
  var precipSeen = false;
  var missingNodes = entries.length - withData.length;

  for (final e in withData) {
    final w = e.weather!;
    final g = w.values[WxVar.windGust];
    if (g != null && (maxGust == null || g > maxGust)) maxGust = g;
    final pp = w.values[WxVar.precipProb];
    if (pp != null && (maxPrecipProb == null || pp > maxPrecipProb)) {
      maxPrecipProb = pp;
    }
    final pr = w.values[WxVar.precip];
    if (pr != null) {
      precipSeen = true;
      totalPrecip += pr;
    }
    final t = w.values[WxVar.temperature];
    if (t != null) {
      if (minTemp == null || t < minTemp) minTemp = t;
      if (maxTemp == null || t > maxTemp) maxTemp = t;
    }
  }

  if (maxGust != null && maxGust >= 17.2) {
    hints.add(
      WxHint(
        id: 'gust',
        title: '大风提示',
        detail:
            '沿途最大预报阵风约 ${maxGust.toStringAsFixed(1)} m/s（蒲福 ${_bft(maxGust)} 级），山脊与垭口可能更强。',
        basis: '阈值：阵风 ≥ 17.2 m/s（8 级下限）。自行计算，非官方预警。',
        level: HintLevel.warning,
      ),
    );
  }
  if (totalPrecip >= 8 && precipSeen) {
    hints.add(
      WxHint(
        id: 'precip',
        title: '较强降水提示',
        detail:
            '选定时段沿途累计预报降水量约 ${totalPrecip.toStringAsFixed(1)} mm，注意防雨、防滑与溪水上涨。',
        basis: '阈值：时段累计降水 ≥ 8 mm。自行计算，非官方预警。',
        level: HintLevel.caution,
      ),
    );
  }
  if (maxPrecipProb != null && maxPrecipProb >= 70 && !(totalPrecip >= 8)) {
    hints.add(
      WxHint(
        id: 'precip_prob',
        title: '降水概率较高',
        detail:
            '沿途最大降水概率 ${maxPrecipProb.toStringAsFixed(0)}%。降水概率不等于降水量，请同时关注降水量。',
        basis: '阈值：降水概率 ≥ 70%。概率与量为不同指标，分别展示。',
        level: HintLevel.caution,
      ),
    );
  }
  if (minTemp != null && minTemp <= -10) {
    hints.add(
      WxHint(
        id: 'cold',
        title: '低温提示',
        detail: '沿途最低预报气温约 ${minTemp.toStringAsFixed(0)}°C，注意保暖与装备。',
        basis: '阈值：气温 ≤ -10°C。自行计算，非官方预警。',
        level: HintLevel.caution,
      ),
    );
  }
  if (maxTemp != null && maxTemp >= 35) {
    hints.add(
      WxHint(
        id: 'heat',
        title: '高温提示',
        detail: '沿途最高预报气温约 ${maxTemp.toStringAsFixed(0)}°C，注意补水与避开正午。',
        basis: '阈值：气温 ≥ 35°C。自行计算，非官方预警。',
        level: HintLevel.caution,
      ),
    );
  }
  if (missingNodes > 0) {
    hints.add(
      WxHint(
        id: 'partial',
        title: '部分节点无数据',
        detail: '$missingNodes 个节点在选定时间无该来源数据，以上结论不完整。',
        basis: '数据缺失时明确标注，不默认安全。',
        level: HintLevel.info,
      ),
    );
  }
  return hints;
}

int _bft(double ms) {
  final bounds = [
    0.3,
    1.6,
    3.4,
    5.5,
    8.0,
    10.8,
    13.9,
    17.2,
    20.8,
    24.5,
    28.5,
    32.7,
  ];
  for (var i = 0; i < bounds.length; i++) {
    if (ms < bounds[i]) return i;
  }
  return 12;
}

/// 日落相关提示：完成时间晚于日落时提醒。
WxHint? sunsetHint({
  required DateTime finishEtaUtc,
  required DateTime sunsetUtc,
}) {
  if (finishEtaUtc.isAfter(sunsetUtc)) {
    return WxHint(
      id: 'sunset',
      title: '日落后仍在途中',
      detail:
          '按当前配速估算，到达终点时间晚于来源提供的日落时间（${sunsetUtc.toIso8601String()} UTC），请携带照明。',
      basis: '比较：预计到达时间 vs 来源提供的日落时间（如提供）。',
      level: HintLevel.caution,
    );
  }
  return null;
}
