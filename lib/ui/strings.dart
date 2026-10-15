/// 集中管理的界面文案（默认中文）。
///
/// 国际化架构说明：所有面向用户的文案经由本文件常量引用，
/// 迁移到 ARB/gen-l10n 时只需把这些常量改为生成访问器，
/// 不需要改动业务代码（见 docs/architecture.md）。
abstract final class S {
  static const appTitle = '山晴';

  // 通用
  static const ok = '确定';
  static const cancel = '取消';
  static const retry = '重试';
  static const refresh = '刷新';
  static const close = '关闭';
  static const settings = '设置';
  static const importRoute = '导入线路';
  static const favorites = '收藏';
  static const viewDetail = '查看详情';
  static const unknown = '未知';
  static const notProvided = '此来源未提供';
  static const demoLabel = '演示';
  static const loading = '加载中…';
  static const emptyRoutes = '当前区域没有线路';

  // 地图首页
  static const searchHint = '搜索地点、山峰或徒步线路';
  static const hybridSearchTitle = '混合线路搜索';
  static const directRoutes = '可直接分析的线路';
  static const placeCandidates = '地点候选';
  static const noDirectRoutes = '暂未找到可直接分析的线路。可导入你有权使用的轨迹文件。';
  static const importOwnedTrack = '导入你有权使用的轨迹';
  // 首页“我的行程”与底部导航（docs/redesign-v2.md）
  static const myTrips = '我的行程';
  static const tabTrips = '行程';
  static const tabMap = '地图';
  static const tabSettings = '设置';
  static const addTrip = '添加线路';
  static const drawRoute = '在地图上手绘线路';
  static const drawRouteHint = '打点画线、标记营地与水源';
  static const delete = '删除';
  static const more = '更多';
  static const deleteTripDetail = '只删除本机保存的这条线路，无法恢复。';
  static const emptyTripsTitle = '导入你的第一条轨迹';
  static const emptyTripsBody =
      '从两步路、六只脚、奥维等导出 GPX / KML / KMZ，导入后按出发时间查看沿途天气。';
  static const openWithHint = '也可以在两步路、奥维、微信或文件管理器里打开轨迹文件时，选择“山晴”直接导入。';
  static const exampleRoutes = '示例线路';
  static const planetEntry = '徒步星球 · 全球经典线路';
  static const planetEntryHint = '44 条经典线路，可直接体验沿途天气';
  static const saveToTrips = '保存到我的行程';
  static const importPrivacyNote =
      '线路将保存在本机（不上传）。注意：线路数据可能包含住宅、常去出发点等敏感位置，分享前请自行判断。';
  static const importTrackHint = '导入 GPX / KML / KMZ / GeoJSON 后即可分析沿途天气';
  static const searchThisArea = '搜索此区域线路';
  // “搜索此区域”降级到线路列表内的次要入口：Overpass 公共实例部署在海外，
  // 国内网络实测大多超时/504，作为主按钮会让用户反复等待后失败。
  static const tryOsmArea = '尝试加载此区域 OSM 线路';
  static const tryOsmAreaNote =
      'OpenStreetMap 线路服务部署在海外，国内网络常常无法访问或要等待较久；'
      '更可靠的方式是导入你自己的 GPX / KML 轨迹。';
  static const osmAreaLoading = '正在请求 OpenStreetMap 线路，可能需要较长时间…';
  static const osmAreaEmpty = '此区域暂未加载到 OSM 线路。';
  static const placeMovedNoRoutes = '已移动到该地点。附近暂无可直接分析的线路，可导入 GPX / KML 轨迹。';
  static const areaTooLarge = '视野范围过大，请放大后重试';
  static const locateMe = '定位到我';
  static const locating = '正在定位…';
  static const currentLocation = '当前位置天气';
  static const lastKnownLocation = '上次已知位置天气';
  static const myLocationChip = '当前位置';
  static const lastKnownChip = '上次已知位置';
  static const myLocationTapHint = '点击查看天气';
  static const myLocationNoTemp = '气温未提供';
  static const lastKnownFallback = '暂未取到新位置，已显示系统缓存的上次已知位置，可能与你此刻所在位置不同。';
  static const selectedPointWeather = '地图选点天气';
  static const locationDenied = '未获得定位权限。你仍可手动点选地图查询天气。';
  static const locationSettings = '打开设置';
  static const tapMapWeatherHint = '点击地图任意位置可查看该点附近天气';
  static const routeListTitle = '本区域线路';
  static const osmFetchFail = 'OpenStreetMap 线路服务暂不可用，可稍后重试或查看本地线路。';
  static const listButton = '线路列表';

