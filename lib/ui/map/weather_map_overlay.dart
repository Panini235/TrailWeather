import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/weather/satellite_frames.dart';
import '../../data/weather/typhoon.dart';
import '../../data/weather/weather_field.dart';
import '../strings.dart';
import '../tokens.dart';
import '../widgets/common.dart';
import 'basemap.dart';
import 'typhoon_layer.dart';

/// 天气图模式：降水与云量是模式预报格点场；卫星云图是观测（实况）；
/// 台风是日本气象厅的实况与路径预报。
enum WxMapMode { precip, cloud, satellite, typhoon }

/// 地图页“天气图”的状态（D-035）。
///
/// 请求纪律：拖动中不请求；停下 500 ms 后，视野超出已取范围才重新请求；
/// 缩放太小（全国以上）不请求格点场。播放只在用户点播放时进行，播完自动停。
///
/// 时间轴（[timeline]）是连续的帧位置：播放和拖动时图层停在两帧之间，按相邻两帧
/// 线性过渡显示，动画才连贯；停下后回到最近的整帧（整点预报 / 真实观测时次），
/// 静止画面和时间标签都不是插出来的。播放只驱动 [timeline]，不重建地图图层。
class WeatherMapController extends ChangeNotifier {
  WeatherMapController({
    required this.fieldService,
    required this.satelliteService,
    required this.typhoonService,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final WeatherFieldService fieldService;
  final SatelliteFrameService satelliteService;
  final TyphoonService typhoonService;

  /// 地图页设置：把视野移到这些点（台风“定位”）。
  void Function(List<LatLng> points)? onFitRequest;
  final DateTime Function() _now;

  /// 格点场的最小缩放级别：再小就是全国以上，80 个格点太稀，不如不画。
  static const minFieldZoom = 5.0;

  /// 播放速度（帧 / 秒）：预报每秒 2.5 小时（48 小时约 19 秒）；
  /// 卫星每秒 3 张（10 分钟一张，2 小时约 4 秒）。
  static const fieldRate = 2.5;
  static const satRate = 3.0;

  /// 卫星时次列表的复用时长（约 10 分钟出一张新图）。
  static const satTtl = Duration(minutes: 10);

  bool active = false;
  WxMapMode mode = WxMapMode.precip;
  FieldVar cloudVar = FieldVar.cloud;

  FieldGrid? grid;
  bool loading = false;
  Object? error;
  bool tooWide = false;

  List<DateTime> satFrames = const [];
  bool satLoading = false;
  Object? satError;
  DateTime? _satFetchedAt;

  List<Typhoon>? typhoons;
  bool tyLoading = false;
  Object? tyError;
  DateTime? _tyFetchedAt;

  /// 当前模式的时间轴位置（帧下标，可为小数）。
  late final AnimationController timeline = AnimationController.unbounded(
    vsync: const _Vsync(),
  );

  /// 不在当前模式时保存各自的位置（降水与云量共用格点场的时间轴）。
  double _fieldPos = 0;
  double _satPos = 0;
  bool _playing = false;
  int _playGen = 0;

  Timer? _debounce;
  FieldBounds? _view;
  double _zoom = 12;
  double _aspect = 0.5;
  CancelToken? _cancel;
  bool _disposed = false;

  bool get playing => _playing;
  bool get _isField => mode == WxMapMode.precip || mode == WxMapMode.cloud;
  FieldVar get fieldVar =>
      mode == WxMapMode.precip ? FieldVar.precip : cloudVar;

  int get frameCount => switch (mode) {
    WxMapMode.satellite => satFrames.length,
    WxMapMode.typhoon => 0,
    _ => grid?.timesUtc.length ?? 0,
  };

  /// 最近的整帧（时间标签、静止画面用）。
  int get frameIndex => _round(timeline.value, frameCount);

  /// 格点场最近的整点时次下标。
  int get timeIndex =>
      _round(_isField ? timeline.value : _fieldPos, grid?.timesUtc.length ?? 0);

  /// 卫星云图最近的观测时次下标。
  int get satIndex => _round(
    mode == WxMapMode.satellite ? timeline.value : _satPos,
    satFrames.length,
  );

  static int _round(double pos, int n) =>
      n == 0 ? 0 : pos.round().clamp(0, n - 1);

  void toggle() {
    active = !active;
    if (!active) {
      _stopPlay();
      _cancel?.cancel();
    } else {
      _ensure();
    }
    _notify();
  }

  void setMode(WxMapMode m) {
    if (m == mode) return;
    _stopPlay();
    if (_isField) {
      _fieldPos = timeline.value;
    } else if (mode == WxMapMode.satellite) {
      _satPos = timeline.value;
    }
    mode = m;
    timeline.value = _isField
        ? _fieldPos
        : mode == WxMapMode.satellite
        ? _satPos
        : 0;
    _ensure();
    _notify();
  }

  void setCloudVar(FieldVar v) {
    cloudVar = v;
    _notify();
  }

  /// 地图停下后调用（业务坐标视野、缩放、视野宽高比）。
  void onView(FieldBounds view, double zoom, double aspect) {
    _view = view;
    _zoom = zoom;
    _aspect = aspect;
    if (!active) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _ensure);
  }

  /// 跳到第 [i] 帧。
  void setFrame(int i) => scrub(i.toDouble());

  /// 拖动时间轴：可停在两帧之间（松手后调用 [settle]）。
  void scrub(double pos) {
    final wasPlaying = _playing;
    _stopPlay();
    timeline.value = pos.clamp(0.0, math.max(0, frameCount - 1).toDouble());
    if (wasPlaying) _notify();
  }

  /// 回到最近的整帧（短动画）。
  void settle({Duration duration = const Duration(milliseconds: 160)}) {
    final target = timeline.value.roundToDouble().clamp(
      0.0,
      math.max(0, frameCount - 1).toDouble(),
    );
    if (target == timeline.value) return;
    if (duration == Duration.zero) {
      timeline.value = target;
    } else {
      timeline.animateTo(target, duration: duration, curve: Curves.easeOut);
    }
  }

  void togglePlay() {
    if (_playing) {
      _stopPlay();
      settle();
      _notify();
      return;
    }
    final n = frameCount;
    if (n < 2) return;
    final end = (n - 1).toDouble();
    if (timeline.value >= end - 0.01) timeline.value = 0;
    final rate = mode == WxMapMode.satellite ? satRate : fieldRate;
    final gen = ++_playGen;
    _playing = true;
    timeline
        .animateTo(
          end,
          duration: Duration(
            microseconds: ((end - timeline.value) / rate * 1e6).round(),
          ),
          curve: Curves.linear,
        )
        .whenCompleteOrCancel(() {
          // 被新的播放、拖动或暂停打断时不改状态（那一方已经处理）。
          if (gen != _playGen) return;
          _playing = false;
          _notify();
        });
    _notify();
  }

  void _stopPlay() {
    if (!_playing) return;
    _playing = false;
    _playGen++;
    timeline.stop();
  }

  Future<void> _ensure() async {
    if (!active) return;
    switch (mode) {
      case WxMapMode.satellite:
        await _ensureSatellite();
      case WxMapMode.typhoon:
        await _ensureTyphoons();
      case WxMapMode.precip || WxMapMode.cloud:
        await _ensureField();
    }
  }

  /// 台风数据 30 分钟内复用（JMA 约 3–6 小时更新一次）。
  Future<void> _ensureTyphoons() async {
    if (tyLoading) return;
    final at = _tyFetchedAt;
    if (typhoons != null &&
        at != null &&
        _now().difference(at) < const Duration(minutes: 30)) {
      return;
    }
    tyLoading = true;
    tyError = null;
    _notify();
    try {
      typhoons = await typhoonService.active();
      _tyFetchedAt = _now();
      final first = typhoons!.firstOrNull;
      if (first != null) onFitRequest?.call(first.allPoints);
    } catch (e) {
      tyError = e;
    } finally {
      tyLoading = false;
      _notify();
    }
  }

  void fitTyphoon(Typhoon t) => onFitRequest?.call(t.allPoints);

  Future<void> _ensureField() async {
    final view = _view;
    if (view == null) return;
    tooWide = _zoom < minFieldZoom;
    if (tooWide) {
      _notify();
      return;
    }
    final hit = fieldService.cachedFor(view);
    if (hit != null) {
      _setGrid(hit);
      return;
    }
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    loading = true;
    error = null;
    _notify();
    try {
      final g = await fieldService.fetch(
        view,
        aspect: _aspect,
        cancelToken: token,
      );
      if (token.isCancelled) return;
      _setGrid(g);
    } catch (e) {
      if (token.isCancelled) return;
      error = e;
    } finally {
      if (identical(_cancel, token)) loading = false;
      _notify();
    }
  }

  void _setGrid(FieldGrid g) {
    if (identical(g, grid)) return;
    final old = grid;
    final pos = _isField ? timeline.value : _fieldPos;
    final prevTime = old == null || old.timesUtc.isEmpty
        ? null
        : old.timesUtc[pos.floor().clamp(0, old.timesUtc.length - 1)];
    grid = g;
    // 换了格点场时保持同一预报时刻；第一次打开从当前小时开始。
    final keep = prevTime == null ? null : g.timeIndexOf(prevTime);
    final next = keep != null
        ? keep + (pos - pos.floorToDouble())
        : (g.timeIndexOf(_now()) ?? 0).toDouble();
    if (!_isField) {
      _fieldPos = next;
    } else if (next != timeline.value ||
        old?.timesUtc.length != g.timesUtc.length) {
      _stopPlay();
      timeline.value = next;
    }
    _notify();
  }

  Future<void> _ensureSatellite() async {
    if (satLoading) return;
    final at = _satFetchedAt;
    if (satFrames.isNotEmpty && at != null && _now().difference(at) < satTtl) {
      return;
    }
    satLoading = true;
    satError = null;
    _notify();
    try {
      final frames = await satelliteService.recentFrames();
      _satFetchedAt = _now();
      if (frames.isEmpty) {
        satError = const FormatException('暂无可用的卫星云图');
      }
      final changed = !listEquals(frames, satFrames);
      satFrames = frames;
      // 新取到的时次从最新一张开始。
      if (changed) {
        final last = math.max(0, frames.length - 1).toDouble();
        if (mode == WxMapMode.satellite) {
          _stopPlay();
          timeline.value = last;
        } else {
          _satPos = last;
        }
      }
    } catch (e) {
      satError = e;
    } finally {
      satLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPlay();
    timeline.dispose();
    _debounce?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}

/// 控制器不是 Widget：直接建 [Ticker]（地图页在后台时播放也会自动播完停下）。
class _Vsync implements TickerProvider {
  const _Vsync();

  @override
  Ticker createTicker(TickerCallback onTick) =>
      Ticker(onTick, debugLabel: 'weather-map');
}

/// 卫星第 [i] 帧在时间轴位置 [pos] 的不透明度。帧按时间倒序叠放（新的在下）：
/// 位于 i0 与 i0+1 之间时，下层 i0+1 不透明，上层 i0 的不透明度为 1−f，
/// 叠出来就是两帧的线性过渡；正好在整帧上时只画那一帧。
double frameWeight(int i, double pos) {
  final i0 = pos.floor();
  final f = pos - i0;
  if (i == i0) return 1 - f;
  if (i == i0 + 1 && f > 0) return 1;
  return 0;
}

class _FrameWeight extends Animatable<double> {
  const _FrameWeight(this.i);

  final int i;

  @override
  double transform(double t) => frameWeight(i, t);
}

/// 地图图层：格点场或卫星瓦片。放在底图之上、线路之下。
List<Widget> weatherMapLayers(WeatherMapController c, Basemap basemap) {
  if (!c.active) return const [];
  if (c.mode == WxMapMode.typhoon) {
    return typhoonLayers(c.typhoons ?? const [], basemap);
  }
  if (c.mode == WxMapMode.satellite) {
    final frames = c.satFrames;
    if (frames.isEmpty) return const [];
    // 所有时次的瓦片一起挂上（不透明度为 0 的不绘制，但会先下载好），
    // 播放和拖动时只调不透明度，不再等网络。新的一帧排在最前，最先请求。
    return [
      RepaintBoundary(
        child: Opacity(
          opacity: 0.62,
          child: Stack(
            children: [
              for (var i = frames.length - 1; i >= 0; i--)
                FadeTransition(
                  key: ValueKey('sat-${frames[i].toIso8601String()}'),
                  opacity: c.timeline.drive(_FrameWeight(i)),
                  child: TileLayer(
                    urlTemplate: SatelliteFrameService.tileTemplate(frames[i]),
                    maxNativeZoom: SatelliteFrameService.maxNativeZoom,
                    userAgentPackageName: 'app.shanqing.hiking',
                    tileDisplay: const TileDisplay.instantaneous(),
                    panBuffer: 0,
                    keepBuffer: 1,
                  ),
                ),
            ],
          ),
        ),
      ),
    ];
  }
  final g = c.grid;
  if (g == null || c.tooWide) return const [];
  return [
    IgnorePointer(
      child: WeatherFieldLayer(
        grid: g,
        variable: c.fieldVar,
        time: c.timeline,
        basemap: basemap,
      ),
    ),
  ];
}

/// 格点场渲染：格点按 8 倍细分做三次（Catmull-Rom）平滑（只为显示；邻点缺失时退回
/// 双线性），三角网逐顶点着色。
///
/// 三角网顶点在参考缩放级别的局部像素坐标里只算一次，平移缩放地图时只改画布变换；
/// 时间轴变化只重算顶点颜色（两整点之间线性过渡，见 [FieldGrid.blendedAt]），
/// 且只重绘这一层，不重建地图。
class WeatherFieldLayer extends StatefulWidget {
  const WeatherFieldLayer({
    super.key,
    required this.grid,
    required this.variable,
    required this.time,
    required this.basemap,
  });

  final FieldGrid grid;
  final FieldVar variable;

  /// 时间轴位置（时次下标，可为小数）。
  final ValueListenable<double> time;
  final Basemap basemap;

  @override
  State<WeatherFieldLayer> createState() => _WeatherFieldLayerState();
}

class _WeatherFieldLayerState extends State<WeatherFieldLayer> {
  _FieldMesh? _mesh;

  @override
  void dispose() {
    _mesh?.dispose();
    super.dispose();
  }

  _FieldMesh _meshFor(Crs crs) {
    final m = _mesh;
    if (m != null &&
        identical(m.grid, widget.grid) &&
        m.gcj == widget.basemap.isGcj) {
      return m;
    }
    m?.dispose();
    return _mesh = _FieldMesh(widget.grid, widget.basemap, crs);
  }

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    return MobileLayerTransformer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _FieldPainter(
            camera: camera,
            mesh: _meshFor(camera.crs),
            variable: widget.variable,
            time: widget.time,
          ),
        ),
      ),
    );
  }
}

