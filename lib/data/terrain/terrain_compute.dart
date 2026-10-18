import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';

/// 地形计算（纯函数，可放进后台 isolate；D-039）。
///
/// 合规（《公开地图内容表示规范》，自然资规〔2023〕2 号第十九条）：境内地图的等高距
/// 应大于 20 m（不含），高程精度不优于 15 m —— 等高距最小 25 m；海拔数字取整到 10 m 并标“约”。

/// 当前缩放下的等高距与计曲线间隔（每 [indexEvery] 条一条粗线）。缩放太小不画等高线。
({double interval, int indexEvery})? contourSpec(double mapZoom) {
  if (mapZoom < 10) return null;
  if (mapZoom < 11.5) return (interval: 200, indexEvery: 5);
  if (mapZoom < 13) return (interval: 100, indexEvery: 5);
  if (mapZoom < 14) return (interval: 50, indexEvery: 5);
  return (interval: 25, indexEvery: 4);
}

/// 显示用海拔：取整到 10 m（高程精度不优于 15 m）。
int displayElevation(double m) => (m / 10).round() * 10;

/// 一块瓦片及其四周各 [border] 像素的高程（(256 + 2·border)²；缺少的邻块用边缘值顶上）。
/// [neighbors] 依次为 西北、北、东北、西、东、西南、南、东南（缺失为 null）。
/// 等高线只需 1 像素；地形阴影要给邻块边缘也算出准确坡度，地形图层用 2 像素。
Float32List extendedGrid(
  Float32List tile,
  List<Float32List?> neighbors, {
  int border = 1,
}) {
  const s = 256;
  final e = s + 2 * border;
  final out = Float32List(e * e);
  for (var i = 0; i < s; i++) {
    out.setRange(
      (i + border) * e + border,
      (i + border) * e + border + s,
      tile,
      i * s,
    );
  }
  Float32List? at(int dx, int dy) => switch ((dx, dy)) {
    (-1, -1) => neighbors[0],
    (0, -1) => neighbors[1],
    (1, -1) => neighbors[2],
    (-1, 0) => neighbors[3],
    (1, 0) => neighbors[4],
    (-1, 1) => neighbors[5],
    (0, 1) => neighbors[6],
    _ => neighbors[7],
  };
  for (var r = 0; r < e; r++) {
    final ty = r - border;
    final dy = ty < 0 ? -1 : (ty >= s ? 1 : 0);
    for (var c = 0; c < e; c++) {
      final tx = c - border;
      final dx = tx < 0 ? -1 : (tx >= s ? 1 : 0);
      if (dx == 0 && dy == 0) continue;
      final n = at(dx, dy);
      out[r * e + c] = n == null
          ? tile[ty.clamp(0, s - 1) * s + tx.clamp(0, s - 1)]
          : n[(ty - dy * s) * s + (tx - dx * s)];
    }
  }
  return out;
}

/// 等高线线段（瓦片像素坐标 0–256，[x0, y0, x1, y1, …]），分普通线与计曲线。
class ContourSegments {
  const ContourSegments(this.minor, this.major);

  final Float32List minor;
  final Float32List major;
}

