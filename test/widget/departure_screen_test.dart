import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/data/weather/departure_provider.dart';
import 'package:trailweather/data/weather/departure_windows.dart';
import 'package:trailweather/data/weather/eta.dart';
import 'package:trailweather/ui/departure/departure_screen.dart';
import 'package:trailweather/ui/departure/departure_threshold_screen.dart';

import '../support/departure_fixtures.dart';

Future<
  (
    DepartureWeatherFixture,
    ProviderContainer,
    ValueNotifier<DepartureSelection?>,
  )
>
pumpDeparture(
  WidgetTester tester, {
  double scale = 1,
  bool dark = false,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final fake = DepartureWeatherFixture();
  final selection = ValueNotifier<DepartureSelection?>(null);
  addTearDown(selection.dispose);
  final args = DepartureArgs(
    route: departureTestRoute,
    nodes: departureTestNodes,
    pace: PaceConfig.defaults,
    providerId: fake.caps.providerId,
    initialDate: DateTime(2026, 10, 17),
    reversed: true,
  );
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, _) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => selection.value = await context
                  .push<DepartureSelection>('/departures', extra: args),
              child: const Text('开启比较'),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/departures',
        builder: (_, state) =>
            DepartureScreen(args: state.extra! as DepartureArgs),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        weatherProvidersProvider.overrideWithValue([fake]),
        weatherNowProvider.overrideWithValue(
          () => DateTime(2026, 10, 17, 6).toUtc(),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          useMaterial3: true,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('开启比较'));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(DepartureScreen)),
  );
  return (fake, container, selection);
}

Finder firstDepartureCell() => find.byKey(
  ValueKey('departure-${DateTime(2026, 10, 17, 7).toUtc().toIso8601String()}'),
);

Future<void> showFirstCell(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    firstDepartureCell(),
    300,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('十五格合并请求，调整阈值本地重算，点击依据并应用时刻', (tester) async {
    final (fake, container, selected) = await pumpDeparture(tester);
    expect(fake.calls, 1);
    expect(fake.requestedStart, DateTime(2026, 10, 17, 7).toUtc());
    expect(fake.requestedEnd, DateTime(2026, 10, 19, 18).toUtc());
    final newSettings = container
        .read(settingsProvider)
        .copyWith(
          departureThresholds: const DepartureThresholds(
            gustYellow: 5,
            gustRed: 6,
          ),
        );
    await container.read(settingsProvider.notifier).update(newSettings);
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    await showFirstCell(tester);
    expect(find.textContaining('红色阈值'), findsWidgets);
    await tester.tap(firstDepartureCell());
    await tester.pumpAndSettle();
    expect(find.text('出发依据'), findsOneWidget);
    expect(find.textContaining('最大阵风'), findsOneWidget);
    expect(find.textContaining('fixture-model'), findsWidgets);
    await tester.tap(find.text('用这个时间查看行程'));
    await tester.pumpAndSettle();
    expect(selected.value!.startUtc, DateTime(2026, 10, 17, 7).toUtc());
    expect(selected.value!.providerId, fake.caps.providerId);
    expect(find.text('开启比较'), findsOneWidget);
  });

  testWidgets('主动刷新失败仍显示已保存的格子和原始时间', (tester) async {
    final (fake, _, _) = await pumpDeparture(tester);
    fake.fail = true;
    await tester.tap(find.byTooltip('刷新出发窗口'));
    await tester.pumpAndSettle();
    expect(fake.calls, 2);
    expect(find.textContaining('刷新失败，保留'), findsOneWidget);
    await showFirstCell(tester);
    expect(find.textContaining('信息不足'), findsWidgets);
    await tester.tap(firstDepartureCell());
    await tester.pumpAndSettle();
    expect(find.textContaining('继续显示上次保存的预报'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets('360px / 2倍字号 / ${dark ? '深色' : '浅色'}表格和证据无溢出', (tester) async {
      await pumpDeparture(tester, scale: 2, dark: dark);
      expect(tester.takeException(), isNull);
      await showFirstCell(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(firstDepartureCell());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('departure-node-0')),
        300,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.text(departureTestNodes.first.describe()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(departureTestNodes.first.describe()));
      await tester.pumpAndSettle();
      expect(find.textContaining('请求坐标：'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('编辑阈值校验关系、持久化，取消不会改设置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"lowPower":true}',
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [prefsProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DepartureThresholdScreen(),
                  ),
                ),
                child: const Text('编辑'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '20');
    await tester.tap(find.text('保存阈值'));
    await tester.pumpAndSettle();
    expect(find.textContaining('黄色阵风须小于'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), '10');
    await tester.tap(find.text('保存阈值'));
    await tester.pumpAndSettle();
    final restored = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(restored.dispose);
    expect(restored.read(settingsProvider).departureThresholds.gustYellow, 10);
    expect(restored.read(settingsProvider).lowPower, true);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '5');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.text('编辑')),
    );
    expect(container.read(settingsProvider).departureThresholds.gustYellow, 10);
  });

  test('按次来源禁止批量获取；改变阈值不会重建真实来源和仓库', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = DepartureWeatherFixture()..onlyOnDemand = true;
    final c = ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        weatherProvidersProvider.overrideWithValue([fake]),
      ],
    );
    addTearDown(c.dispose);
    final key = DepartureFetchKey(
      nodes: departureTestNodes,
      providerId: fake.caps.providerId,
      startUtc: departureTestStart,
      endUtc: departureTestStart.add(const Duration(days: 3)),
    );
    await expectLater(
      c.read(departureWeatherProvider(key).future),
      throwsStateError,
    );
    expect(fake.calls, 0);
    final actual = ProviderContainer(
      overrides: [prefsProvider.overrideWithValue(prefs)],
    );
    addTearDown(actual.dispose);
    final before = actual.read(weatherRepositoryProvider);
    await actual
        .read(settingsProvider.notifier)
        .update(
          actual
              .read(settingsProvider)
              .copyWith(
                departureThresholds: const DepartureThresholds(
                  gustYellow: 5,
                  gustRed: 6,
                ),
              ),
        );
    expect(identical(actual.read(weatherRepositoryProvider), before), true);
  });
}
