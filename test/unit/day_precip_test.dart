import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/detail_state.dart';

WxProvenance _prov() => WxProvenance(
  providerId: 'open-meteo:best_match',
  vendor: 'Open-Meteo',
  modelOrNetwork: 'best_match',
  modelKnown: false,
  requestLat: 40.16,
  requestLon: 117.4,
  returnedLat: 40.16,
  returnedLon: 117.4,
  locationDetail: null,
  elevationUsedM: null,
  granularity: WxGranularity.grid,
  spatialResolutionNote: null,
  dataKind: WxDataKind.forecast,
  fetchedAtUtc: DateTime.utc(2026, 10, 16),
  modelRunUtc: null,
  utcOffsetSeconds: 0,
  license: 't',
  attribution: 't',
  interpolationNote: null,
  elevationAdjustNote: null,
  traceNote: null,
);

/// 按 2026-10-16 实测蓟县歪顶坨 17 日形态：07–21 时（北京时间）降水、22 时起 0.0 mm 但概率 100%。
/// 北京时间 = UTC+8；Open-Meteo 的 t 表示 t−1h~t 的累计。
WxPointForecast _point(Map<int, double> mmByLocalHourEnd, {double prob = 100}) {
  final dayStartUtc = DateTime.utc(2026, 10, 16, 16); // 17 日 00:00 北京
  return WxPointForecast(
    lat: 40.16,
    lon: 117.4,
    provenance: _prov(),
    hours: [
      for (var h = 0; h <= 25; h++)
        WxHourValue(
          validFromUtc: dayStartUtc.add(Duration(hours: h)),
          values: {
            WxVar.precip: mmByLocalHourEnd[h] ?? 0.0,
            WxVar.precipProb: prob,
          },
        ),
    ],
  );
}

void main() {
  final dayStartUtc = DateTime.utc(2026, 10, 16, 16);

  test('全天合计与降水时段：22 时 0.0 mm 不代表全天无雨', () {
    final rain = {for (var h = 8; h <= 21; h++) h: 5.0}; // 07–21 时每小时 5 mm
    final d = summarizeDayPrecip(
      points: [_point(rain)],
      dayStartUtc: dayStartUtc,
      precedingHour: true,
    );
    expect(d.maxDayMm, 70);
    // 前一小时累计：08:00 记录对应 07–08 时 → 降水从 07 时开始，最后一段为 20–21 时。
    expect(d.firstWetUtc, dayStartUtc.add(const Duration(hours: 7)));
    expect(d.lastWetUtc, dayStartUtc.add(const Duration(hours: 20)));
    expect(d.maxProb, 100);
    expect(d.minHoursCovered, 24);
  });

  test('前一小时语义：00:00 的记录属于前一天，24:00 的记录属于当天', () {
    final d = summarizeDayPrecip(
      points: [
        _point({0: 9.0, 24: 2.0}),
      ],
      dayStartUtc: dayStartUtc,
      precedingHour: true,
    );
    expect(d.maxDayMm, 2.0);
    final same = summarizeDayPrecip(
      points: [
        _point({0: 9.0, 24: 2.0}),
      ],
      dayStartUtc: dayStartUtc,
      precedingHour: false,
    );
    expect(same.maxDayMm, 9.0);
  });

  test('沿途取最大；全无降水量返回 null 而不是 0', () {
    final d = summarizeDayPrecip(
      points: [
        _point({10: 1.0}),
        _point({10: 3.0, 11: 2.0}),
      ],
      dayStartUtc: dayStartUtc,
      precedingHour: true,
    );
    expect(d.maxDayMm, 5.0);

    final none = summarizeDayPrecip(
      points: [
        WxPointForecast(lat: 0, lon: 0, provenance: _prov(), hours: const []),
      ],
      dayStartUtc: dayStartUtc,
      precedingHour: true,
    );
    expect(none.maxDayMm, isNull);
    expect(none.minHoursCovered, 0);
  });
}