/// 在扩展网格（[extendedGrid]）上做 marching squares：覆盖本块像素中心之间以及
/// 与东、南邻块之间的格子，相邻瓦片的线在边界上接得上。0 m 及以下（海面、海底）不画。
ContourSegments contourSegments(
  Float32List ext,
  double interval,
  int indexEvery, {
  int border = 1,
}) {
  final e = 256 + 2 * border;
  final minor = <double>[], major = <double>[];
  final majorStep = interval * indexEvery;
  for (var r = border; r < border + 256; r++) {
    for (var c = border; c < border + 256; c++) {
      final tl = ext[r * e + c], tr = ext[r * e + c + 1];
      final bl = ext[(r + 1) * e + c], br = ext[(r + 1) * e + c + 1];
      if (tl.isNaN || tr.isNaN || bl.isNaN || br.isNaN) continue;
      final lo = math.min(math.min(tl, tr), math.min(bl, br));
      final hi = math.max(math.max(tl, tr), math.max(bl, br));
      // 等值线条件：lo < L ≤ hi。
      var k = (lo / interval).floor() + 1;
      for (var level = k * interval; level <= hi; level = ++k * interval) {
        if (level <= 0) continue;
        final out = (level % majorStep).abs() < 1e-6 ? major : minor;
        // 像素中心：扩展网格下标 r → 瓦片像素 y = r − border + 0.5。
        final x = c - border + 0.5, y = r - border + 0.5;
        double t(double a, double b) => (level - a) / (b - a);
        final idx =
            (tl >= level ? 8 : 0) |
            (tr >= level ? 4 : 0) |
            (br >= level ? 2 : 0) |
            (bl >= level ? 1 : 0);
        void seg(int a, int b) {
          for (final edge in [a, b]) {
            switch (edge) {
              case 0: // 上
                out
                  ..add(x + t(tl, tr))
                  ..add(y);
              case 1: // 右
                out
                  ..add(x + 1)
                  ..add(y + t(tr, br));
              case 2: // 下
                out
                  ..add(x + t(bl, br))
                  ..add(y + 1);
              default: // 左
                out
                  ..add(x)
                  ..add(y + t(tl, bl));
            }
          }
        }

        final centerAbove = (tl + tr + bl + br) / 4 >= level;
        switch (idx) {
          case 1 || 14:
            seg(3, 2);
          case 2 || 13:
            seg(2, 1);
          case 3 || 12:
            seg(3, 1);
          case 4 || 11:
            seg(0, 1);
          case 6 || 9:
            seg(0, 2);
          case 7 || 8:
            seg(3, 0);
          case 5: // 右上、左下在上：鞍部按中心值连
            if (centerAbove) {
              seg(3, 0);
              seg(2, 1);
            } else {
              seg(0, 1);
              seg(3, 2);
            }
          case 10: // 左上、右下在上
            if (centerAbove) {
              seg(0, 1);
              seg(3, 2);
            } else {
              seg(3, 0);
              seg(2, 1);
            }
        }
      }
    }
  }
  return ContourSegments(
    Float32List.fromList(minor),
    Float32List.fromList(major),
  );
}

/// 连成折线并简化后的等高线：[points] 为 [x0, y0, x1, y1, …]，第 i 条折线是
/// 点下标 [starts]\[i] 到 [starts]\[i + 1]（不含）。
class ContourLines {
  const ContourLines(this.points, this.starts);

  final Float32List points;
  final Int32List starts;

  int get lineCount => starts.length - 1;
  int get segmentCount => points.length ~/ 2 - lineCount;
}

/// marching squares 的线段首尾相接（相邻格子共享边上的点，坐标完全相同），
/// 再用 Douglas–Peucker 按 [epsilon]（瓦片像素）简化：每帧要画的几何量少一个数量级。
ContourLines joinAndSimplify(Float32List segs, {double epsilon = 0.3}) {
  final n = segs.length ~/ 4;
  int key(double x, double y) =>
      ((x * 1024).round() + (1 << 20)) << 21 | ((y * 1024).round() + (1 << 20));
  final byPoint = <int, List<int>>{};
  for (var i = 0; i < n; i++) {
    (byPoint[key(segs[i * 4], segs[i * 4 + 1])] ??= []).add(i);
    (byPoint[key(segs[i * 4 + 2], segs[i * 4 + 3])] ??= []).add(i);
  }
  final used = List<bool>.filled(n, false);
  final outPts = <double>[];
  final starts = <int>[0];

  // 从线段 i 的端点 (x, y) 继续往外走，返回经过的点（不含起点）。
  List<double> walk(int from, double x, double y) {
    final pts = <double>[];
    var cx = x, cy = y, prev = from;
    while (true) {
      final next = byPoint[key(cx, cy)]
          ?.where((j) => j != prev && !used[j])
          .firstOrNull;
      if (next == null) break;
      used[next] = true;
      final o = next * 4;
      final atStart = key(segs[o], segs[o + 1]) == key(cx, cy);
      cx = atStart ? segs[o + 2] : segs[o];
      cy = atStart ? segs[o + 3] : segs[o + 1];
      pts
        ..add(cx)
        ..add(cy);
      prev = next;
    }
    return pts;
  }

  for (var i = 0; i < n; i++) {
    if (used[i]) continue;
    used[i] = true;
    final o = i * 4;
    final forward = walk(i, segs[o + 2], segs[o + 3]);
    final backward = walk(i, segs[o], segs[o + 1]);
    final line = <double>[];
    for (var k = backward.length - 2; k >= 0; k -= 2) {
      line
        ..add(backward[k])
        ..add(backward[k + 1]);
    }
    line
      ..addAll([segs[o], segs[o + 1], segs[o + 2], segs[o + 3]])
      ..addAll(forward);
    final simple = _chaikin(_douglasPeucker(line, epsilon));
    outPts.addAll(simple);
    starts.add(outPts.length ~/ 2);
  }
  return ContourLines(Float32List.fromList(outPts), Int32List.fromList(starts));
}

