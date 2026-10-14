import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import 'route_models.dart';

/// 徒步星球地貌类别定义。
class TerrainCategory {
  const TerrainCategory({
    required this.key,
    required this.label,
    required this.icon,
  });

  final String key;
  final String label;
  final String icon;

  static const all = [
    TerrainCategory(key: 'all', label: '全部', icon: '🌍'),
    TerrainCategory(key: 'snow', label: '雪山', icon: '🏔️'),
    TerrainCategory(key: 'glacier', label: '冰川', icon: '🧊'),
    TerrainCategory(key: 'forest', label: '森林', icon: '🌲'),
    TerrainCategory(key: 'canyon', label: '峡谷', icon: '🏞️'),
    TerrainCategory(key: 'coast', label: '海岸', icon: '🌊'),
    TerrainCategory(key: 'peak', label: '奇峰', icon: '🧗'),
    TerrainCategory(key: 'volcano', label: '火山', icon: '🌋'),
    TerrainCategory(key: 'meadow', label: '草甸荒原', icon: '🌾'),
  ];
}

/// 徒步星球全球经典路线仓库。
class PlanetTrailsRepository {
  List<HikingRoute>? _cache;

  /// 加载并解析所有全球经典路线。
  Future<List<HikingRoute>> loadAll() async {
    if (_cache != null) return _cache!;

    final rawJson = await rootBundle.loadString(
      'assets/routes/planet_trails.json',
    );
    final list = jsonDecode(rawJson) as List<dynamic>;

    final routes = <HikingRoute>[];
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final id = map['id'] as String;
      final name = map['name'] as String;
      final region = map['where'] as String?;
      final cat = map['cat'] as String?;
      final days = map['days'] as String?;
      final season = map['season'] as String?;
      final desc = map['desc'] as String?;

      // 解析坐标线：[lon, lat]
      final rawLine = map['line'] as List<dynamic>? ?? [];
      final points = <LatLng>[];
      for (final p in rawLine) {
        if (p is List && p.length >= 2) {
          final lon = (p[0] as num).toDouble();
          final lat = (p[1] as num).toDouble();
          points.add(LatLng(lat, lon));
        }
      }
      if (points.length < 2) continue;

      // 解析高程剖面并为每个轨迹点插值海拔：prof 为 [[dist_km, ele_m], ...]
      final rawProf = map['prof'] as List<dynamic>? ?? [];
      final prof = <(double, double)>[];
      for (final pr in rawProf) {
        if (pr is List && pr.length >= 2) {
          final d = (pr[0] as num).toDouble() * 1000.0; // km -> m
          final ele = (pr[1] as num).toDouble();
          prof.add((d, ele));
        }
      }

      final cumDistances = Geo.cumulativeDistancesM(points);
      final elevations = <double?>[];

      if (prof.isEmpty) {
        elevations.addAll(List.filled(points.length, null));
      } else {
        for (final d in cumDistances) {
          // 在 prof 中二分或查找最近区间进行线性插值
          if (d <= prof.first.$1) {
            elevations.add(prof.first.$2);
          } else if (d >= prof.last.$1) {
            elevations.add(prof.last.$2);
          } else {
            var interpolated = prof.first.$2;
            for (var i = 0; i < prof.length - 1; i++) {
              if (d >= prof[i].$1 && d <= prof[i + 1].$1) {
                final span = prof[i + 1].$1 - prof[i].$1;
                if (span > 0) {
                  final ratio = (d - prof[i].$1) / span;
                  interpolated =
                      prof[i].$2 + ratio * (prof[i + 1].$2 - prof[i].$2);
                } else {
                  interpolated = prof[i].$2;
                }
                break;
              }
            }
            elevations.add(interpolated);
          }
        }
      }

      routes.add(
        HikingRoute(
          id: 'planet-$id',
          name: name,
          origin: RouteOrigin.planet,
          segments: [points],
          elevationsM: elevations,
          sourceName: '徒步星球（SpaceZephyr/trail-planet）',
          sourceUrl: 'https://github.com/SpaceZephyr/trail-planet',
          sourceLicense: 'MIT',
          region: region,
          category: cat,
          seasonDesc: season,
          durationDesc: days,
          description: desc,
        ),
      );
    }

    _cache = routes;
    return routes;
  }

  /// 按地貌、里程筛选。
  Future<List<HikingRoute>> filter({
    String? category,
    double? minKm,
    double? maxKm,
  }) async {
    final all = await loadAll();
    return all.where((r) {
      if (category != null && category != 'all' && r.category != category) {
        return false;
      }
      final km = r.totalDistanceM / 1000.0;
      if (minKm != null && km < minKm) return false;
      if (maxKm != null && km > maxKm) return false;
      return true;
    }).toList();
  }

  /// 随机获取一条经典神线（用于探索巡游模式）。
  Future<HikingRoute> getRandomRoute() async {
    final all = await loadAll();
    return (all..shuffle()).first;
  }
}

final planetTrailsRepositoryProvider = Provider<PlanetTrailsRepository>((ref) {
  return PlanetTrailsRepository();
});

final planetTrailsProvider = FutureProvider<List<HikingRoute>>((ref) async {
  return ref.watch(planetTrailsRepositoryProvider).loadAll();
});
