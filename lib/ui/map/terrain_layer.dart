import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/gcj02.dart';
import '../../data/app_providers.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/terrain/dem.dart';
import '../../data/terrain/terrain_compute.dart';
import '../strings.dart';
import 'basemap.dart';

/// 地形图层（D-039）：由公开高程数据在本机计算的等高线与地形阴影，可叠在任意底图上。
///
/// - 高德（GCJ-02）底图下按瓦片四角的火星偏移在块内插值（[gcjTileWarp]），相邻瓦片边界严丝合缝；
/// - 计算在后台 isolate；停下 120 ms 后才补瓦片，平移缩放只改画布变换；
/// - 新等高距或新级别算好之前，继续画已有的（上一级或上一个等高距），不闪白。
class TerrainLayer extends StatefulWidget {
  const TerrainLayer({
    super.key,
    required this.dem,
    required this.basemap,
    this.contours = true,
    this.hillshade = false,
  });

  final DemService dem;
  final Basemap basemap;
  final bool contours;
  final bool hillshade;

  /// 某缩放级别用哪一级高程瓦片：比地图低一级（一块高程瓦片覆盖 2×2 块底图），最高 12 级。
  static int demZoomFor(double mapZoom) =>
      (mapZoom.floor() - 1).clamp(DemService.minZoom, DemService.maxZoom);

  /// 瓦片四角从 WGS-84 到 GCJ-02 的位移（瓦片像素）；境外为 0。
  @visibleForTesting
  static TileWarp gcjTileWarp(DemTileKey k) {
    final w = Float32List(8);
    var i = 0;
    for (final dy in const [0, 256]) {
      for (final dx in const [0, 256]) {
        final px = k.x * 256.0 + dx, py = k.y * 256.0 + dy;
        final c = latLngOfWorldPixel(px, py, k.z);
        final g = Gcj02.wgs84ToGcj02(c);
        final (gx, gy) = worldPixel(g.latitude, g.longitude, k.z);
        w[i++] = gx - px;
        w[i++] = gy - py;
      }
    }
    return w;
  }

  @override
  State<TerrainLayer> createState() => _TerrainLayerState();
}

typedef _RKey = (DemTileKey, double?, bool);

class _Rendered {
  _Rendered({
    required this.key,
    required this.minor,
    required this.major,
    required this.shade,
    required this.neighborMask,
    required this.warp,
  });

  final DemTileKey key;
  final ContourLines? minor;
  final ContourLines? major;
  final ui.Image? shade;
  final int neighborMask;

  /// 贴到 GCJ-02 底图时的四角位移；WGS-84 底图为 null。
  final TileWarp? warp;

  /// 按线宽档位缓存的三角网格（档位 → 网格）。只在线宽档位变了时重建一次。
  int? _bucket;
  ui.Vertices? _minorMesh, _majorMesh;

  (ui.Vertices?, ui.Vertices?) meshes(
    int bucket,
    double minorHalf,
    double majorHalf,
  ) {
    if (_bucket != bucket) {
      _minorMesh?.dispose();
      _majorMesh?.dispose();
      ui.Vertices? build(ContourLines? l, double hw) {
        if (l == null || l.segmentCount == 0) return null;
        final tris = strokeTriangles(l, hw);
        if (warp != null) warpPoints(tris, warp!);
        return ui.Vertices.raw(ui.VertexMode.triangles, tris);
      }

      _minorMesh = build(minor, minorHalf);
      _majorMesh = build(major, majorHalf);
      _bucket = bucket;
    }
    return (_minorMesh, _majorMesh);
  }

  /// 地形阴影贴图的仿射变换（列主序 4×4）：四角位移的最小二乘仿射近似，
  /// 与双线性位移相差不到 0.05 像素（见测试）。只用普通 drawImageRect 加画布变换，
  /// 不用带纹理坐标的 drawVertices（后者在 Impeller / Vulkan 上会让光栅线程崩溃）。
  Float64List shadeTransform() => _shadeTransform ??= affineOfWarp(warp!);
  Float64List? _shadeTransform;

