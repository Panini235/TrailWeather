import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/weather/satellite_frames.dart';
import '../../data/weather/weather_field.dart';
import '../motion.dart';
import '../strings.dart';
import '../tokens.dart';
import '../widgets/common.dart';
import 'basemap.dart';

/// 天气图模式：降水与云量是模式预报格点场；卫星云图是观测（实况）。
enum WxMapMode { precip, cloud, satellite }

/// 地图页“天气图”的状态（D-035）。
///
/// 请求纪律：拖动中不请求；停下 500 ms 后，视野超出已取范围才重新请求；
/// 缩放太小（全国以上）不请求格点场。播放只在用户点播放时进行，播完自动停。
class WeatherMapController extends ChangeNotifier {
  WeatherMapController({
    required this.fieldService,
    required this.satelliteService,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final WeatherFieldService fieldService;
  final SatelliteFrameService satelliteService;
  final DateTime Function() _now;

  /// 格点场的最小缩放级别：再小就是全国以上，80 个格点太稀，不如不画。
  static const minFieldZoom = 5.0;

  bool active = false;
  WxMapMode mode = WxMapMode.precip;
  FieldVar cloudVar = FieldVar.cloud;

  FieldGrid? grid;
  bool loading = false;
  Object? error;
  bool tooWide = false;
  int timeIndex = 0;

  List<DateTime> satFrames = const [];
  int satIndex = 0;
  bool satLoading = false;
  Object? satError;

  Timer? _play;
  Timer? _debounce;
  FieldBounds? _view;
  double _zoom = 12;
  double _aspect = 0.5;
  CancelToken? _cancel;
  bool _disposed = false;

  bool get playing => _play != null;
  FieldVar get fieldVar =>
      mode == WxMapMode.precip ? FieldVar.precip : cloudVar;

  int get frameCount => mode == WxMapMode.satellite
      ? satFrames.length
      : (grid?.timesUtc.length ?? 0);
  int get frameIndex => mode == WxMapMode.satellite ? satIndex : timeIndex;

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
    mode = m;
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

  void setFrame(int i) {
    if (mode == WxMapMode.satellite) {
      satIndex = i.clamp(0, math.max(0, satFrames.length - 1));
    } else {
      timeIndex = i.clamp(0, math.max(0, (grid?.timesUtc.length ?? 1) - 1));
    }
    _notify();
  }

  void togglePlay() {
    if (playing) {
      _stopPlay();
      _notify();
      return;
    }
    final n = frameCount;
    if (n < 2) return;
    if (frameIndex >= n - 1) setFrame(0);
    _play = Timer.periodic(
      Duration(milliseconds: mode == WxMapMode.satellite ? 900 : 650),
      (_) {
        if (frameIndex >= frameCount - 1) {
          _stopPlay();
        } else {
          setFrame(frameIndex + 1);
          return;
        }
        _notify();
      },
    );
    _notify();
  }

  void _stopPlay() {
    _play?.cancel();
    _play = null;
  }

  Future<void> _ensure() async {
    if (!active) return;
    if (mode == WxMapMode.satellite) {
      await _ensureSatellite();
    } else {
      await _ensureField();
    }
  }

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
    final prevTime = grid == null || grid!.timesUtc.isEmpty
        ? null
        : grid!.timesUtc[timeIndex.clamp(0, grid!.timesUtc.length - 1)];
    grid = g;
    // 换了格点场时保持同一预报时刻；第一次打开从当前小时开始。
    timeIndex =
        (prevTime == null ? null : g.timeIndexOf(prevTime)) ??
        g.timeIndexOf(_now()) ??
        0;
    _notify();
  }

  Future<void> _ensureSatellite() async {
    if (satFrames.isNotEmpty || satLoading) return;
    satLoading = true;
    satError = null;
    _notify();
    try {
      satFrames = await satelliteService.recentFrames();
      satIndex = math.max(0, satFrames.length - 1);
      if (satFrames.isEmpty) satError = const FormatException('暂无可用的卫星云图');
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
    _debounce?.cancel();
    _cancel?.cancel();
    super.dispose();
  }
}

/// 地图图层：格点场或卫星瓦片。放在底图之上、线路之下。
List<Widget> weatherMapLayers(WeatherMapController c, Basemap basemap) {
  if (!c.active) return const [];
  if (c.mode == WxMapMode.satellite) {
    final frames = c.satFrames;
    if (frames.isEmpty) return const [];
    final t = frames[c.satIndex.clamp(0, frames.length - 1)];
    return [
      Opacity(
        opacity: 0.62,
        child: TileLayer(
          key: ValueKey('sat-${t.toIso8601String()}'),
          urlTemplate: SatelliteFrameService.tileTemplate(t),
          maxNativeZoom: SatelliteFrameService.maxNativeZoom,
          userAgentPackageName: 'app.shanqing.hiking',
          tileDisplay: const TileDisplay.instantaneous(),
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
        timeIndex: c.timeIndex,
        basemap: basemap,
      ),
    ),
  ];
}

/// 格点场渲染：格点按 4 倍细分做双线性平滑（只为显示），三角网逐顶点着色。
/// 切换时次时新旧两帧交叉淡入（减少动效时直接替换）；数值本身不在时次间插值。
class WeatherFieldLayer extends StatefulWidget {
  const WeatherFieldLayer({
    super.key,
    required this.grid,
    required this.variable,
    required this.timeIndex,
    required this.basemap,
  });

  final FieldGrid grid;
  final FieldVar variable;
  final int timeIndex;
  final Basemap basemap;

  @override
  State<WeatherFieldLayer> createState() => _WeatherFieldLayerState();
}

class _WeatherFieldLayerState extends State<WeatherFieldLayer>
    with SingleTickerProviderStateMixin {
  static const _k = 4;
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Motion.base,
    value: 1,
  );
  int? _prevTime;
  final _fine = <(FieldVar, int), Float32List>{};

  @override
  void didUpdateWidget(covariant WeatherFieldLayer old) {
    super.didUpdateWidget(old);
    if (!identical(old.grid, widget.grid)) {
      _fine.clear();
      _prevTime = null;
      _fade.value = 1;
      return;
    }
    if (old.timeIndex != widget.timeIndex && old.variable == widget.variable) {
      if (Motion.reduced(context)) {
        _prevTime = null;
        _fade.value = 1;
      } else {
        _prevTime = old.timeIndex;
        _fade.forward(from: 0);
      }
    } else if (old.variable != widget.variable) {
      _prevTime = null;
      _fade.value = 1;
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  /// 细分网格上的值（双线性；任一角缺失则为 NaN → 透明）。
  Float32List _fineValues(FieldVar v, int t) => _fine.putIfAbsent((v, t), () {
    final g = widget.grid;
    final fc = (g.cols - 1) * _k + 1, fr = (g.rows - 1) * _k + 1;
    final out = Float32List(fc * fr);
    final src = g.values[v]![t];
    for (var r = 0; r < fr; r++) {
      final r0 = math.min(r ~/ _k, g.rows - 2);
      final ty = (r - r0 * _k) / _k;
      for (var c = 0; c < fc; c++) {
        final c0 = math.min(c ~/ _k, g.cols - 2);
        final tx = (c - c0 * _k) / _k;
        final a = src[r0 * g.cols + c0], b = src[r0 * g.cols + c0 + 1];
        final d = src[(r0 + 1) * g.cols + c0],
            e = src[(r0 + 1) * g.cols + c0 + 1];
        out[r * fc + c] =
            (a * (1 - tx) + b * tx) * (1 - ty) + (d * (1 - tx) + e * tx) * ty;
      }
    }
    return out;
  });

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final g = widget.grid;
    final t = widget.timeIndex.clamp(0, g.timesUtc.length - 1);
    final prev = _prevTime;
    return MobileLayerTransformer(
      child: AnimatedBuilder(
        animation: _fade,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _FieldPainter(
            camera: camera,
            grid: g,
            basemap: widget.basemap,
            k: _k,
            current: _fineValues(widget.variable, t),
            previous: prev == null || _fade.value >= 1
                ? null
                : _fineValues(
                    widget.variable,
                    prev.clamp(0, g.timesUtc.length - 1),
                  ),
            fade: _fade.value,
            colorOf: fieldColor(widget.variable),
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

const precipStops = <(double, Color)>[
  (0.1, Color(0x0078BEFA)),
  (0.3, Color(0x7378BEFA)),
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
  if (x.isNaN || x < stops.first.$1) return const Color(0x00000000);
  for (var i = 1; i < stops.length; i++) {
    final (x1, c1) = stops[i];
    if (x <= x1) {
      final (x0, c0) = stops[i - 1];
      return Color.lerp(c0, c1, (x - x0) / (x1 - x0))!;
    }
  }
  return stops.last.$2;
}

class _FieldPainter extends CustomPainter {
  _FieldPainter({
    required this.camera,
    required this.grid,
    required this.basemap,
    required this.k,
    required this.current,
    required this.previous,
    required this.fade,
    required this.colorOf,
  });

  final MapCamera camera;
  final FieldGrid grid;
  final Basemap basemap;
  final int k;
  final Float32List current;
  final Float32List? previous;
  final double fade;
  final FieldColorOf colorOf;

  @override
  void paint(Canvas canvas, Size size) {
    final g = grid;
    final fc = (g.cols - 1) * k + 1, fr = (g.rows - 1) * k + 1;
    // 粗格点投影到屏幕，细分点在屏幕坐标里双线性插值（墨卡托下行列等距，误差可忽略）。
    final coarse = [
      for (var r = 0; r < g.rows; r++)
        for (var c = 0; c < g.cols; c++)
          camera.latLngToScreenOffset(
            basemap.toDisplay(LatLng(g.lats[r], g.lons[c])),
          ),
    ];
    final pos = Float32List(fc * fr * 2);
    for (var r = 0; r < fr; r++) {
      final r0 = math.min(r ~/ k, g.rows - 2);
      final ty = (r - r0 * k) / k;
      for (var c = 0; c < fc; c++) {
        final c0 = math.min(c ~/ k, g.cols - 2);
        final tx = (c - c0 * k) / k;
        final a = coarse[r0 * g.cols + c0], b = coarse[r0 * g.cols + c0 + 1];
        final d = coarse[(r0 + 1) * g.cols + c0];
        final e = coarse[(r0 + 1) * g.cols + c0 + 1];
        final p = Offset.lerp(
          Offset.lerp(a, b, tx)!,
          Offset.lerp(d, e, tx)!,
          ty,
        )!;
        pos[(r * fc + c) * 2] = p.dx;
        pos[(r * fc + c) * 2 + 1] = p.dy;
      }
    }
    final idx = Uint16List((fc - 1) * (fr - 1) * 6);
    var n = 0;
    for (var r = 0; r < fr - 1; r++) {
      for (var c = 0; c < fc - 1; c++) {
        final i = r * fc + c;
        idx[n++] = i;
        idx[n++] = i + 1;
        idx[n++] = i + fc;
        idx[n++] = i + 1;
        idx[n++] = i + fc + 1;
        idx[n++] = i + fc;
      }
    }
    void draw(Float32List values, double alpha) {
      if (alpha <= 0.01) return;
      final colors = Int32List(values.length);
      for (var i = 0; i < values.length; i++) {
        final col = colorOf(values[i]);
        colors[i] = col.withValues(alpha: col.a * alpha).toARGB32();
      }
      canvas.drawVertices(
        ui.Vertices.raw(
          ui.VertexMode.triangles,
          pos,
          colors: colors,
          indices: idx,
        ),
        BlendMode.dst,
        Paint(),
      );
    }

    if (previous != null) draw(previous!, 1 - fade);
    draw(current, fade);
  }

  @override
  bool shouldRepaint(covariant _FieldPainter old) =>
      old.camera != camera ||
      !identical(old.current, current) ||
      !identical(old.previous, previous) ||
      old.fade != fade;
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
    final busy = sat ? c.satLoading : c.loading;
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
            if (!sat && c.tooWide)
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
              Row(
                children: [
                  IconButton(
                    tooltip: c.playing ? S.wxMapPause : S.wxMapPlay,
                    icon: Icon(c.playing ? Icons.pause : Icons.play_arrow),
                    onPressed: n > 1 ? c.togglePlay : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: c.frameIndex.toDouble().clamp(
                        0,
                        (n - 1).toDouble(),
                      ),
                      min: 0,
                      max: math.max(1, n - 1).toDouble(),
                      divisions: math.max(1, n - 1),
                      onChanged: n > 1 ? (v) => c.setFrame(v.round()) : null,
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
                    sat
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
