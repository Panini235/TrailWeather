import 'dart:convert';

import 'package:latlong2/latlong.dart';

import 'weather_phenomena.dart';
import 'weather_provider.dart';

/// 同一地点某一海拔在某一时刻的天气（Open-Meteo 按海拔统计降尺度，模型估算）。
class AltitudeSample {
  const AltitudeSample({
    required this.elevationM,
    this.tempC,
    this.apparentC,
    this.gustMs,
    this.phenomenon,
    this.freezingLevelM,
  });
  final double elevationM;
  final double? tempC;
  final double? apparentC;
  final double? gustMs;
  final WxPhenomenon? phenomenon;
  final double? freezingLevelM;
}

/// “同一地点不同海拔”：同一坐标重复多次、每个配一个 elevation，一次请求得到垂直剖面。
///
/// 核验（2026-10-15 实测）：同点 1500 / 2500 / 3058 m 同一时次分别为 14.8 / 8.2 / 4.6 ℃；
/// 地面海拔用 Open-Meteo Elevation API（90 m 高程模型）。
class AltitudeProfileService {
  AltitudeProfileService({StringFetcher? fetcher})
    : fetcher = fetcher ?? defaultFetcher();

  final StringFetcher fetcher;

  /// 地面海拔（Open-Meteo Elevation API，90 m 高程模型）；失败返回 null。
  Future<double?> groundElevation(LatLng p) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/elevation', {
      'latitude': p.latitude.toStringAsFixed(4),
      'longitude': p.longitude.toStringAsFixed(4),
    });
    final m = jsonDecode(await fetcher(uri)) as Map<String, dynamic>;
    final list = m['elevation'];
    return list is List && list.isNotEmpty
        ? (list.first as num?)?.toDouble()
        : null;
  }

  Future<List<AltitudeSample>> profile(
    LatLng p,
    List<double> elevations,
    DateTime atUtc,
  ) async {
    if (elevations.isEmpty) return const [];
    final now = DateTime.now().toUtc();
    final today = DateTime.utc(now.year, now.month, now.day);
    final days = atUtc.difference(today).inDays + 1;
    if (days < 1 || days > 16) {
      throw WxOutOfRange('该时刻不在 Open-Meteo 预报范围（今天起 16 天）');
    }
    final lat = p.latitude.toStringAsFixed(4);
    final lon = p.longitude.toStringAsFixed(4);
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': List.filled(elevations.length, lat).join(','),
      'longitude': List.filled(elevations.length, lon).join(','),
      'elevation': elevations.map((e) => e.round()).join(','),
      'hourly': 'temperature_2m,apparent_temperature,wind_gusts_10m,weather_code,freezing_level_height',
      'models': 'best_match',
      'timezone': 'UTC',
      'forecast_days': '$days',
    });
    final decoded = jsonDecode(await fetcher(uri));
    final arr = decoded is List ? decoded : [decoded];
    final want = DateTime.utc(atUtc.year, atUtc.month, atUtc.day, atUtc.hour);
    final out = <AltitudeSample>[];
    for (var k = 0; k < arr.length && k < elevations.length; k++) {
      final m = arr[k] as Map<String, dynamic>;
      final h = (m['hourly'] as Map<String, dynamic>?) ?? const {};
      final times = (h['time'] as List?) ?? const [];
      final i = times.indexWhere(
        (t) => DateTime.tryParse('${t}Z')?.toUtc() == want,
      );
      double? v(String key) {
        final l = h[key];
        return i >= 0 && l is List && i < l.length
            ? (l[i] as num?)?.toDouble()
            : null;
      }

      final code = v('weather_code');
      final gustKmh = v('wind_gusts_10m');
      out.add(
        AltitudeSample(
          elevationM: (m['elevation'] as num?)?.toDouble() ?? elevations[k],
          tempC: v('temperature_2m'),
          apparentC: v('apparent_temperature'),
          gustMs: gustKmh == null ? null : gustKmh / 3.6,
          phenomenon: code == null ? null : wmoWeatherCodes[code.round()],
          freezingLevelM: v('freezing_level_height'),
        ),
      );
    }
    return out;
  }
}

/// 剖面要取的海拔：节点场景取 [线路最低, 节点, 线路最高]，不足 3 个时补 ±500 m；
/// 地图选点取 [地面, +500, +1000, +1500]。去重（10 m 内视为相同）、升序。
List<double> altitudeLevels({
  required double base,
  double? routeMin,
  double? routeMax,
}) {
  final raw = <double>[base, ?routeMin, ?routeMax];
  if (routeMin == null && routeMax == null) {
    raw.addAll([base + 500, base + 1000, base + 1500]);
  }
  final out = <double>[];
  for (final e in raw..sort()) {
    if (out.isEmpty || (e - out.last).abs() >= 10) out.add(e);
  }
  if (out.length < 3) {
    // 只有 1–2 个不同海拔时补 ±500 m；补完必须重新排序
    // （例如线路最低 78 m、节点 792 m 时补 292 m，不能排在 78 m 前面）。
    if (base - 500 > 0) out.add(base - 500);
    out.add(base + 500);
    out.sort();
  }
  return out;
}
