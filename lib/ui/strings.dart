/// 集中管理的界面文案（默认中文）。
///
/// 国际化架构说明：所有面向用户的文案经由本文件常量引用，
/// 迁移到 ARB/gen-l10n 时只需把这些常量改为生成访问器，
/// 不需要改动业务代码（见 docs/architecture.md）。
abstract final class S {
  static String wxIntervalNote(String labels, String start, String end) =>
      '$labels：$start–$end；瞬时指标取标注整点，未做小时内插值。';
  static String wxPreviousThreeHourNote(
    String labels,
    String start,
    String end,
  ) => '$labels：前三小时 $start–$end，并非单小时概率。';
  static String wxUnknownIntervalNote(String labels) =>
      '$labels：来源标注小时的值，区间起止未确认，未作时间偏移。';
  static String wxOriginalTimes(String times) => '来源原始时次（UTC）：\n$times';
  static const wxTimeDetails = '时段说明';
  static String wxIntervalShort(String labels, String start, String end) =>
      '$labels：$start–$end';
  static String wxThreeHourShort(String labels, String start, String end) =>
      '$labels：前三小时 $start–$end';
  static String wxUnknownIntervalShort(String labels) => '$labels：区间起止未确认';

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
  static const legacyCatalogueElevationNote =
      '历史目录线路的海拔由路线剖面按距离线性插值得到，为估算值；高点位置与爬升量仅供参考。';
  static const longTripNote =
      '按当前配速估算全程超过 12 小时：行程模式按连续行走推算，未计入夜间宿营。'
      '多日线路的后段到达时间与对应天气仅供参考，请按每日行程分段查看。';
  static const multiSegmentNote =
      '此线路包含相距较远（超过 1 km）的断开段，沿途天气只分析首尾相接的最长部分；断开处不自动连线。';
  // 线路详情 v2：方向、起终点、节点联动、标记（docs/redesign-v2.md 第 1 步）
  static const save = '保存';
  static const onDemandQuery = '查询此点（消耗 1 次额度）';
  static const altitudeCardTitle = '同一地点不同海拔';
  static const altitudeExploreTitle = '海拔影响（模型估算）';
  static const altitudeCardNote = 'Open-Meteo 按海拔统计降尺度的模型估算，非实测；▶ 为当前节点/地面海拔。';
  static const airQualityTitle = '空气质量（雾霾）';
  static const phenomenonLabel = '天气现象';
  static const moreMetrics = '更多指标';
  static const shareImage = '分享图片';
  static const shareNeedsData = '天气数据加载完成后才能分享';
  static const probVsAmountNote = '概率与降水量来自不同模型，可能不一致';
  static const noHintsTriggered = '已覆盖数据未触发提示阈值，不代表安全。';
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
  static const meteogramTitle = '未来 24 小时';
  static const meteogramNoData = '此来源没有这一时段的逐时数据。';
  static const meteogramTemp = '气温';
  static const meteogramFeel = '体感';
  static const meteogramPrecip = '降水量';
  static const meteogramProb = '降水概率';
  static const meteogramGust = '风向（颜色看阵风）';
  static const signalsTitle = '需要留意';
  static const tierPrepare = '准备';
  static const tierReference = '参考';
  static const multiSourceCompare = '多来源对比';
  static const arrivalEstimate = '预计到达（估算）';
  static const fixedMoment = '选定时刻';
  static const tapAgainForDetail = '再点一次查看节点详情';
  static const offRouteWaypoint = '偏离线路超过 300 m，未计入沿途时间线';
  static const sharedGridNotePrefix = '网格说明';
  static const nearbyMarksPrefix = '附近';
  static const nearbyMarksTitle = '附近标记（不单独查询天气，按本节点预报）';
  static const nearbyMarkTooltip = '天气见最近的节点';
  static String nearbyOffset(double m) => m < 1000
      ? '相距约 ${(m / 10).round() * 10} m'
      : '相距约 ${(m / 1000).toStringAsFixed(1)} km';
  static const nearbyMarksNote =
      '打卡点、水源、补给点等普通标记挂在最近的节点上，不单独占一行，天气按该节点的预报；'
      '营地、垭口、险段、下撤点、休息点和设了停留时长的标记仍是独立节点。';
  static const foldedSameForecast = '预报同上';
  static const foldedNote = '标“预报同上”的节点与上方节点落在同一网格、同一小时，数据完全相同，默认折叠，点开可逐个查看。';
  static String foldedNodes(int n) => '另 $n 个节点';

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
          '打开等高线、地形阴影、手绘规划或 3D 地形预览时，会按瓦片坐标从 AWS（Terrain Tiles 开放数据）下载高程瓦片。'
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
  static String ridgeBandSemantics(
    int nodes,
    int flagged, {
    required bool hasElevation,
  }) =>
      '$ridgeBandTitle：$nodes 个节点，$flagged 个触发天气提示'
      '${hasElevation ? '' : '，$ridgeNoElevation'}';
  static String ridgeNodeN(int n) => '节点 $n';
  static String ridgeArrive(String eta) => '$eta 到达';

  // 开屏
  static const splashSkip = '跳过动画';
  static const splashTagline = '出发前，看懂沿途天气';

  // 手绘规划（T-189）
  static const plannerTerrain = '等高线与地形阴影';
  static const plannerHintEmpty = '轻触地图任意处开始徒步规划';
  static const plannerHintEdit = '拖动圆点调整位置，拖线段中间的小点插入新点';
  static const plannerElevLoading = '海拔加载中…';
  static const plannerElevUnavailable = '海拔数据暂不可用';
  static const plannerElevNote =
      '海拔为公开高程数据估算（SRTM，约 30 m 网格），取整到 10 m；爬升已滤掉 5 m 以内的起伏。';
  static const plannerDeletePoint = '删除此点';
  static const plannerPoint = '第';
  static const plannerPointSuffix = '点';
  static const plannerAbout = '约';
  static const plannerNoClimb = '未计爬升';
  static const plannerElevSource = '海拔：公开高程数据估算（SRTM，约 30 m）';
  static const plannerHours = '小时';
  static const plannerMinutes = '分';
  static const plannerMinutesOnly = '分钟';
  static const plannerElevRange = '海拔';
  static const plannerMore = '更多';

  // 地形图层（T-190）
  static const terrainSection = '地形';
  static const terrainContours = '等高线';
  static const terrainContoursNote =
      '由公开高程数据（SRTM，约 30 m 网格）在本机计算，等高距 25–200 m 随缩放变化，放大到 10 级以上显示；非测绘成果。';
  static const terrainHillshade = '地形阴影';
  static const terrainHillshadeNote = '压暗背光坡，一眼看出山形；可叠在任意底图上。';
  static const terrainIntervalPrefix = '等高距';
  static const terrainAttribution = '高程：Terrain Tiles（AWS 开放数据）· SRTM（USGS）';

