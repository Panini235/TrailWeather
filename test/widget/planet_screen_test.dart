import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/routes/planet_trails_repository.dart';
import 'package:trailweather/data/routes/route_models.dart';
import 'package:trailweather/ui/planet/planet_screen.dart';

final List<HikingRoute> _testRoutes = [
  HikingRoute(
    id: 'test-tmb',
    name: '环勃朗峰 TMB',
    region: '法国 / 意大利 / 瑞士',
    origin: RouteOrigin.planet,
    category: 'snow',
    sourceName: '徒步星球',
    segments: const [
      [LatLng(45.8, 6.8), LatLng(45.9, 6.9)],
    ],
    elevationsM: const [1000.0, 2500.0],
  ),
  HikingRoute(
    id: 'test-tiger',
    name: '虎跳峡高路徒步',
    region: '中国云南',
    origin: RouteOrigin.planet,
    category: 'canyon',
    sourceName: '徒步星球',
    segments: const [
      [LatLng(27.2, 100.1), LatLng(27.3, 100.2)],
    ],
    elevationsM: const [1800.0, 2600.0],
  ),
];

Widget _wrap(Widget child) => ProviderScope(
  overrides: [planetTrailsProvider.overrideWith((ref) async => _testRoutes)],
  child: MaterialApp(theme: ThemeData(useMaterial3: true), home: child),
);

void main() {
  testWidgets('PlanetTrailsScreen 展示分类 Chip 并列出全球经典路线', (tester) async {
    await tester.pumpWidget(_wrap(const PlanetTrailsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('徒步星球 · 全球经典'), findsOneWidget);
    expect(find.text('🌍 全部'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '🏔️ 雪山'), findsOneWidget);

    // 默认“全部”分类下显示两条路线
    expect(find.textContaining('环勃朗峰 TMB'), findsOneWidget);
    expect(find.textContaining('虎跳峡高路徒步'), findsOneWidget);

    // 切换到“雪山”分类
    await tester.tap(find.widgetWithText(ChoiceChip, '🏔️ 雪山'));
    await tester.pumpAndSettle();

    // 仅显示雪山路线，峡谷路线被过滤
    expect(find.textContaining('环勃朗峰 TMB'), findsOneWidget);
    expect(find.textContaining('虎跳峡高路徒步'), findsNothing);

    // 随机漫游按钮存在
    expect(find.byIcon(Icons.shuffle), findsOneWidget);
  });
}
