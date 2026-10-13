import 'package:flutter/material.dart';

/// 海拔剖面：距离 × 海拔。支持点击选节点（onTapNode 回调 index）。
/// 图表必须与底层真实采样点对应：直接绘制传入的节点序列，不做平滑。
class ElevationProfile extends StatelessWidget {
  const ElevationProfile({
    super.key,
    required this.distancesM,
    required this.elevationsM,
    required this.selectedIndex,
    required this.onTapNode,
  });

  final List<double> distancesM;
  final List<double?> elevationsM;
  final int selectedIndex;
  final void Function(int index) onTapNode;

  @override
  Widget build(BuildContext context) {
    final hasEle = elevationsM.any((e) => e != null);
    if (!hasEle) return const SizedBox.shrink();
    return SizedBox(
      height: 96,
      child: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onTapUp: (d) {
            final t = d.localPosition.dx / constraints.maxWidth;
            final dist = t * (distancesM.last == 0 ? 1 : distancesM.last);
            var best = 0;
            var bestD = double.infinity;
            for (var i = 0; i < distancesM.length; i++) {
              final dd = (distancesM[i] - dist).abs();
              if (dd < bestD) {
                bestD = dd;
                best = i;
              }
            }
            onTapNode(best);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ElevationPainter(
              distancesM: distancesM,
              elevationsM: elevationsM,
              selectedIndex: selectedIndex,
              lineColor: Theme.of(context).colorScheme.primary,
              fillColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
        ),
      ),
    );
  }
}

class _ElevationPainter extends CustomPainter {
  _ElevationPainter({
    required this.distancesM,
    required this.elevationsM,
    required this.selectedIndex,
    required this.lineColor,
    required this.fillColor,
  });

  final List<double> distancesM;
  final List<double?> elevationsM;
  final int selectedIndex;
  final Color lineColor;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    var minEle = double.infinity;
    var maxEle = double.negativeInfinity;
    for (final e in elevationsM) {
      if (e == null) continue;
      if (e < minEle) minEle = e;
      if (e > maxEle) maxEle = e;
    }
    if (minEle == double.infinity) return;
    if (maxEle - minEle < 10) {
      maxEle = minEle + 10; // 避免完全平坦时除零
    }
    final maxDist = distancesM.last == 0 ? 1.0 : distancesM.last;

    Offset? prev;
    final path = Path();
    final fill = Path();
    var started = false;
    for (var i = 0; i < distancesM.length; i++) {
      final e = elevationsM[i];
      if (e == null) {
        prev = null;
        continue;
      }
      final x = distancesM[i] / maxDist * size.width;
      final y = size.height -
          (e - minEle) / (maxEle - minEle) * (size.height - 12) -
          6;
      final off = Offset(x, y);
      if (!started) {
        path.moveTo(off.dx, off.dy);
        fill.moveTo(off.dx, size.height);
        fill.lineTo(off.dx, off.dy);
        started = true;
      } else if (prev != null) {
        path.lineTo(off.dx, off.dy);
        fill.lineTo(off.dx, off.dy);
      }
      prev = off;
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    final fillPaint = Paint()..color = fillColor;
    canvas.drawPath(fill, fillPaint);
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..isAntiAlias = true;
    canvas.drawPath(path, linePaint);

    // 选中节点指示
    if (selectedIndex >= 0 && selectedIndex < distancesM.length) {
      final e = elevationsM[selectedIndex];
      if (e != null) {
        final x = distancesM[selectedIndex] / maxDist * size.width;
        final y = size.height -
            (e - minEle) / (maxEle - minEle) * (size.height - 12) -
            6;
        final dot = Paint()..color = lineColor;
        canvas.drawCircle(Offset(x, y), 4, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ElevationPainter old) =>
      old.selectedIndex != selectedIndex ||
      old.distancesM.length != distancesM.length;
}
