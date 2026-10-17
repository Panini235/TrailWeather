import 'package:flutter/widgets.dart';

/// 动效 token 与降级规则（docs/review-2026-10-16.md 第 7 节，D-031）。
///
/// - 只在状态变化或手势时动，静止时不画帧；不使用无限循环动画。
/// - 系统“减少动效”或 App 低耗电模式下不做位移/缩放编排，直接显示终态。
/// - 动效不能伪造数据：数值不从 0 计数上来，不用“实时”呼吸灯表示预报。
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const emphasis = Duration(milliseconds: 600);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;

  /// 是否应降级为无动画（系统减少动效或低耗电）。
  static bool reduced(BuildContext context, {bool lowPower = false}) =>
      lowPower || (MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  /// 按降级规则取时长：降级时为 0。
  static Duration of(
    BuildContext context,
    Duration duration, {
    bool lowPower = false,
  }) => reduced(context, lowPower: lowPower) ? Duration.zero : duration;
}