/// 削一次角（Chaikin）：每个折角换成两个 1/4 点，线条更顺；曲线始终在原折线的
/// 凸包内，不会造出原数据没有的起伏。闭合线首尾仍相接，开口线保留端点。
List<double> _chaikin(List<double> pts) {
  final m = pts.length ~/ 2;
  if (m < 3) return pts;
  final closed = pts[0] == pts[pts.length - 2] && pts[1] == pts[pts.length - 1];
  final out = <double>[];
  if (!closed) out.addAll([pts[0], pts[1]]);
  for (var i = 0; i < m - 1; i++) {
    final x0 = pts[i * 2], y0 = pts[i * 2 + 1];
    final x1 = pts[i * 2 + 2], y1 = pts[i * 2 + 3];
    out
      ..add(0.75 * x0 + 0.25 * x1)
      ..add(0.75 * y0 + 0.25 * y1)
      ..add(0.25 * x0 + 0.75 * x1)
      ..add(0.25 * y0 + 0.75 * y1);
  }
  if (closed) {
    out.addAll([out[0], out[1]]);
  } else {
    out.addAll([pts[pts.length - 2], pts[pts.length - 1]]);
  }
  return out;
}

List<double> _douglasPeucker(List<double> pts, double eps) {
  final m = pts.length ~/ 2;
  if (m <= 2) return pts;
  final keep = List<bool>.filled(m, false)
    ..[0] = true
    ..[m - 1] = true;
  final stack = <(int, int)>[(0, m - 1)];
  while (stack.isNotEmpty) {
    final (a, b) = stack.removeLast();
    final ax = pts[a * 2], ay = pts[a * 2 + 1];
    final dx = pts[b * 2] - ax, dy = pts[b * 2 + 1] - ay;
    final len = math.sqrt(dx * dx + dy * dy);
    var best = -1.0, at = -1;
    for (var i = a + 1; i < b; i++) {
      final px = pts[i * 2] - ax, py = pts[i * 2 + 1] - ay;
      final d = len == 0
          ? math.sqrt(px * px + py * py)
          : (px * dy - py * dx).abs() / len;
      if (d > best) {
        best = d;
        at = i;
      }
    }
    if (best > eps) {
      keep[at] = true;
      stack
        ..add((a, at))
        ..add((at, b));
    }
  }
  return [
    for (var i = 0; i < m; i++)
      if (keep[i]) ...[pts[i * 2], pts[i * 2 + 1]],
  ];
}

/// 折线 → 三角形网格（每段一个矩形，两端各外延半个线宽，盖住折点处的缝）。
/// [halfWidth] 用瓦片像素表示；线宽随缩放变化时按档重建（见 terrain_layer.dart）。
Float32List strokeTriangles(ContourLines lines, double halfWidth) {
  final out = Float32List(lines.segmentCount * 12);
  var o = 0;
  final p = lines.points;
  for (var l = 0; l < lines.lineCount; l++) {
    for (var k = lines.starts[l]; k < lines.starts[l + 1] - 1; k++) {
      var x0 = p[k * 2], y0 = p[k * 2 + 1];
      var x1 = p[k * 2 + 2], y1 = p[k * 2 + 3];
      final dx = x1 - x0, dy = y1 - y0;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len == 0) continue;
      final ux = dx / len * halfWidth, uy = dy / len * halfWidth;
      x0 -= ux;
      y0 -= uy;
      x1 += ux;
      y1 += uy;
      final nx = -uy, ny = ux;
      out
        ..[o++] = x0 + nx
        ..[o++] = y0 + ny
        ..[o++] = x0 - nx
        ..[o++] = y0 - ny
        ..[o++] = x1 + nx
        ..[o++] = y1 + ny
        ..[o++] = x1 + nx
        ..[o++] = y1 + ny
        ..[o++] = x0 - nx
        ..[o++] = y0 - ny
        ..[o++] = x1 - nx
        ..[o++] = y1 - ny;
    }
  }
  return o == out.length ? out : Float32List.sublistView(out, 0, o);
}

