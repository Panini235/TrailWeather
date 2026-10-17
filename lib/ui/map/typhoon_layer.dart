import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../data/weather/typhoon.dart';
import '../tokens.dart';
import 'basemap.dart';

/// 台风路径图层：过去路径实线、预报路径虚线；大风区（黄）与暴风区（红）；
/// 预报点的 70% 概率圆（虚边）；中心与预报时刻标签。
List<Widget> typhoonLayers(List<Typhoon> list, Basemap basemap) {
  if (list.isEmpty) return const [];
  final circles = <CircleMarker>[];
  final lines = <Polyline>[];
  final markers = <Marker>[];
  for (final t in list) {
    final center = basemap.toDisplay(t.center);
    if (t.galeRadiusM != null) {
      circles.add(
        CircleMarker(
          point: basemap.toDisplay(t.galeCenter ?? t.center),
          radius: t.galeRadiusM!,
          useRadiusInMeter: true,
          color: Semantic.caution.withValues(alpha: 0.16),
          borderColor: Semantic.caution.withValues(alpha: 0.7),
          borderStrokeWidth: 1,
        ),
      );
    }
    if (t.stormRadiusM != null) {
      circles.add(
        CircleMarker(
          point: center,
          radius: t.stormRadiusM!,
          useRadiusInMeter: true,
          color: Semantic.danger.withValues(alpha: 0.22),
          borderColor: Semantic.danger.withValues(alpha: 0.8),
          borderStrokeWidth: 1,
        ),
      );
    }
    for (final f in t.forecasts) {
      if (f.probabilityRadiusM == null) continue;
      circles.add(
        CircleMarker(
          point: basemap.toDisplay(f.center),
          radius: f.probabilityRadiusM!,
          useRadiusInMeter: true,
          color: Colors.white.withValues(alpha: 0.10),
          borderColor: const Color(0xFF5B6B78),
          borderStrokeWidth: 1,
        ),
      );
    }
    if (t.track.length >= 2) {
      lines.add(
        Polyline(
          points: [for (final p in t.track) basemap.toDisplay(p)],
          color: Semantic.danger,
          strokeWidth: 2.5,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      );
    }
    if (t.forecasts.isNotEmpty) {
      lines.add(
        Polyline(
          points: [
            center,
            for (final f in t.forecasts) basemap.toDisplay(f.center),
          ],
          color: Semantic.danger,
          strokeWidth: 2,
          pattern: StrokePattern.dashed(segments: const [8, 6]),
        ),
      );
    }
    markers.add(
      Marker(
        point: center,
        width: 34,
        height: 34,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [BoxShadow(blurRadius: 3, color: Colors.black38)],
          ),
          child: Icon(Icons.cyclone, size: 28, color: Semantic.danger),
        ),
      ),
    );
    markers.add(
      Marker(
        point: center,
        width: 160,
        height: 24,
        alignment: const Alignment(0, 2.2),
        child: Center(
          child: _Tag(
            '${t.nameEn ?? t.id}'
            '${t.pressureHpa == null ? '' : ' · ${t.pressureHpa!.round()} hPa'}',
          ),
        ),
      ),
    );
    // 只标 24 / 72 / 120 小时三个预报点：小比例尺下相邻预报点挨得很近，全标会叠在一起。
    for (final f in t.forecasts) {
      if (f.hours != 24 && f.hours != 72 && f.hours != 120) continue;
      final local = f.validUtc.toLocal();
      markers.add(
        Marker(
          point: basemap.toDisplay(f.center),
          width: 70,
          height: 22,
          alignment: const Alignment(0, 1.6),
          child: Center(child: _Tag('${local.day}日${local.hour}时')),
        ),
      );
    }
  }
  return [
    CircleLayer(circles: circles),
    PolylineLayer(polylines: lines),
    MarkerLayer(markers: markers),
  ];
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(Radii.sm),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10.5, color: Color(0xFF121915)),
    ),
  );
}
