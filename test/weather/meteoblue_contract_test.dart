import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/core/wx_http.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/meteoblue_provider.dart';
import 'package:trailweather/data/weather/open_meteo_provider.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_phenomena.dart';
import 'package:trailweather/data/weather/weather_provider.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

/// 2026-10-15 用户自有 Free key 实测 basic-1h 响应（五台山北台附近，asl=3058），
/// 截取前 3 个时次、去掉 rainspot；响应本身不含 key。
const _fixture = '''
{"metadata": {"modelrun_updatetime_utc": "2026-10-15T13:00+00:00", "name": "", "height": 3058, "timezone_abbrevation": "GMT", "latitude": 39.08, "modelrun_utc": "2026-10-15T13:00+00:00", "longitude": 113.58, "utc_timeoffset": 0.0, "generation_time_ms": 4.8832893},
 "units": {"precipitation": "mm", "windspeed": "ms-1", "precipitation_probability": "percent", "relativehumidity": "percent", "temperature": "C", "time": "ISO8601", "pressure": "hPa", "winddirection": "degree"},
 "data_1h": {"time": ["2026-10-15T00:00+00:00", "2026-10-15T01:00+00:00", "2026-10-15T02:00+00:00"],
  "snowfraction": [0.0, 0.0, 0.0], "windspeed": [3.69, 3.26, 3.7], "temperature": [-1.49, 0.34, 1.77],
  "precipitation_probability": [0, 0, 0], "convective_precipitation": [0.0, 0.0, 0.0], "pictocode": [1, 1, 1],
  "felttemperature": [-7.2, -5.03, -3.86], "precipitation": [0.0, 0.0, 0.0], "isdaylight": [1, 1, 1],
  "uvindex": [1, 1, 2], "relativehumidity": [58, 53, 50], "sealevelpressure": [1017.94, 1017.71, 1017.48],
  "winddirection": [290, 300, 303]}}
''';

/// 在真实结构上把第 2 个时次改成“阴有小雪、降雪占比 60%”（人工构造，用于现象映射）。
String _snowVariant() {
  final m = jsonDecode(_fixture) as Map<String, dynamic>;
  final h = m['data_1h'] as Map<String, dynamic>;
  (h['pictocode'] as List)[1] = 34;
  (h['snowfraction'] as List)[1] = 0.6;
  (h['precipitation'] as List)[1] = 0.4;
  return jsonEncode(m);
}

DateTime _today() {
  final n = DateTime.now().toUtc();
  return DateTime.utc(n.year, n.month, n.day);
}

