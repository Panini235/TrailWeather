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
  static const searchHint = '搜索地点、山峰、线路或经纬度';
  static const coordinateResult = '经纬度';
  static const coordinateNote =
      '按 WGS-84（GPS、两步路、奥维）解析；来自高德等国内地图的坐标约偏几百米，对天气格点影响很小。';
  static const coordinateSwappedNote = '已按“经度, 纬度”顺序识别。';
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
  static const onDemandQuery = '查询此点（消耗 1 次额度）';
  static const altitudeCardTitle = '同一地点不同海拔';
  static const altitudeCardNote = 'Open-Meteo 按海拔统计降尺度的模型估算，非实测；▶ 为当前节点/地面海拔。';
  static const airQualityTitle = '空气质量（雾霾）';
  static const phenomenonLabel = '天气现象';
  static const moreMetrics = '更多指标';
  static const shareImage = '分享图片';
  static const shareNeedsData = '天气数据加载完成后才能分享';
  static const probVsAmountNote = '概率与降水量来自不同模型，可能不一致';
  static const noHintsTriggered = '当前数据未触发任何阈值提示（这不代表安全）。';
  static const dataNotesTitle = '数据说明与来源';
  static const dataNotesSubtitle = '颗粒度、模型、官方预警与线路来源';
  static const chooseSource = '选择天气来源';
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
      '在天地图开放平台（console.tianditu.gov.cn）用你自己的账号申请 Key 后填写，仅保存在本机，App 不代为注册。'
      '天地图按请求是否来自浏览器校验 Key 的“应用类型”，一个 Key 只能用在一端，所以需要两个：'
      '在控制台“创建新应用”时分别选“服务端”和“浏览器端”，白名单都留空。'
      '填写后可使用天地图矢量、影像（卫星）、地形晕渲与注记图层。';
  static const tiandituServerKeyLabel = '服务端 Key（Android / iOS App 使用）';
  static const tiandituServerKeyHint = '控制台应用类型选“服务端”，IP 白名单留空';
  static const tiandituBrowserKeyLabel = '浏览器端 Key（网页版与 3D 视图使用）';
  static const tiandituBrowserKeyHint = '控制台应用类型选“浏览器端”，域名白名单留空';
  static const tiandituUsingServerKey = '本设备的地图使用：服务端 Key';
  static const tiandituUsingBrowserKey = '本设备的地图使用：浏览器端 Key（网页版）';
  static const tiandituSameKeyWarning =
      '两栏填的是同一个 Key：天地图 Key 只有一种应用类型，必有一端无法出图（旧版单一 Key 迁移后也会这样）。'
      '请按 Key 在控制台的实际类型只保留在对应一栏。';
  static const tiandituServerKeyMissing = '需先在“管理图源与天地图 Key”中填写天地图服务端 Key';
  static const tiandituBrowserKeyMissing = '需先在“管理图源与天地图 Key”中填写天地图浏览器端 Key';
  static const tiandituKeyNotConfigured = '未配置';
  static const tiandituErrorTitle = '天地图图层加载失败';
  static const tiandituErrInvalidKey =
      'Key 无效（301001 非法 key）：请到天地图控制台核对 Key 是否完整、是否已删除。';
  static const tiandituErrBrowserKeyNotInBrowser =
      '“服务端 Key”一栏填的是浏览器端 Key（301012）：App 原生地图需要应用类型为“服务端”的 Key；浏览器端 Key 请填到“浏览器端 Key”一栏。';
  static const tiandituErrServerKeyInBrowser =
      '“浏览器端 Key”一栏填的是服务端 Key（301013）：网页版需要应用类型为“浏览器端”的 Key；服务端 Key 请填到“服务端 Key”一栏。';
  static const tiandituErrBlocked =
      '请求被天地图拦截（HTTP 418）：实测 Key 格式不正确时会出现，请检查是否完整复制了 Key。';
  static const tiandituErrOther = '天地图瓦片加载失败，请检查 Key 类型与有效性';
  static const tiandituOpenKeySettings = '设置天地图 Key';
  static const customTileSources = '自定义图源';
  static const customTileSourcesHelp =
      '填写 XYZ 瓦片地址模板，例如 https://{s}.example.com/{z}/{x}/{y}.png。'
      '支持 {x} {y} {-y} {z} {s} {r} {tk}（{tk} 按平台使用天地图 Key：App 用服务端 Key，网页版用浏览器端 Key）。图源的可用性与授权由你自行确认。';
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

  // 隐私说明（首启同意与设置页共用；内容变化时提升 AppSettings.privacyNoticeVersion）
  static const privacyTitle = '隐私说明';
  static const privacySummary =
      '山晴不需要注册账号，不内置统计、广告或崩溃上报 SDK。线路、收藏、图片和设置只保存在本机；'
      '查询天气时，线路或地图上点选的坐标会发送给你启用的天气来源。';
  static const privacyAgree = '我已阅读并同意隐私说明';
  static const privacyRead = '查看隐私说明';
  static const privacyRequired = '请先阅读并勾选同意隐私说明';
  static const privacySections = <(String, String)>[
    (
      '我们不收集什么',
      '山晴没有自己的服务器和账号体系，不收集姓名、手机号、设备标识，'
          '不内置统计、广告或崩溃上报 SDK。',
    ),
    (
      '保存在本机的数据',
      '导入或手绘的线路、收藏、节点图片、离线行程包、设置、你填写的第三方 Key、天气缓存，'
          '都只保存在本机。可在“缓存管理”清除缓存；卸载 App 会一并删除。',
    ),
    (
      '位置',
      '只在前台读取位置，不持续监听、不后台定位。打开地图时，仅当你此前已授权才自动定位；'
          '系统授权只在你点击“定位”按钮时请求。拒绝定位后仍可手动点选地图、搜索地点和查看线路天气。',
    ),
    (
      '发送给第三方的数据',
      '查询天气时，线路采样点、你点选或定位得到的坐标（及海拔）会发送给已启用的天气来源：'
          'Open-Meteo（含海拔、空气质量、地点搜索）、MET Norway，以及你自行配置 Key 后的和风天气、meteoblue。'
          '在地图上搜索线路时，当前视野范围会发送给 OpenStreetMap Overpass 服务。'
          '地图瓦片由你选择的底图服务商（高德、天地图、OpenStreetMap 等）提供，请求中包含瓦片坐标。'
          '这些服务会按各自的隐私政策处理请求（包括你的 IP 地址）。',
    ),
    (
      '文件与图片',
      '导入的 GPX/KML/KMZ/GeoJSON 文件只在本机解析。节点图片来自你主动选择的相册或拍照，只保存在本机。'
          '分享图在本机生成，经系统分享面板发送到你选择的应用。',
    ),
    ('分享与导出', '分享或导出线路时，其中可能包含住宅、常去出发点等敏感位置，请自行确认后再发送。'),
    ('安全提示', '天气提示来自公开预报模型，不是实测，也不能替代官方预警和你的户外安全判断。'),
    ('联系我们', '测试版问题与隐私疑问可在“设置 → 问题反馈”中复制诊断信息并提交。'),
  ];

  // 线路小地图
  static const miniMapLayers = '小地图图层';
  static const miniMapLayersHint = '只提供平面地形图层；完整图层在全屏地图里切换。';
  static const miniMapFollowSettings = '跟随地图设置';
  static const miniMapNeedsTiandituKey = '国内官方图源，需要天地图 Key：点此填写（Key 只保存在本机）';
  static const miniMapTiandituNote = '国内官方图源，山体晕渲显示起伏（天地图不提供等高线），自动叠加地形注记。';
  static const miniMapFit = '回到全线';
  static const miniMapGestureHint = '双指缩放、拖动；单指上下滑动页面';
  static const miniMapLayerFailed = '图源加载缓慢或连不上（国内网络常连不上海外图源）。';
  static const miniMapRevert = '切回';

  // 山脊天气带
  static const ridgeBandTitle = '海拔剖面与沿途天气';
  static const ridgeNoElevation = '无海拔数据';
  static const ridgeAfterSunset = '日落后';

  // 开屏
  static const splashSkip = '跳过动画';
  static const splashTagline = '出发前，看懂沿途天气';

  // 问题反馈
  static const feedbackTitle = '问题反馈';
  static const feedbackSubtitle = '复制诊断信息，到 GitHub 提交问题';
  static const feedbackIntro =
      '请描述你做了什么、看到了什么、期望是什么，最好附上截图或出问题的轨迹文件（注意其中的敏感位置）。'
      '下面的诊断信息不含位置、线路或 Key。';
  static const feedbackCopy = '复制诊断信息';
  static const feedbackCopied = '已复制诊断信息';
  static const feedbackOpenIssues = '去 GitHub 提交问题';
  static const feedbackIssuesNote = '提交 GitHub 问题需要登录 GitHub 账号；问题内容公开可见。';
  static const feedbackOpenFailed = '无法打开浏览器，链接已复制到剪贴板';
}
