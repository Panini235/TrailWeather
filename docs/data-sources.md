# 数据源能力与授权对照

> 2026-10-15 授权复核：完整结论见 `ios-first-commercialization-2026-10-15.md` 第4节。下方2026-10-13网络可达性是历史测试记录，不构成商用或离线授权证明。

> 核验日期：2026-10-13。核验方式：官方文档 + 真实 API 实测（代理出口与大陆直连双路径）。
> 日常 CI 使用 fixture 契约测试；真实联网验证用手动 “Live Smoke” workflow。

## 大陆网络直连实测（2026-10-13，本机直连不走代理）

| 服务 | 直连结果 | 结论与措施 |
| --- | --- | --- |
| api.open-meteo.com（天气） | 200，约 1.1s | 可直连使用 |
| api.met.no（天气） | 200，约 1.7s | 可直连使用（稍慢） |
| geocoding-api.open-meteo.com（地点搜索） | 200，约 1.0s | 可直连使用 |
| **tile.openstreetmap.org（OSM 瓦片）** | **超时（8s+）** | **默认底图已改为高德瓦片，OSM 保留为设置选项（海外网络）** |
| **webrd0{1-4}.is.autonavi.com（高德瓦片）** | **200，约 70ms** | **默认底图**；GCJ-02 坐标系，见“坐标系策略” |
| overpass-api.de | 可达但 504（服务过载）；kumi 镜像直连超时 | OSM 线路发现在大陆不稳定（外部服务状态）；镜像轮换已实现，失败时 App 如实提示，本地线路/导入不受影响 |
| devapi.qweather.com（和风天气） | 域名直连可达（403 为无 key 预期响应），毫秒级 | 已接入和风格点适配器（需用户免费注册配置 key） |

### 坐标系策略（GCJ-02 vs WGS-84）

- 业务数据（线路几何、天气查询、导入导出、Overpass 查询）**始终 WGS-84**；
- 仅在使用高德底图渲染时转换为 GCJ-02（`lib/core/gcj02.dart`，通用近似算法，
  迭代逆变换往返误差米级，测试覆盖含天安门公开参考点）；地图交互坐标逆变换回 WGS-84；
- 底图可在设置中切换（高德/OSM）。

## 天气来源

### 1. Open-Meteo Forecast API

| 项 | 内容 |
| --- | --- |
| 端点 | `https://api.open-meteo.com/v1/forecast`（实测 200） |
| 密钥 | 不需要 |
| CORS | 允许（Web 直连可行） |
| 覆盖 | 全球（陆地为主） |
| 时效 | 最多 16 天；逐小时（1h） |
| 批量 | 支持（latitude/longitude 逗号列表，返回数组；实测验证） |
| 响应溯源 | 返回网格坐标（latitude/longitude）、模型地形海拔（elevation）、utc_offset_seconds；**不返回**模型起报时间与网格中心标识 |
| 我们接入的模型 | `best_match`（按区域自动选模型，响应不指明具体模型 → 按未知处理）、`ecmwf_ifs025` |
| 空间分辨率 | 响应不携带。best_match 分辨率随区域变化（未确认）；ecmwf_ifs025 为 0.25° 级全球模型（按模型名标注，以官方文档为准） |
| 授权 | CC BY 4.0；非商业用途免费额度（商业需付费计划或自托管） |
| 署名 | “数据：Open-Meteo（模型来自 NOAA/GFS 等机构，随 best_match 而定）” |
| 缓存 TTL | 30 min（自定） |
| 限制 | 非商业免费额度有调用上限（官方文档），实现分批 + 最小间隔 600ms + 退避 |

### 2. MET Norway Locationforecast 2.0 (compact)

| 项 | 内容 |
| --- | --- |
| 端点 | `https://api.met.no/weatherapi/locationforecast/2.0/compact`（实测 200） |
| 密钥 | 不需要，但**服务条款要求 User-Agent 标识自身**（已内置） |
| CORS | `Access-Control-Allow-Origin: *`（实测） |
| Web 标识 | 当前MET条款允许低流量浏览器以Origin标识；移动端应使用有效User-Agent和联系方式。旧能力文案过于保守，待后续统一调整；生产端仍需缓存和流量治理 |
| 覆盖 | 全球（北欧分辨率更高） |
| 时效 | compact 实测约 2–3 天逐时（以 3 天标注） |
| 批量 | 不支持（单坐标/请求）；实现最小间隔 250ms |
| 响应溯源 | `meta.updated_at`（作为发布时间）；响应几何为请求坐标原样（不冒充实际网格坐标）；不提供来源使用海拔 |
| 缺失字段（实测） | 体感温度、降水概率、能见度、多数时次的阵风 → UI 显示“此来源未提供” |
| 空间分辨率 | 来源文档：北欧 HARMONIE 约 2.5 km，其他区域 ECMWF 约 9–22 km，随区域与时效变化；响应不携带网格信息 |
| 授权 | NLOD 2.0 / CC BY 4.0 |
| 署名 | “天气数据：MET Norway, CC BY 4.0 / NLOD” |
| 缓存 TTL | 20 min（自定，低于其典型更新节奏） |

