import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:trailweather/data/terrain/dem.dart';
import 'package:trailweather/data/terrain/terrain_mesh.dart';

/// 香山—八大处一带约 5 km 的线路（WGS-84）。
const _xiangshan = [
  LatLng(39.9886, 116.1823),
  LatLng(39.9952, 116.1771),
  LatLng(39.9998, 116.1702),
  LatLng(39.9951, 116.1590),
  LatLng(39.9612, 116.1872),
];

TerrainRegion _region(int cols, int rows) => TerrainRegion(
  z: 12,
  x0: 0,
  y0: 0,
  step: 1,
  cols: cols,
  rows: rows,
  metersPerPx: 30,
);

void main() {
  group('TerrainRegion', () {
    test('5 km 线路：网格不细于 30 m、长边不超过 140 格、瓦片不超过 36 块，四周留边', () {
      final r = TerrainRegion.forPoints(_xiangshan)!;
      expect(
        r.spacingM,
        greaterThanOrEqualTo(TerrainRegion.minSpacingM - 1e-6),
      );
      expect(
        math.max(r.cols, r.rows) - 1,
        lessThanOrEqualTo(TerrainRegion.maxCells),
      );
      expect(r.tiles.length, lessThanOrEqualTo(TerrainRegion.maxTiles));
      expect(r.z, lessThanOrEqualTo(DemService.maxZoom));
      for (final p in _xiangshan) {
        final (gx, gy) = r.gridOf(p);
        // 外扩至少 800 m
        expect(gx * r.spacingM, greaterThan(790));
        expect(gy * r.spacingM, greaterThan(790));
        expect((r.cols - 1 - gx) * r.spacingM, greaterThan(790));
        expect((r.rows - 1 - gy) * r.spacingM, greaterThan(790));
      }
    });

    test('100 km 长线路：自动降级，瓦片数仍受限', () {
      final r = TerrainRegion.forPoints(const [
        LatLng(30.0, 103.0),
        LatLng(30.6, 103.9),
      ])!;
      expect(r.z, lessThan(DemService.maxZoom));
      expect(r.tiles.length, lessThanOrEqualTo(TerrainRegion.maxTiles));
      expect(r.spacingM, greaterThan(300));
    });

    test('长宽比不超过 2:1', () {
      final r = TerrainRegion.forPoints(const [
        LatLng(40.0, 116.0),
        LatLng(40.0, 116.5),
      ])!;
      expect(r.cols / r.rows, lessThanOrEqualTo(2.05));
    });

    test('没有点时不生成', () {
      expect(TerrainRegion.forPoints(const []), isNull);
    });
  });

  group('TerrainGrid', () {
    test('按格点取样；缺失为 NaN，不补 0', () {
      final g = TerrainGrid.sample(
        _region(4, 3),
        (z, x, y) => x == 3 && y == 2 ? null : 100 + x * 10 + y,
      );
      expect(g.elev[0], 100);
      expect(g.elev[1 * 4 + 2], 121);
      expect(g.elev[2 * 4 + 3].isNaN, isTrue);
      expect(g.minE, 100);
      expect(g.maxE, 131); // 最大的 (3, 2) 缺失
      expect(g.missingFraction, closeTo(1 / 12, 1e-9));
    });

    test('双线性高程；邻点缺失或越界为 NaN', () {
      final g = TerrainGrid.sample(
        _region(4, 3),
        (z, x, y) => x == 3 && y == 2 ? null : 100 + x * 10 + y,
      );
      expect(g.heightAt(0.5, 0.5), closeTo(105.5, 1e-6));
      expect(g.heightAt(2.5, 1.5).isNaN, isTrue);
      expect(g.heightAt(-0.1, 0).isNaN, isTrue);
    });

    test('网格坐标与地面坐标互换（原点在中心，y 向北）', () {
      final g = TerrainGrid.sample(_region(5, 3), (z, x, y) => 0);
      expect(g.groundOf(2, 1), (0.0, 0.0));
      final (x, y) = g.groundOf(4, 0);
      expect(x, 60); // 2 格 × 30 m，向东
      expect(y, 30); // 第 0 行在北边
      final (gx, gy) = g.gridOfGround(x, y);
      expect(gx, closeTo(4, 1e-9));
      expect(gy, closeTo(0, 1e-9));
    });
  });

  group('光照', () {
    test('朝西北的坡比朝东南的坡亮；缺失点透明', () {
      // 东西向一条山脊：西半边向西倾（朝西），东半边向东倾（朝东）
      final g = TerrainGrid.sample(
        _region(9, 5),
        (z, x, y) => x == 8 && y == 4 ? null : 500 - 40 * (x - 4).abs(),
      );
      final c = terrainVertexColors(
        g,
        1,
        lowArgb: 0xFF808080,
        highArgb: 0xFF808080,
      );
      int lum(int argb) => (argb >> 16) & 0xFF;
      expect(lum(c[2 * 9 + 1]), greaterThan(lum(c[2 * 9 + 7])));
      expect(c[4 * 9 + 8], 0);
    });
  });

  group('相机与绘制顺序', () {
    const cam = OrbitCamera(
      bearing: 0,
      tilt: 55 * math.pi / 180,
      distance: 10000,
      scale: 0.05,
      cx: 200,
      cy: 300,
    );

    test('旋转中心投到画布中心；朝北看时北边的点在上方、离相机更远', () {
      final xy = Float32List(4), d = Float32List(2);
      cam.project(Float32List.fromList([0, 0, 0, 0, 1000, 0]), xy, d);
      expect(xy[0], closeTo(200, 1e-3));
      expect(xy[1], closeTo(300, 1e-3));
      expect(xy[3], lessThan(xy[1]));
      expect(d[1], greaterThan(d[0]));
    });

    test('俯视时东边的点在右边；转 90° 后东边朝上', () {
      final xy = Float32List(2), d = Float32List(1);
      const top = OrbitCamera(
        bearing: 0,
        tilt: 0,
        distance: 10000,
        scale: 0.05,
        cx: 0,
        cy: 0,
      );
      top.project(Float32List.fromList([1000, 0, 0]), xy, d);
      expect(xy[0], greaterThan(0));
      expect(xy[1], closeTo(0, 1e-3));
      const east = OrbitCamera(
        bearing: math.pi / 2,
        tilt: 0,
        distance: 10000,
        scale: 0.05,
        cx: 0,
        cy: 0,
      );
      east.project(Float32List.fromList([1000, 0, 0]), xy, d);
      expect(xy[1], lessThan(0));
    });

    test('侧面是否朝向相机', () {
      expect(cam.facesCamera(0, -1), isTrue); // 南面朝向朝北看的相机
      expect(cam.facesCamera(0, 1), isFalse);
    });

    test('由远到近排序，跳过缺数据的格子', () {
      final order = farToNear(Float32List.fromList([5, double.nan, 9, 1, 7]));
      expect(order, [2, 4, 0, 3]);
    });

    test('同深度也都保留', () {
      expect(farToNear(Float32List.fromList([3, 3, 3])).length, 3);
    });
  });

  group('线路遮挡', () {
    // 东西走向的高墙在中间一行（北边是低谷），相机在南边朝北看
    final g = TerrainGrid.sample(
      _region(21, 21),
      (z, x, y) => y == 10 ? 800 : 100,
    );
    const cam = OrbitCamera(
      bearing: 0,
      tilt: 70 * math.pi / 180,
      distance: 3000,
      scale: 1,
      cx: 0,
      cy: 0,
    );
    double zOf(double gx, double gy) => g.heightAt(gx, gy) - g.midE;
    final maxZ = g.maxE - g.midE;

    test('墙北边谷底的点被挡住', () {
      final (x, y) = g.groundOf(10, 4);
      expect(
        occluded(g, cam, x, y, 100 - g.midE + 5, zOf: zOf, maxZ: maxZ),
        isTrue,
      );
    });

    test('墙南边（靠相机一侧）的点看得见', () {
      final (x, y) = g.groundOf(10, 16);
      expect(
        occluded(g, cam, x, y, 100 - g.midE + 5, zOf: zOf, maxZ: maxZ),
        isFalse,
      );
    });

    test('高过所有地形的点看得见', () {
      final (x, y) = g.groundOf(10, 4);
      expect(occluded(g, cam, x, y, maxZ + 1, zOf: zOf, maxZ: maxZ), isFalse);
    });
  });
}
