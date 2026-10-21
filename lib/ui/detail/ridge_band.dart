import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/units.dart';
import '../../data/routes/route_models.dart';
import '../../data/settings/settings_repository.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/weather_models.dart';
import '../motion.dart';
import '../strings.dart';
import '../tokens.dart';
import 'detail_state.dart';
import 'node_wx_style.dart';
import 'ridge_axis.dart';
import 'ridge_key_weather.dart';

/// 山脊天气带（D-032）：海拔剖面作主视觉，山脊线按最近节点的天气分类着色。
///
/// 颜色只来自节点的真实分类（与地图标记同一套），节点之间不插值；
/// 保留小圆点的简洁剖面，选中说明中的序号与列表一致。
/// 重要降水/阵风集中在图下标记，黄红提示保留图标；日落后路段铺夜色。
/// 首次拿到数据时山脊线从左到右画出一次，减少动效或低耗电时直接显示。
class RidgeWeatherBand extends ConsumerStatefulWidget {
  const RidgeWeatherBand({
    super.key,
    required this.route,
    required this.rows,
    required this.selectedIndex,
    required this.onTapNode,
    this.etaLabels,
    this.nightFromIndex,
    this.height = 150,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final int? selectedIndex;
  final ValueChanged<int> onTapNode;

  /// 行程模式下各节点的预计到达时刻（本地 HH:mm）；固定时刻模式为 null。
  final List<String>? etaLabels;

  /// 第一个在日落之后到达的节点下标（行程模式且日落已知时）。
  final int? nightFromIndex;
  final double height;

  @override
  ConsumerState<RidgeWeatherBand> createState() => _RidgeWeatherBandState();
}

class _RidgeWeatherBandState extends ConsumerState<RidgeWeatherBand>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Motion.emphasis,
  );
  late final _curve = CurvedAnimation(parent: _reveal, curve: Motion.enter);
  late _Profile _profile = _Profile.of(widget.route);

  bool get _hasWx => widget.rows.any((r) => r.wx != null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeReveal();
  }

  @override
  void didUpdateWidget(covariant RidgeWeatherBand old) {
    super.didUpdateWidget(old);
    if (!identical(old.route, widget.route)) {
      _profile = _Profile.of(widget.route);
    }
    _maybeReveal();
  }