  void dispose() {
    shade?.dispose();
    _minorMesh?.dispose();
    _majorMesh?.dispose();
  }
}

class _TerrainLayerState extends State<TerrainLayer> {
  static const _capacity = 80;
  static const _maxJobs = 2;

  final _rendered = <_RKey, _Rendered>{}; // 插入有序，用作 LRU
  final _byTile = <DemTileKey, _Rendered>{};
  final _computing = <_RKey>{};
  final _repaint = ValueNotifier<int>(0);
  Timer? _debounce;
  MapCamera? _camera;
  int _jobs = 0;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    widget.dem.addListener(_schedule);
  }

  @override
  void didUpdateWidget(covariant TerrainLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.dem, widget.dem)) {
      old.dem.removeListener(_schedule);
      widget.dem.addListener(_schedule);
    }
    if (old.basemap.isGcj != widget.basemap.isGcj) {
      // 坐标系变了，已算好的瓦片位移不再适用。
      for (final r in _rendered.values) {
        r.dispose();
      }
      _rendered.clear();
      _byTile.clear();
    }
    if (old.contours != widget.contours ||
        old.hillshade != widget.hillshade ||
        old.basemap.isGcj != widget.basemap.isGcj) {
      _schedule();
      _repaint.value++;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    widget.dem.removeListener(_schedule);
    for (final r in _rendered.values) {
      r.dispose();
    }
    _repaint.dispose();
    super.dispose();
  }

  void _schedule() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), _update);
  }

  double? get _interval {
    final c = _camera;
    if (c == null || !widget.contours) return null;
    return contourSpec(c.zoom)?.interval;
  }

  /// 视野内需要的高程瓦片（按离视野中心的距离排序）。
  List<DemTileKey> _visibleKeys(MapCamera camera) {
    final z = TerrainLayer.demZoomFor(camera.zoom);
    final b = widget.basemap.toBusinessBounds(camera.visibleBounds);
    final keys = DemService.tilesForBounds(
      south: b.south,
      west: b.west,
      north: b.north,
      east: b.east,
      z: z,
    ).toList();
    final (cx, cy) = worldPixel(
      camera.center.latitude,
      camera.center.longitude,
      z,
    );
    double d(DemTileKey k) =>
        math.pow(k.x * 256 + 128 - cx, 2) + math.pow(k.y * 256 + 128 - cy, 2)
            as double;
    keys.sort((a, b) => d(a).compareTo(d(b)));
    return keys.length > 40 ? keys.sublist(0, 40) : keys;
  }

  static const _neighborOffsets = [
    (-1, -1), (0, -1), (1, -1), //
    (-1, 0), (1, 0), //
    (-1, 1), (0, 1), (1, 1),
  ];

  void _update() {
    final camera = _camera;
    if (_disposed || camera == null) return;
    if (!widget.contours && !widget.hillshade) return;
    final interval = _interval;
    if (interval == null && !widget.hillshade) return;
    final spec = widget.contours ? contourSpec(camera.zoom) : null;
    for (final k in _visibleKeys(camera)) {
      final tile = widget.dem.cached(k);
      if (tile == null) {
        unawaited(widget.dem.load(k));
        continue;
      }
      final rkey = (k, interval, widget.hillshade);
      final neighbors = [
        for (final (dx, dy) in _neighborOffsets)
          widget.dem.cached(DemTileKey(k.z, k.x + dx, k.y + dy))?.elevations,
      ];
      var mask = 0;
      for (var i = 0; i < neighbors.length; i++) {
        if (neighbors[i] != null) mask |= 1 << i;
      }
      final have = _rendered[rkey];
      if (have != null && have.neighborMask == mask) continue;
      if (_computing.contains(rkey) || _jobs >= _maxJobs) continue;
      _computing.add(rkey);
      _jobs++;
      unawaited(_compute(rkey, tile, neighbors, mask, spec?.indexEvery ?? 5));
    }
  }

  Future<void> _compute(
    _RKey rkey,
    DemTile tile,
    List<Float32List?> neighbors,
    int mask,
    int indexEvery,
  ) async {
    try {
      final job = TerrainJob(
        ext: extendedGrid(tile.elevations, neighbors, border: 2),
        border: 2,
        metersPerPixel: tile.metersPerPixel,
        interval: rkey.$2,
        indexEvery: indexEvery,
        hillshade: rkey.$3,
      );
      final result = await compute(runTerrainJob, job);
      ui.Image? shade;
      if (result.shade != null) {
        final c = Completer<ui.Image>();
        ui.decodeImageFromPixels(
          result.shade!,
          DemTile.size + 2,
          DemTile.size + 2,
          ui.PixelFormat.rgba8888,
          c.complete,
        );
        shade = await c.future;
      }
      if (_disposed) {
        shade?.dispose();
        return;
      }
      final r = _Rendered(
        key: rkey.$1,
        minor: result.minor,
        major: result.major,
        shade: shade,
        neighborMask: mask,
        warp: widget.basemap.isGcj ? TerrainLayer.gcjTileWarp(rkey.$1) : null,
      );
      _rendered.remove(rkey)?.dispose();
      _rendered[rkey] = r;
      _byTile[rkey.$1] = r;
      while (_rendered.length > _capacity) {
        final old = _rendered.remove(_rendered.keys.first)!;
        if (identical(_byTile[old.key], old)) _byTile.remove(old.key);
        old.dispose();
      }
      _repaint.value++;
    } catch (_) {
      // 计算失败：这块瓦片不画，不影响其他图层。
    } finally {
      _computing.remove(rkey);
      _jobs--;
      if (!_disposed) _schedule();
    }
  }

  /// 画某块瓦片：优先当前等高距与阴影设置的结果，没有就用这块的其他结果，
  /// 再没有就用上一级（父块）裁到这块的范围。
  _Rendered? _bestFor(DemTileKey k, double? interval) {
    final exact = _rendered[(k, interval, widget.hillshade)];
    if (exact != null) return exact;
    return _byTile[k];
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final moved =
        _camera == null ||
        _camera!.zoom != camera.zoom ||
        _camera!.center != camera.center;
    _camera = camera;
    if (moved) _schedule();
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _TerrainPainter(this, camera),
        ),
      ),
    );
  }
}