typedef FieldColorOf = Color Function(double v);

/// 降水（mm/h）与云量（%）的配色。低于下限透明，避免整屏蒙一层。
FieldColorOf fieldColor(FieldVar v) =>
    v == FieldVar.precip ? precipColor : cloudColor;

// 低端拉长过渡（0.05 → 0.6 mm 渐显），雨区边缘不随细分网格出现台阶。
const precipStops = <(double, Color)>[
  (0.05, Color(0x0078BEFA)),
  (0.6, Color(0x7378BEFA)),
  (1, Color(0x9A3C8CE6)),
  (3, Color(0xB01E5AC8)),
  (8, Color(0xBF783CBE)),
  (16, Color(0xCCC82878)),
  (30, Color(0xD9E61E28)),
];

Color precipColor(double mm) => _ramp(precipStops, mm);

const cloudStops = <(double, Color)>[
  (10, Color(0x005A6473)),
  (40, Color(0x405A6473)),
  (70, Color(0x735A6473)),
  (100, Color(0x995A6473)),
];

Color cloudColor(double pct) => _ramp(cloudStops, pct);

Color _ramp(List<(double, Color)> stops, double x) {
  // 低于下限用首色的透明版本：与相邻顶点插值时不会带出灰黑色边。
  if (x.isNaN || x < stops.first.$1) return stops.first.$2.withValues(alpha: 0);
  for (var i = 1; i < stops.length; i++) {
    final (x1, c1) = stops[i];
    if (x <= x1) {
      final (x0, c0) = stops[i - 1];
      return Color.lerp(c0, c1, (x - x0) / (x1 - x0))!;
    }
  }
  return stops.last.$2;
}

