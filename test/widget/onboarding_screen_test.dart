import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/onboarding/onboarding_screen.dart';

void main() {
  testWidgets('OnboardingScreen 经历问诊、价值唤醒、功能赋能并提供试用', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Page 0: 痛点问诊
    expect(find.text('你最常在什么场景下徒步？'), findsOneWidget);
    expect(find.textContaining('高海拔多日重装徒步'), findsOneWidget);
    expect(find.textContaining('单日郊野登山'), findsOneWidget);

    // 点击切换场景选项
    await tester.tap(find.textContaining('单日郊野登山'));
    await tester.pumpAndSettle();

    // 点击下一步进入 Page 1: 价值唤醒
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('为什么普通天气预报在山里不准？'), findsOneWidget);
    expect(find.textContaining('普通手机天气'), findsOneWidget);
    expect(find.textContaining('TrailWeather 空间微气候推演'), findsOneWidget);
    expect(find.textContaining('失温哨兵'), findsNothing);

    // 点击下一步进入 Page 2: 全能功能展示
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('全能户外路线与气象工坊'), findsOneWidget);
    expect(find.textContaining('徒步星球 · 44+ 条全球顶级经典神线'), findsOneWidget);

    // 点击下一步进入 Page 3: 权益与试用选择
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.textContaining('TrailWeather Pro（规划中）'), findsOneWidget);
    expect(find.textContaining('支付尚未接入'), findsOneWidget);
    expect(find.text('查看 Pro 方案预览'), findsOneWidget);
    expect(find.text('开始免费使用'), findsOneWidget);
  });
}
