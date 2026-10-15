import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../core/units.dart';
import '../../data/app_providers.dart';
import '../../data/map/tianditu.dart';
import '../../data/routes/route_models.dart';
import '../../data/routes/route_sampling.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/photos/route_photos.dart';
import '../../data/weather/eta.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/risk_rules.dart';
import '../../data/weather/weather_models.dart';
import '../../data/weather/weather_provider.dart';
import '../../data/weather/weather_repository.dart';
import '../strings.dart';
import '../widgets/common.dart';
import '../map/basemap.dart';
import '../map/map_layers_ui.dart';
import '../map/route_camera.dart';
import '../map/route_marks.dart';
import 'detail_state.dart';
import 'elevation_profile.dart';
import 'node_detail_view.dart';
import 'node_photos.dart';
import 'node_wx_style.dart';
import 'weather_cells.dart';

class RouteDetailArgs {
  const RouteDetailArgs({required this.route});
  final HikingRoute route;
}

/// 详情页天气数据提供者：参数为（节点序列, 查询）。
/// 必须实现 ==：family 依赖键相等判断，避免每帧重建触发重复请求。
class DetailFetchKey {
  const DetailFetchKey({required this.nodes, required this.query});
  final List<RouteNode> nodes;
  final RouteWeatherQuery query;

  String _nodesSig() => nodes.isEmpty
      ? '0'
      : '${nodes.length}:${nodes.first.distFromStartM.toStringAsFixed(1)}:'
            '${nodes.last.distFromStartM.toStringAsFixed(1)}';

  @override
  bool operator ==(Object other) =>
      other is DetailFetchKey &&
      other.query == query &&
      other._nodesSig() == _nodesSig();

  @override
  int get hashCode => Object.hash(query, _nodesSig());
}

final detailWeatherProvider = FutureProvider.autoDispose
    .family<RouteWeatherBundle, DetailFetchKey>((ref, key) async {
      final repo = ref.watch(weatherRepositoryProvider);
      return repo.getRouteWeatherBundle(
        providerId: key.query.providerId,
        nodes: key.nodes,
        startUtc: key.query.startUtc,
        endUtc: key.query.endUtc,
      );
    });

class RouteDetailScreen extends ConsumerStatefulWidget {
  const RouteDetailScreen({super.key, required this.args});

  final RouteDetailArgs args;

  @override
  ConsumerState<RouteDetailScreen> createState() => _RouteDetailScreenState();
}

class _RouteDetailScreenState extends ConsumerState<RouteDetailScreen> {
  TimeMode _mode = TimeMode.fixed;
  // 固定时刻默认：上午 10 点前为当天 10:00，之后为下一个整点（避免默认落在已过去的时刻）。
  late DateTime _date = _defaultFixedLocal();
  late int _hour = _date.hour;
  TimeOfDay _startTime = const TimeOfDay(hour: 7, minute: 0);
  PaceConfig _pace = PaceConfig.defaults;
  late String _providerId;
  int? _selectedNode;
  double? _previewHour; // 滑块拖动中的预览（不触发请求）

