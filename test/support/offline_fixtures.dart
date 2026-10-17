import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/offline/offline_trip.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/data/weather/open_meteo_provider.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/data/weather/weather_provider.dart';

/// 只用构造的预报；任何网络请求都会被测试视为错误。
class OfflineWeatherFixture extends WeatherProvider {
  @override
  final ProviderCapabilities caps = OpenMeteoProvider(model: 'best_match').caps;
  int calls = 0;
  bool fail = false;
  bool noValues = false;
  bool omitLastPoint = false;
  bool wrongCoordinates = false;
  Set<int> missingHours = {};
  int extraHours = 0;
  double temperature = 12;
  DateTime fetched = DateTime.utc(2026, 10, 16, 22);

  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (fail) throw StateError('测试网络不可达');
    return [
      for (final pos
          in (omitLastPoint ? points.take(points.length - 1) : points))
        WxPointForecast(
          lat: pos.latitude + .01,
          lon: pos.longitude + .01,
          hours: [
            for (
              var t = startUtc;
              t.isBefore(endUtc.add(Duration(hours: extraHours)));
              t = t.add(const Duration(hours: 1))
            )
              if (!missingHours.contains(t.hour))
                WxHourValue(
                  validFromUtc: t,
                  values: noValues
                      ? {WxVar.temperature: null}
                      : {
                          WxVar.temperature: temperature,
                          WxVar.precip: 0,
                          WxVar.precipProb: null,
                          WxVar.windSpeed: 2,
                          WxVar.windGust: 5,
                          WxVar.humidity: null,
                        },
                  symbols: const {'wmo_code': '2'},
                ),
          ],
          dailySunsetsUtc: [
            DateTime.utc(startUtc.year, startUtc.month, startUtc.day + 1, 10),
          ],
          provenance: WxProvenance(
            providerId: caps.providerId,
            vendor: caps.vendor,
            modelOrNetwork: 'fixture-model',
            modelKnown: true,
            requestLat: pos.latitude + (wrongCoordinates ? 1 : 0),
            requestLon: pos.longitude,
            returnedLat: pos.latitude + .01,
            returnedLon: pos.longitude + .01,
            locationDetail: '网格中心（测试）',
            elevationUsedM: 900,
            granularity: WxGranularity.grid,
            spatialResolutionNote: '测试网格',
            dataKind: WxDataKind.forecast,
            fetchedAtUtc: fetched,
            modelRunUtc: fetched.subtract(const Duration(hours: 3)),
            utcOffsetSeconds: 28800,
            license: '测试许可',
            attribution: '测试来源署名',
            interpolationNote: null,
            elevationAdjustNote: null,
            traceNote: 'controlled fixture',
          ),
        ),
    ];
  }
}

OfflineTripPlan offlinePlan({int hours = 72, bool reversed = false}) {
  final original = HikingRoute(
    id: 'offline-fixture',
    name: '离线测试线路',
    origin: RouteOrigin.demo,
    segments: const [
      [LatLng(30, 120), LatLng(30.12, 120.12), LatLng(30.24, 120.24)],
    ],
    elevationsM: const [800, 1000, 1200],
    sourceName: '测试线路',
    isDemo: true,
    waypoints: const [
      RouteWaypoint(
        name: '营地',
        point: LatLng(30.12, 120.12),
        type: WaypointType.camp,
        stopMinutes: 60,
      ),
    ],
  );
  final route = reversed ? original.reversed() : original;
  final path = route.analysisPath;
  final nodes = sampleRoute(
    points: path.points,
    elevations: path.elevations,
    spacingM: 1,
    waypointsAt: snapWaypoints(path.points, route.waypoints),
  );
  final start = DateTime.utc(2026, 10, 16, 23);
  const pace = PaceConfig(speedKmh: 3, restMinutesTotal: 30);
  return OfflineTripPlan(
    route: route,
    nodes: nodes,
    nodeTimesUtc: computeEtas(nodes: nodes, startUtc: start, pace: pace),
    mode: OfflineTimeMode.trip,
    reversed: reversed,
    selectedTimeUtc: start,
    pace: pace,
    startUtc: start,
    endUtc: start.add(Duration(hours: hours)),
  );
}
