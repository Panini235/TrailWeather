part of 'route_detail_screen.dart';

// 详情页：小地图与全屏地图。

/// 小地图可选的平面地形图层（不含卫星与 3D）：底图 id → 叠加层。
/// 天地图地形晕渲没有地名，自动叠加天地图地形注记。
const _miniMapLayers = <String, List<OverlaySelection>>{
  'opentopomap': [],
  'tianditu_ter': [OverlaySelection('tianditu_cta')],
};

/// 按“小地图图层”设置换底图；空串或不在白名单内时跟随地图设置。
AppSettings _miniMapSettings(AppSettings s) {
  final overlays = _miniMapLayers[s.routeMapLayerId];
  if (overlays == null) return s;
  return s.copyWith(baseLayerId: s.routeMapLayerId, overlayLayers: overlays);
}

class _RouteMiniMap extends ConsumerStatefulWidget {
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
  ConsumerState<_RouteMiniMap> createState() => _RouteMiniMapState();
}

class _RouteMiniMapState extends ConsumerState<_RouteMiniMap> {
  final MapController _controller = MapController();

  /// 当前图层是否有瓦片加载失败或迟迟加载不出（换图层时重置）。
  bool _tileFailed = false;
  bool _anyTileLoaded = false;
  String? _signature;
  Timer? _slowTimer;

  /// 自选图层 10 秒内没有任何瓦片成功显示，就当作连不上：国内连海外图源时
  /// 请求常常挂起而不报错（没有连接超时），只靠失败回调会一直空白无提示。
  static const _slowAfter = Duration(seconds: 10);

  void _watchLayer(bool customLayer) {
    _slowTimer?.cancel();
    _anyTileLoaded = false;
    _tileFailed = false;
    if (!customLayer) return;
    _slowTimer = Timer(_slowAfter, () {
      if (mounted && !_anyTileLoaded) setState(() => _tileFailed = true);
    });
  }

