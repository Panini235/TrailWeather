import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings/settings_repository.dart';
import '../../data/weather/layering.dart';
import '../motion.dart';
import '../strings.dart';
import '../tokens.dart';
import 'detail_state.dart';

/// 洋葱穿衣卡片（D-035）：一个人形剪影上叠三层衣服，切换“出发 / 行进 / 停留”时
/// 各层在“穿着（实色）/ 背包（虚线）/ 不需要（隐去）”之间过渡。文字只留衣物名称，
/// 依据收在“依据”里。
class LayeringCard extends ConsumerStatefulWidget {
  const LayeringCard({
    super.key,
    required this.rows,
    this.sunriseUtc,
    this.sunsetUtc,
  });

  final List<NodeWxRow> rows;
  final DateTime? sunriseUtc;
  final DateTime? sunsetUtc;

  @override
  ConsumerState<LayeringCard> createState() => _LayeringCardState();
}

class _LayeringCardState extends ConsumerState<LayeringCard> {
  LayerScene _scene = LayerScene.start;

  LayerPlan? _plan(AppSettings settings) => planLayers(
    entries: rowsToEntries(widget.rows),
    labels: [
      for (final r in widget.rows)
        r.node.label ??
            '${(r.node.distFromStartM / 1000).toStringAsFixed(1)} km 处',
    ],
    sunriseUtc: widget.sunriseUtc,
    sunsetUtc: widget.sunsetUtc,
    coldSensitivity: settings.coldSensitivity,
  );

