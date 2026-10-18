import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../../core/gcj02.dart';
import '../../data/map/tile_cache.dart';
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
///
/// 天地图 Key 按 [flutterMapRequester] 选择：原生 App 用服务端 Key，Web 用
/// 浏览器端 Key（平台判断在数据层，见 [TileRequester]）。
class Basemap {
  const Basemap(this.style, {this.tiandituClient});

  /// [tiandituClient]：天地图图层使用的 http client（通常为
  /// `tiandituTileClientProvider`，用于识别 403 错误码）；为 null 时用
  /// flutter_map 默认 client。只做坐标换算、不渲染瓦片时可不传。
  factory Basemap.fromSettings(AppSettings s, {http.Client? tiandituClient}) =>
      Basemap(
        resolveMapStyle(
          baseLayerId: s.baseLayerId,
          overlays: s.overlayLayers,
          custom: s.customTileSources,
          tiandituKeys: s.tiandituKeys,
          requester: flutterMapRequester,
        ),
        tiandituClient: tiandituClient,
      );

  /// 仅指定底图（测试与简单场景）。
  factory Basemap.base(
    String baseLayerId, {
    TiandituKeys tiandituKeys = const TiandituKeys(),
  }) => Basemap(
    resolveMapStyle(
      baseLayerId: baseLayerId,
      overlays: const [],
      custom: const [],
      tiandituKeys: tiandituKeys,
      requester: flutterMapRequester,
    ),
  );

  final ResolvedMapStyle style;
  final http.Client? tiandituClient;

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
  /// 天地图图层用 [tiandituClient]（外部传入的 client 不会被 TileLayer 关闭）；
  /// 高德图层用 [amapTileCacheGuard]，空白瓦片不进磁盘缓存（T-169）。
  TileLayer _layer(
    TileSourceDef def,
    String template, {
    VoidCallback? onTileError,
    VoidCallback? onTileLoaded,
  }) {
    final client = def.needsTiandituKey ? tiandituClient : null;
    return TileLayer(
      urlTemplate: template.replaceAll('{-y}', '{y}'),
      subdomains: def.subdomains,
      userAgentPackageName: 'app.shanqing.hiking',
      maxNativeZoom: def.maxNativeZoom,
      tms: template.contains('{-y}'),
      tileProvider: client != null
          ? NetworkTileProvider(httpClient: client)
          : _isAmapTemplate(template)
          ? NetworkTileProvider(cachingProvider: amapTileCacheGuard)
          : null,
      errorTileCallback: onTileError == null
          ? null
          : (_, _, _) => onTileError(),
      tileBuilder: onTileLoaded == null
          ? null
          : (context, tileWidget, tile) {
              if (tile.imageInfo != null && !tile.loadError) onTileLoaded();
              return tileWidget;
            },
    );
  }

  static bool _isAmapTemplate(String template) {
    final uri = Uri.tryParse(template.replaceAll('{s}', '1'));
    return uri != null && isAmapTileUrl(uri);
  }

  /// 底图 + 叠加层（自下而上）。在地图 children 中展开使用。
  /// [onTileError]：任一瓦片加载失败时回调；[onTileLoaded]：底图有瓦片成功显示时回调。
  /// 两者都可能在构建期间触发，调用方不能直接 setState。
  List<Widget> tileLayers({
    VoidCallback? onTileError,
    VoidCallback? onTileLoaded,
  }) => [
    _layer(
      style.base,
      style.baseTemplate,
      onTileError: onTileError,
      onTileLoaded: onTileLoaded,
    ),
    for (final (def, template, opacity) in style.overlays)
      Opacity(
        opacity: opacity,
        child: _layer(def, template, onTileError: onTileError),
      ),
  ];

  /// [extra]：本机计算图层的署名（如等高线用到的高程数据）。
  Widget attributionWidget({List<String> extra = const []}) {
    final texts = <String>{
      style.base.attribution,
      for (final o in style.overlays) o.$1.attribution,
      ...extra,
    }.where((t) => t.trim().isNotEmpty);
    return RichAttributionWidget(
      attributions: [
        for (final t in texts) TextSourceAttribution(t, onTap: () {}),
      ],
    );
  }
}
