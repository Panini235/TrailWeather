import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/air_quality.dart';
import 'package:trailweather/data/weather/altitude_profile.dart';
import 'package:trailweather/data/weather/met_norway_provider.dart';
import 'package:trailweather/data/weather/open_meteo_provider.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_phenomena.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

DateTime _today() {
  final n = DateTime.now().toUtc();
  return DateTime.utc(n.year, n.month, n.day);
}

String _ymdh(DateTime t) => t.toIso8601String().substring(0, 16);

/// Open-Meteo 单点响应（结构按 2026-10-15 实测：含 weather_code / snowfall / freezing_level_height）。
Map<String, dynamic> _omPoint({double elevation = 3058, int code = 73}) {
  final t0 = _today();
  return {
    'latitude': 39.08,
    'longitude': 113.58,
    'elevation': elevation,
    'utc_offset_seconds': 0,
    'hourly': {
      'time': [_ymdh(t0), _ymdh(t0.add(const Duration(hours: 1)))],
      'temperature_2m': [-3.2, -2.5],
      'wind_gusts_10m': [54.0, 36.0],
      'weather_code': [code, 3],
      'snowfall': [1.4, 0.0],
      'freezing_level_height': [2600.0, 2650.0],
    },
    'daily': {
      'time': [_ymdh(t0).substring(0, 10)],
      'sunset': [_ymdh(t0)],
    },
  };
}

RouteNode _node(double lat, double lon, double? ele) => RouteNode(
  pointIndex: 0,
  pos: LatLng(lat, lon),
  elevationM: ele,
  distFromStartM: 0,
);

