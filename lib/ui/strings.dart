/// 集中管理的界面文案（默认中文）。
///
/// 国际化架构说明：所有面向用户的文案经由本文件常量引用，
/// 迁移到 ARB/gen-l10n 时只需把这些常量改为生成访问器，
/// 不需要改动业务代码（见 docs/architecture.md）。
abstract final class S {
  static const appTitle = 'TrailWeather 徒步天气';

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
  static const externalGuides = '外部攻略与轨迹线索';
  static const importOwnedTrack = '导入你有权使用的轨迹';
  static const searchThisArea = '搜索此区域线路';
  static const areaTooLarge = '视野范围过大，请放大后重试';
  static const locateMe = '定位到我';
  static const locating = '正在定位…';
  static const currentLocation = '当前位置天气';
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
  static const compareSources = '对比来源';
  static const outOfRange = '此来源暂无该日期数据';
  static const outOfRangeDetail =
      '该日期超出来源的真实预报范围。已保存你的计划日期；进入来源可用预报窗口后刷新即可更新。不会用外推或历史均值冒充预报。';
  static const staleData = '旧数据';
  static const staleDataDetail = '缓存已超过来源建议的有效期，正在后台刷新。以下数据可能过期，不当作刚更新的数据。';
  static const cachedAt = '缓存于';
  static const fetchedAt = '数据获取于';
  static const noElevation = '此线路无海拔数据，未显示海拔剖面，配速未计入爬升影响';
  static const multiSegmentNote =
      '此线路包含多段不连续几何（OSM 路线关系可能多段/缺失）。行程模式基于最长连续段计算。';
  static const sharedGridNotePrefix = '网格说明';

  // 节点
  static const nodeDetail = '节点详情';
  static const distFromStart = '距起点';
  static const eta = '预计到达';
  static const validTime = '数据有效时间';
  static const granularityLabel = '位置颗粒度';
  static const timeAlignmentNote = '各来源的最近数据时次可能不同，以下按各自最接近的有效时刻展示并标注差值。';
}
