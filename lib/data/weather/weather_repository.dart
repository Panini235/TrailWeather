import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../core/cache_store.dart';
import '../routes/route_sampling.dart';
import 'weather_models.dart';
import 'weather_provider.dart';

/// 天气仓库：编排采样节点 → 去重 → 缓存 → 请求。
///
/// 职责：
/// - 缓存键包含来源、时间窗、请求坐标（4 位小数）与参数版本；
/// - 近似网格仅用于同一次线路查询的节点去重，不用于跨请求缓存身份，避免相邻山谷误复用；
/// - TTL 按来源配置；支持 stale-while-revalidate（过期数据标记“旧数据”后
///   立即返回，同时后台刷新，绝不把旧数据当刚更新的数据）；
/// - 网格去重：来源无稳定网格标识时使用“坐标近似网格”策略并明确说明
///   （近似策略，不能伪称精确网格匹配）。
class WeatherRepository {
  WeatherRepository({
    required this.cache,
    required this.providers,
    this.staleWindow = const Duration(hours: 6),
    this.approxGridDeg = 0.1,
  });

  final CacheStore cache;
  final List<WeatherProvider> providers;
  final Duration staleWindow;

  /// 近似网格粒度（度）。用于无网格标识来源的节点去重。
  /// 这只是请求合并策略，不代表天气数据的空间分辨率。
  final double approxGridDeg;

  WeatherProvider? byId(String id) {
    for (final p in providers) {
      if (p.caps.providerId == id) return p;
    }
    return null;
  }

  /// 一次线路天气查询的完整结果：
  /// - result：来源返回（已缓存标记）；
  /// - nodeQueryIndex[i]：第 i 个节点对应的查询点下标；
  /// - sharedGridNote：存在节点合并时的“共享网格”说明。
  Future<RouteWeatherBundle> getRouteWeatherBundle({
    required String providerId,
    required List<RouteNode> nodes,
    required DateTime startUtc,
    required DateTime endUtc,
    bool refresh = false,
  }) async {
    final result = await getRouteWeather(
      providerId: providerId,
      nodes: nodes,
      startUtc: startUtc,
      endUtc: endUtc,
      refresh: refresh,
    );
    final nodeQueryIndex = <int>[];
    for (final n in nodes) {
      final key = approxGridKey(n.pos);
      final q = result.points.indexWhere(
        (p) => approxGridKey(LatLng(p.lat, p.lon)) == key,
      );
      nodeQueryIndex.add(q >= 0 ? q : 0);
    }
    final hasShared = nodeQueryIndex.toSet().length < nodes.length;
    return RouteWeatherBundle(
      result: result,
      nodeQueryIndex: nodeQueryIndex,
      sharedGridNote: hasShared
          ? '部分节点经近似网格（${approxGridDeg.toStringAsFixed(2)}°）合并查询，'
                '这些节点共享同一网格预报，不存在该网格内的差异；'
                '近似合并是请求策略，不代表天气数据的空间分辨率'
          : null,
    );
  }

  /// 近似网格键：用于判断“哪些节点可能共享同一网格预报”。
  String approxGridKey(LatLng p) =>
      '${(p.latitude / approxGridDeg).round()}:${(p.longitude / approxGridDeg).round()}';