  /// 用户标记会更新这条线路（并保存到“我的行程”）；反向行走只是视图状态。
  late HikingRoute _base = widget.args.route;
  bool _reversed = false;
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _tileKeys = {};

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// 选中节点：地图标记、海拔剖面、时间线三处共享同一选中状态。
  void _select(int i, {bool scroll = false}) {
    setState(() => _selectedNode = i);
    if (!scroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _tileKeys[i]?.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.3,
        );
      }
    });
  }

  void _toggleReverse() {
    setState(() {
      _reversed = !_reversed;
      _selectedNode = null;
    });
  }

  // ---- 标记（营地 / 休息点 …）----

  Future<void> _persist(HikingRoute updated) async {
    final wasSaved = ref.read(favoritesProvider).any((r) => r.id == updated.id);
    setState(() => _base = updated);
    await ref.read(favoritesProvider.notifier).add(updated);
    if (!wasSaved && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.markSavedNew)));
    }
  }

  Future<RouteWaypoint?> _editDialog(RouteWaypoint initial) {
    final nameCtrl = TextEditingController(text: initial.name);
    final stopCtrl = TextEditingController(
      text: initial.stopMinutes?.toString() ?? '',
    );
    var type = initial.type;
    return showDialog<RouteWaypoint>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(initial.name.isEmpty ? S.markAs : S.editMark),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<WaypointType>(
                initialValue: type,
                items: [
                  for (final t in WaypointType.values)
                    DropdownMenuItem(
                      value: t,
                      child: Text(waypointTypeLabel(t)),
                    ),
                ],
                onChanged: (t) => setLocal(() {
                  if (t == null) return;
                  // 名称仍是默认类型名时跟随类型变化
                  if (nameCtrl.text == defaultWaypointName(type)) {
                    nameCtrl.text = defaultWaypointName(t);
                  }
                  type = t;
                }),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: S.markName),
              ),
              if (type != WaypointType.camp)
                TextField(
                  controller: stopCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: S.markStopMinutes,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(S.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final stop = int.tryParse(stopCtrl.text.trim());
                Navigator.pop(
                  ctx,
                  RouteWaypoint(
                    name: name.isEmpty ? defaultWaypointName(type) : name,
                    point: initial.point,
                    type: type,
                    desc: initial.desc,
                    elevationM: initial.elevationM,
                    stopMinutes: type == WaypointType.camp || stop == null
                        ? null
                        : stop.clamp(0, 24 * 60),
                  ),
                );
              },
              child: const Text(S.save),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMark(LatLng at, WaypointType type, {double? ele}) async {
    final created = await _editDialog(
      RouteWaypoint(
        name: defaultWaypointName(type),
        point: at,
        type: type,
        elevationM: ele,
        stopMinutes: type == WaypointType.rest ? 15 : null,
      ),
    );
    if (created == null) return;
    await _persist(_base.copyWith(waypoints: [..._base.waypoints, created]));
  }

  Future<void> _editMark(RouteWaypoint wp) async {
    final edited = await _editDialog(wp);
    if (edited == null) return;
    await _persist(
      _base.copyWith(
        waypoints: [
          for (final w in _base.waypoints) identical(w, wp) ? edited : w,
        ],
      ),
    );
  }

  Future<void> _removeMark(RouteWaypoint wp) async {
    await _persist(
      _base.copyWith(
        waypoints: [
          for (final w in _base.waypoints)
            if (!identical(w, wp)) w,
        ],
      ),
    );
  }

  /// 全屏地图返回：int = 查看该节点详情；LatLng = 在此处添加标记（已吸附检查）。
  Future<void> _openFullMap(
    HikingRoute route,
    List<NodeWxRow> rows,
    AppSettings settings,
  ) async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _RouteFullMapPage(
          route: route,
          rows: rows,
          selectedIndex: _selectedNode,
          onSelect: (i) => _select(i),
        ),
      ),
    );
    if (!mounted) return;
    if (result is int) {
      _select(result, scroll: true);
      _showNodeSheet(rows, settings, initialIndex: result);
    } else if (result is LatLng) {
      final path = route.analysisPath.points;
      final snapped = snapWaypoints(path, [
        RouteWaypoint(name: '', point: result, type: WaypointType.poi),
      ]);
      if (snapped.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.markTooFar)));
        return;
      }
      final idx = snapped.keys.first;
      await _addMark(
        path[idx],
        WaypointType.rest,
        ele: route.analysisPath.elevations[idx],
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _providerId = primaryProviderId(
      ref.read(settingsProvider).enabledProviderIds,
      ref.read(weatherProvidersProvider),
    );
  }

  static DateTime _defaultFixedLocal() {
    final now = DateTime.now();
    if (now.hour < 10) return DateTime(now.year, now.month, now.day, 10);
    return DateTime(now.year, now.month, now.day, now.hour + 1); // 23 点会进位到次日
  }

  (DateTime, DateTime) _utcWindow(List<RouteNode> nodes, List<DateTime> etas) {
    if (_mode == TimeMode.fixed) {
      final f = _fixedUtc();
      return (f, f.add(const Duration(hours: 1)));
    }
    final start = _tripStartUtc();
    final end = (etas.isEmpty ? start : etas.last).add(
      const Duration(hours: 1),
    );
    return (start, end.isBefore(start) ? start : end);
  }

  DateTime _fixedUtc() {
    // 滑块拖动期间仅更新 _previewHour（不触发查询），松手才提交 _hour。
    return DateTime(_date.year, _date.month, _date.day, _hour).toUtc();
  }

  DateTime _tripStartUtc() => DateTime(
    _date.year,
    _date.month,
    _date.day,
    _startTime.hour,
    _startTime.minute,
  ).toUtc();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final route = _reversed ? _base.reversed() : _base;
    final nodes = nodesForRoute(
      route,
      spacingKm: settings.effectiveSamplingSpacingKm,
      maxNodes: settings.effectiveMaxNodes,
    );
    final etas = _mode == TimeMode.trip
        ? computeEtas(nodes: nodes, startUtc: _tripStartUtc(), pace: _pace)
        : List<DateTime>.generate(nodes.length, (_) => _fixedUtc());
    final (startUtc, endUtc) = _utcWindow(nodes, etas);
    final query = RouteWeatherQuery(
      routeId: route.id,
      providerId: _providerId,
      mode: _mode,
      startUtc: startUtc,
      endUtc: endUtc,
      fixedUtc: _mode == TimeMode.fixed ? _fixedUtc() : _tripStartUtc(),
      pace: _pace,
    );
    final bundleAsync = ref.watch(
      detailWeatherProvider(DetailFetchKey(nodes: nodes, query: query)),
    );

    final rows = buildNodeRows(
      nodes: nodes,
      bundle: bundleAsync.value,
      mode: _mode,
      fixedUtc: query.fixedUtc,
      etas: etas,
    );

    return Scaffold(
      appBar: AppBar(
        title: Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(route.name, style: const TextStyle(fontSize: 16)),
            if (route.isDemo) const DemoBadge(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined),
            tooltip: '离线气象与轨迹包（开发中）',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('离线气象与轨迹包（开发中）'),
                content: const Text(
                  '该功能尚未上线：当前不会下载或缓存任何离线数据，'
                  '无信号时请勿依赖本 App 获取天气。\n\n'
                  '已查看过的天气会按来源有效期短暂缓存，过期后会标注“旧数据”。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(S.close),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              ref.watch(favoritesProvider).any((r) => r.id == route.id)
                  ? Icons.star
                  : Icons.star_border,
            ),
            tooltip: S.favorites,
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(_base),
          ),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        children: [
          _RouteMiniMap(
            route: route,
            rows: rows,
            selectedIndex: _selectedNode,
            onTapNode: (i) => _select(i, scroll: true),
            onOpenFullscreen: () => _openFullMap(route, rows, settings),
          ),
          const SizedBox(height: 8),
          _RouteFactsCard(
            route: route,
            reversed: _reversed,
            onToggleReverse: _toggleReverse,
          ),
          const SizedBox(height: 8),
          _TimeControlsCard(
            mode: _mode,
            onMode: (m) => setState(() => _mode = m),
            date: _date,
            onDate: (d) => setState(() => _date = d),
            hour: _hour,
            previewHour: _previewHour,
            onHourPreview: (h) => setState(() => _previewHour = h),
            onHourCommit: (h) => setState(() {
              _hour = h;
              _previewHour = null;
            }),
            startTime: _startTime,
            onStartTime: (t) => setState(() => _startTime = t),
            pace: _pace,
            onPace: (p) => setState(() => _pace = p),
          ),
          const SizedBox(height: 8),
          _SourceChips(
            selected: _providerId,
            onSelect: (id) => setState(() => _providerId = id),
            onCompare: () => _showNodeSheet(rows, settings),
          ),
          const SizedBox(height: 8),
          ..._weatherSection(
            bundleAsync,
            rows,
            settings,
            nodes,
            etas,
            route,
            query,
          ),
        ],
      ),
    );
  }

  List<Widget> _weatherSection(
    AsyncValue<RouteWeatherBundle> bundleAsync,
    List<NodeWxRow> rows,
    AppSettings settings,
    List<RouteNode> nodes,
    List<DateTime> etas,
    HikingRoute route,
    RouteWeatherQuery query,
  ) {
    final provider = ref
        .read(weatherProvidersProvider)
        .where((p) => p.caps.providerId == _providerId)
        .first;
    if (bundleAsync.isLoading && !bundleAsync.hasValue) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    if (bundleAsync.hasError) {
      final err = bundleAsync.error;
      if (err is WxOutOfRange) {
        return [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_busy, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        S.outOfRange,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    S.outOfRangeDetail,
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ];
      }
      return [
        ErrorCard(
          title: '来源请求失败（${provider.caps.displayName}）',
          detail: '${err.toString()}\n数据未获取，以下显示为空，不会用历史值冒充。',
          onRetry: () => ref.invalidate(
            detailWeatherProvider(DetailFetchKey(nodes: nodes, query: query)),
          ),
        ),
      ];
    }

    final bundle = bundleAsync.value;
    final summary = summarizeRows(rows);
    // 日落提示只在行程模式有意义：取出发后的第一次日落（不是“今天”的日落）。
    final tripMode = _mode == TimeMode.trip && etas.isNotEmpty;
    final sunset = tripMode
        ? bundle?.result.points.firstOrNullValue?.nextSunsetAfter(etas.first)
        : null;
    final finishEta = tripMode ? etas.last : null;

    return [
      if (bundle != null && bundle.result.stale)
        StaleDataBanner(
          cachedAtUtc: bundle.result.cachedAtUtc ?? DateTime.now().toUtc(),
        ),
      const SizedBox(height: 8),
      _SummaryCard(summary: summary, settings: settings),
      const SizedBox(height: 8),
      if (!route.analysisPath.coversAllSegments)
        const GranularityNotice(text: S.multiSegmentNote),
      if (_reversed) const GranularityNotice(text: S.reversedNote),
      if (route.origin == RouteOrigin.planet)
        const GranularityNotice(text: S.planetElevationNote),
      if (_mode == TimeMode.trip &&
          etas.length > 1 &&
          etas.last.difference(etas.first) > const Duration(hours: 12))
        const GranularityNotice(text: S.longTripNote),
      const SizedBox(height: 8),
      _HintsCard(rows: rows, sunsetUtc: sunset, finishEta: finishEta),
      const SizedBox(height: 8),
      Text(S.weatherAlongRoute, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      if (route.totalAscentM != null) ...[
        ElevationProfile(
          distancesM: [for (final r in rows) r.node.distFromStartM],
          elevationsM: [for (final r in rows) r.node.elevationM],
          selectedIndex: _selectedNode ?? -1,
          onTapNode: (i) => _select(i, scroll: true),
        ),
      ] else
        const GranularityNotice(text: S.noElevation),
      const SizedBox(height: 4),
      for (var i = 0; i < rows.length; i++)
        _NodeTile(
          key: _tileKeys.putIfAbsent(i, GlobalKey.new),
          row: rows[i],
          index: i,
          isLast: i == rows.length - 1,
          selected: _selectedNode == i,
          settings: settings,
          // 第一次点选中（地图/剖面同步高亮），再点打开详情。
          onTap: () => _selectedNode == i
              ? _showNodeSheet(rows, settings, initialIndex: i)
              : _select(i),
          onDetail: () {
            _select(i);
            _showNodeSheet(rows, settings, initialIndex: i);
          },
        ),
      const SizedBox(height: 8),
      _TransparencyCard(provider: provider, bundle: bundle),
    ];
  }

  void _showNodeSheet(
    List<NodeWxRow> rows,
    AppSettings settings, {
    int? initialIndex,
  }) {
    if (rows.isEmpty) return;
    final idx =
        initialIndex ??
        (_selectedNode != null && _selectedNode! < rows.length
            ? _selectedNode!
            : 0);
    // 标记操作先关闭面板再弹编辑框；线路更新后节点会重新计算。
    void closeThen(Future<void> Function() action) {
      Navigator.of(context).pop();
      action();
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            NodeDetailView(
              rows: rows,
              initialIndex: idx,
              tripMode: _mode == TimeMode.trip,
              fixedUtc: _fixedUtc(),
              settings: settings,
              onIndexChanged: (i) => _select(i, scroll: true),
              onMark: (n, type) => closeThen(
                () => _addMark(
                  rows[n.index].node.pos,
                  type,
                  ele: rows[n.index].node.elevationM,
                ),
              ),
              onEditMark: (wp) => closeThen(() => _editMark(wp)),
              onRemoveMark: (wp) => closeThen(() => _removeMark(wp)),
              routeId: _base.id,
            ),
          ],
        ),
      ),
    );
  }
}