void main() {
  group('请求规划：按海拔来源不再把山脊和山谷合成一个点', () {
    late WeatherRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = WeatherRepository(
        cache: CacheStore(await SharedPreferences.getInstance()),
        providers: const [],
      );
    });

    test('同一 0.1° 网格、海拔差 500 m：按海拔来源拆成两个查询点', () {
      final nodes = [
        _node(39.081, 113.581, 1500),
        _node(39.082, 113.582, 2000),
        _node(39.083, 113.583, 1530), // 与第 1 个同档
      ];
      final plan = repo.planQueries(nodes, usesElevation: true);
      expect(plan.points, hasLength(2));
      expect(plan.nodeToQuery, [0, 1, 0]);
      expect(plan.elevations, [1500, 2000]);
      expect(
        repo.planQueries(nodes, usesElevation: false).points,
        hasLength(1),
      );
    });

    test('海拔缺失的节点仍只按网格合并', () {
      final plan = repo.planQueries([
        _node(39.081, 113.581, null),
        _node(39.082, 113.582, null),
      ], usesElevation: true);
      expect(plan.points, hasLength(1));
    });
  });

  group('Open-Meteo：节点海拔、天气现象、降雪、0℃ 层', () {
    test('一批内海拔齐全时传 elevation，并解析新变量与现象', () async {
      Uri? got;
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async {
          got = uri;
          return jsonEncode([_omPoint()]);
        },
      );
      final out = await p.fetchPointsAt(
        points: [const LatLng(39.08, 113.58)],
        elevationsM: [3058.4],
        startUtc: _today(),
        endUtc: _today().add(const Duration(hours: 2)),
      );
      expect(got!.queryParameters['elevation'], '3058');
      expect(got!.queryParameters['hourly'], contains('weather_code'));
      expect(got!.queryParameters['hourly'], contains('freezing_level_height'));
      final h = out.single.hours.first;
      expect(h.values[WxVar.snowfall], 1.4);
      expect(h.values[WxVar.freezingLevel], 2600);
      expect(phenomenonOf(h)!.label, '中雪');
      expect(out.single.provenance.elevationAdjustNote, contains('3058 m'));
    });

    test('有节点缺海拔时整批不传 elevation（不能用 nan：nan 会关闭降尺度）', () async {
      Uri? got;
      final p = OpenMeteoProvider(
        model: 'best_match',
        fetcher: (uri, {headers, cancelToken}) async {
          got = uri;
          return jsonEncode([_omPoint(), _omPoint()]);
        },
      );
      await p.fetchPointsAt(
        points: [const LatLng(39.08, 113.58), const LatLng(39.1, 113.6)],
        elevationsM: [3058, null],
        startUtc: _today(),
        endUtc: _today().add(const Duration(hours: 2)),
      );
      expect(got!.queryParameters.containsKey('elevation'), isFalse);
    });

    test('MET Norway 不按海拔计算（能力声明）', () {
      expect(MetNorwayProvider().caps.usesElevation, isFalse);
      expect(OpenMeteoProvider(model: 'best_match').caps.usesElevation, isTrue);
    });
  });

  group('沿途提示：雷暴 / 降雪 / 雾 / 0℃ 层', () {
    WxHourValue hour({String? wmo, double? snow, double? vis, double? fz}) =>
        WxHourValue(
          validFromUtc: DateTime.utc(2026, 10, 18, 3),
          values: {
            WxVar.snowfall: snow,
            WxVar.visibility: vis,
            WxVar.freezingLevel: fz,
          },
          symbols: wmo == null ? null : {'wmo_code': wmo},
        );
    List<String> ids(List<NodeWeatherEntry> e) =>
        computeHints(entries: e).map((h) => h.id).toList();
    final t = DateTime.utc(2026, 10, 18, 3);

    test('各类现象分别触发', () {
      expect(
        ids([
          NodeWeatherEntry(
            weather: hour(wmo: '95'),
            validUtc: t,
          ),
        ]),
        contains('thunder'),
      );
      expect(
        ids([NodeWeatherEntry(weather: hour(snow: 0.6), validUtc: t)]),
        contains('snow'),
      );
      expect(
        ids([
          NodeWeatherEntry(
            weather: hour(wmo: '45'),
            validUtc: t,
          ),
        ]),
        contains('fog'),
      );
      expect(
        ids([NodeWeatherEntry(weather: hour(vis: 600), validUtc: t)]),
        contains('fog'),
      );
      expect(
        ids([
          NodeWeatherEntry(
            weather: hour(fz: 2800),
            validUtc: t,
            elevationM: 3000,
          ),
        ]),
        contains('freezing'),
      );
    });

    test('数据缺失不触发、也不推测', () {
      final got = ids([
        NodeWeatherEntry(weather: hour(fz: 2800), validUtc: t), // 节点无海拔
        NodeWeatherEntry(weather: hour(), validUtc: t),
      ]);
      expect(got, isNot(contains('freezing')));
      expect(got, isNot(contains('fog')));
      expect(got, isNot(contains('snow')));
    });
  });

  group('同一地点不同海拔', () {
    test('一次请求重复坐标、按海拔取同一时次；阵风 km/h → m/s', () async {
      Uri? got;
      final svc = AltitudeProfileService(
        fetcher: (uri, {headers, cancelToken}) async {
          got = uri;
          return jsonEncode([
            _omPoint(elevation: 1500, code: 0),
            _omPoint(elevation: 3058, code: 73),
          ]);
        },
      );
      final out = await svc.profile(const LatLng(39.08, 113.58), [
        1500,
        3058,
      ], _today());
      expect(got!.queryParameters['latitude'], '39.0800,39.0800');
      expect(got!.queryParameters['elevation'], '1500,3058');
      expect(out.map((s) => s.elevationM), [1500, 3058]);
      expect(out.first.gustMs, closeTo(15, 0.01));
      expect(out.last.phenomenon!.kind, WxPhenomenonKind.snow);
    });

    test('海拔档：节点取线路最低/节点/最高；选点取地面 +500/+1000/+1500', () {
      expect(altitudeLevels(base: 2500, routeMin: 1500, routeMax: 3058), [
        1500,
        2500,
        3058,
      ]);
      expect(altitudeLevels(base: 100), [100, 600, 1100, 1600]);
      expect(altitudeLevels(base: 2500, routeMin: 2500, routeMax: 2505), [
        2000,
        2500,
        3000,
      ]);
    });

    test('超过 16 天抛 WxOutOfRange', () {
      final svc = AltitudeProfileService(
        fetcher: (uri, {headers, cancelToken}) async => '[]',
      );
      expect(
        () => svc.profile(const LatLng(39, 113), [
          1000,
        ], _today().add(const Duration(days: 20))),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('空气质量', () {
    test('解析、按小时取值、1 小时内复用', () async {
      var calls = 0;
      final t0 = _today();
      final svc = AirQualityService(
        fetcher: (uri, {headers, cancelToken}) async {
          calls++;
          expect(uri.host, 'air-quality-api.open-meteo.com');
          return jsonEncode({
            'latitude': 39.1,
            'longitude': 113.6,
            'hourly': {
              'time': [_ymdh(t0), _ymdh(t0.add(const Duration(hours: 1)))],
              'pm2_5': [32.6, 39.6],
              'pm10': [40.0, null],
              'us_aqi': [54, 57],
            },
          });
        },
      );
      final s = await svc.fetch(const LatLng(39.08, 113.58));
      await svc.fetch(const LatLng(39.08, 113.58));
      expect(calls, 1);
      expect(s.gridLat, 39.1);
      final h1 = s.at(t0.add(const Duration(minutes: 70)))!;
      expect(h1.pm25, 39.6);
      expect(h1.pm10, isNull);
      expect(usAqiCategory(h1.usAqi!), '中等');
      expect(s.at(t0.add(const Duration(days: 3))), isNull);
    });
  });
}
