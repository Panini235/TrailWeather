import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../core/geo.dart';
import '../../data/app_providers.dart';
import '../../data/location/location_service.dart';
import '../../data/map/tianditu.dart';
import '../../data/routes/route_exporter.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/terrain/dem.dart';
import '../../data/terrain/terrain_compute.dart';
import '../../data/weather/eta.dart';
import '../detail/route_detail_screen.dart';
import '../map/basemap.dart';
import '../map/map_layers_ui.dart';
import '../map/terrain_layer.dart';
import '../strings.dart';
import '../tokens.dart';
import '../widgets/common.dart';

enum PlannerMode { draw, waypoint }

/// 海拔剖面：沿线约每 25 m 一个样点（公开高程数据估算，D-039）。
class PlannerProfile {
  const PlannerProfile(this.points, this.distM, this.elevM);

  final List<LatLng> points;
  final List<double> distM;

  /// 缺失为 NaN（瓦片还没下载或下载失败）。
  final List<double> elevM;

  bool get complete => elevM.isNotEmpty && !elevM.any((e) => e.isNaN);
  ElevationStats? get stats => complete ? elevationStats(elevM) : null;
}

/// 徒步路线手绘规划工具（Trail Studio，参考两步路与奥维地图）。
///
/// 编辑：轻触地图在末尾加点；拖动圆点调整；拖线段中间的小点插入新点；点选圆点后可删除。
/// 底部实时给出距离、累计爬升 / 下降与估算用时，以及海拔剖面。等高线与地形阴影默认打开。
/// 动效克制：点、线、数字都随手指即时更新，不做过渡动画。
class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  ConsumerState<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final MapController _mapController = MapController();
  final List<LatLng> _points = [];

  /// 撤销快照：轨迹点与航点一起存（“清空”也能撤销）。
  final List<(List<LatLng>, List<RouteWaypoint>)> _undoStack = [];
  final List<RouteWaypoint> _waypoints = [];
  PlannerMode _mode = PlannerMode.draw;

  /// 选中的轨迹点（可删除）。
  int? _selected;

  /// 拖动中的点与起点（显示坐标、屏幕像素累计位移）。
  int? _dragIndex;
  Offset _dragStartWorld = Offset.zero;
  Offset _dragDelta = Offset.zero;

  bool _terrainOn = true;
  LocationFix? _myFix;
  bool _locating = false;

  PlannerProfile _profile = const PlannerProfile([], [], []);
  late final DemService _dem = ref.read(demServiceProvider);

  @override
  void initState() {
    super.initState();
    _dem.addListener(_onDemTile);
  }

  @override
  void dispose() {
    _dem.removeListener(_onDemTile);
    super.dispose();
  }

  Basemap get _basemap => Basemap.fromSettings(ref.read(settingsProvider));

  double get _totalDistM =>
      _points.length < 2 ? 0.0 : Geo.cumulativeDistancesM(_points).last;

  /// 估算用时（分钟）：与详情页行程模式同一配速；有海拔时计入爬升 / 下降。
  int get _estimatedDurationMin {
    const pace = PaceConfig.defaults;
    var min = _totalDistM / 1000.0 / pace.speedKmh * 60;
    final st = _profile.stats;
    if (st != null) {
      min += st.ascentM / 100 * pace.ascentMinPer100m;
      min += st.descentM / 100 * pace.descentMinPer100m;
    }
    return min.round();
  }

  // ---------------------------------------------------------------- 海拔剖面

  void _onDemTile() {
    if (!mounted || _profile.complete || _points.length < 2) return;
    _refreshProfile();
  }

  /// 重算剖面：缺的高程瓦片去下载，到了以后由 [_onDemTile] 再算一次。
  void _refreshProfile() {
    if (_points.length < 2) {
      setState(() => _profile = const PlannerProfile([], [], []));
      return;
    }
    final (pts, dist) = densify(_points, 25);
    final elev = [for (final p in pts) _dem.elevationAt(p) ?? double.nan];
    setState(() => _profile = PlannerProfile(pts, dist, elev));
    if (elev.any((e) => e.isNaN)) {
      for (final k in DemService.tilesForPoints(pts, DemService.maxZoom)) {
        if (_dem.cached(k) == null) unawaited(_dem.load(k));
      }
    }
  }

  // ---------------------------------------------------------------- 编辑

  void _pushUndo() {
    _undoStack.add((List.of(_points), List.of(_waypoints)));
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _edited() {
    _selected = _selected != null && _selected! < _points.length
        ? _selected
        : null;
    _refreshProfile();
  }

  void _onTapMap(TapPosition _, LatLng latLng) {
    final wgsPoint = _basemap.toBusiness(latLng);
    if (_mode == PlannerMode.draw) {
      if (_selected != null) {
        // 有选中点时，轻触地图只取消选中，避免误加点。
        setState(() => _selected = null);
        return;
      }
      _pushUndo();
      _points.add(wgsPoint);
      _edited();
    } else {
      _showAddWaypointDialog(wgsPoint);
    }
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      final (points, waypoints) = _undoStack.removeLast();
      _points
        ..clear()
        ..addAll(points);
      _waypoints
        ..clear()
        ..addAll(waypoints);
    } else if (_points.isNotEmpty) {
      _points.removeLast();
    }
    _edited();
  }

  void _reverse() {
    if (_points.length < 2) return;
    _pushUndo();
    final reversed = _points.reversed.toList();
    _points
      ..clear()
      ..addAll(reversed);
    _selected = _selected == null ? null : _points.length - 1 - _selected!;
    _edited();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(S.plannerReversed),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null || i >= _points.length) return;
    _pushUndo();
    _points.removeAt(i);
    _selected = null;
    _edited();
  }

  void _dragStart(int index) {
    _pushUndo();
    final cam = _mapController.camera;
    _dragIndex = index;
    _dragStartWorld = cam.projectAtZoom(_basemap.toDisplay(_points[index]));
    _dragDelta = Offset.zero;
    setState(() => _selected = index);
  }

  void _dragUpdate(Offset delta) {
    final i = _dragIndex;
    if (i == null) return;
    _dragDelta += delta;
    final cam = _mapController.camera;
    final display = cam.unprojectAtZoom(_dragStartWorld + _dragDelta);
    // 拖动中只更新几何和距离；海拔松手后再算（不在每帧取样）。
    setState(() => _points[i] = _basemap.toBusiness(display));
  }

  void _dragEnd() {
    _dragIndex = null;
    _edited();
  }

  /// 从第 [segment] 段的中点插入新点并开始拖动它。
  void _insertAt(int segment) {
    final a = _points[segment], b = _points[segment + 1];
    _pushUndo();
    _points.insert(
      segment + 1,
      LatLng((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2),
    );
    // 插入本身已入撤销栈，拖动开始时不再重复入栈。
    final cam = _mapController.camera;
    _dragIndex = segment + 1;
    _dragStartWorld = cam.projectAtZoom(
      _basemap.toDisplay(_points[segment + 1]),
    );
    _dragDelta = Offset.zero;
    setState(() => _selected = segment + 1);
  }

  void _clear() {
    if (_points.isEmpty && _waypoints.isEmpty) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.plannerClearTitle),
        content: const Text(S.plannerClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.plannerClear),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        _pushUndo();
        _points.clear();
        _waypoints.clear();
        _selected = null;
        _edited();
      }
    });
  }

  // ---------------------------------------------------------------- 定位

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final fix = await ref
          .read(locationServiceProvider)
          .currentPosition(
            onLastKnown: (p) {
              if (mounted) _moveTo(p);
            },
          );
      if (!mounted) return;
      setState(() => _myFix = fix);
      _moveTo(fix.point);
      if (fix.isLastKnown) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(S.lastKnownFallback)));
      }
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      final canOpen =
          failure.kind == LocationFailureKind.serviceDisabled ||
          failure.kind == LocationFailureKind.deniedForever;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failure.message),
          action: canOpen
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
            .showSnackBar(const SnackBar(content: Text(S.plannerLocateFailed)));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _moveTo(LatLng wgs) {
    final cam = _mapController.camera;
    _mapController.move(_basemap.toDisplay(wgs), math.max(cam.zoom, 14));
  }

  // ---------------------------------------------------------------- 航点、保存、导出

  Future<void> _showAddWaypointDialog(LatLng pt) async {
    final nameCtrl = TextEditingController(
      text: S.plannerWaypointDefaultName(_waypoints.length + 1),
    );
    final descCtrl = TextEditingController();
    var selectedType = WaypointType.poi;

    final created = await showDialog<RouteWaypoint>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text(S.plannerAddWaypointTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: S.plannerWaypointNameLabel,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WaypointType>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: S.plannerWaypointTypeLabel,
                  ),
                  items: WaypointType.values.map((t) {
                    return DropdownMenuItem(
                      value: t,
                      child: Text(waypointTypeLabel(t)),
                    );
                  }).toList(),
                  onChanged: (v) {
                    if (v != null) setDlgState(() => selectedType = v);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: S.plannerWaypointDescLabel,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(S.cancel),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(
                  ctx,
                  RouteWaypoint(
                    name: name,
                    point: pt,
                    type: selectedType,
                    desc: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                  ),
                );
              },
              child: const Text(S.plannerAdd),
            ),
          ],
        ),
      ),
    );

    if (created != null) {
      _pushUndo();
      setState(() {
        _waypoints.add(created);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              S.plannerWaypointAdded(
                created.name,
                waypointTypeLabel(created.type),
              ),
            ),
          ),
        );
      }
    }
  }

  String _durationText() {
    final m = _estimatedDurationMin;
    if (m < 60) return '${S.plannerAbout} $m ${S.plannerMinutesOnly}';
    return '${S.plannerAbout} ${m ~/ 60} ${S.plannerHours} ${m % 60} ${S.plannerMinutes}';
  }

  Future<void> _saveRoute() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text(S.plannerNeedTwoPoints)));
      return;
    }

    final nameCtrl = TextEditingController(
      text: S.plannerDefaultRouteName(DateTime.now().month, DateTime.now().day),
    );
    final descCtrl = TextEditingController();
    final stats = _profile.stats;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(S.plannerSaveTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: S.plannerRouteNameLabel,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: S.plannerDescLabel),
            ),
            const SizedBox(height: 12),
            Text(
              S.plannerSaveSummary(
                distKm: (_totalDistM / 1000.0).toStringAsFixed(2),
                ascentM: stats == null ? null : displayElevation(stats.ascentM),
                waypoints: _waypoints.length,
                duration: _durationText(),
              ),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(S.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(S.plannerSaveAndForecast),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final name = nameCtrl.text.trim().isEmpty
          ? S.plannerUntitledRoute
          : nameCtrl.text.trim();
      // 海拔齐全时按剖面样点保存，详情页的海拔剖面、爬升与配速都能用上；
      // 来源名注明海拔是公开高程数据估算。不齐时只存手绘点、海拔留空，不编造。
      final withElev = _profile.complete;
      final route = HikingRoute(
        id: 'planned-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        origin: RouteOrigin.planned,
        segments: [withElev ? List.of(_profile.points) : List.of(_points)],
        elevationsM: withElev
            ? [for (final e in _profile.elevM) e]
            : List.filled(_points.length, null),
        sourceName: withElev
            ? S.plannerSourceNameWithElev
            : S.plannerSourceName,
        importedAtUtc: DateTime.now().toUtc(),
        description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        waypoints: List.of(_waypoints),
      );

      await ref.read(favoritesProvider.notifier).add(route);
      if (mounted) {
        unawaited(
          context.push(
            '/route/${route.id}',
            extra: RouteDetailArgs(route: route),
          ),
        );
      }
    }
  }

  void _showExportModal() {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(S.plannerNeedTwoPointsExport)),
      );
      return;
    }

    final tempRoute = HikingRoute(
      id: 'export-temp',
      name: S.plannerUntitledRoute,
      origin: RouteOrigin.planned,
      segments: [List.of(_points)],
      elevationsM: List.filled(_points.length, null),
      sourceName: S.plannerExportSourceName,
      waypoints: List.of(_waypoints),
    );

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              S.plannerExportTitle,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const HelpText(S.plannerExportNote, size: 12),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text(S.plannerCopyGpx),
              onPressed: () {
                final gpxStr = RouteExporter.toGpx(tempRoute);
                Clipboard.setData(ClipboardData(text: gpxStr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(S.plannerGpxCopied)),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text(S.plannerCopyKml),
              onPressed: () {
                final kmlStr = RouteExporter.toKml(tempRoute);
                Clipboard.setData(ClipboardData(text: kmlStr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(S.plannerKmlCopied)),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final basemap = Basemap.fromSettings(
      settings,
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    final displayPoints = [for (final p in _points) basemap.toDisplay(p)];
    final terrain = _terrainOn
        ? terrainLayerFor(ref, basemap, contours: true, hillshade: true)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text(S.plannerTitle),
        actions: [
          IconButton(
            tooltip: S.plannerUndo,
            icon: const Icon(Icons.undo),
            onPressed: _points.isEmpty && _undoStack.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: S.plannerReverse,
            icon: const Icon(Icons.swap_calls),
            onPressed: _points.length < 2 ? null : _reverse,
          ),
          // 导出与清空收进菜单：标题在大字号下也能完整显示。
          PopupMenuButton<VoidCallback>(
            tooltip: S.plannerMore,
            onSelected: (action) => action(),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: _showExportModal,
                enabled: _points.length >= 2,
                child: const ListTile(
                  leading: Icon(Icons.file_upload_outlined),
                  title: Text(S.plannerExportMenu),
                ),
              ),
              PopupMenuItem(
                value: _clear,
                enabled: _points.isNotEmpty || _waypoints.isNotEmpty,
                child: const ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text(S.plannerClearMenu),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(39.99, 116.19),
              initialZoom: 13,
              maxZoom: 18,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onTap: _onTapMap,
            ),
            children: [
              ...basemap.tileLayers(),
              ?terrain,
              if (displayPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: displayPoints,
                      strokeWidth: 4,
                      color: Semantic.route,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              if (_mode == PlannerMode.draw)
                _MidHandles(
                  points: displayPoints,
                  onStart: _insertAt,
                  onUpdate: _dragUpdate,
                  onEnd: _dragEnd,
                ),
              MarkerLayer(
                markers: [
                  for (final wp in _waypoints)
                    Marker(
                      point: basemap.toDisplay(wp.point),
                      width: 36,
                      height: 36,
                      child: Tooltip(
                        message: '${wp.name} (${waypointTypeLabel(wp.type)})',
                        child: WaypointMarker(type: wp.type),
                      ),
                    ),
                  for (var i = 0; i < displayPoints.length; i++)
                    Marker(
                      point: displayPoints[i],
                      width: 36,
                      height: 36,
                      child: _VertexHandle(
                        key: ValueKey('vertex-$i'),
                        selected: _selected == i,
                        color: i == 0
                            ? Semantic.go
                            : (i == displayPoints.length - 1
                                  ? Semantic.danger
                                  : Colors.white),
                        enabled: _mode == PlannerMode.draw,
                        onTap: () => setState(
                          () => _selected = _selected == i ? null : i,
                        ),
                        onDragStart: () => _dragStart(i),
                        onDragUpdate: _dragUpdate,
                        onDragEnd: _dragEnd,
                      ),
                    ),
                  if (_myFix != null)
                    Marker(
                      point: basemap.toDisplay(_myFix!.point),
                      width: 20,
                      height: 20,
                      child: _MyLocationDot(stale: _myFix!.isLastKnown),
                    ),
                ],
              ),
              if (terrain != null)
                const ContourIntervalBadge(
                  alignment: Alignment.topLeft,
                  padding: EdgeInsets.fromLTRB(14, 78, 0, 0),
                ),
              basemap.attributionWidget(
                extra: terrain == null
                    ? const []
                    : const [S.terrainAttribution],
              ),
            ],
          ),

          Positioned(
            top: 84,
            right: 12,
            child: Column(
              children: [
                const MapLayerButton(heroTag: 'plannerLayers'),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'plannerTerrain',
                  tooltip: S.plannerTerrain,
                  backgroundColor: _terrainOn
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  onPressed: () => setState(() => _terrainOn = !_terrainOn),
                  child: Icon(
                    _terrainOn ? Icons.terrain : Icons.terrain_outlined,
                  ),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'plannerLocate',
                  tooltip: S.locateMe,
                  onPressed: _locating ? null : _locate,
                  child: const Icon(Icons.my_location),
                ),
              ],
            ),
          ),
          const Positioned(
            top: 84,
            left: 12,
            right: 64,
            child: TiandituErrorBanner(),
          ),

          // 顶部浮动模式切换卡片
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SegmentedButton<PlannerMode>(
                  segments: const [
                    ButtonSegment(
                      value: PlannerMode.draw,
                      icon: Icon(Icons.edit_road),
                      label: Text(S.plannerModeDraw),
                    ),
                    ButtonSegment(
                      value: PlannerMode.waypoint,
                      icon: Icon(Icons.add_location_alt),
                      label: Text(S.plannerModeWaypoint),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _mode = set.first;
                      _selected = null;
                    });
                  },
                ),
              ),
            ),
          ),

          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: _PlannerHud(
              distM: _totalDistM,
              pointCount: _points.length,
              waypointCount: _waypoints.length,
              profile: _profile,
              durationText: _points.length < 2 ? null : _durationText(),
              selected: _selected,
              selectedDistM: _selectedDistM(),
              onDelete: _deleteSelected,
              onSave: _points.length < 2 ? null : _saveRoute,
            ),
          ),
        ],
      ),
    );
  }

  /// 选中点在剖面上的位置（距起点米数）。
  double? _selectedDistM() {
    final i = _selected;
    if (i == null || i >= _points.length) return null;
    return i == 0 ? 0 : Geo.cumulativeDistancesM(_points)[i];
  }
}

