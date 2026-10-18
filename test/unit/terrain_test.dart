import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/terrain/dem.dart';
import 'package:trailweather/data/terrain/terrain_compute.dart';

/// 256×256 的高程网格。
Float32List gridOf(double Function(int row, int col) f) {
  final g = Float32List(256 * 256);
  for (var r = 0; r < 256; r++) {
    for (var c = 0; c < 256; c++) {
      g[r * 256 + c] = f(r, c);
    }
  }
  return g;
}

/// 按 Terrarium 编码成 RGBA（测试替身用）。
Uint8List terrariumRgba(Float32List elev) {
  final out = Uint8List(elev.length * 4);
  for (var i = 0; i < elev.length; i++) {
    final v = elev[i] + 32768;
    final r = v ~/ 256, g = (v - r * 256).floor();
    final b = ((v - r * 256 - g) * 256).round().clamp(0, 255);
    out
      ..[i * 4] = r
      ..[i * 4 + 1] = g
      ..[i * 4 + 2] = b
      ..[i * 4 + 3] = 255;
  }
  return out;
}

/// 圆锥山：中心 1000 m，每像素降 4 m。
final cone = gridOf(
  (r, c) =>
      1000 - 4 * math.sqrt(math.pow(r - 127.5, 2) + math.pow(c - 127.5, 2)),
);