  // 线路详情
  static const distanceLabel = '里程';
  static const ascentLabel = '累计爬升';
  static const elevationLabel = '海拔';
  static const startLabel = '起点';
  static const endLabel = '终点';
  static const highPointLabel = '高点';
  static const dataSourceLabel = '数据来源';
  static const modeFixed = '固定时刻';
  static const modeTrip = '行程模式';
  static const modeFixedDesc = '整条线路展示同一有效时刻的天气：\n“这个时候线路各处天气如何”';
  static const modeTripDesc = '按出发时间与配速估算各节点到达时间，\n查询对应时段天气：“我走到这里时可能是什么天气”';
  static const pickDate = '选择日期';
  static const pickTime = '选择时刻';
  static const departure = '出发时间';
  static const paceSettings = '配速与休息';
  static const etaIsEstimate = '预计到达时间为估算，不构成导航保证';
  static const weatherAlongRoute = '沿途天气节点';
  static const routeSummary = '线路摘要';
  static const riskHints = '天气提示';
  static const officialAlerts = '官方预警';
  static const sourceTransparency = '来源与颗粒度';
  static const routeMapFullscreen = '全屏查看线路地图';
  static const routeMapFitAll = '显示整条线路';
  static const compareSources = '对比来源';
  static const outOfRange = '此来源暂无该日期数据';
  static const outOfRangeDetail =
      '该日期超出来源的真实预报范围。已保存你的计划日期；进入来源可用预报窗口后刷新即可更新。不会用外推或历史均值冒充预报。';
  static const staleData = '旧数据';
  static const staleDataDetail = '缓存已超过来源建议的有效期，正在后台刷新。以下数据可能过期，不当作刚更新的数据。';
  static const cachedAt = '缓存于';
  static const fetchedAt = '数据获取于';
  static const noElevation = '此线路无海拔数据，未显示海拔剖面，配速未计入爬升影响';
  static const planetElevationNote = '经典线路的海拔由路线剖面按距离线性插值得到，为估算值；高点位置与爬升量仅供参考。';
  static const longTripNote =
      '按当前配速估算全程超过 12 小时：行程模式按连续行走推算，未计入夜间宿营。'
      '多日线路的后段到达时间与对应天气仅供参考，请按每日行程分段查看。';
  static const multiSegmentNote =
      '此线路包含相距较远（超过 1 km）的断开段，沿途天气只分析首尾相接的最长部分；断开处不自动连线。';
  // 线路详情 v2：方向、起终点、节点联动、标记（docs/redesign-v2.md 第 1 步）
  static const save = '保存';
  static const startPoint = '起点';
  static const endPoint = '终点';
  static const loopRoute = '环线';
  static const reverseRoute = '反向行走';
  static const reversedNote = '已切换为反向行走：起终点互换，预计到达时间与沿途天气按新方向重新推算。';
  static const nodeDetail2 = '节点详情';
  static const markAs = '标记为';
  static const removeMark = '移除标记';
  static const editMark = '编辑标记';
  static const markName = '名称';
  static const markStopMinutes = '停留时长（分钟，计入后续到达时间）';
  static const markSavedNew = '已保存到“我的行程”（含你的标记）';
  static const markTooFar = '离线路太远（超过 300 m），请在线路附近长按添加标记';
  static const longPressToMark = '长按线路附近任意位置可添加营地、休息点等标记';
  static const next12h = '此节点未来 12 小时（当前来源）';
  static const multiSourceCompare = '多来源对比';
  static const arrivalEstimate = '预计到达（估算）';
  static const fixedMoment = '选定时刻';
  static const tapAgainForDetail = '再点一次查看节点详情';
  static const offRouteWaypoint = '偏离线路超过 300 m，未计入沿途时间线';
  static const sharedGridNotePrefix = '网格说明';

  // 节点
  static const nodeDetail = '节点详情';
  static const distFromStart = '距起点';
  static const eta = '预计到达';
  static const validTime = '数据有效时间';
  static const granularityLabel = '位置颗粒度';
  static const timeAlignmentNote = '各来源的最近数据时次可能不同，以下按各自最接近的有效时刻展示并标注差值。';

  // 地图图层
  static const mapLayers = '地图图层';
  static const baseLayer = '底图';
  static const overlayLayers = '叠加图层';
  static const overlayOpacity = '透明度';
  static const manageTileSources = '管理图源与天地图 Key';
  static const mapLayerDatumNote =
      '显示坐标系由底图决定。高德为 GCJ-02，其余为 WGS-84；坐标系不同的图层叠加会错位约 100–700 m，因此不可同时叠加。线路与天气计算始终使用 WGS-84。';
  static const tiandituKeyTitle = '天地图 Key';
  static const tiandituKeyHelp =
      '在天地图开放平台（console.tianditu.gov.cn）用你自己的账号申请 Key 后填写，仅保存在本机。'
      'App 不代为注册。填写后可使用天地图矢量、影像（卫星）、地形晕渲与注记图层。';
  static const tiandituKeyMissing = '需先在“管理图源与天地图 Key”中填写天地图 Key';
  static const customTileSources = '自定义图源';
  static const customTileSourcesHelp =
      '填写 XYZ 瓦片地址模板，例如 https://{s}.example.com/{z}/{x}/{y}.png。'
      '支持 {x} {y} {-y} {z} {s} {r} {tk}（{tk} 使用天地图 Key）。图源的可用性与授权由你自行确认。';
  static const addCustomTileSource = '添加自定义图源';
  static const editCustomTileSource = '编辑自定义图源';
  static const customTileOverlayOnly = '仅作叠加（透明图层，不能作底图）';
  static const noCustomTileSources = '尚未添加自定义图源。';
  static const saved = '已保存（仅本机）';

  // 节点天气样式与图片
  static const nodeWxLegendNote = '节点颜色按固定阈值归类所选来源该时刻的数据，非安全评分、非官方预警；灰色表示数据不足。';
  static const nodePhotos = '节点图片';
  static const photoFromGallery = '相册';
  static const photoFromCamera = '拍照';
  static const noNodePhotos = '此节点附近还没有图片。';
  static const photosLocalOnly = '图片只保存在本机，不上传；卸载 App 会一并删除。';
  static const photosUnsupported = '当前平台（Web）暂不支持保存图片，请在手机 App 中添加。';
  static const photoAddFailed = '图片添加失败，请重试。';
  static const photoMissing = '图片文件已丢失';
  static const photoAddedAt = '添加于';
  static const photoCaption = '备注';
  static const photoDelete = '删除图片';
}