  /// 三层（排汗 / 保暖 / 防护）在当前场景下的目标状态：1 穿着、0.5 背包、0 不需要。
  /// 用记录类型：值相等，父级重建时不会重新起动画。
  _States _targets(LayerPlan plan, LayerScene scene) {
    double v(LayerKind k) => switch (plan.layer(k)?.wear[scene]) {
      Wear.worn => 1.0,
      Wear.packed => 0.5,
      _ => 0.0,
    };
    return (v(LayerKind.base), v(LayerKind.mid), v(LayerKind.shell));
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final plan = _plan(settings);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    if (plan == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Text(
            S.layeringNoData,
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      );
    }
    final reduced = Motion.reduced(context, lowPower: settings.lowPower);
    final wet = plan.layer(LayerKind.shell)?.name == '防水硬壳';

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Space.md,
          Space.sm,
          Space.md,
          Space.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(S.layeringTitle, style: theme.textTheme.titleSmall),
                const Spacer(),
                _SensitivityToggle(
                  value: settings.coldSensitivity,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setColdSensitivity(v),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            SegmentedButton<LayerScene>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final s in LayerScene.values)
                  ButtonSegment(
                    value: s,
                    label: Text(
                      '${layerSceneLabel(s)} ${plan.feels[s]!.round()}°',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              selected: {_scene},
              onSelectionChanged: (v) => setState(() => _scene = v.first),
            ),
            const SizedBox(height: Space.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Semantics(
                  label: _figureSemantics(plan),
                  child: SizedBox(
                    width: 92,
                    height: 104,
                    // 首次出现与切换场景都由里到外依次过渡；减少动效时直接到终态。
                    child: TweenAnimationBuilder<_States>(
                      tween: _StaggerTween(
                        begin: (0, 0, 0),
                        end: _targets(plan, _scene),
                      ),
                      duration: reduced ? Duration.zero : Motion.slow * 1.5,
                      builder: (context, states, _) => CustomPaint(
                        painter: LayerFigurePainter(
                          states: [states.$1, states.$2, states.$3],
                          shellColor: wet ? Semantic.route : _windShell,
                          outline: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final l in plan.layers)
                        _LayerRow(
                          item: l,
                          wear: l.wear[_scene]!,
                          color: _layerColor(l.kind, wet),
                          muted: muted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (plan.accessories.isNotEmpty) ...[
              const SizedBox(height: Space.sm),
              _Accessories(picks: plan.accessories, muted: muted),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _showBasis(context, plan),
                child: const Text(S.layeringBasis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _figureSemantics(LayerPlan plan) {
    final parts = [
      for (final l in plan.layers)
        '${l.name}${switch (l.wear[_scene]!) {
          Wear.worn => '穿着',
          Wear.packed => '放背包',
          Wear.none => '不需要',
        }}',
    ];
    return '${S.layeringTitle}，${layerSceneLabel(_scene)}时：${parts.join('，')}';
  }

  void _showBasis(BuildContext context, LayerPlan plan) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final muted = Theme.of(ctx).colorScheme.onSurfaceVariant;
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(S.layeringBasis, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final l in plan.layers) ...[
                Text(
                  '${layerKindLabel(l.kind)} · ${l.name}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  l.reason,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 8),
              ],
              for (final a in plan.accessories)
                Text(
                  '${accessoryLabel(a.item)}：${a.reason}',
                  style: const TextStyle(fontSize: 13, height: 1.4),
                ),
              if (plan.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final n in plan.notes)
                  Text(n, style: TextStyle(fontSize: 12, color: muted)),
              ],
              const Divider(height: 24),
              Text(
                S.layeringDisclaimer,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _windShell = Color(0xFF5B6B78);

Color _layerColor(LayerKind k, bool wet) => switch (k) {
  LayerKind.base => Palette.sage,
  LayerKind.mid => Palette.sun,
  LayerKind.shell => wet ? Semantic.route : _windShell,
  LayerKind.legs => Palette.pine,
};

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.item,
    required this.wear,
    required this.color,
    required this.muted,
  });

  final LayerItem item;
  final Wear wear;
  final Color color;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final packed = wear == Wear.packed;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: AnimatedOpacity(
        opacity: wear == Wear.none ? 0.35 : 1,
        duration: Motion.of(context, Motion.base),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: packed ? null : color,
                border: Border.all(color: color, width: 1.6),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                item.name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (packed) ...[
              const SizedBox(width: 6),
              Icon(Icons.backpack_outlined, size: 14, color: muted),
              Text(
                S.layeringPacked,
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Accessories extends StatelessWidget {
  const _Accessories({required this.picks, required this.muted});

  final List<AccessoryPick> picks;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final items = picks.map((p) => p.item).toSet();
    final groups = <(IconData, Color, List<Accessory>)>[
      (
        Icons.wb_sunny_outlined,
        Palette.sun,
        [Accessory.sunscreen, Accessory.sunHat, Accessory.sunglasses],
      ),
      (
        Icons.ac_unit,
        Semantic.cold,
        [
          Accessory.beanie,
          Accessory.gloves,
          Accessory.warmGloves,
          Accessory.buff,
        ],
      ),
      (
        Icons.umbrella_outlined,
        Semantic.route,
        [Accessory.rainPants, Accessory.packCover],
      ),
      (Icons.flashlight_on_outlined, muted, [Accessory.headlamp]),
    ];
    return Wrap(
      spacing: Space.md,
      runSpacing: 4,
      children: [
        for (final (icon, color, list) in groups)
          if (list.any(items.contains))
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 4),
                Text(
                  list.where(items.contains).map(accessoryLabel).join(' · '),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
      ],
    );
  }
}

/// 三档偏好（怕冷 / 适中 / 怕热）。
class _SensitivityToggle extends StatelessWidget {
  const _SensitivityToggle({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget opt(int v, String text) {
      final on = v == value;
      return InkWell(
        borderRadius: BorderRadius.circular(Radii.sm),
        onTap: () => onChanged(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: on ? scheme.secondaryContainer : null,
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              color: on ? scheme.onSecondaryContainer : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Semantics(
      label: S.layeringSensitivity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          opt(-1, S.layeringColdy),
          opt(0, S.layeringNormal),
          opt(1, S.layeringWarmy),
        ],
      ),
    );
  }
}

/// 人形剪影上的三层衣服。[states]：排汗 / 保暖 / 防护各自 0（无）… 0.5（背包）… 1（穿着）。
/// 外层在后、内层在前，像洋葱一样从里到外套着；背包里的层只画虚线轮廓。
class LayerFigurePainter extends CustomPainter {
  LayerFigurePainter({
    required this.states,
    required this.shellColor,
    required this.outline,
  });

  final List<double> states;
  final Color shellColor;
  final Color outline;

  static Path _jacket(Size size, double scale) {
    final w = size.width, h = size.height;
    // 以领口为锚点缩放：内层更小，从领口往下套。
    Offset p(double x, double y) =>
        Offset(w * (0.5 + (x - 0.5) * scale), h * (0.04 + (y - 0.04) * scale));
    return Path()
      ..moveTo(p(0.40, 0.06).dx, p(0.40, 0.06).dy)
      ..lineTo(p(0.17, 0.16).dx, p(0.17, 0.16).dy)
      ..lineTo(p(0.03, 0.62).dx, p(0.03, 0.62).dy)
      ..lineTo(p(0.16, 0.66).dx, p(0.16, 0.66).dy)
      ..lineTo(p(0.26, 0.38).dx, p(0.26, 0.38).dy)
      ..lineTo(p(0.27, 0.97).dx, p(0.27, 0.97).dy)
      ..lineTo(p(0.73, 0.97).dx, p(0.73, 0.97).dy)
      ..lineTo(p(0.74, 0.38).dx, p(0.74, 0.38).dy)
      ..lineTo(p(0.84, 0.66).dx, p(0.84, 0.66).dy)
      ..lineTo(p(0.97, 0.62).dx, p(0.97, 0.62).dy)
      ..lineTo(p(0.83, 0.16).dx, p(0.83, 0.16).dy)
      ..lineTo(p(0.60, 0.06).dx, p(0.60, 0.06).dy)
      ..quadraticBezierTo(
        p(0.5, 0.16).dx,
        p(0.5, 0.16).dy,
        p(0.40, 0.06).dx,
        p(0.40, 0.06).dy,
      )
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    // 外 → 内：防护、保暖、排汗。
    const order = [2, 1, 0];
    const scales = [0.70, 0.85, 1.0];
    final colors = [Palette.sage, Palette.sun, shellColor];

    // 底层虚线人形：没有任何一层时也看得出是个人。
    _dashedPath(
      canvas,
      _jacket(size, 0.70),
      outline.withValues(alpha: 0.18),
      1,
    );
    for (final i in order) {
      final s = states[i];
      if (s <= 0.01) continue;
      final path = _jacket(size, scales[i]);
      final c = colors[i];
      final fill = ((s - 0.5) * 2).clamp(0.0, 1.0);
      if (fill > 0) {
        canvas.drawPath(
          path,
          Paint()..color = c.withValues(alpha: 0.92 * fill),
        );
      }
      final strokeAlpha = (s * 2).clamp(0.0, 1.0);
      if (fill < 0.5) {
        _dashedPath(canvas, path, c.withValues(alpha: 0.9 * strokeAlpha), 1.6);
      } else {
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..strokeJoin = StrokeJoin.round
            ..color = Color.lerp(
              c,
              Colors.black,
              0.25,
            )!.withValues(alpha: strokeAlpha),
        );
      }
    }
  }

  void _dashedPath(Canvas canvas, Path path, Color color, double width) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final PathMetric m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += 7) {
        canvas.drawPath(m.extractPath(d, d + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LayerFigurePainter old) =>
      old.shellColor != shellColor ||
      old.outline != outline ||
      !_listEq(old.states, states);
}

bool _listEq(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

typedef _States = (double, double, double);

/// 三层依次过渡（排汗 0–55%，保暖 22–78%，防护 45–100%），像一层层套上去。
class _StaggerTween extends Tween<_States> {
  _StaggerTween({required super.begin, required super.end});

  @override
  _States lerp(double t) {
    double f(int i, double a, double b) =>
        a +
        (b - a) *
            Motion.enter.transform(((t - i * 0.225) / 0.55).clamp(0.0, 1.0));
    final (a0, a1, a2) = begin!;
    final (b0, b1, b2) = end!;
    return (f(0, a0, b0), f(1, a1, b1), f(2, a2, b2));
  }
}
