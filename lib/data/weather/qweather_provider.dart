import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

import '../../core/wx_http.dart';
import 'weather_models.dart';
import 'weather_provider.dart';

/// 和风天气（QWeather）格点天气适配器。
///
/// 核验（2026-10-13，官方文档 dev.qweather.com；域名直连实测 403-without-key）：
/// - 大陆直连快（实测域名可达、毫秒级响应）；需 API Key（免费订阅）；
/// - 新账号使用控制台分配的专属 API Host（形如 abc123.qweatherapi.com），
///   旧账号 devapi.qweather.com——两者都由用户在设置中配置；
/// - 认证：请求头 X-QW-Api-Key；
/// - 格点逐时 /v7/grid-weather/24h：**仅 24 小时**；location 为“经度,纬度”；
/// - 响应值为字符串（含缺失空串），文档声明格点空间分辨率约 3–5 km；
/// - 未提供：体感温度、阵风（仅风力等级）、能见度单位为 km、无日出日落
///   （均在能力与 UI 中如实标注）；
/// - 真实联网验证：待用户配置 Key 后进行（本适配器经 fixture 契约测试）。
class QWeatherProvider extends WeatherProvider {
  QWeatherProvider({
    required this.apiHost,
    required this.apiKey,
    super.fetcher,
  });

  final String apiHost;
  final String apiKey;

  @override
  ProviderCapabilities get caps => ProviderCapabilities(
        providerId: 'qweather:grid-24h',
        vendor: '和风天气',
        displayName: '和风天气（格点 24h）',
        modelOrNetwork: '和风天气数值模式（响应未标注具体模型，按未知处理）',
        coverage: '全球（中国区域数据质量更好）',
        forecastHorizonDays: 1, // 格点逐时仅 24 小时
        intervalHours: 1,
        batchCoordinates: false,
        maxPointsPerRequest: 1,
        granularity: WxGranularity.grid,
        dataKind: WxDataKind.forecast,
        requiresApiKey: true,
        browserCorsOk: true,
        browserNotes: '浏览器可用（API Key 方式认证，CORS 开放）',
        license: '和风天气开发者服务条款（免费订阅限额内使用；商用需商业订阅）',
        attribution: '天气数据：和风天气 qweather.com',
        supportedVars: const [
          WxVar.temperature,
          WxVar.precip,
          WxVar.precipProb,
          WxVar.windSpeed,
          WxVar.windDir,
          WxVar.humidity,
          WxVar.cloudCover,
          WxVar.visibility,
          WxVar.pressure,
        ],
        minRequestIntervalMs: 150,
        recommendedCacheTtl: const Duration(minutes: 20),
        spatialResolutionNote: '来源文档声明格点空间分辨率约 3–5 km（响应不携带网格信息）',
        modelOverlapNote:
            '注意：和风中国区域融合中国气象局等机构数据，与其他来源可能存在底层模型重叠；'
            '未逐点识别，按未知处理',
      );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    if (apiHost.trim().isEmpty || apiKey.trim().isEmpty) {
      throw const QWeatherConfigurationException(
          '和风天气未配置：请在 设置 → 数据源密钥 填入 API Host 与 API Key（免费订阅）');
    }
    final now = DateTime.now().toUtc();
    final horizonEnd = now.add(const Duration(hours: 24));
    if (startUtc.isAfter(horizonEnd)) {
      throw WxOutOfRange('请求时间超过和风格点逐时 24 小时窗口');
    }

