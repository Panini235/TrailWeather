import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../../data/app_providers.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/terrain/dem.dart';
import '../../data/terrain/terrain_compute.dart';
import '../../data/terrain/terrain_mesh.dart';
import '../motion.dart';
import '../strings.dart';
import '../tokens.dart';
import '../widgets/common.dart';

/// 线路 3D 地形预览（T-191，D-040）：用与等高线同一份公开高程数据，在本机画一块
/// 可转动的地形，线路贴地显示。只为看清山形与线路走向，不承载天气数据。
///
/// 动效克制：手势直接跟手，松手即停（没有惯性和自动旋转）；只有“复位”和切换
/// 高程放大倍数时有一次短过渡，系统减少动效或低耗电时直接到位。
class Route3DPage extends ConsumerStatefulWidget {
  const Route3DPage({super.key, required this.route});

  final HikingRoute route;

  @override
  ConsumerState<Route3DPage> createState() => _Route3DPageState();
}

enum _Phase { loading, ready, failed, noRoute }

class _Route3DPageState extends ConsumerState<Route3DPage>
    with SingleTickerProviderStateMixin {
  late final DemService _dem = ref.read(demServiceProvider);
  late final TerrainRegion? _region = TerrainRegion.forPoints(
    widget.route.flatPoints,
  );
  final _view = _View();
  late final AnimationController _anim = AnimationController(vsync: this)
    ..addListener(_onAnim);
  _ViewValues? _from, _to;

  _Phase _phase = _Phase.loading;
  int _loaded = 0, _total = 0;
  _Scene? _scene;
  double _exaggeration = 1;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _anim.dispose();
    _view.dispose();
    super.dispose();
  }

  Future<void> _load({bool retry = false}) async {
    final region = _region;
    if (region == null) {
      setState(() => _phase = _Phase.noRoute);
      return;
    }
    final tiles = region.tiles.toList();
    setState(() {
      _phase = _Phase.loading;
      _total = tiles.length;
      _loaded = 0;
    });
    final results = await Future.wait([
      for (final k in tiles)
        _dem.load(k, retry: retry).then((t) {
          if (mounted) setState(() => _loaded++);
          return t;
        }),
    ]);
    if (!mounted) return;
    final grid = results.any((t) => t == null)
        ? null
        : TerrainGrid.sample(region, demServiceSampler(_dem));
    if (grid == null || grid.missingFraction > 0.5) {
      setState(() => _phase = _Phase.failed);
      return;
    }
    setState(() {
      _scene = _Scene(grid, widget.route.segments, _exaggeration);
      _phase = _Phase.ready;
    });
  }

  bool get _reduced =>
      Motion.reduced(context, lowPower: ref.read(settingsProvider).lowPower);

  /// 过渡到 [to]；减少动效时直接到位。
  void _animateTo(_ViewValues to, Duration d) {
    if (_reduced) {
      _view.apply(to);
      return;
    }
    _from = _view.values;
    _to = to;
    _anim
      ..duration = d
      ..forward(from: 0);
  }

  void _onAnim() {
    final from = _from, to = _to;
    if (from == null || to == null) return;
    _view.apply(
      _ViewValues.lerp(from, to, Motion.enter.transform(_anim.value)),
    );
  }

  void _reset() => _animateTo(
    _ViewValues.initial.copyWith(exaggeration: _view.exaggeration),
    Motion.slow,
  );

  void _setExaggeration(double ex) {
    setState(() => _exaggeration = ex);
    _scene?.setLighting(ex);
    _animateTo(_view.values.copyWith(exaggeration: ex), Motion.base);
  }

  // ------------------------------------------------------------------ 手势

  _ViewValues? _gestureStart;

  void _onScaleStart(ScaleStartDetails d) {
    _anim.stop();
    _gestureStart = _view.values;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final start = _gestureStart;
    final scene = _scene;
    if (start == null || scene == null) return;
    final v = _view.values;
    if (d.pointerCount == 1) {
      // 单指：左右转、上下俯仰
      _view.apply(
        v.copyWith(
          bearing: v.bearing - d.focalPointDelta.dx * 0.006,
          tilt: (v.tilt - d.focalPointDelta.dy * 0.005).clamp(
            0.0,
            _ViewValues.maxTilt,
          ),
        ),
      );
      return;
    }
    // 双指：缩放、扭转、平移
    final zoom = (start.zoom * d.scale).clamp(0.7, 5.0);
    final s = scene.fitScale * zoom;
    final sb = math.sin(v.bearing), cb = math.cos(v.bearing);
    final dx = d.focalPointDelta.dx / s;
    final dy = d.focalPointDelta.dy / s / math.max(math.cos(v.tilt), 0.35);
    final g = scene.grid;
    _view.apply(
      v.copyWith(
        zoom: zoom,
        bearing: start.bearing - d.rotation,
        targetX: (v.targetX - dx * cb + dy * sb).clamp(
          -g.widthM / 2,
          g.widthM / 2,
        ),
        targetY: (v.targetY + dx * sb + dy * cb).clamp(
          -g.heightM / 2,
          g.heightM / 2,
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ 界面

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scene = _scene;
    return Scaffold(
      appBar: AppBar(title: const Text(S.route3dTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: scene == null ? 0 : 1,
                    duration: Motion.of(
                      context,
                      Motion.base,
                      lowPower: ref.watch(settingsProvider).lowPower,
                    ),
                    curve: Motion.enter,
                    child: scene == null
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onScaleStart: _onScaleStart,
                            onScaleUpdate: _onScaleUpdate,
                            onDoubleTap: _reset,
                            child: Semantics(
                              label: S.route3dTitle,
                              image: true,
                              child: RepaintBoundary(
                                child: CustomPaint(
                                  size: Size.infinite,
                                  painter: _TerrainPainter(
                                    scene,
                                    _view,
                                    dark: theme.brightness == Brightness.dark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
                if (_phase == _Phase.loading)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: Space.sm),
                        HelpText('${S.route3dLoading} $_loaded / $_total'),
                      ],
                    ),
                  ),
                if (_phase == _Phase.failed || _phase == _Phase.noRoute)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.xl),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _phase == _Phase.failed
                                ? S.route3dFailed
                                : S.route3dNoRoute,
                            textAlign: TextAlign.center,
                          ),
                          if (_phase == _Phase.failed) ...[
                            const SizedBox(height: Space.sm),
                            OutlinedButton(
                              onPressed: () => _load(retry: true),
                              child: const Text(S.route3dRetry),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                if (scene != null) ...[
                  Positioned(
                    top: Space.sm,
                    left: Space.sm,
                    child: _Compass(
                      view: _view,
                      onPressed: () => _animateTo(
                        _view.values.copyWith(bearing: 0),
                        Motion.slow,
                      ),
                    ),
                  ),
                  Positioned(
                    top: Space.md,
                    right: Space.md,
                    child: _Badge(
                      _exaggeration == 1
                          ? S.route3dExNone
                          : '${S.route3dExPrefix}${_fmtEx(_exaggeration)}',
                    ),
                  ),
                ],
              ],
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerLow,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.lg,
                  Space.md,
                  Space.lg,
                  Space.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Text(S.route3dExLabel),
                        const SizedBox(width: Space.md),
                        Expanded(
                          child: SegmentedButton<double>(
                            showSelectedIcon: false,
                            segments: [
                              for (final ex in _Scene.exaggerations)
                                ButtonSegment(
                                  value: ex,
                                  label: Text('×${_fmtEx(ex)}'),
                                ),
                            ],
                            selected: {_exaggeration},
                            onSelectionChanged: scene == null
                                ? null
                                : (s) => _setExaggeration(s.first),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.sm),
                    const HelpText(S.route3dHint),
                    HelpText(
                      S.route3dNote(
                        displayElevation(
                          scene?.grid.spacingM ?? TerrainRegion.minSpacingM,
                        ),
                      ),
                    ),
                    if (scene != null && scene.grid.missingFraction > 0)
                      const HelpText(S.route3dPartial),
                    const HelpText(S.terrainAttribution),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtEx(double ex) =>
      ex == ex.roundToDouble() ? ex.toStringAsFixed(0) : ex.toString();
}

/// 视角参数（弧度、米）。
class _ViewValues {
  const _ViewValues({
    required this.bearing,
    required this.tilt,
    required this.zoom,
    required this.targetX,
    required this.targetY,
    required this.exaggeration,
  });

  final double bearing, tilt, zoom, targetX, targetY, exaggeration;

  static const maxTilt = 75 * math.pi / 180;

  /// 初始：朝北（与平面地图一致）、斜 55°、全区域。
  static const initial = _ViewValues(
    bearing: 0,
    tilt: 55 * math.pi / 180,
    zoom: 1,
    targetX: 0,
    targetY: 0,
    exaggeration: 1,
  );

  _ViewValues copyWith({
    double? bearing,
    double? tilt,
    double? zoom,
    double? targetX,
    double? targetY,
    double? exaggeration,
  }) => _ViewValues(
    bearing: bearing ?? this.bearing,
    tilt: tilt ?? this.tilt,
    zoom: zoom ?? this.zoom,
    targetX: targetX ?? this.targetX,
    targetY: targetY ?? this.targetY,
    exaggeration: exaggeration ?? this.exaggeration,
  );

  /// 朝向走近的那一边（不绕远路转一圈）。
  static _ViewValues lerp(_ViewValues a, _ViewValues b, double t) {
    var db = (b.bearing - a.bearing) % (2 * math.pi);
    if (db > math.pi) db -= 2 * math.pi;
    double l(double x, double y) => x + (y - x) * t;
    return _ViewValues(
      bearing: a.bearing + db * t,
      tilt: l(a.tilt, b.tilt),
      zoom: l(a.zoom, b.zoom),
      targetX: l(a.targetX, b.targetX),
      targetY: l(a.targetY, b.targetY),
      exaggeration: l(a.exaggeration, b.exaggeration),
    );
  }
}

/// 视角状态：变化时只重绘地形画布，不重建页面。
class _View extends ChangeNotifier {
  _ViewValues values = _ViewValues.initial;

  double get bearing => values.bearing;
  double get exaggeration => values.exaggeration;

  void apply(_ViewValues v) {
    values = v;
    notifyListeners();
  }
}

/// 地形与线路的几何、颜色和每帧复用的缓冲区。
class _Scene {
  _Scene(this.grid, List<List<LatLng>> segments, double exaggeration) {
    final cols = grid.cols, rows = grid.rows;
    nTerrain = cols * rows;
    _sides = [
      // 北、南、西、东：格点下标序列与外法线
      _Side([for (var j = 0; j < cols; j++) j], 0, 1),
      _Side([for (var j = 0; j < cols; j++) (rows - 1) * cols + j], 0, -1),
      _Side([for (var i = 0; i < rows; i++) i * cols], -1, 0),
      _Side([for (var i = 0; i < rows; i++) i * cols + cols - 1], 1, 0),
    ];
    var n = nTerrain;
    for (final s in _sides) {
      s.offset = n;
      n += s.cells.length * 2;
    }
    nAll = n;
    ground = Float32List(nAll * 2);
    rel = Float32List(nAll);
    for (var i = 0; i < rows; i++) {
      for (var j = 0; j < cols; j++) {
        final o = i * cols + j;
        final (x, y) = grid.groundOf(j.toDouble(), i.toDouble());
        ground[o * 2] = x;
        ground[o * 2 + 1] = y;
        rel[o] = grid.elev[o] - grid.midE;
      }
    }
    final diag = math.sqrt(
      grid.widthM * grid.widthM + grid.heightM * grid.heightM,
    );
    plinthM = diag * 0.035;
    distance = diag * 1.8;
    for (final s in _sides) {
      for (var k = 0; k < s.cells.length; k++) {
        final src = s.cells[k];
        final top = s.offset + k, bottom = s.offset + s.cells.length + k;
        for (final v in [top, bottom]) {
          ground[v * 2] = ground[src * 2];
          ground[v * 2 + 1] = ground[src * 2 + 1];
        }
        rel[top] = rel[src];
        rel[bottom] = double.nan; // 底边：高度单独算（见 _updateZ）
      }
    }
    xyz = Float32List(nAll * 3);
    xy = Float32List(nAll * 2);
    depth = Float32List(nAll);
    cellDepth = Float32List((cols - 1) * (rows - 1));
    var quads = 0;
    for (final s in _sides) {
      quads += s.cells.length - 1;
    }
    indices = Uint16List(cellDepth.length * 6 + quads * 6);
    colors = Int32List(nAll);
    for (final ex in exaggerations) {
      _lit[ex] = terrainVertexColors(grid, ex, lowArgb: _low, highArgb: _high);
    }
    setLighting(exaggeration);

    for (final seg in segments) {
      if (seg.length < 2) continue;
      final (pts, _) = densify(seg, grid.spacingM * 0.5);
      final r = Float32List(pts.length * 3);
      for (var i = 0; i < pts.length; i++) {
        final (gx, gy) = grid.region.gridOf(pts[i]);
        final (x, y) = grid.groundOf(gx, gy);
        r[i * 3] = x;
        r[i * 3 + 1] = y;
        r[i * 3 + 2] = grid.heightAt(gx, gy) - grid.midE;
      }
      routeRel.add(r);
    }
    final all = [for (final s in segments) ...s];
    if (all.isNotEmpty) {
      ends = [all.first, all.last];
    }
  }

  final TerrainGrid grid;
  late final int nTerrain, nAll;
  late final List<_Side> _sides;
  late final Float32List ground, rel, xyz, xy, depth, cellDepth;
  late final Uint16List indices;
  late final Int32List colors;
  late final double plinthM, distance;

  /// 线路（每段）：地面 x、y 与相对高程（缺失为 NaN）。
  final routeRel = <Float32List>[];
  List<LatLng> ends = const [];

  static const exaggerations = [1.0, 1.5, 2.0];

  static const _low = 0xFFA9BC9F; // 低处偏绿
  static const _high = 0xFFEDE6D6; // 高处偏米白
  static const _wallTop = 0xFF9A9180;
  static const _wallBottom = 0xFF6F685B;

  /// 三档倍数的地形光照在生成时一次算好，切换时只拷贝，不卡帧。
  final _lit = <double, Int32List>{};

  /// 光照随高程放大倍数变化（坡度变了）。
  void setLighting(double ex) {
    final c = _lit[ex] ??= terrainVertexColors(
      grid,
      ex,
      lowArgb: _low,
      highArgb: _high,
    );
    colors.setRange(0, nTerrain, c);
    for (final s in _sides) {
      // 侧面：朝西北（光源方向）的亮一些
      final f = 0.78 + 0.22 * math.max(0, (-s.nx + s.ny) * 0.7071);
      int shade(int argb) {
        int ch(int shift) => (((argb >> shift) & 0xFF) * f).round();
        return 0xFF000000 | ch(16) << 16 | ch(8) << 8 | ch(0);
      }

      for (var k = 0; k < s.cells.length; k++) {
        colors[s.offset + k] = shade(_wallTop);
        colors[s.offset + s.cells.length + k] = shade(_wallBottom);
      }
    }
    _lastEx = null;
  }

  double? _lastEx;
  double get maxZ => (grid.maxE - grid.midE) * (_lastEx ?? 1);

  void _updateZ(double ex) {
    if (_lastEx == ex) return;
    _lastEx = ex;
    final bottom = (grid.minE - grid.midE) * ex - plinthM;
    for (var i = 0; i < nAll; i++) {
      xyz[i * 3] = ground[i * 2];
      xyz[i * 3 + 1] = ground[i * 2 + 1];
      final r = rel[i];
      xyz[i * 3 + 2] = r.isNaN ? (i < nTerrain ? 0 : bottom) : r * ex;
    }
  }

  /// 旋转中心处每米多少像素：在各个朝向下整块地形都放得下。按尺寸与倍数缓存。
  double fitScale = 1;
  Size? _fitSize;
  double? _fitEx;

  void _fit(Size size, _ViewValues v) {
    if (_fitSize == size && _fitEx == v.exaggeration) return;
    _fitSize = size;
    _fitEx = v.exaggeration;
    final w = grid.widthM / 2, h = grid.heightM / 2;
    final top = (grid.maxE - grid.midE) * v.exaggeration;
    final bottom = (grid.minE - grid.midE) * v.exaggeration - plinthM;
    final corners = Float32List.fromList([
      for (final z in [top, bottom]) ...[
        -w,
        -h,
        z,
        w,
        -h,
        z,
        -w,
        h,
        z,
        w,
        h,
        z,
      ],
    ]);
    final out = Float32List(16), d = Float32List(8);
    var ax = 0.0, ay = 0.0;
    for (var b = 0; b < 12; b++) {
      OrbitCamera(
        bearing: b * math.pi / 6,
        tilt: _ViewValues.initial.tilt,
        distance: distance,
        scale: 1,
        cx: 0,
        cy: 0,
      ).project(corners, out, d);
      for (var i = 0; i < 8; i++) {
        ax = math.max(ax, out[i * 2].abs());
        ay = math.max(ay, out[i * 2 + 1].abs());
      }
    }
    fitScale = math.min(size.width / (2 * ax), size.height / (2 * ay)) * 0.96;
  }

  OrbitCamera camera(Size size, _ViewValues v) {
    _fit(size, v);
    return OrbitCamera(
      bearing: v.bearing,
      tilt: v.tilt,
      distance: distance,
      scale: fitScale * v.zoom,
      cx: size.width / 2,
      cy: size.height / 2,
      targetX: v.targetX,
      targetY: v.targetY,
    );
  }

  /// 本帧要画的三角形（由远到近）；返回索引个数。
  int buildIndices(OrbitCamera cam) {
    final cols = grid.cols, rows = grid.rows;
    var c = 0;
    for (var i = 0; i < rows - 1; i++) {
      for (var j = 0; j < cols - 1; j++, c++) {
        final a = i * cols + j, b = a + 1, d = a + cols, e = d + 1;
        cellDepth[c] =
            rel[a].isNaN || rel[b].isNaN || rel[d].isNaN || rel[e].isNaN
            ? double.nan
            : (depth[a] + depth[b] + depth[d] + depth[e]) / 4;
      }
    }
    var n = 0;
    for (final cell in farToNear(cellDepth)) {
      final i = cell ~/ (cols - 1), j = cell % (cols - 1);
      final a = i * cols + j, b = a + 1, d = a + cols, e = d + 1;
      indices
        ..[n++] = a
        ..[n++] = b
        ..[n++] = d
        ..[n++] = b
        ..[n++] = e
        ..[n++] = d;
    }
    // 侧面裙边在所有地形之前（离相机更近），只画朝向相机的面。
    for (final s in _sides) {
      if (!cam.facesCamera(s.nx, s.ny)) continue;
      final len = s.cells.length;
      for (var k = 0; k < len - 1; k++) {
        if (rel[s.cells[k]].isNaN || rel[s.cells[k + 1]].isNaN) continue;
        final t0 = s.offset + k, t1 = t0 + 1;
        final b0 = s.offset + len + k, b1 = b0 + 1;
        indices
          ..[n++] = t0
          ..[n++] = t1
          ..[n++] = b0
          ..[n++] = t1
          ..[n++] = b1
          ..[n++] = b0;
      }
    }
    return n;
  }
}

class _Side {
  _Side(this.cells, this.nx, this.ny);

  final List<int> cells;
  final double nx, ny;
  int offset = 0;
}

class _TerrainPainter extends CustomPainter {
  _TerrainPainter(this.scene, this.view, {required this.dark})
    : super(repaint: view);

  final _Scene scene;
  final _View view;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final v = view.values;
    final s = scene;
    s._updateZ(v.exaggeration);
    final cam = s.camera(size, v);
    cam.project(s.xyz, s.xy, s.depth);
    final n = s.buildIndices(cam);
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      s.xy,
      colors: s.colors,
      indices: Uint16List.sublistView(s.indices, 0, n),
    );
    canvas.drawVertices(vertices, BlendMode.dst, Paint());
    vertices.dispose();
    _drawRoute(canvas, cam, v.exaggeration);
  }

  void _drawRoute(Canvas canvas, OrbitCamera cam, double ex) {
    final g = scene.grid;
    final lift = g.spacingM * 0.35;
    final maxZ = (g.maxE - g.midE) * ex;
    double zOf(double gx, double gy) => (g.heightAt(gx, gy) - g.midE) * ex;
    final solid = Path(), hidden = Path();
    for (final r in scene.routeRel) {
      final m = r.length ~/ 3;
      final pts = Float32List(m * 3);
      for (var i = 0; i < m; i++) {
        pts[i * 3] = r[i * 3];
        pts[i * 3 + 1] = r[i * 3 + 1];
        pts[i * 3 + 2] = r[i * 3 + 2] * ex + lift;
      }
      final xy = Float32List(m * 2), d = Float32List(m);
      cam.project(pts, xy, d);
      final vis = List<bool>.generate(
        m,
        (i) =>
            !pts[i * 3 + 2].isNaN &&
            !occluded(
              g,
              cam,
              pts[i * 3],
              pts[i * 3 + 1],
              pts[i * 3 + 2],
              zOf: zOf,
              maxZ: maxZ,
            ),
      );
      for (var i = 1; i < m; i++) {
        if (pts[i * 3 + 2].isNaN || pts[i * 3 - 1].isNaN) continue;
        final a = Offset(xy[i * 2 - 2], xy[i * 2 - 1]);
        final b = Offset(xy[i * 2], xy[i * 2 + 1]);
        (vis[i - 1] && vis[i] ? solid : hidden)
          ..moveTo(a.dx, a.dy)
          ..lineTo(b.dx, b.dy);
      }
    }
    canvas
      ..drawPath(
        _dashed(hidden),
        Paint()
          ..color = Semantic.route.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      )
      ..drawPath(
        solid,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      )
      ..drawPath(
        solid,
        Paint()
          ..color = Semantic.route
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round,
      );

    // 起点、终点（被挡住时画淡）
    final ends = scene.ends;
    for (var k = ends.length - 1; k >= 0; k--) {
      final p = ends[k];
      final (gx, gy) = g.region.gridOf(p);
      final h = zOf(gx, gy);
      if (h.isNaN) continue;
      final (x, y) = g.groundOf(gx, gy);
      final xyz = Float32List.fromList([x, y, h + lift]);
      final out = Float32List(2), d = Float32List(1);
      cam.project(xyz, out, d);
      final hiddenEnd = occluded(g, cam, x, y, h + lift, zOf: zOf, maxZ: maxZ);
      final c = Offset(out[0], out[1]);
      final alpha = hiddenEnd ? 0.45 : 1.0;
      canvas
        ..drawCircle(
          c,
          7,
          Paint()..color = Colors.white.withValues(alpha: alpha),
        )
        ..drawCircle(
          c,
          5,
          Paint()
            ..color = (k == 0 ? Semantic.go : Semantic.danger).withValues(
              alpha: alpha,
            ),
        );
    }
  }

  /// 被山体挡住的路段：6 px 实、5 px 空的虚线。
  static Path _dashed(Path src) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 11) {
        out.addPath(m.extractPath(d, math.min(d + 6, m.length)), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter old) =>
      !identical(old.scene, scene) || old.dark != dark;
}

/// 指北针：随视角转动；点一下转回朝北。
class _Compass extends StatelessWidget {
  const _Compass({required this.view, required this.onPressed});

  final _View view;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerHighest
        .withValues(alpha: 0.9),
    shape: const CircleBorder(),
    child: IconButton(
      tooltip: S.route3dCompass,
      onPressed: onPressed,
      icon: ListenableBuilder(
        listenable: view,
        builder: (context, _) => Transform.rotate(
          angle: -view.bearing,
          child: const Icon(Icons.navigation, color: Semantic.danger),
        ),
      ),
    ),
  );
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    ),
  );
}
