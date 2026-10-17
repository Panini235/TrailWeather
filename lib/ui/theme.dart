import 'package:flutter/material.dart';

import 'tokens.dart';

/// 户外高对比主题：深浅色两套，取色自品牌“山与天”（lib/ui/tokens.dart）。
class AppTheme {
  static const seed = Palette.pine;

  static ThemeData light() =>
      _base(ColorScheme.fromSeed(seedColor: seed, surface: Palette.paper));

  static ThemeData dark() => _base(
    ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: Palette.ink,
    ),
  );

  static ThemeData _base(ColorScheme scheme) {
    final t = ThemeData(colorScheme: scheme);
    return t.copyWith(
      visualDensity: VisualDensity.standard,
      // 不覆盖 labelStyle：只给字号会丢掉 Material 3 按状态给出的文字颜色，
      // 深色模式下 Chip 文字变成深色压在深色底上几乎看不见（实机走查发现）。
      chipTheme: t.chipTheme.copyWith(
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
