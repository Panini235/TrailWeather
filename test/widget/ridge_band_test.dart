import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/detail_state.dart';
import 'package:trailweather/ui/detail/ridge_band.dart';
import 'package:trailweather/ui/strings.dart';
import 'package:trailweather/ui/theme.dart';
import 'package:trailweather/ui/widgets/rolling_text.dart';

final _t = DateTime.utc(2026, 10, 17, 2);

HikingRoute _route({bool elevation = true}) => HikingRoute(
  id: 'ridge',
  name: '测试线路',
  origin: RouteOrigin.import,
  segments: [
    [for (var i = 0; i < 30; i++) LatLng(40.16 + i * 0.001, 117.40)],
  ],
  elevationsM: [
    for (var i = 0; i < 30; i++)
      elevation ? 300.0 + (i < 18 ? i : 36 - i) * 30 : null,
  ],
  sourceName: '用户导入',
);

WxProvenance _prov() => WxProvenance(
  providerId: 'open-meteo:best_match',
  vendor: 'Open-Meteo',
  modelOrNetwork: 'best_match',
  modelKnown: false,
  requestLat: 40,
  requestLon: 117,
  returnedLat: 40,
  returnedLon: 117,
  locationDetail: null,
  elevationUsedM: null,
  granularity: WxGranularity.grid,
  spatialResolutionNote: null,
  dataKind: WxDataKind.forecast,
  fetchedAtUtc: _t,
  modelRunUtc: null,
  utcOffsetSeconds: 0,
  license: 't',
  attribution: 't',
  interpolationNote: null,
  elevationAdjustNote: null,
  traceNote: null,
);

/// 6 个节点：第 2 个较强降水（黄），第 4 个大风（红），其余未触发；
/// [withWx] 为 false 时模拟还没拿到数据。
List<NodeWxRow> _rows({bool withWx = true}) => [
  for (var i = 0; i < 6; i++)
    NodeWxRow(
      node: RouteNode(
        pointIndex: i * 5,
        pos: LatLng(40.16 + i * 0.005, 117.40),
        elevationM: 300.0 + i * 100,
        distFromStartM: i * 550.0,
        label: i == 0 ? '起点' : null,
      ),
      validUtc: _t,
      point: withWx
          ? WxPointForecast(
              lat: 40,
              lon: 117,
              provenance: _prov(),
              hours: [
                WxHourValue(
                  validFromUtc: _t,
                  values: {
                    WxVar.temperature: 10.0,
                    WxVar.precip: i == 2 ? 4.0 : 0.0,
                    WxVar.windGust: i == 4 ? 19.0 : 5.0,
                  },
                ),
              ],
            )
          : null,
      sharedWithPrev: false,
    ),
];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool disableAnimations = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 800),
            disableAnimations: disableAnimations,
          ),
          child: Scaffold(
            body: Padding(padding: const EdgeInsets.all(8), child: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('点击剖面选中最近节点；说明行显示距离、海拔与天气类别', (tester) async {
    int? selected;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => RidgeWeatherBand(
          route: _route(),
          rows: _rows(),
          selectedIndex: selected,
          onTapNode: (i) => setState(() => selected = i),
          etaLabels: const [
            '08:00',
            '08:20',
            '08:40',
            '09:00',
            '09:20',
            '09:40',
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('6 个节点，2 个触发天气提示')), findsOneWidget);
    // 右侧末端附近点一下 → 选中最后一个节点。
    final box = tester.getRect(find.byType(CustomPaint).last);
    await tester.tapAt(Offset(box.right - 4, box.center.dy));
    await tester.pumpAndSettle();
    expect(selected, 5);
    expect(find.textContaining('09:40 到达'), findsOneWidget);
    expect(find.textContaining('2.8 km'), findsOneWidget);
  });

  testWidgets('画出动画只在首次拿到数据时播一次，结束后不再画帧', (tester) async {
    Widget band(List<NodeWxRow> rows) => RidgeWeatherBand(
      route: _route(),
      rows: rows,
      selectedIndex: null,
      onTapNode: (_) {},
    );
    await _pump(tester, band(_rows(withWx: false)));
    await tester.pump();
    // 没有天气数据时不播。
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    await _pump(tester, band(_rows()));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, greaterThan(0));
    await tester.pumpAndSettle();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);

    // 再换一批数据（如切换时间）：不重播。
    await _pump(tester, band(_rows()));
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('减少动效时直接显示，不画出', (tester) async {
    await _pump(
      tester,
      RidgeWeatherBand(
        route: _route(),
        rows: _rows(),
        selectedIndex: null,
        onTapNode: (_) {},
      ),
      disableAnimations: true,
    );
    await tester.pump();
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
  });

  testWidgets('没有海拔时注明，节点仍按天气着色可点', (tester) async {
    await _pump(
      tester,
      RidgeWeatherBand(
        route: _route(elevation: false),
        rows: _rows(),
        selectedIndex: 2,
        onTapNode: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(S.ridgeNoElevation)), findsOneWidget);
    expect(find.textContaining('较强降水'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('滑动数字：过渡中只出现新旧两个真实值；减少动效时直接替换', (tester) async {
    var value = '16 km/h';
    late StateSetter set;
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return RollingText(value);
        },
      ),
    );
    set(() => value = '32 km/h');
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.text('16 km/h'), findsOneWidget);
    expect(find.text('32 km/h'), findsOneWidget);
    expect(find.byType(Text), findsNWidgets(2));
    await tester.pumpAndSettle();
    expect(find.text('16 km/h'), findsNothing);

    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          set = setState;
          return RollingText(value);
        },
      ),
      disableAnimations: true,
    );
    set(() => value = '48 km/h');
    await tester.pump();
    expect(find.text('32 km/h'), findsNothing);
    expect(find.text('48 km/h'), findsOneWidget);
  });
}
