import 'package:flutter/material.dart';

/// 设计 token（docs/review-2026-10-16.md 第 7 节，D-032）。
///
/// 颜色只在这里定义；页面用主题 [ColorScheme] 或下面的语义色，不再直接写十六进制。
/// 对比度用 WCAG 公式核算过，数值写在各项注释里。

/// 品牌色：来自“观山”图标（assets/branding/app-icon.svg）。
abstract final class Palette {
  static const cream = Color(0xFFF3EAD8);
  static const pine = Color(0xFF384D42);
  static const sage = Color(0xFF779078);
  static const sun = Color(0xFFE39441);

  /// 深色模式与开屏的夜色底。
  static const night = Color(0xFF18211C);

  /// 浅色 / 深色界面底色（比 cream 更淡、比 night 更深，保证正文对比度）。
  static const paper = Color(0xFFFBF8F1);
  static const ink = Color(0xFF121915);
}

/// 语义色。标记色用于图标、地图标记和色带，深浅主题共用一套（地图底图始终是浅色）；
/// 文字要用 [SemanticInk]，按深浅主题取不同色值。
abstract final class Semantic {
  /// 红色阈值、终点、危险标记。白底 5.4:1。
  static const danger = Color(0xFFC0392B);

  /// 黄色阈值。图形上要配白色描边或图标（白底只有 2.3:1）。
  static const caution = Color(0xFFE0A100);

  /// 未触发阈值、起点。白底 4.9:1。
  static const go = Color(0xFF3F7D4E);

  /// 低温提示。白底 4.7:1。
  static const cold = Color(0xFF3B78A8);

  /// 冰冻（0 ℃ 上下）。
  static const ice = Color(0xFF2A9BAF);

  /// 数据不足 / 无数据。
  static const unknown = Color(0xFF9A9F9B);

  /// 地图上的线路。白底 6.1:1，与绿色起点、红色终点区分。
  static const route = Color(0xFF2F62A8);

  /// 地图上的其他线路：徒步星球、OSM 区域线路（半透明叠加）。
  static const planetRoute = Color(0xCC3F7D4E);
  static const osmRoute = Color(0xCC7B4FA0);

  /// 黄色阈值的容器底色（浅 / 深），配 [SemanticInk.caution]。
  static const cautionContainerLight = Color(0xFFFBE9B7);
  static const cautionContainerDark = Color(0xFF3D3008);
}

/// 语义文字色：浅色底 ≥5.7:1，深色底 ≥7.7:1（含 12% 同色底）。
abstract final class SemanticInk {
  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;

  static Color danger(BuildContext c) =>
      _dark(c) ? const Color(0xFFFF9A8A) : const Color(0xFFA32A1E);
  static Color caution(BuildContext c) =>
      _dark(c) ? const Color(0xFFF2C45A) : const Color(0xFF7A5200);
  static Color go(BuildContext c) =>
      _dark(c) ? const Color(0xFF8FCB9B) : const Color(0xFF2F6040);
  static Color cold(BuildContext c) =>
      _dark(c) ? const Color(0xFF8FC1E8) : const Color(0xFF2C5F87);
  static Color info(BuildContext c) =>
      _dark(c) ? const Color(0xFFB6C4BC) : const Color(0xFF4F5F58);

  /// 分享卡等固定浅色背景上的文字色。
  static const dangerOnLight = Color(0xFFA32A1E);
  static const cautionOnLight = Color(0xFF7A5200);
  static const goOnLight = Color(0xFF2F6040);
  static const infoOnLight = Color(0xFF4F5F58);
}

/// 间距（4 的倍数）。
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// 圆角。
abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}
