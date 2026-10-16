import 'package:flutter/material.dart';

/// 户外高对比主题：深浅色两套。
class AppTheme {
  static const seed = Color(0xFF2E5D32);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: seed));

  static ThemeData dark() =>
      _base(ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark));

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
