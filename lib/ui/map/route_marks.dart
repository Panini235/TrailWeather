import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../data/routes/route_models.dart';
import '../strings.dart';
import 'basemap.dart';

/// 线路方向箭头：沿全部段按总里程等分取 [count] 个位置（不含起终点附近），
/// 返回位置与该处行进方位角（度，0 = 正北）。纯函数，便于测试。
List<(LatLng, double)> routeDirectionMarks(
  List<List<LatLng>> segments, {
  int count = 8,
}) {
  final legs = <(LatLng, LatLng, double)>[];
  var total = 0.0;
  for (final s in segments) {
    for (var i = 1; i < s.length; i++) {
      final d = Geo.distanceM(s[i - 1], s[i]);
      if (d <= 0) continue;
      legs.add((s[i - 1], s[i], d));
      total += d;
    }
  }
  if (legs.isEmpty || count <= 0) return const [];
  final out = <(LatLng, double)>[];
  var legIdx = 0;
  var acc = 0.0;
  for (var k = 1; k <= count; k++) {
    final target = total * k / (count + 1);
    while (legIdx < legs.length - 1 && acc + legs[legIdx].$3 < target) {
      acc += legs[legIdx].$3;
      legIdx++;
    }
    final (a, b, d) = legs[legIdx];
    final t = ((target - acc) / d).clamp(0.0, 1.0);
    out.add((
      LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      Geo.bearingDeg(a, b),
    ));
  }
  return out;
}

/// 方向箭头标记层。
MarkerLayer routeDirectionLayer(
  HikingRoute route,
  Basemap basemap, {
  Color color = const Color(0xFF0D47A1),
}) {
  return MarkerLayer(
    markers: [
      for (final (pos, bearing) in routeDirectionMarks(route.segments))
        Marker(
          point: basemap.toDisplay(pos),
          width: 18,
          height: 18,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: bearing * math.pi / 180,
              child: Icon(Icons.navigation, size: 16, color: color),
            ),
          ),
        ),
    ],
  );
}

/// 起点 / 终点标记（环线合并为一个“起终”标记）。
MarkerLayer routeEndpointLayer(HikingRoute route, Basemap basemap) {
  final pts = route.flatPoints;
  if (pts.isEmpty) return const MarkerLayer(markers: []);
  Marker badge(LatLng p, String text, Color color) => Marker(
    point: basemap.toDisplay(p),
    width: 34,
    height: 34,
    child: IgnorePointer(
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
  if (route.isLoop) {
    return MarkerLayer(
      markers: [badge(pts.first, '起终', const Color(0xFF2E7D32))],
    );
  }
  return MarkerLayer(
    markers: [
      badge(pts.last, S.endPoint.substring(0, 1), const Color(0xFFC62828)),
      badge(pts.first, S.startPoint.substring(0, 1), const Color(0xFF2E7D32)),
    ],
  );
}