void main() {
  group('MeteoblueProvider 契约（basic-1h）', () {
    test('解析：变量映射、缺失保持 null、现象编码、溯源（海拔/起报）', () async {
      final p = MeteoblueProvider(
        apiKey: 'test-key',
        fetcher: (uri, {headers, cancelToken}) async => _snowVariant(),
      );
      final out = await p.fetchPointsAt(
        points: [const LatLng(39.08, 113.58)],
        elevationsM: [3058.4],
        startUtc: _today(),
        endUtc: _today().add(const Duration(hours: 3)),
      );
      final pt = out.single;
      final h0 = pt.hours[0].values;
      expect(h0[WxVar.temperature], -1.49);
      expect(h0[WxVar.apparentTemp], -7.2);
      expect(h0[WxVar.windSpeed], 3.69); // 已请求 ms-1，不再换算
      expect(h0[WxVar.windGust], isNull); // basic-1h 不含阵风
      expect(h0[WxVar.visibility], isNull);
      expect(h0[WxVar.pressure], 1017.94);
      expect(h0[WxVar.uvIndex], 1);
      expect(pt.hours[0].validFromUtc, DateTime.utc(2026, 10, 15, 0));

      final h1 = pt.hours[1];
      expect(h1.values[WxVar.snowFraction], 60);
      expect(phenomenonOf(h1)!.label, '阴有小雪');
      expect(phenomenonOf(h1)!.kind, WxPhenomenonKind.snow);
      expect(phenomenonOf(pt.hours[0])!.kind, WxPhenomenonKind.clear);

      final prov = pt.provenance;
      expect(prov.elevationUsedM, 3058);
      expect(prov.modelRunUtc, DateTime.utc(2026, 10, 15, 13));
      expect(prov.elevationAdjustNote, contains('3058 m'));
      expect(prov.modelKnown, isFalse);
    });

    test('请求参数：带海拔时传 asl（取整），单位与时区固定；不带海拔不传 asl', () async {
      final uris = <Uri>[];
      final p = MeteoblueProvider(
        apiKey: ' test-key ',
        fetcher: (uri, {headers, cancelToken}) async {
          uris.add(uri);
          return _fixture;
        },
      );
      await p.fetchPointsAt(
        points: [const LatLng(39.08, 113.58), const LatLng(39.0, 113.5)],
        elevationsM: [2511.6, null],
        startUtc: _today(),
        endUtc: _today().add(const Duration(hours: 1)),
      );
      expect(uris, hasLength(2)); // 一点一次请求
      final q = uris[0].queryParameters;
      expect(uris[0].host, 'my.meteoblue.com');
      expect(uris[0].path, '/packages/basic-1h');
      expect(q['apikey'], 'test-key');
      expect(q['asl'], '2512');
      expect(q['tz'], 'UTC');
      expect(q['windspeed'], 'ms-1');
      expect(q['format'], 'json');
      expect(uris[1].queryParameters.containsKey('asl'), isFalse);
    });

    test('未配置 key：不发请求，给出配置指引', () async {
      var calls = 0;
      final p = MeteoblueProvider(
        apiKey: '',
        fetcher: (uri, {headers, cancelToken}) async {
          calls++;
          return _fixture;
        },
      );
      await expectLater(
        p.fetchPoints(
          points: [const LatLng(39, 113)],
          startUtc: _today(),
          endUtc: _today().add(const Duration(hours: 1)),
        ),
        throwsA(isA<MeteoblueConfigurationException>()),
      );
      expect(calls, 0);
    });

    test('来源返回错误 JSON：异常带来源信息、不含 key', () async {
      final p = MeteoblueProvider(
        apiKey: 'secret-key',
        fetcher: (uri, {headers, cancelToken}) async =>
            '{"error": true, "error_message": "API key invalid"}',
      );
      try {
        await p.fetchPoints(
          points: [const LatLng(39, 113)],
          startUtc: _today(),
          endUtc: _today().add(const Duration(hours: 1)),
        );
        fail('应抛出异常');
      } on SourceHttpException catch (e) {
        expect(e.toString(), contains('API key invalid'));
        expect(e.toString(), isNot(contains('secret-key')));
      }
    });

    test('超过 7 天窗口抛 WxOutOfRange', () async {
      final p = MeteoblueProvider(
        apiKey: 'k',
        fetcher: (uri, {headers, cancelToken}) async => _fixture,
      );
      expect(
        () => p.fetchPoints(
          points: [const LatLng(39, 113)],
          startUtc: _today().add(const Duration(days: 9)),
          endUtc: _today().add(const Duration(days: 9, hours: 1)),
        ),
        throwsA(isA<WxOutOfRange>()),
      );
    });

    test('能力声明：按需、按海拔、额度说明', () {
      final caps = MeteoblueProvider(apiKey: '').caps;
      expect(caps.onDemandOnly, isTrue);
      expect(caps.usesElevation, isTrue);
      expect(caps.quotaNote, contains('8000'));
      expect(caps.supports(WxVar.windGust), isFalse);
    });
  });

  group('仓库：按海拔来源的缓存与计数', () {
    test('不同海拔各自请求；同一海拔 3 小时内命中缓存，不再计数', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var networkCalls = 0;
      final repo = WeatherRepository(
        cache: CacheStore(prefs),
        providers: [
          MeteoblueProvider(
            apiKey: 'k',
            onNetworkCall: () => networkCalls++,
            fetcher: (uri, {headers, cancelToken}) async => _fixture,
          ),
        ],
      );
      Future<void> query(double ele) => repo.getRouteWeatherBundle(
        providerId: MeteoblueProvider.providerIdValue,
        nodes: [
          RouteNode(
            pointIndex: 0,
            pos: const LatLng(39.08, 113.58),
            elevationM: ele,
            distFromStartM: 0,
          ),
        ],
        startUtc: _today(),
        endUtc: _today().add(const Duration(hours: 30)),
      );
      await query(3058);
      await query(3058);
      expect(networkCalls, 1);
      await query(2500);
      expect(networkCalls, 2);
    });
  });

  test('自动请求的主来源跳过按需来源', () {
    final providers = <WeatherProvider>[
      MeteoblueProvider(apiKey: 'k'),
      OpenMeteoProvider(model: 'best_match'),
    ];
    expect(
      primaryProviderId([MeteoblueProvider.providerIdValue], providers),
      'open-meteo:best_match',
    );
    expect(
      primaryProviderId([
        MeteoblueProvider.providerIdValue,
        'open-meteo:best_match',
      ], providers),
      'open-meteo:best_match',
    );
  });

  test('逐时现象表：雾/霾/雷暴/雨夹雪分类', () {
    WxPhenomenonKind k(int c) => meteoblueHourlyPictocodes[c]!.kind;
    expect(k(16), WxPhenomenonKind.fog);
    expect(k(13), WxPhenomenonKind.haze);
    expect(k(27), WxPhenomenonKind.thunder);
    expect(k(35), WxPhenomenonKind.mixed);
    expect(meteoblueHourlyPictocodes.length, 35);
    expect(
      phenomenonOf(
        WxHourValue(validFromUtc: DateTime.utc(2026), values: const {}),
      ),
      isNull,
    );
  });
}
