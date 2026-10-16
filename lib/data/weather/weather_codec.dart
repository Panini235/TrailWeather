import 'dart:convert';

import 'weather_models.dart';

/// 天气快照的稳定编码；兼容 v3 普通缓存，同时供独立离线包使用。
/// 保存全部返回时次和溯源；缓存状态在读取时按实际时钟重新计算。
abstract final class WeatherCodec {
  static String encode(WxSourceResult r) {
    final points = <Map<String, dynamic>>[];
    for (final p in r.points) {
      final hours = <Map<String, dynamic>>[];
      for (final h in p.hours) {
        final v = <String, double>{};
        h.values.forEach((k, val) {
          if (val != null) v['${k.index}'] = val;
        });
        hours.add({
          't': h.validFromUtc.toIso8601String(),
          'v': v,
          's': h.symbols,
        });
      }
      points.add({
        'lat': p.lat,
        'lon': p.lon,
        'sunsets': [for (final t in p.dailySunsetsUtc) t.toIso8601String()],
        'hours': hours,
        'prov': _provToJson(p.provenance),
      });
    }
    return jsonEncode({
      'providerId': r.providerId,
      'fetchedAt': r.fetchedAtUtc.toIso8601String(),
      'points': points,
    });
  }

  static WxSourceResult? decode(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final points = <WxPointForecast>[];
      for (final pm in (m['points'] as List)) {
        final p = pm as Map<String, dynamic>;
        final hours = <WxHourValue>[];
        for (final hm in (p['hours'] as List)) {
          final h = hm as Map<String, dynamic>;
          final vals = <WxVar, double?>{};
          final v = (h['v'] as Map<String, dynamic>?);
          if (v != null) {
            for (final e in v.entries) {
              final vi = int.parse(e.key);
              if (vi >= 0 && vi < WxVar.values.length) {
                vals[WxVar.values[vi]] = (e.value as num).toDouble();
              }
            }
          }
          for (final var_ in WxVar.values) {
            vals.putIfAbsent(var_, () => null);
          }
          hours.add(
            WxHourValue(
              validFromUtc: DateTime.parse(h['t'] as String),
              values: vals,
              symbols: (h['s'] as Map<String, dynamic>?)
                  ?.cast<String, String>(),
            ),
          );
        }
        points.add(
          WxPointForecast(
            lat: (p['lat'] as num).toDouble(),
            lon: (p['lon'] as num).toDouble(),
            hours: hours,
            provenance: _provFromJson((p['prov'] as Map<String, dynamic>)),
            dailySunsetsUtc: [
              for (final t in (p['sunsets'] as List?) ?? const [])
                DateTime.parse(t as String),
            ],
          ),
        );
      }
      return WxSourceResult(
        providerId: m['providerId'] as String,
        points: points,
        fromCache: false,
        stale: false,
        cachedAtUtc: null,
        fetchedAtUtc: DateTime.parse(m['fetchedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

Map<String, dynamic> _provToJson(WxProvenance p) => {
  'providerId': p.providerId,
  'vendor': p.vendor,
  'model': p.modelOrNetwork,
  'modelKnown': p.modelKnown,
  'rlat': p.requestLat,
  'rlon': p.requestLon,
  'lat': p.returnedLat,
  'lon': p.returnedLon,
  'loc': p.locationDetail,
  'ele': p.elevationUsedM,
  'g': p.granularity.index,
  'res': p.spatialResolutionNote,
  'k': p.dataKind.index,
  'f': p.fetchedAtUtc.toIso8601String(),
  'm': p.modelRunUtc?.toIso8601String(),
  'off': p.utcOffsetSeconds,
  'lic': p.license,
  'attr': p.attribution,
  'interp': p.interpolationNote,
  'elevAdj': p.elevationAdjustNote,
  'trace': p.traceNote,
};

WxProvenance _provFromJson(Map<String, dynamic> m) => WxProvenance(
  providerId: m['providerId'] as String,
  vendor: m['vendor'] as String,
  modelOrNetwork: m['model'] as String,
  modelKnown: m['modelKnown'] as bool? ?? false,
  requestLat: (m['rlat'] as num).toDouble(),
  requestLon: (m['rlon'] as num).toDouble(),
  returnedLat: (m['lat'] as num?)?.toDouble(),
  returnedLon: (m['lon'] as num?)?.toDouble(),
  locationDetail: m['loc'] as String?,
  elevationUsedM: (m['ele'] as num?)?.toDouble(),
  granularity: WxGranularity.values[m['g'] as int],
  spatialResolutionNote: m['res'] as String?,
  dataKind: WxDataKind.values[m['k'] as int],
  fetchedAtUtc: DateTime.parse(m['f'] as String),
  modelRunUtc: m['m'] == null ? null : DateTime.parse(m['m'] as String),
  utcOffsetSeconds: m['off'] as int? ?? 0,
  license: m['lic'] as String,
  attribution: m['attr'] as String,
  interpolationNote: m['interp'] as String?,
  elevationAdjustNote: m['elevAdj'] as String?,
  traceNote: m['trace'] as String?,
);