/// 瓦片四角的位移（瓦片像素，[西北 dx, dy, 东北 dx, dy, 西南 dx, dy, 东南 dx, dy]），
/// 块内按双线性插值（[warpPoints]）。用于把 WGS-84 计算的地形贴到 GCJ-02 底图上：
/// 火星偏移在一块 12 级瓦片（约 7 km）内会变十几到二十多米，整块按中心平移会在
/// 瓦片边界错开 1–2 个像素；四角插值时相邻瓦片共用角点，边界上的位移完全一致。
typedef TileWarp = Float32List;

/// 按四角位移原地移动 [xy]（瓦片像素坐标 [x0, y0, x1, y1, …]）。
void warpPoints(Float32List xy, TileWarp w) {
  for (var i = 0; i + 1 < xy.length; i += 2) {
    final u = xy[i] / 256, v = xy[i + 1] / 256;
    final top = 1 - u, bottom = 1 - v;
    xy[i] += (w[0] * top + w[2] * u) * bottom + (w[4] * top + w[6] * u) * v;
    xy[i + 1] += (w[1] * top + w[3] * u) * bottom + (w[5] * top + w[7] * u) * v;
  }
}

/// 四角位移的最小二乘仿射近似（列主序 4×4，作用在瓦片像素坐标上）：
/// 去掉双线性里的交叉项，四个角各差 ±交叉项/4。
Float64List affineOfWarp(TileWarp w) {
  double du(int o) => ((w[2 + o] - w[o]) + (w[6 + o] - w[4 + o])) / 2;
  double dv(int o) => ((w[4 + o] - w[o]) + (w[6 + o] - w[2 + o])) / 2;
  double c(int o) =>
      (w[o] + w[2 + o] + w[4 + o] + w[6 + o]) / 4 - du(o) / 2 - dv(o) / 2;
  return Float64List.fromList([
    1 + du(0) / 256, du(1) / 256, 0, 0, //
    dv(0) / 256, 1 + dv(1) / 256, 0, 0, //
    0, 0, 1, 0, //
    c(0), c(1), 0, 1,
  ]);
}

/// 地形阴影（256×256 RGBA，黑色 + 不透明度）：Horn 法坡度坡向，光源方位 315°、高度 45°，
/// 只压暗背光坡，平地与向光坡透明，不改变底图的颜色。
Uint8List hillshadeRgba(
  Float32List ext,
  double metersPerPixel, {
  double zFactor = 1.6,
  double maxAlpha = 0.5,
  bool padded = false,
  int border = 1,
}) {
  final e = 256 + 2 * border;
  // padded：四周多一圈（258×258，取自邻块边缘），绘制时只取中间 256×256，
  // 双线性插值在瓦片边界上也是连续的。[border] ≥ 2 时这一圈的坡度也准确，
  // 否则用单侧差分近似。
  final p = padded ? 1 : 0;
  final s = 256 + 2 * p;
  const zenith = math.pi / 4; // 90° − 高度 45°
  const azimuth = 135 * math.pi / 180; // 数学角：360 − 315 + 90
  final cosZ = math.cos(zenith), sinZ = math.sin(zenith);
  final out = Uint8List(s * s * 4);
  final k = zFactor / (8 * metersPerPixel);
  double at(int r, int c) => ext[r.clamp(0, e - 1) * e + c.clamp(0, e - 1)];
  for (var i = 0; i < s; i++) {
    for (var j = 0; j < s; j++) {
      final r = i + border - p, c = j + border - p;
      final a = at(r - 1, c - 1), b = at(r - 1, c), cc = at(r - 1, c + 1);
      final d = at(r, c - 1), f = at(r, c + 1);
      final g = at(r + 1, c - 1), h = at(r + 1, c), ii = at(r + 1, c + 1);
      final dzdx = ((cc + 2 * f + ii) - (a + 2 * d + g)) * k;
      final dzdy = ((g + 2 * h + ii) - (a + 2 * b + cc)) * k;
      if (dzdx.isNaN || dzdy.isNaN) continue;
      final slope = math.atan(math.sqrt(dzdx * dzdx + dzdy * dzdy));
      final aspect = math.atan2(dzdy, -dzdx);
      final shade =
          cosZ * math.cos(slope) +
          sinZ * math.sin(slope) * math.cos(azimuth - aspect);
      final dark = ((cosZ - shade) / cosZ).clamp(0.0, 1.0);
      out[(i * s + j) * 4 + 3] = (math.pow(dark, 0.8) * maxAlpha * 255).round();
    }
  }
  return out;
}

