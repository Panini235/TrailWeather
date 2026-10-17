import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:trailweather/data/weather/satellite_frames.dart';
import 'package:trailweather/data/weather/typhoon.dart';
import 'package:trailweather/data/weather/weather_field.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/meteogram.dart';
import 'package:trailweather/ui/map/basemap.dart';
import 'package:trailweather/ui/map/weather_map_overlay.dart';
import 'package:trailweather/ui/strings.dart';

import '../unit/weather_field_test.dart'
    show fakeFieldResponse, fakeUniformResponse;

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
    typhoonService: TyphoonService(fetcher: _jmaFixture),
  );
}

/// 2026-10-17 实测的 JMA 响应（台风 Champi，test/fixtures/jma）。
Future<String> _jmaFixture(
  Uri uri, {
  Map<String, String>? headers,
  CancelToken? cancelToken,
}) async {
  final name = uri.path.endsWith('targetTc.json')
      ? 'targetTc.json'
      : 'TC2636_${uri.pathSegments.last}';
  return File('test/fixtures/jma/$name').readAsStringSync();
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

  testWidgets('播放：时间轴连续前进，播到最后自动停；不自动开始', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await _pumpPanel(tester, c);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(c.playing, isFalse);
    expect(c.timeline.value, 0);
    await tester.tap(find.byTooltip(S.wxMapPlay));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 每秒 2.5 小时：0.2 s 后停在第 0 与第 1 个整点之间（过渡中）
    expect(c.timeline.value, closeTo(0.5, 0.05));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(c.playing, isFalse);
    expect(c.timeline.value, c.frameCount - 1);
    expect(c.timeIndex, c.frameCount - 1);
  });

  testWidgets('暂停或松开时间轴：回到最近的整点，标签只显示整点', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await _pumpPanel(tester, c);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(S.wxMapPlay));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 280));
    expect(c.timeline.value, closeTo(0.7, 0.05));
    await tester.tap(find.byTooltip(S.wxMapPause));
    await tester.pumpAndSettle();
    expect(c.playing, isFalse);
    expect(c.timeline.value, 1);

    c.scrub(1.4);
    await tester.pump();
    final hour = c.grid!.timesUtc[1].toLocal().hour.toString().padLeft(2, '0');
    expect(find.textContaining('$hour:00'), findsOneWidget);
    c.settle();
    await tester.pumpAndSettle();
    expect(c.timeline.value, 1);
  });

  test('卫星帧叠放权重：两帧之间线性过渡，整帧上只画一帧', () {
    expect(frameWeight(2, 2), 1);
    expect(frameWeight(3, 2), 0);
    expect(frameWeight(1, 2), 0);
    expect(frameWeight(2, 2.25), closeTo(0.75, 1e-9));
    expect(frameWeight(3, 2.25), 1);
    expect(frameWeight(4, 2.25), 0);
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

  testWidgets('卫星云图：所有时次一起挂上，按时间轴交叉淡入；停下回到真实观测时次', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    await _pumpPanel(tester, c);
    await tester.tap(find.text(S.wxMapSatellite));
    await tester.pumpAndSettle();
    final n = c.satFrames.length;
    expect(n, 13);
    expect(c.timeline.value, n - 1);
    final stack =
        ((weatherMapLayers(c, Basemap.base('osm')).single as RepaintBoundary)
                        .child!
                    as Opacity)
                .child!
            as Stack;
    final fades = stack.children.cast<FadeTransition>();
    expect(fades, hasLength(n));
    // 新的在下：倒序叠放
    expect(
      (fades.first.key! as ValueKey<String>).value,
      contains(c.satFrames.last.toIso8601String()),
    );
    List<double> opacities() => [for (final f in fades) f.opacity.value];
    expect(opacities().where((o) => o > 0), hasLength(1));
    c.scrub(n - 1.75);
    final o = opacities();
    // 位于第 n-2 与 n-1 帧之间 1/4 处：最新一帧在下层不透明，第 n-2 帧在上层 0.75
    expect(o[0], 1);
    expect(o[1], closeTo(0.75, 1e-9));
    expect(o.skip(2).every((x) => x == 0), isTrue);
    c.settle();
    await tester.pumpAndSettle();
    expect(c.timeline.value, n - 2);
    expect(c.satIndex, n - 2);
  });

  testWidgets('台风：列出名称、强度、气压与移向，可定位', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    List<LatLng>? fitted;
    c.onFitRequest = (pts) => fitted = pts;
    c.toggle();
    await _pumpPanel(tester, c);
    await tester.tap(find.text(S.wxMapTyphoon));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(c.typhoons, hasLength(1));
    expect(find.textContaining('Champi（2630）'), findsOneWidget);
    expect(find.textContaining('960 hPa'), findsOneWidget);
    expect(find.textContaining('向西'), findsOneWidget);
    expect(find.text(S.wxMapTyphoonNote), findsOneWidget);
    // 进入台风模式自动定位一次；点“定位”再次定位
    expect(fitted, isNotNull);
    fitted = null;
    await tester.tap(find.text(S.wxMapLocate));
    expect(fitted, isNotEmpty);
  });

  testWidgets('格点场图层在地图上绘制，时间轴连续变化与切换变量不报错', (tester) async {
    final c = _controller();
    addTearDown(c.dispose);
    c.toggle();
    c.onView(_view, 10, 0.5);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    final grid = c.grid!;
    final time = ValueNotifier<double>(0);
    addTearDown(time.dispose);
    Widget map(FieldVar v) => MaterialApp(
      home: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(40, 116.2),
          initialZoom: 9,
        ),
        children: [
          WeatherFieldLayer(
            grid: grid,
            variable: v,
            time: time,
            basemap: Basemap.base('osm'),
          ),
        ],
      ),
    );
    await tester.pumpWidget(map(FieldVar.precip));
    // 时间轴变化只重绘本层（含两整点之间的过渡位置）
    time.value = 1.5;
    await tester.pump();
    time.value = 2;
    await tester.pump();
    await tester.pumpWidget(map(FieldVar.cloudLow));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('格点场画在格点范围内：平移缩放后位置跟着地图走', (tester) async {
    // 4×4 格点，全场 5 mm/h；范围约北纬 39.8–40.2、东经 116.0–116.4
    final grid = WeatherFieldService.parse(
      fakeUniformResponse(16, 5),
      bounds: _view,
      cols: 4,
      rows: 4,
      lats: const [40.2, 40.067, 39.933, 39.8],
      lons: const [116.0, 116.133, 116.267, 116.4],
      fetchedAtUtc: _now,
    );
    final time = ValueNotifier<double>(0);
    addTearDown(time.dispose);
    final key = GlobalKey();
    Future<ui.Image> render(LatLng center, double zoom) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 400,
                height: 400,
                child: FlutterMap(
                  key: ValueKey('$center$zoom'),
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: zoom,
                    backgroundColor: Colors.transparent,
                  ),
                  children: [
                    WeatherFieldLayer(
                      grid: grid,
                      variable: FieldVar.precip,
                      time: time,
                      basemap: Basemap.base('osm'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      return (await tester.runAsync(() => boundary.toImage()))!;
    }

    Future<int> alphaAt(ui.Image img, int x, int y) async {
      final data = (await tester.runAsync(
        () => img.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      return data.getUint8((y * img.width + x) * 4 + 3);
    }

    // 缩放 9：格点场宽约 145 px，居中
    var img = await render(const LatLng(40, 116.2), 9);
    expect(await alphaAt(img, 200, 200), greaterThan(0));
    expect(await alphaAt(img, 200 + 50, 200), greaterThan(0));
    expect(await alphaAt(img, 200 + 120, 200), 0);
    expect(await alphaAt(img, 200, 200 - 120), 0);
    // 缩放 10、中心东移 0.2°：场的西缘落在画面中心附近，中心以东仍有颜色、以西变透明
    img = await render(const LatLng(40, 116.4), 10);
    expect(await alphaAt(img, 200 - 100, 200), greaterThan(0));
    expect(await alphaAt(img, 200 + 20, 200), 0);
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
