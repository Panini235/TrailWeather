import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// 地理计算工具：haversine 距离、累计里程、几何简化。
/// 全部为纯函数，便于单元测试。
class Geo {
  static const double _earthRadiusM = 6371008.8;

  static double _rad(double deg) => deg * math.pi / 180.0;

  /// 两点间大圆距离（米）。
  static double distanceM(LatLng a, LatLng b) {
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final la1 = _rad(a.latitude);
    final la2 = _rad(b.latitude);
    final h =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(la1) * math.cos(la2) * math.pow(math.sin(dLon / 2), 2);
    return 2 * _earthRadiusM * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  /// 累计里程：out[i] 为 points[0..i] 的长度（米），out[0] = 0。
  static List<double> cumulativeDistancesM(List<LatLng> points) {
    final out = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      out[i] = out[i - 1] + distanceM(points[i - 1], points[i]);
    }
    return out;
  }

  /// Douglas-Peucker 简化（近似平面投影，容差单位：米）。
  /// 用于地图渲染；计算（里程/采样）始终使用原始几何。
  static List<LatLng> simplify(List<LatLng> points, double toleranceM) {
    if (points.length <= 2) return List.of(points);
    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    _dp(points, 0, points.length - 1, toleranceM, keep);
    return [
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }

  /// 轨迹自适应抽稀（带海拔同步与关键极值点保留）。
  ///
  /// - 当点数 <= targetMaxPoints 时直接返回副本；
  /// - 当点数超过时，保留首尾点、海拔最高点与最低点，并基于 Douglas-Peucker 算法抽稀；
  /// - 容差动态递增调整，直到保留的点数 <= targetMaxPoints；
  /// - 返回：(抽稀后的坐标点集, 抽稀后的海拔列表)，两列表严格 1:1 对齐。
  static (List<LatLng>, List<double?>) simplifyTrack(
    List<LatLng> points,
    List<double?> elevations, {
    int targetMaxPoints = 3000,
  }) {
    if (points.length <= targetMaxPoints || points.length <= 2) {
      return (List.of(points), List.of(elevations));
    }

    final hasElevations = elevations.length == points.length;

    // 寻找必须保留的特殊关键点：首尾点 + 海拔最高点 + 海拔最低点
    final mandatory = <int>{0, points.length - 1};
    if (hasElevations) {
      var minEle = double.infinity;
      var maxEle = -double.infinity;
      var minIdx = -1;
      var maxIdx = -1;
      for (var i = 0; i < elevations.length; i++) {
        final ele = elevations[i];
        if (ele != null) {
          if (ele < minEle) {
            minEle = ele;
            minIdx = i;
          }
          if (ele > maxEle) {
            maxEle = ele;
            maxIdx = i;
          }
        }
      }
      if (minIdx >= 0) mandatory.add(minIdx);
      if (maxIdx >= 0) mandatory.add(maxIdx);
    }

    // 动态调整容差（从 2 米开始，逐步放大，直到抽稀后点数 <= targetMaxPoints）
    var tolerance = 2.0;
    var keep = List<bool>.filled(points.length, false);

    for (var iter = 0; iter < 15; iter++) {
      keep = List<bool>.filled(points.length, false);
      for (final idx in mandatory) {
        keep[idx] = true;
      }

      final sortedMandatory = mandatory.toList()..sort();
      for (var m = 0; m < sortedMandatory.length - 1; m++) {
        _dp(
          points,
          sortedMandatory[m],
          sortedMandatory[m + 1],
          tolerance,
          keep,
        );
      }

      var count = 0;
      for (var i = 0; i < keep.length; i++) {
        if (keep[i]) count++;
      }

      if (count <= targetMaxPoints) {
        break;
      }
      tolerance *= 1.8;
    }

    final outPoints = <LatLng>[];
    final outElevations = <double?>[];
    for (var i = 0; i < points.length; i++) {
      if (keep[i]) {
        outPoints.add(points[i]);
        if (hasElevations) {
          outElevations.add(elevations[i]);
        }
      }
    }

    return (outPoints, outElevations);
  }

  static void _dp(
    List<LatLng> pts,
    int first,
    int last,
    double tol,
    List<bool> keep,
  ) {
    if (last <= first + 1) return;
    final latScale = 111320.0; // 每纬度米数
    final lonScale = 111320.0 * math.cos(_rad(pts[first].latitude));
    var maxDist = -1.0;
    var maxIdx = -1;
    final x1 = pts[first].longitude * lonScale;
    final y1 = pts[first].latitude * latScale;
    final x2 = pts[last].longitude * lonScale;
    final y2 = pts[last].latitude * latScale;
    final dx = x2 - x1;
    final dy = y2 - y1;
    final len2 = dx * dx + dy * dy;
    for (var i = first + 1; i < last; i++) {
      final x = pts[i].longitude * lonScale;
      final y = pts[i].latitude * latScale;
      double d;
      if (len2 == 0) {
        d = _hypot(x - x1, y - y1);
      } else {
        var t = ((x - x1) * dx + (y - y1) * dy) / len2;
        t = t.clamp(0.0, 1.0);
        d = _hypot(x - (x1 + t * dx), y - (y1 + t * dy));
      }
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }
    if (maxDist > tol && maxIdx > 0) {
      keep[maxIdx] = true;
      _dp(pts, first, maxIdx, tol, keep);
      _dp(pts, maxIdx, last, tol, keep);
    }
  }

  /// 点到线段的最近距离（米，近似投影）。
  static double pointToSegmentDistanceM(LatLng p, LatLng a, LatLng b) {
    final latScale = 111320.0;
    final midLat = (p.latitude + a.latitude + b.latitude) / 3;
    final lonScale = 111320.0 * math.cos(_rad(midLat));
    final px = p.longitude * lonScale, py = p.latitude * latScale;
    final ax = a.longitude * lonScale, ay = a.latitude * latScale;
    final bx = b.longitude * lonScale, by = b.latitude * latScale;
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    if (len2 == 0) return _hypot(px - ax, py - ay);
    var t = ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    return _hypot(px - (ax + t * dx), py - (ay + t * dy));
  }

  static (double, double) minMaxLat(List<LatLng> pts) {
    var mn = pts.first.latitude, mx = pts.first.latitude;
    for (final p in pts) {
      if (p.latitude < mn) mn = p.latitude;
      if (p.latitude > mx) mx = p.latitude;
    }
    return (mn, mx);
  }

  static (double, double) minMaxLon(List<LatLng> pts) {
    var mn = pts.first.longitude, mx = pts.first.longitude;
    for (final p in pts) {
      if (p.longitude < mn) mn = p.longitude;
      if (p.longitude > mx) mx = p.longitude;
    }
    return (mn, mx);
  }

  /// 线路总爬升（米）。任一相邻点海拔缺失则返回 null，不编造。
  static double? totalAscentM(List<double?> elevations) {
    var prev = elevations.first;
    if (prev == null) return null;
    var ascent = 0.0;
    for (final e in elevations.skip(1)) {
      if (e == null) return null;
      final d = e - prev!;
      if (d > 0) ascent += d;
      prev = e;
    }
    return ascent;
  }

  /// Dart math 无 hypot，自实现。
  static double _hypot(double a, double b) => math.sqrt(a * a + b * b);
}
