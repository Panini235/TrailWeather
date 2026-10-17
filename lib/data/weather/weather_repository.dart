import 'dart:async' show unawaited;

import 'package:latlong2/latlong.dart';

import '../../core/cache_store.dart';
import '../routes/route_sampling.dart';
import 'weather_models.dart';
import 'weather_codec.dart';
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
    this.approxGridDeg = 0.1,
  });

  final CacheStore cache;
  final List<WeatherProvider> providers;
  final _requests = <String, Future<WxSourceResult>>{};

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
  }) => watchRouteWeatherBundle(
    providerId: providerId,
    nodes: nodes,
    startUtc: startUtc,
    endUtc: endUtc,
    refresh: refresh,
  ).last;

  /// 页面订阅此流：先展示已保存的数据，随后接收刷新结果。
  Stream<RouteWeatherBundle> watchRouteWeatherBundle({
    required String providerId,
    required List<RouteNode> nodes,
    required DateTime startUtc,
    required DateTime endUtc,
    bool refresh = false,
  }) async* {
    final usesEle = byId(providerId)?.caps.usesElevation ?? false;
    final plan = planQueries(nodes, usesElevation: usesEle);
    final hasShared = plan.nodeToQuery.toSet().length < nodes.length;
    await for (final result in watchRouteWeather(
      providerId: providerId,
      nodes: nodes,
      startUtc: startUtc,
      endUtc: endUtc,
      refresh: refresh,
    )) {
      yield RouteWeatherBundle(
        result: result,
        // 保留缺失查询点的索引；不得把未返回的点静默映射到第一个点。
        nodeQueryIndex: plan.nodeToQuery,
        sharedGridNote: hasShared
            ? '部分节点经近似网格（${approxGridDeg.toStringAsFixed(2)}°'
                  '${usesEle ? '，且海拔相差不足 ${elevationBandM.toStringAsFixed(0)} m' : ''}）合并查询，'
                  '这些节点共享同一网格预报，不存在其间的差异；'
                  '近似合并是请求策略，不代表天气数据的空间分辨率'
            : null,
      );
    }
  }

  /// 近似网格键：用于判断“哪些节点可能共享同一网格预报”。
  String approxGridKey(LatLng p) =>
      '${(p.latitude / approxGridDeg).round()}:${(p.longitude / approxGridDeg).round()}';

  /// 按海拔计算的来源合并节点时的海拔档宽（米）。
  /// 只按 0.1° 网格合并会把同一网格内的山脊与山谷合成一个点，抹平海拔差。
  static const double elevationBandM = 100;

  /// 请求规划：哪些节点合并成同一个查询点。
  /// 按海拔计算的来源（caps.usesElevation）要求同网格且同海拔档才合并。
  QueryPlan planQueries(List<RouteNode> nodes, {required bool usesElevation}) {
    final keys = <String>[];
    final points = <LatLng>[];
    final elevations = <double?>[];
    final nodeToQuery = <int>[];
    for (final n in nodes) {
      var k = approxGridKey(n.pos);
      if (usesElevation && n.elevationM != null) {
        k = '$k|${(n.elevationM! / elevationBandM).round()}';
      }
      var idx = keys.indexOf(k);
      if (idx < 0) {
        idx = keys.length;
        keys.add(k);
        points.add(n.pos);
        elevations.add(n.elevationM);
      }
      nodeToQuery.add(idx);
    }
    return QueryPlan(points, elevations, nodeToQuery);
  }

  /// 一次性调用等待刷新结束；交互页面使用 watchRouteWeatherBundle。
  Future<WxSourceResult> getRouteWeather({
    required String providerId,
    required List<RouteNode> nodes,
    required DateTime startUtc,
    required DateTime endUtc,
    bool refresh = false,
  }) => watchRouteWeather(
    providerId: providerId,
    nodes: nodes,
    startUtc: startUtc,
    endUtc: endUtc,
    refresh: refresh,
  ).last;

  Stream<WxSourceResult> watchRouteWeather({
    required String providerId,
    required List<RouteNode> nodes,
    required DateTime startUtc,
    required DateTime endUtc,
    bool refresh = false,
  }) async* {
    final provider = byId(providerId);
    if (provider == null) throw StateError('未知来源 $providerId');
    final start = startUtc.toUtc();
    final end = endUtc.toUtc();
    if (end.isBefore(start)) throw ArgumentError('结束时间不能早于开始时间');
    final plan = planQueries(nodes, usesElevation: provider.caps.usesElevation);
    final key = _cacheKey(
      providerId,
      plan.points,
      start,
      end,
      elevations: provider.caps.usesElevation ? plan.elevations : null,
    );
    final cached = await _findCached(key, plan.points.length, start, end);
    if (cached != null) {
      final mustRefresh =
          refresh ||
          cached.entry.isExpired ||
          (!cached.complete && cached.key != key);
      yield cached.result(refreshing: mustRefresh);
      if (!mustRefresh) return;
    }
    // 任意年龄的旧缓存都尝试更新；失败时保留原始获取时间与真实覆盖范围。
    try {
      final fresh = await _fetchAndStore(
        provider,
        plan.points,
        plan.elevations,
        start,
        end,
        key,
      );
      if (cached != null &&
          _coverageCount(fresh, start, end) == 0 &&
          _coverageCount(cached.source, start, end) > 0) {
        yield cached.result(refreshFailed: true);
      } else {
        yield fresh;
      }
    } catch (_) {
      if (cached == null) rethrow;
      // 错误变为可见状态，不留无人处理的后台 Future，也不宣称一定是断网。
      yield cached.result(refreshFailed: true);
    }
  }

  Future<_CachedForecast?> _findCached(
    String exactKey,
    int pointCount,
    DateTime start,
    DateTime end,
  ) async {
    // 保留 v3 键格式，升级前的持久缓存同样可跨小时使用。
    final parts = exactKey.split('|');
    final hasElevation = parts.last.startsWith('ele:');
    final timeIndex = parts.length - (hasElevation ? 3 : 2);
    final prefix = '${parts.take(timeIndex).join('|')}|';
    final suffix = hasElevation ? '|${parts.last}' : '';
    _CachedForecast? best;
    var bestCount = -1;
    for (final key in cache.keys(CacheNs.weather, prefix: prefix)) {
      if (key.split('|').length != parts.length ||
          (hasElevation && !key.endsWith(suffix))) {
        continue;
      }
      final entry = await cache.read(CacheNs.weather, key, touch: false);
      if (entry == null) continue;
      final source = WeatherCodec.decode(entry.payload);
      if (source == null ||
          source.providerId != parts[1] ||
          source.points.length != pointCount ||
          pointCount == 0) {
        continue;
      }
      final count = _coverageCount(source, start, end);
      if (count == 0 && key != exactKey) continue;
      final complete = count == _expectedHours(start, end) * pointCount;
      final candidate = _CachedForecast(key, entry, source, complete);
      // 优先完整覆盖，再比较覆盖小时数与获取时间。过期与否由 TTL 独立判断。
      if (best == null ||
          count > bestCount ||
          (count == bestCount &&
              source.fetchedAtUtc.isAfter(best.source.fetchedAtUtc))) {
        best = candidate;
        bestCount = count;
      }
    }
    if (best != null) await cache.read(CacheNs.weather, best.key);
    return best;
  }

  static DateTime _hour(DateTime time) => DateTime.utc(
    time.toUtc().year,
    time.toUtc().month,
    time.toUtc().day,
    time.toUtc().hour,
  );

  // 请求窗按 [start, end) 使用；零宽查询表示 start 所在小时。
  static int _expectedHours(DateTime start, DateTime end) =>
      ((end.difference(_hour(start)).inMinutes / 60).ceil()).clamp(1, 1000000);

  static int _coverageCount(
    WxSourceResult source,
    DateTime start,
    DateTime end,
  ) {
    final first = _hour(start);
    final last = first.add(Duration(hours: _expectedHours(start, end)));
    var count = 0;
    for (final point in source.points) {
      count += point.hours
          .map((h) => h.validFromUtc.toUtc())
          .where((time) => !time.isBefore(first) && time.isBefore(last))
          .toSet()
          .length;
    }
    return count;
  }

  Future<WxSourceResult> _fetchAndStore(
    WeatherProvider provider,
    List<LatLng> queryPoints,
    List<double?> queryElevations,
    DateTime startUtc,
    DateTime endUtc,
    String cacheKey,
  ) => _requests.putIfAbsent(cacheKey, () async {
    try {
      final points = await provider.fetchPointsAt(
        points: queryPoints,
        elevationsM: queryElevations,
        startUtc: startUtc,
        endUtc: endUtc,
      );
      final now = DateTime.now().toUtc();
      final raw = WxSourceResult(
        providerId: provider.caps.providerId,
        points: points,
        fromCache: false,
        stale: false,
        cachedAtUtc: null,
        fetchedAtUtc: now,
      );
      final result = WxSourceResult(
        providerId: raw.providerId,
        points: points,
        fromCache: false,
        stale: false,
        cachedAtUtc: null,
        fetchedAtUtc: now,
        partialCoverage:
            points.length != queryPoints.length ||
            _coverageCount(raw, startUtc, endUtc) <
                _expectedHours(startUtc, endUtc) * queryPoints.length,
      );
      // 保留真实的来源返回范围（即使本次请求窗没有覆盖），避免按次来源
      // 因其自身的覆盖限制重复计费；但不得覆盖同键下仍可用的离线数据。
      if (points.length == queryPoints.length &&
          points.every((p) => p.hours.isNotEmpty)) {
        final previous = await cache.read(
          CacheNs.weather,
          cacheKey,
          touch: false,
        );
        final prior = previous == null
            ? null
            : WeatherCodec.decode(previous.payload);
        if (_coverageCount(result, startUtc, endUtc) > 0 ||
            prior == null ||
            _coverageCount(prior, startUtc, endUtc) == 0) {
          await cache.write(
            CacheNs.weather,
            cacheKey,
            WeatherCodec.encode(result),
            provider.caps.recommendedCacheTtl,
          );
        }
      }
      return result;
    } finally {
      unawaited(_requests.remove(cacheKey));
    }
  });

  /// 缓存键包含：来源、实际请求坐标集合、时间窗、参数版本。
  /// 坐标保留 4 位小数（约 11 m）；近似网格只负责同次请求去重，不能跨请求复用。
  String _cacheKey(
    String providerId,
    List<LatLng> pts,
    DateTime startUtc,
    DateTime endUtc, {
    List<double?>? elevations,
  }) {
    final coords = pts
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
        )
        .join('|');
    final s = startUtc.toIso8601String().substring(0, 13); // 小时粒度
    final e = endUtc.toIso8601String().substring(0, 13);
    // 按海拔计算的来源：海拔（10 m 取整）进入缓存键，避免不同海拔误用同一缓存。
    final ele = elevations == null
        ? ''
        : '|ele:${elevations.map((x) => x == null ? '-' : (x / 10).round() * 10).join(',')}';
    return 'v3|$providerId|$coords|$s|$e$ele';
  }
}

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

/// 请求规划结果：查询点、对应海拔、每个节点所用查询点下标。
class QueryPlan {
  const QueryPlan(this.points, this.elevations, this.nodeToQuery);
  final List<LatLng> points;
  final List<double?> elevations;
  final List<int> nodeToQuery;
}

class _CachedForecast {
  const _CachedForecast(this.key, this.entry, this.source, this.complete);
  final String key;
  final CachedRead entry;
  final WxSourceResult source;
  final bool complete;

  WxSourceResult result({
    bool refreshing = false,
    bool refreshFailed = false,
  }) => WxSourceResult(
    providerId: source.providerId,
    points: source.points,
    fromCache: true,
    stale: entry.isExpired,
    cachedAtUtc: entry.storedAtUtc,
    fetchedAtUtc: source.fetchedAtUtc,
    refreshing: refreshing,
    refreshFailed: refreshFailed,
    partialCoverage: !complete,
  );
}
