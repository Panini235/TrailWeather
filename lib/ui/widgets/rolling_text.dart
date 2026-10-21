import 'package:flutter/material.dart';

import '../motion.dart';

/// 数值换新时旧值上滑淡出、新值自下滑入（D-031 动效规则）。
///
/// 只在两个真实值之间切换，不做数字插值计数：过渡中不会出现不存在的中间值。
/// 系统减少动效或低耗电时直接替换。
class RollingText extends StatelessWidget {
  const RollingText(
    this.text, {
    super.key,
    this.style,
    this.unitStyle,
    this.lowPower = false,
  });

  final String text;
  final TextStyle? style;

  /// 可选：弱化末尾空格后的单位，仍将完整读数作为一次切换。
  final TextStyle? unitStyle;
  final bool lowPower;

  Widget _value({Key? key}) {
    final split = unitStyle == null ? -1 : text.lastIndexOf(' ');
    if (split <= 0) return Text(text, key: key, style: style);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: text.substring(0, split)),
          TextSpan(text: text.substring(split), style: unitStyle),
        ],
      ),
      key: key,
      style: style,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Motion.reduced(context, lowPower: lowPower)) {
      return _value();
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
      child: _value(key: key),
    );
  }
}