  // 线路 3D 地形预览（T-191）
  static const route3dTitle = '3D 地形预览';
  static const route3dLoading = '高程加载中';
  static const route3dFailed = '高程数据没能加载（国内直连 AWS 有时较慢），稍后再试。';
  static const route3dRetry = '重试';
  static const route3dNoRoute = '这条线路没有坐标，无法生成 3D 地形。';
  static const route3dHint = '单指拖动：旋转、俯仰 · 双指：缩放、平移、扭转 · 双击：复位';
  static const route3dExLabel = '高程';
  static const route3dExNone = '高程未放大';
  static const route3dExPrefix = '高程放大 ×';
  static const route3dCompass = '转回朝北';
  static const route3dPartial = '部分区域缺少高程数据，空白处未绘制。';
  static String route3dNote(int spacingM) =>
      '地形由公开高程数据（SRTM，约 30 m 网格）在本机生成，网格间距约 $spacingM m；'
      '线路按地形贴地显示，被山体挡住的路段画成虚线。仅供看山形，非测绘成果。';

  // 问题反馈
  static const startupFailedTitle = '山晴没能启动';
  static const startupFailedBody =
      '读取本机设置时出错，App 无法继续。请复制下面的诊断信息，到 GitHub Issues 反馈；'
      '也可以先到 Releases 下载最新的测试版覆盖安装。';
  static const startupCopyDiagnostics = '复制诊断信息';
  static const startupCopied = '已复制';
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

  // 穿衣建议（洋葱法）
  static const layeringTitle = '穿衣建议';
  static String layeringSummary(List<String> items) => items.join(' · ');
  static String layeringWearForScene(String scene, List<String> items) =>
      '$scene穿：${layeringSummary(items)}';
  static String layeringCarry(List<String> items) =>
      '随身带：${items.isEmpty ? '未列出额外备装' : layeringSummary(items)}';
  static const layeringDetails = '调整与详情';
  static String layeringPreference(String preference) => '按$preference偏好';
  static const nodeWeatherTools = '更多天气与工具';
  static const layeringIncomplete = '部分条件未评估，查看依据';
  static const layeringNoData = '穿衣建议：此来源在选定时间没有气温，无法估计。';
  static const layeringBasis = '依据';
  static const layeringPacked = '背包';
  static const layeringSensitivity = '体感偏好';
  static const layeringColdy = '怕冷';
  static const layeringNormal = '适中';
  static const layeringWarmy = '怕热';
  static const layeringDisclaimer =
      '经验建议：按预报推算各段体感，不替代你对路况、海拔和自身状况的判断。'
      '“停留”指沿途最冷处（山顶、垭口、午饭、等人）；出发时略凉为宜，爬升十几分钟后就会热。';
  static const layeringShare = '穿衣';

  // 天气图（地图页）
  static const wxMapButton = '天气图';
  static const wxMapPrecip = '降水';
  static const wxMapCloud = '云量';
  static const wxMapSatellite = '卫星云图';
  static const wxMapTyphoon = '台风';
  static const wxMapCloudAll = '全部';
  static const wxMapCloudLow = '低云';
  static const wxMapCloudMid = '中云';
  static const wxMapCloudHigh = '高云';
  static const wxMapPlay = '播放';
  static const wxMapPause = '暂停';
  static const wxMapLoading = '正在获取天气图…';
  static const wxMapFailed = '天气图获取失败，稍后重试';
  static const wxMapZoomIn = '放大到省市范围查看';
  static const wxMapForecastNote = '模式预报 · Open-Meteo · 非雷达实况';
  static const wxMapPrecipUnit = '随后一小时降水 mm';
  static const wxMapCloudUnit = '云量 %';
  static const wxMapSatelliteNote = '红外云图（实况）· Himawari-9 · NASA GIBS';
  static const wxMapSatelliteTime = '观测';
  static const wxMapTyphoonNote = '日本气象厅（RSMC 东京）· 风速为 10 分钟平均 · 圆为 70% 概率圆';
  static const wxMapNoTyphoon = '日本气象厅目前没有发布西北太平洋与南海的热带气旋信息。';
  static const wxMapLocate = '定位';
  static const wxMapInfo =
      '降水、云量：Open-Meteo 模式预报，按网格点取值后在点间平滑显示，不是雷达或卫星实况；'
      '降水为标注整点起一小时累计，云量按标注整点。播放和拖动时，相邻两个整点（或两张云图）之间是线性过渡，'
      '只为画面连贯；停下后显示的是整点数据。卫星云图：日本 Himawari-9 红外通道，经 NASA GIBS 提供，'
      '颜色越亮越冷，代表云顶越高；约 10 分钟一张，有 20–40 分钟延迟。'
      '台风：日本气象厅（西北太平洋区域专业气象中心）实况与路径预报，风速为 10 分钟平均，'
      '与中央气象台的 2 分钟平均不同；虚线圆是中心落点的 70% 概率圆，不是风圈。';

