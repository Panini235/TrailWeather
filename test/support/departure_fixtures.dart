import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';
import 'package:trailweather/data/weather/weather_repository.dart';

final departureTestStart = DateTime.utc(2026, 10, 17, 7);
final departureTestNodes = [
  for (var i = 0; i < 2; i++)
    RouteNode(
      pointIndex: i,
      pos: LatLng(30, i * .2),
      elevationM: 100,
      distFromStartM: i * 3600,
      label: i == 0 ? '起点' : '终点',
    ),
];
final departureTestRoute = HikingRoute(
  id: 'departures',
  name: '测试出发线路',
  origin: RouteOrigin.demo,
  isDemo: true,
  sourceName: '测试',
  segments: [departureTestNodes.map((n) => n.pos).toList()],
  elevationsM: [100, 100],
);

typedef DepartureValues = Map<WxVar, double?> Function(int node, DateTime hour);

Map<WxVar, double?> clearDepartureValues(int _, DateTime _) => {
  WxVar.temperature: 15,
  WxVar.windSpeed: 5,
  WxVar.windGust: 7,
  WxVar.precip: 0,
};

RouteWeatherBundle departureBundle({
  List<RouteNode>? nodes,
  String providerId = 'test:departure',
  DepartureValues values = clearDepartureValues,
  DateTime? start,
  int hours = 160,
  bool sunsets = true,
  bool stale = false,
  bool refreshFailed = false,
  List<int>? nodeMap,
  WxDataKind kind = WxDataKind.forecast,
}) {
  final ns = nodes ?? departureTestNodes;
  final begin = start ?? departureTestStart;
  return RouteWeatherBundle(
    nodeQueryIndex: nodeMap ?? [for (var i = 0; i < ns.length; i++) i],
    result: WxSourceResult(
      providerId: providerId,
      fromCache: stale || refreshFailed,
      stale: stale,
      refreshFailed: refreshFailed,
      cachedAtUtc: null,
      fetchedAtUtc: departureTestStart.subtract(const Duration(hours: 1)),
      points: [
        for (var i = 0; i < ns.length; i++)
          WxPointForecast(
            lat: ns[i].pos.latitude,
            lon: ns[i].pos.longitude,
            hours: [
              for (var h = 0; h < hours; h++)
                WxHourValue(
                  validFromUtc: begin.add(Duration(hours: h)),
                  values: values(i, begin.add(Duration(hours: h))),
                ),
            ],
            dailySunsetsUtc: sunsets
                ? [
                    for (var d = -1; d < 10; d++)
                      DateTime.utc(2026, 10, 17 + d, 18),
                  ]
                : [],
            provenance: WxProvenance(
              providerId: providerId,
              vendor: '测试来源',
              modelOrNetwork: 'fixture-model',
              modelKnown: true,
              requestLat: ns[i].pos.latitude,
              requestLon: ns[i].pos.longitude,
              returnedLat: ns[i].pos.latitude + .01,
              returnedLon: ns[i].pos.longitude + .01,
              locationDetail: '测试返回网格',
              elevationUsedM: 120,
              granularity: WxGranularity.grid,
              spatialResolutionNote: '测试分辨率',
              dataKind: kind,
              fetchedAtUtc: departureTestStart.subtract(
                const Duration(hours: 1),
              ),
              modelRunUtc: null,
              utcOffsetSeconds: 0,
              license: '测试',
              attribution: '测试署名',
              interpolationNote: null,
              elevationAdjustNote: null,
              traceNote: null,
            ),
          ),
      ],
    ),
  );
}

class DepartureWeatherFixture extends WeatherProvider {
  int calls = 0;
  bool fail = false;
  bool onlyOnDemand = false;
  DateTime? requestedStart;
  DateTime? requestedEnd;
  @override
  ProviderCapabilities get caps => ProviderCapabilities(
    providerId: 'test:departure',
    vendor: '测试来源',
    displayName: '测试天气',
    modelOrNetwork: 'fixture-model',
    coverage: 'test',
    forecastHorizonDays: 7,
    intervalHours: 1,
    batchCoordinates: true,
    maxPointsPerRequest: 100,
    granularity: WxGranularity.grid,
    dataKind: WxDataKind.forecast,
    requiresApiKey: false,
    browserCorsOk: true,
    browserNotes: '',
    license: 'test',
    attribution: 'test',
    supportedVars: const [WxVar.temperature, WxVar.precip, WxVar.windGust],
    minRequestIntervalMs: 0,
    recommendedCacheTtl: const Duration(hours: 1),
    onDemandOnly: onlyOnDemand,
  );
  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    calls++;
    requestedStart = startUtc;
    requestedEnd = endUtc;
    if (fail) throw StateError('测试断网');
    return departureBundle(
      nodes: [
        for (var i = 0; i < points.length; i++)
          RouteNode(
            pointIndex: i,
            pos: points[i],
            elevationM: 100,
            distFromStartM: i * 3600,
          ),
      ],
      start: startUtc,
      hours: endUtc.difference(startUtc).inHours,
    ).result.points;
  }
}
