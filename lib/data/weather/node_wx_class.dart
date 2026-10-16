import 'weather_models.dart';

/// 节点天气分类（地图节点颜色/图标用）。
///
/// 只是按固定阈值归类所选来源的单个时次数据，不是安全评分，也不是官方预警。
/// 阈值与 docs/redesign-v2.md 出发窗口一致：阵风 ≥ 13.9 m/s（7 级）黄、
/// ≥ 17.2 m/s（8 级）红；小时降水 ≥ 2 mm 黄；气温 ≤ -10 ℃ 红。
/// 缺失数据不计为“无显著天气”（红线：缺失 ≠ 安全）。
enum NodeWxClass {
  /// 阵风≥ 17.2 m/s。
  galeWind,

  /// 气温 ≤ -10 ℃。
  severeCold,

  /// 小时降水 ≥ 2 mm。
  heavyPrecip,

  /// 阵风≥ 13.9 m/s。
  strongWind,

  /// 小时降水 ≥ 0.1 mm，或降水概率 ≥ 50%。
  precip,

  /// 气温 ≤ 0 ℃。
  freezing,

  /// 关键变量（气温、降水、风）全部有值且未触发以上阈值。
  calm,

  /// 关键变量缺失，无法判断。
  insufficient,

  /// 该时刻没有数据。
  noData,
}

enum NodeWxLevel { red, yellow, info, none, unknown }

extension NodeWxClassInfo on NodeWxClass {
  NodeWxLevel get level => switch (this) {
    NodeWxClass.galeWind || NodeWxClass.severeCold => NodeWxLevel.red,
    NodeWxClass.heavyPrecip || NodeWxClass.strongWind => NodeWxLevel.yellow,
    NodeWxClass.precip || NodeWxClass.freezing => NodeWxLevel.info,
    NodeWxClass.calm => NodeWxLevel.none,
    NodeWxClass.insufficient || NodeWxClass.noData => NodeWxLevel.unknown,
  };

  String get label => switch (this) {
    NodeWxClass.galeWind => '大风（阵风 ≥ 8 级）',
    NodeWxClass.severeCold => '严寒（≤ -10 ℃）',
    NodeWxClass.heavyPrecip => '较强降水（≥ 2 mm/h）',
    NodeWxClass.strongWind => '强风（阵风 ≥ 7 级）',
    NodeWxClass.precip => '降水',
    NodeWxClass.freezing => '低于冰点',
    NodeWxClass.calm => '未触发阈值',
    NodeWxClass.insufficient => '信息不足',
    NodeWxClass.noData => '无数据',
  };
}

NodeWxClass classifyNodeWx(WxHourValue? wx) {
  if (wx == null) return NodeWxClass.noData;
  final v = wx.values;
  final temp = v[WxVar.temperature];
  final precip = v[WxVar.precip];
  final prob = v[WxVar.precipProb];
  // 阵风与持续风速分别建模；缺少阵风就保留未知。
  final wind = v[WxVar.windGust];

  if (wind != null && wind >= 17.2) return NodeWxClass.galeWind;
  if (temp != null && temp <= -10) return NodeWxClass.severeCold;
  if (precip != null && precip >= 2) return NodeWxClass.heavyPrecip;
  if (wind != null && wind >= 13.9) return NodeWxClass.strongWind;
  if ((precip != null && precip >= 0.1) || (prob != null && prob >= 50)) {
    return NodeWxClass.precip;
  }
  if (temp != null && temp <= 0) return NodeWxClass.freezing;
  if (temp == null || precip == null || wind == null) {
    return NodeWxClass.insufficient;
  }
  return NodeWxClass.calm;
}
