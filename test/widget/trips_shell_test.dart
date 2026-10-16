import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/app.dart';
import 'package:trailweather/data/app_providers.dart';
import 'package:trailweather/data/location/location_service.dart';
import 'package:trailweather/data/routes/incoming_file_source.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/data/settings/favorites_repository.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/strings.dart';
import 'package:trailweather/ui/onboarding/onboarding_screen.dart';
import 'package:trailweather/ui/settings/settings_screen.dart';

class _DeniedLocationService implements LocationService {
  @override
  Future<LocationFix> currentPosition({
    void Function(LatLng)? onLastKnown,
    bool requestPermission = true,
  }) async =>
      throw const LocationFailure(LocationFailureKind.denied, '未获得定位权限。');

  @override
  Future<bool> openSettings(LocationFailureKind kind) async => false;
}

class _FakeIncoming implements IncomingFileSource {
  _FakeIncoming({this.initial, required this.bytes});

  final IncomingFile? initial;
  final Uint8List bytes;
  final controller = StreamController<IncomingFile>.broadcast();

  @override
  Stream<IncomingFile> get files => controller.stream;

  @override
  Future<IncomingFile?> initialFile() async => initial;

  @override
  Future<Uint8List> readBytes(IncomingFile file) async => bytes;
}

const _gpx = '''<?xml version="1.0"?>
<gpx version="1.1"><trk><name>外部传入线路</name><trkseg>
<trkpt lat="39.05" lon="113.65"><ele>2500</ele></trkpt>
<trkpt lat="39.06" lon="113.66"><ele>2600</ele></trkpt>
</trkseg></trk></gpx>''';

HikingRoute _trip(String id, String name) => HikingRoute(
  id: id,
  name: name,
  origin: RouteOrigin.import,
  segments: const [
    [LatLng(39.05, 113.65), LatLng(39.06, 113.66)],
  ],
  elevationsM: const [2500, 2600],
  sourceName: '用户导入',
);

Future<SharedPreferences> _prefs({List<HikingRoute> trips = const []}) async {
  SharedPreferences.setMockInitialValues({
    'settings.v1': jsonEncode(
      const AppSettings()
          .copyWith(
            hasCompletedOnboarding: true,
            privacyAcceptedVersion: AppSettings.privacyNoticeVersion,
          )
          .toJson(),
    ),
    'favorites.v1': jsonEncode([for (final t in trips) t.toJson()]),
  });
  return SharedPreferences.getInstance();
}

