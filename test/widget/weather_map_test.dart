import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/satellite_frames.dart';
import 'package:trailweather/data/weather/weather_field.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/meteogram.dart';
import 'package:trailweather/ui/map/basemap.dart';
import 'package:trailweather/ui/map/weather_map_overlay.dart';
import 'package:trailweather/ui/strings.dart';

import '../unit/weather_field_test.dart' show fakeFieldResponse;

final _now = DateTime.now().toUtc();

WeatherMapController _controller() {
  return WeatherMapController(
    now: () => _now,
    fieldService: WeatherFieldService(
      now: () => _now,
      fetcher: (uri, {headers, cancelToken}) async => fakeFieldResponse(uri),
    ),
    satelliteService: SatelliteFrameService(
      now: () => _now,
      probe: (_) async => 200,
    ),
  );
}

const _view = FieldBounds(south: 39.8, west: 116.0, north: 40.2, east: 116.4);

Future<void> _pumpPanel(WidgetTester tester, WeatherMapController c) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: WeatherMapPanel(controller: c),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('打开天气图：停下后请求格点场，显示时间轴、图例与来源说明', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await _pumpPanel(tester, c);
    expect(find.text(S.wxMapLoading), findsOneWidget);
    // 去抖 500 ms 后才请求
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(c.grid, isNotNull);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.textContaining(S.wxMapForecastNote), findsOneWidget);
    expect(find.text(S.wxMapPrecipUnit), findsOneWidget);
    expect(find.byTooltip(S.wxMapPlay), findsOneWidget);

    // 云量：出现低 / 中 / 高云切换
    await tester.tap(find.text(S.wxMapCloud));
    await tester.pumpAndSettle();
    expect(find.text(S.wxMapCloudLow), findsOneWidget);
    await tester.tap(find.text(S.wxMapCloudLow));
    await tester.pumpAndSettle();
    expect(c.fieldVar, FieldVar.cloudLow);
  });

  testWidgets('播放：逐帧前进，播到最后自动停；不自动开始', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await _pumpPanel(tester, c);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(c.playing, isFalse);
    final start = c.timeIndex;
    await tester.tap(find.byTooltip(S.wxMapPlay));
    await tester.pump(const Duration(milliseconds: 700));
    expect(c.timeIndex, start + 1);
    await tester.pump(const Duration(seconds: 3));
    expect(c.playing, isFalse);
    expect(c.timeIndex, c.frameCount - 1);
  });

  testWidgets('缩放太小（全国以上）：不请求，提示放大', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(
      const FieldBounds(south: 10, west: 70, north: 55, east: 140),
      3.5,
      0.5,
    );
    await _pumpPanel(tester, c);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(c.grid, isNull);
    expect(find.text(S.wxMapZoomIn), findsOneWidget);
  });

  testWidgets('卫星云图：显示观测时间与实况说明', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    await _pumpPanel(tester, c);
    await tester.tap(find.text(S.wxMapSatellite));
    await tester.pumpAndSettle();
    expect(c.satFrames, isNotEmpty);
    expect(find.textContaining(S.wxMapSatelliteTime), findsOneWidget);
    expect(find.text(S.wxMapSatelliteNote), findsOneWidget);
  });

  testWidgets('格点场图层在地图上绘制且切换时次不报错', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final grid = c.grid!;
    Widget map(int t) => MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(40, 116.2),
          initialZoom: 9,
        ),
        children: [
          WeatherFieldLayer(
            grid: grid,
            variable: FieldVar.precip,
            timeIndex: t,
            basemap: Basemap.base('osm'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(map(0));
    await tester.pumpWidget(map(2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('节点气象时间图：默认显示到达时刻，点按换到其他小时', (tester) async {
    final arrival = DateTime.utc(2026, 10, 18, 4);
    final point = WxPointForecast(
      lat: 40,
      lon: 116,
      provenance: _prov(),
      dailySunrisesUtc: [DateTime.utc(2026, 10, 17, 22, 28)],
      dailySunsetsUtc: [DateTime.utc(2026, 10, 18, 9, 31)],
      hours: [
        for (var i = 0; i < 30; i++)
          WxHourValue(
            validFromUtc: DateTime.utc(2026, 10, 18).add(Duration(hours: i)),
            values: {
              for (final v in WxVar.values) v: null,
              WxVar.temperature: 5.0 + i % 8,
              WxVar.apparentTemp: 2.0 + i % 8,
              WxVar.precip: i == 6 ? 1.2 : 0,
              WxVar.precipProb: i == 6 ? 70 : 10,
              WxVar.windGust: 8.0 + i,
              WxVar.windDir: 315,
              WxVar.cloudLow: 90,
              WxVar.cloudMid: 30,
              WxVar.cloudHigh: 0,
              WxVar.uvIndex: i == 5 ? 7 : 0,
            },
          ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 380,
            child: NodeMeteogram(
              point: point,
              arrivalUtc: arrival,
              settings: const AppSettings(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final arrivalHour = arrival.toLocal().hour.toString().padLeft(2, '0');
    expect(find.textContaining('$arrivalHour时'), findsOneWidget);
    // 点最右侧一列
    final box = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pump();
    expect(find.textContaining('$arrivalHour时'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

WxProvenance _prov() => WxProvenance(
  providerId: 'fake',
  vendor: 'fake',
  modelOrNetwork: 'fake',
  modelKnown: false,
  requestLat: 40,
  requestLon: 116,
  returnedLat: null,
  returnedLon: null,
  locationDetail: null,
  elevationUsedM: null,
  granularity: WxGranularity.grid,
  spatialResolutionNote: null,
  dataKind: WxDataKind.forecast,
  fetchedAtUtc: DateTime.utc(2026, 10, 17),
  modelRunUtc: null,
  utcOffsetSeconds: 0,
  license: 'test',
  attribution: 'test',
  interpolationNote: null,
  elevationAdjustNote: null,
  traceNote: null,
);