extension on List<WxPointForecast> {
  WxPointForecast? get firstOrNullValue => isEmpty ? null : first;
}

class _RouteMiniMap extends ConsumerWidget {
  const _RouteMiniMap({
    required this.route,
    required this.rows,
    required this.selectedIndex,
    required this.onTapNode,
    required this.onOpenFullscreen,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;
  final ValueChanged<int> onTapNode;
  final VoidCallback onOpenFullscreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basemap = Basemap.fromSettings(
      ref.watch(settingsProvider),
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    final fit = routeCameraFit(route, basemap);
    final photos = ref
        .watch(routePhotosProvider)
        .where((p) => p.routeId == route.id)
        .toList();
    // 小地图不响应拖动/缩放，避免与外层 ListView 滚动手势冲突；
    // 点节点标记选中节点，点空白处或全屏按钮进入可交互大图。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                FlutterMap(
                  // 反向行走时几何不变但起终点互换，key 带上方向让相机与标记重建。
                  key: ValueKey(
                    'mini-${route.id}-${basemap.signature}-${route.flatPoints.first}',
                  ),
                  options: MapOptions(
                    initialCameraFit: fit,
                    // 无几何时的兜底；有 fit 时 initialCameraFit 优先。
                    initialCenter: const LatLng(39.99, 116.17),
                    initialZoom: 12,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    onTap: (_, _) => onOpenFullscreen(),
                  ),
                  children: _routeMapLayers(
                    basemap: basemap,
                    route: route,
                    rows: rows,
                    selectedIndex: selectedIndex,
                    onTapNode: onTapNode,
                    photos: photos,
                    onTapPhoto: (p) => showRoutePhotoViewer(context, p),
                  ),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: S.routeMapFullscreen,
                      icon: const Icon(Icons.fullscreen),
                      onPressed: onOpenFullscreen,
                    ),
                  ),
                ),
                const Positioned(
                  top: 6,
                  left: 6,
                  right: 58,
                  child: TiandituErrorBanner(compact: true),
                ),
              ],
            ),
          ),
        ),
        NodeWxLegend(
          classes: [
            for (final r in rows)
              if (r.node.waypoint == null) classifyNodeWx(r.wx),
          ],
        ),
      ],
    );
  }
}

