import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;

import '../../data/routes/route_models.dart';
import '../strings.dart';

/// 只绘制本地轨迹；不初始化地图或请求瓦片，不将断开的段连接起来。
class RouteSchematic extends StatelessWidget {
  const RouteSchematic({super.key, required this.route});
  final HikingRoute route;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Text(S.offlineSchematicTitle),
      Semantics(
        image: true,
        label: S.offlineSchematicLabel(route.name, route.segments.length),
        child: SizedBox(
          height: 200,
          width: double.infinity,
          child: CustomPaint(
            painter: _RoutePainter(
              route,
              Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    ],
  );
}

class _RoutePainter extends CustomPainter {
  const _RoutePainter(this.route, this.color);
  final HikingRoute route;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final points = route.flatPoints;
    if (points.isEmpty) return;
    final origin = points.first;
    // 经度跨日界线时取相对起点的短弧，仅作为局部几何示意。
    Offset project(LatLng p) => Offset(
      ((p.longitude - origin.longitude + 540) % 360 - 180) *
          math.cos(origin.latitude * math.pi / 180),
      origin.latitude - p.latitude,
    );
    final xy = points.map(project).toList();
    final minX = xy.map((p) => p.dx).reduce(math.min);
    final maxX = xy.map((p) => p.dx).reduce(math.max);
    final minY = xy.map((p) => p.dy).reduce(math.min);
    final maxY = xy.map((p) => p.dy).reduce(math.max);
    final scale = math.min(
      (size.width - 32) / math.max(maxX - minX, 0.000001),
      (size.height - 32) / math.max(maxY - minY, 0.000001),
    );
    Offset screen(LatLng p) {
      final q = project(p);
      return Offset(
        size.width / 2 + (q.dx - (minX + maxX) / 2) * scale,
        size.height / 2 + (q.dy - (minY + maxY) / 2) * scale,
      );
    }

    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final segment in route.segments) {
      final path = Path();
      for (var i = 0; i < segment.length; i++) {
        final p = screen(segment[i]);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
    canvas.drawCircle(screen(points.first), 6, paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(screen(points.last), 4, paint);
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.route != route || oldDelegate.color != color;
}
