import '../routes/route_sampling.dart';
import 'eta.dart';
import 'weather_models.dart';
import 'weather_repository.dart';

/// 独立于节点图例的可调出发规则，单位固定为 m/s、mm/h、℃。
class DepartureThresholds {
  const DepartureThresholds({
    this.gustYellow = 13.9,
    this.gustRed = 17.2,
    this.precipYellow = 2,
    this.coldRed = -10,
  });

  final double gustYellow;
  final double gustRed;
  final double precipYellow;
  final double coldRed;

  bool get isValid =>
      [gustYellow, gustRed, precipYellow, coldRed].every((v) => v.isFinite) &&
      gustYellow > 0 &&
      gustYellow < gustRed &&
      gustRed <= 100 &&
      precipYellow > 0 &&
      precipYellow <= 200 &&
      coldRed >= -80 &&
      coldRed <= 10;

  Map<String, double> toJson() => {
    'gustYellow': gustYellow,
    'gustRed': gustRed,
    'precipYellow': precipYellow,
    'coldRed': coldRed,
  };

  static DepartureThresholds fromJson(Object? json) {
    if (json is! Map) return const DepartureThresholds();
    double read(String k, double fallback) =>
        json[k] is num ? (json[k] as num).toDouble() : fallback;
    final result = DepartureThresholds(
      gustYellow: read('gustYellow', 13.9),
      gustRed: read('gustRed', 17.2),
      precipYellow: read('precipYellow', 2),
      coldRed: read('coldRed', -10),
    );
    return result.isValid ? result : const DepartureThresholds();
  }
}

enum DepartureLevel { none, yellow, red }

const departureRequiredVars = [WxVar.temperature, WxVar.precip, WxVar.windGust];

DateTime departureHour(DateTime time) {
  final t = time.toUtc();
  return DateTime.utc(t.year, t.month, t.day, t.hour);
}

/// 一段经过时窗的一个端点抽样。保留各变量原始有效时间，不能将累积量当瞬时值。
class DepartureSample {
  const DepartureSample({
    required this.nodeIndex,
    required this.hourUtc,
    required this.point,
    required this.values,
    required this.sourceTimesUtc,
    this.instantOnly = false,
  });
  final bool instantOnly;
  final int nodeIndex;
  final DateTime hourUtc;
  final WxPointForecast? point;
  final Map<WxVar, double?> values;
  final Map<WxVar, DateTime> sourceTimesUtc;
  bool get complete => sourceTimesUtc.keys.every((v) => values[v] != null);
}

class DepartureFinding {
  const DepartureFinding({
    required this.level,
    required this.reason,
    this.sample,
    this.variable,
    this.sunsetUtc,
  });
  final DepartureLevel level;
  final String reason;
  final DepartureSample? sample;
  final WxVar? variable;
  final DateTime? sunsetUtc;
}

class DepartureAssessment {
  const DepartureAssessment({
    required this.startUtc,
    required this.etasUtc,
    required this.samples,
    required this.findings,
    required this.gaps,
    required this.missingValues,
    required this.bundle,
    required this.sunsetUtc,
  });
  final DateTime startUtc;
  final List<DateTime> etasUtc;
  final List<DepartureSample> samples;
  final List<DepartureFinding> findings;
  final List<String> gaps;
  final Map<WxVar, int> missingValues;
  final RouteWeatherBundle bundle;
  final DateTime? sunsetUtc;
  DateTime get finishUtc => etasUtc.isEmpty ? startUtc : etasUtc.last;
  bool get insufficient =>
      gaps.isNotEmpty || missingValues.values.any((n) => n > 0);
  DepartureLevel get level => findings.fold(
    DepartureLevel.none,
    (level, f) => f.level.index > level.index ? f.level : level,
  );
  String get label => switch (level) {
    DepartureLevel.red => insufficient ? '红色阈值 · 信息不足' : '触发红色阈值',
    DepartureLevel.yellow => insufficient ? '黄色阈值 · 信息不足' : '触发黄色阈值',
    DepartureLevel.none => insufficient ? '信息不足' : '未触发阈值',
  };
}