/// 配色查找表（逐顶点着色时不再逐个插值颜色）。
class _ColorLut {
  _ColorLut(List<(double, Color)> stops)
    : lo = stops.first.$1,
      hi = stops.last.$1 {
    for (var i = 0; i < n; i++) {
      table[i] = _ramp(stops, lo + (hi - lo) * i / (n - 1)).toARGB32();
    }
  }

  static const n = 2048;
  final double lo, hi;
  final table = Int32List(n);

  static final precip = _ColorLut(precipStops);
  static final cloud = _ColorLut(cloudStops);

  /// 缺失（NaN）与低于下限：首色的透明版本。
  int argb(double x) {
    if (!(x >= lo)) return table[0];
    if (x >= hi) return table[n - 1];
    return table[((x - lo) / (hi - lo) * (n - 1)).round()];
  }
}

/// 一个格点场的三角网：位置、索引与外圈渐隐只算一次；颜色按时间位置缓存最近一份。
class _FieldMesh {
  _FieldMesh(this.grid, Basemap basemap, Crs crs) : gcj = basemap.isGcj {
    final g = grid;
    fc = (g.cols - 1) * k + 1;
    fr = (g.rows - 1) * k + 1;
    LatLng display(int r, int c) =>
        basemap.toDisplay(LatLng(g.lats[r], g.lons[c]));
    anchor = display(0, 0);
    final a0 = crs.latLngToOffset(anchor, refZoom);
    // 粗格点投影到参考级别的局部像素坐标（double 里减去锚点，再存 float，避免大数丢精度），
    // 细分点在其间双线性插值（墨卡托下行列等距，误差可忽略）。
    final coarse = [
      for (var r = 0; r < g.rows; r++)
        for (var c = 0; c < g.cols; c++)
          crs.latLngToOffset(display(r, c), refZoom) - a0,
    ];
    positions = Float32List(fc * fr * 2);
    edge = Float32List(fc * fr);
    for (var r = 0; r < fr; r++) {
      final r0 = math.min(r ~/ k, g.rows - 2);
      final ty = (r - r0 * k) / k;
      for (var c = 0; c < fc; c++) {
        final c0 = math.min(c ~/ k, g.cols - 2);
        final tx = (c - c0 * k) / k;
        final a = coarse[r0 * g.cols + c0], b = coarse[r0 * g.cols + c0 + 1];
        final d = coarse[(r0 + 1) * g.cols + c0];
        final e = coarse[(r0 + 1) * g.cols + c0 + 1];
        final i = r * fc + c;
        positions[i * 2] =
            (a.dx * (1 - tx) + b.dx * tx) * (1 - ty) +
            (d.dx * (1 - tx) + e.dx * tx) * ty;
        positions[i * 2 + 1] =
            (a.dy * (1 - tx) + b.dy * tx) * (1 - ty) +
            (d.dy * (1 - tx) + e.dy * tx) * ty;
        // 外圈半个格距内渐隐：换新格点场前视野超出范围时，边界不是一条硬线。
        final ring = math.min(math.min(r, c), math.min(fr - 1 - r, fc - 1 - c));
        edge[i] = (ring / (k / 2)).clamp(0.0, 1.0);
      }
    }
    indices = Uint16List((fc - 1) * (fr - 1) * 6);
    var n = 0;
    for (var r = 0; r < fr - 1; r++) {
      for (var c = 0; c < fc - 1; c++) {
        final i = r * fc + c;
        indices[n++] = i;
        indices[n++] = i + 1;
        indices[n++] = i + fc;
        indices[n++] = i + 1;
        indices[n++] = i + fc + 1;
        indices[n++] = i + fc;
      }
    }
  }