/// 轨迹点：轻触选中，按住拖动。可点区域 36 px，画出来的圆点 12 px（选中 18 px）。
class _VertexHandle extends StatelessWidget {
  const _VertexHandle({
    super.key,
    required this.selected,
    required this.color,
    required this.enabled,
    required this.onTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final bool selected;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 18.0 : 12.0;
    final dot = Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black87,
            width: selected ? 3 : 2,
          ),
        ),
      ),
    );
    if (!enabled) return IgnorePointer(child: dot);
    return _HandleGesture(
      onTap: onTap,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      child: dot,
    );
  }
}

/// 地图上可拖的小圆点。地图的拖动识别器用系统触摸阈值（真机约 8 px）就接管手势，
/// 这里把阈值设成 2 px，保证先于地图接管；6 px 以内松手仍算轻触（选中）。
class _HandleGesture extends StatelessWidget {
  const _HandleGesture({
    super.key,
    required this.child,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    this.onTap,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;

  static const _settings = DeviceGestureSettings(touchSlop: 2);

  @override
  Widget build(BuildContext context) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      if (onTap != null)
        TapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
              TapGestureRecognizer.new,
              (r) => r.onTap = onTap,
            ),
      ImmediateMultiDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<
            ImmediateMultiDragGestureRecognizer
          >(ImmediateMultiDragGestureRecognizer.new, (r) {
            r
              ..gestureSettings = _settings
              ..onStart = (_) => _HandleDrag(this);
          }),
    },
    child: child,
  );
}

