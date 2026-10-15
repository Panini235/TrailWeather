import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/tile_sources.dart';

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
    this.baseLayerId = defaultBaseLayerId,
    this.overlayLayers = const [],
    this.customTileSources = const [],
    this.tiandituKey = '',
    this.qweatherApiHost = '',
    this.qweatherApiKey = '',
    this.hasCompletedOnboarding = false,
    this.elevationLapseRateCorrection = true,
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

  /// 底图来源 id（见 tile_sources.dart；旧版 `basemap` 字段自动迁移）。
  final String baseLayerId;

  /// 叠加图层（自下而上）。
  final List<OverlaySelection> overlayLayers;

  /// 用户自定义瓦片来源。
  final List<TileSourceDef> customTileSources;

  /// 天地图 Key（用户自行申请，仅保存在本机）。
  final String tiandituKey;

  /// 和风天气 API Host（控制台专属域名，如 abc123.qweatherapi.com；
  /// 旧账号可为 devapi.qweather.com）。仅保存在本机。
  final String qweatherApiHost;

  /// 和风天气 API Key（仅保存在本机，不上传）。
  final String qweatherApiKey;

  bool get qweatherConfigured =>
      qweatherApiHost.trim().isNotEmpty && qweatherApiKey.trim().isNotEmpty;

  double get effectiveSamplingSpacingKm =>
      lowPower ? (samplingSpacingKm * 2).clamp(1.0, 5.0) : samplingSpacingKm;

  int get effectiveMaxNodes => lowPower ? 12 : maxNodesPerRoute;

  final bool hasCompletedOnboarding;
  final bool elevationLapseRateCorrection;

  AppSettings copyWith({
    bool? imperial,
    String? windUnit,
    ThemeMode? themeMode,
    bool? lowPower,
    List<String>? enabledProviderIds,
    double? samplingSpacingKm,
    int? maxNodesPerRoute,
    String? baseLayerId,
    List<OverlaySelection>? overlayLayers,
    List<TileSourceDef>? customTileSources,
    String? tiandituKey,
    String? qweatherApiHost,
    String? qweatherApiKey,
    bool? hasCompletedOnboarding,
    bool? elevationLapseRateCorrection,
  }) => AppSettings(
    imperial: imperial ?? this.imperial,
    windUnit: windUnit ?? this.windUnit,
    themeMode: themeMode ?? this.themeMode,
    lowPower: lowPower ?? this.lowPower,
    enabledProviderIds: enabledProviderIds ?? List.of(this.enabledProviderIds),
    samplingSpacingKm: samplingSpacingKm ?? this.samplingSpacingKm,
    maxNodesPerRoute: maxNodesPerRoute ?? this.maxNodesPerRoute,
    baseLayerId: baseLayerId ?? this.baseLayerId,
    overlayLayers: overlayLayers ?? List.of(this.overlayLayers),
    customTileSources: customTileSources ?? List.of(this.customTileSources),
    tiandituKey: tiandituKey ?? this.tiandituKey,
    qweatherApiHost: qweatherApiHost ?? this.qweatherApiHost,
    qweatherApiKey: qweatherApiKey ?? this.qweatherApiKey,
    hasCompletedOnboarding:
        hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    elevationLapseRateCorrection:
        elevationLapseRateCorrection ?? this.elevationLapseRateCorrection,
  );

  Map<String, dynamic> toJson() => {
    'imperial': imperial,
    'windUnit': windUnit,
    'themeMode': themeMode.name,
    'lowPower': lowPower,
    'enabledProviderIds': enabledProviderIds,
    'samplingSpacingKm': samplingSpacingKm,
    'maxNodesPerRoute': maxNodesPerRoute,
    'baseLayerId': baseLayerId,
    'overlayLayers': [for (final o in overlayLayers) o.toJson()],
    'customTileSources': [for (final c in customTileSources) c.toJson()],
    'tiandituKey': tiandituKey,
    'qweatherApiHost': qweatherApiHost,
    'qweatherApiKey': qweatherApiKey,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'elevationLapseRateCorrection': elevationLapseRateCorrection,
  };

  static AppSettings fromJson(Map<String, dynamic> m) => AppSettings(
    imperial: m['imperial'] as bool? ?? false,
    windUnit: m['windUnit'] as String? ?? 'km/h',
    themeMode: ThemeMode.values.byName(m['themeMode'] as String? ?? 'system'),
    lowPower: m['lowPower'] as bool? ?? false,
    enabledProviderIds:
        (m['enabledProviderIds'] as List?)?.map((e) => e as String).toList() ??
        List.of(defaultProviderIds),
    samplingSpacingKm: (m['samplingSpacingKm'] as num?)?.toDouble() ?? 1.5,
    maxNodesPerRoute: (m['maxNodesPerRoute'] as num?)?.toInt() ?? 24,
    // 旧版只存 `basemap`（amap/osm），与新 id 同名，可直接迁移。
    baseLayerId:
        m['baseLayerId'] as String? ??
        m['basemap'] as String? ??
        defaultBaseLayerId,
    overlayLayers: [
      for (final o in (m['overlayLayers'] as List?) ?? const [])
        OverlaySelection.fromJson(o as Map<String, dynamic>),
    ],
    customTileSources: [
      for (final c in (m['customTileSources'] as List?) ?? const [])
        TileSourceDef.customFromJson(c as Map<String, dynamic>),
    ],
    tiandituKey: m['tiandituKey'] as String? ?? '',
    qweatherApiHost: m['qweatherApiHost'] as String? ?? '',
    qweatherApiKey: m['qweatherApiKey'] as String? ?? '',
    hasCompletedOnboarding: m['hasCompletedOnboarding'] as bool? ?? false,
    elevationLapseRateCorrection:
        m['elevationLapseRateCorrection'] as bool? ?? true,
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

  Future<void> completeOnboarding() =>
      update(state.copyWith(hasCompletedOnboarding: true));

  Future<void> setLapseRateCorrection(bool v) =>
      update(state.copyWith(elevationLapseRateCorrection: v));

  // —— 地图图层 ——

  Future<void> setBaseLayer(String id) {
    // 新底图本身若在叠加列表中则移除，避免同一来源叠两次。
    final overlays = state.overlayLayers.where((o) => o.id != id).toList();
    return update(state.copyWith(baseLayerId: id, overlayLayers: overlays));
  }

  Future<void> toggleOverlay(String id) {
    final overlays = List.of(state.overlayLayers);
    final i = overlays.indexWhere((o) => o.id == id);
    if (i >= 0) {
      overlays.removeAt(i);
    } else {
      overlays.add(OverlaySelection(id, opacity: 0.7));
    }
    return update(state.copyWith(overlayLayers: overlays));
  }

  Future<void> setOverlayOpacity(String id, double opacity) => update(
    state.copyWith(
      overlayLayers: [
        for (final o in state.overlayLayers)
          o.id == id ? o.copyWith(opacity: opacity.clamp(0.1, 1.0)) : o,
      ],
    ),
  );

  Future<void> upsertCustomTileSource(TileSourceDef def) {
    final list = List.of(state.customTileSources);
    final i = list.indexWhere((c) => c.id == def.id);
    if (i >= 0) {
      list[i] = def;
    } else {
      list.add(def);
    }
    return update(state.copyWith(customTileSources: list));
  }

  Future<void> removeCustomTileSource(String id) => update(
    state.copyWith(
      customTileSources: state.customTileSources
          .where((c) => c.id != id)
          .toList(),
      overlayLayers: state.overlayLayers.where((o) => o.id != id).toList(),
      baseLayerId: state.baseLayerId == id
          ? defaultBaseLayerId
          : state.baseLayerId,
    ),
  );

  Future<void> setTiandituKey(String key) =>
      update(state.copyWith(tiandituKey: key.trim()));
}

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('prefsProvider 必须在 main() 中 override');
});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
