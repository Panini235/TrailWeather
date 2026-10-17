import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache_store.dart';
import '../core/external_url_launcher.dart';
import 'geocode.dart';
import 'location/location_service.dart';
import 'routes/overpass.dart';
import 'routes/route_models.dart';
import 'routes/sample_routes.dart';
import 'settings/favorites_repository.dart';
import 'settings/settings_repository.dart';
import 'weather/air_quality.dart';
import 'weather/altitude_profile.dart';
import 'weather/met_norway_provider.dart';
import 'weather/meteoblue_provider.dart';
import 'weather/meteoblue_settings.dart';
import 'weather/open_meteo_provider.dart';
import 'weather/qweather_provider.dart';
import 'weather/satellite_frames.dart';
import 'weather/weather_field.dart';
import 'weather/weather_provider.dart';
import 'weather/weather_repository.dart';

final locationServiceProvider = Provider<LocationService>(
  (ref) => const GeolocatorLocationService(),
);

final geocodeServiceProvider = Provider<GeocodeService>(
  (ref) => GeocodeService(),
);

final externalUrlLauncherProvider = Provider<ExternalUrlLauncher>(
  (ref) => const SystemExternalUrlLauncher(),
);

final overpassRouteSourceProvider = Provider<OverpassRouteSource>(
  (ref) => OverpassRouteSource(),
);

/// 已接入的真实天气来源注册表。
/// 顺序即 UI 默认主来源顺序。和风（大陆直连）需在设置中配置 API Host/Key，
/// 未配置时仍注册但请求会给出明确的配置指引。
List<WeatherProvider> defaultWeatherProviders({
  String qweatherApiHost = '',
  String qweatherApiKey = '',
  String meteoblueApiKey = '',
  void Function()? onMeteoblueCall,
}) => [
  OpenMeteoProvider(model: 'best_match'),
  OpenMeteoProvider(model: 'ecmwf_ifs025'),
  MetNorwayProvider(),
  QWeatherProvider(apiHost: qweatherApiHost, apiKey: qweatherApiKey),
  // 按次计费，只在用户点击时单点查询（caps.onDemandOnly）。
  MeteoblueProvider(apiKey: meteoblueApiKey, onNetworkCall: onMeteoblueCall),
];

final airQualityServiceProvider = Provider<AirQualityService>(
  (ref) => AirQualityService(),
);

final altitudeProfileServiceProvider = Provider<AltitudeProfileService>(
  (ref) => AltitudeProfileService(),
);

/// 地图页天气图：降水/云量格点场（Open-Meteo）与卫星云图帧（NASA GIBS）。
final weatherFieldServiceProvider = Provider<WeatherFieldService>(
  (ref) => WeatherFieldService(),
);

final satelliteFrameServiceProvider = Provider<SatelliteFrameService>(
  (ref) => SatelliteFrameService(),
);

/// 自动请求（线路天气、首页位置天气）用的主来源：已启用、且不是按次计费的按需来源。
String primaryProviderId(
  List<String> enabledIds,
  List<WeatherProvider> providers,
) {
  final auto = providers.where((p) => !p.caps.onDemandOnly).toList();
  return enabledIds.firstWhere(
    (e) => auto.any((p) => p.caps.providerId == e),
    orElse: () => auto.first.caps.providerId,
  );
}

final weatherProvidersProvider = Provider<List<WeatherProvider>>((ref) {
  final credentials = ref.watch(
    settingsProvider.select((s) => (s.qweatherApiHost, s.qweatherApiKey)),
  );
  // 只监听 key：调用计数变化不应重建来源列表（否则会连带刷新所有天气请求）。
  final mbKey = ref.watch(meteoblueSettingsProvider.select((s) => s.apiKey));
  return defaultWeatherProviders(
    qweatherApiHost: credentials.$1,
    qweatherApiKey: credentials.$2,
    meteoblueApiKey: mbKey,
    onMeteoblueCall: () =>
        ref.read(meteoblueSettingsProvider.notifier).recordCall(),
  );
});

/// 可测试的当前时钟；定位时间与天气查询时间分别记录。
final weatherNowProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(
    cache: CacheStore(ref.watch(prefsProvider)),
    providers: ref.watch(weatherProvidersProvider),
  );
});

final sampleRoutesProvider = FutureProvider<List<HikingRoute>>((ref) async {
  return SampleRoutes().loadAll();
});

/// 全部本地线路（示例 + 收藏/导入）。
final localRoutesProvider = Provider<List<HikingRoute>>((ref) {
  final samples = ref.watch(sampleRoutesProvider).value ?? const [];
  final favs = ref.watch(favoritesProvider);
  return [...samples, ...favs];
});
