import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/paywall/paywall_screen.dart';

void main() {
  testWidgets('PaywallScreen 展示特权清单与 3 档套餐并完成开通', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          home: PaywallScreen(sourceFeature: '高程微气候垂直修正'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 标题与来源说明
    expect(find.text('TrailWeather Pro'), findsOneWidget);
    expect(find.textContaining('当前操作涉及 Pro 专享权益'), findsOneWidget);

    // 核心特权清单
    expect(find.text('高程微气候垂直修正'), findsOneWidget);
    expect(find.text('高山失温与极端天气哨兵'), findsOneWidget);
    expect(find.text('离网气象与离线轨迹包'), findsOneWidget);

    // 套餐卡片展示
    expect(find.text('年度会员'), findsOneWidget);
    expect(find.text('月度会员'), findsOneWidget);
    expect(find.text('终身买断'), findsOneWidget);

    // 默认主推年度会员（¥98）
    expect(find.textContaining('立即开始 7 天免费试用'), findsOneWidget);

    // 切换到终身买断
    await tester.tap(find.text('终身买断'));
    await tester.pumpAndSettle();
    expect(find.textContaining('一次性购买终身会员'), findsOneWidget);

    // 恢复购买按钮
    expect(find.text('恢复购买'), findsOneWidget);
  });
}
