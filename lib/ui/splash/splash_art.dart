import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// 开屏图标“观山”（assets/branding/app-icon.svg）的分层绘制与时间编排。
///
/// 坐标沿用图标的 1024 坐标系，路径与 SVG 一致，保证与启动图标同形。
abstract final class SplashArt {
  static const lightBackground = Color(0xFFF3EAD8);
  static const darkBackground = Color(0xFF18211C);
  static const sun = Color(0xFFE39441);
  static const moon = Color(0xFFE8C27A);
  static const mountain = Color(0xFF384D42);
  static const hill = Color(0xFF779078);
  static const cream = Color(0xFFF3EAD8);

  /// 山体底边：天空（太阳/月亮）只画在它上方，升起时从山后露出。
  static const horizonY = 742.0;

  /// 绘制取景：图标坐标 (112,150)–(912,950)。
  static const viewLeft = 112.0, viewTop = 150.0, viewSize = 800.0;

  /// 完整版总时长；各层在其中的区间（毫秒），见 [SplashPainter]。
  static const fullDuration = Duration(milliseconds: 1100);
  static const shortDuration = Duration(milliseconds: 250);
  static const stillHold = Duration(milliseconds: 300);
}

/// 开屏天空：按设备本地时钟摆放太阳或月亮。
///
/// 纯装饰，只读手机时钟，不定位、不联网；固定以 6–19 时为白天，
/// 不代表当地真实日出日落（真实日出日落在线路页按坐标计算）。
class SplashSky {
  const SplashSky({required this.x, required this.y, required this.night});

  factory SplashSky.at(DateTime local) {
    final h = local.hour + local.minute / 60;
    if (h < 6 || h >= 19) return const SplashSky(x: 640, y: 300, night: true);
    final t = (h - 6) / 13;
    return SplashSky(
      x: 300 + 430 * t,
      y: 470 - 140 * math.sin(math.pi * t),
      night: false,
    );
  }

  /// 圆心（图标坐标）。
  final double x, y;
  final bool night;

  double get radius => night ? 110 : 150;
}

enum SplashMode {
  /// 当天第一次冷启动：完整组装动画，可跳过。
  full,

  /// 当天再次冷启动：完整图标快速淡入。
  short,

  /// 系统减少动效或低耗电：静态图标，不做位移和缩放。
  still,
}

String splashDayKey(DateTime local) =>
    '${local.year}-${local.month.toString().padLeft(2, '0')}-'
    '${local.day.toString().padLeft(2, '0')}';

SplashMode splashModeFor({
  required DateTime local,
  required String? lastFullDay,
  required bool reduced,
}) {
  if (reduced) return SplashMode.still;
  return lastFullDay == splashDayKey(local)
      ? SplashMode.short
      : SplashMode.full;
}

/// 各层按 [progress]（0–1，对应 [SplashArt.fullDuration]）出现：
/// 山体升起 0–450 ms（200 ms 内已不透明，太阳不会透出来）→
/// 太阳/月亮从山后升到此刻位置 250–750 ms →
/// 山顶落雪 450–620 ms → 山坡滑入 380–760 ms → 小路一笔画出 600–1000 ms。
class SplashPainter extends CustomPainter {
  SplashPainter({
    required this.progress,
    required this.sky,
    required this.background,
  }) : super(repaint: progress);

  final Animation<double> progress;
  final SplashSky sky;
  final Color background;

  static double _seg(double t, int fromMs, int toMs) {
    const total = 1100;
    final v = ((t * total - fromMs) / (toMs - fromMs)).clamp(0.0, 1.0);
    return Curves.easeOutCubic.transform(v);
  }

  static final Path _mountain = Path()
    ..moveTo(132, 742)
    ..lineTo(410, 384)
    ..quadraticBezierTo(430, 359, 450, 384)
    ..lineTo(592, 559)
    ..lineTo(695, 440)
    ..quadraticBezierTo(716, 417, 737, 442)
    ..lineTo(901, 628)
    ..lineTo(901, 778)
    ..lineTo(132, 778)
    ..close();

  static final Path _snow = Path()
    ..moveTo(427, 408)
    ..lineTo(490, 488)
    ..lineTo(425, 467)
    ..lineTo(368, 495)
    ..close();

  static final Path _hill = Path()
    ..moveTo(144, 748)
    ..quadraticBezierTo(313, 599, 497, 687)
    ..quadraticBezierTo(636, 754, 892, 635)
    ..lineTo(892, 796)
    ..lineTo(144, 796)
    ..close();

  static final Path _trail = Path()
    ..moveTo(188, 817)
    ..quadraticBezierTo(351, 705, 473, 767)
    ..quadraticBezierTo(595, 829, 837, 720);

  static final PathMetric _trailMetric = _trail.computeMetrics().first;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    canvas
      ..save()
      ..scale(size.width / SplashArt.viewSize)
      ..translate(-SplashArt.viewLeft, -SplashArt.viewTop);

    // 天空：裁到山体底边以上，从山后升起。
    final skyP = _seg(t, 250, 750);
    final hidden = SplashArt.horizonY - (sky.y - sky.radius);
    canvas
      ..save()
      ..clipRect(const Rect.fromLTRB(0, 0, 1024, SplashArt.horizonY))
      ..translate(0, (1 - skyP) * hidden);
    final center = Offset(sky.x, sky.y);
    if (sky.night) {
      canvas
        ..drawCircle(center, sky.radius, Paint()..color = SplashArt.moon)
        ..drawCircle(
          center.translate(55, -35),
          95,
          Paint()..color = background,
        );
    } else {
      canvas.drawCircle(center, sky.radius, Paint()..color = SplashArt.sun);
    }
    canvas.restore();

    final mountainP = _seg(t, 0, 450);
    final mountainAlpha = _seg(t, 0, 200);
    canvas
      ..save()
      ..translate(0, (1 - mountainP) * 120)
      ..drawPath(
        _mountain,
        Paint()..color = SplashArt.mountain.withValues(alpha: mountainAlpha),
      );
    final snowP = _seg(t, 450, 620);
    if (snowP > 0) {
      canvas
        ..translate(427, 408)
        ..scale(0.2 + 0.8 * snowP)
        ..translate(-427, -408)
        ..drawPath(
          _snow,
          Paint()..color = SplashArt.cream.withValues(alpha: snowP),
        );
    }
    canvas.restore();

    final hillP = _seg(t, 380, 760);
    canvas
      ..save()
      ..translate((1 - hillP) * -60, 0)
      ..drawPath(
        _hill,
        Paint()..color = SplashArt.hill.withValues(alpha: hillP),
      )
      ..restore();

    final trailP = _seg(t, 600, 1000);
    if (trailP > 0) {
      canvas.drawPath(
        _trailMetric.extractPath(0, _trailMetric.length * trailP),
        Paint()
          ..color = SplashArt.cream
          ..style = PaintingStyle.stroke
          ..strokeWidth = 35
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SplashPainter old) =>
      old.progress != progress ||
      old.sky != sky ||
      old.background != background;
}
