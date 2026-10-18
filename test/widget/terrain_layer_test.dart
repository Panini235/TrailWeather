import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/core/gcj02.dart';
import 'package:trailweather/data/terrain/dem.dart';
import 'package:trailweather/data/terrain/terrain_compute.dart';
import 'package:trailweather/ui/map/basemap.dart';
import 'package:trailweather/ui/map/terrain_layer.dart';

import '../unit/terrain_test.dart' show cone, terrariumRgba;

void main() {
  testWidgets('真实 Terrarium 瓦片经引擎解码后数值不变（香山脚下 12/3370/1550）', (tester) async {
    final png = File('test/fixtures/dem/terrarium_12_3370_1550.png')
        .readAsBytesSync();
    final elev = (await tester.runAsync(
      () async => terrariumToElevation(await decodePngRgba(png)),
    ))!;
    // 期望值由独立的 Python PNG 解码得出
    expect(elev[0], 56);
    expect(elev[128 * 256 + 128], 140);
    expect(elev[200 * 256 + 10], 108);
    expect(elev[255 * 256 + 255], 48);
  });

  testWidgets('后台算好的等高线画在地图上', (tester) async {
    // 视野内所有瓦片都是同一座圆锥山（替身），等高距 50 m（缩放 13）
    final dem = DemService(
      fetcher: (uri, {cancelToken}) async => Uint8List(0),
      decoder: (_) async => terrariumRgba(cone),
    );
    addTearDown(dem.dispose);
    final key = GlobalKey();
    Future<int> inkPixels() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final data = (await tester.runAsync(() async {
        final img = await boundary.toImage();
        return img.toByteData(format: ui.ImageByteFormat.rawRgba);
      }))!;
      var n = 0;
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 0) n++;
      }
      return n;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 300,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(40, 116.2),
                  initialZoom: 13,
                  backgroundColor: Colors.transparent,
                ),
                children: [
                  TerrainLayer(dem: dem, basemap: Basemap.base('osm')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 去抖 → 下载 → 后台计算（compute 在测试里也是真的 isolate）
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }
    await tester.pump();
    expect(await inkPixels(), greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('高德（GCJ-02）底图：等高线与地形阴影按四角位移变形后画出', (tester) async {
    // 视野内所有瓦片都是同一座圆锥山（替身），等高距 50 m（缩放 13）
    final dem = DemService(
      fetcher: (uri, {cancelToken}) async => Uint8List(0),
      decoder: (_) async => terrariumRgba(cone),
    );
    addTearDown(dem.dispose);
    final key = GlobalKey();
    Future<int> inkPixels() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final data = (await tester.runAsync(() async {
        final img = await boundary.toImage();
        return img.toByteData(format: ui.ImageByteFormat.rawRgba);
      }))!;
      var n = 0;
      for (var i = 3; i < data.lengthInBytes; i += 4) {
        if (data.getUint8(i) > 0) n++;
      }
      return n;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 300,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(40, 116.2),
                  initialZoom: 13,
                  backgroundColor: Colors.transparent,
                ),
                children: [
                  TerrainLayer(
                    dem: dem,
                    basemap: Basemap.base('amap'),
                    hillshade: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 去抖 → 下载 → 后台计算（compute 在测试里也是真的 isolate）
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }
    await tester.pump();
    expect(await inkPixels(), greaterThan(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('地形阴影只压暗：半透明黑色、不超过 50%，向光坡透明（不盖住底图）', (tester) async {
    final dem = DemService(
      fetcher: (uri, {cancelToken}) async => Uint8List(0),
      decoder: (_) async => terrariumRgba(cone),
    );
    addTearDown(dem.dispose);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 300,
              height: 300,
              child: FlutterMap(
                options: const MapOptions(
                  initialCenter: LatLng(40, 116.2),
                  initialZoom: 13,
                  backgroundColor: Colors.transparent,
                ),
                children: [
                  TerrainLayer(
                    dem: dem,
                    basemap: Basemap.base('amap'),
                    contours: false,
                    hillshade: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
    }
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data = (await tester.runAsync(() async {
      final img = await boundary.toImage();
      return img.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    var shaded = 0, clear = 0, maxA = 0, maxRgb = 0;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3);
      if (a == 0) {
        clear++;
        continue;
      }
      shaded++;
      maxA = math.max(maxA, a);
      maxRgb = math.max(maxRgb, data.getUint8(i));
    }
    expect(shaded, greaterThan(1000));
    expect(clear, greaterThan(1000));
    expect(maxA, lessThanOrEqualTo(130));
    expect(maxRgb, lessThan(8), reason: '只有黑色（压暗），没有灰白色盖在底图上');
    expect(tester.takeException(), isNull);
  });

  group('贴到 GCJ-02 底图的瓦片位移', () {
    // 香山附近的 12 级瓦片与它东边、南边的邻块
    const k = DemTileKey(12, 3369, 1550);
    const east = DemTileKey(12, 3370, 1550);
    const south = DemTileKey(12, 3369, 1551);

    (double, double) warped(DemTileKey t, double px, double py) {
      final xy = Float32List.fromList([px, py]);
      warpPoints(xy, TerrainLayer.gcjTileWarp(t));
      return (t.x * 256 + xy[0].toDouble(), t.y * 256 + xy[1].toDouble());
    }

    test('相邻瓦片共用边上的点位移完全一致（边界不错开）', () {
      for (final y in [0.0, 64.0, 200.5, 256.0]) {
        final (ax, ay) = warped(k, 256, y);
        final (bx, by) = warped(east, 0, y);
        expect(ax, closeTo(bx, 1e-3));
        expect(ay, closeTo(by, 1e-3));
      }
      for (final x in [0.0, 128.0, 256.0]) {
        final (ax, ay) = warped(k, x, 256);
        final (bx, by) = warped(south, x, 0);
        expect(ax, closeTo(bx, 1e-3));
        expect(ay, closeTo(by, 1e-3));
      }
    });

    test('块内插值与逐点精确换算相差不到 0.1 像素', () {
      var worst = 0.0;
      for (var py = 0.0; py <= 256; py += 32) {
        for (var px = 0.0; px <= 256; px += 32) {
          final (wx, wy) = warped(k, px, py);
          final c = latLngOfWorldPixel(k.x * 256 + px, k.y * 256 + py, 12);
          final g = Gcj02.wgs84ToGcj02(c);
          final (ex, ey) = worldPixel(g.latitude, g.longitude, 12);
          worst = math.max(worst, math.max((wx - ex).abs(), (wy - ey).abs()));
        }
      }
      expect(worst, lessThan(0.1));
    });

    test('地形阴影的仿射近似：角点与双线性位移相差不到 0.05 像素', () {
      for (final t in [k, east, south, const DemTileKey(10, 842, 387)]) {
        final w = TerrainLayer.gcjTileWarp(t);
        final m = affineOfWarp(w);
        for (final (px, py) in [
          (0.0, 0.0),
          (256.0, 0.0),
          (0.0, 256.0),
          (256.0, 256.0),
          (128.0, 77.0),
        ]) {
          final xy = Float32List.fromList([px, py]);
          warpPoints(xy, w);
          final ax = m[0] * px + m[4] * py + m[12];
          final ay = m[1] * px + m[5] * py + m[13];
          expect(ax, closeTo(xy[0], 0.05));
          expect(ay, closeTo(xy[1], 0.05));
        }
      }
    });

    test('整块按中心平移在瓦片边上会差出 0.3 像素以上（这正是要修的错位）', () {
      final c = latLngOfWorldPixel(k.x * 256 + 128.0, k.y * 256 + 128.0, 12);
      final g = Gcj02.wgs84ToGcj02(c);
      final (cx, cy) = worldPixel(c.latitude, c.longitude, 12);
      final (gx, gy) = worldPixel(g.latitude, g.longitude, 12);
      final e = latLngOfWorldPixel(k.x * 256 + 256.0, k.y * 256 + 128.0, 12);
      final ge = Gcj02.wgs84ToGcj02(e);
      final (ex, ey) = worldPixel(e.latitude, e.longitude, 12);
      final (gex, gey) = worldPixel(ge.latitude, ge.longitude, 12);
      final err = math.max(
        ((gex - ex) - (gx - cx)).abs(),
        ((gey - ey) - (gy - cy)).abs(),
      );
      expect(err, greaterThan(0.3));
    });
  });
}