  // 出发窗口
  static const departureVarTemp = '气温';
  static const departureVarGust = '阵风';
  static const departureVarPrecip = '小时降水';
  static const departurePastSnack = '该出发时刻已过去，请重新选择';
  static const departureExplainCompare =
      '比较日期 × 出发时刻的沿途天气。所有时间按设备时区显示，跨时区出行请核对。';
  static const departureExplainSlots = '每隔 2 小时比较一次，最多 5 个出发时刻；可左右滑动表格。';
  static const departureExplainColors =
      '颜色只表示阈值结果，不代表安全等级。灰色为信息不足；红/黄也可能同时缺数据。官方预警未接入；日出未接入，未核验全程是否处于白昼。';
  static String departureExplainThresholds(
    double gustYellow,
    double gustRed,
    double precipYellow,
    double coldRed,
  ) =>
      '按阈值：阵风 ≥$gustYellow/$gustRed m/s（黄/红）；小时降水 ≥$precipYellow mm（黄）；气温 ≤$coldRed℃（红）；预计到达晚于日落（黄）。';
  static const departureExplainMethod =
      '计算方法：按配速、爬升/下降、休息与航点停留估算 ETA；逐段检查经过小时的两个采样端点，属于保守的时空近似，不是实时实测。点开格子可查看原因、缺口和各节点时次。';
  static String departureSingleSource(String model, int horizonDays) =>
      '单一来源 · $model · 最远约 $horizonDays 天，以实际返回覆盖为准。';
  static const departureTitle = '出发窗口';
  static const departureRulesTitle = '规则与数据说明';
  static const departureRefreshTooltip = '刷新出发窗口';
  static const departureDemoPrefix = '演示 · ';
  static const departureForward = '正向行走';
  static String departureDirectionDuration(String direction, String hours) =>
      '$direction · 全程约 $hours 小时（估算）';
  static String departureFromDate(String date) => '从 $date 起';
  static String departureDays(int n) => '$n 天';
  static String departureFirstSlot(String time) => '首个时刻 $time';
  static const departureUnsupported =
      '当前线路缺少节点或预计连续行走超过 24 小时。请先导入单日线路；多日拆分尚未完成。';
  static const departureNoSource = '没有可用于比较的来源。请在设置中启用可自动查询的天气来源。';
  static const departureLoadingSemantics = '正在获取出发窗口天气';
  static const departureFetchError = '天气请求失败或超出来源预报范围。请调整日期或来源后重试。';
  static const departureRetry = '重试出发窗口';
  static const departureLegend = '✓ 未触发　风 阵风　雨 降水　冷 低温　晚 晚于日落　缺 信息不足　点格子看依据';
  static const departureStale = '旧缓存';
  static const departureCached = '已缓存预报';
  static const departureFetched = '已获取预报';
  static String departureFetchedAt(String state, String stamp) =>
      '$state · 获取于 $stamp';
  static const departureRefreshFailed = '刷新失败，保留上次数据及其真实获取时间。';
  static const departureAdjustThresholds = '调整出发阈值';
  static const departureSunsetNote =
      '· 日落采用来源提供的终点日落，按终点经度近似归属出发日期；不使用手机所在日期推算线路日落。未考虑山体遮挡，未核验日出和极昼/极夜。';
  static const departureShareTitle = '分享出发窗口';
  static String departureShareText(String routeName) =>
      '$routeName · 出发窗口对比 · 山晴徒步天气';
  static String departureShareThresholds(
    double gustYellow,
    double gustRed,
    double precipYellow,
    double coldRed,
  ) =>
      '阈值：阵风 ≥$gustYellow/$gustRed m/s（黄/红），小时降水 ≥$precipYellow mm（黄），气温 ≤$coldRed℃（红），晚于日落（黄）。';
  static const today = '今天';
  static const tomorrow = '明天';
  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  /// [weekday] 为 DateTime.weekday（1 = 周一）。
  static String departureWeekday(int weekday) => '周${_weekdays[weekday - 1]}';
  static const departureGlyphPast = '过';
  static const departureTipPast = '已过去';
  static const departureGlyphMissing = '缺';
  static const departureTipInsufficient = '信息不足';
  static const departureGlyphWind = '风';
  static const departureGlyphRain = '雨';
  static const departureGlyphCold = '冷';
  static const departureGlyphLate = '晚';
  static String departureCellSemantics(
    String start,
    String label,
    String finish,
  ) => '$start 出发，$label，预计 $finish 到达';
  static String departureCellTooltip(String label, String finish) =>
      '$label · 约 $finish 到达';
  static const departureEvidenceTitle = '出发依据';
  static String departureEvidenceTimes(String start, String finish) =>
      '出发 $start\n预计到达 $finish（估算；设备时区）';
  static String departureEvidenceSource(String providerId, String stamp) =>
      '来源 $providerId · 获取 $stamp';
  static const departurePast = '该出发时刻已过去';
  static const departureUseThis = '用这个时间查看行程';
  static String departureNodePassHour(String node, String stamp) =>
      '$node\n经过小时 $stamp';
  static String departureRawValidTime(String stamp) => '原始有效时次 $stamp';
  static String departureModel(String model) => '模型 $model';
  static String departureModelUnknown(String model) => '未知（$model）';
  static String departureSunset(String stamp) => '终点日落 $stamp（日期归属近似）';
  static const departureNoFindings = '已提供的数据没有触发当前阈值；这不是安全保证。';
  static String departureGap(String gap) => '信息不足 · $gap';
  static String departureMissing(String name, int n) =>
      '$name：$n 个节点小时缺失，此来源未提供';
  static String departureSampleSummary(int complete, int total) =>
      '完整天气采样 $complete/$total 个采样（逐小时气温/阵风/降水，整点抵达另核对气温）；共享查询点不算独立证据。';
  static const departureNodesTitle = '各节点与原始时次';
  static const departureOpenMeteoNote =
      'Open-Meteo：小时降水和阵风使用该小时结束时的记录；气温使用小时起点的瞬时值。下面保留每项原始有效时次。';
  static String departureNodeEta(String stamp) => '预计到达 $stamp（估算）';
  static const departureArrivalHour = '抵达整点';
  static const departurePassingHour = '经过小时';
  static String departureSampleLine(String name, String value, String stamp) =>
      '$name：$value · 原始时次 $stamp';
  static const departureFootnote =
      '预报不是实测；采样、ETA 与日期归属均有近似。日出和官方预警未接入，仍需核对现场与官方信息。';
  // 会员付费墙
  static const paywallPurchaseSuccess = '🎉 恭喜！您已成功解锁 山晴 Pro 专业会员全量特权！';
  static const paywallRestoreSuccess = '已成功恢复 Pro 会员权益！';
  static const paywallRestoreNotFound = '未查询到有效的 Pro 会员订单记录';
  static const paywallTitle = '山晴 Pro';
  static const paywallRestore = '恢复购买';
  static const paywallHeadline = '专业户外微气候推演';
  static String paywallSourceFeature(String feature) =>
      '当前操作涉及 Pro 专享权益：【$feature】';
  static const paywallPlanIntro = '以下为 Pro 方案规划，标注“开发中”的功能尚未上线';
  static const paywallBenefitsTitle = 'Pro 权益规划';
  static const paywallInDevelopment = '开发中';
  static const paywallChoosePlan = '选择适合你的订阅方案';
  static const paywallAlreadyPro = '已是 Pro 专业会员';
  static const paywallBillingUnavailable = '支付未接入，暂不可开通';
  static const paywallCtaYearly = '立即开始 7 天免费试用（试用后 ¥98/年）';
  static const paywallCtaMonthly = '立即开通月度会员（¥18/月）';
  static const paywallCtaLifetime = '一次性购买终身会员（¥198）';
  static const paywallLifetimeNote = '终身买断一次性付费，尊享后续算法升级，无需续费。';
  static const paywallSubscriptionNote = '试用期内可随时在应用商店或设置中取消，不产生扣费。自动续订，可随时取消。';
  static const paywallContinueFree = '返回，继续免费使用';
  // 首次引导
  static const onboardingHeadline = '出发前，看懂沿途天气';
  static const onboardingIntro = '导入一条徒步线路，按出发时间查看沿途预报。\n不需要注册账号，也可以先从示例线路开始。';
  static const onboardingStepRouteTitle = '带上你的线路';
  static const onboardingStepRouteBody = '支持 GPX、KML、KMZ 和 GeoJSON，也可以在地图上手绘。';
  static const onboardingStepTimeTitle = '选择出发时间';
  static const onboardingStepTimeBody = '查看同一时刻的天气，或结合配速估算沿途到达时间。';
  static const onboardingStepSourceTitle = '核对来源与更新时间';
  static const onboardingStepSourceBody = '预报不是实测；缺失数据和超出预报范围的时段会明确说明。';
  static const onboardingOfflineNote =
      '出发前可在线下载线路与预报，再从首页打开离线行程包。离线底图尚未提供，请另备地图。';
  static const onboardingImportMine = '导入我的线路';
  static const onboardingTryExamples = '先看示例线路';
  // 行程首页
  static String tripsDeleteTitle(String name) => '删除“$name”？';
  static const tripsOfflineTitle = '离线行程包';
  static const tripsOfflineSubtitle = '查看已保存的线路与预报';
  // 启动失败页
  static String startupDiagnostics(String version, String error) =>
      '版本：$version\n错误：$error';
  // 地图页
  static const mapPlaceSearchFailed = '地点候选加载失败；仍可使用本地线路或导入轨迹。';
  static String mapPlaceRoutesFound(String place, int n) =>
      '已在 $place 附近找到 $n 条可直接分析的线路。';
  static const mapLocateFailed = '定位失败。你仍可手动点选地图查询天气。';
  static const mapWxStaleSuffix = ' · 旧预报';
  static const mapWxRefreshingSuffix = ' · 更新中';
  static const mapWxRefreshFailedSuffix = ' · 更新失败';
  static String mapOsmRoutesLoaded(int n) => '已加载 $n 条 OSM 线路。';
  static const mapLoopStartEnd = '起终';
  static String mapMonthDay(int month, int day) => '$month月$day日';
  static String mapTyphoonForecastTag(int day, int hour) => '$day日$hour时';
  static const dayAfterTomorrow = '后天';
  static const yesterday = '昨天';
  // 地图页：混合搜索
  static const mapSearchRoutesSubtitle = '有完整几何，可直接进入沿途天气分析';
  static const mapSearchPlacesSubtitle = '先定位到区域，再查附近 OSM 线路';
  static const mapSearchPlannerTitle = '线路规划工坊 (Trail Studio)';
  static const mapSearchPlannerSubtitle = '在地图上手绘规划、标记营地水源、即时推演天气与耗时';
  // 地图页：自定义图源
  static const mapTileNameRequired = '请填写名称';
  static const mapTileZoomInvalid = '最大缩放级别需为 1–22';
  static const mapCustomTileNote = '用户自定义图源：可用性与授权由使用者自行确认。';
  static const mapTileName = '名称';
  static const mapTileUrlTemplate = 'URL 模板';
  static const mapTileSubdomains = '子域名（可选，逗号分隔）';
  static const mapTileMaxZoom = '最大原生缩放级别';
  static const mapTileAttribution = '署名（地图角标显示）';
  static const mapTileDatum = '坐标系';
  // 地图页：点位天气
  static String pointWxCoordsAndTime(String lat, String lon, String time) =>
      'WGS-84 $lat, $lon · 查询时刻 $time';
  static String pointWxLocationReadAt(String time) =>
      '位置读取于 $time · 天气按该坐标查询，移动后请重新定位';
  static const pointWxGridNote =
      '这里展示的是所选坐标附近的网格预报，不是该点实测。'
      '各来源独立显示，返回坐标、网格颗粒度和缺失项以来源说明为准。';
  static String pointWxSourceFailed(String source) => '$source 请求失败';
  static const pointWxNoLocationData = '该来源未返回此位置数据';
  static const pointWxNoPeriodData = '该来源未返回当前时段数据';
  static String pointWxValidTime(String time) => '有效时次 $time';
  static String pointWxMinutesOff(int minutes) => ' · 相差 $minutes 分钟';
  // 地图页：天气图
  static String wxMapGridSpacing(int km) => ' · 格点约 $km km';
  static String wxMapTyphoonMaxWind(int ms) => '最大风速 $ms m/s';
  static String wxMapTyphoonHeading(String course) => '向$course';
  static String wxMapTyphoonIssued(String time) => '发布 $time';
  static const wxMapSatelliteLegend = '暗 = 地面或低云　亮/彩 = 云顶高、对流强';

