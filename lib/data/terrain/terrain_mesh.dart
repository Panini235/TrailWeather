import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import 'dem.dart';

/// 线路 3D 预览的地形网格与视图计算（T-191，D-040）。纯函数，不依赖界面。
///
/// - 网格在墨卡托像素空间等距，换算成米时用区域中心纬度（几十公里内误差可忽略）；
/// - 网格间距不细于 30 m（公开高程数据本身约 30 m；《公开地图内容表示规范》第十九条
///   高程精度不优于 15 m），缺数据的格点为 NaN，相关三角形不画，绝不补 0；
/// - 画法：不用深度缓冲，每帧按格子中心到相机的距离由远到近排序（计数排序，O(n)）。

/// 3D 预览覆盖的范围：线路外扩一圈，选一级高程瓦片，定网格尺寸。
class TerrainRegion {
  const TerrainRegion({
    required this.z,
    required this.x0,
    required this.y0,
    required this.step,
    required this.cols,
    required this.rows,
    required this.metersPerPx,
  });

  /// 高程瓦片级别。
  final int z;

  /// 西北角格点的墨卡托世界像素坐标（[z] 级）。
  final double x0, y0;

  /// 相邻格点相隔的世界像素。
  final double step;

  /// 格点列数、行数。
  final int cols, rows;

  /// 区域中心纬度处一个世界像素的地面长度（米）。
  final double metersPerPx;

  double get spacingM => step * metersPerPx;

  static const minSpacingM = 30.0;
  static const maxCells = 140;
  static const maxTiles = 36;

  /// 覆盖 [points] 的区域：四周外扩 15%（至少 800 m），长宽比不超过 2:1，
  /// 长边最多 [maxCells] 格、间距不小于 [minSpacingM]。点为空时返回 null。
  static TerrainRegion? forPoints(Iterable<LatLng> points) {
    final pts = points.toList();
    if (pts.isEmpty) return null;
    // 先在 12 级像素里量范围，再按网格间距选级别。
    const zr = DemService.maxZoom;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in pts) {
      final (x, y) = worldPixel(p.latitude, p.longitude, zr);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }
    final center = latLngOfWorldPixel((minX + maxX) / 2, (minY + maxY) / 2, zr);
    final mppR =
        156543.03392 * math.cos(center.latitude * math.pi / 180) / (1 << zr);
    final margin = math.max(
      0.15 * math.max(maxX - minX, maxY - minY),
      800 / mppR,
    );
    minX -= margin;
    maxX += margin;
    minY -= margin;
    maxY += margin;
    var w = maxX - minX, h = maxY - minY;
    if (w < h / 2) {
      minX -= (h / 2 - w) / 2;
      w = h / 2;
    } else if (h < w / 2) {
      minY -= (w / 2 - h) / 2;
      h = w / 2;
    }
    final longM = math.max(w, h) * mppR;
    final cells = (longM / minSpacingM).floor().clamp(24, maxCells);
    final spacingM = longM / cells;

    // 高程像素最多比网格细一倍（再细也用不上），且瓦片数不超过上限。
    var z = zr;
    double mpp(int z) => mppR * (1 << zr) / (1 << z);
    while (z > DemService.minZoom && mpp(z) < spacingM / 2) {
      z--;
    }
    int tileCount(int z) {
      final s = (1 << zr) / (1 << z) * 256;
      return ((maxX / s).floor() - (minX / s).floor() + 1) *
          ((maxY / s).floor() - (minY / s).floor() + 1);
    }

    while (z > DemService.minZoom && tileCount(z) > maxTiles) {
      z--;
    }
    final k = (1 << zr) / (1 << z); // 12 级像素 / z 级像素
    final step = spacingM / mpp(z);
    return TerrainRegion(
      z: z,
      x0: minX / k,
      y0: minY / k,
      step: step,
      cols: (w / k / step).round() + 1,
      rows: (h / k / step).round() + 1,
      metersPerPx: mpp(z),
    );
  }

  /// 需要的高程瓦片。
  Set<DemTileKey> get tiles {
    final n = 1 << z;
    final x1 = x0 + (cols - 1) * step, y1 = y0 + (rows - 1) * step;
    return {
      for (
        var x = (x0 ~/ 256).clamp(0, n - 1);
        x <= (x1 ~/ 256).clamp(0, n - 1);
        x++
      )
        for (
          var y = (y0 ~/ 256).clamp(0, n - 1);
          y <= (y1 ~/ 256).clamp(0, n - 1);
          y++
        )
          DemTileKey(z, x, y),
    };
  }

  /// 经纬度 → 网格坐标（列、行，带小数）。
  (double, double) gridOf(LatLng p) {
    final (x, y) = worldPixel(p.latitude, p.longitude, z);
    return ((x - x0) / step, (y - y0) / step);
  }
}

