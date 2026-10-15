/// 地图瓦片来源定义与图层选择（纯数据，不依赖 flutter_map，便于测试与持久化）。
///
/// 坐标系约束（诚实）：高德为 GCJ-02，其余内置来源为 WGS-84（天地图为
/// CGCS2000，与 WGS-84 差异在厘米级，按 WGS-84 处理）。显示坐标系由底图决定；
/// 坐标系不同的叠加层会整体错位约 100–700 m，因此不允许叠加。
library;

enum TileDatum { wgs84, gcj02 }

enum TileCategory { standard, satellite, terrain, annotation, custom }

/// 天地图 Key 在 URL 模板中的占位符。
const tiandituKeyPlaceholder = '{tk}';

class TileSourceDef {
  const TileSourceDef({
    required this.id,
    required this.name,
    required this.category,
    required this.urlTemplate,
    required this.datum,
    required this.attribution,
    this.subdomains = const [],
    this.maxNativeZoom = 18,
    this.overlayOnly = false,
    this.note = '',
    this.builtIn = true,
  });

  final String id;
  final String name;
  final TileCategory category;
  final String urlTemplate;
  final TileDatum datum;
  final String attribution;
  final List<String> subdomains;
  final int maxNativeZoom;

  /// 透明注记层，只能叠加，不能作底图。
  final bool overlayOnly;

  /// 可用性/授权说明，在图层面板展示。
  final String note;
  final bool builtIn;

  bool get needsTiandituKey => urlTemplate.contains(tiandituKeyPlaceholder);

