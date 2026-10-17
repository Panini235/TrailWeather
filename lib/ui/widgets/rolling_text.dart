import 'package:flutter/material.dart';

import '../motion.dart';

/// 数值换新时旧值上滑淡出、新值自下滑入（D-031 动效规则）。
///
/// 只在两个真实值之间切换，不做数字插值计数：过渡中不会出现不存在的中间值。
/// 系统减少动效或低耗电时直接替换。
class RollingText extends StatelessWidget {
  const RollingText(this.text, {super.key, this.style, this.lowPower = false});

  final String text;
  final TextStyle? style;
  final bool lowPower;

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context, lowPower: lowPower)) {
      return Text(text, style: style);
    }
    final key = ValueKey(text);
    return AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, ?current],
      ),
      transitionBuilder: (child, animation) {
        final incoming = child.key == key;
        return ClipRect(
          child: SlideTransition(
            position: Tween(
              begin: Offset(0, incoming ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(animation),
            child: FadeTransition(opacity: animation, child: child),
          ),
        );
      },
      child: Text(text, key: key, style: style),
    );
  }
}
