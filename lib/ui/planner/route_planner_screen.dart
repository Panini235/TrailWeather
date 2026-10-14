import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/routes/route_exporter.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/favorites_repository.dart';
import '../../data/settings/settings_repository.dart';
import '../detail/route_detail_screen.dart';
import '../map/basemap.dart';

enum PlannerMode { draw, waypoint }

/// 徒步路线手绘规划工具（Trail Studio，参考两步路与奥维地图）。
class RoutePlannerScreen extends ConsumerStatefulWidget {
  const RoutePlannerScreen({super.key});

  @override
  ConsumerState<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends ConsumerState<RoutePlannerScreen> {
  final MapController _mapController = MapController();
  final List<LatLng> _points = [];
  final List<List<LatLng>> _undoStack = [];
  final List<RouteWaypoint> _waypoints = [];
  PlannerMode _mode = PlannerMode.draw;

  double get _totalDistM =>
      _points.length < 2 ? 0.0 : Geo.cumulativeDistancesM(_points).last;

  /// 基于常规户外徒步平均速度（平地约 4.2 km/h）估算徒步耗时（分钟）
  int get _estimatedDurationMin {
    final km = _totalDistM / 1000.0;
    return (km / 4.2 * 60).round();
  }

  void _pushUndo() {
    _undoStack.add(List.of(_points));
    if (_undoStack.length > 30) {
      _undoStack.removeAt(0);
    }
  }

  void _onTapMap(TapPosition _, LatLng latLng) {
    final settings = ref.read(settingsProvider);
    final basemap = Basemap(settings.basemap);
    final wgsPoint = basemap.toBusiness(latLng);

    if (_mode == PlannerMode.draw) {
      _pushUndo();
      setState(() {
        _points.add(wgsPoint);
      });
    } else {
      _showAddWaypointDialog(wgsPoint);
    }
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      setState(() {
        _points
          ..clear()
          ..addAll(_undoStack.removeLast());
      });
    } else if (_points.isNotEmpty) {
      setState(() {
        _points.removeLast();
      });
    }
  }

  void _reverse() {
    if (_points.length < 2) return;
    _pushUndo();
    setState(() {
      final reversed = _points.reversed.toList();
      _points
        ..clear()
        ..addAll(reversed);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('路线方向已反转（反穿规划）'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _clear() {
    if (_points.isEmpty && _waypoints.isEmpty) return;
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空当前规划？'),
        content: const Text('此操作将清除已绘制的全部轨迹点与航点。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) {
        _pushUndo();
        setState(() {
          _points.clear();
          _waypoints.clear();
        });
      }
    });
  }

  Future<void> _showAddWaypointDialog(LatLng pt) async {
    final nameCtrl = TextEditingController(text: '航点 ${_waypoints.length + 1}');
    final descCtrl = TextEditingController();
    var selectedType = WaypointType.poi;

    final created = await showDialog<RouteWaypoint>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('添加关键航点 (POI)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '航点名称（如：一线天、白家营地）',
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<WaypointType>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(labelText: '航点类型'),
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
                    labelText: '备注（如：可扎营3顶帐篷、有流动山泉）',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
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
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (created != null) {
      setState(() {
        _waypoints.add(created);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '已添加：${created.name}（${waypointTypeLabel(created.type)}）',
            ),
          ),
        );
      }
    }
  }

  Future<void> _saveRoute() async {
    if (_points.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('规划轨迹至少需要连接 2 个点')));
      return;
    }

