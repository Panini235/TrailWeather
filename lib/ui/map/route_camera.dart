import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/routes/route_models.dart';
import 'basemap.dart';

/// 包围盒最小边长（度，约 200 m）。单点或极短线路的包围盒为零面积，
/// 直接适配会得到无穷大缩放级别。
const double _minSpanDeg = 0.002;

/// 线路全部几何段在**显示坐标系**下的包围盒（GCJ-02 底图先 toDisplay）。
/// 没有任何点时返回 null。
LatLngBounds? routeDisplayBounds(HikingRoute route, Basemap basemap) {
  double? minLat, maxLat, minLon, maxLon;
  for (final seg in route.segments) {
    for (final p in seg) {
      final d = basemap.toDisplay(p);
      if (minLat == null) {
        minLat = maxLat = d.latitude;
        minLon = maxLon = d.longitude;
        continue;
      }
      if (d.latitude < minLat) minLat = d.latitude;
      if (d.latitude > maxLat!) maxLat = d.latitude;
      if (d.longitude < minLon!) minLon = d.longitude;
      if (d.longitude > maxLon!) maxLon = d.longitude;
    }
  }
  if (minLat == null) return null;
  var (s, n, w, e) = (minLat, maxLat!, minLon!, maxLon!);
  if (n - s < _minSpanDeg) {
    final mid = (n + s) / 2;
    s = mid - _minSpanDeg / 2;
    n = mid + _minSpanDeg / 2;
  }
  if (e - w < _minSpanDeg) {
    final mid = (e + w) / 2;
    w = mid - _minSpanDeg / 2;
    e = mid + _minSpanDeg / 2;
  }
  return LatLngBounds(LatLng(s, w), LatLng(n, e));
}

/// 让整条线路落在视野内的相机适配；线路无几何时返回 null。
CameraFit? routeCameraFit(
  HikingRoute route,
  Basemap basemap, {
  EdgeInsets padding = const EdgeInsets.all(24),
}) {
  final bounds = routeDisplayBounds(route, basemap);
  if (bounds == null) return null;
  return CameraFit.bounds(bounds: bounds, padding: padding, maxZoom: 16);
}
