import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trailweather/data/photos/photo_store.dart';
import 'package:trailweather/data/photos/route_photos.dart';
import 'package:trailweather/data/settings/settings_repository.dart';

void main() {
  test('添加、备注、删除图片并持久化；删除同时移除文件', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = MemoryPhotoStore();
    ProviderContainer make() => ProviderContainer(
      overrides: [
        prefsProvider.overrideWithValue(prefs),
        photoStoreProvider.overrideWithValue(store),
      ],
    );

    final c1 = make();
    final photo = await c1
        .read(routePhotosProvider.notifier)
        .add(
          routeId: 'r1',
          pos: const LatLng(30, 120),
          bytes: Uint8List.fromList([1, 2, 3]),
          extension: 'jpg',
        );
    await c1.read(routePhotosProvider.notifier).updateCaption(photo.id, '垭口');
    expect(store.files[photo.storageKey], [1, 2, 3]);
    c1.dispose();

    // 重建容器：从 prefs 恢复。
    final c2 = make();
    final restored = c2.read(routePhotosProvider).single;
    expect(restored.caption, '垭口');
    expect(restored.pos, const LatLng(30, 120));

    await c2.read(routePhotosProvider.notifier).remove(restored);
    expect(c2.read(routePhotosProvider), isEmpty);
    expect(store.files, isEmpty);
    c2.dispose();
  });

  test('photosNear 只取同线路、半径内的图片', () {
    RoutePhoto p(String id, String route, double lat) => RoutePhoto(
      id: id,
      routeId: route,
      lat: lat,
      lon: 120,
      storageKey: '$id.jpg',
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );
    final all = [
      p('a', 'r1', 30.0000),
      p('b', 'r1', 30.0003), // 约 33 m
      p('c', 'r1', 30.0010), // 约 111 m
      p('d', 'r2', 30.0000),
    ];
    expect(
      [for (final x in photosNear(all, 'r1', const LatLng(30, 120))) x.id],
      ['a', 'b'],
    );
  });
}