  // 离线行程包
  static const offlineCoverageComplete = '所选时段均有数据';
  static String offlineCoverageMissing(int n) => '覆盖不全：缺少 $n 个节点小时';
  static String offlineCoverageText(String time, int core, int expected) =>
      '$time\n温度、降水量和持续风速均有值：$core/$expected 个节点小时。'
      '缺失指标仍显示“此来源未提供”。';
  static const offlineScope =
      '保存线路、航点、行程设置及此来源返回的预报。离线预报不会自动更新。'
      '不含地图底图、节点照片和实时定位导航；官方预警未接入。';
  static const offlineDownloadTitle = '下载离线行程包';
  static String offlineWeatherSource(String name) => '天气来源：$name';
  static String offlineDirectionNodes(bool reversed, int n) =>
      '行走方向：${reversed ? '反向' : '原方向'} · $n 个采样节点';
  static const offlineRequestRange = '请求预报时段（设备时区）';
  static String offlineHours(int h) => '$h 小时';
  static String offlineRangeText(String start, String end) =>
      '$start 至 $end（不含结束时刻）';
  static const offlineCoverageNote = '实际覆盖取决于来源；会保留来源返回的全部时次，并核对所选时段。';
  static String offlineOutsideSelected(int n) => '$n 个计划到达时刻超出所选时段，请增加时长或调整行程。';
  static const offlineWebNote =
      'Web 仅供工程验证：受浏览器配额限制，清除站点数据会删除离线包；此功能不保证网页断网冷启动。';
  static const offlineSourceUnsupported =
      '此来源暂未开放离线下载。请返回选择 Open-Meteo 或 MET Norway；按次计费来源不批量请求。';
  static const offlineDownloading = '正在获取、校验并保存…';
  static const offlineDownload = '下载并校验';
  static const offlineRedownload = '重新下载';
  static const offlineDeleteTitle = '删除离线包？';
  static String offlineDeleteBody(String name) => '将删除“$name”的离线副本。收藏和导入线路仍保留。';
  static const offlineUnreadableName = '无法读取的离线包';
  static const offlineDeleteFailed = '删除失败，请稍后重试';
  static const offlineTripsTitle = '离线行程包';
  static const offlineListLoadFailed = '无法读取本机离线包，点击重试';
  static const offlineListNote =
      '从本机读取，不请求天气或地图。出发前请联网更新，再关闭网络检查所需时段。卸载 App 会删除本机副本。';
  static const offlineListEmpty = '还没有离线包。打开任意线路，点击右上角的离线下载按钮。';
  static const offlineEntryUnreadable = '离线包无法读取';
  static String offlineEntrySubtitle({
    required bool demo,
    required String source,
    required int hours,
    required bool complete,
    required String fetched,
  }) =>
      '${demo ? '演示线路 · ' : ''}$source\n'
      '请求 $hours 小时 · ${complete ? '时段均有数据' : '覆盖不全'}\n'
      '获取于 $fetched';
  static const offlineDeleteTooltip = '删除离线包';
  static const offlineUpdated = '新预报已校验并保存，请检查覆盖情况。';
  static String offlineUpdateFailed(String error) => '$error\n原有离线包仍可查看。';
  static const offlineViewTitle = '离线查看';
  static const offlineTripLoadFailed = '离线包校验失败或无法读取。请返回列表检查存储空间，并从原线路重新下载。';
  static const offlineTripMissing = '离线包不存在，请返回列表重新选择。';
  static const offlineReadingNote = '正在读取本机保存的预报，不代表实时观测；仅点击“联网更新”才请求新预报。';
  static const offlineWindowEnded = '所选行程时段已结束。此包仅供回看，请为下一次行程重新下载。';
  static const offlineNeedsUpdate = '旧预报：已超过来源建议的更新间隔，联网后请更新。断网时无法得知后续天气变化。';
  static String offlineTripMeta(String source, String fetched, String saved) =>
      '来源：$source\n预报获取于 $fetched\n离线包保存于 $saved';
  static String offlineOutsideRequested(int n) =>
      '$n 个计划到达时刻超出请求时段；是否有数据以每个节点为准。';
  static const offlineUpdating = '正在更新，旧包仍可查看…';
  static const offlineUpdate = '联网更新此包';
  static const offlineViewTime = '查看天气时刻（设备时区）';
  static const offlineUsePlan = '按计划的预计到达时刻查看';
  static const offlineUsePlanNote = '到达时间为下载时的估算，未跟随实时位置变化';
  static const offlinePrevHour = '前一小时';
  static const offlineNextHour = '后一小时';
  static String offlineNodeTime(bool plan, String time) =>
      '${plan ? '预计到达（估算）' : '数据有效时刻'}：$time';
  static const offlineHourMissing = '此来源未提供该时次预报，不能判断天气。';
  static const offlineViewProvenance = '查看此节点的数据来源';
  static const offlineSavedSettings = '已保存的线路与行程设置';
  static String offlineSavedPlan(bool reversed, bool trip, String time) =>
      '行走方向：${reversed ? '反向' : '原方向'}\n'
      '${trip ? '计划出发' : '选定时刻'}：$time';
  static const offlinePartialPath = '天气节点与预计到达仅覆盖最长连续路径；其余轨迹段已保存。';
  static String offlineStopMinutes(int minutes) => ' · 停留 $minutes 分钟';
  static String offlineRouteSource(String source, String? license) =>
      '线路来源：$source\n授权说明：${license ?? '未提供'}';
  static const offlineDownloadFailed =
      '下载或保存失败。请检查网络、来源配置和剩余空间，然后重试；未将此次失败标记为离线就绪。';
  // 线路示意图
  static const offlineSchematicTitle = '线路示意图 · 北向上 · 无底图，不能用于定位导航';
  static String offlineSchematicLabel(String name, int segments) =>
      '$name的已保存轨迹，共$segments段；空心点为起点，实心点为终点';
  // 出发窗口阈值
  static const departureThresholdInvalid =
      '黄色阵风须小于红色阵风；阵风范围 >0–100，降水 >0–200，气温 −80–10。';
  static const departureThresholdSaveFailed = '设置未能保存，请重试';
  static const departureThresholdTitle = '出发窗口阈值';
  static const departureThresholdIntro =
      '这些规则只用于出发窗口比较。颜色表示触发阈值，不代表安全等级。单位固定如下，不随显示单位变化。';
  static const departureThresholdGustYellow = '黄色 · 阵风 ≥（m/s）';
  static const departureThresholdGustRed = '红色 · 阵风 ≥（m/s）';
  static const departureThresholdPrecipYellow = '黄色 · 小时降水 ≥（mm）';
  static const departureThresholdColdRed = '红色 · 气温 ≤（℃）';
  static const departureThresholdInvalidNumber = '请输入有效数字';
  static const departureThresholdRulesNote =
      '预计到达晚于出发日日落：黄色。缺少气温、阵风、降水或日落：信息不足。缺失值不会用 0 或其他变量代替。';
  static const departureThresholdSaving = '保存中…';
  static const departureThresholdSave = '保存阈值';
  static const departureThresholdReset = '恢复默认值（保存后生效）';
  // 导入线路
  static const importTypeTrack = '轨迹文件';
  static const importTypeAll = '所有文件';
  static String importPickerFailed(String error) => '无法打开文件选择器：$error';
  static String importFailedDetail(String error) => '导入失败：$error';
  static const importParsing = '正在解析…';
  static const importPickFile = '选择 GPX / KML / KMZ / GeoJSON 文件';
  static const importFormatsHelp =
      '支持标准 GPX、KML/KMZ（奥维互动地图/两步路/Google Earth）与 GeoJSON，按文件内容自动识别格式。'
      '单文件上限 30MB，超长轨迹自动平滑抽稀保留峰顶与关键地形特征，异常漂移点自动过滤。纯本地解析，不上传云端。';
  static const importPasteLabel = '或粘贴内容：';
  static const importPasteHint = '<gpx …> 或 {"type": "FeatureCollection", …}';
  static const importParseAndImport = '解析并导入';
  static const importFailed = '导入失败';
  static String importConfirmTitle(String name) => '导入：$name';
  static String importConfirmSummary({
    required int segments,
    required int points,
    required String lengthKm,
    required String ascent,
    required List<String> warnings,
  }) =>
      '段数：$segments\n'
      '总点数：$points\n'
      '长度：约 $lengthKm km\n'
      '累计爬升：$ascent\n'
      '${warnings.isEmpty ? '' : '\n${warnings.map((w) => '· $w').join('\n')}\n'}\n'
      '$importPrivacyNote';
  // “用山晴打开”传入文件
  static String importIncomingParsing(String name) => '正在解析 $name…';
  static String importIncomingFailed(String name, String error) =>
      '无法导入 $name：$error';
  static String importIncomingReadFailed(String name, String error) =>
      '无法读取 $name：$error';
  // 设置
  static const settingsConfigured = '已配置';
  static const settingsNotConfigured = '未配置';
  static const settingsDisplaySection = '显示与使用';
  static const settingsImperial = '英制单位';
  static const settingsImperialHint = '温度 °F、距离 mi、降水 in';
  static const settingsWindUnit = '风速单位';
  static const settingsTheme = '主题';
  static const settingsThemeSystem = '系统';
  static const settingsThemeLight = '浅色';
  static const settingsThemeDark = '深色';
  static const settingsThresholdHint = '调整阵风、小时降水和低温规则';
  static const settingsLowPower = '低耗电模式';
  static const settingsLowPowerHint =
      '加大采样间距，并把常规节点上限设为 12（关键航点仍保留）。前台仍检查天气时效，不在后台轮询。';
  static String settingsSamplingSpacing(String km) => '采样间距：$km km';
  static const settingsSamplingSpacingHint = '线路天气节点的采样间距（工程参数，不代表天气空间分辨率）';
  static String settingsOverlayCount(int n) => ' + $n 个叠加层';
  static const settingsSourcesSection = '天气来源与密钥';
  static String settingsProviderSubtitle(
    String vendor,
    String coverage,
    int horizonDays,
    bool requiresKey,
  ) =>
      '$vendor · 覆盖 $coverage · 预报 $horizonDays 天 · ${requiresKey ? '需密钥' : '无需密钥'}';
  static const settingsCapabilities = '来源能力与授权对照';
  static const settingsApiKeys = '数据源密钥';
  static String settingsApiKeysStatus(bool qweather, bool meteoblue) =>
      '和风：${qweather ? settingsConfigured : settingsNotConfigured} · '
      'meteoblue：${meteoblue ? settingsConfigured : settingsNotConfigured}';
  static const settingsDataSection = '数据与帮助';
  static const settingsGuide = '查看使用指引';
  static const settingsGuideHint = '导入线路、选择出发时间、核对天气来源';
  static const settingsAttribution = '数据授权与署名';
  static const settingsExport = '导出我的线路数据';
  static const settingsExportHint = '收藏与导入线路导出为 JSON 文本（本地操作，不上传）';
  static const settingsExportDone = '导出数据（已复制到剪贴板）';
  static String settingsCapabilityDetails({
    required String vendor,
    required String model,
    required String coverage,
    required int horizonDays,
    required int intervalHours,
    required String? resolution,
    required String browserNotes,
    required String license,
    required String attribution,
  }) =>
      '服务商：$vendor\n模型：$model\n覆盖：$coverage\n'
      '时效：$horizonDays 天 · 间隔 $intervalHours h\n'
      '空间分辨率：${resolution ?? '来源未提供'}\n'
      'Web 端：$browserNotes\n授权：$license\n署名：$attribution';
  static const settingsAttributionBody =
      '地图瓦片：默认 © 高德地图；可切换 © OpenStreetMap 贡献者。仅在线显示，不预下载。\n\n'
      '徒步线路与具名路径段（OSM）：© OpenStreetMap 贡献者，ODbL 1.0。线路几何来自 Overpass API 按视野查询；路径段不冒充完整路线，App 展示不构成对路线可通行性或许可进入的担保。\n\n'
      '天气：Open-Meteo（CC BY 4.0，非商业免费额度；模型来自 NOAA 等机构）；MET Norway Locationforecast 2.0（NLOD 2.0 / CC BY 4.0）。\n\n'
      '地点搜索：Open-Meteo Geocoding（GeoNames/知识共享数据）。\n\n'
      '内置示例线路为本项目演示数据（已标注“演示”），非实测。\n\n'
      '完整对照表与条款链接见 docs/data-sources.md。';
  static const settingsQweatherTitle = '和风天气（大陆直连推荐）';
  static const settingsQweatherHelp =
      '在 dev.qweather.com 控制台查看已开通服务的 API Key 与 API Host'
      '（新账号为专属域名，形如 abc123.qweatherapi.com；旧账号可用 devapi.qweather.com）。'
      '密钥仅保存在本机。未配置时该来源会显示配置指引，其余来源不受影响。';
  static const settingsCacheRoutes = '线路数据';
  static const settingsCacheMap = '地图/区域查询';
  static const settingsCacheWeather = '天气数据';
  static const settingsCacheUser = '用户数据';
  static String settingsCacheEntry(String? name, int count, String kb) =>
      '$name（$count 条 · $kb KB）';
  static const settingsCacheClear = '清除';
  // meteoblue 密钥卡
  static const meteoblueTitle = 'meteoblue（逐点海拔，按次计费）';
  static const meteoblueHelp =
      '在 meteoblue 账户的 Weather API 页面获取 key。每次查询约 8000 credits'
      '（免费版 1 年 1000 万 ≈ 1,250 次），所以只在节点详情“多来源对比”或地图选点里'
      '点“查询此点”时才请求，按节点海拔计算；3 小时内重复查询同一点使用缓存。'
      '密钥仅保存在本机。';
  static String meteoblueUsage(int calls, String tenThousands) =>
      '本机已发起 $calls 次请求（约 $tenThousands 万 credits）；'
      '剩余额度以 meteoblue 后台为准。';
  // 反馈诊断信息
  static const feedbackDiagBuild = '$appTitle 测试版';
  static String feedbackDiagVersion(String version) => '版本：$version';
  static String feedbackDiagDownload(String url) => '下载：$url';
  static String feedbackDiagPlatform(String os) => '平台：$os';
  static String feedbackDiagSources(String ids) => '天气来源：$ids';
  static String feedbackDiagBasemap(String id) => '底图：$id';
  static String feedbackDiagLowPower(bool on) => '低耗电：${on ? '开' : '关'}';
  static String feedbackDiagLapseRate(bool on) => '海拔订正：${on ? '开' : '关'}';
  static String feedbackDiagQweather(bool configured) =>
      '和风天气 Key：${configured ? settingsConfigured : settingsNotConfigured}';
  // 通用组件：缓存提示与请求错误
  static String wxCacheMonthDay(int month, int day) => '$month月$day日';
  static String wxCacheFetched(bool stale, String fetched) =>
      '${stale ? '旧预报' : '已保存的预报'} · 获取于 $fetched';
  static const wxCacheRefreshing = '正在更新，先显示已保存的数据。';
  static const wxCacheRefreshFailed = '更新失败，继续显示已保存的数据，请稍后重试。';
  static const wxCachePartial = '部分时段未覆盖；缺失时段显示“此来源未提供”。';
  static const wxCacheStale = '已超过来源建议的缓存时效，请勿当作刚更新的天气。';
  static const wxCacheRetry = '重新更新';
  static String staleBannerText(int mins) =>
      '$staleData（$cachedAt $mins 分钟前）：已超过来源建议的缓存时效。';
  static const fetchErrorNetwork = '网络不可用或连接超时';
  static String fetchErrorHttp(String code) => '来源返回错误（HTTP $code）';
  static const fetchErrorCancelled = '请求已取消';
  static const fetchErrorFailed = '请求失败';
  static String fetchErrorSource(String message) => '来源返回错误（$message）';
  static const fetchErrorFormat = '响应格式无法识别';

