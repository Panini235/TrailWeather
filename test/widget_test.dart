import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/app.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

// 覆盖此文件以防止 CI 中 `flutter create` 生成引用模板符号的默认测试。
void main() {
  testWidgets('App 启动 smoke：路由到地图首页并渲染脚手架', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: const TrailWeatherApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Scaffold), findsWidgets);
  });
}
