import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/core/cache_store.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/weather_repository.dart';
import 'package:trailweather/ui/map/point_weather_sheet.dart';
import 'package:trailweather/ui/theme.dart';

import '../weather/cache_freshness_test.dart' show WindowProvider, ageCache;

void main() {
  for (final fails in [false, true]) {
    testWidgets('点位天气页面实际接收缓存后的${fails ? '失败状态' : '新预报'}', (tester) async {
      tester.view.physicalSize = const Size(390, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'settings.v1': '{"enabledProviderIds":["fake:test"]}',
      });
      final prefs = await SharedPreferences.getInstance();
      final provider = WindowProvider();
      final repo = WeatherRepository(
        cache: CacheStore(prefs),
        providers: [provider],
      );
      final now = DateTime.utc(2026, 10, 16, 23);
      await fetchPointWeather(
        repo,
        providerId: 'fake:test',
        point: const LatLng(30, 120),
        label: '测试位置',
        requestedAtUtc: now,
      );
      await ageCache(prefs);
      provider.temperature = 22;
      provider.offline = fails;
      if (!fails) provider.gate = Completer<void>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            prefsProvider.overrideWithValue(prefs),
            weatherProvidersProvider.overrideWithValue([provider]),
            weatherRepositoryProvider.overrideWithValue(repo),
            weatherNowProvider.overrideWithValue(() => now),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: PointWeatherSheet(
                point: const LatLng(30, 120),
                label: '测试位置',
                requestedAtUtc: now,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('12°C'), findsOneWidget);
      if (fails) {
        await tester.pumpAndSettle();
        expect(find.textContaining('更新失败，继续显示已保存的数据'), findsOneWidget);
        expect(find.text('重新更新'), findsOneWidget);
      } else {
        expect(find.textContaining('正在更新，先显示已保存的数据'), findsOneWidget);
        provider.gate!.complete();
        await tester.pumpAndSettle();
        expect(find.text('22°C'), findsOneWidget);
        expect(find.text('12°C'), findsNothing);
        expect(find.textContaining('正在更新，先显示已保存的数据'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
