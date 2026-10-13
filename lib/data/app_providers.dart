import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/cache_store.dart';
import 'routes/route_models.dart';
import 'routes/sample_routes.dart';
import 'settings/favorites_repository.dart';
import 'settings/settings_repository.dart';
import 'weather/met_norway_provider.dart';
import 'weather/open_meteo_provider.dart';
import 'weather/qweather_provider.dart';
import 'weather/weather_provider.dart';
import 'weather/weather_repository.dart';

/// 已接入的真实天气来源注册表。
/// 顺序即 UI 默认主来源顺序。和风（大陆直连）需在设置中配置 API Host/Key，
/// 未配置时仍注册但请求会给出明确的配置指引。
List<WeatherProvider> defaultWeatherProviders({String qweatherApiHost = '', String qweatherApiKey = ''}) =>
    [
      OpenMeteoProvider(model: 'best_match'),
      OpenMeteoProvider(model: 'ecmwf_ifs025'),
      MetNorwayProvider(),
      QWeatherProvider(apiHost: qweatherApiHost, apiKey: qweatherApiKey),
    ];

final weatherProvidersProvider = Provider<List<WeatherProvider>>((ref) {
  final settings = ref.watch(settingsProvider);
  return defaultWeatherProviders(
    qweatherApiHost: settings.qweatherApiHost,
    qweatherApiKey: settings.qweatherApiKey,
  );
});

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
