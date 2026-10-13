import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 单位与偏好设置。
class AppSettings {
  const AppSettings({
    this.imperial = false,
    this.windUnit = 'km/h',
    this.themeMode = ThemeMode.system,
    this.lowPower = false,
    this.enabledProviderIds = defaultProviderIds,
    this.samplingSpacingKm = 1.5,
    this.maxNodesPerRoute = 24,
  });

  static const defaultProviderIds = <String>[
    'open-meteo:best_match',
    'open-meteo:ecmwf_ifs025',
    'met.no:locationforecast2.0',
  ];

  final bool imperial;
  final String windUnit;
  final ThemeMode themeMode;

  /// 低耗电模式：降低自动刷新与采样开销（加大采样间距）。
  final bool lowPower;

  final List<String> enabledProviderIds;
  final double samplingSpacingKm;
  final int maxNodesPerRoute;

  double get effectiveSamplingSpacingKm =>
      lowPower ? (samplingSpacingKm * 2).clamp(1.0, 5.0) : samplingSpacingKm;

  int get effectiveMaxNodes => lowPower ? 12 : maxNodesPerRoute;

  AppSettings copyWith({
    bool? imperial,
    String? windUnit,
    ThemeMode? themeMode,
    bool? lowPower,
    List<String>? enabledProviderIds,
    double? samplingSpacingKm,
    int? maxNodesPerRoute,
  }) =>
      AppSettings(
        imperial: imperial ?? this.imperial,
        windUnit: windUnit ?? this.windUnit,
        themeMode: themeMode ?? this.themeMode,
        lowPower: lowPower ?? this.lowPower,
        enabledProviderIds:
            enabledProviderIds ?? List.of(this.enabledProviderIds),
        samplingSpacingKm: samplingSpacingKm ?? this.samplingSpacingKm,
        maxNodesPerRoute: maxNodesPerRoute ?? this.maxNodesPerRoute,
      );

  Map<String, dynamic> toJson() => {
        'imperial': imperial,
        'windUnit': windUnit,
        'themeMode': themeMode.name,
        'lowPower': lowPower,
        'enabledProviderIds': enabledProviderIds,
        'samplingSpacingKm': samplingSpacingKm,
        'maxNodesPerRoute': maxNodesPerRoute,
      };

  static AppSettings fromJson(Map<String, dynamic> m) => AppSettings(
        imperial: m['imperial'] as bool? ?? false,
        windUnit: m['windUnit'] as String? ?? 'km/h',
        themeMode: ThemeMode.values
                .byName(m['themeMode'] as String? ?? 'system'),
        lowPower: m['lowPower'] as bool? ?? false,
        enabledProviderIds: (m['enabledProviderIds'] as List?)
                ?.map((e) => e as String)
                .toList() ??
            List.of(defaultProviderIds),
        samplingSpacingKm: (m['samplingSpacingKm'] as num?)?.toDouble() ?? 1.5,
        maxNodesPerRoute: (m['maxNodesPerRoute'] as num?)?.toInt() ?? 24,
      );
}

/// 设置状态：持久化到 shared_preferences（user 命名空间，不属于缓存）。
class SettingsNotifier extends Notifier<AppSettings> {
  static const _key = 'settings.v1';

  @override
  AppSettings build() {
    final prefs = ref.read(prefsProvider);
    final raw = prefs.getString(_key);
    if (raw == null) return const AppSettings();
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> _save(AppSettings s) async {
    final prefs = ref.read(prefsProvider);
    await prefs.setString(_key, jsonEncode(s.toJson()));
  }

  Future<void> update(AppSettings s) async {
    state = s;
    await _save(s);
  }

  Future<void> toggleProvider(String id) async {
    final ids = List.of(state.enabledProviderIds);
    if (ids.contains(id)) {
      if (ids.length <= 1) return; // 至少保留一个来源
      ids.remove(id);
    } else {
      ids.add(id);
    }
    await update(state.copyWith(enabledProviderIds: ids));
  }

  Future<void> setLowPower(bool v) => update(state.copyWith(lowPower: v));
}

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('prefsProvider 必须在 main() 中 override');
});

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