  /// 解析为 flutter_map 可用的模板；需要天地图 Key 而未填写时返回 null。
  String? resolvedTemplate({required String tiandituKey}) {
    if (!needsTiandituKey) return urlTemplate;
    final key = tiandituKey.trim();
    if (key.isEmpty) return null;
    return urlTemplate.replaceAll(
      tiandituKeyPlaceholder,
      Uri.encodeQueryComponent(key),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'urlTemplate': urlTemplate,
    'datum': datum.name,
    'attribution': attribution,
    'subdomains': subdomains,
    'maxNativeZoom': maxNativeZoom,
    'overlayOnly': overlayOnly,
  };

  /// 仅用于用户自定义来源。
  static TileSourceDef customFromJson(Map<String, dynamic> m) => TileSourceDef(
    id: m['id'] as String,
    name: m['name'] as String? ?? '自定义图源',
    category: TileCategory.custom,
    urlTemplate: m['urlTemplate'] as String,
    datum: TileDatum.values.asNameMap()[m['datum']] ?? TileDatum.wgs84,
    attribution: m['attribution'] as String? ?? '',
    subdomains:
        (m['subdomains'] as List?)?.map((e) => e as String).toList() ??
        const [],
    maxNativeZoom: (m['maxNativeZoom'] as num?)?.toInt() ?? 18,
    overlayOnly: m['overlayOnly'] as bool? ?? false,
    note: '用户自定义图源：可用性与授权由使用者自行确认。',
    builtIn: false,
  );
}

const _amapNote = '高德直连瓦片：国内访问快；正式接入与授权范围待核验（见 docs/licenses.md）。';
const _tdtNote = '天地图：需在设置中填写你自己在天地图开放平台申请的 Key。';
const _overseasNote = '服务部署在海外，国内网络常常加载缓慢或失败。';
const _tdtSub = ['0', '1', '2', '3', '4', '5', '6', '7'];
const _tdtAttr = '© 天地图（国家地理信息公共服务平台）';

/// 内置来源。顺序即图层面板中的展示顺序。
const builtInTileSources = <TileSourceDef>[
  TileSourceDef(
    id: 'amap',
    name: '高德标准',
    category: TileCategory.standard,
    urlTemplate: 'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    datum: TileDatum.gcj02,
    attribution: '© 高德地图',
    note: _amapNote,
  ),
  TileSourceDef(
    id: 'amap_satellite',
    name: '高德卫星',
    category: TileCategory.satellite,
    urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=6&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    datum: TileDatum.gcj02,
    attribution: '© 高德地图',
    note: _amapNote,
  ),
  TileSourceDef(
    id: 'amap_labels',
    name: '高德路网注记',
    category: TileCategory.annotation,
    urlTemplate: 'https://webst0{s}.is.autonavi.com/appmaptile?style=8&x={x}&y={y}&z={z}',
    subdomains: ['1', '2', '3', '4'],
    datum: TileDatum.gcj02,
    attribution: '© 高德地图',
    overlayOnly: true,
    note: '透明路网与地名，适合叠加在高德卫星上。',
  ),
  TileSourceDef(
    id: 'tianditu_vec',
    name: '天地图矢量',
    category: TileCategory.standard,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=vec_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    note: _tdtNote,
  ),
  TileSourceDef(
    id: 'tianditu_img',
    name: '天地图影像（卫星）',
    category: TileCategory.satellite,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=img_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    note: _tdtNote,
  ),
  TileSourceDef(
    id: 'tianditu_ter',
    name: '天地图地形晕渲',
    category: TileCategory.terrain,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=ter_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    maxNativeZoom: 14,
    note: '$_tdtNote地形图最高 14 级，更大比例尺为放大显示。',
  ),
  TileSourceDef(
    id: 'tianditu_cva',
    name: '天地图矢量注记',
    category: TileCategory.annotation,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=cva_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    overlayOnly: true,
    note: _tdtNote,
  ),
  TileSourceDef(
    id: 'tianditu_cia',
    name: '天地图影像注记',
    category: TileCategory.annotation,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=cia_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    overlayOnly: true,
    note: _tdtNote,
  ),
  TileSourceDef(
    id: 'tianditu_cta',
    name: '天地图地形注记',
    category: TileCategory.annotation,
    urlTemplate: 'https://t{s}.tianditu.gov.cn/DataServer?T=cta_w&x={x}&y={y}&l={z}&tk={tk}',
    subdomains: _tdtSub,
    datum: TileDatum.wgs84,
    attribution: _tdtAttr,
    maxNativeZoom: 14,
    overlayOnly: true,
    note: _tdtNote,
  ),
  TileSourceDef(
    id: 'opentopomap',
    name: 'OpenTopoMap 等高线',
    category: TileCategory.terrain,
    urlTemplate: 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
    subdomains: ['a', 'b', 'c'],
    datum: TileDatum.wgs84,
    attribution: '© OpenStreetMap 贡献者, SRTM | © OpenTopoMap (CC-BY-SA)',
    maxNativeZoom: 17,
    note: '等高线地形图。$_overseasNote',
  ),
  TileSourceDef(
    id: 'esri_imagery',
    name: 'Esri 卫星影像',
    category: TileCategory.satellite,
    urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    datum: TileDatum.wgs84,
    attribution: 'Esri, Maxar, Earthstar Geographics',
    maxNativeZoom: 19,
    note: '$_overseasNote使用条款与商用授权待核验。',
  ),
  TileSourceDef(
    id: 'osm',
    name: 'OpenStreetMap',
    category: TileCategory.standard,
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    datum: TileDatum.wgs84,
    attribution: '© OpenStreetMap 贡献者',
    maxNativeZoom: 19,
    note: _overseasNote,
  ),
];

const defaultBaseLayerId = 'amap';

/// 已选叠加层。
class OverlaySelection {
  const OverlaySelection(this.id, {this.opacity = 1.0});

  final String id;
  final double opacity;

  OverlaySelection copyWith({double? opacity}) =>
      OverlaySelection(id, opacity: opacity ?? this.opacity);

  Map<String, dynamic> toJson() => {'id': id, 'opacity': opacity};

  static OverlaySelection fromJson(Map<String, dynamic> m) => OverlaySelection(
    m['id'] as String,
    opacity: ((m['opacity'] as num?)?.toDouble() ?? 1.0).clamp(0.1, 1.0),
  );

  @override
  bool operator ==(Object other) =>
      other is OverlaySelection && other.id == id && other.opacity == opacity;