class _TerrainPainter extends CustomPainter {
  _TerrainPainter(this.state, this.camera) : super(repaint: state._repaint);

  final _TerrainLayerState state;
  final MapCamera camera;

  /// 灰度 → 黑色，透明度 = 不透明度 − 灰度（未预乘）：阴影瓦片处为 1 − 灰度，
  /// 图层里没画的地方仍然透明。
  static const _grayToShade = ColorFilter.matrix([
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    0, 0, 0, 0, 0, //
    -1, 0, 0, 1, 0,
  ]);

  // 不透明颜色：网格在折点处相互重叠，半透明会叠出深色小点。
  static const _minorColor = Color(0xFFB38B62);
  static const _majorColor = Color(0xFF8A5A2B);

  @override
  void paint(Canvas canvas, Size size) {
    final w = state.widget;
    if (!w.contours && !w.hillshade) return;
    final interval = w.contours ? contourSpec(camera.zoom)?.interval : null;
    if (interval == null && !w.hillshade) return;
    final draws = <(_Rendered, DemTileKey?)>[];
    for (final k in state._visibleKeys(camera)) {
      final r = state._bestFor(k, interval);
      if (r != null) {
        draws.add((r, null));
        continue;
      }
      // 还没算好：用父块（最多上两级）裁到这块的范围顶上。
      var p = k;
      for (var i = 0; i < 2 && p.z > DemService.minZoom; i++) {
        p = p.parent;
        final pr = state._bestFor(p, interval);
        if (pr != null) {
          draws.add((pr, k));
          break;
        }
      }
    }
    if (w.hillshade && draws.any((d) => d.$1.shade != null)) {
      // 阴影瓦片是不透明灰度图，先在一个图层里叠放（相邻瓦片边缘零点几像素的
      // 重叠不会像半透明黑色那样叠深），合成时再把灰度换回“黑色 + 透明度”。
      canvas.saveLayer(null, Paint()..colorFilter = _grayToShade);
      for (final (r, clipTo) in draws) {
        final shade = r.shade;
        if (shade == null) continue;
        _place(canvas, r, clipTo);
        if (r.warp != null) canvas.transform(r.shadeTransform());
        canvas
          ..drawImageRect(
            shade,
            // 阴影图四周多一圈邻块像素：插值在边界上连续；每边再多画半个像素
            // 与邻块重叠（图层里是不透明图，重叠不加深），盖住抗锯齿的接缝。
            const Rect.fromLTRB(0.5, 0.5, 257.5, 257.5),
            const Rect.fromLTRB(-0.5, -0.5, 256.5, 256.5),
            Paint()..filterQuality = FilterQuality.low,
          )
          ..restore();
      }
      canvas.restore();
    }
    if (interval == null) return;
    for (final (r, clipTo) in draws) {
      final scale = _place(canvas, r, clipTo);
      // 线宽按屏幕像素固定：每 1/4 个缩放级一档，档内随缩放略粗略细，换档时重建网格。
      final bucket = (math.log(scale) / math.ln2 * 4).round();
      final s = math.pow(2, bucket / 4).toDouble();
      final (minor, major) = r.meshes(bucket, 0.45 / s, 0.75 / s);
      if (minor != null) {
        canvas.drawVertices(minor, BlendMode.dst, Paint()..color = _minorColor);
      }
      if (major != null) {
        canvas.drawVertices(major, BlendMode.dst, Paint()..color = _majorColor);
      }
      canvas.restore();
    }
  }

