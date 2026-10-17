import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_providers.dart';
import '../routes/route_sampling.dart';
import 'weather_repository.dart';

/// 所有格子共享一个联合查询窗；阈值变化不影响请求身份。
class DepartureFetchKey {
  DepartureFetchKey({
    required List<RouteNode> nodes,
    required this.providerId,
    required this.startUtc,
    required this.endUtc,
    this.refresh = 0,
  }) : nodes = List.unmodifiable(nodes),
       coordinates = List.unmodifiable(
         nodes.map((n) => (n.pos.latitude, n.pos.longitude, n.elevationM)),
       );
  final List<RouteNode> nodes;
  final List<(double, double, double?)> coordinates;
  final String providerId;
  final DateTime startUtc;
  final DateTime endUtc;
  final int refresh;

  @override
  bool operator ==(Object other) =>
      other is DepartureFetchKey &&
      providerId == other.providerId &&
      startUtc == other.startUtc &&
      endUtc == other.endUtc &&
      refresh == other.refresh &&
      listEquals(coordinates, other.coordinates);
  @override
  int get hashCode => Object.hash(
    providerId,
    startUtc,
    endUtc,
    refresh,
    Object.hashAll(coordinates),
  );
}

final departureWeatherProvider = StreamProvider.autoDispose
    .family<RouteWeatherBundle, DepartureFetchKey>((ref, key) {
      final repo = ref.watch(weatherRepositoryProvider);
      final source = repo.byId(key.providerId);
      if (source == null || source.caps.onDemandOnly) {
        throw StateError('此来源不支持出发窗口批量比较，请选择其他来源');
      }
      return repo.watchRouteWeatherBundle(
        providerId: key.providerId,
        nodes: key.nodes,
        startUtc: key.startUtc,
        endUtc: key.endUtc,
        refresh: key.refresh > 0,
      );
    });