/// 高程采样：给 [z] 级世界像素坐标，返回米；没有数据返回 null。
typedef DemSampler = double? Function(int z, double wx, double wy);

/// 从 [DemService] 的缓存取样（只读缓存，不下载）。
DemSampler demServiceSampler(DemService dem) => (z, wx, wy) {
  final k = DemTileKey(z, wx ~/ 256, wy ~/ 256);
  return dem.cached(k)?.sampleAt(wx - k.x * 256, wy - k.y * 256);
};

class TerrainGrid {
  TerrainGrid(this.region, this.elev) {
    var lo = double.infinity, hi = -double.infinity, missing = 0;
    for (final e in elev) {
      if (e.isNaN) {
        missing++;
        continue;
      }
      lo = math.min(lo, e);
      hi = math.max(hi, e);
    }
    minE = lo;
    maxE = hi;
    missingFraction = elev.isEmpty ? 1 : missing / elev.length;
  }

  final TerrainRegion region;

  /// 行优先（北 → 南），缺失为 NaN。
  final Float32List elev;

  late final double minE, maxE;
  late final double missingFraction;

  int get cols => region.cols;
  int get rows => region.rows;
  double get spacingM => region.spacingM;

  /// 东西、南北方向的总长（米）。
  double get widthM => (cols - 1) * spacingM;
  double get heightM => (rows - 1) * spacingM;

  static TerrainGrid sample(TerrainRegion r, DemSampler sampler) {
    final e = Float32List(r.cols * r.rows);
    for (var i = 0; i < r.rows; i++) {
      for (var j = 0; j < r.cols; j++) {
        e[i * r.cols + j] =
            sampler(r.z, r.x0 + j * r.step, r.y0 + i * r.step) ?? double.nan;
      }
    }
    return TerrainGrid(r, e);
  }

  /// 网格坐标处的双线性高程；越界或任一邻点缺失为 NaN。
  double heightAt(double gx, double gy) {
    if (gx < 0 || gy < 0 || gx > cols - 1 || gy > rows - 1) return double.nan;
    final j = math.min(gx.floor(), cols - 2),
        i = math.min(gy.floor(), rows - 2);
    final tx = gx - j, ty = gy - i;
    final o = i * cols + j;
    final a = elev[o],
        b = elev[o + 1],
        c = elev[o + cols],
        d = elev[o + cols + 1];
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty;
  }

  /// 网格坐标 → 以区域中心为原点的地面坐标（米，x 向东、y 向北）。
  (double, double) groundOf(double gx, double gy) =>
      ((gx - (cols - 1) / 2) * spacingM, ((rows - 1) / 2 - gy) * spacingM);

  /// 地面坐标 → 网格坐标。
  (double, double) gridOfGround(double x, double y) =>
      (x / spacingM + (cols - 1) / 2, (rows - 1) / 2 - y / spacingM);

  /// 显示用的高度原点：高程中值，旋转时绕它转。
  double get midE => (minE + maxE) / 2;
}

/// 地形块的颜色：按高程在两色之间过渡，再乘光照（光源西北 315°、高度 45°，
/// 与 2D 地形阴影一致，固定在地形上，转动视角时明暗不变）。缺失点透明。
Int32List terrainVertexColors(
  TerrainGrid g,
  double exaggeration, {
  required int lowArgb,
  required int highArgb,
  double ambient = 0.42,
}) {
  final cols = g.cols, rows = g.rows, e = g.elev;
  final out = Int32List(cols * rows);
  final range = math.max(g.maxE - g.minE, 1.0);
  const lx = -0.5, ly = 0.5, lz = 0.70710678; // 西北、高 45°
  final k = exaggeration / (2 * g.spacingM);
  int ch(int argb, int shift) => (argb >> shift) & 0xFF;
  for (var i = 0; i < rows; i++) {
    for (var j = 0; j < cols; j++) {
      final o = i * cols + j;
      final v = e[o];
      if (v.isNaN) continue;
      double at(int ii, int jj) {
        final w = e[ii.clamp(0, rows - 1) * cols + jj.clamp(0, cols - 1)];
        return w.isNaN ? v : w;
      }

      final dzdx = (at(i, j + 1) - at(i, j - 1)) * k;
      final dzdy = (at(i - 1, j) - at(i + 1, j)) * k; // 行号向南增加
      final len = math.sqrt(dzdx * dzdx + dzdy * dzdy + 1);
      final lambert = math.max(0.0, (-dzdx * lx - dzdy * ly + lz) / len);
      final light = math.min(1.0, ambient + (1 - ambient) * lambert / lz);
      final t = (v - g.minE) / range;
      int mix(int shift) =>
          ((ch(lowArgb, shift) * (1 - t) + ch(highArgb, shift) * t) * light)
              .round()
              .clamp(0, 255);
      out[o] = 0xFF000000 | mix(16) << 16 | mix(8) << 8 | mix(0);
    }
  }
  return out;
}

