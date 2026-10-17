part of 'route_detail_screen.dart';

// 详情页：小地图与全屏地图。

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
            color: Semantic.route,
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
                  // 选中外圈不用红色：红色专指“触发红色阈值”。
                  border: Border.all(color: Palette.pine, width: 3),
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