  /// 保存画布并变换到瓦片 [r] 的像素坐标（用父块顶上时裁到 [clipTo]）。
  /// 返回瓦片像素到屏幕的缩放；调用方画完要 restore。
  double _place(Canvas canvas, _Rendered r, DemTileKey? clipTo) {
    final k = r.key;
    final scale = camera.getZoomScale(camera.zoom, k.z.toDouble());
    final origin = camera.pixelOrigin;
    canvas.save();
    if (clipTo != null) {
      // GCJ-02 底图下裁剪框按子块四角的平均位移挪过去。
      final cs = camera.getZoomScale(camera.zoom, clipTo.z.toDouble());
      var sx = 0.0, sy = 0.0;
      if (r.warp != null) {
        final w = TerrainLayer.gcjTileWarp(clipTo);
        sx = (w[0] + w[2] + w[4] + w[6]) / 4;
        sy = (w[1] + w[3] + w[5] + w[7]) / 4;
      }
      canvas.clipRect(
        Rect.fromLTWH(
          (clipTo.x * 256 + sx) * cs - origin.dx,
          (clipTo.y * 256 + sy) * cs - origin.dy,
          256 * cs,
          256 * cs,
        ),
      );
    }
    canvas
      ..translate(k.x * 256 * scale - origin.dx, k.y * 256 * scale - origin.dy)
      ..scale(scale);
    return scale;
  }

  @override
  bool shouldRepaint(covariant _TerrainPainter old) =>
      old.camera != camera || !identical(old.state, state);
}

/// 按设置（或调用方指定）决定是否叠加地形图层；都关时返回 null。
Widget? terrainLayerFor(
  WidgetRef ref,
  Basemap basemap, {
  bool? contours,
  bool? hillshade,
}) {
  final s = ref.watch(settingsProvider);
  final c = contours ?? s.terrainContours;
  final h = hillshade ?? s.terrainHillshade;
  if (!c && !h) return null;
  return TerrainLayer(
    dem: ref.watch(demServiceProvider),
    basemap: basemap,
    contours: c,
    hillshade: h,
  );
}

/// 地图左下角的等高距标注：看等高线必须知道间距；缩放太小不画等高线时不显示。
class ContourIntervalBadge extends StatelessWidget {
  const ContourIntervalBadge({
    super.key,
    this.padding = const EdgeInsets.all(8),
    this.alignment = Alignment.bottomLeft,
  });

  final EdgeInsets padding;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final spec = contourSpec(MapCamera.of(context).zoom);
    if (spec == null) return const SizedBox.shrink();
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '${S.terrainIntervalPrefix} ${spec.interval.round()} m',
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF5B3A1A),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