/// 线路地图图层：线路、方向箭头、节点（可点选）、航点、起终点、选中高亮。
List<Widget> _routeMapLayers({
  required Basemap basemap,
  required HikingRoute route,
  required List<NodeWxRow> rows,
  required int? selectedIndex,
  ValueChanged<int>? onTapNode,
  List<RoutePhoto> photos = const [],
  ValueChanged<RoutePhoto>? onTapPhoto,
  bool attribution = false,
}) {
  final onRoute = {
    for (final r in rows)
      if (r.node.waypoint != null) r.node.waypoint!,
  };
  final sel = selectedIndex != null && selectedIndex < rows.length
      ? selectedIndex
      : null;
  return [
    ...basemap.tileLayers(),
    PolylineLayer(
      polylines: [
        for (final seg in route.segments)
          Polyline(
            points: [
              for (final pt in Geo.simplify(seg, 15)) basemap.toDisplay(pt),
            ],
            strokeWidth: 4,
            color: const Color(0xFF1565C0),
          ),
      ],
    ),
    routeDirectionLayer(route, basemap),
    MarkerLayer(
      markers: [
        // 偏离线路、未进入时间线的航点：半透明显示，不可选。
        for (final wp in route.waypoints)
          if (!onRoute.contains(wp))
            Marker(
              point: basemap.toDisplay(wp.point),
              width: 22,
              height: 22,
              child: Tooltip(
                message: '${wp.name}（${S.offRouteWaypoint}）',
                child: Opacity(
                  opacity: 0.55,
                  child: WaypointMarker(type: wp.type, size: 14),
                ),
              ),
            ),
        for (var i = 0; i < rows.length; i++)
          Marker(
            point: basemap.toDisplay(rows[i].node.pos),
            width: 30,
            height: 30,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTapNode == null ? null : () => onTapNode(i),
              child: Center(
                child: rows[i].node.waypoint != null
                    ? WaypointMarker(
                        type: rows[i].node.waypoint!.type,
                        size: sel == i ? 22 : 16,
                      )
                    : NodeWxMarker(
                        cls: classifyNodeWx(rows[i].wx),
                        selected: sel == i,
                      ),
              ),
            ),
          ),
      ],
    ),
    routeEndpointLayer(route, basemap),
    if (photos.isNotEmpty)
      MarkerLayer(
        markers: [
          for (final p in photos)
            Marker(
              point: basemap.toDisplay(p.pos),
              width: 24,
              height: 24,
              alignment: Alignment.topRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTapPhoto == null ? null : () => onTapPhoto(p),
                child: const PhotoMapMarker(),
              ),
            ),
        ],
      ),
    if (sel != null)
      MarkerLayer(
        markers: [
          Marker(
            point: basemap.toDisplay(rows[sel].node.pos),
            width: 38,
            height: 38,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.red, width: 3),
                ),
              ),
            ),
          ),
        ],
      ),
    if (attribution) basemap.attributionWidget(),
  ];
}