### 模型重叠（诚实声明）

- Open-Meteo 的多个 `models` 参数（best_match / ecmwf_ifs025）来自**同一服务商接口**，
  不是相互独立的证据。
- MET Norway 全球部分使用 ECMWF 模型，与 Open-Meteo 的 ECMWF 系模型可能共享底层模型；
  未逐点识别，按“未知，可能重叠”标注。
- App 在来源卡片与设置页展示以上说明。

### 3. 和风天气 QWeather（格点 24h）

| 项 | 内容 |
| --- | --- |
| 端点 | `https://{API Host}/v7/grid-weather/24h?location=经度,纬度`（官方文档核验 2026-10-13） |
| 密钥 | **需要**（按账号已开通服务与认证配置）。新账号使用控制台专属 API Host（形如 abc123.qweatherapi.com）；旧账号 devapi.qweather.com。设置 → 数据源密钥 配置，仅存本机 |
| 认证 | 请求头 `X-QW-Api-Key` |
| CORS | 开放（Web 可用） |
| 时效 | 格点逐时**仅 24 小时**（超窗如实显示“此来源暂无该日期数据”） |
| 批量 | 不支持（单坐标/请求）；最小间隔 150ms |
| 空间分辨率 | 文档声明约 3–5 km（响应不携带网格信息） |
| 缺失变量 | 无体感温度、无阵风（仅风力等级文本）；能见度单位 km（内部转 m） |
| 授权 | 待核验：当前许可正文访问受限，需从控制台取得账号适用条款并确认商业用途、缓存/再分发、风险提示和归因；不以免费额度或Key推定许可 |
| 署名 | “天气数据：和风天气 qweather.com” |
| 真实联网验证 | **未验证**（无 key）；域名直连可达已实测。fixture 契约测试覆盖解析；待用户配置 key 后用 Live Smoke 验证 |

### 1b. Open-Meteo 补充（2026-10-15 核验：官方文档 + 实测）

- **按节点海拔降尺度**：`elevation` 参数可为逗号列表（每坐标一个）；默认 90 m 高程模型；`elevation=nan`
  会**关闭**降尺度改用网格平均高度——所以节点缺海拔时整批不传 `elevation`，不用 nan 补位。
- **新增变量**：`weather_code`（WMO 表：45/48 雾、56/57/66/67 冻雨、71–77/85/86 雪、95–99 雷暴；96/99 仅部分模式）、
  `snowfall`（cm，前一小时新增雪深，约 7 cm ≈ 10 mm 降水）、`freezing_level_height`（m，0℃ 层海拔）。
- **同一地点不同海拔**：同一坐标重复 N 次、配 N 个 elevation，一次请求得到垂直剖面（实测五台山北台附近同一时次
  1500 / 2500 / 3058 m 为 14.8 / 8.2 / 4.6 ℃）；地面海拔用 Elevation API `/v1/elevation`（90 m 高程模型）。
- **合并策略**：按海拔计算的来源只合并“同 0.1° 网格且海拔差 <100 m”的节点，避免山脊与山谷合成一个点。

### 1c. Open-Meteo Air Quality（CAMS）

- `air-quality-api.open-meteo.com/v1/air-quality`，`hourly=pm2_5,pm10,us_aqi`；中国区域为 CAMS 全球预报，
  **约 0.4°（≈45 km）网格**，每 12 小时更新、5 天预报；PM2.5 为近地面（约 10 m）浓度。
- 展示为“区域级数值”，并说明山脊在逆温层之上时实际空气可能更好；必须署名 CAMS（哥白尼大气监测服务）与 Open-Meteo。
- 授权同 Open-Meteo（免费 API 非商用；商用需订阅）。

### 4. meteoblue Forecast API（basic-1h，按需单点）

核验：2026-10-15，用户自有 Free key 实测 1 次 + 官方页面（business.meteoblue.com 免费版对比表、
docs.meteoblue.com 逐时 pictogram 表）。

