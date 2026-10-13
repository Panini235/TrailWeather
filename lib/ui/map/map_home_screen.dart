import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/cache_store.dart';
import '../../core/geo.dart';
import '../../data/app_providers.dart';
import '../../data/geocode.dart';
import '../../data/routes/overpass.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../detail/route_detail_screen.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 地图首页：地图浏览 → 线路发现 → 进入详情。
///
/// 请求纪律（低耗电）：
/// - 地图拖动期间不发起任何天气/线路网络请求；
/// - 本地线路按 viewport 过滤（纯本地计算）；
/// - OSM 线路仅在用户点击“搜索此区域”时请求一次，结果缓存 10 分钟；
/// - 定位仅在用户点击按钮时请求。
class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key});

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);
  final TextEditingController _searchCtrl = TextEditingController();
  final GeocodeService _geocode = GeocodeService();

  static const _initialCenter = LatLng(39.99, 116.17); // 北京西山示例线路附近
  static const _initialZoom = 12.0;

  List<HikingRoute> _osmRoutes = const [];
  HikingRoute? _selected;
  bool _osmLoading = false;
  String? _osmError;
  List<PlaceSuggestion> _suggestions = const [];
  bool _searching = false;

  double get _zoom {
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return _initialZoom;
    }
  }

  (double, double, double, double) get _bbox {
    try {
      final b = _mapController.camera.visibleBounds;
      return (b.south, b.west, b.north, b.east);
    } catch (_) {
      return (39.9, 116.0, 40.1, 116.3);
    }
  }

  void _onTapMap(TapPosition pos, LatLng latlng) {
    // 命中检测由 PolylineLayer 的 hitNotifier 完成（见 GestureDetector onTap）。
    if (_selected != null) {
      setState(() => _selected = null);
    }
  }

  HikingRoute? _findById(List<HikingRoute> all, String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> _searchArea() async {
    final (minLat, minLon, maxLat, maxLon) = _bbox;
    if (_zoom < 11) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(S.areaTooLarge)));
      return;
    }
    final src = OverpassRouteSource();
    setState(() {
      _osmLoading = true;
      _osmError = null;
    });
    try {
      final cache = CacheStore(ref.read(prefsProvider));
      final key =
          '${minLat.toStringAsFixed(1)}|${minLon.toStringAsFixed(1)}|${maxLat.toStringAsFixed(1)}|${maxLon.toStringAsFixed(1)}';
      final hit = await cache.read(CacheNs.map, 'overpass|$key');
      if (hit != null && !hit.isExpired) {
        final routes = [
          for (final e in hit.payload.split('\u241F'))
            if (e.isNotEmpty) HikingRoute.decode(e),
        ];
        setState(() {
          _osmRoutes = routes;
          _osmLoading = false;
        });
        return;
      }
      final routes = await src.fetchRoutesInBBox(
          minLat, minLon, maxLat, maxLon);
      await cache.write(
          CacheNs.map, 'overpass|$key', routes.map((r) => r.encode()).join('\u241F'),
          const Duration(minutes: 10));
      setState(() {
        _osmRoutes = routes;
        _osmLoading = false;
      });
    } catch (e) {
      setState(() {
        _osmLoading = false;
        _osmError = e.toString();
      });
    }
  }

  Future<void> _doSearch(String q) async {
    setState(() => _searching = true);
    try {
      final results = await _geocode.search(q);
      setState(() {
        _suggestions = results;
        _searching = false;
      });
    } catch (_) {
      setState(() {
        _suggestions = const [];
        _searching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('地点搜索失败，请稍后重试')));
      }
    }
  }

  Future<void> _locate() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text(S.locationDenied)));
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      _mapController.move(LatLng(pos.latitude, pos.longitude), 13);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('定位失败。你仍然可以搜索地点或手动浏览地图。')));
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locals = ref.watch(localRoutesProvider);
    final (minLat, minLon, maxLat, maxLon) = _bbox;
    final visible = <HikingRoute>[
      ..._osmRoutes,
      ...locals.where((r) =>
          r.intersectsBBox(minLat - 0.05, minLon - 0.05, maxLat + 0.05, maxLon + 0.05)),
    ]..sort((a, b) => a.name.compareTo(b.name));

    final selectedId = _selected?.id;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _initialCenter,
              initialZoom: _initialZoom,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _onTapMap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'dev.trailweather.trailweather',
              ),
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: () {
                  final hit = _hitNotifier.value;
                  if (hit == null || hit.hitValues.isEmpty) {
                    if (_selected != null) {
                      setState(() => _selected = null);
                    }
                    return;
                  }
                  final all = [...ref.read(localRoutesProvider), ..._osmRoutes];
                  final route = _findById(all, hit.hitValues.first);
                  if (route != null) setState(() => _selected = route);
                },
                child: PolylineLayer<String>(
                  hitNotifier: _hitNotifier,
                  simplificationTolerance: 0,
                  polylines: [
                    for (final r in visible)
                      for (final seg in r.segments)
                        Polyline<String>(
                          points: Geo.simplify(
                              seg, _zoom >= 14 ? 15 : 40),
                          strokeWidth: r.id == selectedId ? 7 : 4,
                          color: r.id == selectedId
                              ? const Color(0xFF1565C0)
                              : (r.isDemo
                                  ? const Color(0xCC2E7D32)
                                  : const Color(0xCC7B1FA2)),
                          borderStrokeWidth: r.id == selectedId ? 2 : 0,
                          borderColor: Colors.white,
                          hitValue: r.id,
                        ),
                  ],
                ),
              ),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    '© OpenStreetMap 贡献者',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),

          // 顶部搜索条
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchBar(),
                  if (_suggestions.isNotEmpty) _buildSuggestions(),
                ],
              ),
            ),
          ),

          // 右侧操作按钮
          SafeArea(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FloatingActionButton.small(
                      heroTag: 'locate',
                      onPressed: _locate,
                      tooltip: S.locateMe,
                      child: const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'searchArea',
                      onPressed: _osmLoading ? null : _searchArea,
                      tooltip: S.searchThisArea,
                      child: _osmLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.travel_explore),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'list',
                      onPressed: () => _showRouteList(visible),
                      tooltip: S.listButton,
                      child: const Icon(Icons.list),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'import',
                      onPressed: () => context.push('/import'),
                      tooltip: S.importRoute,
                      child: const Icon(Icons.file_upload_outlined),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'settings',
                      onPressed: () => context.push('/settings'),
                      tooltip: S.settings,
                      child: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部选中线路卡
          if (_selected != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: _SelectedRouteCard(
                route: _selected!,
                onClose: () => setState(() => _selected = null),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: S.searchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _searching
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () => _doSearch(_searchCtrl.text),
              ),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        isDense: true,
      ),
      onSubmitted: _doSearch,
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black26)],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, i) {
          final s = _suggestions[i];
          return ListTile(
            dense: true,
            title: Text(s.name, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${s.admin ?? ''} ${s.country ?? ''}'.trim(),
                style: const TextStyle(fontSize: 12)),
            onTap: () {
              setState(() => _suggestions = const []);
              _mapController.move(LatLng(s.lat, s.lon), 12.5);
            },
          );
        },
      ),
    );
  }

  void _showRouteList(List<HikingRoute> visible) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          Text(S.routeListTitle,
              style: Theme.of(context).textTheme.titleMedium),
          if (_osmError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: GranularityNotice(text: S.osmFetchFail),
            ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(S.emptyRoutes)),
            ),
          for (final r in visible)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(r.name),
                  if (r.isDemo) const DemoBadge(),
                ],
              ),
              subtitle: Text(
                '${(r.totalDistanceM / 1000).toStringAsFixed(1)} km · '
                '${r.totalAscentM == null ? S.unknown : '↑${(r.totalAscentM! / 1000).toStringAsFixed(2)} km'} · '
                '${routeOriginLabel(r.origin)}',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selected = r);
              },
            ),
        ],
      ),
    );
  }
}

class _SelectedRouteCard extends ConsumerWidget {
  const _SelectedRouteCard({required this.route, required this.onClose});

  final HikingRoute route;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favs = ref.watch(favoritesProvider);
    final isFav = favs.any((r) => r.id == route.id);
    return SafeArea(
      child: Card(
        margin: const EdgeInsets.all(12),
        elevation: 6,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(route.name,
                            style: Theme.of(context).textTheme.titleMedium),
                        if (route.isDemo) const DemoBadge(),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(isFav ? Icons.star : Icons.star_border),
                    tooltip: S.favorites,
                    onPressed: () =>
                        ref.read(favoritesProvider.notifier).toggle(route),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: onClose,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${S.distanceLabel}：${(route.totalDistanceM / 1000).toStringAsFixed(1)} km　'
                '${S.ascentLabel}：${route.totalAscentM == null ? S.unknown : '${(route.totalAscentM! / 1000).toStringAsFixed(2)} km'}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 4),
              RouteSourceLine(route: route),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => context.push('/route/${route.id}',
                      extra: RouteDetailArgs(route: route)),
                  icon: const Icon(Icons.insights_outlined, size: 18),
                  label: Text(S.viewDetail),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
