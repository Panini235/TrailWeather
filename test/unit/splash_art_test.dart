import 'package:flutter_test/flutter_test.dart';
import 'package:trailweather/ui/splash/splash_art.dart';

void main() {
  group('SplashSky：按本地时钟摆放太阳或月亮', () {
    test('6–19 时为太阳，从左低到正午最高再到右低', () {
      final dawn = SplashSky.at(DateTime(2026, 10, 17, 6));
      final noon = SplashSky.at(DateTime(2026, 10, 17, 12, 30));
      final dusk = SplashSky.at(DateTime(2026, 10, 17, 18, 59));
      expect([dawn.night, noon.night, dusk.night], [false, false, false]);
      expect(dawn.x, lessThan(noon.x));
      expect(noon.x, lessThan(dusk.x));
      // 图标坐标系 y 向下：正午最高（y 最小），早晚低。
      expect(noon.y, lessThan(dawn.y));
      expect(noon.y, lessThan(dusk.y));
      expect(noon.y, closeTo(330, 1));
    });

    test('19 时以后、6 时以前为月亮', () {
      expect(SplashSky.at(DateTime(2026, 10, 17, 19)).night, isTrue);
      expect(SplashSky.at(DateTime(2026, 10, 17, 23, 59)).night, isTrue);
      expect(SplashSky.at(DateTime(2026, 10, 17, 5, 59)).night, isTrue);
    });
  });

  group('splashModeFor：当天第一次完整，之后缩短，减少动效时静态', () {
    final now = DateTime(2026, 10, 17, 8, 30);

    test('当天未播过完整版 → full', () {
      expect(
        splashModeFor(local: now, lastFullDay: null, reduced: false),
        SplashMode.full,
      );
      expect(
        splashModeFor(local: now, lastFullDay: '2026-10-16', reduced: false),
        SplashMode.full,
      );
    });

    test('当天已播过 → short；减少动效优先 → still', () {
      expect(splashDayKey(now), '2026-10-17');
      expect(
        splashModeFor(local: now, lastFullDay: '2026-10-17', reduced: false),
        SplashMode.short,
      );
      expect(
        splashModeFor(local: now, lastFullDay: null, reduced: true),
        SplashMode.still,
      );
    });
  });
}
