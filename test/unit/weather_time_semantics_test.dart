import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_codec.dart';
import 'package:trailweather/ui/map/point_weather_sheet.dart';
import 'package:trailweather/ui/detail/detail_state.dart';

import '../support/departure_fixtures.dart';

void main() {
  test('节点行：整点气温与随后一小时降水/概率/阵风/降雪对齐，跨午夜', () {
    final start = DateTime.utc(2026, 10, 18, 23);
    final bundle = departureBundle(
      start: start,
      hours: 2,
      providerId: 'open-meteo:best_match',
      values: (_, t) => {
        WxVar.temperature: t == start ? 10 : 20,
        WxVar.precip: t == start ? 0 : 8,
        WxVar.precipProb: t == start ? 0 : 90,
        WxVar.windGust: t == start ? 2 : 18,
        WxVar.snowfall: t == start ? 0 : 1,
      },
    );
    final rows = buildNodeRows(
      nodes: departureTestNodes,
      bundle: bundle,
      mode: TimeMode.fixed,
      fixedUtc: start.add(const Duration(minutes: 30)),
      etas: [],
    );
    expect(rows.first.wx!.values[WxVar.temperature], 10);
    expect(rows.first.wx!.values[WxVar.precip], 8);
    expect(rows.first.wx!.values[WxVar.precipProb], 90);
    expect(rows.first.wx!.values[WxVar.windGust], 18);
    expect(rows.first.wx!.values[WxVar.snowfall], 1);
    // 最后一小时没有下一条区间记录，不能回退到上一小时或补 0。
    final last = bundle.result.points.first.hourAt(
      start.add(const Duration(hours: 1)),
    )!;
    expect(last.values[WxVar.temperature], 20);
    expect(last.values[WxVar.precip], isNull);
  });
  test('原始缓存编码往返不偏移，展示序列与单小时查询一致', () {
    final bundle = departureBundle(
      providerId: 'open-meteo:best_match',
      hours: 4,
      values: (_, t) => {
        WxVar.temperature: 10,
        WxVar.precip: t.hour.toDouble(),
      },
    );
    final encoded = WeatherCodec.encode(bundle.result);
    final restored = WeatherCodec.decode(encoded)!;
    final p = restored.points.first;
    expect(p.rawHourAt(departureTestStart)!.values[WxVar.precip], 7);
    expect(p.hourAt(departureTestStart)!.values[WxVar.precip], 8);
    expect(
      p.hourAt(departureTestStart)!.sourceTimesUtc[WxVar.precip],
      departureTestStart.add(const Duration(hours: 1)),
    );
    expect(WeatherCodec.encode(restored), encoded);
    for (final h in p.displayHours) {
      expect(h.values, p.hourAt(h.validFromUtc)!.values);
    }
    // 07:50 仍属于 07–08 的区间，不选更近的 08:00 行。
    expect(
      nearestPointHour(
        p,
        departureTestStart.add(const Duration(minutes: 50)),
      )!.values[WxVar.precip],
      8,
    );
  });

  test('MET 次一小时不偏移；meteoblue 平均风速/风向与降水偏移，瞬时阵风不偏移', () {
    for (final id in ['met.no:locationforecast2.0', 'meteoblue:basic-1h']) {
      final p = departureBundle(
        providerId: id,
        hours: 2,
        values: (_, t) => {
          WxVar.temperature: 10,
          WxVar.precip: t.hour.toDouble(),
          WxVar.precipProb: t.hour.toDouble(),
          WxVar.windSpeed: t.hour.toDouble(),
          WxVar.windDir: t.hour.toDouble(),
          WxVar.windGust: t.hour.toDouble(),
        },
      ).result.points.first;
      final wx = p.hourAt(departureTestStart)!;
      final shifted = id.startsWith('meteoblue:');
      expect(wx.values[WxVar.precip], shifted ? 8 : 7);
      expect(wx.values[WxVar.precipProb], 7);
      if (shifted) {
        expect(wx.precedingThreeHourVariables, contains(WxVar.precipProb));
      }
      expect(wx.values[WxVar.windSpeed], shifted ? 8 : 7);
      expect(wx.values[WxVar.windDir], shifted ? 8 : 7);
      expect(wx.values[WxVar.windGust], 7);
    }
  });

  test('区间来源缺口不拿相邻值补；和风区间未确认则保留原始时次并标注', () {
    final open = departureBundle(
      providerId: 'open-meteo:best_match',
      hours: 2,
      values: (_, t) => {
        WxVar.temperature: 10,
        WxVar.precip: t == departureTestStart ? 9 : null,
      },
    ).result.points.first;
    expect(open.hourAt(departureTestStart)!.values[WxVar.precip], isNull);
    final q = departureBundle(
      providerId: 'qweather:grid-24h',
      hours: 2,
      values: (_, t) => {WxVar.precip: t.hour.toDouble()},
    ).result.points.first.hourAt(departureTestStart)!;
    expect(q.values[WxVar.precip], 7);
    expect(q.unconfirmedIntervalVariables, contains(WxVar.precip));
  });
}