/// 可拖动/缩放的线路大图；打开时自动适配整条线路范围。
/// 点节点选中并显示摘要卡；长按线路附近返回该位置用于添加标记。
class _RouteFullMapPage extends ConsumerStatefulWidget {
  const _RouteFullMapPage({
    required this.route,
    required this.rows,
    required this.selectedIndex,
    required this.onSelect,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  ConsumerState<_RouteFullMapPage> createState() => _RouteFullMapPageState();
}

class _RouteFullMapPageState extends ConsumerState<_RouteFullMapPage> {
  final MapController _controller = MapController();
  late int? _sel = widget.selectedIndex;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final basemap = Basemap.fromSettings(
      settings,
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    final fit = routeCameraFit(
      widget.route,
      basemap,
      padding: const EdgeInsets.all(40),
    );
    final sel = _sel != null && _sel! < widget.rows.length ? _sel : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.route.name)),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MapLayerButton(heroTag: 'detailLayers'),
          if (fit != null) ...[
            const SizedBox(height: 10),
            FloatingActionButton.small(
              heroTag: 'detailFit',
              tooltip: S.routeMapFitAll,
              onPressed: () => _controller.fitCamera(fit),
              child: const Icon(Icons.fit_screen),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCameraFit: fit,
              minZoom: 3,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onLongPress: (_, p) =>
                  Navigator.of(context).pop(basemap.toBusiness(p)),
            ),
            children: _routeMapLayers(
              basemap: basemap,
              route: widget.route,
              rows: widget.rows,
              selectedIndex: sel,
              onTapNode: (i) {
                setState(() => _sel = i);
                widget.onSelect(i);
              },
              photos: ref
                  .watch(routePhotosProvider)
                  .where((p) => p.routeId == widget.route.id)
                  .toList(),
              onTapPhoto: (p) => showRoutePhotoViewer(context, p),
              attribution: true,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        S.longPressToMark,
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const TiandituErrorBanner(margin: EdgeInsets.only(top: 6)),
                ],
              ),
            ),
          ),
          if (sel != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Card(
                  margin: const EdgeInsets.fromLTRB(12, 0, 64, 12),
                  child: ListTile(
                    title: Text(
                      '${widget.rows[sel].node.label ?? '节点 ${sel + 1}'} · '
                      '${(widget.rows[sel].node.distFromStartM / 1000).toStringAsFixed(1)} km',
                    ),
                    subtitle: WxBriefLine(
                      wx: widget.rows[sel].wx,
                      settings: settings,
                    ),
                    trailing: TextButton(
                      onPressed: () => Navigator.of(context).pop(sel),
                      child: const Text(S.nodeDetail2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RouteFactsCard extends ConsumerWidget {
  const _RouteFactsCard({
    required this.route,
    required this.reversed,
    required this.onToggleReverse,
  });

  final HikingRoute route;
  final bool reversed;
  final VoidCallback onToggleReverse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = const TextStyle(fontSize: 13);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${S.distanceLabel}：${(route.totalDistanceM / 1000).toStringAsFixed(1)} km',
                  style: style,
                ),
                const SizedBox(width: 16),
                Text(
                  '${S.ascentLabel}：${route.totalAscentM == null ? S.unknown : '${route.totalAscentM!.toStringAsFixed(0)} m'}',
                  style: style,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  route.isLoop ? Icons.loop : Icons.trending_flat,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    route.isLoop
                        ? '${S.loopRoute}（起终点相同，箭头为行进方向）'
                        : '${S.startPoint}（绿）→ ${S.endPoint}（红）'
                              '${reversed ? ' · 已反向' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                // 环线同样有方向（顺/逆时针到达各点的时间不同），始终可反向。
                TextButton.icon(
                  onPressed: onToggleReverse,
                  icon: const Icon(Icons.swap_horiz, size: 18),
                  label: Text(reversed ? '恢复原方向' : S.reverseRoute),
                ),
              ],
            ),
            RouteSourceLine(route: route),
          ],
        ),
      ),
    );
  }
}