  static const k = 8;
  static const refZoom = 10.0;

  /// Catmull-Rom 四点权重（细分点在 [i0, i0+1] 之间的位置 t）。
  static List<double> _cubic(double t) {
    final t2 = t * t, t3 = t2 * t;
    return [
      (-t3 + 2 * t2 - t) / 2,
      (3 * t3 - 5 * t2 + 2) / 2,
      (-3 * t3 + 4 * t2 + t) / 2,
      (t3 - t2) / 2,
    ];
  }

  /// 一个方向上每个细分点取哪 4 个粗格点（越界取边上的点）、各自的权重，
  /// 以及双线性回退用的左格点与位置。
  static (Int32List, Float32List, Int32List, Float32List) _taps(int n) {
    final fn = (n - 1) * k + 1;
    final idx = Int32List(fn * 4), w = Float32List(fn * 4);
    final lo = Int32List(fn), t = Float32List(fn);
    for (var f = 0; f < fn; f++) {
      final i0 = math.min(f ~/ k, n - 2);
      final tt = (f - i0 * k) / k;
      lo[f] = i0;
      t[f] = tt;
      final ws = _cubic(tt);
      for (var j = 0; j < 4; j++) {
        idx[f * 4 + j] = (i0 - 1 + j).clamp(0, n - 1);
        w[f * 4 + j] = ws[j];
      }
    }
    return (idx, w, lo, t);
  }

