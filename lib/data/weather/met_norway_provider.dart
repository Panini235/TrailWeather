import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'weather_models.dart';
import 'weather_provider.dart';

/// MET Norway Locationforecast 2.0 (compact) 适配器。
///
/// 实测与文档核验（2026-10-13，见 docs/data-sources.md）：
/// - 免费无密钥；服务条款要求请求方以 User-Agent 标识自身；
/// - CORS: Access-Control-Allow-Origin: *（实测）；
/// - 浏览器禁止自定义 User-Agent（浏览器安全机制），Web 端标识能力受限，
///   caps.browserNotes 如实说明，Web 端实际请求可能被服务方拒绝；
/// - 单坐标请求（无批量）；
/// - compact 响应不提供：体感温度、降水概率、能见度、阵风（多数时段）→
///   相应变量保持 null，UI 显示“此来源未提供”；
/// - 响应 geometry 为请求坐标原样，未提供实际网格中心；
/// - meta.updated_at 可作为发布时间。
class MetNorwayProvider extends WeatherProvider {
  MetNorwayProvider({super.fetcher});

  static const _host = 'api.met.no';
  static const _userAgent =
      'TrailWeather/0.1.0 (github.com/Panini235/TrailWeather; contact: via repository)';

  @override
  ProviderCapabilities get caps => ProviderCapabilities(
        providerId: 'met.no:locationforecast2.0',
        vendor: 'MET Norway',
        displayName: 'MET Norway（Locationforecast 2.0）',
        modelOrNetwork:
            'HARMONIE（北欧）/ ECMWF（全球）混合，响应未标注具体模型',
        coverage: '全球（北欧区域分辨率更高）',
        forecastHorizonDays: 3, // compact 实测约 2–3 天逐时
        intervalHours: 1,
        batchCoordinates: false,
        maxPointsPerRequest: 1,
        granularity: WxGranularity.grid,
        dataKind: WxDataKind.forecast,
        requiresApiKey: false,
        browserCorsOk: true,
        browserNotes: kIsWeb
            ? '浏览器端无法自定义 User-Agent（浏览器安全限制），不符合 MET 服务条款的标识要求，请求可能被拒绝；移动端正常'
            : '需 User-Agent 标识（已内置）',
        license: 'NLOD 2.0 / CC BY 4.0（MET Norway）',
        attribution: '天气数据：MET Norway, CC BY 4.0 / NLOD',
        supportedVars: const [
          WxVar.temperature,
          WxVar.precip,
          WxVar.windSpeed,
          WxVar.windGust, // 仅部分时次提供
          WxVar.windDir,
          WxVar.humidity,
          WxVar.cloudCover,
          WxVar.pressure,
        ],
        minRequestIntervalMs: 250,
        recommendedCacheTtl: const Duration(minutes: 20),
        spatialResolutionNote:
            '来源文档：北欧 HARMONIE 约 2.5 km，其他区域 ECMWF 约 9–22 km，随区域与时效变化；本请求未返回具体网格信息',
        modelOverlapNote:
            '注意：MET Norway 全球部分使用 ECMWF 模型，与其他使用 ECMWF 系模型的来源可能存在底层模型重叠；未逐点识别，按未知处理',
      );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    final results = <WxPointForecast>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final uri = Uri(
        scheme: 'https',
        host: _host,
        path: '/weatherapi/locationforecast/2.0/compact',
        queryParameters: {
          'lat': p.latitude.toStringAsFixed(4),
          'lon': p.longitude.toStringAsFixed(4),
        },
      );
      final headers = <String, String>{};
      if (!kIsWeb) {
        // 浏览器禁止设置 User-Agent；Web 端不设置并如实标注限制。
        headers['User-Agent'] = _userAgent;
      }
      final body = await fetcher(uri, headers: headers, cancelToken: cancelToken);
      results.add(_parse(body, p, uri));
      if (i < points.length - 1) {
        await Future<void>.delayed(
            Duration(milliseconds: caps.minRequestIntervalMs));
      }
    }
    return results;
  }

  WxPointForecast _parse(String body, LatLng req, Uri uri) {
    final m = jsonDecode(body) as Map<String, dynamic>;
    final props = m['properties'] as Map<String, dynamic>;
    final meta = props['meta'] as Map<String, dynamic>;
    final updatedAt = DateTime.tryParse(meta['updated_at'] as String? ?? '')?.toUtc();
    final fetchedAt = DateTime.now().toUtc();

    final timeseries = (props['timeseries'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final hours = <WxHourValue>[];
    for (final entry in timeseries) {
      final t = DateTime.tryParse(entry['time'] as String? ?? '')?.toUtc();
      if (t == null) continue;
      final data = entry['data'] as Map<String, dynamic>;
      final values = <WxVar, double?>{};
      final symbols = <String, String>{};

      final instant = data['instant'] as Map<String, dynamic>?;
      final details = instant?['details'] as Map<String, dynamic>?;
      double? d(String k) => (details?[k] as num?)?.toDouble();
      values[WxVar.temperature] = d('air_temperature');
      values[WxVar.windSpeed] = d('wind_speed');
      values[WxVar.windGust] = d('wind_gust'); // 多数时次缺失 → null
      values[WxVar.windDir] = d('wind_from_direction');
      values[WxVar.humidity] = d('relative_humidity');
      values[WxVar.cloudCover] = d('cloud_area_fraction');
      values[WxVar.pressure] = d('air_pressure_at_sea_level');

      final next1 = data['next_1_hours'] as Map<String, dynamic>?;
      final n1Details = next1?['details'] as Map<String, dynamic>?;
      values[WxVar.precip] =
          (n1Details?['precipitation_amount'] as num?)?.toDouble();
      values[WxVar.precipProb] =
          (n1Details?['probability_of_precipitation'] as num?)?.toDouble();
      final symbol =
          (next1?['summary'] as Map<String, dynamic>?)?['symbol_code'];
      if (symbol is String) symbols['met_symbol'] = symbol;

      // 本来源未提供：apparentTemp / visibility 保持 null（绝不用 0 冒充）。
      hours.add(WxHourValue(validFromUtc: t, values: values, symbols: symbols));
    }
    hours.sort((a, b) => a.validFromUtc.compareTo(b.validFromUtc));

    final prov = WxProvenance(
      providerId: caps.providerId,
      vendor: caps.vendor,
      modelOrNetwork: caps.modelOrNetwork,
      modelKnown: false, // 响应未标注具体模型
      requestLat: req.latitude,
      requestLon: req.longitude,
      returnedLat: null,
      returnedLon: null,
      locationDetail: '返回坐标为请求坐标原样；实际网格中心未提供',
      elevationUsedM: null, // compact 响应未提供来源使用海拔
      granularity: caps.granularity,
      spatialResolutionNote: caps.spatialResolutionNote,
      dataKind: caps.dataKind,
      fetchedAtUtc: fetchedAt,
      modelRunUtc: updatedAt,
      utcOffsetSeconds: 0, // 响应时间均为 UTC
      license: caps.license,
      attribution: caps.attribution,
      interpolationNote: '来源侧插值情况未说明；本应用未做额外空间插值',
      elevationAdjustNote: null,
      traceNote: kIsWeb
          ? 'GET api.met.no/locationforecast 200（Web：未携带自定义 User-Agent）'
          : 'GET api.met.no/locationforecast 200',
    );

    return WxPointForecast(
      lat: req.latitude,
      lon: req.longitude,
      hours: hours,
      provenance: prov,
    );
  }
}
