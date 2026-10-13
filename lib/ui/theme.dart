import 'package:flutter/material.dart';

/// 户外高对比主题：深浅色两套。
class AppTheme {
  static const seed = Color(0xFF2E5D32);

  static ThemeData light() => _base(ColorScheme.fromSeed(seedColor: seed));

  static ThemeData dark() => _base(
        ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
      );

  static ThemeData _base(ColorScheme scheme) {
    final t = ThemeData(colorScheme: scheme);
    return t.copyWith(
      visualDensity: VisualDensity.standard,
      chipTheme: t.chipTheme.copyWith(
        labelStyle: const TextStyle(fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
