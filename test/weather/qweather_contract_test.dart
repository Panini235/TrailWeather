import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/wx_http.dart';
import 'package:trailweather/data/weather/qweather_provider.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';

/// 和风格点天气 fixture：按官方文档响应结构构造（值为字符串）。
/// 真实联网验证：待用户配置 API Key 后进行（docs/data-sources.md 如实登记）。
const qweatherFixture = '''
{
  "code": "200",
  "updateTime": "2026-10-13T16:35+08:00",
  "fxLink": "https://www.qweather.com/weather/grids/116.18,39.99.html",
  "hourly": [
    {
      "fxTime": "2026-10-13T17:00+08:00",
      "temp": "18",
      "icon": "100",
      "text": "晴",
      "wind360": "359",
      "windDir": "北风",
      "windScale": "2",
      "windSpeed": "8",
      "humidity": "50",
      "pop": "10",
      "precip": "0.0",
      "pressure": "1013",
      "cloud": "0",
      "dew": "8"
    },
    {
      "fxTime": "2026-10-13T18:00+08:00",
      "temp": "16",
      "icon": "101",
      "text": "多云",
      "wind360": "20",
      "windDir": "东北风",
      "windScale": "3",
      "windSpeed": "15",
      "humidity": "55",
      "pop": "",
      "precip": "",
      "pressure": "1012",
      "cloud": "60",
      "dew": "7"
    }
  ],
  "refer": {"sources": ["qweather.com"], "license": "QWeather Developers ToS"}
}
''';

void main() {
  test('解析：字符串值转数值、单位换算（km/h→m/s、km→m）、时间偏移→UTC', () async {
    Uri? seenUri;
    Map<String, String>? seenHeaders;
    final p = QWeatherProvider(
      apiHost: 'abc123.qweatherapi.com',
      apiKey: 'test-key',
      fetcher: (uri, {headers, cancelToken}) async {
        seenUri = uri;
        seenHeaders = headers;
        return qweatherFixture;
      },
    );
    final out = await p.fetchPoints(
      points: [const LatLng(39.99, 116.18)],
      startUtc: DateTime.now().toUtc(),
      endUtc: DateTime.now().toUtc().add(const Duration(hours: 12)),
    );

    // 请求形态：location=经度,纬度（2 位小数）；X-QW-Api-Key 头
    expect(seenUri!.host, 'abc123.qweatherapi.com');
    expect(seenUri!.queryParameters['location'], '116.18,39.99');
    expect(seenHeaders?['X-QW-Api-Key'], 'test-key');

    final pt = out.first;
    expect(pt.hours, hasLength(2));
    final h0 = pt.hours[0];
    // fxTime "2026-10-13T17:00+08:00" → UTC 09:00
    expect(h0.validFromUtc, DateTime.utc(2026, 10, 13, 9));
    expect(h0.values[WxVar.temperature], 18.0);
    expect(h0.values[WxVar.precipProb], 10.0);
    expect(h0.values[WxVar.windSpeed], closeTo(8 / 3.6, 0.001)); // km/h→m/s
    expect(h0.values[WxVar.windDir], 359.0);
    expect(h0.values[WxVar.cloudCover], 0.0);
    expect(h0.values[WxVar.pressure], 1013.0);
    expect(h0.symbols?['qweather_text'], '晴');
    // 未提供（该来源无此变量）：体感温度、阵风 → null
    expect(h0.values[WxVar.apparentTemp], isNull);
    expect(h0.values[WxVar.windGust], isNull);

    // 第二时次空串 = 未提供 → null（绝不为 0）
    final h1 = pt.hours[1];
    expect(h1.values[WxVar.precip], isNull);
    expect(h1.values[WxVar.precipProb], isNull);
    expect(h1.values[WxVar.windSpeed], closeTo(15 / 3.6, 0.001));

    // 溯源
    final prov = pt.provenance;
    expect(prov.vendor, '和风天气');
    expect(prov.modelKnown, isFalse);
    expect(prov.modelRunUtc, DateTime.utc(2026, 10, 13, 8, 35));
    expect(prov.granularityStatement(), contains('网格预报'));
    expect(prov.granularityStatement(), contains('3–5 km'));
    expect(prov.locationDetail, contains('经度,纬度'));
  });

  test('错误码映射为如实异常', () async {
    final p = QWeatherProvider(
      apiHost: 'h',
      apiKey: 'k',
      fetcher: (uri, {headers, cancelToken}) async =>
          '{"code":"402","hourly":[]}',
    );
    expect(
      () => p.fetchPoints(
        points: [const LatLng(39.9, 116.2)],
        startUtc: DateTime.now().toUtc(),
        endUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
      throwsA(
        isA<SourceHttpException>().having(
          (e) => e.message,
          'message',
          contains('免费额度'),
        ),
      ),
    );
  });

  test('未配置密钥：抛配置异常（UI 给指引而非笼统失败）', () async {
    final p = QWeatherProvider(apiHost: '', apiKey: '');
    expect(
      () => p.fetchPoints(
        points: [const LatLng(39.9, 116.2)],
        startUtc: DateTime.now().toUtc(),
        endUtc: DateTime.now().toUtc().add(const Duration(hours: 2)),
      ),
      throwsA(isA<QWeatherConfigurationException>()),
    );
  });

  test('超 24h 窗口抛 WxOutOfRange（和风格点逐时仅 24 小时，如实标注）', () {
    final p = QWeatherProvider(apiHost: 'h', apiKey: 'k');
    expect(
      () => p.fetchPoints(
        points: [const LatLng(39.9, 116.2)],
        startUtc: DateTime.now().toUtc().add(const Duration(days: 3)),
        endUtc: DateTime.now().toUtc().add(const Duration(days: 3, hours: 2)),
      ),
      throwsA(isA<WxOutOfRange>()),
    );
  });

  test('能力声明：需密钥、24h 时效、分辨率与缺失变量如实', () {
    final p = QWeatherProvider(apiHost: 'h', apiKey: 'k');
    final c = p.caps;
    expect(c.requiresApiKey, isTrue);
    expect(c.forecastHorizonDays, 1);
    expect(c.supports(WxVar.windGust), isFalse);
    expect(c.supports(WxVar.apparentTemp), isFalse);
    expect(c.spatialResolutionNote, contains('3–5 km'));
  });

  test('fixture 本身可解析（哨兵）', () {
    expect(jsonDecode(qweatherFixture), isA<Map>());
  });
}
