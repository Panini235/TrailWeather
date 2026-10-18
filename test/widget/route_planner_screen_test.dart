import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/terrain/dem.dart';
import 'package:trailweather/ui/planner/route_planner_screen.dart';
import 'package:trailweather/ui/strings.dart';

import '../unit/terrain_test.dart' show gridOf, terrariumRgba;

/// 替身高程：全局自西向东每像素升 0.5 m（跨瓦片连续，向东走一直上坡）。
/// 下载替身把瓦片列号放进字节里，解码替身据此拼出连续的坡面。
DemService _fakeDem() => DemService(
  fetcher: (uri, {cancelToken}) async =>
      Uint8List.fromList(utf8.encode(uri.pathSegments[3])),
  decoder: (bytes) async {
    final x = int.parse(utf8.decode(bytes));
    return terrariumRgba(
      gridOf((r, c) => 100.0 + 0.5 * ((x - 3360) * 256 + c)),
    );
  },
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
      child: const MaterialApp(home: RoutePlannerScreen()),
    ),
  );
  await tester.pump();
}

/// 两次轻触间隔开，免得被当成双击缩放。
Future<void> _tapMap(WidgetTester tester, Offset at) async {
  await tester.tapAt(at);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('初始：标题、模式切换、工具按钮与空状态提示', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    expect(find.textContaining('线路规划工坊'), findsOneWidget);
    expect(find.text('打点画线'), findsOneWidget);
    expect(find.text('标记营地/水源'), findsOneWidget);
    expect(find.text('0.00 km'), findsOneWidget);
    expect(find.text(S.plannerHintEmpty), findsOneWidget);
    expect(find.byTooltip(S.locateMe), findsOneWidget);
    expect(find.byTooltip(S.plannerTerrain), findsOneWidget);
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.swap_calls), findsOneWidget);
    // 导出与清空在“更多”菜单里，没有轨迹时不可用
    await tester.tap(find.byTooltip(S.plannerMore));
    await tester.pumpAndSettle();
    expect(find.text('导出 GPX / KML'), findsOneWidget);
    expect(find.text('清空重画'), findsOneWidget);
    final items = tester.widgetList<PopupMenuItem<VoidCallback>>(
      find.byType(PopupMenuItem<VoidCallback>),
    );
    expect(items.every((i) => !i.enabled), isTrue);
  });

  testWidgets('打点：距离、爬升（公开高程数据估算，取整 10 m）、用时与剖面随时更新', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(400, 300));
    await _tapMap(tester, const Offset(550, 300));
    await tester.pumpAndSettle();
    expect(find.text('0.00 km'), findsNothing);
    // 向东一直上坡：有爬升、没有下降
    expect(find.textContaining('↑ ${S.plannerAbout}'), findsOneWidget);
    expect(find.textContaining('↓ ${S.plannerAbout} 0 m'), findsOneWidget);
    expect(find.textContaining('3 点 / 0 航点'), findsOneWidget);
    expect(find.textContaining(S.plannerNoClimb), findsNothing);
    expect(
      find.textContaining('${S.plannerAbout} 0 ${S.plannerMinutesOnly}'),
      findsNothing,
    );
  });

  testWidgets('清空后可以撤销（轨迹点与航点一起恢复）', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(400, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(S.plannerMore));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空重画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('0.00 km'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 点 / 0 航点'), findsOneWidget);
  });

  testWidgets('选中点后可删除；撤销恢复', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(400, 300));
    await _tapMap(tester, const Offset(550, 300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vertex-1')));
    await tester.pump();
    expect(find.textContaining(S.plannerDeletePoint), findsOneWidget);
    await tester.tap(find.textContaining(S.plannerDeletePoint));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 点 / 0 航点'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 点 / 0 航点'), findsOneWidget);
  });

  testWidgets('拖动轨迹点：改的是点，不是平移地图；距离跟着变', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(400, 300));
    await tester.pumpAndSettle();
    String km() =>
        tester.widgetList<Text>(find.textContaining(' km')).first.data!;
    final before = km();
    await tester.drag(
      find.byKey(const ValueKey('vertex-1')),
      const Offset(150, 0),
    );
    await tester.pumpAndSettle();
    final after = km();
    expect(
      double.parse(after.split(' ').first),
      greaterThan(double.parse(before.split(' ').first) * 1.8),
    );
    // 第一个点没被拖走（地图没有平移）
    expect(
      tester.getCenter(find.byKey(const ValueKey('vertex-0'))).dx,
      closeTo(250, 2),
    );
  });

  testWidgets('真机触摸阈值（约 8 px，地图先接管拖动）下，拖圆点仍是改点不是平移地图', (tester) async {
    tester.view.gestureSettings = const ui.GestureSettings(
      physicalTouchSlop: 24, // 测试视图 3 倍像素 → 8 逻辑像素
    );
    addTearDown(tester.view.resetGestureSettings);
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(400, 300));
    await tester.pumpAndSettle();
    // 小步移动（像手指一样），而不是一步到位
    final g = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('vertex-1'))),
    );
    for (var i = 0; i < 30; i++) {
      await g.moveBy(const Offset(4, 0));
      await tester.pump(const Duration(milliseconds: 8));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(const ValueKey('vertex-0'))).dx,
      closeTo(250, 2),
      reason: '地图没有平移',
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('vertex-1'))).dx,
      closeTo(520, 3),
    );
  });

  testWidgets('拖线段中间的小点插入新点', (tester) async {
    final dem = _fakeDem();
    addTearDown(dem.dispose);
    await _pump(tester, dem);
    await _tapMap(tester, const Offset(250, 300));
    await _tapMap(tester, const Offset(550, 300));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mid-0')), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('mid-0')),
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('3 点 / 0 航点'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('vertex-1'))).dy,
      closeTo(220, 3),
    );
  });
}
