import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/departure_provider.dart';
import 'package:trailweather/data/weather/departure_windows.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

import '../support/departure_fixtures.dart';

DepartureAssessment assess({
  RouteWeatherBundle? bundle,
  List<RouteNode>? nodes,
  DateTime? start,
  DepartureThresholds thresholds = const DepartureThresholds(),
}) => assessDeparture(
  nodes: nodes ?? departureTestNodes,
  startUtc: start ?? departureTestStart,
  pace: PaceConfig.defaults,
  bundle: bundle ?? departureBundle(),
  thresholds: thresholds,
);

void main() {
  test('完整数据未触发阈值，来源和每个原始时次可追溯', () {
    final result = assess();
    expect(result.level, DepartureLevel.none);
    expect(result.insufficient, false);
    expect(result.finishUtc, departureTestStart.add(const Duration(hours: 1)));
    expect(result.samples.every((s) => s.complete), true);
    expect(
      result.samples.first.point!.provenance.modelOrNetwork,
      'fixture-model',
    );
  });

  test('严格使用已确认阈值，边界包含相等', () {
    for (final (variable, value, level) in [
      (WxVar.windGust, 13.89, DepartureLevel.none),
      (WxVar.windGust, 13.9, DepartureLevel.yellow),
      (WxVar.windGust, 17.2, DepartureLevel.red),
      (WxVar.precip, 1.99, DepartureLevel.none),
      (WxVar.precip, 2.0, DepartureLevel.yellow),
      (WxVar.temperature, -10.0, DepartureLevel.red),
    ]) {
      expect(
        assess(
          bundle: departureBundle(
            values: (i, h) => {...clearDepartureValues(i, h), variable: value},
          ),
        ).level,
        level,
        reason: '$variable $value',
      );
    }
  });

  test('缺阵风不能退用持续风；缺降水不能用概率或0代替', () {
    final result = assess(
      bundle: departureBundle(
        values: (i, h) => {
          WxVar.temperature: 15,
          WxVar.windSpeed: 30,
          WxVar.precipProb: 100,
        },
      ),
    );
    expect(result.insufficient, true);
    expect(result.level, DepartureLevel.none);
    expect(result.missingValues[WxVar.windGust], greaterThan(0));
    expect(result.missingValues[WxVar.precip], greaterThan(0));
    expect(result.label, '信息不足');
  });

  test('已知红色阈值与缺口同时保留，NaN 不当作完整值', () {
    final result = assess(
      bundle: departureBundle(
        values: (i, h) => {
          WxVar.temperature: -12,
          WxVar.precip: double.nan,
          WxVar.windGust: null,
        },
      ),
    );
    expect(result.level, DepartureLevel.red);
    expect(result.insufficient, true);
    expect(result.label, contains('信息不足'));
  });

  test('段中出现阵风，即使两端ETA天气平静也检出', () {
    final nodes = [
      departureTestNodes.first,
      const RouteNode(
        pointIndex: 1,
        pos: LatLng(30, .2),
        elevationM: 100,
        distFromStartM: 10800,
      ),
    ];
    final result = assess(
      nodes: nodes,
      bundle: departureBundle(
        nodes: nodes,
        values: (i, h) => {
          ...clearDepartureValues(i, h),
          WxVar.windGust: h.hour == 8 ? 20 : 5,
        },
      ),
    );
    expect(result.finishUtc.hour, 10);
    expect(result.findings.single.sample!.hourUtc.hour, 8);
    expect(result.level, DepartureLevel.red);
  });

  test('Open-Meteo上一小时累计按原始时次对齐，不算出发前和抵达后降水', () {
    final raw = departureBundle(
      providerId: 'open-meteo:best_match',
      values: (i, h) => {
        ...clearDepartureValues(i, h),
        WxVar.precip: h.hour == 8 ? 0 : 40,
      },
    );
    expect(assess(bundle: raw).level, DepartureLevel.none);
    final rain = assess(
      bundle: departureBundle(
        providerId: 'open-meteo:best_match',
        values: (i, h) => {
          ...clearDepartureValues(i, h),
          WxVar.precip: h.hour == 8 ? 2 : 0,
        },
      ),
    );
    final f = rain.findings.single;
    expect(f.sample!.hourUtc.hour, 7);
    expect(f.sample!.sourceTimesUtc[WxVar.precip]!.hour, 8);
  });

  test('整点抵达的瞬时低温也会被检出', () {
    final result = assess(
      bundle: departureBundle(
        values: (i, h) => {
          ...clearDepartureValues(i, h),
          WxVar.temperature: h.hour == 8 && i == 1 ? -15 : 10,
        },
      ),
    );
    expect(result.level, DepartureLevel.red);
    expect(result.findings.single.sample!.instantOnly, true);
  });

  test('逐节点映射可反向/共享；缺映射信息不足而不崩溃', () {
    final mapped = assess(
      bundle: departureBundle(
        nodeMap: [1, 0],
        values: (i, h) => {
          ...clearDepartureValues(i, h),
          WxVar.windGust: i == 0 ? 19 : 5,
        },
      ),
    );
    expect(mapped.findings.first.sample!.nodeIndex, 1);
    expect(mapped.findings.first.sample!.point!.provenance.requestLon, 0);
    expect(assess(bundle: departureBundle(nodeMap: [0])).insufficient, true);
  });

  test('超出实际小时范围、缺日落、旧缓存和刷新失败均不标成完整', () {
    for (final bundle in [
      departureBundle(hours: 0),
      departureBundle(sunsets: false),
      departureBundle(stale: true),
      departureBundle(refreshFailed: true),
      departureBundle(kind: WxDataKind.observation),
    ]) {
      expect(assess(bundle: bundle).insufficient, true);
    }
  });

  test('晚于日落的出发不能误取第二天日落；刚好到达日落不算晚于', () {
    final after = assess(start: DateTime.utc(2026, 10, 17, 19));
    expect(after.sunsetUtc, DateTime.utc(2026, 10, 17, 18));
    expect(after.level, DepartureLevel.yellow);
    expect(
      assess(start: DateTime.utc(2026, 10, 17, 17)).level,
      DepartureLevel.none,
    );
    final overnight = assess(start: DateTime.utc(2026, 10, 17, 23, 30));
    expect(overnight.level, DepartureLevel.yellow);
    expect(overnight.gaps.any((s) => s.contains('跨夜')), true);
  });

  test('日落日期归属按线路经度，跨UTC日期不取明天', () {
    final nodes = [
      for (var i = 0; i < 2; i++)
        RouteNode(
          pointIndex: i,
          pos: const LatLng(40, -120),
          elevationM: 100,
          distFromStartM: i * 3600,
        ),
    ];
    final raw = departureBundle(nodes: nodes);
    final points = [
      for (final p in raw.result.points)
        WxPointForecast(
          lat: p.lat,
          lon: p.lon,
          hours: p.hours,
          provenance: p.provenance,
          dailySunsetsUtc: [
            DateTime.utc(2026, 10, 18, 1),
            DateTime.utc(2026, 10, 19, 1),
          ],
        ),
    ];
    final bundle = RouteWeatherBundle(
      nodeQueryIndex: [0, 1],
      result: WxSourceResult(
        providerId: raw.result.providerId,
        points: points,
        fromCache: false,
        stale: false,
        cachedAtUtc: null,
        fetchedAtUtc: raw.result.fetchedAtUtc,
      ),
    );
    expect(
      assess(
        nodes: nodes,
        start: DateTime.utc(2026, 10, 18, 2),
        bundle: bundle,
      ).sunsetUtc,
      DateTime.utc(2026, 10, 18, 1),
    );
  });

  test('大于24小时行程不静默裁剪天气窗', () {
    final nodes = [
      departureTestNodes.first,
      const RouteNode(
        pointIndex: 1,
        pos: LatLng(30, .2),
        elevationM: 100,
        distFromStartM: 100000,
      ),
    ];
    final result = assess(nodes: nodes);
    expect(result.samples, isEmpty);
    expect(result.gaps.first, contains('24 小时'));
    expect(result.insufficient, true);
  });

  test('阈值持久化向后兼容，非法阈值回退但不丢弃原偏好', () {
    expect(
      AppSettings.fromJson({'lowPower': true}).departureThresholds.gustRed,
      17.2,
    );
    const t = DepartureThresholds(
      gustYellow: 10,
      gustRed: 15,
      precipYellow: 1,
      coldRed: -5,
    );
    final restored = AppSettings.fromJson(
      const AppSettings(lowPower: true, departureThresholds: t).toJson(),
    );
    expect(restored.departureThresholds.toJson(), t.toJson());
    expect(restored.lowPower, true);
    expect(
      DepartureThresholds.fromJson({'gustYellow': 20, 'gustRed': 10}).gustRed,
      17.2,
    );
    expect(
      DepartureThresholds.fromJson({'gustYellow': double.nan}).isValid,
      true,
    );
    expect(
      assess(thresholds: const DepartureThresholds(gustYellow: 5, gustRed: 6))
          .level,
      DepartureLevel.red,
    );
  });

  test('请求身份包含节点顺序和海拔，拷贝节点相等', () {
    DepartureFetchKey key(List<RouteNode> nodes) => DepartureFetchKey(
      nodes: nodes,
      providerId: 'test',
      startUtc: departureTestStart,
      endUtc: departureTestStart.add(const Duration(days: 3)),
    );
    expect(key(departureTestNodes), key(List.of(departureTestNodes)));
    expect(
      key(departureTestNodes),
      isNot(key(departureTestNodes.reversed.toList())),
    );
    final nodes = [
      const RouteNode(
        pointIndex: 0,
        pos: LatLng(30, 0),
        elevationM: 200,
        distFromStartM: 0,
      ),
      departureTestNodes.last,
    ];
    expect(key(nodes), isNot(key(departureTestNodes)));
  });
}