  void _onTileError() {
    if (_tileFailed) return;
    // 回调可能在构建/布局期间触发，延后到帧结束再 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_tileFailed) setState(() => _tileFailed = true);
    });
  }

  @override
  void dispose() {
    _slowTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final route = widget.route;
    final rows = widget.rows;
    final settings = ref.watch(settingsProvider);
    final customLayer = _miniMapLayers.containsKey(settings.routeMapLayerId);
    final basemap = Basemap.fromSettings(
      _miniMapSettings(settings),
      tiandituClient: ref.watch(tiandituTileClientProvider),
    );
    if (_signature != basemap.signature) {
      _signature = basemap.signature;
      _watchLayer(customLayer);
    }
    final fit = routeCameraFit(route, basemap);
    final photos = ref
        .watch(routePhotosProvider)
        .where((p) => p.routeId == route.id)
        .toList();
    // 只开双指缩放/平移与双击放大：单指拖动留给外层 ListView 上下滚动，
    // 避免一滑页面就变成拖地图。点节点选中，再点打开节点详情。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 220,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  // 反向行走时几何不变但起终点互换，key 带上方向让相机与标记重建。
                  key: ValueKey(
                    'mini-${route.id}-${basemap.signature}-${route.flatPoints.first}',
                  ),
                  options: MapOptions(
                    initialCameraFit: fit,
                    // 无几何时的兜底；有 fit 时 initialCameraFit 优先。
                    initialCenter: const LatLng(39.99, 116.17),
                    initialZoom: 12,
                    minZoom: 3,
                    maxZoom: 18,
                    interactionOptions: const InteractionOptions(
                      flags:
                          InteractiveFlag.pinchZoom |
                          InteractiveFlag.pinchMove |
                          InteractiveFlag.doubleTapZoom,
                    ),
                  ),
                  children: _routeMapLayers(
                    basemap: basemap,
                    route: route,
                    rows: rows,
                    selectedIndex: widget.selectedIndex,
                    onTapNode: widget.onTapNode,
                    photos: photos,
                    onTapPhoto: (p) => showRoutePhotoViewer(context, p),
                    // 只对小地图自选的地形图层提示；默认底图沿用原有行为。
                    onTileError: customLayer ? _onTileError : null,
                    onTileLoaded: customLayer
                        ? () => _anyTileLoaded = true
                        : null,
                    terrain: terrainLayerFor(ref, basemap),
                  ),
                ),
                if (customLayer && _tileFailed)
                  Positioned(
                    left: 6,
                    right: 58,
                    bottom: 6,
                    child: _LayerFailedBanner(
                      onRevert: () => ref
                          .read(settingsProvider.notifier)
                          .setRouteMapLayer(''),
                    ),
                  ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: Column(
                    children: [
                      _mapButton(
                        context,
                        tooltip: S.routeMapFullscreen,
                        icon: Icons.fullscreen,
                        onPressed: widget.onOpenFullscreen,
                      ),
                      const SizedBox(height: Space.xs),
                      _mapButton(
                        context,
                        tooltip: S.miniMapLayers,
                        icon: Icons.layers_outlined,
                        onPressed: () => _showLayers(context),
                      ),
                      if (fit != null) ...[
                        const SizedBox(height: Space.xs),
                        _mapButton(
                          context,
                          tooltip: S.miniMapFit,
                          icon: Icons.fit_screen,
                          onPressed: () => _controller.fitCamera(fit),
                        ),
                      ],
                    ],
                  ),
                ),
                const Positioned(
                  top: 6,
                  left: 6,
                  right: 58,
                  child: TiandituErrorBanner(compact: true),
                ),
                if (route.flatPoints.length >= 2)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: _mapButton(
                      context,
                      tooltip: S.route3dTitle,
                      icon: Icons.view_in_ar_outlined,
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => Route3DPage(route: route),
                        ),
                      ),
                    ),
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
        const HelpText(S.miniMapGestureHint),
      ],
    );
  }

  Widget _mapButton(
    BuildContext context, {
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
  }) => Material(
    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
    shape: const CircleBorder(),
    child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
  );

  /// 小地图图层：跟随设置 / 等高线 / 天地图地形晕渲；不提供卫星与 3D。
  Future<void> _showLayers(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final base = findTileSource(
      settings.baseLayerId,
      settings.customTileSources,
    );
    final hasTdt = settings.tiandituKeys
        .forRequester(flutterMapRequester)
        .trim()
        .isNotEmpty;
    final current = _miniMapLayers.containsKey(settings.routeMapLayerId)
        ? settings.routeMapLayerId
        : '';
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        Widget option(
          String id,
          String title,
          String? subtitle, {
          bool enabled = true,
        }) => ListTile(
          enabled: enabled,
          leading: Icon(
            id == current ? Icons.radio_button_checked : Icons.radio_button_off,
          ),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          onTap: () {
            Navigator.pop(ctx);
            notifier.setRouteMapLayer(id);
          },
        );
        final topo = findTileSource('opentopomap', const []);
        final ter = findTileSource('tianditu_ter', const []);
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.lg,
                    0,
                    Space.lg,
                    Space.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        S.miniMapLayers,
                        style: Theme.of(ctx).textTheme.titleMedium,
                      ),
                      const HelpText(S.miniMapLayersHint),
                    ],
                  ),
                ),
                option('', S.miniMapFollowSettings, base?.name),
                // 国内官方图源排第一（D-034）；没有 Key 时点击直接去填 Key。
                if (ter != null)
                  hasTdt
                      ? option(
                          ter.id,
                          S.detailMapRecommended(ter.name),
                          S.miniMapTiandituNote,
                        )
                      : ListTile(
                          leading: const Icon(Icons.vpn_key_outlined),
                          title: Text(S.detailMapRecommended(ter.name)),
                          subtitle: const Text(S.miniMapNeedsTiandituKey),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const MapSourcesPage(),
                              ),
                            );
                          },
                        ),
                if (topo != null)
                  option(topo.id, S.detailMapOverseas(topo.name), topo.note),
                const Divider(height: Space.lg),
                // 等高线、地形阴影由公开高程数据在本机计算，叠在任意底图上（与地图页共用设置）。
                Consumer(
                  builder: (ctx, ref, _) {
                    final s = ref.watch(settingsProvider);
                    return Column(
                      children: [
                        SwitchListTile(
                          secondary: const Icon(Icons.line_axis),
                          title: const Text(S.terrainContours),
                          subtitle: const Text(S.terrainContoursNote),
                          value: s.terrainContours,
                          onChanged: notifier.setTerrainContours,
                        ),
                        SwitchListTile(
                          secondary: const Icon(Icons.terrain_outlined),
                          title: const Text(S.terrainHillshade),
                          subtitle: const Text(S.terrainHillshadeNote),
                          value: s.terrainHillshade,
                          onChanged: notifier.setTerrainHillshade,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 小地图自选图层加载失败时的提示：国内网络常连不上海外图源，给出“切回”。
class _LayerFailedBanner extends StatelessWidget {
  const _LayerFailedBanner({required this.onRevert});

  final VoidCallback onRevert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, 0, Space.xs),
        child: Row(
          children: [
            Expanded(
              child: Text(
                S.miniMapLayerFailed,
                style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: onRevert, child: const Text(S.miniMapRevert)),
          ],
        ),
      ),
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
  VoidCallback? onTileError,
  VoidCallback? onTileLoaded,
  Widget? terrain,
}) {
  final onRoute = {
    for (final r in rows) ...[?r.node.waypoint, ...r.node.nearbyWaypoints],
  };
  final sel = selectedIndex != null && selectedIndex < rows.length
      ? selectedIndex
      : null;
  return [
    ...basemap.tileLayers(onTileError: onTileError, onTileLoaded: onTileLoaded),
    ?terrain,
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
        // 挂在节点上的普通航点：画在自己的位置，点按选中它归属的节点。
        for (var i = 0; i < rows.length; i++)
          for (final wp in rows[i].node.nearbyWaypoints)
            Marker(
              point: basemap.toDisplay(wp.point),
              width: 22,
              height: 22,
              child: Tooltip(
                message: '${wp.name}（${S.nearbyMarkTooltip}）',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapNode == null ? null : () => onTapNode(i),
                  child: Center(child: WaypointMarker(type: wp.type, size: 14)),
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
    if (terrain != null && attribution) const ContourIntervalBadge(),
    if (attribution)
      basemap.attributionWidget(
        extra: terrain == null ? const [] : const [S.terrainAttribution],
      ),
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
              terrain: terrainLayerFor(ref, basemap),
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
                      '${widget.rows[sel].node.label ?? S.detailNodeFallback(sel + 1)} · '
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
