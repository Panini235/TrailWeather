import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/wx_http.dart';
import 'weather_models.dart';
import 'weather_provider.dart';

/// Open-Meteo Forecast API 适配器。
///
/// 实测与文档核验（2026-10-13，见 docs/data-sources.md）：
/// - 免费、无需密钥、CORS 允许（Web 可直连）；
/// - 多坐标批量：latitude/longitude 逗号列表，响应为 JSON 数组；
/// - 响应携带模型网格海拔（elevation）与 utc_offset_seconds；
/// - 默认 hourly 步长 1 小时；forecast_days 最多 16 天；
/// - 时效外 API 会直接截断而不是报错，客户端需如实标记范围。
class OpenMeteoProvider extends WeatherProvider {
  OpenMeteoProvider({required this.model, super.fetcher});

  /// Open-Meteo models 参数，如 best_match / ecmwf_ifs025。
  final String model;

  static const _host = 'api.open-meteo.com';

  static const _hourlyVars = <String, WxVar>{
    'temperature_2m': WxVar.temperature,
    'apparent_temperature': WxVar.apparentTemp,
    'precipitation': WxVar.precip,
    'precipitation_probability': WxVar.precipProb,
    'wind_speed_10m': WxVar.windSpeed,
    'wind_gusts_10m': WxVar.windGust,
    'wind_direction_10m': WxVar.windDir,
    'relative_humidity_2m': WxVar.humidity,
    'cloud_cover': WxVar.cloudCover,
    'visibility': WxVar.visibility,
    'surface_pressure': WxVar.pressure,
    'snowfall': WxVar.snowfall, // cm（前一小时新增雪深）
    'freezing_level_height': WxVar.freezingLevel, // m
    'uv_index': WxVar.uvIndex, // ECMWF 等部分模型返回空 → null
    'uv_index_clear_sky': WxVar.uvIndexClearSky,
    'cloud_cover_low': WxVar.cloudLow,
    'cloud_cover_mid': WxVar.cloudMid,
    'cloud_cover_high': WxVar.cloudHigh,
    'dew_point_2m': WxVar.dewPoint,
    'snow_depth': WxVar.snowDepth, // m
    'cape': WxVar.cape, // J/kg
  };

