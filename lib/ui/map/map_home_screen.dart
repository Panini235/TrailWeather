import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/cache_store.dart';
import '../../core/geo.dart';
import '../../data/app_providers.dart';
import '../../data/geocode.dart';
import '../../data/location/location_service.dart';
import '../../data/monetization/subscription_repository.dart';
import '../../data/routes/external_trail_search.dart';
import '../../data/routes/planet_trails_repository.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../detail/route_detail_screen.dart';
import 'basemap.dart';
import 'hybrid_route_search.dart';
import 'point_weather_sheet.dart';
import '../strings.dart';
import '../widgets/common.dart';

/// 地图首页：地图浏览 → 线路发现 → 进入详情。
///
/// 请求纪律（低耗电）：
/// - 地图拖动期间不发起任何天气/线路网络请求；
/// - 本地线路按 viewport 过滤（纯本地计算）；
/// - 首次定位成功后自动查询一次当地线路；其余线路请求由用户触发，缓存 10 分钟；
/// - 首页只进行一次定位；之后仅在用户点击定位按钮或地图选点时请求。
class MapHomeScreen extends ConsumerStatefulWidget {
  const MapHomeScreen({super.key});

  @override
  ConsumerState<MapHomeScreen> createState() => _MapHomeScreenState();
}

class _MapHomeScreenState extends ConsumerState<MapHomeScreen> {
  final MapController _mapController = MapController();
  final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);
  final TextEditingController _searchCtrl = TextEditingController();

  static const _initialCenter = LatLng(39.99, 116.17); // 北京西山示例线路附近
  static const _initialZoom = 12.0;

  List<HikingRoute> _osmRoutes = const [];
  HikingRoute? _selected;
  bool _osmLoading = false;
  String? _osmError;
  List<PlaceSuggestion> _places = const [];
  List<HikingRoute> _routeMatches = const [];
  String _searchQuery = '';
  bool _searching = false;
  bool _locating = false;
  bool _autoLocateStarted = false;
  LatLng? _weatherPoint;

  double get _zoom {
    try {
      return _mapController.camera.zoom;
    } catch (_) {
      return _initialZoom;
    }
  }

  /// 业务坐标（WGS-84）包围盒：底图为 GCJ-02 时把可视范围逆变换，
  /// 供 Overpass 查询与本地线路过滤使用。
  (double, double, double, double) get _bbox {
    try {
      final b = _basemap.toBusinessBounds(_mapController.camera.visibleBounds);
      return (b.south, b.west, b.north, b.east);
    } catch (_) {
      return (39.9, 116.0, 40.1, 116.3);
    }
  }

  Basemap get _basemap => Basemap(ref.read(settingsProvider).basemap);

  void _onTapMap(TapPosition pos, LatLng displayPoint) {
    // 点击线路时由 PolylineLayer 的命中通知器处理，不同时弹出点位天气。
    final hit = _hitNotifier.value;
    if (hit != null && hit.hitValues.isNotEmpty) return;
    _selectWeatherPoint(
      _basemap.toBusiness(displayPoint),
      label: S.selectedPointWeather,
    );
  }

  void _selectWeatherPoint(LatLng point, {required String label}) {
    if (!mounted) return;
    final requestedAtUtc = DateTime.now().toUtc();
    setState(() {
      _selected = null;
      _weatherPoint = point;
    });
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.82,
        child: PointWeatherSheet(
          point: point,
          label: label,
          requestedAtUtc: requestedAtUtc,
        ),
      ),
    );
  }

  HikingRoute? _findById(List<HikingRoute> all, String id) {
    for (final r in all) {
      if (r.id == id) return r;
    }
    return null;
  }

  List<HikingRoute> _allKnownRoutes() {
    final byId = <String, HikingRoute>{};
    final planetTrails = ref.read(planetTrailsProvider).value ?? const [];
    for (final route in [
      ...ref.read(localRoutesProvider),
      ..._osmRoutes,
      ...planetTrails,
    ]) {
      byId[route.id] = route;
    }
    return byId.values.toList();
  }

  List<HikingRoute> _visibleRoutes() {
    final (minLat, minLon, maxLat, maxLon) = _bbox;
    return _allKnownRoutes()
        .where(
          (route) => route.intersectsBBox(
            minLat - 0.05,
            minLon - 0.05,
            maxLat + 0.05,
            maxLon + 0.05,
          ),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<HikingRoute> _matchRoutes(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    int score(HikingRoute route) {
      final name = route.name.toLowerCase();
      final source = route.sourceName.toLowerCase();
      if (name == query) return 0;
      if (name.startsWith(query)) return 1;
      if (name.contains(query)) return 2;
      if (source.contains(query)) return 3;
      return 99;
    }

    final matches = _allKnownRoutes()
        .where((route) => score(route) < 99)
        .toList();
    matches.sort((a, b) {
      final byScore = score(a).compareTo(score(b));
      return byScore != 0 ? byScore : a.name.compareTo(b.name);
    });
    return matches;
  }

  Future<List<HikingRoute>> _searchArea({bool quiet = false}) async {
    final (minLat, minLon, maxLat, maxLon) = _bbox;
    if (_zoom < 11) {
      if (!quiet) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.areaTooLarge)));
      }
      return const [];
    }
    final src = ref.read(overpassRouteSourceProvider);
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
        if (!mounted) return routes;
        setState(() {
          _osmRoutes = routes;
          _osmLoading = false;
        });
        return routes;
      }
      final routes = await src.fetchRoutesInBBox(
        minLat,
        minLon,
        maxLat,
        maxLon,
      );
      await cache.write(
        CacheNs.map,
        'overpass|$key',
        routes.map((r) => r.encode()).join('\u241F'),
        const Duration(minutes: 10),
      );
      if (!mounted) return routes;
      setState(() {
        _osmRoutes = routes;
        _osmLoading = false;
      });
      return routes;
    } catch (e) {
      if (mounted) {
        setState(() {
          _osmLoading = false;
          _osmError = e.toString();
        });
      }
      return const [];
    }
  }

  Future<void> _doSearch(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      _clearSearch();
      return;
    }
    setState(() {
      _searchQuery = query;
      _routeMatches = _matchRoutes(query);
      _places = const [];
      _searching = true;
    });
    try {
      final places = await ref.read(geocodeServiceProvider).search(query);
      if (!mounted || _searchQuery != query) return;
      setState(() {
        _places = places;
        _routeMatches = _matchRoutes(query);
        _searching = false;
      });
    } catch (_) {
      if (!mounted || _searchQuery != query) return;
      setState(() => _searching = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地点候选加载失败；仍可使用本地线路和外部攻略入口。')),
      );
    }
  }

  Future<void> _selectSearchPlace(PlaceSuggestion place) async {
    final query = _searchQuery;
    final point = LatLng(place.lat, place.lon);
    _mapController.move(_basemap.toDisplay(point), 13);
    setState(() => _searching = true);
    await _searchArea(quiet: true);
    if (!mounted || _searchQuery != query) return;
    final namedMatches = _matchRoutes(query);
    final routes = namedMatches.isNotEmpty ? namedMatches : _visibleRoutes();
    setState(() {
      _routeMatches = routes;
      _searching = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          routes.isEmpty
              ? '该区域暂未找到可直接分析的 OSM 线路，可查看外部攻略或导入 GPX。'
              : '已在 ${place.name} 附近找到 ${routes.length} 条可直接分析的线路。',
        ),
      ),
    );
  }

  void _selectSearchRoute(HikingRoute route) {
    final first = route.mainSegment.first;
    _mapController.move(_basemap.toDisplay(first), 13);
    setState(() {
      _selected = route;
      _weatherPoint = null;
    });
    _clearSearch(clearSelected: false);
  }

  Future<void> _openExternalSearch(ExternalTrailSearchTarget target) async {
    final opened = await ref.read(externalUrlLauncherProvider).open(target.uri);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法打开 ${target.label} 网页搜索，请检查浏览器设置。')),
      );
    }
  }

  void _clearSearch({bool clearSelected = true}) {
    _searchCtrl.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _places = const [];
      _routeMatches = const [];
      _searching = false;
      if (clearSelected) _selected = null;
    });
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final point = await ref.read(locationServiceProvider).currentPosition();
      if (!mounted) return;
      _mapController.move(_basemap.toDisplay(point), 13);
      _selectWeatherPoint(point, label: S.currentLocation);
      // 定位成功后补齐“打开首页就看到当地线路”的闭环；缓存避免重复消耗。
      unawaited(_searchArea(quiet: true));
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      final canOpenSettings =
          failure.kind == LocationFailureKind.serviceDisabled ||
          failure.kind == LocationFailureKind.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: canOpenSettings
              ? SnackBarAction(
                  label: S.locationSettings,
                  onPressed: () => ref
                      .read(locationServiceProvider)
                      .openSettings(failure.kind),
                )
              : null,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('定位失败。你仍可手动点选地图查询天气。')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _autoLocate() {
    if (_autoLocateStarted) return;
    _autoLocateStarted = true;
    unawaited(_locate());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final settings = ref.read(settingsProvider);
      if (!settings.hasCompletedOnboarding) {
        try {
          context.push('/onboarding');
        } catch (_) {}
      }
    });
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
      ...locals.where(
        (r) => r.intersectsBBox(
          minLat - 0.05,
          minLon - 0.05,
          maxLat + 0.05,
          maxLon + 0.05,
        ),
      ),
    ]..sort((a, b) => a.name.compareTo(b.name));

    final selectedId = _selected?.id;
    final basemap = Basemap(ref.watch(settingsProvider).basemap);
    final sub = ref.watch(subscriptionProvider);
    final isPro = sub.isPro;

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
              onMapReady: _autoLocate,
              onTap: _onTapMap,
            ),
            children: [
              basemap.tileLayer(),
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
                  if (route != null) {
                    setState(() {
                      _selected = route;
                      _weatherPoint = null;
                    });
                  }
                },
                child: PolylineLayer<String>(
                  hitNotifier: _hitNotifier,
                  simplificationTolerance: 0,
                  polylines: [
                    for (final r in visible)
                      for (final seg in r.segments)
                        Polyline<String>(
                          // 简化在 WGS-84 业务几何上做，渲染坐标按底图转换
                          points: [
                            for (final pt in Geo.simplify(
                              seg,
                              _zoom >= 14 ? 15 : 40,
                            ))
                              basemap.toDisplay(pt),
                          ],
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
              if (_weatherPoint != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: basemap.toDisplay(_weatherPoint!),
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        Icons.location_on,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black45),
                        ],
                      ),
                    ),
                  ],
                ),
              basemap.attributionWidget(),
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
                  if (_searchQuery.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Material(
                          color: Theme.of(context).colorScheme.surface
                              .withValues(alpha: 0.86),
                          borderRadius: BorderRadius.circular(8),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            child: Text(
                              S.tapMapWeatherHint,
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    HybridRouteSearchResults(
                      query: _searchQuery,
                      routes: _routeMatches,
                      places: _places,
                      searching: _searching,
                      onRouteTap: _selectSearchRoute,
                      onPlaceTap: _selectSearchPlace,
                      onExternalTap: _openExternalSearch,
                      onImportTap: () => context.push('/import'),
                      onClose: () => _clearSearch(clearSelected: false),
                    ),
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
                      onPressed: _locating ? null : _locate,
                      tooltip: _locating ? S.locating : S.locateMe,
                      child: _locating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'searchArea',
                      onPressed: _osmLoading ? null : () => _searchArea(),
                      tooltip: S.searchThisArea,
                      child: _osmLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'proBadge',
                      backgroundColor: isPro ? Colors.amber.shade700 : null,
                      onPressed: () => context.push('/paywall'),
                      tooltip: isPro ? 'TrailWeather Pro 已激活' : 'Pro 方案预览（开发中）',
                      child: Icon(
                        Icons.workspace_premium,
                        color: isPro ? Colors.white : Colors.amber.shade800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'planet',
                      onPressed: () => context.push('/planet'),
                      tooltip: '徒步星球 · 全球经典路线',
                      child: const Icon(Icons.public),
                    ),
                    const SizedBox(height: 10),
                    FloatingActionButton.small(
                      heroTag: 'planner',
                      onPressed: () => context.push('/planner'),
                      tooltip: '线路规划工坊 (Trail Studio)',
                      child: const Icon(Icons.edit_road),
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
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

  void _showRouteList(List<HikingRoute> visible) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          Text(
            S.routeListTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
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
                children: [Text(r.name), if (r.isDemo) const DemoBadge()],
              ),
              subtitle: Text(
                '${(r.totalDistanceM / 1000).toStringAsFixed(1)} km · '
                '${r.totalAscentM == null ? S.unknown : '↑${(r.totalAscentM! / 1000).toStringAsFixed(2)} km'} · '
                '${routeOriginLabel(r.origin)}',
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                setState(() {
                  _selected = r;
                  _weatherPoint = null;
                });
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
                        Text(
                          route.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
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
                  IconButton(icon: const Icon(Icons.close), onPressed: onClose),
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
                  onPressed: () => context.push(
                    '/route/${route.id}',
                    extra: RouteDetailArgs(route: route),
                  ),
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
