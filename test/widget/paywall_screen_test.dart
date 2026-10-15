import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/paywall/paywall_screen.dart';

void main() {
  testWidgets('PaywallScreen 展示权益规划与套餐，支付未接入时不可开通', (tester) async {
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
    expect(find.text('山晴 Pro'), findsOneWidget);
    expect(find.textContaining('当前操作涉及 Pro 专享权益'), findsOneWidget);

    // 核心特权清单
    expect(find.text('高程微气候垂直修正'), findsOneWidget);
    expect(find.text('高山失温与极端天气哨兵'), findsOneWidget);
    expect(find.text('离网气象与离线轨迹包'), findsOneWidget);

    // 套餐卡片展示
    expect(find.text('年度会员'), findsOneWidget);
    expect(find.text('月度会员'), findsOneWidget);
    expect(find.text('终身买断'), findsOneWidget);

    // 支付未接入：明确告知、购买按钮禁用、未实现权益标“开发中”
    expect(find.textContaining('支付尚未接入'), findsOneWidget);
    expect(find.text('开发中'), findsNWidgets(4));
    final buy = find.widgetWithText(FilledButton, '支付未接入，暂不可开通');
    expect(buy, findsOneWidget);
    expect(tester.widget<FilledButton>(buy).onPressed, isNull);
    expect(find.textContaining('7 天免费试用'), findsNothing);
    expect(find.text('¥398'), findsNothing); // 不展示虚构原价

    // 恢复购买按钮
    expect(find.text('恢复购买'), findsOneWidget);
  });
}
