import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_models.dart';
import 'package:trailweather/ui/detail/meteogram.dart';
import 'package:trailweather/ui/detail/weather_cells.dart';
import 'package:trailweather/ui/strings.dart';

import '../support/departure_fixtures.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

String _clock(DateTime utc) {
  final local = utc.toLocal();
  return '${local.month}/${local.day} '
      '${local.hour.toString().padLeft(2, '0')}:00';
}

Finder _chartGesture() => find.descendant(
  of: find.byType(NodeMeteogram),
  matching: find.byWidgetPredicate(
    (w) => w is GestureDetector && w.onHorizontalDragUpdate != null,
  ),
);

void main() {
  testWidgets('时段说明默认只留变量与区间，点击才解释插值与原始 UTC 时次', (tester) async {
    final point = departureBundle(
      providerId: 'open-meteo:best_match',
      hours: 3,
      values: (_, t) => {
        WxVar.temperature: 10,
        WxVar.precip: t == departureTestStart ? 0 : 8,
        WxVar.precipProb: 90,
        WxVar.windGust: 18,
      },
    ).result.points.first;
    await _pump(
      tester,
      WxVarGrid(
        wx: point.hourAt(departureTestStart)!,
        settings: const AppSettings(),
      ),
    );
    expect(find.text('8.0 mm'), findsOneWidget);
    expect(find.textContaining(_clock(departureTestStart)), findsOneWidget);
    expect(
      find.textContaining(
        '${departureTestStart.add(const Duration(hours: 1)).toLocal().hour.toString().padLeft(2, '0')}:00',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('未做小时内插值'), findsNothing);
    expect(find.textContaining('来源原始时次'), findsNothing);
    expect(find.byTooltip(S.wxTimeDetails), findsOneWidget);

    await tester.ensureVisible(find.byType(WeatherHourNotice));
    await tester.tap(find.byType(WeatherHourNotice));
    await tester.pumpAndSettle();
    expect(find.text(S.wxTimeDetails), findsOneWidget);
    expect(find.textContaining('未做小时内插值'), findsOneWidget);
    expect(find.textContaining('来源原始时次（UTC）'), findsOneWidget);
    expect(
      find.textContaining(
        '${WxVar.temperature.label} ${departureTestStart.toIso8601String()}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${WxVar.precip.label} '
        '${departureTestStart.add(const Duration(hours: 1)).toIso8601String()}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('三小时概率和未确认区间不因渐进披露被隐藏', (tester) async {
    final wx = WxHourValue(
      validFromUtc: departureTestStart,
      values: const {WxVar.precipProb: 75, WxVar.precip: 2},
      precedingThreeHourVariables: const {WxVar.precipProb},
      unconfirmedIntervalVariables: const {WxVar.precip},
    );
    await _pump(tester, WeatherHourNotice(wx: wx));
    expect(find.textContaining('前三小时'), findsOneWidget);
    expect(find.textContaining('区间起止未确认'), findsOneWidget);
    expect(find.textContaining(WxVar.precipProb.label), findsOneWidget);
    expect(
      find.textContaining(
        _clock(departureTestStart.subtract(const Duration(hours: 3))),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('未做小时内插值'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('时间图只在选择非到达小时后于图下显示正确区间读数，关闭恢复默认', (tester) async {
    final point = departureBundle(
      providerId: 'open-meteo:best_match',
      hours: 4,
      values: (_, t) => {
        WxVar.temperature: 10,
        WxVar.precip: t.difference(departureTestStart).inHours * 4.0,
        WxVar.precipProb: 90,
        WxVar.windGust: 18,
      },
    ).result.points.first;
    await _pump(
      tester,
      NodeMeteogram(
        point: point,
        arrivalUtc: departureTestStart.add(const Duration(minutes: 30)),
        settings: const AppSettings(),
        hoursBefore: 0,
      ),
    );
    expect(find.byType(WeatherHourNotice), findsNothing);
    expect(find.textContaining('mm 90%'), findsNothing);
    final chart = _chartGesture();
    final rect = tester.getRect(chart);
    // 第一列仍是到达所在小时，不能重复节点顶部的读数。
    await tester.tapAt(Offset(rect.left + 30, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.textContaining('mm 90%'), findsNothing);

    // 第二列展示 08–09 的区间值，取来源 09 时的 8 mm，而非 08 时的 4 mm。
    await tester.tapAt(Offset(rect.left + rect.width * .4, rect.center.dy));
    await tester.pumpAndSettle();
    final readout = find.textContaining('8.0 mm 90%');
    expect(readout, findsOneWidget);
    expect(find.byType(WeatherHourNotice), findsOneWidget);
    expect(tester.getTopLeft(readout).dy, greaterThanOrEqualTo(rect.bottom));
    expect(
      tester
          .widget<WeatherHourNotice>(find.byType(WeatherHourNotice))
          .wx
          .validFromUtc,
      departureTestStart.add(const Duration(hours: 1)),
    );
    expect(find.textContaining('未做小时内插值'), findsNothing);
    await tester.tap(find.byTooltip(S.close));
    await tester.pumpAndSettle();
    expect(find.textContaining('mm 90%'), findsNothing);
    expect(find.byType(WeatherHourNotice), findsNothing);

    // 拖到第三列；区间值仍从随后原始时次取得，而不是插值。
    await tester.dragFrom(
      Offset(rect.left + rect.width * .4, rect.center.dy),
      Offset(rect.width * .25, 0),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('12.0 mm 90%'), findsOneWidget);
    expect(
      tester
          .widget<WeatherHourNotice>(find.byType(WeatherHourNotice))
          .wx
          .validFromUtc,
      departureTestStart.add(const Duration(hours: 2)),
    );
    await tester.tapAt(Offset(rect.left + 30, rect.center.dy));
    await tester.pumpAndSettle();
    expect(find.byType(WeatherHourNotice), findsNothing);
    expect(find.textContaining('mm 90%'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('单时次维持无图提示，不显示重复读数或可关闭的选择', (tester) async {
    final point = departureBundle(hours: 1).result.points.first;
    await _pump(
      tester,
      NodeMeteogram(
        point: point,
        arrivalUtc: departureTestStart,
        settings: const AppSettings(),
        hoursBefore: 0,
      ),
    );
    expect(find.text(S.meteogramNoData), findsOneWidget);
    expect(_chartGesture(), findsNothing);
    expect(find.byType(WeatherHourNotice), findsNothing);
    expect(find.byTooltip(S.close), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
