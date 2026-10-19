import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:trailweather/core/app_links.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/routes/route_sampling.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/departure_windows.dart';
import 'package:trailweather/data/weather/risk_rules.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/detail_state.dart';
import 'package:trailweather/ui/detail/ridge_band.dart';
import 'package:trailweather/ui/share/share_cards.dart';
import 'package:trailweather/ui/share/share_graphics.dart';
import 'package:trailweather/ui/share/share_image.dart';
import 'package:trailweather/ui/theme.dart';

final _t = DateTime.utc(2026, 10, 17, 2);

HikingRoute _route() => HikingRoute(
  id: 'share',
  name: '蓟县歪顶坨',
  origin: RouteOrigin.import,
  segments: [
    [
      for (var i = 0; i < 30; i++)
        LatLng(40.16 + i * 0.001, 117.40 + (i % 5) * 0.0005),
    ],
  ],
  elevationsM: [
    for (var i = 0; i < 30; i++) 267.0 + (i < 18 ? i : 36 - i) * 30,
  ],
  sourceName: '用户导入 KML',
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

/// 10 个节点：第 4 个较强降水（黄），第 7 个大风（红），第 6 个最高。
List<NodeWxRow> _rows() => [
  for (var i = 0; i < 10; i++)
    NodeWxRow(
      node: RouteNode(
        pointIndex: i * 3,
        pos: LatLng(40.16 + i * 0.003, 117.40),
        elevationM: 267.0 + (i <= 6 ? i : 12 - i) * 90,
        distFromStartM: i * 300.0,
        label: i == 0 ? '起点' : (i == 9 ? '终点' : null),
      ),
      validUtc: _t,
      point: WxPointForecast(
        lat: 40,
        lon: 117,
        provenance: _prov(),
        hours: [
          for (final t in [_t, _t.add(const Duration(hours: 1))])
            WxHourValue(
              validFromUtc: t,
              values: {
                WxVar.temperature: 10.0,
                WxVar.precip: i == 4 ? 4.2 : 0.0,
                WxVar.windGust: i == 7 ? 19.0 : 5.0,
              },
              symbols: {'wmo_code': i == 4 ? '81' : '3'},
            ),
        ],
      ),
      sharedWithPrev: false,
    ),
];

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(900, 2400);
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

RouteShareCard _routeCard({ShareLayout layout = ShareLayout.full}) =>
    RouteShareCard(
      layout: layout,
      route: _route(),
      tripMode: false,
      reversed: false,
      summary: const RouteWxSummary(
        minTempC: 8,
        maxTempC: 12,
        maxGustMs: 19,
        totalPrecipMm: 4.2,
      ),
      dayPrecip: DayPrecipSummary(
        maxDayMm: 79,
        firstWetUtc: DateTime.utc(2026, 10, 16, 16),
        lastWetUtc: DateTime.utc(2026, 10, 17, 12),
        maxProb: 100,
        minHoursCovered: 24,
      ),
      hints: const [
        WxHint(
          id: 'precip',
          title: '较强降水提示',
          detail: '',
          basis: '',
          level: HintLevel.caution,
        ),
        WxHint(
          id: 'gust',
          title: '大风提示',
          detail: '',
          basis: '',
          level: HintLevel.warning,
        ),
      ],
      rows: _rows(),
      settings: const AppSettings(),
      sourceName: 'Open-Meteo（best_match）',
      fetchedAtUtc: DateTime.utc(2026, 10, 16, 13),
    );

void main() {
  test('关键节点：起终点、最高点、红/黄阈值节点，按沿途顺序且不超过上限', () {
    final keys = pickKeyNodes(_rows());
    expect(keys, [0, 4, 6, 7, 9]);
    expect(pickKeyNodes(_rows(), max: 4), [0, 6, 7, 9]); // 红优先于黄
    expect(pickKeyNodes(const []), isEmpty);
  });

  test('节点天气一行：现象在前，降水 <0.1 mm 省略，缺失不当 0', () {
    final rows = _rows();
    expect(shareNodeWeather(rows[4], const AppSettings()), contains('阵雨'));
    expect(shareNodeWeather(rows[4], const AppSettings()), contains('4.2 mm'));
    expect(
      shareNodeWeather(rows[0], const AppSettings()),
      isNot(contains('mm')),
    );
  });

  for (final dark in [false, true]) {
    testWidgets(
      '线路分享卡：大数字、醒目提示、示意图与剖面、关键节点、宣传与二维码（${dark ? '深色' : '浅色'}应用，2 倍字号）',
      (tester) async {
        await _pumpCard(tester, _routeCard(), scale: 2, dark: dark);
        expect(tester.takeException(), isNull);
        expect(find.text('全天降水'), findsOneWidget);
        expect(find.text('大风提示'), findsOneWidget);
        expect(find.text('较强降水提示'), findsOneWidget);
        expect(find.byType(RouteSketch), findsOneWidget);
        expect(find.byType(RidgeBandGraphic), findsOneWidget);
        expect(find.text(kShareSlogan), findsOneWidget);
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.textContaining('数据：Open-Meteo'), findsOneWidget);
        expect(find.textContaining('预报非实测'), findsOneWidget);
        // 固定时刻：顶部写明“全线同一时刻”，不和行程混淆。
        expect(find.textContaining('全线同一时刻'), findsOneWidget);
      },
    );
  }

  testWidgets('线路分享卡用山脊天气带：编号与列表一致，行程模式铺出日落后的路段', (tester) async {
    final c = _routeCard();
    // 每 20 分钟到达一个节点；来源只有一个整点，之后的节点无数据（中性色）。
    final rows = [
      for (final (i, r) in _rows().indexed)
        NodeWxRow(
          node: r.node,
          validUtc: _t.add(Duration(minutes: 20 * i)),
          point: r.point,
          sharedWithPrev: false,
        ),
    ];
    await _pumpCard(
      tester,
      RouteShareCard(
        route: c.route,
        tripMode: true,
        reversed: false,
        summary: c.summary,
        dayPrecip: null,
        hints: c.hints,
        rows: rows,
        settings: c.settings,
        sourceName: c.sourceName,
        fetchedAtUtc: c.fetchedAtUtc,
        sunsetUtc: _t.add(const Duration(minutes: 90)),
      ),
    );
    expect(tester.takeException(), isNull);
    final band = tester.widget<RidgeBandGraphic>(find.byType(RidgeBandGraphic));
    expect(band.keyNodes, pickKeyNodes(rows));
    expect(band.nightFromIndex, 5); // 第一个晚于日落到达的节点（100 分钟）
    expect(band.keyLabels, [
      for (final i in band.keyNodes)
        '${rows[i].validUtc.toLocal().hour.toString().padLeft(2, '0')}:'
            '${rows[i].validUtc.toLocal().minute.toString().padLeft(2, '0')}',
    ]);
    expect(find.textContaining(' 出发 → 约 '), findsOneWidget);
    expect(find.textContaining('全线同一时刻'), findsNothing);
  });

  testWidgets('出发窗口分享卡：格子、图例、最早未触发时刻与宣传条', (tester) async {
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
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('卡片可渲染为 PNG', (tester) async {
    final key = GlobalKey();
    await _pumpCard(tester, RepaintBoundary(key: key, child: _routeCard()));
    final bytes = await tester.runAsync(() => capturePng(key, pixelRatio: 1));
    expect(bytes, isNotNull);
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  for (final layout in ShareLayout.values) {
    testWidgets('版式「${layout.label}」：2 倍字号不溢出，保留来源与免责、宣传与二维码', (tester) async {
      await _pumpCard(tester, _routeCard(layout: layout), scale: 2);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('数据：Open-Meteo'), findsOneWidget);
      expect(find.textContaining('预报非实测'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      final width = tester.getSize(find.byType(ShareCardFrame)).width;
      expect(width, layout == ShareLayout.wide ? 820 : 360);
      // 横图三栏：示意图、山脊天气带和关键节点都在（不再只有数字和剖面）。
      if (layout == ShareLayout.wide) {
        expect(find.byType(RidgeBandGraphic), findsOneWidget);
        expect(find.textContaining('终点'), findsWidgets);
      }
      // 简图不列关键节点；长图与横图有线路示意。
      expect(
        find.byType(RouteSketch),
        layout == ShareLayout.brief ? findsNothing : findsOneWidget,
      );
    });
  }

  testWidgets('分享预览页可切换版式', (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SharePreviewPage(
          title: '分享',
          fileName: 'x.png',
          card: _routeCard(),
          variants: [
            for (final l in ShareLayout.values)
              ShareVariant(
                label: l.label,
                icon: l.icon,
                card: _routeCard(layout: l),
                fileSuffix: l.name,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RouteSketch), findsOneWidget);
    await tester.tap(find.text(ShareLayout.brief.label));
    await tester.pumpAndSettle();
    expect(find.byType(RouteSketch), findsNothing);
    await tester.tap(find.text(ShareLayout.wide.label));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(ShareCardFrame)).width, 820);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分享预览页顶部提醒不进图片，操作可点', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: SharePreviewPage(
          title: '分享',
          fileName: 'x.png',
          card: _routeCard(),
          notice: ShareModeNotice(
            text: '固定时刻提醒',
            actionLabel: '改按行程',
            onAction: () => tapped = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('固定时刻提醒'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ShareCardFrame),
        matching: find.text('固定时刻提醒'),
      ),
      findsNothing,
    );
    await tester.tap(find.text('改按行程'));
    expect(tapped, isTrue);
  });
}
