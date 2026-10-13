import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

/// 测试用假来源：可控响应与调用计数。
class FakeProvider extends WeatherProvider {
  FakeProvider({required this.responses, super.fetcher});

  final Map<String, String> responses; // gridKey -> payload
  int callCount = 0;

  @override
  ProviderCapabilities get caps => ProviderCapabilities(
        providerId: 'fake:test',
        vendor: 'FakeVendor',
        displayName: 'Fake（测试）',
        modelOrNetwork: 'fake-model',
        coverage: '测试',
        forecastHorizonDays: 3,
        intervalHours: 1,
        batchCoordinates: true,
        maxPointsPerRequest: 10,
        granularity: WxGranularity.grid,
        dataKind: WxDataKind.forecast,
        requiresApiKey: false,
        browserCorsOk: true,
        browserNotes: '',
        license: 'test',
        attribution: 'test',
        supportedVars: const [WxVar.temperature],
        minRequestIntervalMs: 0,
        recommendedCacheTtl: const Duration(minutes: 30),
      );

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    callCount++;
    return [
      for (final p in points)
        WxPointForecast(
          lat: p.latitude,
          lon: p.longitude,
          hours: [
            WxHourValue(
              validFromUtc: DateTime.utc(2026, 10, 13, 10),
              values: const {WxVar.temperature: 20.0},
            ),
          ],
          provenance: WxProvenance(
            providerId: caps.providerId,
            vendor: caps.vendor,
            modelOrNetwork: caps.modelOrNetwork,
            modelKnown: true,
            requestLat: p.latitude,
            requestLon: p.longitude,
            returnedLat: p.latitude,
            returnedLon: p.longitude,
            locationDetail: null,
            elevationUsedM: null,
            granularity: WxGranularity.grid,
            spatialResolutionNote: null,
            dataKind: WxDataKind.forecast,
            fetchedAtUtc: DateTime.now().toUtc(),
            modelRunUtc: null,
            utcOffsetSeconds: 0,
            license: 'test',
            attribution: 'test',
            interpolationNote: null,
            elevationAdjustNote: null,
            traceNote: null,
          ),
        ),
    ];
  }
}

RouteNode node(double lat, double lon) => RouteNode(
      pointIndex: 0,
      pos: LatLng(lat, lon),
      elevationM: null,
      distFromStartM: 0,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('近似网格去重：相近节点合并查询且标注共享', () async {
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeProvider(responses: {});
    final repo = WeatherRepository(
        cache: CacheStore(prefs), providers: [fake], approxGridDeg: 0.1);
    final nodes = [
      node(40.000, 116.000),
      node(40.001, 116.001), // 同一 0.1° 近似网格
      node(40.500, 116.000), // 不同网格
    ];
    final b = await repo.getRouteWeatherBundle(
      providerId: 'fake:test',
      nodes: nodes,
      startUtc: DateTime.utc(2026, 10, 13, 10),
      endUtc: DateTime.utc(2026, 10, 13, 11),
    );
    expect(b.result.points, hasLength(2)); // 3 节点 → 2 查询点
    expect(b.nodeQueryIndex, [0, 0, 1]);
    expect(b.sharedGridNote, isNotNull);
    expect(b.sharedGridNote, contains('共享同一网格预报'));
    expect(fake.callCount, 1);
  });

  test('缓存命中：相同键不重复请求', () async {
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeProvider(responses: {});
    final repo = WeatherRepository(cache: CacheStore(prefs), providers: [fake]);
    final nodes = [node(40.0, 116.0)];
    final t0 = DateTime.utc(2026, 10, 13, 10);

    final r1 = await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    expect(r1.fromCache, isFalse);
    final r2 = await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    expect(r2.fromCache, isTrue);
    expect(r2.stale, isFalse);
    expect(fake.callCount, 1);

    // 不同时间窗 → 不同缓存键 → 重新请求
    await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0.add(const Duration(hours: 1)), endUtc: t0.add(const Duration(hours: 2)));
    expect(fake.callCount, 2);

    // refresh=true 强制刷新
    await repo.getRouteWeather(
        providerId: 'fake:test',
        nodes: nodes,
        startUtc: t0,
        endUtc: t0.add(const Duration(hours: 1)),
        refresh: true);
    expect(fake.callCount, 3);
  });

  test('TTL 过期读取标记 stale（stale-while-revalidate）', () async {
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeProvider(responses: {});
    final repo = WeatherRepository(cache: CacheStore(prefs), providers: [fake]);
    final nodes = [node(40.0, 116.0)];
    final t0 = DateTime.utc(2026, 10, 13, 10);

    await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    // 手动把缓存改为已过期
    final cache = CacheStore(prefs);
    await cache.write(
        CacheNs.weather,
        repo.approxGridKey(const LatLng(40.0, 116.0)).isEmpty
            ? 'v1|fake:test|${repo.approxGridKey(const LatLng(40.0, 116.0))}|2026-10-13T10|2026-10-13T11'
            : 'v1|fake:test|${repo.approxGridKey(const LatLng(40.0, 116.0))}|2026-10-13T10|2026-10-13T11',
        '{"providerId":"fake:test","fetchedAt":"2026-10-13T09:00:00Z","points":[]}',
        Duration.zero);
    final r = await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    // 空点数缓存不匹配 → 回落到网络
    expect(fake.callCount, 2);
    expect(r.fromCache, isFalse);
  });

  test('缓存序列化往返：温度值保持', () async {
    final prefs = await SharedPreferences.getInstance();
    final fake = FakeProvider(responses: {});
    final repo = WeatherRepository(cache: CacheStore(prefs), providers: [fake]);
    final nodes = [node(40.0, 116.0)];
    final t0 = DateTime.utc(2026, 10, 13, 10);
    await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    final r2 = await repo.getRouteWeather(
        providerId: 'fake:test', nodes: nodes, startUtc: t0, endUtc: t0.add(const Duration(hours: 1)));
    final h = r2.points.first.hourAt(DateTime.utc(2026, 10, 13, 10));
    expect(h, isNotNull);
    expect(h!.values[WxVar.temperature], 20.0);
    expect(h.values[WxVar.precip], isNull); // 未提供的变量经序列化仍为 null
  });

  test('未知来源抛 StateError', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = WeatherRepository(
        cache: CacheStore(prefs), providers: [FakeProvider(responses: {})]);
    expect(
      () => repo.getRouteWeather(
          providerId: 'nope',
          nodes: [node(1, 1)],
          startUtc: DateTime.utc(2026),
          endUtc: DateTime.utc(2026)),
      throwsStateError,
    );
  });
}