  final FieldGrid grid;
  final bool gcj;
  late final int fc, fr;
  late final LatLng anchor;
  late final Float32List positions;
  late final Float32List edge;
  late final Uint16List indices;
  late final (Int32List, Float32List, Int32List, Float32List) _rowTaps = _taps(
    grid.rows,
  );
  late final (Int32List, Float32List, Int32List, Float32List) _colTaps = _taps(
    grid.cols,
  );

  ui.Vertices? _vertices;
  (FieldVar, double)? _key;

  ui.Vertices verticesAt(FieldVar v, double pos) {
    final cached = _vertices;
    if (cached != null && _key == (v, pos)) return cached;
    final g = grid;
    final src = g.blendedAt(v, pos);
    final lut = v == FieldVar.precip ? _ColorLut.precip : _ColorLut.cloud;
    final (rIdx, rW, rLo, rT) = _rowTaps;
    final (cIdx, cW, cLo, cT) = _colTaps;
    // 先沿列方向插出每个粗格行上的细分点，再沿行方向插（可分离的三次插值）。
    final h = Float32List(g.rows * fc);
    for (var row = 0; row < g.rows; row++) {
      final base = row * g.cols;
      for (var c = 0; c < fc; c++) {
        var x = 0.0;
        for (var j = 0; j < 4; j++) {
          x += cW[c * 4 + j] * src[base + cIdx[c * 4 + j]];
        }
        h[row * fc + c] = x;
      }
    }
    final colors = Int32List(fc * fr);
    for (var r = 0; r < fr; r++) {
      for (var c = 0; c < fc; c++) {
        var x = 0.0;
        for (var j = 0; j < 4; j++) {
          x += rW[r * 4 + j] * h[rIdx[r * 4 + j] * fc + c];
        }
        if (x.isNaN) {
          // 邻点缺失：退回只用四个角点的双线性（角点本身缺失仍为 NaN → 透明）。
          final r0 = rLo[r], c0 = cLo[c], ty = rT[r], tx = cT[c];
          final row0 = r0 * g.cols, row1 = row0 + g.cols;
          final top = src[row0 + c0] * (1 - tx) + src[row0 + c0 + 1] * tx;
          final bottom = src[row1 + c0] * (1 - tx) + src[row1 + c0 + 1] * tx;
          x = top * (1 - ty) + bottom * ty;
        }
        final argb = lut.argb(x);
        final i = r * fc + c;
        final alpha = (((argb >> 24) & 0xFF) * edge[i]).round();
        colors[i] = (alpha << 24) | (argb & 0x00FFFFFF);
      }
    }
    cached?.dispose();
    _key = (v, pos);
    return _vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
  }