  /// 只在第一次拿到天气数据时画一次；之后切换时间/来源只换颜色，不重播。
  void _maybeReveal() {
    if (!_hasWx || _reveal.isAnimating || _reveal.isCompleted) return;
    final reduced = Motion.reduced(
      context,
      lowPower: ref.read(settingsProvider).lowPower,
    );
    if (reduced) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rows = widget.rows;
    final classes = [for (final r in rows) classifyNodeWx(r.wx)];
    final sel = widget.selectedIndex;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final flagged = classes
        .where(
          (c) => c.level != NodeWxLevel.none && c.level != NodeWxLevel.unknown,
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: S.ridgeBandSemantics(
            rows.length,
            flagged,
            hasElevation: _profile.hasElevation,
          ),
          child: SizedBox(
            key: const ValueKey('ridge-profile'),
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, c) {
                final geom = _Geometry(
                  size: Size(c.maxWidth, widget.height),
                  profile: _profile,
                  bottom: 26,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: rows.isEmpty
                      ? null
                      : (d) => widget.onTapNode(
                          geom.nearestNode(d.localPosition.dx, rows),
                        ),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      size: Size(c.maxWidth, widget.height),
                      painter: _RidgePainter(
                        geom: geom,
                        rows: rows,
                        classes: classes,
                        selected: sel,
                        nightFromIndex: widget.nightFromIndex,
                        compact: true,
                        calm: Semantic.go,
                        fontFamily: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.fontFamily,
                        onTapNode: widget.onTapNode,
                        progress: _curve,
                        fill: Semantic.go.withValues(alpha: dark ? 0.25 : 0.10),
                        neutral: scheme.outlineVariant,
                        label: scheme.onSurfaceVariant,
                        guide: scheme.onSurface,
                        night: dark
                            ? Colors.black.withValues(alpha: 0.35)
                            : Palette.night.withValues(alpha: 0.10),
                        textDirection: Directionality.of(context),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (sel == null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              S.ridgeInteractionHint,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        if (sel != null && sel >= 0 && sel < rows.length)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: _SelectedLine(
              row: rows[sel],
              index: sel,
              cls: classes[sel],
              eta: widget.etaLabels?[sel],
              settings: ref.watch(settingsProvider),
            ),
          ),
        const SizedBox(height: Space.sm),
        RidgeKeyWeather(
          rows: rows,
          settings: ref.watch(settingsProvider),
          onSelect: widget.onTapNode,
        ),
      ],
    );
  }
}

/// 山脊天气带的静态版本（分享图用）：不播放画出动画、不响应点击，固定浅色卡片配色。
///
/// [keyNodes] 中的节点在山脊上画成连续编号的徽章（1..K），与分享图的示意图和节点列表一致；
/// 其余节点仍画小圆点。着色、图标与夜色规则和 App 内的 [RidgeWeatherBand] 相同。
class RidgeBandGraphic extends StatelessWidget {
  const RidgeBandGraphic({
    super.key,
    required this.route,
    required this.rows,
    this.keyNodes = const [],
    this.keyLabels,
    this.nightFromIndex,
    this.height = 120,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;

  /// 与 [keyNodes] 一一对应、画在编号徽章下方的短标签（行程模式的到达时刻）。
  final List<String>? keyLabels;
  final int? nightFromIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = _Profile.of(route);
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, c) => CustomPaint(
          size: Size(c.maxWidth, height),
          painter: _RidgePainter(
            geom: _Geometry(size: Size(c.maxWidth, height), profile: profile),
            rows: rows,
            classes: [for (final r in rows) classifyNodeWx(r.wx)],
            fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
            selected: null,
            nightFromIndex: nightFromIndex,
            keyNodes: keyNodes,
            keyLabels: keyLabels,
            progress: kAlwaysCompleteAnimation,
            fill: scheme.primary.withValues(alpha: 0.10),
            neutral: scheme.outlineVariant,
            label: scheme.onSurfaceVariant,
            guide: scheme.onSurface,
            night: Palette.night.withValues(alpha: 0.10),
            textDirection: Directionality.of(context),
          ),
        ),
      ),
    );
  }
}

class _SelectedLine extends StatelessWidget {
  const _SelectedLine({
    required this.row,
    required this.index,
    required this.cls,
    required this.eta,
    required this.settings,
  });