void main() {
  group('坐标与编码', () {
    test('Terrarium 解码公式', () {
      final rgba = Uint8List.fromList([128, 140, 0, 255, 127, 255, 128, 255]);
      expect(terrariumToElevation(rgba), [140.0, -0.5]);
    });

    test('墨卡托世界像素与经纬度互换', () {
      const p = LatLng(39.9917, 116.1889);
      final (x, y) = worldPixel(p.latitude, p.longitude, 12);
      expect(x ~/ 256, 3369);
      expect(y ~/ 256, 1550);
      final back = latLngOfWorldPixel(x, y, 12);
      expect(back.latitude, closeTo(p.latitude, 1e-9));
      expect(back.longitude, closeTo(p.longitude, 1e-9));
    });

    test('覆盖范围的瓦片', () {
      final keys = DemService.tilesForBounds(
        south: 39.9,
        west: 116.1,
        north: 40.05,
        east: 116.3,
        z: 12,
      );
      expect(keys, contains(const DemTileKey(12, 3370, 1550)));
      // 0.2° × 0.15° 在 12 级约跨 3–4 块 × 3–4 块
      expect(keys.length, inInclusiveRange(9, 16));
    });
  });

  group('DemService', () {
    test('下载解码、合并并发请求、缓存与按点取值（双线性）', () async {
      var fetches = 0;
      final s = DemService(
        fetcher: (uri, {cancelToken}) async {
          fetches++;
          expect(uri.host, 's3.amazonaws.com');
          expect(uri.path, '/elevation-tiles-prod/terrarium/12/3370/1550.png');
          return Uint8List(0);
        },
        decoder: (_) async => terrariumRgba(gridOf((r, c) => 100.0 + c)),
      );
      var notified = 0;
      s.addListener(() => notified++);
      const k = DemTileKey(12, 3370, 1550);
      final results = await Future.wait([s.load(k), s.load(k)]);
      expect(fetches, 1);
      expect(identical(results[0], results[1]), isTrue);
      expect(notified, 1);
      expect(s.cached(k), isNotNull);
      // 像素中心对齐：第 10 列中心（x = 10.5）处为 110
      final (x0, y0) = (k.x * 256 + 10.5, k.y * 256 + 20.5);
      final p = latLngOfWorldPixel(x0, y0, 12);
      expect(s.elevationAt(p), closeTo(110, 0.01));
      expect(s.elevationAt(const LatLng(30, 100)), isNull);
    });

    test('失败的瓦片 1 分钟内不重试；容量满时淘汰最久未用的', () async {
      var t = DateTime(2026, 10, 17, 12);
      var fail = true;
      final s = DemService(
        now: () => t,
        capacity: 2,
        fetcher: (uri, {cancelToken}) async {
          if (fail) throw Exception('offline');
          return Uint8List(0);
        },
        decoder: (_) async => terrariumRgba(gridOf((r, c) => 1)),
      );
      const a = DemTileKey(12, 1, 1);
      expect(await s.load(a), isNull);
      fail = false;
      expect(await s.load(a), isNull, reason: '1 分钟内不重试');
      t = t.add(const Duration(minutes: 2));
      expect(await s.load(a), isNotNull);
      await s.load(const DemTileKey(12, 1, 2));
      s.cached(a); // a 最近用过
      await s.load(const DemTileKey(12, 1, 3));
      expect(s.cached(a), isNotNull);
      expect(s.cached(const DemTileKey(12, 1, 2)), isNull);
    });
  });

  group('等高线', () {
    test('等高距都大于 20 m（公开地图内容表示规范）；太小的缩放不画', () {
      for (var z = 10.0; z <= 18; z += 0.25) {
        expect(contourSpec(z)!.interval, greaterThan(20));
      }
      expect(contourSpec(9.9), isNull);
      expect(contourSpec(14)!.interval, 25);
      expect(contourSpec(12)!.interval, 100);
    });

    test('海拔显示取整到 10 m', () {
      expect(displayElevation(1234.4), 1230);
      expect(displayElevation(1235), 1240);
    });

    test('圆锥山：每条线上的点都落在对应高度上，计曲线单独一组', () {
      final ext = extendedGrid(cone, List.filled(8, null));
      final segs = contourSegments(ext, 100, 5);
      expect(segs.minor.length, greaterThan(100));
      expect(segs.major.length, greaterThan(20));
      double elevAt(double x, double y) {
        // 像素中心 (c + 0.5, r + 0.5)
        final dx = x - 128, dy = y - 128;
        return 1000 - 4 * math.sqrt(dx * dx + dy * dy);
      }

      for (final (list, isMajor) in [(segs.minor, false), (segs.major, true)]) {
        for (var i = 0; i < list.length; i += 2) {
          final e = elevAt(list[i], list[i + 1]);
          final level = (e / 100).round() * 100;
          expect((e - level).abs(), lessThan(4), reason: '线段端点高度 $e');
          expect(level % 500 == 0, isMajor);
        }
      }
    });

    test('连线与简化：圆锥山的线首尾相接成整条（瓦片内的闭合），几何量大幅减少且仍贴着等高线', () {
      final segs = contourSegments(
        extendedGrid(cone, List.filled(8, null)),
        100,
        5,
      );
      final lines = joinAndSimplify(segs.minor);
      // 600–900 m 的圆在瓦片内闭合（4 条）；300、400 m 的圆只在四个角上露出弧段（各 4 条）；
      // 100、200 m 的圆在瓦片外。
      expect(lines.lineCount, 12);
      expect(lines.segmentCount, lessThan(segs.minor.length ~/ 4 ~/ 4));
      var closed = 0;
      for (var l = 0; l < lines.lineCount; l++) {
        final a = lines.starts[l], b = lines.starts[l + 1] - 1;
        if ((lines.points[a * 2] - lines.points[b * 2]).abs() < 1e-3 &&
            (lines.points[a * 2 + 1] - lines.points[b * 2 + 1]).abs() < 1e-3) {
          closed++;
        }
      }
      expect(closed, 4);
      for (var i = 0; i < lines.points.length; i += 2) {
        final dx = lines.points[i] - 128, dy = lines.points[i + 1] - 128;
        final e = 1000 - 4 * math.sqrt(dx * dx + dy * dy);
        expect((e - (e / 100).round() * 100).abs(), lessThan(4));
      }
      // 每段两个三角形
      expect(strokeTriangles(lines, 0.5).length, lines.segmentCount * 12);
    });

    test('0 m 及以下不画（海面、海底）', () {
      final sea = gridOf((r, c) => -300.0 + c * 2);
      final segs = contourSegments(
        extendedGrid(sea, List.filled(8, null)),
        100,
        5,
      );
      for (var i = 0; i < segs.minor.length; i += 2) {
        expect(-300.0 + (segs.minor[i] - 0.5) * 2, greaterThan(50));
      }
    });

    test('扩展网格：四周一圈取自邻块，缺的用本块边缘', () {
      final self = gridOf((r, c) => 5);
      final east = gridOf((r, c) => 9);
      final ext = extendedGrid(self, [
        null,
        null,
        null,
        null,
        east,
        null,
        null,
        null,
      ]);
      expect(ext[10 * 258 + 257], 9); // 东侧一列来自东邻块
      expect(ext[10 * 258 + 0], 5); // 西侧缺：用本块边缘
      // 与东邻块之间的格子也有等高线（接缝处不断）
      // 本块最东一列 2649 m，东邻块最西一列 2659 m：2650 m 线落在两块之间的格子里
      final ramp = gridOf((r, c) => c * 10.0 + 99);
      final eastRamp = gridOf((r, c) => (c + 256) * 10.0 + 99);
      final segs = contourSegments(
        extendedGrid(ramp, [
          null,
          null,
          null,
          null,
          eastRamp,
          null,
          null,
          null,
        ]),
        25,
        4,
      );
      final xs = [for (var i = 0; i < segs.minor.length; i += 2) segs.minor[i]];
      expect(xs.any((x) => x > 255.5), isTrue);
    });
  });

  group('地形阴影', () {
    test('平地透明；背光坡（朝东南）变暗，向光坡（朝西北）透明', () {
      final flat = hillshadeRgba(
        extendedGrid(gridOf((r, c) => 500), List.filled(8, null)),
        30,
      );
      expect(flat.where((v) => v != 0), isEmpty);
      double alphaAt(Float32List g) => hillshadeRgba(
        extendedGrid(g, List.filled(8, null)),
        30,
      )[(128 * 256 + 128) * 4 + 3].toDouble();
      // 西北高、东南低：坡朝东南，背对西北的光 → 变暗
      expect(alphaAt(gridOf((r, c) => 2000.0 - 20 * (r + c))), greaterThan(40));
      // 东南高、西北低：坡朝西北，向光 → 透明
      expect(alphaAt(gridOf((r, c) => 2000.0 + 20 * (r + c))), 0);
    });

    test('2 像素边：阴影图外圈与邻块自己算的边缘一致（瓦片边界看不出缝）', () {
      // 东西相邻两块，起伏跨块连续
      double f(int r, int c) => 800 + 300 * math.sin(c / 37) * math.cos(r / 23);
      final a = gridOf(f), b = gridOf((r, c) => f(r, c + 256));
      List<Float32List?> only({Float32List? w, Float32List? e}) => [
        null,
        null,
        null,
        w,
        e,
        null,
        null,
        null,
      ];
      final shadeA = hillshadeRgba(
        extendedGrid(a, only(e: b), border: 2),
        30,
        padded: true,
        border: 2,
      );
      final shadeB = hillshadeRgba(
        extendedGrid(b, only(w: a), border: 2),
        30,
        padded: true,
        border: 2,
      );
      for (final row in [10, 100, 200]) {
        // A 的最东一圈（padded 第 257 列）= B 的第 0 列（padded 第 1 列）
        expect(
          shadeA[((row + 1) * 258 + 257) * 4 + 3],
          shadeB[((row + 1) * 258 + 1) * 4 + 3],
        );
        expect(
          shadeB[((row + 1) * 258 + 0) * 4 + 3],
          shadeA[((row + 1) * 258 + 256) * 4 + 3],
        );
      }
    });

    test('边宽不影响等高线', () {
      final n = List<Float32List?>.filled(8, cone);
      final one = contourSegments(extendedGrid(cone, n), 50, 5);
      final two = contourSegments(
        extendedGrid(cone, n, border: 2),
        50,
        5,
        border: 2,
      );
      expect(two.minor, one.minor);
      expect(two.major, one.major);
    });

    test('带一圈邻块像素的阴影图：中间 256×256 与不带边的完全相同', () {
      final ext = extendedGrid(cone, List.filled(8, cone));
      final plain = hillshadeRgba(ext, 30);
      final padded = hillshadeRgba(ext, 30, padded: true);
      expect(padded.length, 258 * 258 * 4);
      for (final (i, j) in [(0, 0), (0, 255), (128, 7), (255, 255)]) {
        expect(
          padded[((i + 1) * 258 + j + 1) * 4 + 3],
          plain[(i * 256 + j) * 4 + 3],
        );
      }
    });
  });

  group('剖面', () {
    test('加密取样：保留端点，距离单调，间距不超过步长', () {
      const pts = [LatLng(40, 116), LatLng(40, 116.01), LatLng(40.01, 116.01)];
      final (dense, dist) = densify(pts, 25);
      expect(dense.first, pts.first);
      expect(dense.last.latitude, closeTo(40.01, 1e-12));
      expect(dense.length, dist.length);
      for (var i = 1; i < dist.length; i++) {
        expect(dist[i] - dist[i - 1], inInclusiveRange(0.0, 25.0));
      }
      expect(dist.last, closeTo(853 + 1112, 15));
    });

    test('累计爬升滤掉 5 m 以内的起伏；缺值不出结果', () {
      final noisy = [for (var i = 0; i < 100; i++) 100.0 + (i.isEven ? 0 : 3)];
      expect(elevationStats(noisy)!.ascentM, 0);
      final climb = [for (var i = 0; i <= 100; i++) 100.0 + i * 2];
      final st = elevationStats(climb)!;
      expect(st.ascentM, closeTo(200, 6));
      expect(st.descentM, 0);
      expect(st.maxM, 300);
      expect(elevationStats([1, double.nan, 3]), isNull);
    });
  });
}