| 项 | 事实 |
| --- | --- |
| 端点 | `GET https://my.meteoblue.com/packages/basic-1h?apikey=…&lat=…&lon=…&asl=…&format=json&tz=UTC` |
| 计费 | 响应头 `mb-credits-accounted: 8000`（每次）；免费版 1000 万 credits / 1 年 ≈ 1,250 次（页面另写“约 2,500 次调用”，以账户为准） |
| 批量 | 一次一个坐标，无多点批量 |
| 海拔 | `asl` 指定海拔后按该海拔计算；不指定时用 80 m 高程模型；`metadata.height` 回显所用海拔 |
| 时效 | `data_1h` 自当天 00:00 UTC 起 169 个逐时值（7 天） |
| 变量 | 气温、体感、降水量、降水概率、风速（ms-1）、风向、湿度、海平面气压、降雪占比（snowfraction）、pictocode |
| 不含 | 阵风、能见度、云量（在 wind/clouds 包，免费版仅 3 小时分辨率）→ 保持 null |
| Web | CORS `Access-Control-Allow-Origin: *`（实测）；Web 端 key 出现在请求地址中 |
| 授权 | 免费版页面对比表标注 “Commercial use ✓”；早期页面写非商用。**以账户条款为准**，商用前复核 |
| 署名 | 展示“天气数据：meteoblue” |

**接入方式（因额度）**：`caps.onDemandOnly = true`——不参与线路自动请求与首页位置天气；只在节点详情
“多来源对比”或地图选点里用户点击“查询此点”时单点请求，按节点轨迹海拔传 `asl`，缓存 3 小时（缓存键含海拔）。
本机记录真实请求次数（设置页显示），剩余额度以 meteoblue 后台为准。密钥仅存本机（`meteoblue.v1`），不入库。

**pictocode**：basic-1h 使用逐时编码表（1–35），日数据为另一套（1–25），不能混用；映射见
`lib/data/weather/weather_phenomena.dart`。

## 其他数据服务

### Open-Meteo Geocoding（地点搜索）

- 免费无密钥，CORS 开放（实测）。数据来自 GeoNames 等（知识共享署名）。
- 返回 IANA 时区字段（地理数据库属性，非天气分辨率）。

### Overpass API（OSM 徒步路线与路径发现）

- 端点轮换：overpass-api.de / kumi.systems / private.coffee。
- 实测状态（2026-10-13）：主站对大查询返回 504（过载，外部状态）；退避与镜像轮换已实现，
  真实可用性以 Live Smoke 结果为准。
- 使用纪律：仅 zoom≥11；首页定位成功或选择地点后自动查询一次，用户也可点击“搜索此区域”；
  bbox 跨度 ≤0.6°；正式路线与路径段合计单次 ≤60 条；结果缓存 10 min。不把公共查询服务
  当无限量生产数据库。
- 查询与标注：`relation[route=hiking]` 标为“徒步路线关系”；具名
  `highway=path|footway|track` 仅标为“具名路径段（不是完整规划路线）”，不把普通路径伪装成
  可直接导航的完整线路。
- 几何处理：relation 成员 way 乱序/缺失/不连通时按端点贪心串联，不共享端点的段独立，
  **绝不自动连直线**；行程模式基于最长连续段并标注。

### 用户建议的第三方线路平台（接入边界）