/// 绕地形中心转动的透视相机。角度为弧度。
///
/// [bearing]：视线朝向（0 朝北，顺时针为正）；[tilt]：与竖直方向的夹角（0 为俯视）；
/// [distance]：相机到旋转中心的距离（米）；[scale]：旋转中心处每米多少屏幕像素；
/// [targetX]/[targetY]：旋转中心的地面坐标（米）。
class OrbitCamera {
  const OrbitCamera({
    required this.bearing,
    required this.tilt,
    required this.distance,
    required this.scale,
    required this.cx,
    required this.cy,
    this.targetX = 0,
    this.targetY = 0,
  });

  final double bearing, tilt, distance, scale, cx, cy, targetX, targetY;

  /// 投影 [xyz]（每点 3 个数：地面 x、y 与显示高度 z，米）到屏幕 [outXY]，
  /// [outDepth] 为沿视线到相机的距离（越大越远）。
  void project(Float32List xyz, Float32List outXY, Float32List outDepth) {
    final sb = math.sin(bearing), cb = math.cos(bearing);
    final st = math.sin(tilt), ct = math.cos(tilt);
    final f = scale * distance;
    final n = xyz.length ~/ 3;
    for (var i = 0; i < n; i++) {
      final px = xyz[i * 3] - targetX, py = xyz[i * 3 + 1] - targetY;
      final pz = xyz[i * 3 + 2];
      final xr = px * cb - py * sb;
      final yf = px * sb + py * cb;
      final depth = distance + yf * st - pz * ct;
      final up = yf * ct + pz * st;
      final s = f / math.max(depth, distance * 0.05);
      outXY[i * 2] = cx + xr * s;
      outXY[i * 2 + 1] = cy - up * s;
      outDepth[i] = depth;
    }
  }

  /// 相机在地面坐标系里的位置（x、y、显示高度 z）。
  (double, double, double) get position {
    final st = math.sin(tilt);
    return (
      targetX - distance * st * math.sin(bearing),
      targetY - distance * st * math.cos(bearing),
      distance * math.cos(tilt),
    );
  }

  /// 外法线为 ([nx], [ny]) 的竖直面是否朝向相机（侧面裙边只画朝向相机的两面）。
  bool facesCamera(double nx, double ny) =>
      nx * math.sin(bearing) + ny * math.cos(bearing) < 0;
}

/// 按深度由远到近排列格子（计数排序，4096 档）：返回每个格子的下标。
/// [cellDepth] 里 NaN 表示该格不画（缺数据）。
Int32List farToNear(Float32List cellDepth, {int buckets = 4096}) {
  var lo = double.infinity, hi = -double.infinity, n = 0;
  for (final d in cellDepth) {
    if (d.isNaN) continue;
    n++;
    if (d < lo) lo = d;
    if (d > hi) hi = d;
  }
  final out = Int32List(n);
  if (n == 0) return out;
  final scale = hi > lo ? (buckets - 1) / (hi - lo) : 0.0;
  final count = Int32List(buckets + 1);
  for (final d in cellDepth) {
    if (d.isNaN) continue;
    count[buckets - 1 - ((d - lo) * scale).floor() + 1]++;
  }
  for (var b = 1; b <= buckets; b++) {
    count[b] += count[b - 1];
  }
  for (var i = 0; i < cellDepth.length; i++) {
    final d = cellDepth[i];
    if (d.isNaN) continue;
    out[count[buckets - 1 - ((d - lo) * scale).floor()]++] = i;
  }
  return out;
}

/// 地面坐标 ([x], [y]) 处、显示高度 [z] 的点是否被地形挡住（沿到相机的射线逐格检查）。
/// [zOf]：网格坐标处的显示高度（米，NaN 表示缺数据，按不遮挡处理）。
bool occluded(
  TerrainGrid g,
  OrbitCamera cam,
  double x,
  double y,
  double z, {
  required double Function(double gx, double gy) zOf,
  required double maxZ,
}) {
  final (camX, camY, camZ) = cam.position;
  final dx = camX - x, dy = camY - y, dz = camZ - z;
  final hl = math.sqrt(dx * dx + dy * dy);
  if (hl < 1e-6) return false;
  final step = g.spacingM * 0.7;
  final rise = dz / hl;
  for (var d = step; ; d += step) {
    final rz = z + rise * d;
    if (rz > maxZ) return false; // 已高过所有地形
    final t = d / hl;
    if (t >= 1) return false;
    final (gx, gy) = g.gridOfGround(x + dx * t, y + dy * t);
    if (gx < 0 || gy < 0 || gx > g.cols - 1 || gy > g.rows - 1) return false;
    final h = zOf(gx, gy);
    if (!h.isNaN && h > rz) return true;
  }
}