class _TimeControlsCard extends StatelessWidget {
  const _TimeControlsCard({
    required this.mode,
    required this.onMode,
    required this.date,
    required this.onDate,
    required this.hour,
    this.previewHour,
    required this.onHourPreview,
    required this.onHourCommit,
    required this.startTime,
    required this.onStartTime,
    required this.pace,
    required this.onPace,
  });

  final TimeMode mode;
  final void Function(TimeMode) onMode;
  final DateTime date;
  final void Function(DateTime) onDate;
  final int hour;
  final double? previewHour;
  final void Function(double) onHourPreview;
  final void Function(int) onHourCommit;
  final TimeOfDay startTime;
  final void Function(TimeOfDay) onStartTime;
  final PaceConfig pace;
  final void Function(PaceConfig) onPace;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<TimeMode>(
              segments: [
                ButtonSegment(value: TimeMode.fixed, label: Text(S.modeFixed)),
                ButtonSegment(value: TimeMode.trip, label: Text(S.modeTrip)),
              ],
              selected: {mode},
              onSelectionChanged: (s) => onMode(s.first),
            ),
            const SizedBox(height: 4),
            Text(
              mode == TimeMode.fixed ? S.modeFixedDesc : S.modeTripDesc,
              style: const TextStyle(fontSize: 11, height: 1.4),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    '${date.year}-${_two(date.month)}-${_two(date.day)}',
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final d = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: now.subtract(const Duration(days: 1)),
                      lastDate: now.add(const Duration(days: 30)),
                    );
                    if (d != null) onDate(d);
                  },
                ),
                const SizedBox(width: 8),
                if (mode == TimeMode.trip)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.schedule, size: 16),
                    label: Text(
                      '${S.departure} ${_two(startTime.hour)}:${_two(startTime.minute)}',
                    ),
                    onPressed: () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: startTime,
                      );
                      if (t != null) onStartTime(t);
                    },
                  ),
              ],
            ),
            if (mode == TimeMode.fixed) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('时刻', style: Theme.of(context).textTheme.labelMedium),
                  Expanded(
                    child: Slider(
                      value: hour.toDouble(),
                      min: 0,
                      max: 23,
                      divisions: 23,
                      label: '${_two(hour)}:00（本地时区）',
                      onChanged: onHourPreview,
                      onChangeEnd: (v) => onHourCommit(v.round()),
                    ),
                  ),
                  Text('${_two((previewHour ?? hour.toDouble()).round())}:00'),
                ],
              ),
            ],
            if (mode == TimeMode.trip)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.directions_walk),
                title: const Text(
                  S.paceSettings,
                  style: TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  '速度 ${pace.speedKmh} km/h · 上升 ${pace.ascentMinPer100m} min/100m · 休息 ${pace.restMinutesTotal} min',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: const Icon(Icons.tune, size: 18),
                onTap: () => _showPaceSheet(context),
              ),
            if (mode == TimeMode.trip)
              Text(
                S.etaIsEstimate,
                style: TextStyle(
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showPaceSheet(BuildContext context) {
    var speed = pace.speedKmh;
    var ascent = pace.ascentMinPer100m;
    var rest = pace.restMinutesTotal;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.paceSettings, style: Theme.of(ctx).textTheme.titleMedium),
              ...pace.assumptionNotes().map(
                (n) => Text('· $n', style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 8),
              Text('平地速度：${speed.toStringAsFixed(1)} km/h'),
              Slider(
                value: speed,
                min: 1.5,
                max: 6,
                divisions: 18,
                label: speed.toStringAsFixed(1),
                onChanged: (v) => setSheet(() => speed = v),
              ),
              Text('每上升 100 m 加时：${ascent.toStringAsFixed(0)} 分钟'),
              Slider(
                value: ascent,
                min: 4,
                max: 40,
                divisions: 36,
                label: ascent.toStringAsFixed(0),
                onChanged: (v) => setSheet(() => ascent = v),
              ),
              Text('全程休息：$rest 分钟'),
              Slider(
                value: rest.toDouble(),
                min: 0,
                max: 180,
                divisions: 18,
                label: '$rest',
                onChanged: (v) => setSheet(() => rest = v.round()),
              ),
              FilledButton(
                onPressed: () {
                  onPace(
                    PaceConfig(
                      speedKmh: speed,
                      ascentMinPer100m: ascent,
                      descentMinPer100m: (ascent / 2).roundToDouble(),
                      restMinutesTotal: rest,
                    ),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text(S.ok),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}

class _SourceChips extends ConsumerWidget {
  const _SourceChips({
    required this.selected,
    required this.onSelect,
    required this.onCompare,
  });

  final String selected;
  final void Function(String) onSelect;
  final VoidCallback onCompare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providers = ref.watch(weatherProvidersProvider);
    final enabled = ref.watch(settingsProvider).enabledProviderIds;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final p in providers)
                  if (enabled.contains(p.caps.providerId) &&
                      !p.caps.onDemandOnly)
                    ChoiceChip(
                      label: Text(
                        p.caps.displayName,
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: selected == p.caps.providerId,
                      onSelected: (_) => onSelect(p.caps.providerId),
                    ),
              ],
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.compare_arrows, size: 16),
                label: Text(
                  S.compareSources,
                  style: const TextStyle(fontSize: 13),
                ),
                onPressed: onCompare,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.settings});

  final RouteWxSummary summary;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    if (!summary.hasAnyData) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            '当前选定时间与来源没有可用数据（${summary.nodesWithData}/${summary.totalNodes} 节点有数据）。信息不足时无法给出摘要。',
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.routeSummary, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _kv(
                  '最低/最高温',
                  '${Units.temp(summary.minTempC ?? 0, imperial: settings.imperial, digits: 0)} / ${Units.temp(summary.maxTempC ?? 0, imperial: settings.imperial)}',
                ),
                _kv(
                  '沿途降水（估算）',
                  summary.totalPrecipMm == null
                      ? S.notProvided
                      : Units.precipMm(
                          summary.totalPrecipMm!,
                          imperial: settings.imperial,
                        ),
                ),
                _kv(
                  '最大阵风',
                  summary.maxGustMs == null
                      ? S.notProvided
                      : Units.windMs(
                          summary.maxGustMs!,
                          unit: settings.windUnit,
                        ),
                ),
                _kv(
                  '有降水节点',
                  '${summary.precipNodeCount}/${summary.totalNodes}',
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '按当前选定来源汇总，不与其他来源拼接。',
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      Text(
        v,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _HintsCard extends StatelessWidget {
  const _HintsCard({
    required this.rows,
    required this.sunsetUtc,
    required this.finishEta,
  });

  final List<NodeWxRow> rows;
  final DateTime? sunsetUtc;
  final DateTime? finishEta;

  @override
  Widget build(BuildContext context) {
    final hints = computeHints(entries: rowsToEntries(rows));
    final sunset = (sunsetUtc != null && finishEta != null)
        ? sunsetHint(sunsetUtc: sunsetUtc!, finishEtaUtc: finishEta!)
        : null;
    final all = [...hints, ?sunset];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.riskHints, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            if (all.isEmpty)
              const Text(
                '当前数据未触发任何阈值提示（这不代表安全）。',
                style: TextStyle(fontSize: 12),
              ),
            for (final h in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      h.level == HintLevel.warning
                          ? Icons.warning_amber_rounded
                          : h.level == HintLevel.caution
                          ? Icons.info
                          : Icons.info_outline,
                      size: 16,
                      color: h.level == HintLevel.warning
                          ? Colors.red
                          : h.level == HintLevel.caution
                          ? Colors.orange
                          : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${h.title}：${h.detail}',
                            style: const TextStyle(fontSize: 12, height: 1.4),
                          ),
                          Text(
                            '依据：${h.basis}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            Text(
              S.officialAlerts,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            const Text(
              officialAlertsNotAvailable,
              style: TextStyle(fontSize: 11, height: 1.4, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.row,
    required this.index,
    required this.isLast,
    required this.selected,
    required this.settings,
    required this.onTap,
    required this.onDetail,
  });

  final NodeWxRow row;
  final int index;
  final bool isLast;
  final bool selected;
  final AppSettings settings;
  final VoidCallback onTap;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final local = row.validUtc.toLocal();
    final wp = row.node.waypoint;
    final Widget leading;
    if (wp != null) {
      leading = WaypointMarker(type: wp.type, size: 16);
    } else if (index == 0) {
      leading = const Icon(Icons.flag, size: 18, color: Color(0xFF2E7D32));
    } else if (isLast) {
      leading = const Icon(
        Icons.sports_score,
        size: 18,
        color: Color(0xFFC62828),
      );
    } else if (row.node.label == '高点') {
      leading = const Icon(Icons.terrain_outlined, size: 18);
    } else {
      leading = const Icon(Icons.circle, size: 10);
    }
    return ListTile(
      dense: true,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer
          .withValues(alpha: 0.3),
      leading: SizedBox(width: 24, child: Center(child: leading)),
      title: Text(
        '${row.node.label ?? '节点 ${index + 1}'} · ${(row.node.distFromStartM / 1000).toStringAsFixed(1)} km'
        '${row.node.elevationM == null ? '' : ' · ${row.node.elevationM!.toStringAsFixed(0)} m'}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_fmt(local)}（UTC ${_fmtUtc(row.validUtc)}）'
            '${wp?.stopMinutes == null ? '' : ' · 停留 ${wp!.stopMinutes} 分钟'}'
            '${row.sharedWithPrev ? ' · 与上一节点共享同一查询点' : ''}',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          WxBriefLine(wx: row.wx, settings: settings),
          if (selected)
            const Text(
              S.tapAgainForDetail,
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
      trailing: IconButton(
        tooltip: S.nodeDetail2,
        icon: const Icon(Icons.info_outline, size: 20),
        onPressed: onDetail,
      ),
      onTap: onTap,
    );
  }

  String _fmt(DateTime t) =>
      '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  String _fmtUtc(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _TransparencyCard extends StatelessWidget {
  const _TransparencyCard({required this.provider, required this.bundle});

  final WeatherProvider provider;
  final RouteWeatherBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final caps = provider.caps;
    final prov = bundle?.result.points.isEmpty == false
        ? bundle!.result.points.first.provenance
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.sourceTransparency,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                SourceBadge(caps: caps),
                DataKindChip(kind: caps.dataKind),
              ],
            ),
            const SizedBox(height: 8),
            GranularityNotice(
              text:
                  prov?.granularityStatement() ??
                  caps.spatialResolutionNote ??
                  '来源未提供空间分辨率，位置颗粒度未确认',
            ),
            if (bundle?.sharedGridNote != null) ...[
              const SizedBox(height: 6),
              GranularityNotice(
                text: '${S.sharedGridNotePrefix}：${bundle!.sharedGridNote}',
              ),
            ],
            if (caps.modelOverlapNote != null) ...[
              const SizedBox(height: 6),
              GranularityNotice(
                text: caps.modelOverlapNote!,
                icon: Icons.hub_outlined,
              ),
            ],
            const SizedBox(height: 8),
            if (prov != null)
              Text(
                '${S.fetchedAt}：${prov.fetchedAtUtc.toIso8601String().substring(0, 16)} UTC'
                '${prov.modelRunUtc == null ? '' : '\n起报/发布：${prov.modelRunUtc!.toIso8601String().substring(0, 16)} UTC'}'
                '${prov.elevationUsedM == null ? '' : '\n来源使用海拔（模型地形）：${prov.elevationUsedM!.toStringAsFixed(0)} m；轨迹海拔见各节点（两者是不同数据）'}',
                style: const TextStyle(fontSize: 11, height: 1.5),
              ),
            TextButton.icon(
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text('查看完整溯源信息', style: TextStyle(fontSize: 12)),
              onPressed: prov == null
                  ? null
                  : () {
                      final map = prov.toDisplayMap();
                      showDialog<void>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          title: const Text(S.sourceTransparency),
                          content: SizedBox(
                            width: 380,
                            child: ListView(
                              shrinkWrap: true,
                              children: [
                                for (final e in map.entries)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      '${e.key}：${e.value}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dCtx),
                              child: const Text(S.close),
                            ),
                          ],
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}