  final NodeWxRow row;
  final int index;
  final NodeWxClass cls;
  final String? eta;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final n = row.node;
    final parts = [
      S.ridgeNodeN(index + 1),
      if (n.label != null) n.label!,
      '${(n.distFromStartM / 1000).toStringAsFixed(1)} km',
      if (n.elevationM != null) '${n.elevationM!.round()} m',
      if (eta != null) S.ridgeArrive(eta!),
      cls.label,
      '${S.ridgeNodePrecip} ${row.wx?.values[WxVar.precip] == null ? S.notProvided : Units.precipMm(row.wx!.values[WxVar.precip]!, imperial: settings.imperial)}',
      '${S.ridgeNodeGust} ${row.wx?.values[WxVar.windGust] == null ? S.notProvided : Units.windMs(row.wx!.values[WxVar.windGust]!, unit: settings.windUnit)}',
    ];
    return Row(
      children: [
        Icon(nodeWxIcon(cls), size: 16, color: nodeWxColor(cls)),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Text(
            parts.join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// 完整轨迹的累计距离与海拔（与节点 distFromStartM 同一算法）。
class _Profile {
  _Profile(this.dist, this.ele);

  factory _Profile.of(HikingRoute route) {
    final path = route.analysisPath;
    return _Profile(Geo.cumulativeDistancesM(path.points), path.elevations);
  }

  final List<double> dist;
  final List<double?> ele;

  late final bool hasElevation = ele.where((e) => e != null).length >= 2;
  late final double total = dist.isEmpty ? 1 : math.max(dist.last, 1);
  late final double minE = hasElevation
      ? ele.whereType<double>().reduce(math.min)
      : 0;
  late final double maxE = hasElevation
      ? ele.whereType<double>().reduce(math.max)
      : 0;

  /// 某距离处的海拔（相邻有值点线性插值；无海拔时为 null）。
  double? eleAt(double d) {
    if (!hasElevation) return null;
    var lo = 0, hi = dist.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (dist[mid] <= d) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final a = ele[lo], b = ele[hi];
    if (a == null) return b;
    if (b == null) return a;
    final span = dist[hi] - dist[lo];
    final t = span <= 0 ? 0.0 : ((d - dist[lo]) / span).clamp(0.0, 1.0);
    return a + (b - a) * t;
  }
}

class _Geometry {
  _Geometry({required this.size, required this.profile, this.bottom = 18});

  final Size size;
  final _Profile profile;

  static const left = 34.0, right = 8.0, top = 30.0;
  final double bottom;

  double get plotW => size.width - left - right;
  double get plotH => size.height - top - bottom;

  double x(double d) => left + plotW * (d / profile.total).clamp(0.0, 1.0);

  double y(double? e) {
    if (e == null || !profile.hasElevation) return top + plotH * 0.6;
    final span = math.max(profile.maxE - profile.minE, 30);
    return top + plotH * (1 - (e - profile.minE) / span);
  }

  int nearestNode(double px, List<NodeWxRow> rows) {
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < rows.length; i++) {
      final d = (x(rows[i].node.distFromStartM) - px).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  /// 剖面在距离区间 [d0, d1] 内的折线（端点插值）。
  Path segment(double d0, double d1) {
    final p = Path()..moveTo(x(d0), y(profile.eleAt(d0)));
    for (var i = 0; i < profile.dist.length; i++) {
      final d = profile.dist[i];
      if (d <= d0) continue;
      if (d >= d1) break;
      p.lineTo(x(d), y(profile.ele[i] ?? profile.eleAt(d)));
    }
    p.lineTo(x(d1), y(profile.eleAt(d1)));
    return p;
  }
}

class _RidgePainter extends CustomPainter {
  _RidgePainter({
    required this.geom,
    required this.rows,
    required this.classes,
    required this.selected,
    required this.nightFromIndex,
    this.keyNodes = const [],
    this.keyLabels,
    this.compact = false,
    this.calm,
    this.fontFamily,
    this.onTapNode,
    required this.progress,
    required this.fill,
    required this.neutral,
    required this.label,
    required this.guide,
    required this.night,
    required this.textDirection,
  }) : super(repaint: progress);

  final _Geometry geom;
  final List<NodeWxRow> rows;
  final List<NodeWxClass> classes;
  final int? selected;
  final int? nightFromIndex;

  /// 画成编号徽章的节点（分享图）；App 内为空。
  final List<int> keyNodes;
  final List<String>? keyLabels;
  final bool compact;
  final Color? calm;
  final String? fontFamily;
  final ValueChanged<int>? onTapNode;
  final Animation<double> progress;
  final Color fill, neutral, label, guide, night;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geom;
    final p = g.profile;
    final t = progress.value;
    final plot = Rect.fromLTWH(_Geometry.left, _Geometry.top, g.plotW, g.plotH);
    final floorY = size.height - g.bottom;
    Color colorAt(int i) => rows[i].wx == null
        ? neutral
        : (compact && classes[i] == NodeWxClass.calm
              ? calm!
              : nodeWxColor(classes[i]));

    // 细网格与四级海拔刻度；无海拔不生成任何海拔值。
    if (p.hasElevation) {
      final span = math.max(p.maxE - p.minE, 30);
      final divisions = compact ? 2 : 3;
      for (var i = 0; i <= divisions; i++) {
        final elevation = p.minE + span * i / divisions;
        final y = g.y(elevation);
        canvas.drawLine(
          Offset(plot.left, y),
          Offset(plot.right, y),
          Paint()
            ..color = label.withValues(alpha: 0.12)
            ..strokeWidth = 0.5,
        );
        _text(canvas, '${elevation.round()} m', Offset(0, y - 6), 10);
      }
    }
    for (final d in ridgeDistanceTicks(p.total, g.plotW)) {
      final x = g.x(d);
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, floorY),
        Paint()
          ..color = label.withValues(alpha: compact ? 0 : 0.08)
          ..strokeWidth = 0.5,
      );
      final km = d / 1000;
      _text(
        canvas,
        km == km.roundToDouble() ? '${km.round()}' : '$km',
        Offset(x, floorY + (compact ? 8 : 3)),
        10,
        center: true,
      );
    }

    // 夜色：日落后到达的路段（从该节点与前一节点的中点起）。
    final nf = nightFromIndex;
    if (nf != null && nf < rows.length) {
      final d0 = nf == 0
          ? 0.0
          : (rows[nf - 1].node.distFromStartM + rows[nf].node.distFromStartM) /
                2;
      final r = Rect.fromLTRB(g.x(d0), plot.top - 14, plot.right, floorY);
      canvas.drawRect(r, Paint()..color = night);
      // 标在夜色区底部：顶部留给天气图标。
      _text(canvas, S.ridgeAfterSunset, Offset(r.left + 4, floorY - 14), 10);
    }

    // 山体：填充随画出进度淡入。
    final body = g.segment(0, p.total)
      ..lineTo(g.x(p.total), floorY)
      ..lineTo(g.x(0), floorY)
      ..close();
    canvas.drawPath(body, Paint()..color = fill.withValues(alpha: fill.a * t));

    // 山脊线：从左到右画出；每个节点负责到相邻节点中点的一段。
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, plot.left + plot.width * t, size.height));
    if (rows.isEmpty) {
      canvas.drawPath(g.segment(0, p.total), _stroke(neutral));
    } else {
      for (var i = 0; i < rows.length; i++) {
        final d = rows[i].node.distFromStartM;
        final d0 = i == 0 ? 0.0 : (rows[i - 1].node.distFromStartM + d) / 2;
        final d1 = i == rows.length - 1
            ? p.total
            : (d + rows[i + 1].node.distFromStartM) / 2;
        if (d1 <= d0) continue;
        final c = colorAt(i);
        canvas.drawPath(g.segment(d0, d1), _stroke(c));
      }
    }
    canvas.restore();

    // 选中节点：竖向参考线。
    final s = selected;
    if (s != null && s >= 0 && s < rows.length) {
      final sx = g.x(rows[s].node.distFromStartM);
      canvas.drawLine(
        Offset(sx, plot.top - 4),
        Offset(sx, floorY),
        Paint()
          ..color = guide.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
    }

    // 节点：山脊上的小圆点。
    final revealX = plot.left + plot.width * t + 0.5;
    for (var i = 0; i < rows.length; i++) {
      final n = rows[i].node;
      final nx = g.x(n.distFromStartM);
      if (nx > revealX) continue;
      final ny = g.y(n.elevationM ?? p.eleAt(n.distFromStartM));
      final color = colorAt(i);
      final k = keyNodes.indexOf(i);
      if (k >= 0) {
        _numberBadge(canvas, Offset(nx, ny), k + 1, color);
        final kl = keyLabels;
        if (kl != null && k < kl.length) {
          _text(canvas, kl[k], Offset(nx, ny + 12), 9, center: true);
        }
        continue;
      }
      final isSel = i == s;
      canvas
        ..drawCircle(
          Offset(nx, ny),
          isSel ? 6.5 : 4.5,
          Paint()..color = Colors.white,
        )
        ..drawCircle(Offset(nx, ny), isSel ? 5 : 3.2, Paint()..color = color);
    }

    // 图标：触发提示的节点按严重程度依次摆放（选中的先放），与已放的太近就省略，
    // 不让图标互相压住；省略的节点山脊颜色与圆点仍然在。
    final order =
        [
          for (var i = 0; i < rows.length; i++)
            if ((i == s && classes[i].level != NodeWxLevel.none) ||
                (rows[i].wx != null &&
                    (compact
                        ? classes[i].level == NodeWxLevel.red ||
                              classes[i].level == NodeWxLevel.yellow
                        : classes[i].level != NodeWxLevel.none)))
              i,
        ]..sort((a, b) {
          if (a == s) return -1;
          if (b == s) return 1;
          final r = _rank(classes[a]).compareTo(_rank(classes[b]));
          return r != 0 ? r : a.compareTo(b);
        });
    final placed = <double>[];
    for (final i in order) {
      final nx = g.x(rows[i].node.distFromStartM);
      if (nx > revealX) continue;
      if (placed.any((x) => (x - nx).abs() < _badgeGap)) continue;
      placed.add(nx);
      final color = rows[i].wx == null ? neutral : nodeWxColor(classes[i]);
      _badge(canvas, Offset(nx, plot.top - 16), classes[i], color);
    }

    // 无海拔说明与起终距离。
    if (!p.hasElevation) {
      _text(canvas, S.ridgeNoElevation, Offset(plot.left, floorY - 14), 10);
    }
    _text(canvas, '0', Offset(plot.left, floorY + (compact ? 8 : 3)), 10);
    final km = '${(p.total / 1000).toStringAsFixed(1)} km';
    _text(
      canvas,
      km,
      Offset(plot.right, floorY + (compact ? 8 : 3)),
      10,
      alignRight: true,
    );
  }

  /// 图标之间的最小水平间距（图标直径 20 + 留白）。
  static const _badgeGap = 22.0;

  /// 图标摆放优先级：红色阈值 > 黄色 > 提示 > 数据不足。
  static int _rank(NodeWxClass c) => switch (c.level) {
    NodeWxLevel.red => 0,
    NodeWxLevel.yellow => 1,
    NodeWxLevel.info => 2,
    NodeWxLevel.unknown => 3,
    NodeWxLevel.none => 4,
  };

  Paint _stroke(Color c) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _badge(Canvas canvas, Offset c, NodeWxClass cls, Color color) {
    canvas
      ..drawCircle(c, 10, Paint()..color = Colors.white)
      ..drawCircle(c, 8.5, Paint()..color = color);
    final icon = nodeWxIcon(cls);
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: 11,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _numberBadge(Canvas canvas, Offset c, int n, Color color) {
    canvas
      ..drawCircle(c, 10, Paint()..color = Colors.white)
      ..drawCircle(c, 8.5, Paint()..color = color);
    final tp = TextPainter(
      text: TextSpan(
        text: '$n',
        style: TextStyle(
          fontSize: 10,
          fontFamily: fontFamily,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _text(
    Canvas canvas,
    String s,
    Offset at,
    double size, {
    bool alignRight = false,
    bool center = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: size, color: label, fontFamily: fontFamily),
      ),
      textDirection: textDirection,
    )..layout();
    tp.paint(
      canvas,
      alignRight
          ? at - Offset(tp.width, 0)
          : center
          ? at - Offset(tp.width / 2, 0)
          : at,
    );
  }

  @override
  SemanticsBuilderCallback? get semanticsBuilder => onTapNode == null
      ? null
      : (size) => [
          for (var i = 0; i < rows.length; i++)
            CustomPainterSemantics(
              rect: Rect.fromCenter(
                center: Offset(
                  geom.x(rows[i].node.distFromStartM),
                  geom.y(
                    rows[i].node.elevationM ??
                        geom.profile.eleAt(rows[i].node.distFromStartM),
                  ),
                ),
                width: 24,
                height: 24,
              ),
              properties: SemanticsProperties(
                label:
                    '${S.ridgeNodeN(i + 1)}${rows[i].node.label == null ? '' : ' · ${rows[i].node.label}'}',
                button: true,
                selected: i == selected,
                textDirection: textDirection,
                onTap: onTapNode == null ? null : () => onTapNode!(i),
              ),
            ),
        ];

  @override
  bool shouldRebuildSemantics(covariant _RidgePainter old) => true;

  @override
  bool shouldRepaint(covariant _RidgePainter old) =>
      old.rows != rows ||
      old.selected != selected ||
      old.nightFromIndex != nightFromIndex ||
      old.keyNodes != keyNodes ||
      old.keyLabels != keyLabels ||
      old.compact != compact ||
      old.calm != calm ||
      old.fontFamily != fontFamily ||
      old.geom.size != geom.size ||
      old.geom.profile != geom.profile ||
      old.fill != fill;
}