  void dispose() {
    _vertices?.dispose();
    _vertices = null;
  }
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({
    required this.camera,
    required this.mesh,
    required this.variable,
    required this.time,
  }) : super(repaint: time);

  final MapCamera camera;
  final _FieldMesh mesh;
  final FieldVar variable;
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final origin = camera.getOffsetFromOrigin(mesh.anchor);
    final scale = camera.getZoomScale(camera.zoom, _FieldMesh.refZoom);
    canvas
      ..save()
      ..translate(origin.dx, origin.dy)
      ..scale(scale);
    canvas.drawVertices(
      mesh.verticesAt(variable, time.value),
      BlendMode.dst,
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) =>
      old.camera != camera ||
      !identical(old.mesh, mesh) ||
      old.variable != variable ||
      !identical(old.time, time);
}

/// 地图右侧的“天气图”按钮。
class WeatherMapButton extends StatelessWidget {
  const WeatherMapButton({
    super.key,
    required this.controller,
    required this.onPressed,
  });

  final WeatherMapController controller;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => FloatingActionButton.small(
      heroTag: 'wxmap',
      tooltip: S.wxMapButton,
      backgroundColor: controller.active
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
      onPressed: onPressed,
      child: Icon(controller.active ? Icons.cloud : Icons.cloud_outlined),
    ),
  );
}

