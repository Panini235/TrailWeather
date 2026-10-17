import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/wx_http.dart';
import 'package:trailweather/data/weather/met_norway_provider.dart';
import 'package:trailweather/data/weather/open_meteo_provider.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';

/// 以下 fixture 依据 2026-10-13 对真实 API 的实测响应结构制作（脱敏精简），
/// 用于日常 CI 的可追溯契约测试；真实联网 smoke 测试单独配置（.github/workflows/live-smoke.yml）。

const openMeteoMultiPointFixture = '''
[
  {
    "latitude": 40.03515,
    "longitude": 116.18182,
    "utc_offset_seconds": 0,
    "timezone": "GMT",
    "elevation": 126.0,
    "hourly_units": {"temperature_2m": "°C", "wind_speed_10m": "km/h", "precipitation": "mm"},
    "hourly": {
      "time": ["2026-10-13T00:00", "2026-10-13T01:00"],
      "temperature_2m": [12.5, 11.0],
      "apparent_temperature": [10.1, 9.0],
      "precipitation": [0.0, 0.2],
      "precipitation_probability": [10, 30],
      "wind_speed_10m": [8.6, 9.4],
      "wind_gusts_10m": [20.2, 25.0],
      "wind_direction_10m": [270, 275],
      "relative_humidity_2m": [40, 45],
      "cloud_cover": [20, 80],
      "visibility": [24000, 10000],
      "surface_pressure": [1013, 1012],
      "uv_index": [0.25, 0.15],
      "uv_index_clear_sky": [3.25, 3.75],
      "cloud_cover_low": [100, 100],
      "cloud_cover_mid": [100, 100],
      "cloud_cover_high": [100, 98],
      "dew_point_2m": [10.6, 10.9],
      "snow_depth": [0.0, 0.0],
      "cape": [0.0, 30.0]
    },
    "daily": {"time": ["2026-10-13"], "sunrise": ["2026-10-12T22:23"], "sunset": ["2026-10-13T09:58"]}
  },
  {
    "latitude": 40.0625,
    "longitude": 116.3125,
    "utc_offset_seconds": 0,
    "elevation": 210.0,
    "hourly": {
      "time": ["2026-10-13T00:00", "2026-10-13T01:00"],
      "temperature_2m": [11.5, 10.0],
      "precipitation_probability": [5, 10]
    },
    "daily": {"time": ["2026-10-13"], "sunset": ["2026-10-13T09:58"]}
  }
]
''';

const openMeteoMissingFieldsFixture = '''
{
  "latitude": 40.0,
  "longitude": 116.2,
  "utc_offset_seconds": 28800,
  "elevation": 150.0,
  "hourly": {
    "time": ["2026-10-13T00:00"],
    "temperature_2m": [12.5]
  }
}
''';

const metNorwayFixture = '''
{
  "type": "Feature",
  "geometry": {"type": "Point", "coordinates": [116.19, 39.99, 125]},
  "properties": {
    "meta": {
      "updated_at": "2026-10-13T11:24:26Z",
      "units": {"air_temperature": "celsius", "wind_speed": "m/s", "precipitation_amount": "mm", "ultraviolet_index_clear_sky": "1"}
    },
    "timeseries": [
      {
        "time": "2026-10-13T11:00:00Z",
        "data": {
          "instant": {"details": {
            "air_temperature": 15.5, "apparent_air_temperature": 14.4, "wind_speed": 3.0,
            "wind_from_direction": 273.8, "relative_humidity": 24.7,
            "cloud_area_fraction": 0.0, "cloud_area_fraction_low": 0.0,
            "cloud_area_fraction_medium": 0.0, "cloud_area_fraction_high": 0.0,
            "dew_point_temperature": -4.6, "fog_area_fraction": 0.0,
            "ultraviolet_index_clear_sky": 0.5, "air_pressure_at_sea_level": 1022.2
          }},
          "next_1_hours": {"summary": {"symbol_code": "clearsky_day"}, "details": {"precipitation_amount": 0.0}}
        }
      },
      {
        "time": "2026-10-13T12:00:00Z",
        "data": {
          "instant": {"details": {
            "air_temperature": 17.0, "wind_speed": 4.5, "wind_gust": 9.2,
            "wind_from_direction": 280.0, "relative_humidity": 20.0,
            "cloud_area_fraction": 10.0
          }},
          "next_1_hours": {"summary": {"symbol_code": "fair_day"}, "details": {"precipitation_amount": 0.3}}
        }
      }
    ]
  }
}
''';

