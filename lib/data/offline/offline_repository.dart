import 'dart:math';

import '../weather/weather_provider.dart';
import '../weather/weather_repository.dart';
import 'offline_store.dart';
import 'offline_trip.dart';

class OfflineEntry {
  const OfflineEntry({required this.id, this.trip, this.error});
  final String id;
  final OfflineTrip? trip;
  final String? error;
}

/// 只在 download 的显式操作中访问天气仓库；列表与查看可以完全离线启动。
class OfflineTripRepository {
  OfflineTripRepository({
    required this.store,
    required this.weather,
    required this.now,
  });
  final OfflineTripStore store;
  final WeatherRepository Function() weather;
  final DateTime Function() now;
  final _busy = <String>{};

  static bool supportsSource(WeatherProvider source) =>
      !source.caps.onDemandOnly &&
      (const {
        'open-meteo:best_match',
        'open-meteo:ecmwf_ifs025',
        'met.no:locationforecast2.0',
      }.contains(source.caps.providerId));

  Future<OfflineTrip?> load(String id) async {
    final raw = await store.read(id);
    if (raw == null) return null;
    final trip = OfflineTrip.decode(raw);
    if (trip.id != id) throw const FormatException('离线包标识不匹配');
    return trip;
  }

  Future<List<OfflineEntry>> list() async {
    final entries = <OfflineEntry>[];
    for (final id in await store.ids()) {
      try {
        final trip = await load(id);
        if (trip != null) entries.add(OfflineEntry(id: id, trip: trip));
      } catch (_) {
        entries.add(OfflineEntry(id: id, error: '无法读取或校验失败，请重新下载；其他离线包不受影响。'));
      }
    }
    entries.sort(
      (a, b) => (b.trip?.savedAtUtc ?? DateTime(1970)).compareTo(
        a.trip?.savedAtUtc ?? DateTime(1970),
      ),
    );
    return entries;
  }

  Future<OfflineTrip> download({
    required OfflineTripPlan plan,
    required String providerId,
    String? replacingId,
  }) async {
    plan.validate();
    final id =
        replacingId ??
        'trip-${now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';
    if (!_busy.add(id)) throw StateError('此离线包正在更新，请稍后');
    try {
      final previous = replacingId == null ? null : await load(id);
      // 函数注入保证离线读取不会初始化网络服务。
      final repo = weather();
      final provider = repo.byId(providerId);
      if (provider == null || !supportsSource(provider)) {
        throw StateError('此来源暂不支持离线包，请选择 Open-Meteo 或 MET Norway');
      }
      final queries = repo.planQueries(
        plan.nodes,
        usesElevation: provider.caps.usesElevation,
      );
      final bundle = await repo.getRouteWeatherBundle(
        providerId: providerId,
        nodes: plan.nodes,
        startUtc: plan.startUtc,
        endUtc: plan.endUtc,
        refresh: true,
      );
      if (bundle.result.refreshFailed || bundle.result.fromCache) {
        throw StateError('未能获取新预报，已保留原有离线包；联网后可重试');
      }
      final trip = OfflineTrip(
        id: id,
        plan: plan,
        bundle: bundle,
        queryPoints: queries.points,
        sourceName: provider.caps.displayName,
        modelOverlapNote: provider.caps.modelOverlapNote,
        freshFor: provider.caps.recommendedCacheTtl,
        savedAtUtc: now().toUtc(),
      );
      trip.validate();
      if (trip.coverage.available == 0) {
        throw StateError('所选时段没有可用预报，未保存；请调整日期或来源后重试');
      }
      if (previous != null &&
          trip.coverage.available < previous.coverage.available) {
        throw StateError('本次返回的可用时段少于原离线包，已保留原包；请稍后重试');
      }
      // 编码→解码→结构核验完成后才提交；返回已验证的持久化快照。
      final encoded = trip.encode();
      final checked = OfflineTrip.decode(encoded);
      await store.write(id, encoded);
      return checked;
    } finally {
      _busy.remove(id);
    }
  }

  Future<void> delete(String id) async {
    if (!_busy.add(id)) throw StateError('此离线包正在更新，请稍后');
    try {
      await store.delete(id);
    } finally {
      _busy.remove(id);
    }
  }
}