/// 底部天气图面板：模式、时间轴与播放、图例。文字只留时间与一行来源。
class WeatherMapPanel extends StatelessWidget {
  const WeatherMapPanel({super.key, required this.controller});

  final WeatherMapController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => _panel(context),
  );

  Widget _panel(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final small = TextStyle(fontSize: 11, color: muted);
    final sat = c.mode == WxMapMode.satellite;
    final n = c.frameCount;
    final busy = switch (c.mode) {
      WxMapMode.satellite => c.satLoading,
      WxMapMode.typhoon => c.tyLoading,
      _ => c.loading,
    };
    final err = sat ? c.satError : c.error;

    Widget chip(WxMapMode m, String label, IconData icon) => ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: c.mode == m,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => c.setMode(m),
    );

    String timeLabel() {
      if (n == 0) return '';
      // 标签只显示最近的整帧（真实的预报整点 / 观测时次），不显示过渡中的时刻。
      final t = (sat ? c.satFrames[c.satIndex] : c.grid!.timesUtc[c.timeIndex])
          .toLocal();
      final today = DateTime.now();
      final d = DateTime(
        t.year,
        t.month,
        t.day,
      ).difference(DateTime(today.year, today.month, today.day)).inDays;
      final day = switch (d) {
        0 => '今天',
        1 => '明天',
        2 => '后天',
        -1 => '昨天',
        _ => '${t.month}/${t.day}',
      };
      final hm =
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      return sat ? '${S.wxMapSatelliteTime} $hm' : '$day $hm';
    }

    return Material(
      color: theme.colorScheme.surface.withValues(alpha: 0.96),
      elevation: 3,
      borderRadius: BorderRadius.circular(Radii.lg),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.xs,
          Space.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    children: [
                      chip(
                        WxMapMode.precip,
                        S.wxMapPrecip,
                        Icons.water_drop_outlined,
                      ),
                      chip(WxMapMode.cloud, S.wxMapCloud, Icons.cloud_outlined),
                      chip(
                        WxMapMode.satellite,
                        S.wxMapSatellite,
                        Icons.satellite_alt_outlined,
                      ),
                      chip(WxMapMode.typhoon, S.wxMapTyphoon, Icons.cyclone),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: S.close,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: c.toggle,
                ),
              ],
            ),
            if (c.mode == WxMapMode.cloud)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SegmentedButton<FieldVar>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: FieldVar.cloud,
                      label: Text(S.wxMapCloudAll),
                    ),
                    ButtonSegment(
                      value: FieldVar.cloudLow,
                      label: Text(S.wxMapCloudLow),
                    ),
                    ButtonSegment(
                      value: FieldVar.cloudMid,
                      label: Text(S.wxMapCloudMid),
                    ),
                    ButtonSegment(
                      value: FieldVar.cloudHigh,
                      label: Text(S.wxMapCloudHigh),
                    ),
                  ],
                  selected: {c.cloudVar},
                  onSelectionChanged: (v) => c.setCloudVar(v.first),
                ),
              ),
            if (c.mode == WxMapMode.typhoon)
              _TyphoonBody(controller: c, small: small)
            else if (!sat && c.tooWide)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(S.wxMapZoomIn, style: small),
              )
            else if (err != null && n == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '${S.wxMapFailed}（${fetchErrorText(err)}）',
                  style: small,
                ),
              )
            else if (n == 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text(S.wxMapLoading, style: small),
                  ],
                ),
              )
            else ...[
              // 只有这一行跟着时间轴每帧重建；整块面板只在状态变化时重建。
              AnimatedBuilder(
                animation: c.timeline,
                builder: (context, _) => Row(
                  children: [
                    IconButton(
                      tooltip: c.playing ? S.wxMapPause : S.wxMapPlay,
                      icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
                      onPressed: n > 1 ? c.togglePlay : null,
                    ),
                    Expanded(
                      child: Slider(
                        value: c.timeline.value.clamp(0, (n - 1).toDouble()),
                        min: 0,
                        max: math.max(1, n - 1).toDouble(),
                        onChanged: n > 1 ? c.scrub : null,
                        onChangeEnd: n > 1 ? (_) => c.settle() : null,
                      ),
                    ),
                    SizedBox(
                      width: 88,
                      child: Text(
                        timeLabel(),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [ui.FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: _Legend(mode: c.mode, muted: muted),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                if (busy && n > 0) ...[
                  const SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    c.mode == WxMapMode.typhoon
                        ? S.wxMapTyphoonNote
                        : sat
                        ? S.wxMapSatelliteNote
                        : '${S.wxMapForecastNote}'
                              '${c.grid == null ? '' : ' · 格点约 ${c.grid!.spacingKm.round()} km'}',
                    style: small,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Tooltip(
                  message: S.wxMapInfo,
                  triggerMode: TooltipTriggerMode.tap,
                  showDuration: const Duration(seconds: 8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.info_outline, size: 16, color: muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 台风模式：每个活跃台风一行（名称、强度、气压、风速、移向），点“定位”移到台风。
class _TyphoonBody extends StatelessWidget {
  const _TyphoonBody({required this.controller, required this.small});

  final WeatherMapController controller;
  final TextStyle small;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final list = c.typhoons;
    if (list == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: c.tyError != null
            ? Text(
                '${S.wxMapFailed}（${fetchErrorText(c.tyError!)}）',
                style: small,
              )
            : Text(S.wxMapLoading, style: small),
      );
    }
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(S.wxMapNoTyphoon, style: small),
      );
    }
    String fmtTime(DateTime utc) {
      final t = utc.toLocal();
      return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final t in list)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(Icons.cyclone, size: 22, color: Semantic.danger),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${t.categoryLabel} ${t.title}'
                        '${t.intensityLabel == null ? '' : ' · ${t.intensityLabel}'}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        [
                          if (t.pressureHpa != null)
                            '${t.pressureHpa!.round()} hPa',
                          if (t.maxWindMs != null)
                            '最大风速 ${t.maxWindMs!.round()} m/s',
                          if (t.course != null)
                            '向${t.course}${t.speedKmh == null ? '' : ' ${t.speedKmh!.round()} km/h'}',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 12),
                      ),
                      Text('发布 ${fmtTime(t.issueUtc)}', style: small),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => c.fitTyphoon(t),
                  child: const Text(S.wxMapLocate),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.mode, required this.muted});

  final WxMapMode mode;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontSize: 10, color: muted);
    if (mode == WxMapMode.satellite) {
      return Row(
        children: [
          Container(
            width: 120,
            height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF3A3A3A),
                  Color(0xFFDADADA),
                  Color(0xFF2B6CD9),
                  Color(0xFF2EC24A),
                  Color(0xFFE53935),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('暗 = 地面或低云　亮/彩 = 云顶高、对流强', style: style)),
        ],
      );
    }
    final stops = mode == WxMapMode.precip ? precipStops : cloudStops;
    final labels = mode == WxMapMode.precip
        ? const ['0.1', '1', '3', '8', '16', '30']
        : const ['10', '40', '70', '100'];
    final unit = mode == WxMapMode.precip
        ? S.wxMapPrecipUnit
        : S.wxMapCloudUnit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            gradient: LinearGradient(
              colors: [
                for (final (_, c) in stops)
                  c.withValues(alpha: math.max(c.a, 0.25)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            for (final l in labels) ...[
              Text(l, style: style),
              if (l != labels.last) const Spacer(),
            ],
            const SizedBox(width: 8),
            Text(unit, style: style),
          ],
        ),
      ],
    );
  }
}
