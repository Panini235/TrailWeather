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
import 'package:trailweather/ui/strings.dart';

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
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  SharedPreferences.setMockInitialValues({});
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
        home: RouteDetailScreen(args: RouteDetailArgs(route: _route())),
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
                values: {...h.values, WxVar.temperature: null},
              ),
          ],
        ),
    ];
  }
}

void main() {
  testWidgets('移动端天气摘要先于地图；缺气温不显示成零度', (tester) async {
    await _pump(tester, missingTemperature: true, width: 390);
    expect(find.text('${S.notProvided} / ${S.notProvided}'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text(S.routeSummary)).dy,
      lessThan(tester.getTopLeft(find.byType(FlutterMap).first).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('显示行进方向；点节点选中，再点或点详情打开节点详情', (tester) async {
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
    expect(find.text(S.tapAgainForDetail), findsOneWidget);

    await tester.tap(_tileTitle('起点 · 0.0 km'));
    await tester.pumpAndSettle();
    expect(find.text(S.markAs), findsOneWidget);
    expect(find.text(S.next12h), findsOneWidget);
    expect(find.text(S.multiSourceCompare), findsOneWidget);
  });

  testWidgets('把节点标为营地：保存到我的行程并出现在时间线', (tester) async {
    final container = await _pump(tester);

    final detailButtons = find.byTooltip(S.nodeDetail2);
    await tester.scrollUntilVisible(detailButtons.at(1), 300);
    await tester.pumpAndSettle();
    await tester.tap(detailButtons.at(1));
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
}
