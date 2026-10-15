import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/map/tile_sources.dart';
import 'package:trailweather/data/photos/photo_picker.dart';
import 'package:trailweather/data/photos/photo_store.dart';
import 'package:trailweather/data/photos/route_photos.dart';
import 'package:trailweather/data/settings/settings_repository.dart';
import 'package:trailweather/ui/detail/node_photos.dart';
import 'package:trailweather/ui/map/map_layers_ui.dart';
import 'package:trailweather/ui/strings.dart';

// 1x1 透明 PNG。
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

class _FakePicker implements PhotoPicker {
  int calls = 0;

  @override
  Future<PickedPhoto?> pick(PhotoPickSource source) async {
    calls++;
    return PickedPhoto(_png, 'png');
  }
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget child, {
  List overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [prefsProvider.overrideWithValue(prefs), ...overrides.cast()],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(home: Scaffold(body: child)),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('图层面板：切换底图、坐标系不同的叠加层不可选、天地图需 Key', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = await _pump(tester, const MapLayerPanel());

    // 默认高德（GCJ-02）：WGS-84 的等高线叠加层不可开。
    final topoSwitch = find.widgetWithText(SwitchListTile, 'OpenTopoMap 等高线');
    expect(tester.widget<SwitchListTile>(topoSwitch).onChanged, isNull);

    // 天地图底图未填 Key 时不可选。
    // 底图区在前，叠加区（SwitchListTile 内部也是 ListTile）在后。
    final tdtTile = find.widgetWithText(ListTile, '天地图影像（卫星）').first;
    expect(tester.widget<ListTile>(tdtTile).enabled, isFalse);

    // 切到 OSM（WGS-84）后，等高线可以叠加。
    await tester.tap(find.widgetWithText(ListTile, 'OpenStreetMap').first);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).baseLayerId, 'osm');
    await tester.tap(topoSwitch);
    await tester.pumpAndSettle();
    expect(c.read(settingsProvider).overlayLayers.map((o) => o.id), [
      'opentopomap',
    ]);
    expect(find.text(S.overlayOpacity), findsOneWidget);

    // 填写 Key 后天地图可选。
    await c.read(settingsProvider.notifier).setTiandituKey('k');
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(tdtTile).enabled, isTrue);
  });

  testWidgets('自定义图源：校验失败给出原因，合法后保存', (tester) async {
    final c = await _pump(tester, const CustomTileSourcesCard());
    await tester.tap(find.text(S.addCustomTileSource));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '我的等高线');
    await tester.enterText(
      fields.at(1),
      'https://tiles.example.com/{z}/{x}.png',
    );
    await tester.tap(find.text(S.ok));
    await tester.pumpAndSettle();
    expect(find.textContaining('{y}'), findsWidgets);
    expect(c.read(settingsProvider).customTileSources, isEmpty);

    await tester.enterText(
      fields.at(1),
      'https://tiles.example.com/{z}/{x}/{y}.png',
    );
    await tester.tap(find.text(S.ok));
    await tester.pumpAndSettle();
    final saved = c.read(settingsProvider).customTileSources.single;
    expect(saved.name, '我的等高线');
    expect(saved.datum, TileDatum.wgs84);
    expect(find.text('我的等高线'), findsOneWidget);

    // 自定义来源出现在可选来源中。
    expect(findTileSource(saved.id, [saved]), isNotNull);
  });

  testWidgets('节点图片：添加后显示缩略图，可删除', (tester) async {
    final picker = _FakePicker();
    final store = MemoryPhotoStore();
    final c = await _pump(
      tester,
      const NodePhotosSection(routeId: 'r1', pos: LatLng(30, 120)),
      overrides: [
        photoPickerProvider.overrideWithValue(picker),
        photoStoreProvider.overrideWithValue(store),
      ],
    );
    expect(find.text(S.noNodePhotos), findsOneWidget);

    await tester.tap(find.text(S.photoFromGallery));
    await tester.pumpAndSettle();
    expect(picker.calls, 1);
    expect(c.read(routePhotosProvider), hasLength(1));
    expect(find.byType(RoutePhotoImage), findsOneWidget);

    await tester.tap(find.byType(RoutePhotoImage));
    await tester.pumpAndSettle();
    await tester.tap(find.text(S.photoDelete));
    await tester.pumpAndSettle();
    expect(c.read(routePhotosProvider), isEmpty);
    expect(store.files, isEmpty);
    expect(find.text(S.noNodePhotos), findsOneWidget);
  });
}
