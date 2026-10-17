import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/cache_store.dart';
import '../../core/geo.dart';
import '../../core/units.dart';
import '../../data/app_providers.dart';
import '../../data/geocode.dart';
import '../../data/location/location_service.dart';
import '../../data/routes/planet_trails_repository.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/map/tianditu.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_repository.dart';
import '../detail/route_detail_screen.dart';
import 'basemap.dart';
import 'map_layers_ui.dart';
import 'hybrid_route_search.dart';
import 'point_weather_sheet.dart';
import 'route_marks.dart';
import 'route_camera.dart';
import '../strings.dart';
import '../weather_refresh_clock.dart';
import '../widgets/common.dart';
import '../tokens.dart';
import '../../core/coord_parse.dart';

/// 地图首页：地图浏览 → 线路发现 → 进入详情。
///
/// 请求纪律（低耗电）：
/// - 地图拖动期间不发起任何天气/线路网络请求；
/// - 本地线路按 viewport 过滤（纯本地计算）；
/// - 定位成功只移动地图并显示当前位置天气小标签（单点、主来源一次请求），
///   不自动弹出面板、不自动请求 Overpass；
/// - OSM 线路请求只由用户在线路列表中主动触发（海外服务，国内常不可达），缓存 10 分钟；
/// - 首页只进行一次自动定位；之后仅在用户点击定位按钮或地图选点时请求。
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

  /// 搜索词被识别为经纬度时的坐标（不再发起地名搜索）。
  ParsedCoordinate? _coordinate;
  bool _locating = false;
  bool _autoLocateStarted = false;
  LatLng? _weatherPoint;
  LocationFix? _myFix;
  DateTime? _myFixAtUtc;
  String? _myWxText;
  String? _myWxSource;
  late final WeatherRefreshClock _weatherClock;
  StreamSubscription<RouteWeatherBundle>? _myWeatherSubscription;
  int _weatherGeneration = 0;

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

  Basemap get _basemap => Basemap.fromSettings(ref.read(settingsProvider));

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
    setState(() {
      _selected = null;
      _weatherPoint = point;
    });
    _showPointSheet(
      point,
      label: label,
      requestedAtUtc: ref.read(weatherNowProvider)(),
    );
  }

  void _showPointSheet(
    LatLng point, {
    required String label,
    required DateTime requestedAtUtc,
    DateTime? locationAtUtc,
  }) {
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
          locationAtUtc: locationAtUtc,
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
    final coordinate = parseCoordinate(query);
    setState(() {
      _searchQuery = query;
      _coordinate = coordinate;
      _routeMatches = coordinate == null ? _matchRoutes(query) : const [];
      _places = const [];
      _searching = coordinate == null;
    });
    // 经纬度直接查天气，不把坐标发给地名搜索。
    if (coordinate != null) return;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('地点候选加载失败；仍可使用本地线路或导入轨迹。')));
    }
  }

  Future<void> _selectSearchPlace(PlaceSuggestion place) async {
    final query = _searchQuery;
    final point = LatLng(place.lat, place.lon);
    _mapController.move(_basemap.toDisplay(point), 13);
    // 不再自动请求 Overpass（海外服务，国内常不可达）；只用已加载/本地线路。
    if (!mounted || _searchQuery != query) return;
    final namedMatches = _matchRoutes(query);
    final routes = namedMatches.isNotEmpty ? namedMatches : _visibleRoutes();
    setState(() => _routeMatches = routes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          routes.isEmpty
              ? S.placeMovedNoRoutes
              : '已在 ${place.name} 附近找到 ${routes.length} 条可直接分析的线路。',
        ),
      ),
    );
  }

  /// 经纬度搜索：地图移到该点并打开该点天气（与点选地图同一流程）。
  void _selectCoordinate(ParsedCoordinate c) {
    _clearSearch(clearSelected: false);
    try {
      _mapController.move(_basemap.toDisplay(c.point), 12);
    } catch (_) {
      // 地图尚未就绪时忽略；仍打开该点天气。
    }
    _selectWeatherPoint(c.point, label: S.coordinateResult);
  }

  /// 让整条线路落在视野内（避开顶部搜索栏、右侧按钮与底部线路卡）。
  void _fitRoute(HikingRoute route) {
    final fit = routeCameraFit(
      route,
      _basemap,
      padding: const EdgeInsets.fromLTRB(32, 120, 72, 230),
    );
    if (fit == null) return;
    try {
      _mapController.fitCamera(fit);
    } catch (_) {
      // 地图尚未就绪时忽略；线路仍会被选中。
    }
  }

  void _selectSearchRoute(HikingRoute route) {
    _fitRoute(route);
    setState(() {
      _selected = route;
      _weatherPoint = null;
    });
    _clearSearch(clearSelected: false);
  }

  void _clearSearch({bool clearSelected = true}) {
    _searchCtrl.clear();
    if (!mounted) return;
    setState(() {
      _searchQuery = '';
      _places = const [];
      _routeMatches = const [];
      _searching = false;
      _coordinate = null;
      if (clearSelected) _selected = null;
    });
  }

  /// [interactive] 为 false 时是打开地图的自动定位：只在已授权时定位，
  /// 不弹系统授权框，失败也不提示；授权只在用户点“定位”时请求。
  Future<void> _locate({bool interactive = true}) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final fix = await ref
          .read(locationServiceProvider)
          .currentPosition(
            requestPermission: interactive,
            // 系统缓存的上次已知位置先用于居中，减少等待新定位时的空白。
            onLastKnown: (point) {
              if (mounted) _mapController.move(_basemap.toDisplay(point), 13);
            },
          );
      if (!mounted) return;
      _mapController.move(_basemap.toDisplay(fix.point), 13);
      final atUtc = ref.read(weatherNowProvider)();
      setState(() {
        _myFix = fix;
        _myFixAtUtc = atUtc;
        _myWxText = null;
        _myWxSource = null;
      });
      if (fix.isLastKnown) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.lastKnownFallback)));
      }
      unawaited(_loadMyLocationWeather(fix, atUtc));
    } on LocationFailure catch (failure) {
      if (!mounted || !interactive) return;
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
      if (mounted && interactive) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('定位失败。你仍可手动点选地图查询天气。')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  String _primaryProviderId() => primaryProviderId(
    ref.read(settingsProvider).enabledProviderIds,
    ref.read(weatherProvidersProvider),
  );

  String _myLocationSheetLabel(LocationFix fix) =>
      fix.isLastKnown ? S.lastKnownLocation : S.currentLocation;

  /// 当前位置小标签：只取主来源最近时次气温，详情点击后在面板中按来源展示。
  Future<void> _loadMyLocationWeather(LocationFix fix, DateTime atUtc) async {
    final providerId = _primaryProviderId();
    final caps = ref
        .read(weatherProvidersProvider)
        .firstWhere((p) => p.caps.providerId == providerId)
        .caps;
    final generation = ++_weatherGeneration;
    unawaited(_myWeatherSubscription?.cancel());
    if (!mounted || generation != _weatherGeneration) return;
    _myWeatherSubscription =
        watchPointWeather(
          ref.read(weatherRepositoryProvider),
          providerId: providerId,
          point: fix.point,
          label: _myLocationSheetLabel(fix),
          requestedAtUtc: atUtc,
        ).listen(
          (bundle) {
            if (!mounted ||
                generation != _weatherGeneration ||
                !identical(_myFix, fix)) {
              return;
            }
            final points = bundle.result.points;
            // 当前位置标签只显示当前小时；缺口不拿临近小时冒充。
            final hour = points.isEmpty ? null : points.first.hourAt(atUtc);
            final temp = hour?.values[WxVar.temperature];
            setState(() {
              _myWxText = temp == null
                  ? S.myLocationNoTemp
                  : Units.temp(
                      temp,
                      imperial: ref.read(settingsProvider).imperial,
                    );
              _myWxSource =
                  '${caps.displayName}'
                  '${bundle.result.stale ? ' · 旧预报' : ''}'
                  '${bundle.result.refreshing ? ' · 更新中' : ''}'
                  '${bundle.result.refreshFailed ? ' · 更新失败' : ''}';
            });
          },
          onError: (Object error) {
            if (!mounted || generation != _weatherGeneration) return;
            setState(() {
              _myWxText = S.myLocationTapHint;
              _myWxSource = caps.displayName;
            });
          },
        );
  }

  void _refreshCurrentWeather() {
    final fix = _myFix;
    if (fix != null) {
      unawaited(_loadMyLocationWeather(fix, _weatherClock.value));
    }
  }

  void _openMyLocationWeather() {
    final fix = _myFix;
    if (fix == null) return;
    _weatherClock.check();
    _showPointSheet(
      fix.point,
      label: _myLocationSheetLabel(fix),
      requestedAtUtc: ref.read(weatherNowProvider)(),
      locationAtUtc: _myFixAtUtc,
    );
  }

  Marker _myLocationMarker(Basemap basemap, LocationFix fix) {
    final scheme = Theme.of(context).colorScheme;
    final title = fix.isLastKnown ? S.lastKnownChip : S.myLocationChip;
    return Marker(
      point: basemap.toDisplay(fix.point),
      width: 180,
      height: 64,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: _openMyLocationWeather,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Material(
              color: scheme.surface,
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$title · ${_myWxText ?? '…'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_myWxSource != null)
                      Text(
                        _myWxSource!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: fix.isLastKnown ? Semantic.unknown : scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _searchAreaFromList() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_zoom < 11) {
      messenger.showSnackBar(const SnackBar(content: Text(S.areaTooLarge)));
      return;
    }
    messenger
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text(S.osmAreaLoading)));
    final routes = await _searchArea(quiet: true);
    if (!mounted) return;
    messenger.clearSnackBars();
    if (_osmError != null) {
      messenger.showSnackBar(const SnackBar(content: Text(S.osmFetchFail)));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            routes.isEmpty ? S.osmAreaEmpty : '已加载 ${routes.length} 条 OSM 线路。',
          ),
        ),
      );
    }
  }

  void _autoLocate() {
    if (_autoLocateStarted) return;
    _autoLocateStarted = true;
    unawaited(_locate(interactive: false));
  }

  @override
  void initState() {
    super.initState();
    _weatherClock = WeatherRefreshClock(
      initialUtc: ref.read(weatherNowProvider)(),
      nowUtc: ref.read(weatherNowProvider),
    )..addListener(_refreshCurrentWeather);
  }

  @override
  void dispose() {
    _weatherGeneration++;
    _myWeatherSubscription?.cancel();
    _weatherClock.dispose();
    _mapController.dispose();
    _hitNotifier.dispose();
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
    final basemap = Basemap.fromSettings(
      ref.watch(settingsProvider),
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );

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
              ...basemap.tileLayers(),
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
                              ? Semantic.route
                              : (r.isDemo
                                    ? Semantic.planetRoute
                                    : Semantic.osmRoute),
                          borderStrokeWidth: r.id == selectedId ? 2 : 0,
                          borderColor: Colors.white,
                          hitValue: r.id,
                        ),
                  ],
                ),
              ),
              // 选中线路：方向箭头与起终点
              if (_selected != null) routeDirectionLayer(_selected!, basemap),
              if (_selected != null) routeEndpointLayer(_selected!, basemap),
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
              if (_myFix != null)
                MarkerLayer(markers: [_myLocationMarker(basemap, _myFix!)]),
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
                      onImportTap: () => context.push('/import'),
                      onClose: () => _clearSearch(clearSelected: false),
                      coordinate: _coordinate,
                      onCoordinateTap: _selectCoordinate,
                    ),
                  const TiandituErrorBanner(margin: EdgeInsets.only(top: 6)),
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
                    const MapLayerButton(),
                    const SizedBox(height: 10),
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
                      heroTag: 'list',
                      onPressed: () => _showRouteList(visible),
                      tooltip: S.listButton,
                      child: const Icon(Icons.list),
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
                _fitRoute(r);
                setState(() {
                  _selected = r;
                  _weatherPoint = null;
                });
              },
            ),
          const Divider(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _osmLoading
                  ? null
                  : () {
                      Navigator.pop(context);
                      unawaited(_searchAreaFromList());
                    },
              icon: const Icon(Icons.travel_explore, size: 18),
              label: const Text(S.tryOsmArea),
            ),
          ),
          Text(
            S.tryOsmAreaNote,
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
