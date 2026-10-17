import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'weather_provider.dart';

/// 一个时次的空气质量（近地面约 10 m 浓度）。缺失为 null。
class AirQualityHour {
  const AirQualityHour({required this.utc, this.pm25, this.pm10, this.usAqi});
  final DateTime utc;
  final double? pm25;
  final double? pm10;
  final double? usAqi;
}

class AirQualitySeries {
  const AirQualitySeries({
    required this.gridLat,
    required this.gridLon,
    required this.hours,
  });

  /// 来源返回的网格点坐标（≠ 请求坐标）。
  final double? gridLat;
  final double? gridLon;
  final List<AirQualityHour> hours;

  /// [utc] 所在小时的值；越界返回 null（不插值）。
  AirQualityHour? at(DateTime utc) {
    final t = DateTime.utc(utc.year, utc.month, utc.day, utc.hour);
    for (final h in hours) {
      if (h.utc == t) return h;
    }
    return null;
  }
}

/// 美国 AQI 分级（Open-Meteo us_aqi = 各污染物分指数的最大值）。
String usAqiCategory(double aqi) {
  if (aqi <= 50) return '优';
  if (aqi <= 100) return '中等';
  if (aqi <= 150) return '对敏感人群不健康';
  if (aqi <= 200) return '不健康';
  if (aqi <= 300) return '非常不健康';
  return '危险';
}

/// Open-Meteo Air Quality API（CAMS 预报）。
///
/// 核验（2026-10-15，官方文档 + 实测）：中国区域使用 CAMS 全球预报，约 0.4°（≈45 km）网格，
/// 每 12 小时更新、5 天预报；PM2.5 为近地面（约 10 m）浓度；必须署名 CAMS 与 Open-Meteo。
/// 这是区域级数值，山脊位于逆温层之上时实际空气可能明显好于该值。
class AirQualityService {
  AirQualityService({StringFetcher? fetcher})
    : fetcher = fetcher ?? defaultFetcher();

  final StringFetcher fetcher;
  final _memo = <String, (DateTime, AirQualitySeries)>{};
  static const _ttl = Duration(hours: 1);

  static const attribution =
      '空气质量：哥白尼大气监测服务（CAMS）全球预报，经 Open-Meteo；约 0.4°（≈45 km）网格，区域级数值';

  Future<AirQualitySeries> fetch(LatLng p) async {
    final key =
        '${p.latitude.toStringAsFixed(2)},${p.longitude.toStringAsFixed(2)}';
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.$1) < _ttl) return hit.$2;
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': p.latitude.toStringAsFixed(4),
      'longitude': p.longitude.toStringAsFixed(4),
      'hourly': 'pm2_5,pm10,us_aqi',
      'forecast_days': '5',
      'timezone': 'UTC',
    });
    final m = jsonDecode(await fetcher(uri)) as Map<String, dynamic>;
    final h = (m['hourly'] as Map<String, dynamic>?) ?? const {};
    final times = (h['time'] as List?) ?? const [];
    double? at(String k, int i) {
      final l = h[k];
      return l is List && i < l.length ? (l[i] as num?)?.toDouble() : null;
    }

    final series = AirQualitySeries(
      gridLat: (m['latitude'] as num?)?.toDouble(),
      gridLon: (m['longitude'] as num?)?.toDouble(),
      hours: [
        for (var i = 0; i < times.length; i++)
          if (DateTime.tryParse('${times[i]}Z') case final t?)
            AirQualityHour(
              utc: t.toUtc(),
              pm25: at('pm2_5', i),
              pm10: at('pm10', i),
              usAqi: at('us_aqi', i),
            ),
      ],
    );
    _memo[key] = (DateTime.now(), series);
    return series;
  }
}