- [两步路](https://www.2bulu.com/)：本轮未找到面向第三方 App 的公开线路目录 API 与明确商用授权；
  不抓取网页或调用未公开接口。
- [六只脚](https://www.foooooot.com/)：官网公开展示行程目录，但本轮未找到官方开发者 API/商用再分发条款；
  未获书面许可前不把网页内容当 API。
- 小红书公开 Ark API 为商家电商接口，不提供笔记/徒步线路目录搜索；不读取登录 Cookie 或移动端私有接口。
- [奥维互动地图第三方接口](https://www.ovital.com/openapi/)：官方接口用于 Windows 版奥维与第三方程序通过
  Windows 消息/WebSocket 协作，可读写用户收藏夹中的轨迹/路线；它不是公开线路目录，也不能直接作为
  Flutter Android/iOS/Web 的云端线路来源。
- **当前实现**：混合搜索本机匹配已有线路并调用 Open-Meteo Geocoding；百度外部攻略入口已在Round 12移除。App不抓取或复制外部平台内容。
- 可合规推进的路径：继续支持用户自行导出的 GPX/GeoJSON；若产品方提供正式 SDK/API 与商用授权，
  再做账号授权或深链导入。生产版不以逆向、爬虫或复用私人接口替代合作协议。

### 可直接评测的徒步线路 API（候选，尚未接入）

| 类型 | 候选 | 能力与边界 |
| --- | --- | --- |
| OSM 线路目录 | [Waymarked Trails API](https://github.com/waymarkedtrails/waymarkedtrails-api) | 基于 OSM，支持线路名称模糊搜索；服务端 GPLv3，需自建数据库/后端并履行 ODbL，不依赖公共实例 SLA |
| 商业线路目录 | [Outdooractive API 示例](https://github.com/Outdooractive/outdooractive-examples) | 有专业户外线路内容，但需商务申请项目密钥、数据范围与商用再分发许可，不是匿名即用 API |
| 徒步路线生成 | [openrouteservice](https://openrouteservice.org/services/) | `foot-hiking`，返回几何；是起终点规划器，不是热门线路目录，可申请 key 或自建 |
| 徒步路线生成 | [GraphHopper Routing API](https://docs.graphhopper.com/openapi/routing-api) | `hike` profile，返回 polyline/GeoJSON，有商业套餐；需对中国景区覆盖做样本验证 |
| 徒步/步行生成 | [Mapbox Directions](https://docs.mapbox.com/api/navigation/directions/) | `mapbox/walking` 包含部分步道/徒步场景；商业计费，不提供社区热门线路目录 |
| 大陆步行生成 | [高德路线规划](https://lbs.amap.com/api/webservice/guide/api/direction) / [腾讯路线规划](https://lbs.qq.com/service/webService/webServiceGuide/webServiceRoute) | 大陆道路覆盖较好，但只有步行模式，不保证山地步道完整性；需密钥、GCJ-02 边界和商用授权 |

Wikiloc 官方说明暂无开发者 API；Komoot 官方说明无公开 API；AllTrails 未核验到公开自助线路目录 API；
Strava API 主要读取获授权用户自己的路线。第三方“scraper API”不进入候选。

### 高德地图栅格瓦片（默认底图）

- 当前代码直连 `webrd0{1-4}.is.autonavi.com`，历史实测可访问；**未核验该接入方式的本项目授权**。
- 正式分发前需通过高德开放平台确认个人主体、官方SDK/API、使用场景及所需书面许可；在线Key不等同离线授权。
- GCJ-02 坐标系：App 侧做 WGS-84↔GCJ-02 显示层转换（见上“坐标系策略”）。
- 署名：© 高德地图（地图页脚）。

### OpenStreetMap 标准瓦片（备选底图）

- `tile.openstreetmap.org`，仅在线显示，遵守瓦片使用政策，**不做离线预下载**。
- 署名：© OpenStreetMap 贡献者（地图页脚 RichAttributionWidget + 设置页说明）。
- 重负载生产环境应更换商用瓦片（发布前检查项，见 release-checklist.md）。

### 地图图层（底图 + 叠加，Round 16）

- 来源注册表：`lib/data/map/tile_sources.dart`（高德标准/卫星/路网注记、天地图矢量/影像/地形晕渲及三种注记、
  OpenTopoMap 等高线、Esri 卫星、OSM）。用户可自定义 XYZ 图源（URL 模板、子域名、坐标系、最大缩放、署名）。
- 显示坐标系由底图决定；**坐标系不同的叠加层不渲染**（GCJ-02 与 WGS-84 混叠会错位约 100–700 m），
  面板中显示原因。业务计算始终 WGS-84。
- 天地图需用户自行申请 Key（`{tk}` 占位），未填写时天地图图层不可选；所选天地图底图在 Key 缺失时回退默认底图并提示。
  天地图为 CGCS2000，与 WGS-84 差异厘米级，按 WGS-84 处理。天地图地形与地形注记最高 14 级。
  Key 类型与错误码见下节。
- 国内可达性未实测：OpenTopoMap、Esri 为海外服务，面板中注明“国内常常加载缓慢或失败”。

### 天地图 Key 类型与错误码（2026-10-15 实测）

App 直接请求天地图 HTTP 瓦片（`t{0-7}.tianditu.gov.cn/DataServer?T=…&tk=…`），不使用天地图 Android/iOS SDK。
用户在天地图控制台申请了“浏览器端”和“服务端”两个 Key，直连 `t3.tianditu.gov.cn`，z10 北京附近，
vec/img/ter/cva/cia/cta 六个图层实测（原始记录：claude/zealous-cori-926437 分支 `docs/3d-map-evaluation.md` §5.1）。

**天地图按 User-Agent 是否含 `Mozilla` 判定请求是否来自浏览器，与 Referer 无关**，再按 Key 的“应用类型”放行：

| Key 类型 | UA 不含 Mozilla（flutter_map 默认 UA、空 UA、`Dart/…`、`okhttp/…`） | UA 含 Mozilla（浏览器、WebView） |
| --- | --- | --- |
| 浏览器端 | 403 `{"code":301012,"msg":"权限类型错误","resolve":"Key权限类型为:浏览器端，请使用浏览器访问！"}` | 200 图片 |
| 服务端 | 200 图片（t0/t3/t7 子域、z10/z12 均通过） | 403 `{"code":301013,"msg":"权限类型错误","resolve":"Key权限类型为:服务器端，请使用服务器端访问！"}` |

- 错误 Key：403 `{"resolve":"请到API控制台重新申请Key","code":301001,"msg":"非法key"}`
  （用户实测；本轮又用 32 位十六进制假值复测，UA 含/不含 Mozilla 结果相同）。
- Key 格式异常：本轮用 15 位、含非十六进制字符的假值请求，返回 418 防火墙拦截页（HTML，`Server: CW`），不是 JSON；
  具体触发条件（长度还是字符）未细分。
- 403 JSON 响应带 `Access-Control-Allow-Origin: *`（本轮复测），Web 端可以读到响应体；同时带 `Cache-Control: max-age=432000`（5 天），
  浏览器可能缓存同一 URL 的 403。在控制台修改已有 Key 的类型后，网页版可能需要清除站点缓存才生效（推断，未实测）。

**App 的做法（D-023）**：

| 渲染环境 | 发出的 UA | 使用的 Key（设置项） |
| --- | --- | --- |
| Android / iOS 原生 2D（flutter_map） | `flutter_map (app.shanqing.hiking)` | 服务端（`tiandituServerKey`） |
| Flutter Web 2D | 浏览器 UA（无法改写） | 浏览器端（`tiandituBrowserKey`） |
| 将来的 3D 视图（WebView / iframe） | 浏览器 UA | 浏览器端 |

- 选 Key 在数据层：`TileRequester` + `TiandituKeys.forRequester`（`lib/data/map/tile_sources.dart`），平台判断只有
  `flutterMapRequester = kIsWeb ? browser : nativeApp` 一处。对应 Key 未填时该端天地图图层不可选（不跨端借用另一个 Key）。
- 不伪造浏览器 UA 绕过类型校验（用户决定）。
- 天地图图层的瓦片请求经过 `TiandituErrorSniffingClient`（`lib/data/map/tianditu.dart`）：只在天地图域名的错误响应上
  读取响应体，按 code 映射为明确提示（301001 Key 无效 / 301012 服务端栏填了浏览器端 Key / 301013 浏览器端栏填了服务端 Key /
  418 拦截 / 其他状态码），显示在地图顶部与 Key 设置卡片中，而不是只留空白瓦片。
- 两栏填同一个值时设置卡片提示“必有一端无法出图”；旧版单一 `tiandituKey` 迁移后两栏相同，同样会提示。
- 申请方法：天地图控制台“创建新应用”，应用类型分别选“服务端”与“浏览器端”，白名单留空。“安卓端”类型需要
  发布版 SHA1 + 包名，用于天地图 Android SDK 的签名校验，本项目不用 SDK，且 CI 每次构建签名都不同，不使用（推断，未实测）。
- 3D 地形/地图未实现：flutter_map 只支持 2D 栅格，需要更换渲染引擎，另行评估。

## OSM 衍生数据义务评估（简要）

- 展示 OSM 线路（ODbL）：当前 App 按 viewport 查询、缓存 10 分钟、附署名与许可说明，
  属于“生产数据库另行构建”之外的有限使用；若后续做离线打包/再分发，需要按 ODbL
  开放衍生数据库——已列入发布前检查项，不宣称已完全合规。

## 字体/图标

- Material Icons（Flutter SDK 自带，Apache-2.0 授权的图标集）。
- 系统默认字体，无打包字体。

## 完整第三方依赖许可

见 `docs/licenses.md`（由 pub 依赖树人工整理，发布前用 `flutter pub deps` 复核）。

## 内置徒步星球目录（2026-10-15复核）

上游 SpaceZephyr/trail-planet 公开仓库未提供许可证，GitHub license=null、license接口404，README没有授权声明。代码原MIT标注已纠正。正式分发前须取得作者及上游数据所需权利，或移除/替换该数据；当前仍是发布阻塞。
