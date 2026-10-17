import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/wx_http.dart';
import 'weather_models.dart';
import 'weather_provider.dart';

/// meteoblue Forecast API（basic-1h 包）适配器——按次计费的“按需单点”来源。
///
/// 核验（2026-10-15，用户自有 Free key 实测 + business.meteoblue.com 免费版页面）：
/// - GET https://my.meteoblue.com/packages/basic-1h?apikey=…&lat=…&lon=…&asl=…&format=json；
/// - 每次调用响应头 `mb-credits-accounted: 8000`；免费版 10M credits / 1 年 ≈ 1,250 次；
///   一次一个坐标（无多点批量）→ 只在用户点击时查询，缓存 3 小时，不参与线路自动请求；
/// - `asl` 指定海拔后按该海拔计算（未指定时用 80 m 高程模型）；metadata.height 回显所用海拔；
/// - 响应 data_1h 自当天 00:00 UTC 起 169 个逐时值（7 天）；CORS `*`（Web 可直连）；
/// - basic-1h 不含阵风、能见度、云量（在 wind/clouds 包中，免费版仅 3 小时分辨率），保持 null；
/// - 免费版页面对比表“Commercial use ✓”，但以账户条款为准（docs/data-sources.md）。
class MeteoblueProvider extends WeatherProvider {
  MeteoblueProvider({required this.apiKey, this.onNetworkCall, super.fetcher});

  final String apiKey;

  /// 每发起一次真实网络请求回调一次（用于本机额度计数；缓存命中不回调）。
  final void Function()? onNetworkCall;

  static const providerIdValue = 'meteoblue:basic-1h';
  static const creditsPerCall = 8000;

