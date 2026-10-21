import 'package:flutter/material.dart';
import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_map/flutter_map.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/favorites_repository.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/detail/route_detail_screen.dart';
import 'package:trailweather/ui/detail/ridge_band.dart';
import 'package:trailweather/ui/detail/layering_card.dart';
import 'package:trailweather/ui/detail/environment_cards.dart';
import 'package:trailweather/ui/detail/node_detail_sheet.dart';
import 'package:trailweather/ui/map/map_layers_ui.dart';
import 'package:trailweather/ui/strings.dart';
import 'package:trailweather/ui/theme.dart';

import '../integration/core_flow_test.dart' show IntegrationFakeProvider;

HikingRoute _route() => HikingRoute(
  id: 'v2-detail',
  name: '详情 v2 测试线路',
  origin: RouteOrigin.import,
  segments: [
    [
      for (var i = 0; i < 40; i++)
        LatLng(39.99 + i * 0.001, 116.18 + i * 0.001),
    ],
  ],
  elevationsM: [for (var i = 0; i < 40; i++) i * 20.0],
  sourceName: '测试',
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  bool missingTemperature = false,
  double width = 900,
  double height = 2400,
  double textScale = 1,
  bool dark = false,
  Map<String, Object> initialPrefs = const {},
  HikingRoute? route,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues(initialPrefs);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        weatherProvidersProvider.overrideWithValue([
          missingTemperature
              ? _MissingTemperatureProvider()
              : IntegrationFakeProvider(),
        ]),
      ],
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: RouteDetailScreen(
          args: RouteDetailArgs(route: route ?? _route()),
        ),
      ),
    ),
  );
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
}

/// 节点列表行的标题（山脊天气带下方的选中说明行以同样文字开头，需排除）。
Finder _tileTitle(String text) => find.descendant(
  of: find.byType(ListTile),
  matching: find.textContaining(text),
);

class _MissingTemperatureProvider extends IntegrationFakeProvider {
  @override
  Future<List<WxPointForecast>> fetchPoints({
    required List<LatLng> points,
    required DateTime startUtc,
    required DateTime endUtc,
    CancelToken? cancelToken,
  }) async {
    final data = await super.fetchPoints(
      points: points,
      startUtc: startUtc,
      endUtc: endUtc,
    );
    return [
      for (final p in data)
        WxPointForecast(
          lat: p.lat,
          lon: p.lon,
          provenance: p.provenance,
          dailySunsetsUtc: p.dailySunsetsUtc,
          hours: [
            for (final h in p.hours)
              WxHourValue(
                validFromUtc: h.validFromUtc,
                values: {
                  ...h.values,
                  WxVar.temperature: null,
                  WxVar.apparentTemp: null,
                },
              ),
          ],
        ),
    ];
  }
}

