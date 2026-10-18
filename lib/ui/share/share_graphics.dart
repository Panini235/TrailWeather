import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/geo.dart';
import '../../data/routes/route_models.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/risk_rules.dart';
import '../detail/detail_state.dart';
import '../detail/node_wx_style.dart';
import '../tokens.dart';

/// 分享图里要编号展示的关键节点（下标），至多 [max] 个，按沿途顺序：
/// 起点、终点、最高点、命名航点、触发红/黄阈值的节点（红优先），其余不进列表。
List<int> pickKeyNodes(List<NodeWxRow> rows, {int max = 6}) {
  if (rows.isEmpty) return const [];
  final must = <int>{0, rows.length - 1};
  var high = -1;
  for (var i = 0; i < rows.length; i++) {
    final e = rows[i].node.elevationM;
    if (e != null &&
        (high < 0 ||
            e > (rows[high].node.elevationM ?? double.negativeInfinity))) {
      high = i;
    }
  }
  if (high >= 0) must.add(high);
  final ranked = <(int, int)>[]; // (优先级, 下标)，数小优先
  for (var i = 0; i < rows.length; i++) {
    if (must.contains(i)) continue;
    final level = classifyNodeWx(rows[i].wx).level;
    if (level == NodeWxLevel.red) {
      ranked.add((0, i));
    } else if (level == NodeWxLevel.yellow) {
      ranked.add((1, i));
    } else if (rows[i].node.waypoint != null) {
      ranked.add((2, i));
    }
  }
  ranked.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  final out = <int>{...must};
  for (final (_, i) in ranked) {
    if (out.length >= max) break;
    out.add(i);
  }
  return out.toList()..sort();
}

/// 提示类别 → 醒目图标（分享图与结论区共用）。
IconData hintIcon(WxHint h) => switch (h.id) {
  'gust' => Icons.air,
  'precip' || 'precip_prob' => Icons.water_drop,
  'snow' || 'freezing' => Icons.ac_unit,
  'thunder' => Icons.thunderstorm,
  'fog' => Icons.foggy,
  'cold' => Icons.severe_cold,
  'heat' => Icons.wb_sunny,
  'sunset' => Icons.wb_twilight,
  _ => Icons.info_outline,
};

/// 提示等级色：分享卡是固定浅色底，用 [SemanticInk] 的浅底文字色。
Color hintColor(WxHint h) => switch (h.level) {
  HintLevel.warning => SemanticInk.dangerOnLight,
  HintLevel.caution => SemanticInk.cautionOnLight,
  HintLevel.info => SemanticInk.infoOnLight,
};