  @override
  ProviderCapabilities get caps => ProviderCapabilities(
    providerId: providerIdValue,
    vendor: 'meteoblue',
    displayName: 'meteoblue（逐点海拔）',
    modelOrNetwork: 'meteoblue 多模型后处理（响应未标注具体模型，按未知处理）',
    coverage: '全球',
    forecastHorizonDays: 7,
    intervalHours: 1,
    batchCoordinates: false,
    maxPointsPerRequest: 1,
    granularity: WxGranularity.grid,
    dataKind: WxDataKind.forecast,
    requiresApiKey: true,
    browserCorsOk: true,
    browserNotes: 'CORS 开放（实测）；Web 端 API key 会出现在请求地址中（你自己的 key，仅存本机）',
    license: 'meteoblue Free Weather API（免费版页面标注可商用，以账户条款为准）',
    attribution: '天气数据：meteoblue',
    supportedVars: const [
      WxVar.temperature,
      WxVar.apparentTemp,
      WxVar.precip,
      WxVar.precipProb,
      WxVar.windSpeed,
      WxVar.windDir,
      WxVar.humidity,
      WxVar.pressure,
      WxVar.snowFraction,
      WxVar.uvIndex,
    ],
    minRequestIntervalMs: 250,
    recommendedCacheTtl: const Duration(hours: 3),
    spatialResolutionNote: '按请求坐标与海拔（asl）计算；响应未返回网格分辨率（分辨率未确认）',
    modelOverlapNote: 'meteoblue 融合多家数值模式（含 ECMWF/ICON 等），与其他来源可能共享底层模型；未逐点识别',
    onDemandOnly: true,
    usesElevation: true,
    quotaNote:
        '每次查询约消耗 $creditsPerCall credits（免费版 1 年 1000 万 ≈ 1,250 次）；'
        '3 小时内重复查询同一点使用缓存，不消耗额度',
  );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) => fetchPointsAt(
    points: points,
    elevationsM: List.filled(points.length, null),
    startUtc: startUtc,
    endUtc: endUtc,
    cancelToken: cancelToken,
  );

  @override
  Future<List<WxPointForecast>> fetchPointsAt({
    required List<LatLng> points,
    required List<double?> elevationsM,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const MeteoblueConfigurationException(
        'meteoblue 未配置：请在 设置 → 数据源密钥 填入你的 meteoblue API key',
      );
    }
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    if (startUtc.isAfter(today.add(Duration(days: caps.forecastHorizonDays)))) {
      throw WxOutOfRange('请求时间超过 meteoblue basic-1h 的 7 天窗口');
    }
    if (endUtc.isBefore(today)) {
      throw WxOutOfRange('请求时间早于今天，meteoblue 预报接口不提供该时段');
    }

    final out = <WxPointForecast>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final asl = i < elevationsM.length ? elevationsM[i] : null;
      final uri = Uri(
        scheme: 'https',
        host: 'my.meteoblue.com',
        path: '/packages/basic-1h',
        queryParameters: {
          'apikey': apiKey.trim(),
          'lat': p.latitude.toStringAsFixed(4),
          'lon': p.longitude.toStringAsFixed(4),
          if (asl != null) 'asl': asl.round().toString(),
          'format': 'json',
          'tz': 'UTC',
          'timeformat': 'iso8601',
          'temperature': 'C',
          'windspeed': 'ms-1',
          'precipitationamount': 'mm',
        },
      );
      onNetworkCall?.call();
      final body = await fetcher(uri, cancelToken: cancelToken);
      out.add(_parse(body, p, asl));
      if (i < points.length - 1) {
        await Future<void>.delayed(
          Duration(milliseconds: caps.minRequestIntervalMs),
        );
      }
    }
    return out;
  }

  WxPointForecast _parse(String body, LatLng req, double? asl) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw SourceHttpException(200, '响应格式无法识别', 'my.meteoblue.com/packages');
    }
    if (decoded['error'] == true || decoded['error_message'] != null) {
      // 错误信息原样展示（不含 key：key 只在请求地址中，不在响应里）。
      throw SourceHttpException(
        200,
        'meteoblue 返回错误：${decoded['error_message'] ?? '未知'}',
        'my.meteoblue.com/packages',
      );
    }
    final meta = (decoded['metadata'] as Map<String, dynamic>?) ?? const {};
    final h = (decoded['data_1h'] as Map<String, dynamic>?) ?? const {};
    final times = (h['time'] as List?) ?? const [];
    double? at(String key, int i) {
      final list = h[key];
      if (list is! List || i >= list.length) return null;
      return (list[i] as num?)?.toDouble();
    }

    final hours = <WxHourValue>[];
    for (var i = 0; i < times.length; i++) {
      final t = DateTime.tryParse('${times[i]}')?.toUtc();
      if (t == null) continue;
      final snow = at('snowfraction', i);
      final picto = at('pictocode', i);
      hours.add(
        WxHourValue(
          validFromUtc: t,
          values: {
            WxVar.temperature: at('temperature', i),
            WxVar.apparentTemp: at('felttemperature', i),
            WxVar.precip: at('precipitation', i),
            WxVar.precipProb: at('precipitation_probability', i),
            WxVar.windSpeed: at('windspeed', i),
            WxVar.windGust: null, // basic-1h 不含阵风
            WxVar.windDir: at('winddirection', i),
            WxVar.humidity: at('relativehumidity', i),
            WxVar.cloudCover: null,
            WxVar.visibility: null,
            WxVar.pressure: at('sealevelpressure', i),
            WxVar.snowFraction: snow == null ? null : snow * 100,
            // 文档未说明 uvindex 是否计入云量（docs/data-sources.md）；
            // 作为紫外线预报使用，若为晴空值则偏高，方向上不会低估风险。
            WxVar.uvIndex: at('uvindex', i),
          },
          symbols: picto == null ? null : {'mb_pictocode': '${picto.round()}'},
        ),
      );
    }

    final height = (meta['height'] as num?)?.toDouble();
    final prov = WxProvenance(
      providerId: caps.providerId,
      vendor: caps.vendor,
      modelOrNetwork: caps.modelOrNetwork,
      modelKnown: false,
      requestLat: req.latitude,
      requestLon: req.longitude,
      returnedLat: (meta['latitude'] as num?)?.toDouble(),
      returnedLon: (meta['longitude'] as num?)?.toDouble(),
      locationDetail: asl == null
          ? '未指定海拔：meteoblue 按 80 m 高程模型取该点海拔计算'
          : '按请求海拔 ${asl.round()} m 计算（asl 参数）',
      elevationUsedM: height,
      granularity: caps.granularity,
      spatialResolutionNote: caps.spatialResolutionNote,
      dataKind: caps.dataKind,
      fetchedAtUtc: DateTime.now().toUtc(),
      modelRunUtc: DateTime.tryParse('${meta['modelrun_utc']}')?.toUtc(),
      utcOffsetSeconds: 0,
      license: caps.license,
      attribution: caps.attribution,
      interpolationNote: '来源侧按海拔与地形修正（meteoblue 方法未逐项说明）；本应用未做额外插值',
      elevationAdjustNote: asl == null
          ? null
          : '来源按轨迹海拔 ${asl.round()} m 修正（meteoblue asl），非本应用推算',
      traceNote: 'GET my.meteoblue.com/packages/basic-1h 200',
    );
    return WxPointForecast(
      lat: req.latitude,
      lon: req.longitude,
      hours: hours,
      provenance: prov,
    );
  }
}

class MeteoblueConfigurationException implements Exception {
  const MeteoblueConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}