  // 手绘规划
  static const plannerTitle = '线路规划工坊';
  static const plannerUndo = '撤销';
  static const plannerReverse = '反向走法（反穿）';
  static const plannerExportMenu = '导出 GPX / KML';
  static const plannerClearMenu = '清空重画';
  static const plannerModeDraw = '打点画线';
  static const plannerModeWaypoint = '标记营地/水源';
  static const plannerFinish = '完成并查天气';
  static String plannerCounts(int points, int waypoints) =>
      ' · $points 点 / $waypoints 航点';
  static const plannerReversed = '路线方向已反转（反穿规划）';
  static const plannerClearTitle = '清空当前规划？';
  static const plannerClearBody = '此操作将清除已绘制的全部轨迹点与航点。';
  static const plannerClear = '清空';
  static const plannerLocateFailed = '定位失败，可以继续在地图上打点。';
  static String plannerWaypointDefaultName(int n) => '航点 $n';
  static const plannerAddWaypointTitle = '添加关键航点 (POI)';
  static const plannerWaypointNameLabel = '航点名称（如：一线天、白家营地）';
  static const plannerWaypointTypeLabel = '航点类型';
  static const plannerWaypointDescLabel = '备注（如：可扎营3顶帐篷、有流动山泉）';
  static const plannerAdd = '添加';
  static String plannerWaypointAdded(String name, String type) =>
      '已添加：$name（$type）';
  static const plannerNeedTwoPoints = '规划轨迹至少需要连接 2 个点';
  static String plannerDefaultRouteName(int month, int day) =>
      '手绘规划线路 $month月$day日';
  static const plannerSaveTitle = '保存手绘路线并查看天气';
  static const plannerRouteNameLabel = '线路名称';
  static const plannerDescLabel = '备注说明（可选）';
  static String plannerSaveSummary({
    required String distKm,
    required int? ascentM,
    required int waypoints,
    required String duration,
  }) =>
      '总里程：$distKm km\n'
      '${ascentM == null ? '' : '累计爬升：$plannerAbout $ascentM m\n'}'
      '航点数：$waypoints 个\n'
      '预计徒步耗时：$duration';
  static const plannerSaveAndForecast = '保存并推演天气';
  static const plannerUntitledRoute = '手绘规划线路';
  static const plannerSourceName = '用户手绘规划（Trail Studio）';
  static const plannerSourceNameWithElev =
      '$plannerSourceName· $plannerElevSource';
  static const plannerExportSourceName = '用户规划';
  static const plannerNeedTwoPointsExport = '至少需要 2 个轨迹点才能导出';
  static const plannerExportTitle = '导出规划轨迹';
  static const plannerExportNote = '可导出为标准 GPX 或 KML 格式，在两步路、奥维互动地图或户外手表中加载：';
  static const plannerCopyGpx = '复制 GPX 内容到剪贴板';
  static const plannerGpxCopied = 'GPX 文本已复制到剪贴板！可直接粘贴保存为 .gpx 文件使用';
  static const plannerCopyKml = '复制 KML 内容到剪贴板（奥维/两步路推荐）';
  static const plannerKmlCopied = 'KML 文本已复制到剪贴板！可直接粘贴保存为 .kml 文件使用';
  // 线路详情：控制条与时间设置
  static String detailDirection({required bool reversed}) =>
      '$startPoint（绿）→ $endPoint（红）${reversed ? ' · 已反向' : ''}';
  static const detailRestoreDirection = '恢复原方向';
  static const detailHourLabel = '时刻';
  static String detailHourSliderLabel(String hh) => '$hh:00（本地时区）';
  static String detailPaceSummary(
    double speedKmh,
    double ascentMinPer100m,
    int restMin,
  ) => '速度 $speedKmh km/h · 上升 $ascentMinPer100m min/100m · 休息 $restMin min';
  static String detailPaceSpeed(String kmh) => '平地速度：$kmh km/h';
  static String detailPaceAscent(String min) => '每上升 100 m 加时：$min 分钟';
  static String detailPaceRest(int min) => '全程休息：$min 分钟';
  static const detailTimeAndPace = '设置时间与配速';
  // 线路详情：小地图
  static String detailMapRecommended(String name) => '$name（推荐）';
  static String detailMapOverseas(String name) => '$name（海外图源）';
  static String detailNodeFallback(int n) => '节点 $n';
  // 线路详情：摘要、节点与来源
  static String detailSummaryNoData(int withData, int total) =>
      '当前选定时间与来源没有可用数据（$withData/$total 节点有数据）。信息不足时无法给出摘要。';
  static const detailMinMaxTemp = '最低/最高温';
  static const detailMaxGust = '最大阵风';
  static const detailTripPrecip = '行程降水';
  static const detailHourPrecip = '该时次降水';
  static const detailCompareDepartures = '比较出发窗口';
  static String detailMoreHints(int n) => '  等 $n 项提示';
  static String detailStopMinutes(int min) => '停留 $min 分钟';
  static const detailNoResolution = '来源未提供空间分辨率，位置颗粒度未确认';
  static String detailModelRunLine(String time) => '\n起报/发布：$time UTC';
  static String detailSourceElevLine(String m) =>
      '\n来源使用海拔（模型地形）：$m m；轨迹海拔见各节点（两者是不同数据）';
  static const detailFullProvenance = '查看完整溯源信息';
  // 线路详情：页面
  static const detailDownloadOffline = '下载离线行程包';
  static const detailLoadingWeather = '正在获取线路天气';
  static String detailShareText(String routeName, String timeLabel) =>
      '$routeName · $timeLabel · 山晴徒步天气';
  static String detailDayHead(int month, int day) => '$month月$day日全天';
  static String detailDayNoPrecip(String head) => '$head：此来源未提供降水量。';
  static String detailDayPartial(int hours) => '（来源仅覆盖 $hours 小时）';
  static String detailDayMaxProb(String pct) => '，最大概率 $pct%';
  static String detailDayDry(String head, String prob, String partial) =>
      '$head：沿途预报无明显降水（每小时 <0.1 mm）$prob$partial';
  static String detailDayWet({
    required String head,
    required String amount,
    required String from,
    required String to,
    required String prob,
    required String partial,
  }) => '$head：沿途降水最多约 $amount，主要在 $from–$to 时$prob$partial';
  static String detailChipTrip(String t) => '出发 $t';
  static String detailChipFixed(String t) => '固定 $t';
  static String detailModeFixed(String hhmm) => '全线同一时刻 $hhmm · 非预计到达';
  static String detailModeTrip(String start, String end) =>
      '$start 出发 → 约 $end 到达（配速估算）';
  static const detailSwitchToTrip = '按出发时间看';
  static String detailHintBasis(String basis) => '依据：$basis';
  static String detailSourceFailed(String source) => '来源请求失败（$source）';
  static String detailSourceFailedDetail(String error) =>
      '$error\n数据未获取，以下显示为空，不会用历史值冒充。';
  static const detailSunsetNote = '日落按终点经度近似归属出发日期；未计山体遮挡，日出未接入。';
  static const detailSunsetMissing = '日落：此来源未提供出发日终点日落。日出未接入。';
  static const detailTimeZoneNote = '时间按设备时区显示。';
  // 节点详情
  static const nodePrevious = '上一个节点';
  static const nodeNext = '下一个节点';
  static String nodeDistFromStartKm(String km) => '距起点 $km km';
  static const nodeNoDataAtTime = '此来源在该时刻没有数据（超出预报范围或来源未提供）。';
  static String nodeLocalTime(int month, int day, String hhmm) =>
      '$month月$day日 $hhmm';
  // 节点详情：不同海拔与空气质量
  static String envFetchFailed(String reason) => '暂时无法获取：$reason';
  static String envFreezingLevel(String m) => '0℃ 层约 $m m。';
  static String envGust(String wind) => '阵风 $wind';
  static const envAqiOutOfRange = '该时刻不在空气质量预报范围（约 5 天）。';
  static String envAqiValue(String aqi, String category) =>
      'AQI $aqi（$category，美国标准）';
  static String envAqiNote(String attribution) =>
      '$attribution。近地面浓度；山脊若在逆温层之上，实际空气可能明显好于此值。';
  // 节点多来源对比
  static const compareNodeFallback = '节点';
  static String compareValidTime({
    required String utc,
    required String local,
    required bool tripMode,
  }) =>
      '$validTime：$utc UTC（$local 本地）'
      '${tripMode ? '（行程模式：$eta，估算）' : ''}';
  static String compareSourceFailed(String error) => '该来源请求失败：$error';
  static const compareNoPointData = '该来源未返回此位置数据';
  static String compareSourceRange(String range) =>
      '该来源的时间范围：$range。$outOfRangeDetail';
  static String compareNearestHour(String time, int diffMin) =>
      '来源最近有效时次：$time UTC（与请求时刻相差 $diffMin 分钟）';
  static String compareModelRun(String hhmm) => ' · 起报 $hhmm UTC';
  static const compareNoSeries = '未返回时间序列';
  // 节点天气数值
  static const cellsNoDataAtHour = '该时次无数据（超出来源范围或未提供）';
  static const cellsPrecipMissing = '降水：未提供';
  static String cellsPrecip(String amount) => '降水 $amount';
  static const cellsWindMissing = '风：未提供';
  static String cellsWind(String speed) => '风 $speed';
  static const cellsTempFeels = '气温 / 体感';
  static String cellsSustained(String speed) => '持续 $speed';
  static String cellsProb(String pct) => '概率 $pct%';
  static String cellsProbWithNote(String pct) => '概率 $pct% · $probVsAmountNote';
  // 节点未来 24 小时图
  static String meteogramSemantics({
    required int hours,
    required int? tempLo,
    required int? tempHi,
    required String? precipMm,
  }) =>
      '$meteogramTitle：$hours 小时，'
      '${tempLo == null ? '气温未提供' : '气温 $tempLo 到 $tempHi 度'}，'
      '${precipMm == null ? '降水未提供' : '降水合计约 $precipMm 毫米'}';
  static String meteogramHour(String hh) => '$hh时';
  static String meteogramViewing(int month, int day, String hh) =>
      '查看 $month/$day $hh时';
  static String meteogramTempFeels(String temp, String feels) =>
      '$temp / 体感 $feels';
  static const meteogramCloud = '云';
  static String meteogramDay(int day) => '$day日';
  // 穿衣卡片
  static String layeringAtKm(String km) => '$km km 处';
  static const layeringWorn = '穿着';
  static const layeringPackedAway = '放背包';
  static const layeringNotNeeded = '不需要';
  static String layeringFigureSemantics(String scene, List<String> parts) =>
      '$layeringTitle，$scene时：${parts.join('，')}';