/// 一块瓦片的地形计算输入 / 输出（跨 isolate 传递）。
class TerrainJob {
  const TerrainJob({
    required this.ext,
    this.border = 1,
    required this.metersPerPixel,
    this.interval,
    this.indexEvery = 5,
    this.hillshade = false,
  });

  final Float32List ext;
  final int border;
  final double metersPerPixel;
  final double? interval;
  final int indexEvery;
  final bool hillshade;
}

class TerrainResult {
  const TerrainResult(this.minor, this.major, this.shade);

  final ContourLines? minor;
  final ContourLines? major;
  final Uint8List? shade;
}

TerrainResult runTerrainJob(TerrainJob job) {
  final segs = job.interval == null
      ? null
      : contourSegments(
          job.ext,
          job.interval!,
          job.indexEvery,
          border: job.border,
        );
  return TerrainResult(
    segs == null ? null : joinAndSimplify(segs.minor),
    segs == null ? null : joinAndSimplify(segs.major),
    job.hillshade
        ? shadeAsGray(
            hillshadeRgba(
              job.ext,
              job.metersPerPixel,
              padded: true,
              border: job.border,
            ),
          )
        : null,
  );
}

/// 半透明黑色阴影 → 不透明灰度（白 = 不压暗）。图层里先按不透明图叠放，
/// 合成时再换回黑色 + 透明度（terrain_layer.dart），瓦片边缘重叠时不会叠深。
Uint8List shadeAsGray(Uint8List rgba) {
  for (var i = 0; i < rgba.length; i += 4) {
    final g = 255 - rgba[i + 3];
    rgba
      ..[i] = g
      ..[i + 1] = g
      ..[i + 2] = g
      ..[i + 3] = 255;
  }
  return rgba;
}

/// 沿折线约每 [stepM] 米取一个点（保留原有顶点），并给出每点距起点的距离。
(List<LatLng>, List<double>) densify(List<LatLng> points, double stepM) {
  if (points.isEmpty) return (const [], const []);
  final out = <LatLng>[points.first];
  final dist = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final d = Geo.distanceM(a, b);
    final n = math.max(1, (d / stepM).ceil());
    for (var k = 1; k <= n; k++) {
      final t = k / n;
      out.add(
        LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ),
      );
      dist.add(dist[dist.length - k] + d * t);
    }
  }
  return (out, dist);
}

/// 海拔剖面统计。累计爬升 / 下降用 [threshold] 米的滞回去掉 DEM 噪声（只是估算）。
class ElevationStats {
  const ElevationStats({
    required this.ascentM,
    required this.descentM,
    required this.minM,
    required this.maxM,
  });

  final double ascentM, descentM, minM, maxM;
}

/// 任一点缺失时返回 null，不拿 0 或邻点顶上。
ElevationStats? elevationStats(List<double> elev, {double threshold = 5}) {
  if (elev.isEmpty || elev.any((e) => e.isNaN)) return null;
  var ref = elev.first, up = 0.0, down = 0.0;
  var lo = elev.first, hi = elev.first;
  for (final e in elev.skip(1)) {
    lo = math.min(lo, e);
    hi = math.max(hi, e);
    if (e - ref >= threshold) {
      up += e - ref;
      ref = e;
    } else if (ref - e >= threshold) {
      down += ref - e;
      ref = e;
    }
  }
  return ElevationStats(ascentM: up, descentM: down, minM: lo, maxM: hi);
}
