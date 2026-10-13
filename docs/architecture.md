# 架构

## 技术栈与选型理由

| 层 | 选择 | 理由（含已核验事实） | 备选与放弃原因 |
| --- | --- | --- | --- |
| 框架 | Flutter (stable 3.47.7 / Dart 3.13.5) | 三端一致 | — |
| 状态管理 | flutter_riverpod ^3.4 | 轻量、可测、family/autoDispose 支持参数化数据获取 | Bloc 偏重 |
| 路由 | go_router ^18 | 声明式、深链 | Navigator 1.0 难维护 |
| 地图 | flutter_map ^8.3 + latlong2 ^0.10 | 纯 Dart：Android/iOS/Web 行为一致；瓦片供应商可换；v8 支持 polyline 命中测试与内置瓦片缓存（官方文档核验） | maplibre_gl：native+web 双实现，Web 支持弱、维护风险高；为单端能力牺牲三端不值得 |
| HTTP | dio ^5.11 | CancelToken 取消、拦截器、超时；之上封装 WxHttp（429/5xx 退避、异常不携带坐标） | package:http 无取消 |
| 持久化 | shared_preferences ^2.5 | 三端一致；设置/收藏直接存储，业务缓存用 CacheStore（TTL/LRU/命名空间） | path_provider 不支持 Web |
| XML/GPX | xml ^7.1 | 纯 Dart，不解析外部实体（防 XXE） | — |
| 文件选择 | file_selector ^1.1 | 官方维护，三端 | — |
| 定位 | geolocator ^14 | 仅按需一次性定位 | — |
| 图表 | 自写 CustomPainter | 与真实采样点严格对应、零额外依赖 | fl_chart 增加依赖面 |

## 分层

```
ui/            屏幕（地图首页/详情/对比/设置/导入）+ 公共组件
data/weather   WeatherProvider 抽象 + 适配器（Open-Meteo / MET Norway）
               WeatherRepository：采样节点→近似网格去重→缓存→请求→溯源
data/routes    HikingRoute（多段几何）+ GPX/GeoJSON 导入 + Overpass 发现 + 示例
data/settings  AppSettings / Favorites（Notifier + shared_preferences）
core/          Geo（haversine/DP 简化）、Units、WxHttp、CacheStore
```

- **地图渲染与业务解耦**：业务层只产出 `HikingRoute` / `RouteNode` / `WxSourceResult`，
  ui/map 仅负责渲染与命中。换地图库不动业务。
- **无网关**：当前数据源全部免密钥且 CORS 开放，直连即可（不为无密钥 API 加后端复杂度）。
  Web 端 MET Norway 的 User-Agent 限制如实标注。未来需要密钥/合并/限流时再加轻量网关
  （`.env.example` 已预留 `WEATHER_GATEWAY_URL`）。

## 数据真实性模型（核心不变量）

`WxProvenance` 强制携带：服务商、实际模型（未知标记）、请求坐标 vs 返回坐标、
来源使用海拔、颗粒度（网格/站点/区域/城市/未知）、空间分辨率及依据（无则“未确认”）、
数据类型（观测/模型估计/预报/趋势）、获取时间、起报时间、时区偏移、授权与署名、
插值/海拔修正说明、追踪信息（不含坐标）。

所有变量值 `double?`；`WxVar.windGust` 与 `windSpeed`、`precipProb` 与 `precip`
是不同键。内部标准单位：°C / m/s / mm / m；来源单位在适配器内换算。

## 时间与缓存

- 内部时间一律 UTC；ETA 纯 UTC 运算（跨午夜/DST 安全）；展示按设备本地或来源偏移并标注。
- 缓存命名空间：routes / map / weather / user。天气缓存键 =
  `v1|providerId|近似网格坐标串|起始小时|结束小时`；TTL 按来源（Open-Meteo 30min、
  MET 20min）；过期 6h 内可读但 UI 标“旧数据”并后台刷新（stale-while-revalidate）。

## 请求纪律

- 地图拖动期间零天气请求；选中线路才拉取。
- 近似网格（0.1°，可配）合并查询点；上限/间距可配（低耗电模式加倍）。
- 429/5xx 指数退避并尊重 Retry-After；不换端点规避配额。
- 时间滑块拖动仅预览已加载数据，onChangeEnd 才发起新查询。

## 国际化

默认中文。文案集中于 `lib/ui/strings.dart`（`S` 抽象类常量），业务代码不内联用户可见
文案。迁移 ARB/gen-l10n 时仅需将 `S.xxx` 替换为生成访问器（任务 T-220）。
MaterialApp 已配置 zh/en supportedLocales 与本地化代理（日期选择器等为中文）。

## 平台目录策略

不提交 android/ios 模板；提交定制文件（AndroidManifest、Info.plist、web/）。
构建前 `flutter create --platforms=...` 生成其余（CI 内置）。理由：模板随 Flutter
版本变化，手写模板易错配；生成保证与所 pin 的 Flutter 版本一致。