  @override
  ProviderCapabilities get caps => ProviderCapabilities(
    providerId: 'open-meteo:$model',
    vendor: 'Open-Meteo',
    displayName: 'Open-Meteo（$model）',
    modelOrNetwork: model == 'best_match'
        ? 'best_match：按区域自动选择模型，具体模型来源未随响应返回'
        : model,
    coverage: '全球（陆地为主）',
    forecastHorizonDays: 16,
    intervalHours: 1,
    batchCoordinates: true,
    maxPointsPerRequest: 10, // 单 URL 长度控制（工程上限，非 API 硬限制）
    granularity: WxGranularity.grid,
    dataKind: WxDataKind.forecast,
    requiresApiKey: false,
    browserCorsOk: true,
    browserNotes: '浏览器直连可用（CORS 开放）；非商业用途免费额度',
    license: 'CC BY 4.0（Open-Meteo 聚合再分发，非商业免费）',
    attribution: '数据：Open-Meteo（模型来自 NOAA/GFS 等机构，随 best_match 而定）',
    supportedVars: _hourlyVars.values.toList(),
    minRequestIntervalMs: 600,
    recommendedCacheTtl: const Duration(minutes: 30),
    usesElevation: true,
    spatialResolutionNote: model == 'best_match'
        ? 'best_match 按区域动态选择模型，来源未随响应提供本请求的空间分辨率（分辨率未确认）'
        : '按模型名标注：$model（0.25° 级全球模型；以官方文档为准，本请求未返回网格信息）',
    modelOverlapNote:
        '注意：Open-Meteo 的不同 models 参数属于同一服务商接口，不一定代表相互独立的证据；'
        '且不同 API 服务商也可能使用相同底层气象模型。未识别处按未知处理。',
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

  /// [elevationsM]：节点轨迹海拔。一批内全部有值时传 `elevation` 参数，按该海拔统计降尺度；
  /// 有缺失时整批不传（Open-Meteo 用 90 m 高程模型）——不能用 nan 补位，
  /// nan 会关闭降尺度、改用网格平均高度（官方文档）。
  @override
  Future<List<WxPointForecast>> fetchPointsAt({
    required List<LatLng> points,
    required List<double?> elevationsM,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    final now = DateTime.now().toUtc();
    final todayUtc = DateTime.utc(now.year, now.month, now.day);
    if (endUtc.isBefore(todayUtc)) {
      // 预报接口从当天 00:00 UTC 起提供；更早的时刻不是预报，不外推。
      throw WxOutOfRange('请求时间早于今天，Open-Meteo 预报接口不提供该时段');
    }
    final days = _forecastDays(now, startUtc, endUtc);
    if (days <= 0) {
      throw WxOutOfRange('请求起始时间超过 Open-Meteo 16 天预报窗口');
    }

    final out = <WxPointForecast>[];
    for (var i = 0; i < points.length; i += caps.maxPointsPerRequest) {
      final batch = points.skip(i).take(caps.maxPointsPerRequest).toList();
      final eles = [
        for (var j = i; j < i + batch.length; j++)
          j < elevationsM.length ? elevationsM[j] : null,
      ];
      final useEle = eles.every((e) => e != null);
      final uri = _buildUri(batch, days, useEle ? eles.cast<double>() : null);
      final body = await fetcher(uri, cancelToken: cancelToken);
      out.addAll(_parse(body, batch, uri, useEle ? eles : null));
      if (i + caps.maxPointsPerRequest < points.length) {
        await Future<void>.delayed(
          Duration(milliseconds: caps.minRequestIntervalMs),
        );
      }
    }
    return out;
  }

  Uri _buildUri(List<LatLng> batch, int days, List<double>? elevations) {
    final lats = batch.map((p) => p.latitude.toStringAsFixed(4)).join(',');
    final lons = batch.map((p) => p.longitude.toStringAsFixed(4)).join(',');
    return Uri(
      scheme: 'https',
      host: _host,
      path: '/v1/forecast',
      queryParameters: {
        'latitude': lats,
        'longitude': lons,
        'hourly': [..._hourlyVars.keys, 'weather_code'].join(','),
        if (elevations != null)
          'elevation': elevations.map((e) => e.round()).join(','),
        'daily': 'sunrise,sunset',
        'timezone': 'UTC',
        'forecast_days': '$days',
        'models': model,
      },
    );
  }

  int _forecastDays(DateTime nowUtc, DateTime startUtc, DateTime endUtc) {
    final horizonEnd = nowUtc.add(Duration(days: caps.forecastHorizonDays));
    // 请求起点已超出来源真实预报窗口：如实抛出，由 UI 显示“此来源暂无该日期数据”。
    if (startUtc.isAfter(horizonEnd)) return 0;
    // 响应从当天 00:00 UTC 起，当天已过去的小时同样可用（仅要求不早于今天）。
    final effEnd = endUtc.isAfter(horizonEnd) ? horizonEnd : endUtc;
    final days =
        effEnd
            .difference(DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day))
            .inDays +
        1;
    return days.clamp(1, caps.forecastHorizonDays);
  }

  List<WxPointForecast> _parse(
    String body,
    List<LatLng> requested,
    Uri uri,
    List<double?>? requestedElevations,
  ) {
    final decoded = jsonDecode(body);
    final List<dynamic> arr = decoded is List ? decoded : <dynamic>[decoded];
    if (arr.length != requested.length) {
      throw SourceHttpException(
        200,
        '响应点数(${arr.length})与请求(${requested.length})不符',
        '${uri.host}${uri.path}',
      );
    }
    final fetchedAt = DateTime.now().toUtc();
    final results = <WxPointForecast>[];
    for (var i = 0; i < arr.length; i++) {
      final m = arr[i] as Map<String, dynamic>;
      results.add(
        _parsePoint(m, requested[i], fetchedAt, requestedElevations?[i]),
      );
    }
    return results;
  }

  WxPointForecast _parsePoint(
    Map<String, dynamic> m,
    LatLng req,
    DateTime fetchedAt,
    double? requestedElevation,
  ) {
    final returnedLat = (m['latitude'] as num?)?.toDouble();
    final returnedLon = (m['longitude'] as num?)?.toDouble();
    final elevation = (m['elevation'] as num?)?.toDouble();
    final offsetSec = (m['utc_offset_seconds'] as num?)?.toInt() ?? 0;

    final hourly = (m['hourly'] as Map<String, dynamic>?) ?? {};
    final times = (hourly['time'] as List?) ?? const [];
    final series = <WxHourValue>[];
    final varLists = <WxVar, List>{};
    for (final e in _hourlyVars.entries) {
      varLists[e.value] = (hourly[e.key] as List?) ?? const [];
    }
    final codes = (hourly['weather_code'] as List?) ?? const [];
    for (var i = 0; i < times.length; i++) {
      final t = _parseUtcHour(times[i] as String);
      if (t == null) continue;
      final values = <WxVar, double?>{};
      varLists.forEach((v, list) {
        final raw = i < list.length ? (list[i] as num?)?.toDouble() : null;
        if (raw == null) {
          values[v] = null;
          return;
        }
        // 来源单位 -> 内部标准单位（m/s）。文档：wind_speed_10m 为 km/h。
        if (v == WxVar.windSpeed || v == WxVar.windGust) {
          values[v] = raw / 3.6;
        } else {
          values[v] = raw;
        }
      });
      final code = i < codes.length ? (codes[i] as num?)?.toInt() : null;
      series.add(
        WxHourValue(
          validFromUtc: t,
          values: values,
          symbols: code == null ? null : {'wmo_code': '$code'},
        ),
      );
    }

    // 保留每一天的日出日落；取哪一天由调用方按出发时间决定（不能默认取“今天”）。
    final daily = m['daily'] as Map<String, dynamic>?;
    List<DateTime> dailyTimes(String key) => [
      for (final raw in (daily?[key] as List?) ?? const [])
        ?(raw is String ? _parseUtcHour(raw) : null),
    ];
    final sunsets = dailyTimes('sunset');
    final sunrises = dailyTimes('sunrise');

    final prov = WxProvenance(
      providerId: caps.providerId,
      vendor: caps.vendor,
      modelOrNetwork: caps.modelOrNetwork,
      modelKnown: model != 'best_match',
      requestLat: req.latitude,
      requestLon: req.longitude,
      returnedLat: returnedLat,
      returnedLon: returnedLon,
      locationDetail: requestedElevation == null
          ? '网格预报；来源未提供网格中心标识；未指定海拔，按 90 m 高程模型降尺度'
          : '网格预报；按请求海拔 ${requestedElevation.round()} m 统计降尺度',
      elevationUsedM: elevation,
      granularity: caps.granularity,
      spatialResolutionNote: caps.spatialResolutionNote,
      dataKind: caps.dataKind,
      fetchedAtUtc: fetchedAt,
      modelRunUtc: null, // 该接口未返回模型起报时间
      utcOffsetSeconds: offsetSec,
      license: caps.license,
      attribution: caps.attribution,
      interpolationNote: '来源侧插值情况未说明；本应用未做额外空间插值',
      elevationAdjustNote: requestedElevation == null
          ? null
          : '来源按轨迹海拔 ${requestedElevation.round()} m 统计降尺度（Open-Meteo elevation 参数），非本应用推算',
      traceNote: 'GET api.open-meteo.com/v1/forecast 200',
    );

    return WxPointForecast(
      lat: req.latitude,
      lon: req.longitude,
      hours: series,
      provenance: prov,
      dailySunsetsUtc: sunsets,
      dailySunrisesUtc: sunrises,
    );
  }

  /// Open-Meteo timezone=UTC 时时间串无后缀，如 "2026-10-13T00:00"。
  static DateTime? _parseUtcHour(String s) {
    final withZ = s.endsWith('Z') ? s : '${s}Z';
    return DateTime.tryParse(withZ)?.toUtc();
  }
}