/// 线路示意图（不含地图瓦片，避免瓦片授权进入外发图片）。D-034 重新设计：
/// - 按经纬度等比例投影、北向上，附指北针与比例尺；
/// - 分析路径按最近节点的天气分类分段着色（与山脊天气带同一规则），其余支线浅灰；
/// - 起终点在精确位置画端点，路线上用小箭头标行走方向；
/// - 关键节点用连续编号 1..K，徽章沿路线法向外移并用引线连到精确位置，互相避让，
///   不再压在路线上；起点 / 终点徽章旁注“起”“终”。
class RouteSketch extends StatelessWidget {
  const RouteSketch({
    super.key,
    required this.route,
    required this.rows,
    required this.keyNodes,
    this.height = 200,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CustomPaint(
        painter: _SketchPainter(
          route: route,
          rows: rows,
          keyNodes: keyNodes,
          neutral: scheme.outlineVariant,
          label: scheme.onSurfaceVariant,
          ink: scheme.onSurface,
          paper: scheme.surfaceContainerLow,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.route,
    required this.rows,
    required this.keyNodes,
    required this.neutral,
    required this.label,
    required this.ink,
    required this.paper,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;
  final Color neutral, label, ink, paper;

  static const _pad = 34.0, _bottom = 22.0, _badgeR = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [for (final s in route.segments) ...s];
    if (all.length < 2) return;
    var minLat = all.first.latitude, maxLat = minLat;
    var minLon = all.first.longitude, maxLon = minLon;
    for (final p in all) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // 经度按纬度余弦缩放，保持形状不变形。
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * k, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    final scale = math.min(
      (size.width - 2 * _pad) / w,
      (size.height - 2 * _pad - _bottom) / h,
    );
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - _bottom - h * scale) / 2;
    Offset at(LatLng p) => Offset(
      ox + (p.longitude - minLon) * k * scale,
      oy + (maxLat - p.latitude) * scale,
    );

    // ① 所有段先画浅灰（分析路径以外的支线保持浅灰）。
    for (final s in route.segments) {
      if (s.length < 2) continue;
      canvas.drawPath(_poly([for (final p in s) at(p)]), _stroke(neutral, 3));
    }

    // ② 分析路径按最近节点天气分段着色。
    final path = route.analysisPath;
    final pts = path.points;
    final dist = Geo.cumulativeDistancesM(pts);
    LatLng pointAt(double d) {
      if (d <= 0) return pts.first;
      if (d >= dist.last) return pts.last;
      var lo = 0, hi = dist.length - 1;
      while (hi - lo > 1) {
        final m = (lo + hi) >> 1;
        if (dist[m] <= d) {
          lo = m;
        } else {
          hi = m;
        }
      }
      final span = dist[hi] - dist[lo];
      final t = span <= 0 ? 0.0 : (d - dist[lo]) / span;
      return LatLng(
        pts[lo].latitude + (pts[hi].latitude - pts[lo].latitude) * t,
        pts[lo].longitude + (pts[hi].longitude - pts[lo].longitude) * t,
      );
    }

    List<Offset> span(double a, double b) => [
      at(pointAt(a)),
      for (var i = 0; i < pts.length; i++)
        if (dist[i] > a && dist[i] < b) at(pts[i]),
      at(pointAt(b)),
    ];

    if (rows.isEmpty) {
      canvas.drawPath(_poly([for (final p in pts) at(p)]), _stroke(ink, 3.5));
    }
    for (var i = 0; i < rows.length; i++) {
      final d = rows[i].node.distFromStartM;
      final a = i == 0 ? 0.0 : (rows[i - 1].node.distFromStartM + d) / 2;
      final b = i == rows.length - 1
          ? dist.last
          : (d + rows[i + 1].node.distFromStartM) / 2;
      if (b <= a) continue;
      canvas.drawPath(
        _poly(span(a, b)),
        _stroke(nodeWxColor(classifyNodeWx(rows[i].wx)), 3.5),
      );
    }

    // ③ 行走方向：沿路线每隔约 48 px 画一个小箭头。
    final screen = [for (final p in pts) at(p)];
    var acc = 24.0;
    for (var i = 1; i < screen.length; i++) {
      final seg = screen[i] - screen[i - 1];
      final len = seg.distance;
      if (len <= 0) continue;
      while (acc <= len) {
        final c = screen[i - 1] + seg * (acc / len);
        _chevron(canvas, c, seg / len);
        acc += 48;
      }
      acc -= len;
    }

    // ④ 端点：起点绿、终点红（环线合成一个）。
    final start = screen.first, end = screen.last;
    final loop = route.isLoop;
    _endpoint(canvas, start, Semantic.go);
    if (!loop) _endpoint(canvas, end, Semantic.danger);

    // ⑤ 关键节点徽章：法向外移 + 引线，互相避让。
    final centroid = Offset(
      screen.map((o) => o.dx).reduce((a, b) => a + b) / screen.length,
      screen.map((o) => o.dy).reduce((a, b) => a + b) / screen.length,
    );
    final placed = <Offset>[];
    final tags = <(Offset, String, Color)>[];
    final bounds = Rect.fromLTRB(
      _badgeR + 2,
      _badgeR + 2,
      size.width - _badgeR - 2,
      size.height - _bottom - _badgeR,
    );
    for (var n = 0; n < keyNodes.length; n++) {
      final i = keyNodes[n];
      if (i < 0 || i >= rows.length) continue;
      final node = rows[i].node;
      final anchor = at(pointAt(node.distFromStartM));
      // 节点处的路线切线 → 法线；优先朝路线外侧（远离重心）。
      final before = at(pointAt(math.max(0, node.distFromStartM - 60)));
      final after = at(pointAt(math.min(dist.last, node.distFromStartM + 60)));
      var t = after - before;
      if (t.distance < 1e-6) t = const Offset(1, 0);
      t = t / t.distance;
      var normal = Offset(-t.dy, t.dx);
      if ((anchor - centroid).dx * normal.dx +
              (anchor - centroid).dy * normal.dy <
          0) {
        normal = -normal;
      }
      Offset? spot;
      for (final r in const [22.0, 32.0, 44.0, 56.0]) {
        for (final dir in [normal, -normal, t, -t]) {
          final c = anchor + dir * r;
          if (!bounds.contains(c)) continue;
          if (placed.any((o) => (o - c).distance < 2 * _badgeR + 3)) continue;
          spot = c;
          break;
        }
        if (spot != null) break;
      }
      spot ??= anchor + normal * 22;
      placed.add(spot);
      final color = nodeWxColor(classifyNodeWx(rows[i].wx));
      canvas
        ..drawLine(
          anchor,
          spot,
          Paint()
            ..color = ink.withValues(alpha: 0.55)
            ..strokeWidth = 1,
        )
        ..drawCircle(anchor, 3, Paint()..color = ink);
      _badge(canvas, spot, '${n + 1}', color);
      final tag = i == 0
          ? (loop ? '起终' : '起')
          : (i == rows.length - 1 && !loop ? '终' : null);
      if (tag != null) {
        tags.add((spot, tag, i == 0 ? Semantic.go : Semantic.danger));
      }
    }

    // “起 / 终”标签：在徽章右、左、上、下中找第一个不与徽章或其他标签重叠的位置。
    final taken = [
      for (final o in placed) Rect.fromCircle(center: o, radius: _badgeR + 1.5),
    ];
    for (final (spot, tag, color) in tags) {
      final pw = tag.length * 11 + 10.0;
      final options = [
        spot + Offset(_badgeR + 4 + pw / 2, 0),
        spot - Offset(_badgeR + 4 + pw / 2, 0),
        spot - const Offset(0, _badgeR + 12),
        spot + const Offset(0, _badgeR + 12),
      ];
      var c = options.first;
      for (final o in options) {
        final r = Rect.fromCenter(center: o, width: pw, height: 16);
        if (taken.every((t) => !t.overlaps(r)) &&
            r.left >= 0 &&
            r.right <= size.width &&
            r.top >= 0) {
          c = o;
          break;
        }
      }
      taken.add(Rect.fromCenter(center: c, width: pw, height: 16));
      _pill(canvas, c, tag, color);
    }

    // ⑥ 指北针与比例尺。
    _north(canvas, const Offset(16, 14));
    _scaleBar(canvas, Offset(12, size.height - 10), scale);
  }

  Path _poly(List<Offset> o) {
    final p = Path()..moveTo(o.first.dx, o.first.dy);
    for (final e in o.skip(1)) {
      p.lineTo(e.dx, e.dy);
    }
    return p;
  }

  Paint _stroke(Color c, double w) => Paint()
    ..color = c
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _chevron(Canvas canvas, Offset c, Offset dir) {
    final n = Offset(-dir.dy, dir.dx);
    final tip = c + dir * 3;
    final p = Path()
      ..moveTo((c - dir * 3 + n * 3).dx, (c - dir * 3 + n * 3).dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo((c - dir * 3 - n * 3).dx, (c - dir * 3 - n * 3).dy);
    canvas.drawPath(p, _stroke(paper, 1.6));
  }

  void _endpoint(Canvas canvas, Offset c, Color color) {
    canvas
      ..drawCircle(c, 6.5, Paint()..color = Colors.white)
      ..drawCircle(c, 5, Paint()..color = color);
  }

  void _badge(Canvas canvas, Offset c, String text, Color color) {
    canvas
      ..drawCircle(c, _badgeR + 1.5, Paint()..color = Colors.white)
      ..drawCircle(c, _badgeR, Paint()..color = color);
    _text(canvas, c, text, 11, Colors.white, bold: true);
  }

  void _pill(Canvas canvas, Offset c, String text, Color color) {
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: c, width: text.length * 11 + 10, height: 16),
      const Radius.circular(8),
    );
    canvas.drawRRect(r, Paint()..color = color);
    _text(canvas, c, text, 10, Colors.white, bold: true);
  }

  void _north(Canvas canvas, Offset c) {
    final p = Path()
      ..moveTo(c.dx, c.dy - 7)
      ..lineTo(c.dx + 4.5, c.dy + 4)
      ..lineTo(c.dx, c.dy + 1.5)
      ..lineTo(c.dx - 4.5, c.dy + 4)
      ..close();
    canvas.drawPath(p, Paint()..color = label);
    _text(canvas, c + const Offset(0, 13), 'N', 9, label, bold: true);
  }

  /// 比例尺：取 1–2–5 系列中最接近 80 px 的整距离。
  void _scaleBar(Canvas canvas, Offset left, double pxPerDegLat) {
    final pxPerM = pxPerDegLat / 111320;
    const nice = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 50000];
    var m = nice.first;
    for (final n in nice) {
      if (n * pxPerM <= 90) m = n;
    }
    final len = m * pxPerM;
    final y = left.dy;
    final paint = Paint()
      ..color = label
      ..strokeWidth = 1.5;
    canvas
      ..drawLine(Offset(left.dx, y), Offset(left.dx + len, y), paint)
      ..drawLine(Offset(left.dx, y - 4), Offset(left.dx, y), paint)
      ..drawLine(Offset(left.dx + len, y - 4), Offset(left.dx + len, y), paint);
    final text = m >= 1000 ? '${m ~/ 1000} km' : '$m m';
    _text(
      canvas,
      Offset(left.dx + len + 6, y - 4),
      text,
      9,
      label,
      alignLeft: true,
    );
  }

  void _text(
    Canvas canvas,
    Offset c,
    String s,
    double size,
    Color color, {
    bool bold = false,
    bool alignLeft = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      alignLeft
          ? c - Offset(0, tp.height / 2)
          : c - Offset(tp.width / 2, tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) =>
      old.rows != rows || old.route != route || old.keyNodes != keyNodes;
}