Future<void> _pumpApp(
  WidgetTester tester,
  SharedPreferences prefs, {
  IncomingFileSource incoming = const NoIncomingFiles(),
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        locationServiceProvider.overrideWithValue(_DeniedLocationService()),
        sampleRoutesProvider.overrideWith((ref) async => const []),
        incomingFileSourceProvider.overrideWithValue(incoming),
      ],
      child: const TrailWeatherApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 解析在 compute（真实 isolate）中进行，需让出真实时间再推进帧。
Future<void> _settleIsolate(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('首页是“我的行程”；空状态引导导入与手绘', (tester) async {
    await _pumpApp(tester, await _prefs());

    expect(find.text(S.myTrips), findsOneWidget);
    expect(find.text(S.emptyTripsTitle), findsOneWidget);
    expect(find.widgetWithText(FilledButton, S.importRoute), findsOneWidget);
    expect(find.text(S.planetEntry), findsOneWidget);
    // 底部导航三个分支
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(S.tabMap), findsOneWidget);
  });

  testWidgets('行程列表展示线路要点，可删除；底部导航切换到设置再回来', (tester) async {
    final prefs = await _prefs(trips: [_trip('t1', '五台山大朝台')]);
    await _pumpApp(tester, prefs);

    expect(find.text('五台山大朝台'), findsOneWidget);
    expect(find.textContaining('↑100 m'), findsOneWidget);
    expect(find.text(S.emptyTripsTitle), findsNothing);

    await tester.tap(find.text(S.tabSettings));
    await tester.pumpAndSettle();
    expect(find.text(S.myTrips), findsNothing);
    expect(find.textContaining('山晴 Pro'), findsNothing);
    expect(find.text('查看方案预览'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('查看使用指引'),
      350,
      scrollable: find
          .descendant(
            of: find.byType(SettingsScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('会员方案与权益对比'), findsNothing);
    expect(find.textContaining('(PRO)'), findsNothing);
    await tester.tap(find.text(S.tabTrips));
    await tester.pumpAndSettle();
    expect(find.text('五台山大朝台'), findsOneWidget);

    await tester.tap(find.byTooltip(S.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.delete).last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, S.delete));
    await tester.pumpAndSettle();
    expect(find.text('五台山大朝台'), findsNothing);
    expect(find.text(S.emptyTripsTitle), findsOneWidget);
  });

  testWidgets('旧付费墙链接返回首页，不展示套餐', (tester) async {
    await _pumpApp(tester, await _prefs());
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    container.read(appRouterProvider).go('/paywall');
    await tester.pumpAndSettle();
    expect(find.text(S.myTrips), findsOneWidget);
    expect(find.text('年度会员'), findsNothing);
    expect(find.textContaining('山晴 Pro'), findsNothing);
  });

  testWidgets('外部应用传入文件：解析 → 确认 → 保存到行程', (tester) async {
    final prefs = await _prefs();
    final incoming = _FakeIncoming(
      initial: const IncomingFile(uri: 'content://x/1', name: 'a.gpx'),
      bytes: Uint8List.fromList(utf8.encode(_gpx)),
    );
    await _pumpApp(tester, prefs, incoming: incoming);
    await _settleIsolate(tester);

    expect(find.text('导入：外部传入线路'), findsOneWidget);
    await tester.tap(find.text(S.saveToTrips));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Navigator).first),
    );
    expect(
      container.read(favoritesProvider).map((r) => r.name),
      contains('外部传入线路'),
    );
  });

  testWidgets('首次启动：先同意隐私说明，再处理外部传入的文件', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final incoming = _FakeIncoming(
      initial: const IncomingFile(uri: 'content://x/3', name: 'c.gpx'),
      bytes: Uint8List.fromList(utf8.encode(_gpx)),
    );
    await _pumpApp(tester, prefs, incoming: incoming);
    await _settleIsolate(tester);
    expect(find.byType(OnboardingScreen), findsOneWidget);
    expect(find.text('导入：外部传入线路'), findsNothing);

    await tester.tap(find.text(S.privacyAgree));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('先看示例线路'));
    await tester.tap(find.text('先看示例线路'));
    await _settleIsolate(tester);
    expect(find.byType(OnboardingScreen), findsNothing);
    expect(find.text('导入：外部传入线路'), findsOneWidget);
  });

  testWidgets('老用户未同意过隐私说明：再次进入引导页', (tester) async {
    SharedPreferences.setMockInitialValues({
      'settings.v1': '{"hasCompletedOnboarding":true}',
    });
    await _pumpApp(tester, await SharedPreferences.getInstance());
    expect(find.byType(OnboardingScreen), findsOneWidget);
  });

  testWidgets('外部传入无法识别的文件给出明确错误，不保存', (tester) async {
    final prefs = await _prefs();
    final incoming = _FakeIncoming(
      bytes: Uint8List.fromList(utf8.encode('not a track')),
    );
    await _pumpApp(tester, prefs, incoming: incoming);

    incoming.controller.add(
      const IncomingFile(uri: 'content://x/2', name: 'b.bin'),
    );
    await _settleIsolate(tester);
    expect(find.textContaining('无法导入 b.bin'), findsOneWidget);
    expect(find.text(S.emptyTripsTitle), findsOneWidget);
  });
}