WxPointForecast? departurePoint(RouteWeatherBundle bundle, int nodeIndex) {
  if (nodeIndex >= bundle.nodeQueryIndex.length) return null;
  final index = bundle.nodeQueryIndex[nodeIndex];
  if (index < 0 || index >= bundle.result.points.length) return null;
  final p = bundle.result.points[index];
  // 观测不能充当未来预报；错配来源不能作为当前格子的证据。
  if (p.provenance.dataKind != WxDataKind.forecast ||
      p.provenance.providerId != bundle.result.providerId) {
    return null;
  }
  return p;
}

/// 连续行走上限为 24 小时；更长的路线需先按营地/日程拆分（T-147）。
/// 每个线段在所有经过小时检查两个端点，避免只看 ETA 而漏掉段中天气。
DepartureAssessment assessDeparture({
  required List<RouteNode> nodes,
  required DateTime startUtc,
  required PaceConfig pace,
  required RouteWeatherBundle bundle,
  DepartureThresholds thresholds = const DepartureThresholds(),
}) {
  if (!thresholds.isValid) throw ArgumentError('无效的出发阈值');
  final start = startUtc.toUtc();
  final etas = computeEtas(nodes: nodes, startUtc: start, pace: pace);
  final samples = <DepartureSample>[];
  final findings = <DepartureFinding>[];
  final gaps = <String>[];
  final missing = {for (final v in departureRequiredVars) v: 0};
  final seen = <(int, DateTime, bool)>{};
  final extremes = <WxVar, DepartureSample>{};
  final finish = etas.isEmpty ? start : etas.last;

  void add(int node, DateTime hour, {bool instantOnly = false}) {
    if (!seen.add((node, hour, instantOnly))) return;
    final point = departurePoint(bundle, node);
    final values = <WxVar, double?>{};
    final times = <WxVar, DateTime>{};
    for (final v in instantOnly ? [WxVar.temperature] : departureRequiredVars) {
      final wx = point?.hourAt(hour);
      times[v] = wx?.sourceTimesUtc[v] ?? hour;
      final raw = wx?.values[v];
      final value =
          raw != null && raw.isFinite && (v == WxVar.temperature || raw >= 0)
          ? raw
          : null;
      values[v] = value;
      if (value == null) missing[v] = missing[v]! + 1;
    }
    final sample = DepartureSample(
      nodeIndex: node,
      instantOnly: instantOnly,
      hourUtc: hour,
      point: point,
      values: Map.unmodifiable(values),
      sourceTimesUtc: Map.unmodifiable(times),
    );
    samples.add(sample);
    for (final v in departureRequiredVars) {
      final value = values[v];
      if (value == null) continue;
      final old = extremes[v]?.values[v];
      if (old == null || (v == WxVar.temperature ? value < old : value > old)) {
        extremes[v] = sample;
      }
    }
  }

  if (nodes.isEmpty) {
    gaps.add('线路没有可用采样节点');
  } else if (finish.difference(start) > const Duration(hours: 24)) {
    gaps.add('预计连续行程超过 24 小时，需先拆分每日行程');
  } else {
    for (var i = 0; i < nodes.length; i++) {
      // 整点到达终点只补气温瞬时值，不把抵达后的一小时降水算在途内。
      if (i == nodes.length - 1 && departureHour(etas[i]) == etas[i]) {
        add(i, departureHour(etas[i]), instantOnly: true);
      }
      if (nodes.length == 1) add(i, departureHour(etas[i]));
      if (i == 0) continue;
      for (
        var h = departureHour(etas[i - 1]);
        h.isBefore(etas[i]);
        h = h.add(const Duration(hours: 1))
      ) {
        add(i - 1, h);
        add(i, h);
      }
    }
    void weather(WxVar v, DepartureLevel level, String reason) {
      findings.add(
        DepartureFinding(
          level: level,
          reason: reason,
          sample: extremes[v],
          variable: v,
        ),
      );
    }

    final gust = extremes[WxVar.windGust]?.values[WxVar.windGust];
    if (gust != null && gust >= thresholds.gustYellow) {
      final red = gust >= thresholds.gustRed;
      weather(
        WxVar.windGust,
        red ? DepartureLevel.red : DepartureLevel.yellow,
        '最大阵风 ${gust.toStringAsFixed(1)} m/s ≥ ${red ? thresholds.gustRed : thresholds.gustYellow} m/s',
      );
    }
    final rain = extremes[WxVar.precip]?.values[WxVar.precip];
    if (rain != null && rain >= thresholds.precipYellow) {
      weather(
        WxVar.precip,
        DepartureLevel.yellow,
        '小时降水 ${rain.toStringAsFixed(1)} mm ≥ ${thresholds.precipYellow} mm',
      );
    }
    final cold = extremes[WxVar.temperature]?.values[WxVar.temperature];
    if (cold != null && cold <= thresholds.coldRed) {
      weather(
        WxVar.temperature,
        DepartureLevel.red,
        '最低气温 ${cold.toStringAsFixed(1)} ℃ ≤ ${thresholds.coldRed} ℃',
      );
    }
  }

  DateTime? sunset;
  if (nodes.isNotEmpty) {
    final day = departureSolarDate(start, nodes.last.pos.longitude);
    sunset = departureDaySunset(
      point: departurePoint(bundle, nodes.length - 1),
      longitude: nodes.last.pos.longitude,
      startUtc: start,
    );
    if (sunset == null) {
      gaps.add('日落：此来源未提供出发日终点的可用日落时间');
    } else if (finish.isAfter(sunset)) {
      findings.add(
        DepartureFinding(
          level: DepartureLevel.yellow,
          reason: '预计到达晚于出发日终点日落',
          sunsetUtc: sunset,
        ),
      );
    }
    if (departureSolarDate(finish, nodes.last.pos.longitude) != day) {
      gaps.add('跨夜行程尚未按日拆分，需另行核对夜间安排');
    }
    if (nodes.any((n) => n.elevationM == null)) {
      gaps.add('部分轨迹海拔缺失，ETA 未计入这些路段的爬升/下降影响');
    }
  }
  if (bundle.result.stale) gaps.add('旧缓存尚未更新，阈值仅反映已保存预报');
  if (bundle.result.refreshFailed) gaps.add('刷新失败，继续显示上次保存的预报');
  samples.sort((a, b) {
    final node = a.nodeIndex.compareTo(b.nodeIndex);
    return node == 0 ? a.hourUtc.compareTo(b.hourUtc) : node;
  });
  return DepartureAssessment(
    startUtc: start,
    etasUtc: List.unmodifiable(etas),
    samples: List.unmodifiable(samples),
    findings: List.unmodifiable(findings),
    gaps: List.unmodifiable(gaps),
    missingValues: Map.unmodifiable(missing),
    bundle: bundle,
    sunsetUtc: sunset,
  );
}

/// 经度仅用于日落的日期归属近似，不是时区或日落时间推算。
DateTime departureSolarDate(DateTime time, double longitude) {
  final local = time.toUtc().add(Duration(seconds: (longitude * 240).round()));
  return DateTime.utc(local.year, local.month, local.day);
}

DateTime? departureDaySunset({
  required WxPointForecast? point,
  required double longitude,
  required DateTime startUtc,
}) {
  final day = departureSolarDate(startUtc, longitude);
  final candidates =
      point?.dailySunsetsUtc
          .where((s) => departureSolarDate(s, longitude) == day)
          .toList() ??
      [];
  return candidates.length == 1 ? candidates.single.toUtc() : null;
}