class _HandleDrag implements Drag {
  _HandleDrag(this.h);

  final _HandleGesture h;
  Offset _pending = Offset.zero;
  bool _dragging = false;

  @override
  void update(DragUpdateDetails d) {
    if (_dragging) {
      h.onDragUpdate(d.delta);
      return;
    }
    _pending += d.delta;
    if (_pending.distance < 6) return;
    _dragging = true;
    h.onDragStart();
    h.onDragUpdate(_pending);
  }

  @override
  void end(DragEndDetails d) {
    // 拖动识别器 2 px 就接管了，轻触识别器随之出局：没真正拖起来就当作轻触。
    if (_dragging) {
      h.onDragEnd();
    } else {
      h.onTap?.call();
    }
  }

  @override
  void cancel() {
    if (_dragging) h.onDragEnd();
  }
}

/// 线段中间的小点：拖动它插入新点。线段在屏幕上太短时不显示，免得挤在一起。
class _MidHandles extends StatelessWidget {
  const _MidHandles({
    required this.points,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final List<LatLng> points;
  final ValueChanged<int> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2 || points.length > 400) {
      return const SizedBox.shrink();
    }
    final camera = MapCamera.of(context);
    final markers = <Marker>[];
    for (var i = 0; i < points.length - 1; i++) {
      final a = camera.projectAtZoom(points[i]);
      final b = camera.projectAtZoom(points[i + 1]);
      if ((a - b).distance < 56) continue;
      markers.add(
        Marker(
          point: camera.unprojectAtZoom((a + b) / 2),
          width: 28,
          height: 28,
          // 按下开始拖时插入新点，之后的位移交给同一个拖动流程。
          child: _HandleGesture(
            key: ValueKey('mid-$i'),
            onDragStart: () => onStart(i),
            onDragUpdate: onUpdate,
            onDragEnd: onEnd,
            child: Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: Semantic.route, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return MarkerLayer(markers: markers);
  }
}

class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot({required this.stale});

  final bool stale;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: stale ? Semantic.unknown : const Color(0xFF2F7BEA),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 3),
      boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
    ),
  );
}

