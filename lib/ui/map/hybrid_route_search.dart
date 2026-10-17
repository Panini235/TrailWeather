import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/geocode.dart';
import '../../data/routes/route_models.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../../core/coord_parse.dart';

class HybridRouteSearchResults extends StatelessWidget {
  const HybridRouteSearchResults({
    super.key,
    required this.query,
    required this.routes,
    required this.places,
    required this.searching,
    required this.onRouteTap,
    required this.onPlaceTap,
    required this.onImportTap,
    required this.onClose,
    this.coordinate,
    this.onCoordinateTap,
  });

  final String query;
  final List<HikingRoute> routes;
  final List<PlaceSuggestion> places;
  final bool searching;
  final ValueChanged<HikingRoute> onRouteTap;
  final ValueChanged<PlaceSuggestion> onPlaceTap;
  final VoidCallback onImportTap;
  final VoidCallback onClose;

  /// 搜索词被识别为经纬度时：放在结果最上方，点击查看该点天气。
  final ParsedCoordinate? coordinate;
  final ValueChanged<ParsedCoordinate>? onCoordinateTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 430),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              ListTile(
                dense: true,
                title: Text(
                  '${S.hybridSearchTitle} · $query',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                trailing: IconButton(
                  tooltip: S.close,
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ),
              if (searching) const LinearProgressIndicator(minHeight: 2),
              if (coordinate case final c?)
                ListTile(
                  leading: const Icon(Icons.gps_fixed, size: 22),
                  title: Text(
                    '${S.coordinateResult} '
                    '${c.point.latitude.toStringAsFixed(5)}, '
                    '${c.point.longitude.toStringAsFixed(5)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      S.selectedPointWeather,
                      if (c.swapped) S.coordinateSwappedNote,
                      S.coordinateNote,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onCoordinateTap == null
                      ? null
                      : () => onCoordinateTap!(c),
                ),
              if (routes.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.route_outlined,
                  title: S.directRoutes,
                  subtitle: '有完整几何，可直接进入沿途天气分析',
                ),
                for (final route in routes.take(6))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.hiking, size: 20),
                    title: Text(route.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${(route.totalDistanceM / 1000).toStringAsFixed(1)} km · '
                      '${routeOriginLabel(route.origin)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: route.isDemo ? const DemoBadge() : null,
                    onTap: () => onRouteTap(route),
                  ),
              ],
              if (places.isNotEmpty) ...[
                const _SectionTitle(
                  icon: Icons.place_outlined,
                  title: S.placeCandidates,
                  subtitle: '先定位到区域，再查附近 OSM 线路',
                ),
                for (final place in places.take(5))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.map_outlined, size: 20),
                    title: Text(place.name, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${place.admin ?? ''} ${place.country ?? ''}'.trim(),
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onPlaceTap(place),
                  ),
              ],
              if (!searching &&
                  coordinate == null &&
                  routes.isEmpty &&
                  places.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(S.noDirectRoutes, style: TextStyle(fontSize: 12)),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.public, size: 20),
                title: const Text('徒步星球 · 全球经典路线'),
                subtitle: const Text('44+ 条雪山/冰川/森林/峡谷世界顶级徒步线路'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/planet'),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.edit_road, size: 20),
                title: const Text('线路规划工坊 (Trail Studio)'),
                subtitle: const Text('在地图上手绘规划、标记营地水源、即时推演天气与耗时'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/planner'),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.file_upload_outlined, size: 20),
                title: const Text(S.importOwnedTrack),
                subtitle: const Text(S.importTrackHint),
                onTap: onImportTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
