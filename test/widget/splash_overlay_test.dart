import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/splash/splash_art.dart';
import 'package:trailweather/ui/splash/splash_overlay.dart';
import 'package:trailweather/ui/strings.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _pump(
  WidgetTester tester,
  SharedPreferences prefs, {
  DateTime? local,
  bool disableAnimations = false,
}) async {
  final nowUtc = (local ?? DateTime(2026, 10, 17, 8, 30)).toUtc();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        weatherNowProvider.overrideWithValue(() => nowUtc),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: disableAnimations),
          child: SplashOverlay(child: child!),
        ),
        home: const Scaffold(body: Text('首页内容')),
      ),
    ),
  );
}

SplashPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.byWidgetPredicate(
                (w) => w is CustomPaint && w.painter is SplashPainter,
              ),
            )
            .painter!
        as SplashPainter;

void _expectIdle() {
  expect(SchedulerBinding.instance.transientCallbackCount, 0);
  expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
}

void main() {
  testWidgets('当天第一次：完整组装、有“跳过动画”，跳过后移除开屏且不再画帧', (tester) async {
    final prefs = await _prefs();
    await _pump(tester, prefs);
    expect(find.text(S.splashSkip), findsOneWidget);
    expect(find.text(S.splashTagline), findsOneWidget);
    expect(_painter(tester).sky.night, isFalse);
    expect(
      prefs.getString(SplashOverlay.lastFullDayKey),
      splashDayKey(DateTime(2026, 10, 17)),
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(S.splashSkip));
    // 跳过后退场 220 ms；按 100 ms 一帧计，含启动帧与收尾帧不超过 5 帧。
    expect(await tester.pumpAndSettle(), lessThanOrEqualTo(5));
    expect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is SplashPainter,
      ),
      findsNothing,
    );
    expect(find.text(S.splashSkip), findsNothing);
    expect(find.text('首页内容'), findsOneWidget);
    _expectIdle();
  });

  testWidgets('字标使用正常文字样式（不是缺少 Material 时的黄色双下划线）', (tester) async {
    await _pump(tester, await _prefs());
    await tester.pump(SplashArt.fullDuration);
    final rich = tester.widget<RichText>(
      find.descendant(
        of: find.byType(SplashOverlay),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == S.appTitle,
        ),
      ),
    );
    final decoration = rich.text.style?.decoration;
    expect(decoration == null || decoration == TextDecoration.none, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('完整版不点跳过：1.6 秒内结束', (tester) async {
    await _pump(tester, await _prefs());
    expect(await tester.pumpAndSettle(), lessThanOrEqualTo(16));
    expect(find.text(S.splashSkip), findsNothing);
    _expectIdle();
  });

  testWidgets('当天再次启动：快速淡入，无跳过按钮，0.7 秒内结束', (tester) async {
    final prefs = await _prefs({
      SplashOverlay.lastFullDayKey: splashDayKey(DateTime(2026, 10, 17)),
    });
    await _pump(tester, prefs);
    expect(find.text(S.splashSkip), findsNothing);
    expect(await tester.pumpAndSettle(), lessThanOrEqualTo(7));
    expect(find.text(S.splashTagline), findsNothing);
    _expectIdle();
  });

  testWidgets('系统减少动效：静态图标，无跳过按钮', (tester) async {
    await _pump(tester, await _prefs(), disableAnimations: true);
    expect(find.text(S.splashSkip), findsNothing);
    expect(find.text(S.splashTagline), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(S.splashTagline), findsNothing);
    _expectIdle();
  });

  testWidgets('低耗电模式同样静态', (tester) async {
    final prefs = await _prefs({'settings.v1': '{"lowPower":true}'});
    await _pump(tester, prefs);
    expect(find.text(S.splashSkip), findsNothing);
    await tester.pumpAndSettle();
    _expectIdle();
  });

  testWidgets('夜里换成月亮', (tester) async {
    await _pump(tester, await _prefs(), local: DateTime(2026, 10, 17, 22));
    expect(_painter(tester).sky.night, isTrue);
    await tester.pumpAndSettle();
  });

  testWidgets('深色模式下文字与底色对比度达标', (tester) async {
    final prefs = await _prefs();
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(prefs),
          weatherNowProvider.overrideWithValue(
            () => DateTime(2026, 10, 17, 8).toUtc(),
          ),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => SplashOverlay(child: child!),
          home: const Scaffold(body: SizedBox()),
        ),
      ),
    );
    await tester.pump(SplashArt.fullDuration);
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
