import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/ui/weather_refresh_clock.dart';

void main() {
  testWidgets('前台跨午夜推进时间，后台不轮询，恢复检查时效', (tester) async {
    var now = DateTime.utc(2026, 10, 16, 23, 59);
    final clock = WeatherRefreshClock(initialUtc: now, nowUtc: () => now);
    var changes = 0;
    clock.addListener(() => changes++);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(clock.value, now);
    expect(changes, 1);
    clock.didChangeAppLifecycleState(AppLifecycleState.paused);
    now = now.add(const Duration(hours: 4));
    await tester.pump(const Duration(hours: 4));
    expect(changes, 1);
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(clock.value, now);
    expect(changes, 2);
    clock.dispose();
    await tester.pump(const Duration(hours: 1));
    expect(changes, 2);
  });

  testWidgets('短暂前后台切换不触发重复请求，同小时过期检查会触发', (tester) async {
    var now = DateTime.utc(2026, 10, 16, 10);
    final clock = WeatherRefreshClock(initialUtc: now, nowUtc: () => now);
    var changes = 0;
    clock.addListener(() => changes++);
    now = now.add(const Duration(minutes: 2));
    clock.didChangeAppLifecycleState(AppLifecycleState.paused);
    clock.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(changes, 0);
    now = now.add(const Duration(minutes: 14));
    clock.check();
    expect(changes, 1);
    clock.dispose();
  });
}