void main() {
  testWidgets('小地图单指拖动改变中心，工具收进一个菜单，线路可临时隐藏看地名', (tester) async {
    await _pump(tester);
    final map = find.byType(FlutterMap).first;
    final before = MapCamera.of(
      tester.element(
        find.descendant(of: map, matching: find.byType(TileLayer)).first,
      ),
    ).center;
    await tester.drag(map, const Offset(-80, 0));
    await tester.pumpAndSettle();
    final after = MapCamera.of(
      tester.element(
        find.descendant(of: map, matching: find.byType(TileLayer)).first,
      ),
    ).center;
    expect(after, isNot(before));
    expect(find.byTooltip('地图工具'), findsOneWidget);
    expect(find.byTooltip(S.routeMapFullscreen), findsOneWidget);
    await tester.tap(find.byTooltip('地图工具'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏线路，查看地名'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: map, matching: find.byType(PolylineLayer)),
      findsNothing,
    );
    expect(find.text('显示线路'), findsOneWidget);
    await tester.tap(find.text('显示线路'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: map, matching: find.byType(PolylineLayer)),
      findsOneWidget,
    );
  });

  testWidgets('手机默认显示衣物动画和场景，无需先展开穿衣卡', (tester) async {
    await _pump(tester, width: 390, height: 844);
    final figure = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LayerFigurePainter,
    );
    expect(figure, findsOneWidget);
    expect(find.textContaining('停留 '), findsOneWidget);
    expect(find.text(S.layeringColdy), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(S.layeringTitle)).dy,
      greaterThan(tester.getTopLeft(find.byType(RidgeWeatherBand)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('移动端天气摘要先于地图；缺气温不显示成零度', (tester) async {
    await _pump(tester, missingTemperature: true, width: 390);
    expect(find.text('${S.notProvided} / ${S.notProvided}'), findsOneWidget);
    expect(find.text(S.layeringNoData), findsOneWidget);
    expect(
      tester.getTopLeft(find.byType(RidgeWeatherBand)).dy,
      lessThan(tester.getTopLeft(find.byType(LayeringCard)).dy),
    );
    expect(
      tester.getTopLeft(find.byType(LayeringCard)).dy,
      lessThan(tester.getTopLeft(find.byType(FlutterMap).first).dy),
    );
    expect(
      tester.getTopLeft(find.text(S.routeSummary)).dy,
      lessThan(tester.getTopLeft(find.byType(FlutterMap).first).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间控制条切换模式，摘要保留完整时间上下文', (tester) async {
    await _pump(tester);
    expect(find.byTooltip(RegExp('全线同一时刻')), findsOneWidget);
    await tester.tap(find.byTooltip(RegExp(S.detailTimeAndPace)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.modeTrip));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('全线同一时刻'), findsNothing);
    expect(find.textContaining('（配速估算）'), findsOneWidget);
    expect(find.text(S.detailSwitchToTrip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('显示行进方向；点击整行直接打开节点详情，不再重复信息按钮', (tester) async {
    await _pump(tester);

    expect(
      find.textContaining('${S.startPoint}（绿）→ ${S.endPoint}（红）'),
      findsOneWidget,
    );
    expect(find.text(S.reverseRoute), findsOneWidget);

    await tester.scrollUntilVisible(_tileTitle('起点 · 0.0 km'), 300);
    await tester.pumpAndSettle();
    await tester.tap(_tileTitle('起点 · 0.0 km'));
    await tester.pumpAndSettle();
    expect(find.byTooltip(S.nodeDetail2), findsNothing);
    expect(find.text(S.markAs), findsOneWidget);
    expect(find.text(S.meteogramTitle), findsOneWidget);
    expect(find.text(S.altitudeExploreTitle), findsNothing);
    expect(find.text(S.multiSourceCompare), findsNothing);
    await tester.scrollUntilVisible(
      find.text(S.nodeWeatherTools),
      150,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(S.nodeWeatherTools));
    await tester.pumpAndSettle();
    expect(find.text(S.multiSourceCompare), findsOneWidget);
    expect(find.byType(AirQualityCard), findsNothing);
    expect(find.byType(AltitudeWeatherCard), findsNothing);
    expect(find.byType(NodeComparePanel), findsNothing);
  });

  testWidgets('命名航点同样显示顺序编号，不占用一个看不见的编号', (tester) async {
    final base = _route();
    await _pump(
      tester,
      route: base.copyWith(
        waypoints: [
          RouteWaypoint(
            name: '山腰营地',
            point: base.segments.first[20],
            type: WaypointType.camp,
          ),
        ],
      ),
    );
    await tester.scrollUntilVisible(_tileTitle('山腰营地'), 300);
    final tile = find.ancestor(
      of: _tileTitle('山腰营地'),
      matching: find.byType(ListTile),
    );
    expect(find.descendant(of: tile, matching: find.text('3')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点选剖面末节点后，列表终点同步高亮并保留统一编号', (tester) async {
    await _pump(tester);
    final chart = find.byKey(const ValueKey('ridge-profile'));
    final box = tester.getRect(chart);
    await tester.tapAt(Offset(box.right - 8, box.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('节点 5 · 终点'), findsOneWidget);
    final end = _tileTitle('终点 · ');
    await tester.scrollUntilVisible(end, 300);
    final tile = find.ancestor(of: end, matching: find.byType(ListTile));
    expect(tester.widget<ListTile>(tile).selected, isTrue);
    expect(find.descendant(of: tile, matching: find.text('5')), findsOneWidget);
  });

  testWidgets('穿衣卡片：切换场景、怕冷偏好会加厚保暖层并保存', (tester) async {
    final container = await _pump(tester);
    expect(find.text(S.layeringTitle), findsOneWidget);
    expect(find.text(S.layeringColdy), findsOneWidget);
    expect(find.text(S.layeringIncomplete), findsOneWidget);
    // 场景、衣物动画、偏好和依据均直接可用。
    // 保暖层那一行是否带“背包”标记（防护层随假数据的时刻变化，不参与断言）。
    Finder midPacked(String name) => find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(Row)).first,
      matching: find.text(S.layeringPacked),
    );
    // 体感全程 13°：保暖层“薄抓绒”，出发时放背包
    expect(find.text('薄抓绒'), findsOneWidget);
    expect(midPacked('薄抓绒'), findsOneWidget);

    final figure = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.painter is LayerFigurePainter,
    );
    await tester.tap(find.textContaining('停留 '));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 160));
    final transitioning =
        (tester.widget<CustomPaint>(figure).painter! as LayerFigurePainter)
            .states;
    expect(transitioning[1], greaterThan(0.5));
    expect(transitioning[1], lessThan(1));
    await tester.pumpAndSettle();
    // 停留时保暖层通过动画由背包态过渡到穿着态。
    expect(midPacked('薄抓绒'), findsNothing);
    final states =
        (tester.widget<CustomPaint>(figure).painter! as LayerFigurePainter)
            .states;
    expect(states[1], 1);

    await tester.tap(find.text(S.layeringColdy));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).coldSensitivity, -1);
    expect(find.text(S.layeringColdy), findsOneWidget);
    expect(find.text('抓绒衣'), findsOneWidget);

    await tester.tap(find.text(S.layeringBasis));
    await tester.pumpAndSettle();
    expect(find.textContaining('经验建议'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('390px 大字号衣物动画及偏好可用（dark=$dark）', (tester) async {
      await _pump(tester, width: 390, height: 844, textScale: 1.6, dark: dark);
      await tester.scrollUntilVisible(find.text(S.layeringColdy), 250);
      await tester.pumpAndSettle();
      await tester.tap(find.text(S.layeringColdy));
      await tester.pumpAndSettle();
      expect(find.text('抓绒衣'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('把节点标为营地：保存到我的行程并出现在时间线', (tester) async {
    final container = await _pump(tester);

    final endNode = _tileTitle('终点 · ');
    await tester.scrollUntilVisible(endNode, 300);
    await tester.pumpAndSettle();
    await tester.tap(endNode);
    await tester.pumpAndSettle();

    // 节点详情只保留一个“标记为”按钮，类型在二级面板里选。
    await tester.scrollUntilVisible(
      find.text(S.markAs),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text(S.markAs));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '营地'));
    await tester.pumpAndSettle();
    expect(find.text(S.markName), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, S.save));
    await tester.pumpAndSettle();

    expect(find.text(S.markSavedNew), findsOneWidget);
    final saved = container.read(favoritesProvider).single;
    expect(saved.waypoints.single.type, WaypointType.camp);
    expect(_tileTitle('营地 · '), findsOneWidget);
  });

  testWidgets('同网格、同一小时的普通节点折叠成“预报同上”，点开展开、再点收起', (tester) async {
    // 测试线路约 5 km，全部落在一个近似网格内；默认固定时刻。
    await _pump(tester);
    final fold = find.textContaining(' · ${S.foldedSameForecast}');
    await tester.scrollUntilVisible(fold, 300);
    await tester.pumpAndSettle();
    expect(fold, findsOneWidget);
    expect(find.textContaining(S.foldedNodes(3)), findsOneWidget);
    expect(_tileTitle('节点 2'), findsNothing);
    expect(_tileTitle('终点'), findsOneWidget);

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(_tileTitle('节点 2'), findsOneWidget);
    expect(_tileTitle('节点 4'), findsOneWidget);

    await tester.tap(fold);
    await tester.pumpAndSettle();
    expect(_tileTitle('节点 2'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('普通航点不单独成行：挂在最近节点上显示名称，地图上不算偏离线路', (tester) async {
    final base = _route();
    final route = base.copyWith(
      waypoints: [
        RouteWaypoint(
          name: '观景台',
          point: base.segments.first[20],
          type: WaypointType.poi,
        ),
      ],
    );
    await _pump(tester, route: route);
    final nearby = find.textContaining('${S.nearbyMarksPrefix}：观景台');
    await tester.scrollUntilVisible(nearby, 300);
    expect(nearby, findsOneWidget);
    expect(_tileTitle('观景台'), findsNothing);
    expect(find.byTooltip('观景台（${S.nearbyMarkTooltip}）'), findsWidgets);
    expect(find.byTooltip('观景台（${S.offRouteWaypoint}）'), findsNothing);
  });

  testWidgets('反向行走：起点海拔变为原终点海拔', (tester) async {
    await _pump(tester);
    await tester.scrollUntilVisible(_tileTitle('起点 · 0.0 km · 0 m'), 300);
    expect(_tileTitle('起点 · 0.0 km · 0 m'), findsOneWidget);

    await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.reverseRoute));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    // 线路要点行标明“已反向”；完整说明在“数据说明与来源”里。
    expect(find.textContaining('已反向'), findsOneWidget);
    await tester.scrollUntilVisible(_tileTitle('起点 · 0.0 km · 780 m'), 300);
    expect(_tileTitle('起点 · 0.0 km · 780 m'), findsOneWidget);
  });

  testWidgets('小地图图层只给平面地形：跟随设置 / 天地图地形（推荐）/ 等高线（海外）', (tester) async {
    final container = await _pump(tester);
    await tester.tap(find.byTooltip(S.miniMapTools));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.miniMapLayers));
    await tester.pumpAndSettle();
    expect(find.text(S.miniMapFollowSettings), findsOneWidget);
    expect(find.text('天地图地形晕渲（推荐）'), findsOneWidget);
    expect(find.text('OpenTopoMap 等高线（海外图源）'), findsOneWidget);
    expect(find.text(S.miniMapNeedsTiandituKey), findsOneWidget);
    expect(find.textContaining('卫星'), findsNothing);

    await tester.tap(find.text('OpenTopoMap 等高线（海外图源）'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).routeMapLayerId, 'opentopomap');
    // 小地图图层不改全局底图。
    expect(
      container.read(settingsProvider).baseLayerId,
      const AppSettings().baseLayerId,
    );

    // 没有天地图 Key：点“天地图地形”直接进入填 Key 页面。
    await tester.tap(find.byTooltip(S.miniMapTools));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.miniMapLayers));
    await tester.pumpAndSettle();
    await tester.tap(find.text('天地图地形晕渲（推荐）'));
    await tester.pumpAndSettle();
    expect(find.byType(MapSourcesPage), findsOneWidget);
    expect(container.read(settingsProvider).routeMapLayerId, 'opentopomap');
    expect(tester.takeException(), isNull);
  });

  testWidgets('小地图自选图层加载不出时提示，并可一键切回', (tester) async {
    final container = await _pump(
      tester,
      initialPrefs: {'settings.v1': '{"routeMapLayerId":"opentopomap"}'},
    );
    // 测试环境没有网络：瓦片不会成功显示，10 秒后给出提示。
    await tester.pump(const Duration(seconds: 11));
    await tester.pump();
    expect(find.text(S.miniMapLayerFailed), findsOneWidget);
    await tester.tap(find.text(S.miniMapRevert));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).routeMapLayerId, '');
    expect(find.text(S.miniMapLayerFailed), findsNothing);
  });
}