  // 分享图
  static String shareFailed(Object e) => '分享失败：$e';
  static const shareBrand = '山晴 · 徒步天气';
  static const shareCallToAction = '导入轨迹，按出发时间查看沿途天气\n扫码下载测试版';
  static const shareQrLabel = '下载二维码';
  static const shareSketchStart = '起';
  static const shareSketchEnd = '终';
  static const shareSketchStartEnd = '起终';
  static const shareLayoutFull = '长图·完整';
  static const shareLayoutBrief = '简图·摘要';
  static const shareLayoutWide = '横图';
  static const shareNodeNoData = '此来源无该时刻数据';
  static const shareNodeIncomplete = '数据不完整';
  static String shareNodeGust(String gust) => '阵风 $gust';
  static String shareNodeAtKm(String km) => '$km km 处';
  static const shareNotProvided = '未提供';
  static const shareModeFixed = '固定时刻';
  static String shareFixedModeNotice(String hhmm) =>
      '这张图是全线同一时刻（$hhmm）的天气快照，每个节点都取这一小时，'
      '不是按出发时间推算的行程。约好出发时间的话，建议改按行程分享。';
  static const shareModeTrip = '行程模式';
  static String shareModeFixedTitle(String stamp) => '全线同一时刻 · $stamp';
  static const shareModeFixedNote = '各节点都取这一小时的预报，没有按出发时间和行走时间推算。';
  static String shareModeTripTitle(String start, String end) =>
      '$start 出发 → 约 $end 到达';
  static String shareModeTripNote(String? sunset) =>
      '按配速估算到达各节点的时刻，天气取到达时的预报'
      '${sunset == null ? '' : ' · 日落 $sunset'}';
  static const shareTemp = '气温';
  static const shareMaxGust = '最大阵风';
  static const shareDayPrecip = '全天降水';
  static const shareTripPrecip = '行程降水';
  static const shareHourPrecip = '该时次降水';
  static const shareNoNotablePrecip = '无明显降水';
  static String shareWetHours(String from, String to) => '$from–$to 时';
  static const shareNoHints = '未触发阈值提示（不代表安全）';
  static const shareReversed = '反向';
  static const shareDemoRoute = '演示线路';
  static String shareSourceLine(String source, String stamp) =>
      '数据：$source · 获取于 $stamp（设备时区）';
  static String shareRouteDisclaimer({required bool tripMode}) =>
      '预报非实测；提示按阈值计算，非官方预警、非安全评分${tripMode ? '；到达时间为配速估算' : ''}。示意图不含地图。';
  static const shareGearWorn = '出发穿';
  static const shareGearPacked = '背包带';
  static const shareGearAccessories = '配件';
  static const shareGlyphPast = '过';
  static const shareGlyphMissing = '缺';
  static const shareDemoSuffix = '（演示）';
  static String shareDepartureSubtitle({
    required bool reversed,
    required String hours,
  }) => '出发窗口对比 · ${reversed ? '反向' : '正向'} · 全程约 $hours 小时（估算）';
  static const shareDepartureLegend =
      '✓ 未触发　风 阵风　雨 降水　冷 低温　晚 晚于日落　缺 信息不足　过 已过去';
  static const shareNoClearDeparture = '所列时段内没有“未触发阈值且信息完整”的出发时刻。';
  static String shareEarliestClear(String stamp) => '最早未触发阈值的出发：$stamp';
  static const shareDepartureDisclaimer = '颜色只表示阈值结果，非安全评分；预报非实测，官方预警与日出未接入。';
}