/// 单点、日期为今天的最小响应（用于“今天已过去的小时”用例）。
String openMeteoSinglePointToday() {
  final now = DateTime.now().toUtc();
  final d =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  return '[{"latitude":40.0,"longitude":116.0,"utc_offset_seconds":0,'
      '"elevation":100.0,"hourly":{"time":["${d}T00:00","${d}T01:00"],'
      '"temperature_2m":[10.0,11.0]},"daily":{"time":["$d"],"sunset":["${d}T09:58"]}}]';
}

void main() {
  group('OpenMeteoProvider 契约', () {
    test('多坐标批量：解析数组、溯源字段完整', () async {
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async {
          expect(uri.host, 'api.open-meteo.com');
          expect(uri.queryParameters['timezone'], 'UTC');
          expect(uri.queryParameters['models'], 'best_match');
          expect(uri.queryParameters['latitude']!.contains(','), isTrue);
          return openMeteoMultiPointFixture;
        },
      );
      final pts = [const LatLng(40.0, 116.18), const LatLng(40.06, 116.31)];
      final now = DateTime.now().toUtc();
      final out = await p.fetchPoints(
        points: pts,
        startUtc: now,
        endUtc: now.add(const Duration(days: 1)),
      );
      expect(out, hasLength(2));

      final first = out.first;
      expect(first.hours, hasLength(2));
      // 时间解析为 UTC（无后缀 + timezone=UTC）
      expect(first.hours.first.validFromUtc, DateTime.utc(2026, 10, 13, 0));
      // 单位换算：来源 wind km/h -> 内部 m/s
      expect(
        first.hours.first.values[WxVar.windSpeed],
        closeTo(8.6 / 3.6, 0.01),
      );
      expect(
        first.hours.first.values[WxVar.windGust],
        closeTo(20.2 / 3.6, 0.01),
      );
      expect(first.hours.first.values[WxVar.temperature], 12.5);
      expect(first.hours.first.values[WxVar.precipProb], 10);
      expect(first.dailySunsetsUtc, [DateTime.utc(2026, 10, 13, 9, 58)]);
      expect(first.dailySunrisesUtc, [DateTime.utc(2026, 10, 12, 22, 23)]);
      // 出发那天的日出：凌晨出发（日出前）同样取当天日出
      expect(
        first.sunriseNear(DateTime.utc(2026, 10, 12, 21)),
        DateTime.utc(2026, 10, 12, 22, 23),
      );
      expect(first.sunriseNear(DateTime.utc(2026, 10, 14, 12)), isNull);
      // 紫外线：预报值与晴空值是两个变量（阴天 0.25 vs 晴空 3.25）
      final h0 = first.hours.first.values;
      expect(h0[WxVar.uvIndex], 0.25);
      expect(h0[WxVar.uvIndexClearSky], 3.25);
      expect(h0[WxVar.cloudLow], 100);
      expect(h0[WxVar.cloudHigh], 100);
      expect(h0[WxVar.dewPoint], 10.6);
      expect(h0[WxVar.snowDepth], 0.0);
      expect(h0[WxVar.cape], 0.0);
      // 取“出发后的第一次日落”，而不是固定取第一天
      expect(
        first.nextSunsetAfter(DateTime.utc(2026, 10, 13, 1)),
        DateTime.utc(2026, 10, 13, 9, 58),
      );
      expect(first.nextSunsetAfter(DateTime.utc(2026, 10, 13, 12)), isNull);

      // 溯源：请求坐标 vs 返回坐标分开保存
      final prov = first.provenance;
      expect(prov.requestLat, 40.0);
      expect(prov.returnedLat, closeTo(40.03515, 1e-5));
      expect(prov.returnedLat, isNot(prov.requestLat));
      expect(prov.elevationUsedM, 126.0);
      expect(prov.granularity, WxGranularity.grid);
      expect(prov.modelKnown, isFalse); // best_match 未随响应返回具体模型
      expect(prov.granularityStatement(), contains('非点位实测'));

      // 缺失字段保持 null（第二个点只有部分字段）
      final second = out[1];
      expect(second.hours.first.values[WxVar.apparentTemp], isNull);
      expect(second.hours.first.values[WxVar.precip], isNull);
      expect(second.hours.first.values[WxVar.temperature], 11.5);
      expect(second.hours.first.values[WxVar.uvIndex], isNull);
      expect(second.dailySunrisesUtc, isEmpty);
    });

    test('缺失字段 fixture：全部保持 null，绝不为 0', () async {
      final p = OpenMeteoProvider(
        model: 'ecmwf_ifs025',
        fetcher: (uri, {headers, cancelToken}) async =>
            openMeteoMissingFieldsFixture,
      );
      final out = await p.fetchPoints(
        points: [const LatLng(40, 116.2)],
        startUtc: DateTime.now().toUtc(),
        endUtc: DateTime.now().toUtc().add(const Duration(days: 1)),
      );
      expect(out, hasLength(1));
      final h = out.first.hours.first;
      expect(h.values[WxVar.precip], isNull);
      expect(h.values[WxVar.precipProb], isNull);
      expect(h.values[WxVar.windGust], isNull);
      expect(h.values[WxVar.visibility], isNull);
      // utc_offset_seconds 保留
      expect(out.first.provenance.utcOffsetSeconds, 28800);
      // ecmwf 模型名已知
      expect(out.first.provenance.modelKnown, isTrue);
    });

    test('响应点数不符抛异常', () async {
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async =>
            openMeteoMultiPointFixture,
      );
      final now = DateTime.now().toUtc();
      expect(
        () => p.fetchPoints(
          points: [const LatLng(40, 116)],
          startUtc: now,
          endUtc: now.add(const Duration(days: 1)),
        ),
        throwsA(isA<SourceHttpException>()),
      );
    });

    test('今天已过去的小时仍可请求（预报从当天 00:00 UTC 起）', () async {
      Uri? requested;
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async {
          requested = uri;
          return openMeteoSinglePointToday();
        },
      );
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day);
      await p.fetchPoints(
        points: [const LatLng(40, 116)],
        startUtc: today,
        endUtc: today.add(const Duration(hours: 1)),
      );
      expect(requested!.queryParameters['forecast_days'], '1');
    });

    test('早于今天的时段抛 WxOutOfRange（不再误报“超过 16 天”）', () async {
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async =>
            openMeteoMultiPointFixture,
      );
      final now = DateTime.now().toUtc();
      final yesterday = DateTime.utc(now.year, now.month, now.day - 1, 10);
      expect(
        () => p.fetchPoints(
          points: [const LatLng(40, 116)],
          startUtc: yesterday,
          endUtc: yesterday.add(const Duration(hours: 1)),
        ),
        throwsA(
          isA<WxOutOfRange>().having(
            (e) => e.message,
            'message',
            contains('早于今天'),
          ),
        ),
      );
    });

    test('超 16 天窗口抛 WxOutOfRange', () async {
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async =>
            openMeteoMultiPointFixture,
      );
      expect(
        () => p.fetchPoints(
          points: [const LatLng(40, 116)],
          startUtc: DateTime.now().toUtc().add(const Duration(days: 20)),
          endUtc: DateTime.now().toUtc().add(const Duration(days: 21)),
        ),
        throwsA(isA<WxOutOfRange>()),
      );
    });

    test('能力声明如实', () {
      final p = OpenMeteoProvider(model: 'best_match');
      final c = p.caps;
      expect(c.requiresApiKey, isFalse);
      expect(c.browserCorsOk, isTrue);
      expect(c.batchCoordinates, isTrue);
      expect(c.modelOverlapNote, isNotNull); // 必须有模型重叠提示
    });
  });

  group('MetNorwayProvider 契约', () {
    test('解析 complete 响应、溯源与缺失标注', () async {
      Uri? seenUri;
      Map<String, String>? seenHeaders;
      final p = MetNorwayProvider(
        fetcher: (uri, {headers, cancelToken}) async {
          seenUri = uri;
          seenHeaders = headers;
          return metNorwayFixture;
        },
      );
      final out = await p.fetchPoints(
        points: [const LatLng(39.99, 116.19)],
        startUtc: DateTime.utc(2026, 10, 13),
        endUtc: DateTime.utc(2026, 10, 14),
      );
      expect(out, hasLength(1));

      // 非浏览器环境必须携带 User-Agent（服务条款要求）
      expect(seenHeaders?['User-Agent'], contains('TrailWeather'));
      expect(seenUri!.host, 'api.met.no');
      expect(seenUri!.path, endsWith('/complete'));

      final pt = out.first;
      expect(pt.hours, hasLength(2));
      final h0 = pt.hours[0];
      expect(h0.values[WxVar.temperature], 15.5);
      expect(h0.values[WxVar.windSpeed], 3.0); // m/s 直存
      expect(h0.values[WxVar.precip], 0.0);
      expect(h0.symbols?['met_symbol'], 'clearsky_day');
      // complete 多出的字段
      expect(h0.values[WxVar.apparentTemp], 14.4);
      expect(h0.values[WxVar.dewPoint], -4.6);
      expect(h0.values[WxVar.cloudLow], 0.0);
      // 只有晴空紫外线：不得写进紫外线预报
      expect(h0.values[WxVar.uvIndexClearSky], 0.5);
      expect(h0.values[WxVar.uvIndex], isNull);
      // 仍无：降水概率 / 能见度
      expect(h0.values[WxVar.precipProb], isNull);
      expect(h0.values[WxVar.visibility], isNull);
      // 第二时次缺体感温度 → null，不沿用上一时次
      expect(pt.hours[1].values[WxVar.apparentTemp], isNull);
      // 第二时次有阵风
      expect(pt.hours[1].values[WxVar.windGust], 9.2);

      final prov = pt.provenance;
      expect(prov.modelRunUtc, DateTime.utc(2026, 10, 13, 11, 24, 26));
      expect(prov.modelKnown, isFalse); // 响应未标注具体模型
      expect(prov.returnedLat, isNull); // 返回坐标为请求原样，不冒充实际网格坐标
      expect(prov.locationDetail, contains('请求坐标原样'));
      expect(prov.granularityStatement(), contains('网格预报'));
      expect(prov.granularityStatement(), contains('9–22 km'));
      expect(prov.elevationUsedM, isNull); // 未提供来源使用海拔
    });

    test('空 timeseries 不崩溃', () async {
      final p = MetNorwayProvider(
        fetcher: (uri, {headers, cancelToken}) async =>
            '{"properties":{"meta":{},"timeseries":[]}}',
      );
      final out = await p.fetchPoints(
        points: [const LatLng(39.99, 116.19)],
        startUtc: DateTime.utc(2026, 10, 13),
        endUtc: DateTime.utc(2026, 10, 14),
      );
      expect(out.first.hours, isEmpty);
    });

    test('能力声明如实（含 Web UA 限制标注）', () {
      final p = MetNorwayProvider();
      final c = p.caps;
      expect(c.requiresApiKey, isFalse);
      expect(c.supports(WxVar.apparentTemp), isTrue);
      expect(c.supports(WxVar.uvIndex), isFalse);
      expect(c.supports(WxVar.uvIndexClearSky), isTrue);
      expect(c.supports(WxVar.precipProb), isFalse);
      expect(c.supports(WxVar.windGust), isTrue); // 部分时次提供
      expect(c.modelOverlapNote, contains('ECMWF'));
    });

    test('损坏 JSON 抛 FormatException（由上层转为来源失败态）', () async {
      final p = MetNorwayProvider(
        fetcher: (uri, {headers, cancelToken}) async => 'not-json',
      );
      expect(
        () => p.fetchPoints(
          points: [const LatLng(39.99, 116.19)],
          startUtc: DateTime.utc(2026, 10, 13),
          endUtc: DateTime.utc(2026, 10, 14),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('fixture 可被 jsonDecode（数据完整性哨兵）', () {
    expect(jsonDecode(openMeteoMultiPointFixture), isA<List>());
    expect(jsonDecode(metNorwayFixture), isA<Map>());
  });
}
