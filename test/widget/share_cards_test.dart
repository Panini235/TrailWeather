import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/departure_windows.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/ui/detail/detail_state.dart';
import 'package:trailweather/ui/share/share_cards.dart';
import 'package:trailweather/ui/share/share_image.dart';
import 'package:trailweather/ui/theme.dart';

HikingRoute _route() => HikingRoute(
  id: 'share',
  name: '蓟县歪顶坨',
  origin: RouteOrigin.import,
  segments: [
    [for (var i = 0; i < 30; i++) LatLng(40.16 + i * 0.001, 117.40)],
  ],
  elevationsM: [for (var i = 0; i < 30; i++) 267.0 + i * 18],
  sourceName: '用户导入 KML',
);

List<NodeWxRow> _rows(int n) => [
  for (var i = 0; i < n; i++)
    NodeWxRow(
      node: RouteNode(
        pointIndex: i,
        pos: LatLng(40.16 + i * 0.001, 117.40),
        elevationM: 267.0 + i * 30,
        distFromStartM: i * 500.0,
        label: i == 0 ? '起点' : null,
      ),
      validUtc: DateTime.utc(2026, 10, 17, 2),
      point: null,
      sharedWithPrev: false,
    ),
];

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(400, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Theme(data: AppTheme.light(), child: card),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

RouteShareCard _routeCard(int nodes) => RouteShareCard(
  route: _route(),
  timeLabel: '固定 10/17 22:00',
  tripMode: false,
  reversed: false,
  summary: const RouteWxSummary(
    minTempC: 8,
    maxTempC: 12,
    maxGustMs: 9,
    totalPrecipMm: 0,
  ),
  dayLine: '10月17日全天：沿途降水最多约 79.0 mm，主要在 00–21 时，最大概率 100%',
  hints: const [
    WxHint(
      id: 'precip',
      title: '较强降水提示',
      detail: '',
      basis: '',
      level: HintLevel.caution,
    ),
  ],
  rows: _rows(nodes),
  settings: const AppSettings(),
  sourceName: 'Open-Meteo（best_match）',
  fetchedAtUtc: DateTime.utc(2026, 10, 16, 13),
);

void main() {
  test('分享节点抽样保留首尾，且不超过上限', () {
    expect(sampleShareIndices(5), [0, 1, 2, 3, 4]);
    final picked = sampleShareIndices(24);
    expect(picked.length, shareMaxNodes);
    expect(picked.first, 0);
    expect(picked.last, 23);
  });

  for (final dark in [false, true]) {
    testWidgets('线路天气分享卡：全天降水、来源与免责、节点抽样说明（${dark ? '深色' : '浅色'}应用，2 倍字号）', (
      tester,
    ) async {
      await _pumpCard(tester, _routeCard(24), scale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('全天：沿途降水最多约 79.0 mm'), findsOneWidget);
      expect(find.textContaining('该时次降水'), findsOneWidget);
      expect(find.textContaining('数据：Open-Meteo'), findsOneWidget);
      expect(find.textContaining('预报非实测'), findsOneWidget);
      expect(find.textContaining('共 24 个节点'), findsOneWidget);
    });
  }

  testWidgets('出发窗口分享卡：格子、图例与最早未触发时刻', (tester) async {
    final day1 = DateTime(2026, 10, 17);
    final day2 = DateTime(2026, 10, 18);
    DateTime at(DateTime d, int h) =>
        DateTime(d.year, d.month, d.day, h).toUtc();
    await _pumpCard(
      tester,
      DepartureShareCard(
        routeName: '蓟县歪顶坨',
        isDemo: false,
        reversed: false,
        durationHours: 3.5,
        dayLabels: const ['明天 10/17', '周六 10/18'],
        dates: [day1, day2],
        slotLabels: const ['07:00', '09:00'],
        cells: const [
          [
            DepartureShareCell('雨', DepartureLevel.yellow, false),
            DepartureShareCell('风雨', DepartureLevel.red, false),
          ],
          [
            DepartureShareCell.missing(),
            DepartureShareCell('✓', DepartureLevel.none, false),
          ],
        ],
        startsUtc: [
          [at(day1, 7), at(day1, 9)],
          [at(day2, 7), at(day2, 9)],
        ],
        sourceName: 'Open-Meteo（best_match）',
        fetchedAtUtc: DateTime.utc(2026, 10, 16, 13),
        thresholdText: '阈值：阵风 ≥13.9/17.2 m/s',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('风雨'), findsOneWidget);
    expect(find.textContaining('最早未触发阈值的出发：10/18 09:00'), findsOneWidget);
    expect(find.textContaining('非安全评分'), findsOneWidget);
  });

  testWidgets('卡片可渲染为 PNG', (tester) async {
    final key = GlobalKey();
    await _pumpCard(tester, RepaintBoundary(key: key, child: _routeCard(5)));
    final bytes = await tester.runAsync(() => capturePng(key, pixelRatio: 1));
    expect(bytes, isNotNull);
    // PNG 文件头
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });
}