  Future<WxSourceResult> getRouteWeather({
    required String providerId,
    required List<RouteNode> nodes,
    required DateTime startUtc,
    required DateTime endUtc,
    bool refresh = false,
    Future<void> Function()? onBackgroundRefresh,
  }) async {
    final provider = byId(providerId);
    if (provider == null) {
      throw StateError('未知来源 $providerId');
    }

    // 请求点去重（近似网格策略）。
    final gridKeys = <String>[];
    final queryPoints = <LatLng>[];
    for (var i = 0; i < nodes.length; i++) {
      final k = approxGridKey(nodes[i].pos);
      if (!gridKeys.contains(k)) {
        gridKeys.add(k);
        queryPoints.add(nodes[i].pos);
      }
    }

    final cacheKey = _cacheKey(providerId, queryPoints, startUtc, endUtc);

    if (!refresh) {
      final hit = await cache.read(CacheNs.weather, cacheKey);
      if (hit != null) {
        final restored = _decode(hit.payload);
        if (restored != null && restored.points.length == queryPoints.length) {
          final expired = hit.isExpired;
          final result = WxSourceResult(
            providerId: providerId,
            points: restored.points,
            fromCache: true,
            stale: expired,
            cachedAtUtc: hit.storedAtUtc,
            fetchedAtUtc: restored.fetchedAtUtc,
          );
          if (expired &&
              DateTime.now().toUtc().isBefore(
                hit.storedAtUtc.add(staleWindow),
              )) {
            // stale-while-revalidate：返回旧数据（已标记），后台刷新。
            unawaited(
              _fetchAndStore(
                provider,
                queryPoints,
                startUtc,
                endUtc,
                cacheKey,
                onBackgroundRefresh,
              ),
            );
          }
          return result;
        }
      }
    }

    return _fetchAndStore(
      provider,
      queryPoints,
      startUtc,
      endUtc,
      cacheKey,
      onBackgroundRefresh,
    );
  }

  Future<WxSourceResult> _fetchAndStore(
    WeatherProvider provider,
    List<LatLng> queryPoints,
    DateTime startUtc,
    DateTime endUtc,
    String cacheKey,
    Future<void> Function()? onBackgroundRefresh,
  ) async {
    final points = await provider.fetchPoints(
      points: queryPoints,
      startUtc: startUtc,
      endUtc: endUtc,
    );
    final now = DateTime.now().toUtc();
    final result = WxSourceResult(
      providerId: provider.caps.providerId,
      points: points,
      fromCache: false,
      stale: false,
      cachedAtUtc: null,
      fetchedAtUtc: now,
    );
    await cache.write(
      CacheNs.weather,
      cacheKey,
      _encode(result),
      provider.caps.recommendedCacheTtl,
    );
    if (onBackgroundRefresh != null) unawaited(onBackgroundRefresh());
    return result;
  }

  /// 缓存键包含：来源、实际请求坐标集合、时间窗、参数版本。
  /// 坐标保留 4 位小数（约 11 m）；近似网格只负责同次请求去重，不能跨请求复用。
  String _cacheKey(
    String providerId,
    List<LatLng> pts,
    DateTime startUtc,
    DateTime endUtc,
  ) {
    final coords = pts
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
        )
        .join('|');
    final s = startUtc.toIso8601String().substring(0, 13); // 小时粒度
    final e = endUtc.toIso8601String().substring(0, 13);
    return 'v2|$providerId|$coords|$s|$e';
  }

  String _encode(WxSourceResult r) {
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
        'sunset': p.dailySunsetUtc?.toIso8601String(),
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

  WxSourceResult? _decode(String raw) {
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
              if (vi < WxVar.values.length) {
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
            lat: p['lat'] as double,
            lon: p['lon'] as double,
            hours: hours,
            provenance: _provFromJson((p['prov'] as Map<String, dynamic>)),
            dailySunsetUtc: p['sunset'] == null
                ? null
                : DateTime.parse(p['sunset'] as String),
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
  requestLat: m['rlat'] as double,
  requestLon: m['rlon'] as double,
  returnedLat: m['lat'] as double?,
  returnedLon: m['lon'] as double?,
  locationDetail: m['loc'] as String?,
  elevationUsedM: m['ele'] as double?,
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

/// 线路天气查询结果包。
class RouteWeatherBundle {
  const RouteWeatherBundle({
    required this.result,
    required this.nodeQueryIndex,
    this.sharedGridNote,
  });

  final WxSourceResult result;

  /// nodeQueryIndex[i] = 第 i 个节点对应的查询点下标。
  final List<int> nodeQueryIndex;

  /// 存在节点合并时的“共享网格”说明（诚实标注，不制造虚假差异）。
  final String? sharedGridNote;
}
