import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../core/geo.dart';
import '../../data/routes/route_models.dart';
import '../../data/weather/node_wx_class.dart';
import '../../data/weather/risk_rules.dart';
import '../detail/detail_state.dart';
import '../detail/node_wx_style.dart';

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

Color hintColor(WxHint h) => switch (h.level) {
  HintLevel.warning => const Color(0xFFC62828),
  HintLevel.caution => const Color(0xFFE65100),
  HintLevel.info => const Color(0xFF546E7A),
};

/// 线路示意图（不含地图瓦片）：按经纬度等比例投影，北向上；
/// 节点按天气类别着色，关键节点标编号，起终点用绿/红。
class RouteSketch extends StatelessWidget {
  const RouteSketch({
    super.key,
    required this.route,
    required this.rows,
    required this.keyNodes,
    this.height = 170,
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
          segments: route.segments,
          rows: rows,
          keyNodes: keyNodes,
          line: scheme.primary,
          loop: route.isLoop,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _SketchPainter extends CustomPainter {
  _SketchPainter({
    required this.segments,
    required this.rows,
    required this.keyNodes,
    required this.line,
    required this.loop,
  });

  final List<List<LatLng>> segments;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;
  final Color line;
  final bool loop;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = [for (final s in segments) ...s];
    if (pts.length < 2) return;
    var minLat = pts.first.latitude, maxLat = minLat;
    var minLon = pts.first.longitude, maxLon = minLon;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLon = math.min(minLon, p.longitude);
      maxLon = math.max(maxLon, p.longitude);
    }
    // 经度按纬度余弦缩放，保持形状不变形。
    final k = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLon - minLon) * k, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    const pad = 22.0;
    final scale = math.min(
      (size.width - 2 * pad) / w,
      (size.height - 2 * pad) / h,
    );
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;
    Offset at(LatLng p) => Offset(
      ox + (p.longitude - minLon) * k * scale,
      oy + (maxLat - p.latitude) * scale,
    );

    final stroke = Paint()
      ..color = line
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final s in segments) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(at(s.first).dx, at(s.first).dy);
      for (final p in s.skip(1)) {
        path.lineTo(at(p).dx, at(p).dy);
      }
      canvas.drawPath(path, stroke);
    }

    // 普通节点：天气类别色小圆点；关键节点：编号徽章。
    for (var i = 0; i < rows.length; i++) {
      if (keyNodes.contains(i)) continue;
      final c = nodeWxColor(classifyNodeWx(rows[i].wx));
      canvas.drawCircle(at(rows[i].node.pos), 3.5, Paint()..color = c);
    }
    for (final i in keyNodes) {
      _badge(
        canvas,
        at(rows[i].node.pos),
        '${i + 1}',
        nodeWxColor(classifyNodeWx(rows[i].wx)),
      );
    }
    // 起终点（环线合并）。
    final start = at(pts.first);
    final end = at(pts.last);
    _tag(canvas, start, loop ? '起终' : '起', const Color(0xFF2E7D32));
    if (!loop) _tag(canvas, end, '终', const Color(0xFFC62828));
  }

  void _badge(Canvas canvas, Offset c, String text, Color color) {
    canvas.drawCircle(c, 10, Paint()..color = Colors.white);
    canvas.drawCircle(c, 8.5, Paint()..color = color);
    _text(canvas, c, text, 10, Colors.white);
  }

  void _tag(Canvas canvas, Offset c, String text, Color color) {
    final o = c.translate(0, -18);
    final r = RRect.fromRectAndRadius(
      Rect.fromCenter(center: o, width: text.length * 11 + 8, height: 16),
      const Radius.circular(8),
    );
    canvas.drawRRect(r, Paint()..color = color);
    _text(canvas, o, text, 10, Colors.white);
  }

  void _text(Canvas canvas, Offset c, String s, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) =>
      old.rows != rows || old.segments != segments;
}

/// 海拔剖面（用完整轨迹海拔），关键节点在剖面上标编号、按天气着色。
class ShareElevationProfile extends StatelessWidget {
  const ShareElevationProfile({
    super.key,
    required this.route,
    required this.rows,
    required this.keyNodes,
    this.height = 84,
  });

  final HikingRoute route;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;
  final double height;

  @override
  Widget build(BuildContext context) {
    final path = route.analysisPath;
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: CustomPaint(
        size: Size.infinite,
        painter: _ProfilePainter(
          points: path.points,
          elevations: path.elevations,
          rows: rows,
          keyNodes: keyNodes,
          fill: scheme.primary.withValues(alpha: 0.18),
          line: scheme.primary,
          label: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ProfilePainter extends CustomPainter {
  _ProfilePainter({
    required this.points,
    required this.elevations,
    required this.rows,
    required this.keyNodes,
    required this.fill,
    required this.line,
    required this.label,
  });

  final List<LatLng> points;
  final List<double?> elevations;
  final List<NodeWxRow> rows;
  final List<int> keyNodes;
  final Color fill;
  final Color line;
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // 与节点 distFromStartM 同一算法，编号点才能准确落在剖面上。
    final dist = Geo.cumulativeDistancesM(points);
    final eles = [
      for (var i = 0; i < elevations.length; i++)
        if (elevations[i] != null) (dist[i], elevations[i]!),
    ];
    if (eles.length < 2) return;
    final minE = eles.map((e) => e.$2).reduce(math.min);
    final maxE = eles.map((e) => e.$2).reduce(math.max);
    final span = math.max(maxE - minE, 20);
    const left = 34.0, top = 12.0, bottom = 6.0;
    final total = math.max(dist.last, 1);
    Offset at(double x, double e) => Offset(
      left + (size.width - left - 4) * x / total,
      top + (size.height - top - bottom) * (1 - (e - minE) / span),
    );
    final p = Path()..moveTo(at(eles.first.$1, eles.first.$2).dx, size.height);
    for (final (x, e) in eles) {
      p.lineTo(at(x, e).dx, at(x, e).dy);
    }
    p
      ..lineTo(at(eles.last.$1, eles.last.$2).dx, size.height)
      ..close();
    canvas.drawPath(p, Paint()..color = fill);
    final l = Path()
      ..moveTo(
        at(eles.first.$1, eles.first.$2).dx,
        at(eles.first.$1, eles.first.$2).dy,
      );
    for (final (x, e) in eles.skip(1)) {
      l.lineTo(at(x, e).dx, at(x, e).dy);
    }
    canvas.drawPath(
      l,
      Paint()
        ..color = line
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
    _label(canvas, Offset(0, top - 6), '${maxE.round()} m');
    _label(canvas, Offset(0, size.height - bottom - 12), '${minE.round()} m');

    for (final i in keyNodes) {
      final e = rows[i].node.elevationM;
      if (e == null) continue;
      final c = at(rows[i].node.distFromStartM, e);
      canvas.drawCircle(c, 8, Paint()..color = Colors.white);
      canvas.drawCircle(
        c,
        6.5,
        Paint()..color = nodeWxColor(classifyNodeWx(rows[i].wx)),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: const TextStyle(
            fontSize: 8,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _label(Canvas canvas, Offset o, String s) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontSize: 9, color: label),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  @override
  bool shouldRepaint(covariant _ProfilePainter old) => old.rows != rows;
}
