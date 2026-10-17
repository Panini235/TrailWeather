import 'dart:convert';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/tile_sources.dart';
import '../weather/departure_windows.dart';

/// 单位与偏好设置。
class AppSettings {
  const AppSettings({
    this.departureThresholds = const DepartureThresholds(),
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
    this.tiandituServerKey = '',
    this.tiandituBrowserKey = '',
    this.qweatherApiHost = '',
    this.qweatherApiKey = '',
    this.hasCompletedOnboarding = false,
    this.privacyAcceptedVersion = 0,
    this.elevationLapseRateCorrection = true,
    this.routeMapLayerId = '',
    this.coldSensitivity = 0,
  });

  /// 隐私说明版本。说明内容有实质变化时 +1，已同意旧版的用户会再次看到并确认。
  static const privacyNoticeVersion = 1;

  static const defaultProviderIds = <String>[
    'open-meteo:best_match',
    'open-meteo:ecmwf_ifs025',
    'met.no:locationforecast2.0',
  ];

  final DepartureThresholds departureThresholds;
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

  /// 天地图“服务端”Key：Android/iOS 原生地图使用（用户自行申请，仅保存在本机）。
  final String tiandituServerKey;

  /// 天地图“浏览器端”Key：Web 与将来的 3D WebView 使用（仅保存在本机）。
  final String tiandituBrowserKey;

  TiandituKeys get tiandituKeys =>
      TiandituKeys(server: tiandituServerKey, browser: tiandituBrowserKey);

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

  /// 用户已同意的隐私说明版本（0 = 未同意）。
  final int privacyAcceptedVersion;

  bool get privacyAccepted => privacyAcceptedVersion >= privacyNoticeVersion;

  final bool elevationLapseRateCorrection;

  /// 线路详情小地图的图层：空串 = 跟随地图设置；否则为限定的平面地形图层 id
  /// （等高线 / 地形晕渲，见 lib/ui/detail/detail_map.dart）。
  final String routeMapLayerId;

  /// 穿衣建议的体感偏好：-1 怕冷、0 适中、1 怕热（体感阈值平移 ±3 ℃）。
  final int coldSensitivity;

  AppSettings copyWith({
    DepartureThresholds? departureThresholds,
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
    String? tiandituServerKey,
    String? tiandituBrowserKey,
    String? qweatherApiHost,
    String? qweatherApiKey,
    bool? hasCompletedOnboarding,
    int? privacyAcceptedVersion,
    bool? elevationLapseRateCorrection,
    String? routeMapLayerId,
    int? coldSensitivity,
  }) => AppSettings(
    departureThresholds: departureThresholds ?? this.departureThresholds,
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
    tiandituServerKey: tiandituServerKey ?? this.tiandituServerKey,
    tiandituBrowserKey: tiandituBrowserKey ?? this.tiandituBrowserKey,
    qweatherApiHost: qweatherApiHost ?? this.qweatherApiHost,
    qweatherApiKey: qweatherApiKey ?? this.qweatherApiKey,
    hasCompletedOnboarding:
        hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    privacyAcceptedVersion:
        privacyAcceptedVersion ?? this.privacyAcceptedVersion,
    elevationLapseRateCorrection:
        elevationLapseRateCorrection ?? this.elevationLapseRateCorrection,
    routeMapLayerId: routeMapLayerId ?? this.routeMapLayerId,
    coldSensitivity: coldSensitivity ?? this.coldSensitivity,
  );

  Map<String, dynamic> toJson() => {
    'departureThresholds': departureThresholds.toJson(),
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
    'tiandituServerKey': tiandituServerKey,
    'tiandituBrowserKey': tiandituBrowserKey,
    'qweatherApiHost': qweatherApiHost,
    'qweatherApiKey': qweatherApiKey,
    'hasCompletedOnboarding': hasCompletedOnboarding,
    'privacyAcceptedVersion': privacyAcceptedVersion,
    'elevationLapseRateCorrection': elevationLapseRateCorrection,
    'routeMapLayerId': routeMapLayerId,
    'coldSensitivity': coldSensitivity,
  };

  static AppSettings fromJson(Map<String, dynamic> m) => AppSettings(
    departureThresholds: DepartureThresholds.fromJson(m['departureThresholds']),
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
    tiandituServerKey: _tiandituKeyFromJson(m, 'tiandituServerKey'),
    tiandituBrowserKey: _tiandituKeyFromJson(m, 'tiandituBrowserKey'),
    qweatherApiHost: m['qweatherApiHost'] as String? ?? '',
    qweatherApiKey: m['qweatherApiKey'] as String? ?? '',
    hasCompletedOnboarding: m['hasCompletedOnboarding'] as bool? ?? false,
    privacyAcceptedVersion: (m['privacyAcceptedVersion'] as num?)?.toInt() ?? 0,
    elevationLapseRateCorrection:
        m['elevationLapseRateCorrection'] as bool? ?? true,
    routeMapLayerId: m['routeMapLayerId'] as String? ?? '',
    coldSensitivity: ((m['coldSensitivity'] as num?)?.toInt() ?? 0).clamp(-1, 1),
  );

  /// 旧版只有一个 `tiandituKey`，无法离线判断它是服务端还是浏览器端类型
  /// （类型只在天地图服务端可知）。迁移时两栏都填旧值：原本能出图的那一端
  /// 不受影响；另一端会收到 301012/301013，地图上按错误码提示该换哪一栏，
  /// Key 设置卡片也会提示“两栏相同”（见 D-023）。保存后旧字段不再写出。
  static String _tiandituKeyFromJson(Map<String, dynamic> m, String field) {
    final migrated =
        !m.containsKey('tiandituServerKey') &&
        !m.containsKey('tiandituBrowserKey');
    return (migrated ? m['tiandituKey'] : m[field]) as String? ?? '';
  }
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

  Future<void> acceptPrivacy() => update(
    state.copyWith(privacyAcceptedVersion: AppSettings.privacyNoticeVersion),
  );

  Future<void> setRouteMapLayer(String id) =>
      update(state.copyWith(routeMapLayerId: id));

  Future<void> setColdSensitivity(int v) =>
      update(state.copyWith(coldSensitivity: v.clamp(-1, 1)));

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

  Future<void> setTiandituKeys({
    required String server,
    required String browser,
  }) => update(
    state.copyWith(
      tiandituServerKey: server.trim(),
      tiandituBrowserKey: browser.trim(),
    ),
  );
}

final prefsProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('prefsProvider 必须在 main() 中 override');
});

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