    final nameCtrl = TextEditingController(
      text: '手绘规划线路 ${DateTime.now().month}月${DateTime.now().day}日',
    );
    final descCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存手绘路线并查看天气'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: '线路名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: '备注说明（可选）'),
            ),
            const SizedBox(height: 12),
            Text(
              '总里程：${(_totalDistM / 1000.0).toStringAsFixed(2)} km\n'
              '航点数：${_waypoints.length} 个\n'
              '预计徒步耗时：约 ${(_estimatedDurationMin / 60).floor()} 小时 ${_estimatedDurationMin % 60} 分钟',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存并推演天气'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final name = nameCtrl.text.trim().isEmpty
          ? '手绘规划线路'
          : nameCtrl.text.trim();
      final route = HikingRoute(
        id: 'planned-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        origin: RouteOrigin.planned,
        segments: [List.of(_points)],
        elevationsM: List.filled(_points.length, null),
        sourceName: '用户手绘规划（Trail Studio）',
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('至少需要 2 个轨迹点才能导出')));
      return;
    }

    final tempRoute = HikingRoute(
      id: 'export-temp',
      name: '手绘规划线路',
      origin: RouteOrigin.planned,
      segments: [List.of(_points)],
      elevationsM: List.filled(_points.length, null),
      sourceName: '用户规划',
      waypoints: List.of(_waypoints),
    );

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '导出规划轨迹',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '可导出为标准 GPX 或 KML 格式，在两步路、奥维互动地图或户外手表中加载：',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('复制 GPX 内容到剪贴板'),
              onPressed: () {
                final gpxStr = RouteExporter.toGpx(tempRoute);
                Clipboard.setData(ClipboardData(text: gpxStr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('GPX 文本已复制到剪贴板！可直接粘贴保存为 .gpx 文件使用'),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('复制 KML 内容到剪贴板（奥维/两步路推荐）'),
              onPressed: () {
                final kmlStr = RouteExporter.toKml(tempRoute);
                Clipboard.setData(ClipboardData(text: kmlStr));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('KML 文本已复制到剪贴板！可直接粘贴保存为 .kml 文件使用'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final basemap = Basemap(settings.basemap);

    // 显示层点转换
    final displayPoints = [for (final p in _points) basemap.toDisplay(p)];

    final displayWaypoints = [
      for (final wp in _waypoints)
        Marker(
          point: basemap.toDisplay(wp.point),
          width: 36,
          height: 36,
          child: Tooltip(
            message: '${wp.name} (${waypointTypeLabel(wp.type)})',
            child: _WaypointMarkerWidget(type: wp.type),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('线路规划工坊 (Trail Studio)'),
        actions: [
          IconButton(
            tooltip: '撤销打点',
            icon: const Icon(Icons.undo),
            onPressed: _points.isEmpty ? null : _undo,
          ),
          IconButton(
            tooltip: '反向走法（反穿）',
            icon: const Icon(Icons.swap_calls),
            onPressed: _points.length < 2 ? null : _reverse,
          ),
          IconButton(
            tooltip: '导出 GPX / KML',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _points.length < 2 ? null : _showExportModal,
          ),
          IconButton(
            tooltip: '清空重画',
            icon: const Icon(Icons.delete_outline),
            onPressed: (_points.isEmpty && _waypoints.isEmpty) ? null : _clear,
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
              onTap: _onTapMap,
            ),
            children: [
              basemap.tileLayer(),
              if (displayPoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: displayPoints,
                      strokeWidth: 4.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ],
                ),
              // 打点锚点标记
              MarkerLayer(
                markers: [
                  for (var i = 0; i < displayPoints.length; i++)
                    Marker(
                      point: displayPoints[i],
                      width: 14,
                      height: 14,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == 0
                              ? Colors.green
                              : (i == displayPoints.length - 1
                                    ? Colors.red
                                    : Colors.white),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black87, width: 2),
                        ),
                      ),
                    ),
                  ...displayWaypoints,
                ],
              ),
            ],
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
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<PlannerMode>(
                        segments: const [
                          ButtonSegment(
                            value: PlannerMode.draw,
                            icon: Icon(Icons.edit_road),
                            label: Text('打点画线'),
                          ),
                          ButtonSegment(
                            value: PlannerMode.waypoint,
                            icon: Icon(Icons.add_location_alt),
                            label: Text('标记营地/水源'),
                          ),
                        ],
                        selected: {_mode},
                        onSelectionChanged: (set) {
                          setState(() => _mode = set.first);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 底部规划状态与保存动作条
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Card(
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${(_totalDistM / 1000.0).toStringAsFixed(2)} km',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '(${_points.length} 点 / ${_waypoints.length} 航点)',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _points.isEmpty
                                ? '轻触地图任意处开始徒步规划'
                                : '预计耗时: 约 ${(_estimatedDurationMin / 60).floor()}h ${_estimatedDurationMin % 60}m',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      icon: const Icon(Icons.check),
                      label: const Text('完成并查天气'),
                      onPressed: _points.length < 2 ? null : _saveRoute,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WaypointMarkerWidget extends StatelessWidget {
  const _WaypointMarkerWidget({required this.type});

  final WaypointType type;

  @override
  Widget build(BuildContext context) {
    final (icon, col) = switch (type) {
      WaypointType.camp => (Icons.cabin, Colors.amber.shade800),
      WaypointType.water => (Icons.water_drop, Colors.blue),
      WaypointType.danger => (Icons.warning, Colors.red),
      WaypointType.pass => (Icons.landscape, Colors.deepPurple),
      WaypointType.exit => (Icons.exit_to_app, Colors.teal),
      WaypointType.poi => (Icons.place, Colors.orange),
    };

    return Container(
      decoration: BoxDecoration(
        color: col,
        shape: BoxShape.circle,
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }
}