    final results = <WxPointForecast>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      // 和风 location 格式为“经度,纬度”，小数最多 2 位（文档）。
      final loc =
          '${p.longitude.toStringAsFixed(2)},${p.latitude.toStringAsFixed(2)}';
      final uri = Uri(
        scheme: 'https',
        host: apiHost.trim(),
        path: '/v7/grid-weather/24h',
        queryParameters: {'location': loc, 'lang': 'zh', 'unit': 'm'},
      );
      final body = await fetcher(uri,
          headers: {'X-QW-Api-Key': apiKey.trim()},
          cancelToken: cancelToken);
      results.add(_parse(body, p));
      if (i < points.length - 1) {
        await Future<void>.delayed(
            Duration(milliseconds: caps.minRequestIntervalMs));
      }
    }
    return results;
  }

  WxPointForecast _parse(String body, LatLng req) {
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw SourceHttpException(200, '响应不是合法 JSON', apiHost);
    }
    final code = m['code'] as String? ?? '';
    if (code != '200') {
      throw SourceHttpException(
        int.tryParse(code),
        switch (code) {
          '401' => '认证失败（检查 API Key）',
          '402' => '超出免费额度',
          '403' => '无权限（检查订阅与 API Host）',
          '404' => '查询位置无数据',
          '429' => '请求过快（限流）',
          _ => '和风返回错误码 $code',
        },
        apiHost,
      );
    }
    final fetchedAt = DateTime.now().toUtc();
    final updateTime =
        DateTime.tryParse(m['updateTime'] as String? ?? '')?.toUtc();
    final hourly = (m['hourly'] as List? ?? const [])
        .cast<Map<String, dynamic>>();

    final hours = <WxHourValue>[];
    for (final h in hourly) {
      final t = DateTime.tryParse(h['fxTime'] as String? ?? '')?.toUtc();
      if (t == null) continue;
      final values = <WxVar, double?>{
        // 和风响应值均为字符串；空串/缺失 = 未提供（null），绝不为 0。
        WxVar.temperature: _d(h['temp']),
        WxVar.precip: _d(h['precip']),
        WxVar.precipProb: _d(h['pop']),
        WxVar.windSpeed: _msFromKmh(_d(h['windSpeed'])),
        WxVar.windDir: _d(h['wind360']),
        WxVar.humidity: _d(h['humidity']),
        WxVar.cloudCover: _d(h['cloud']),
        WxVar.visibility: _mFromKm(_d(h['vis'])),
        WxVar.pressure: _d(h['pressure']),
        // 本来源未提供：apparentTemp / windGust（仅有风力等级文本）→ 保持 null。
      };
      final icon = h['icon'] as String?;
      hours.add(WxHourValue(
        validFromUtc: t,
        values: values,
        symbols: icon == null ? null : {'qweather_icon': icon, 'qweather_text': (h['text'] as String? ?? '')},
      ));
    }
    hours.sort((a, b) => a.validFromUtc.compareTo(b.validFromUtc));

    final prov = WxProvenance(
      providerId: caps.providerId,
      vendor: caps.vendor,
      modelOrNetwork: caps.modelOrNetwork,
      modelKnown: false,
      requestLat: req.latitude,
      requestLon: req.longitude,
      returnedLat: null,
      returnedLon: null,
      locationDetail: '格点预报；location 按“经度,纬度”保留 2 位小数请求，'
          '来源未返回实际网格中心（响应坐标为请求坐标）',
      elevationUsedM: null,
      granularity: caps.granularity,
      spatialResolutionNote: caps.spatialResolutionNote,
      dataKind: caps.dataKind,
      fetchedAtUtc: fetchedAt,
      modelRunUtc: updateTime,
      utcOffsetSeconds: 0,
      license: caps.license,
      attribution: caps.attribution,
      interpolationNote: '来源侧插值情况未说明；本应用未做额外空间插值',
      elevationAdjustNote: null,
      traceNote: 'GET $apiHost/v7/grid-weather/24h 200',
    );

    return WxPointForecast(
      lat: req.latitude,
      lon: req.longitude,
      hours: hours,
      provenance: prov,
    );
  }

  static double? _d(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String && v.trim().isNotEmpty) return double.tryParse(v);
    return null;
  }

  static double? _msFromKmh(double? kmh) => kmh == null ? null : kmh / 3.6;
  static double? _mFromKm(double? km) => km == null ? null : km * 1000;
}

/// 和风配置缺失：UI 据此给出明确的配置指引（而非笼统失败）。
class QWeatherConfigurationException implements Exception {
  const QWeatherConfigurationException(this.message);
  final String message;

  @override
  String toString() => message;
}
