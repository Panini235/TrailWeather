import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/gcj02.dart';
import '../../data/map/tile_sources.dart';
import '../../data/settings/settings_repository.dart';

/// 底图与坐标系适配：业务层始终 WGS-84，仅渲染/交互边界做转换。
///
/// 显示坐标系由底图决定：高德系列为 GCJ-02（渲染前把 WGS-84 业务坐标转
/// GCJ-02，交互坐标逆变换回 WGS-84），其余为 WGS-84 恒等。叠加层必须与底图
/// 同坐标系（见 [overlayBlockReason]），否则不渲染。
///
/// 偏移说明（诚实）：GCJ-02 为国测局加密坐标，偏移约 100–700 m；
/// 转换为业内通用近似算法（迭代逆变换误差米级），非官方精确参数。
class Basemap {
  const Basemap(this.style);

  factory Basemap.fromSettings(AppSettings s) => Basemap(
    resolveMapStyle(
      baseLayerId: s.baseLayerId,
      overlays: s.overlayLayers,
      custom: s.customTileSources,
      tiandituKey: s.tiandituKey,
    ),
  );

  /// 仅指定底图（测试与简单场景）。
  factory Basemap.base(String baseLayerId, {String tiandituKey = ''}) =>
      Basemap(
        resolveMapStyle(
          baseLayerId: baseLayerId,
          overlays: const [],
          custom: const [],
          tiandituKey: tiandituKey,
        ),
      );

  final ResolvedMapStyle style;

  bool get isGcj => style.datum == TileDatum.gcj02;

  /// 图层组合签名，用于在图层切换时重建依赖初始相机的地图。
  String get signature => [
    style.base.id,
    for (final o in style.overlays) '${o.$1.id}@${o.$3}',
  ].join('+');

  /// 业务（WGS-84）→ 显示坐标。
  LatLng toDisplay(LatLng wgs) => isGcj ? Gcj02.wgs84ToGcj02(wgs) : wgs;

  /// 显示坐标 → 业务（WGS-84）。
  LatLng toBusiness(LatLng display) =>
      isGcj ? Gcj02.gcj02ToWgs84(display) : display;

  /// 可视包围盒（显示坐标系）→ 业务包围盒（用于 Overpass 查询与本地过滤）。
  LatLngBounds toBusinessBounds(LatLngBounds b) => isGcj
      ? LatLngBounds(
          Gcj02.gcj02ToWgs84(b.southWest),
          Gcj02.gcj02ToWgs84(b.northEast),
        )
      : b;

  /// flutter_map 没有 `{-y}` 占位符：转为 `{y}` + tms 翻转。
  static TileLayer _layer(TileSourceDef def, String template) => TileLayer(
    urlTemplate: template.replaceAll('{-y}', '{y}'),
    subdomains: def.subdomains,
    userAgentPackageName: 'dev.trailweather.trailweather',
    maxNativeZoom: def.maxNativeZoom,
    tms: template.contains('{-y}'),
  );

  /// 底图 + 叠加层（自下而上）。在地图 children 中展开使用。
  List<Widget> tileLayers() => [
    _layer(style.base, style.baseTemplate),
    for (final (def, template, opacity) in style.overlays)
      Opacity(opacity: opacity, child: _layer(def, template)),
  ];

  Widget attributionWidget() {
    final texts = <String>{
      style.base.attribution,
      for (final o in style.overlays) o.$1.attribution,
    }.where((t) => t.trim().isNotEmpty);
    return RichAttributionWidget(
      attributions: [
        for (final t in texts) TextSourceAttribution(t, onTap: () {}),
      ],
    );
  }
}
