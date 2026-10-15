import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/planner/route_planner_screen.dart';

void main() {
  testWidgets('RoutePlannerScreen 渲染地图规划画板、模式切换与底栏状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: RoutePlannerScreen()),
      ),
    );
    await tester.pump();

    // 标题
    expect(find.textContaining('线路规划工坊'), findsOneWidget);

    // 模式切换
    expect(find.text('打点画线'), findsOneWidget);
    expect(find.text('标记营地/水源'), findsOneWidget);

    // 初始底栏状态
    expect(find.text('0.00 km'), findsOneWidget);
    expect(find.text('轻触地图任意处开始徒步规划'), findsOneWidget);

    // 切换到标记营地/水源模式
    await tester.tap(find.text('标记营地/水源'));
    await tester.pump();

    // 检查控制按钮存在
    expect(find.byIcon(Icons.undo), findsOneWidget);
    expect(find.byIcon(Icons.swap_calls), findsOneWidget);
    expect(find.byIcon(Icons.file_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