  @override
  int get hashCode => Object.hash(id, opacity);
}

/// 全部可用来源（内置 + 自定义）。自定义 id 与内置冲突时以内置为准。
List<TileSourceDef> allTileSources(List<TileSourceDef> custom) {
  final builtInIds = {for (final s in builtInTileSources) s.id};
  return [
    ...builtInTileSources,
    ...custom.where((c) => !builtInIds.contains(c.id)),
  ];
}

TileSourceDef? findTileSource(String id, List<TileSourceDef> custom) {
  for (final s in allTileSources(custom)) {
    if (s.id == id) return s;
  }
  return null;
}

/// 叠加层不可用的原因；可用返回 null。
String? overlayBlockReason(
  TileSourceDef base,
  TileSourceDef overlay, {
  required String tiandituKey,
}) {
  if (overlay.id == base.id) return '已作为底图使用';
  if (overlay.datum != base.datum) {
    return '坐标系与当前底图不同（${datumLabel(overlay.datum)} / '
        '${datumLabel(base.datum)}），叠加会错位约 100–700 m';
  }
  if (overlay.resolvedTemplate(tiandituKey: tiandituKey) == null) {
    return '需先在设置中填写天地图 Key';
  }
  return null;
}

String datumLabel(TileDatum d) => switch (d) {
  TileDatum.wgs84 => 'WGS-84',
  TileDatum.gcj02 => 'GCJ-02',
};

/// 解析后的图层组合：底图 + 可用叠加层（不可用的被丢弃，不静默错位）。
class ResolvedMapStyle {
  const ResolvedMapStyle({
    required this.base,
    required this.baseTemplate,
    required this.overlays,
    this.baseFallbackReason,
  });

  final TileSourceDef base;
  final String baseTemplate;
  final List<(TileSourceDef, String, double)> overlays;

  /// 所选底图不可用（如缺天地图 Key、已删除的自定义来源）时回退到默认底图的原因。
  final String? baseFallbackReason;

  TileDatum get datum => base.datum;
}

ResolvedMapStyle resolveMapStyle({
  required String baseLayerId,
  required List<OverlaySelection> overlays,
  required List<TileSourceDef> custom,
  required String tiandituKey,
}) {
  final fallback = builtInTileSources.firstWhere(
    (s) => s.id == defaultBaseLayerId,
  );
  var base = findTileSource(baseLayerId, custom);
  String? reason;
  if (base == null) {
    reason = '所选底图已不存在，已回退到默认底图';
  } else if (base.overlayOnly) {
    reason = '注记层不能作为底图，已回退到默认底图';
  } else if (base.resolvedTemplate(tiandituKey: tiandituKey) == null) {
    reason = '未填写天地图 Key，已回退到默认底图';
  }
  if (reason != null) base = fallback;
  final resolvedBase = base!;
  final layers = <(TileSourceDef, String, double)>[];
  for (final sel in overlays) {
    final def = findTileSource(sel.id, custom);
    if (def == null) continue;
    if (overlayBlockReason(resolvedBase, def, tiandituKey: tiandituKey) !=
        null) {
      continue;
    }
    layers.add((
      def,
      def.resolvedTemplate(tiandituKey: tiandituKey)!,
      sel.opacity,
    ));
  }
  return ResolvedMapStyle(
    base: resolvedBase,
    baseTemplate: resolvedBase.resolvedTemplate(tiandituKey: tiandituKey)!,
    overlays: layers,
    baseFallbackReason: reason,
  );
}

/// 校验自定义瓦片 URL 模板；通过返回 null，否则返回原因。
String? validateCustomTemplate(
  String raw, {
  List<String> subdomains = const [],
}) {
  final t = raw.trim();
  if (t.isEmpty) return '请填写 URL 模板';
  final uri = Uri.tryParse(t.replaceAll(RegExp(r'\{[^}]*\}'), '0'));
  if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
    return '仅支持 http(s) 地址';
  }
  if (uri.host.isEmpty) return '地址缺少主机名';
  for (final p in ['{x}', '{z}']) {
    if (!t.contains(p)) return '模板必须包含 $p';
  }
  if (!t.contains('{y}') && !t.contains('{-y}')) return '模板必须包含 {y} 或 {-y}';
  if (t.contains('{s}') && subdomains.isEmpty) return '模板含 {s}，请填写子域名（如 a,b,c）';
  final unknown = RegExp(r'\{([^}]*)\}')
      .allMatches(t)
      .map((m) => m.group(1)!)
      .where((n) => !const {'x', 'y', '-y', 'z', 's', 'r', 'tk'}.contains(n))
      .toList();
  if (unknown.isNotEmpty) return '不支持的占位符：{${unknown.first}}';
  return null;
}
