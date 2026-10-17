import 'weather_models.dart';

/// 指标层级（docs/data-hierarchy.md）：决定“怎么展示”，不决定“展示与否”。
///
/// - 决策层缺失时也要显示“未提供”（缺失 ≠ 安全）；
/// - 准备层平时收起，触发阈值时以信号形式升到重点位置；
/// - 参考层只在“更多指标”里出现，缺失时不占格子。
enum WxTier {
  /// 改变“去不去、怎么走、何时折返”：气温/体感、降水、阵风、能见度。
  decide,

  /// 改变“带什么、穿什么”：紫外线、低云、0℃ 层、降雪/积雪、湿度、风向。
  prepare,

  /// 解释与核对：持续风速、气压、总云量、中高云、露点、晴空紫外线、对流潜势等。
  reference,
}

WxTier tierOf(WxVar v) => switch (v) {
  WxVar.temperature ||
  WxVar.apparentTemp ||
  WxVar.precip ||
  WxVar.precipProb ||
  WxVar.windGust ||
  WxVar.visibility => WxTier.decide,
  WxVar.uvIndex ||
  WxVar.cloudLow ||
  WxVar.freezingLevel ||
  WxVar.snowfall ||
  WxVar.snowDepth ||
  WxVar.humidity ||
  WxVar.windDir => WxTier.prepare,
  WxVar.windSpeed ||
  WxVar.pressure ||
  WxVar.cloudCover ||
  WxVar.cloudMid ||
  WxVar.cloudHigh ||
  WxVar.dewPoint ||
  WxVar.uvIndexClearSky ||
  WxVar.snowFraction ||
  WxVar.cape => WxTier.reference,
};

/// 世界卫生组织紫外线分级：0–2 低、3–5 中等、6–7 高、8–10 很高、11+ 极高。
enum UvLevel { low, moderate, high, veryHigh, extreme }

UvLevel uvLevelOf(double uv) => uv < 3
    ? UvLevel.low
    : uv < 6
    ? UvLevel.moderate
    : uv < 8
    ? UvLevel.high
    : uv < 11
    ? UvLevel.veryHigh
    : UvLevel.extreme;

String uvLevelLabel(UvLevel l) => switch (l) {
  UvLevel.low => '低',
  UvLevel.moderate => '中等',
  UvLevel.high => '高',
  UvLevel.veryHigh => '很高',
  UvLevel.extreme => '极高',
};

/// 准备层升为重点的信号种类。
enum WxSignalKind {
  uv,
  uvClearSky,
  snowGlare,
  lowCloud,
  aboveFreezing,
  snowfall,
  snowCover,
  dampCold,
  convective,
}

enum WxSignalLevel { info, caution, warning }

/// 一个被触发的准备层信号：短文案 + 依据（依据只在展开时出现）。
class WxSignal {
  const WxSignal({
    required this.kind,
    required this.level,
    required this.label,
    required this.basis,
  });

  final WxSignalKind kind;
  final WxSignalLevel level;

  /// 6–10 个字以内的短文案，如“紫外线很高 9”。
  final String label;
  final String basis;
}

/// 某节点某时次被触发的准备层信号（按严重程度排序）。缺失变量不触发。
List<WxSignal> signalsFor(WxHourValue wx, {double? elevationM}) {
  final v = wx.values;
  final out = <WxSignal>[];
  final uv = v[WxVar.uvIndex];
  final uvClear = v[WxVar.uvIndexClearSky];
  final snowDepth = v[WxVar.snowDepth];
  final snowfall = v[WxVar.snowfall];
  final hasSnow =
      (snowDepth != null && snowDepth >= 0.01) ||
      (snowfall != null && snowfall >= 0.5);

  if (uv != null && uv >= 6) {
    final level = uvLevelOf(uv);
    out.add(
      WxSignal(
        kind: WxSignalKind.uv,
        level: uv >= 8 ? WxSignalLevel.warning : WxSignalLevel.caution,
        label: '紫外线${uvLevelLabel(level)} ${uv.round()}',
        basis: '世界卫生组织分级：6–7 高，8–10 很高，11 以上极高。海拔每升高约 1000 m，紫外线约增强 10%。',
      ),
    );
  } else if (uv == null && uvClear != null && uvClear >= 6) {
    // 晴空值只说明“若放晴可达”，不是预报值。
    out.add(
      WxSignal(
        kind: WxSignalKind.uvClearSky,
        level: WxSignalLevel.info,
        label: '晴空紫外线可达 ${uvClear.round()}',
        basis: '此来源只提供晴空紫外线（假设无云），不是紫外线预报。',
      ),
    );
  }
  if (hasSnow && uv != null && uv >= 2) {
    out.add(
      const WxSignal(
        kind: WxSignalKind.snowGlare,
        level: WxSignalLevel.caution,
        label: '雪面反光',
        basis: '新雪可反射约 80% 的紫外线（世界卫生组织），需戴墨镜防雪盲。积雪为模式估计。',
      ),
    );
  }
  final fz = v[WxVar.freezingLevel];
  if (fz != null && elevationM != null && elevationM >= fz) {
    out.add(
      WxSignal(
        kind: WxSignalKind.aboveFreezing,
        level: WxSignalLevel.caution,
        label: '高于 0℃ 层',
        basis:
            '节点海拔 ${elevationM.round()} m 高于模型 0℃ 层 ${fz.round()} m：可能结冰或降雪。',
      ),
    );
  }
  if (snowfall != null && snowfall >= 0.5) {
    out.add(
      WxSignal(
        kind: WxSignalKind.snowfall,
        level: WxSignalLevel.caution,
        label: '降雪 ${snowfall.toStringAsFixed(1)} cm/h',
        basis: '单小时新增积雪 ≥ 0.5 cm。',
      ),
    );
  } else if (snowDepth != null && snowDepth >= 0.05) {
    out.add(
      WxSignal(
        kind: WxSignalKind.snowCover,
        level: WxSignalLevel.info,
        label: '积雪约 ${(snowDepth * 100).round()} cm',
        basis: '模式积雪深度 ≥ 5 cm；山区积雪为模型估计，与实际雪况可能差别很大。',
      ),
    );
  }
  final low = v[WxVar.cloudLow];
  if (low != null && low >= 80) {
    out.add(
      WxSignal(
        kind: WxSignalKind.lowCloud,
        level: WxSignalLevel.info,
        label: '低云 ${low.round()}%',
        basis: '低云（约 2 km 以下，含雾）≥ 80%：山脊与垭口可能在云雾中，能见度下降。',
      ),
    );
  }
  final t = v[WxVar.temperature];
  final rh = v[WxVar.humidity];
  if (t != null && rh != null && t <= 5 && rh >= 90) {
    out.add(
      const WxSignal(
        kind: WxSignalKind.dampCold,
        level: WxSignalLevel.info,
        label: '湿冷',
        basis: '气温 ≤ 5 ℃ 且相对湿度 ≥ 90%：体感更冷，衣物受潮后保暖性下降，避免棉质。',
      ),
    );
  }
  final cape = v[WxVar.cape];
  if (cape != null && cape >= 1000) {
    out.add(
      WxSignal(
        kind: WxSignalKind.convective,
        level: WxSignalLevel.info,
        label: '对流潜势${cape >= 2500 ? '强' : '较强'}',
        basis:
            '对流有效位能 ${cape.round()} J/kg（≥ 1000 较强，≥ 2500 强）：大气不稳定，午后易发展雷阵雨。这是潜势，不是雷暴预报。',
      ),
    );
  }
  out.sort((a, b) => b.level.index.compareTo(a.level.index));
  return out;
}