/// 底部状态：距离、爬升 / 下降、估算用时，海拔剖面，选中点操作，完成按钮。
class _PlannerHud extends StatelessWidget {
  const _PlannerHud({
    required this.distM,
    required this.pointCount,
    required this.waypointCount,
    required this.profile,
    required this.durationText,
    required this.selected,
    required this.selectedDistM,
    required this.onDelete,
    required this.onSave,
  });

  final double distM;
  final int pointCount;
  final int waypointCount;
  final PlannerProfile profile;
  final String? durationText;
  final int? selected;
  final double? selectedDistM;
  final VoidCallback onDelete;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(
      fontSize: 12,
      color: theme.colorScheme.onSurfaceVariant,
    );
    const tabular = [FontFeature.tabularFigures()];
    final stats = profile.stats;
    final hasLine = pointCount >= 2;
    final elevText = !hasLine
        ? null
        : stats != null
        ? '↑ ${S.plannerAbout} ${displayElevation(stats.ascentM)} m  '
              '↓ ${S.plannerAbout} ${displayElevation(stats.descentM)} m'
        : profile.elevM.isEmpty
        ? null
        : S.plannerElevLoading;
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '${(distM / 1000.0).toStringAsFixed(2)} km',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFeatures: tabular,
                  ),
                ),
                const SizedBox(width: 10),
                if (elevText != null)
                  Flexible(
                    child: Text(
                      elevText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFeatures: tabular,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              !hasLine
                  ? (pointCount == 0 ? S.plannerHintEmpty : S.plannerHintEdit)
                  : '$durationText${stats == null ? ' · ${S.plannerNoClimb}' : ''}${S.plannerCounts(pointCount, waypointCount)}',
              style: muted,
            ),
            if (hasLine && profile.elevM.isNotEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 56,
                child: _ProfileStrip(
                  profile: profile,
                  markerDistM: selectedDistM,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (selected != null)
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    label: Text(
                      '${S.plannerDeletePoint}（${S.plannerPoint} ${selected! + 1} ${S.plannerPointSuffix}）',
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text(S.plannerFinish),
                  onPressed: onSave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 海拔剖面小图：面积图 + 最低 / 最高（取整到 10 m，标“约”），选中点画一条竖线。
class _ProfileStrip extends StatelessWidget {
  const _ProfileStrip({required this.profile, required this.markerDistM});

  final PlannerProfile profile;
  final double? markerDistM;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: S.plannerElevNote,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: CustomPaint(
        size: Size.infinite,
        painter: _ProfilePainter(
          profile: profile,
          markerDistM: markerDistM,
          line: Semantic.route,
          fill: Semantic.route.withValues(alpha: 0.14),
          text: scheme.onSurfaceVariant,
          missing: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.profile,
    required this.markerDistM,
    required this.line,
    required this.fill,
    required this.text,
    required this.missing,
  });

  final PlannerProfile profile;
  final double? markerDistM;
  final Color line, fill, text, missing;

  @override
  void paint(Canvas canvas, Size size) {
    final d = profile.distM, e = profile.elevM;
    if (d.length < 2) return;
    final total = d.last <= 0 ? 1.0 : d.last;
    final known = [
      for (final v in e)
        if (!v.isNaN) v,
    ];
    if (known.isEmpty) {
      // 海拔还没到：画一条虚的基线占位，不画假的起伏。
      final p = Paint()
        ..color = missing
        ..strokeWidth = 1;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, size.height - 1),
          Offset(math.min(x + 4, size.width), size.height - 1),
          p,
        );
      }
      return;
    }
    var lo = known.reduce(math.min), hi = known.reduce(math.max);
    if (hi - lo < 20) {
      final mid = (hi + lo) / 2;
      lo = mid - 10;
      hi = mid + 10;
    }
    const top = 12.0;
    final h = size.height - top;
    double xOf(double dist) => dist / total * size.width;
    double yOf(double v) => top + (1 - (v - lo) / (hi - lo)) * h;

    final path = Path();
    final area = Path();
    var open = false;
    double? lastX;
    for (var i = 0; i < d.length; i++) {
      final v = e[i];
      final x = xOf(d[i]);
      if (v.isNaN) {
        if (open) {
          area
            ..lineTo(lastX!, size.height)
            ..close();
        }
        open = false;
        continue;
      }
      final y = yOf(v);
      if (!open) {
        path.moveTo(x, y);
        area
          ..moveTo(x, size.height)
          ..lineTo(x, y);
        open = true;
      } else {
        path.lineTo(x, y);
        area.lineTo(x, y);
      }
      lastX = x;
    }
    if (open) {
      area
        ..lineTo(lastX!, size.height)
        ..close();
    }
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );

    final m = markerDistM;
    if (m != null) {
      final x = xOf(m).clamp(0.0, size.width);
      canvas.drawLine(
        Offset(x, top - 2),
        Offset(x, size.height),
        Paint()
          ..color = line
          ..strokeWidth = 1.2,
      );
    }

    final style = TextStyle(fontSize: 10, color: text);
    void label(String s, Offset at) {
      TextPainter(
          text: TextSpan(text: s, style: style),
          textDirection: TextDirection.ltr,
        )
        ..layout()
        ..paint(canvas, at);
    }

    // 只标范围，不把“最高 / 最低”摆在两端，免得被看成起点、终点的海拔。
    final maxV = known.reduce(math.max), minV = known.reduce(math.min);
    label(
      '${S.plannerElevRange} ${S.plannerAbout} '
      '${displayElevation(minV)}–${displayElevation(maxV)} m',
      const Offset(0, -2),
    );
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter old) =>
      !identical(old.profile, profile) ||
      old.markerDistM != markerDistM ||
      old.line != line ||
      old.text != text;
}
