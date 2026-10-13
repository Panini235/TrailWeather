import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/gcj02.dart';
import '../../data/settings/settings_repository.dart';

/// 底图与坐标系适配：业务层始终 WGS-84，仅渲染/交互边界做转换。
///
/// - amap（默认）：高德栅格瓦片，GCJ-02；大陆直连快（实测 70ms 级）。
///   WGS-84 业务坐标渲染前转 GCJ-02；地图交互坐标逆变换回 WGS-84。
/// - osm：OpenStreetMap 标准瓦片，WGS-84 恒等；大陆直连通常不可用（实测超时），
///   供海外网络或代理环境选择。
///
/// 偏移说明（诚实）：GCJ-02 为国测局加密坐标，偏移约 100–700 m；
/// 转换为业内通用近似算法（迭代逆变换误差米级），非官方精确参数。
class Basemap {
  const Basemap(this.source);

  final BasemapSource source;

  bool get isGcj => source == BasemapSource.amap;

  /// 业务（WGS-84）→ 显示坐标。
  LatLng toDisplay(LatLng wgs) =>
      isGcj ? Gcj02.wgs84ToGcj02(wgs) : wgs;

  /// 显示坐标 → 业务（WGS-84）。
  LatLng toBusiness(LatLng display) =>
      isGcj ? Gcj02.gcj02ToWgs84(display) : display;

  /// 可视包围盒（显示坐标系）→ 业务包围盒（用于 Overpass 查询与本地过滤）。
  LatLngBounds toBusinessBounds(LatLngBounds b) => isGcj
      ? LatLngBounds(
          Gcj02.gcj02ToWgs84(b.southWest), Gcj02.gcj02ToWgs84(b.northEast))
      : b;

  TileLayer tileLayer() => switch (source) {
        BasemapSource.amap => TileLayer(
            urlTemplate:
                'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
            subdomains: const ['1', '2', '3', '4'],
            userAgentPackageName: 'dev.trailweather.trailweather',
            maxNativeZoom: 18,
          ),
        BasemapSource.osm => TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'dev.trailweather.trailweather',
          ),
      };

  Widget attributionWidget() => RichAttributionWidget(
        attributions: [
          TextSourceAttribution(
            switch (source) {
              BasemapSource.amap => '© 高德地图',
              BasemapSource.osm => '© OpenStreetMap 贡献者',
            },
            onTap: () {},
          ),
        ],
      );
}
