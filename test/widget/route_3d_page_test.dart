import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/terrain/dem.dart';
import 'package:trailweather/ui/detail/route_3d_page.dart';
import 'package:trailweather/ui/strings.dart';

import '../unit/terrain_test.dart' show cone, terrariumRgba;

final _route = HikingRoute(
  id: 't3d',
  name: '测试线路',
  origin: RouteOrigin.planned,
  segments: const [
    [
      LatLng(39.9886, 116.1823),
      LatLng(39.9998, 116.1702),
      LatLng(39.9612, 116.1872),
    ],
  ],
  elevationsM: const [null, null, null],
  sourceName: '测试',
);

Future<void> _pump(WidgetTester tester, DemService dem) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        demServiceProvider.overrideWithValue(dem),
      ],
      child: MaterialApp(home: Route3DPage(route: _route)),
    ),
  );
}

void main() {
  testWidgets('加载高程 → 画出地形；切换高程放大倍数时标注跟着变', (tester) async {
    final dem = DemService(
      fetcher: (uri, {cancelToken}) async => Uint8List(0),
      decoder: (_) async => terrariumRgba(cone),
    );
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    expect(find.textContaining(S.route3dLoading), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining(S.route3dLoading), findsNothing);
    expect(find.text(S.route3dExNone), findsOneWidget);
    expect(find.textContaining('网格间距约'), findsOneWidget);
    expect(find.text(S.terrainAttribution), findsOneWidget);

    await tester.tap(find.text('×2'));
    await tester.pumpAndSettle();
    expect(find.text('${S.route3dExPrefix}2'), findsOneWidget);

    // 单指转、双击复位都不抛异常，松手后不再出帧（没有惯性 / 循环动画）
    await tester.drag(find.byType(CustomPaint).last, const Offset(120, 40));
    await tester.pump();
    final canvas = find.byType(GestureDetector).first;
    await tester.tap(canvas);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(canvas);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);

    // 双指张开（缩放）+ 平移
    final center = tester.getCenter(canvas);
    final f1 = await tester.startGesture(center - const Offset(40, 0));
    final f2 = await tester.startGesture(center + const Offset(40, 0));
    for (var i = 0; i < 10; i++) {
      await f1.moveBy(const Offset(-6, 2));
      await f2.moveBy(const Offset(6, 2));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await f1.up();
    await f2.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('高程瓦片下载失败：说明原因并可重试，不画假地形', (tester) async {
    var fail = true;
    final dem = DemService(
      fetcher: (uri, {cancelToken}) async {
        if (fail) throw Exception('offline');
        return Uint8List(0);
      },
      decoder: (_) async => terrariumRgba(cone),
    );
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await tester.pumpAndSettle();
    expect(find.text(S.route3dFailed), findsOneWidget);
    expect(find.text(S.route3dExNone), findsNothing);

    fail = false;
    await tester.tap(find.text(S.route3dRetry));
    await tester.pumpAndSettle();
    expect(find.text(S.route3dFailed), findsNothing);
    expect(find.text(S.route3dExNone), findsOneWidget);
  });
}
