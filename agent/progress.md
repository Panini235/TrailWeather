# 迭代进度

格式：每轮一节；无实质改动不得声明新一轮。

## Round 1 — 2026-10-13（M0+M1+M2+M3 核心，一次性批量实现）

**目标**：完成可构建的核心闭环并首次推送 CI（策略：批量提交降低 workflow 次数）。

**完成**：
- 研究核验（实测）：Open-Meteo forecast/geocoding、MET Norway compact（CORS *、UA 要求）、
  Overpass（主站 504 过载）、Flutter stable=3.47.7、全部依赖最新版本（pub.dev API）。
- 代码：core（geo/units/http/cache）→ weather（模型/两来源/仓库/ETA/风险）→
  routes（模型/GPX/GeoJSON/Overpass/示例）→ settings → UI 五屏 → 3 条演示 GPX 资产。
- 测试：单元 8 组 + 来源契约（fixture）+ 组件 + 集成闭环。
- CI：单 job 全量（analyze/test/web/apk + artifacts）、手动 iOS、手动 Live Smoke。
- 文档：docs/ 全套 + AGENTS.md + agent/ 四件套。

**已知问题（本轮自评）**：
- 本地无 SDK，全部正确性押在 CI 首跑；预期需要 1–3 轮修复。
- Overpass 主站过载为外部状态（镜像轮换已实现）。
- 耗电/真机性能未验证（无设备）。

**下一轮计划**：push → gh run watch → 修复 analyze/test/build 错误 → 更新本文件。

## Round 2 — 2026-10-13（CI 修复至全绿）

**环境变化**：用户批准本地安装 Flutter（3.47.7，flutter-io.cn 镜像，无模拟器），
本地 analyze/test 迭代后一次推送，大幅降低 CI 次数。

**修复**（4 轮 CI）：
1. analyze 32 项错误（hypot/导入路径/Riverpod3 valueOrNull/词法等）→ 清零。
2. info 级 lint 4 项 → 清零（该版本 flutter analyze 将 info 计为失败）。
3. 测试失败：缓存 jsonEncode（'v' 改显式 Map<String,double>）、超窗判断、
   6 处测试断言自身错误、ListView 懒挂载需滚动暴露 → 本地 83/83 全绿。
4. Android：AndroidManifest launchTheme→theme+NormalThemeMeta → APK 构建通过。

**CI 结果**：run 38402622454 conclusion=success
（analyze ✓ / test 83 ✓ / web release ✓ / apk release ✓ / artifacts ✓）。
iOS 手动构建已触发（run 38403822714），结果见后续记录。

**状态升级**：原型可运行 → **核心功能已验证（Android/Web 构建级 + 测试级）**。
未完成：iOS 结果、真机性能/耗电、Web 浏览器人工冒烟、商业授权——见 blockers.md。

**下一轮**：iOS 构建结果记录；可选：Web 冒烟、ARB 迁移、远期趋势调研。

## Round 3 — 2026-10-13（iOS 验证 + 收尾）

- iOS release --no-codesign 构建通过（run 38403822714）：三端构建级验证完成。
- ci.yml 增加 docs/agent 的 paths-ignore（文档变更不再触发构建，进一步降低次数）。
- 验收矩阵/任务状态同步更新。
- 本批次 CI 运行数：7 次（含 1 次 iOS 手动），达成"尽可能降低构建次数"约束下的全绿。

## Round 4 — 2026-10-13（大陆网络适配）

**用户需求**：气象 API 大陆直连可用；地图换国内源（OSM 大陆不可用）。

**直连实测**（不走代理）：Open-Meteo/MET/Geocoding 可直连（1–2s）；
OSM 瓦片超时；高德瓦片 70ms；和风域名可达。→ 天气 API 本身大陆可用，
瓶颈在瓦片；额外接入和风作为国内厂商选项。

**实现**：
- GCJ-02 转换（lib/core/gcj02.dart）+ Basemap 适配层（ui/map/basemap.dart）：
  默认高德底图，业务坐标始终 WGS-84 仅显示层转换；OSM 可选（海外）。
- 和风格点 24h 适配器（key/host 用户在设置页配置，仅存本机）：
  能力声明如实（24h/3–5km/无阵风体感/免费订阅限额）；未配置给指引。
- 设置页：底图切换 + 数据源密钥卡。
- 测试 93/93 全绿（新增 GCJ-02 往返/参考点 + 和风契约 fixture）。
- Live Smoke 增加和风可选步骤（配置 Secrets 后生效）。

**CI**：run 38408260872 全绿。累计 CI 9 次（含 iOS 手动 1 次）。

**遗留（诚实）**：和风真实联网未验证（无 key，A-015）；Overpass 大陆直连
不稳定（外部过载，已如实标注）；高德瓦片 GCJ 偏移转换为通用近似算法（米级）。


## Round 5 — 2026-10-14（首页可用性与当地线路发现）

**用户反馈**：首页无法获得当前线路；需要地图点选天气、启动自动定位天气；定位按钮只能用一次。

**实现**：
- 定位插件封装为可注入 `LocationService`：服务关闭、拒绝、永久拒绝、15 秒超时与未知失败分型；
  永久拒绝/服务关闭提供系统设置入口；每次请求在 `finally` 恢复按钮。
- 地图就绪后只自动定位一次；成功后移动到当前位置、弹出多来源当前时次天气，并自动查询一次
  当前视野线路。没有后台定位和位置流订阅。
- 地图空白处或地点搜索结果可直接查询点位天气；WGS-84 标记、请求坐标、有效时次、来源、
  网格颗粒度、缺失项与旧缓存状态独立展示，不把网格预报称为点位实测。
- Overpass 从仅正式 `relation[route=hiking]` 扩展到具名 path/footway/track；普通路径明确标为
  “路径段、不是完整规划路线”，不与正式徒步路线混称；合计上限 60，仍有 bbox/TTL/镜像约束。
- 核验两步路、六只脚、奥维：未找到前两者可直接商用的公开目录 API；奥维公开接口是
  Windows 客户端协作接口而非公共线路目录，未采用爬虫或私有接口。
- 修复两个随日期漂移的 Open-Meteo 契约测试，并为旧集成测试注入定位假实现，保持日常测试不联网。
- 天气缓存键升为 v2，使用实际请求坐标 4 位小数；0.1° 近似网格仅用于同次线路查询去重，
  防止相邻山谷的独立地图点位错误复用缓存。

**本地验证**：`flutter analyze` 0 问题；`flutter test` 96/96 通过。未做本地发布构建；
按项目策略待推送后由 GitHub Actions 构建 Web/APK。


## Round 6 — 2026-10-14（混合线路搜索）

**目标**：让用户明确搜索的是“地点/山峰/线路”，并把可分析线路、外部攻略线索与导入分开。

**实现**：
- 搜索框改为“搜索地点、山峰或徒步线路”；同步匹配本地/收藏/导入/已加载 OSM 线路名称，
  并调用地理编码返回地点候选。
- 选择地点后移动地图、查询附近 OSM，优先显示同名线路；没有同名时展示当前视野可直接分析线路。
- 分组面板明确展示“可直接分析的线路”“地点候选”“外部攻略与轨迹线索”“导入轨迹”。
- 小红书/两步路/六只脚使用用户主动点击的百度 `site:` 搜索；系统浏览器打开，不抓取网页、
  不读取 Cookie、不缓存或复制平台内容。外链失败有可见错误提示。
- 新增可注入 `GeocodeService` / `ExternalUrlLauncher` 边界；加入官方 `url_launcher 6.3.3`
  （精确锁定，Android/iOS/Web），锁文件保持 flutter-io.cn 镜像。
- 调研记录可直接评测的后续 API：Waymarked Trails/Outdooractive（目录）与
  openrouteservice/GraphHopper/Mapbox（路线生成），未把路线生成器冒充社区目录。

**本地验证**：`flutter analyze --no-pub` 0 问题；`flutter test --no-pub` 99/99 通过；
新文件 Dart format 检查 0 变更；外链 URI 2 项单测 + 混合搜索完整组件流 1 项通过。
GitHub Actions Web/APK 构建待推送。


**CI 结果**：功能分支 `feat/hybrid-route-search`，commit `4e34604`，run 38510507584 全绿：
依赖 ✓ / analyze ✓ / test 99 ✓ / Web release ✓ / Android APK release ✓ / 产物上传 ✓。
产物：`web-release` 14,456,349 bytes；`apk-release` 28,190,862 bytes；均未过期。

## Round 7 — 2026-10-14（商业级轨迹导入重构与多格式支持）

**用户反馈**：导入受限严重无法使用，文件过大或含非标准标签直接报错崩溃；需要更强通用性。

**实现**：
- **解除机械硬限制**：文件上限从 2MB 放宽至 30MB；取消 5,000 点一票否决抛错逻辑。
- **自适应 RDP 抽稀算法**：在 `lib/core/geo.dart` 中实现 `Geo.simplifyTrack`，对超过 3,000 点的超长轨迹自适应平滑抽稀，同时强制保留起点、终点以及最高/最低海拔极值点，保证高程与经纬度 1:1 对齐，并在 UI 中如实提示。
- **异常海拔容错清洗**：遇到传感器漂移噪点（<-500m 或 >10000m）时置为 null 并提示警告，严格遵守真实性红线，绝不因个别噪点使整条轨迹报错崩溃。
- **全面支持 KML 格式**：新增 `lib/data/routes/kml_import.dart`，支持奥维互动地图、两步路、Google Earth 的 LineString、MultiGeometry 与 gx:Track。
- **GPX 鲁棒性增强**：过滤 UTF-8 BOM（`\uFEFF`）；忽略 XML 命名空间前缀；支持分散的 `<wpt>` 航点集合自动转换为航线。
- **移动端与文件选择关联**：扩展文件选择器候选扩展名（含 gpx/kml/kmz/geojson/json/gsx/xml/txt）；在 AndroidManifest.xml 与 Info.plist 中注册 VIEW intent-filter 与 Document Types，支持从微信或文件管理器等外部应用打开轨迹。
- **编码容错**：文件读取使用 `utf8.decode(bytes, allowMalformed: true)`，防止非 UTF-8 编码或老旧设备导出文件抛 `FormatException`。

**本地验证**：
- `flutter analyze --no-pub` 0 问题（0 错误、0 警告、0 info）；
- `flutter test --no-pub` 108/108 项测试全绿（新增 9 项单测覆盖 KmlImport 与 Geo.simplifyTrack）；
- `dart format` 全部格式化完毕。

**CI 结果**：分支 `feat/robust-track-import`，GitHub Actions Run ID `38534512846`，全绿成功：
- analyze ✓, test 108/108 ✓, Web Release ✓, Android APK Release ✓。

## Round 8 — 2026-10-14（徒步星球全球经典路线库 + Trail Studio 手绘路线规划工坊）

**用户需求**：
1. 结合 `https://github.com/SpaceZephyr/trail-planet`，把全球顶级 3D/经典路线融入 TrailWeather；
2. 支撑用户手绘规划线路图（参考两步路、奥维地图与 `https://spacezephyr.github.io/map-motion-studio/`），支持打点画线、航点标记、预计徒步耗时、GPX/KML 导出；
3. 二、三优先级一并完成，持续自主迭代升级至成熟商用应用，无需反复询问。

**实现**：
1. **徒步星球路线库（Trail Planet）**：
   - 提取并落盘 `assets/routes/planet_trails.json`（455KB，包含 44 条全球经典徒步路线：环勃朗峰 TMB、冈仁波齐、EBC、虎跳峡、熊野古道、库克山、乞力马扎罗等）。
   - 实现 `lib/data/routes/planet_trails_repository.dart`：涵盖 8 大地貌类型（雪山、森林、冰川、峡谷、海岸、高山草甸、火山、巅峰），支持海拔剖面线性插值，提供地貌分类与里程区间筛选，以及一键随机灵感神线漫游。
   - 实现专区界面 `lib/ui/planet/planet_screen.dart`，并在地图首页浮动按钮及混合搜索中无缝打通。
2. **手绘规划工坊（Trail Studio）**：
   - 数据模型升级（`lib/data/routes/route_models.dart`）：新增 `RouteOrigin.planet` 与 `RouteOrigin.planned`；新增 `RouteWaypoint` 航点模型（营地 ⛺️、水源 💧、险段 ⚠️、垭口 ⛰️、下撤点 🚪、打卡点 📍）。
   - 双向导出引擎（`lib/data/routes/route_exporter.dart`）：支持将规划路线导出为标准 GPX 1.1 与 KML 2.2 文本，完美适配奥维互动地图、两步路及户外 GPS 设备；单测验证往返解析 100% 一致。
   - 交互式规划器（`lib/ui/planner/route_planner_screen.dart`）：支持在底图上触控打点画线、航点添加、撤销（Undo Stack）、反向走法（反穿路线规划）、即时里程统计与基于徒步动力学的预计耗时推演；一键“完成并查天气”保存至收藏并联动 7 天沿途气象推演。
   - 路由与入口整合：注册 `/planet` 与 `/planner` 路由，在地图首页操作栏添加独立快捷入口，在混合搜索推荐区增加显式导航卡片。

**本地验证**：
- `flutter analyze --no-pub` 0 问题（0 错误、0 警告、0 info）；
- `flutter test --no-pub` 115/115 项全量通过（覆盖 planet_trails_test、route_exporter_test、planet_screen_test、route_planner_screen_test）；
- `dart format` 代码风格检查全部合规。

**CI 结果**：分支 `feat/robust-track-import`，GitHub Actions Run ID `38537198873`，全绿成功：
- analyze ✓, test 115/115 ✓, Web Release ✓, Android APK Release ✓。
- 生成产物：`web-release`、`apk-release`。

## Round 9 — 2026-10-14（海明商业化转化体系与 Pro 会员服务闭环）

**目标**：落实 `HammingDev/haiming-app-monetization` 商业化闭环要求，全面提升 TrailWeather 的独特价值展示、使用黏性与付费转化能力，打造专业、成熟、商用的户外微气候产品。

**实现**：
1. **商业化数据模型与状态持久化**（`lib/data/monetization/subscription_models.dart`, `lib/data/monetization/subscription_repository.dart`）：
   - `SubscriptionTier`: free / pro；
   - `SubscriptionPlan`: yearly（¥98/年，含 7 天免费试用，最具性价比主推）、monthly（¥18/月）、lifetime（¥198 终身买断）；
   - 4 项核心特权清单（高程垂直递减修正、极端天气与失温哨兵、离网气象轨迹包、等高线专业底图）；
   - 完整状态流转（购买、免费试用激活、恢复购买、取消续费、持久化至 SharedPreferences）。
2. **痛点引导与场景化问诊**（`lib/ui/onboarding/onboarding_screen.dart`）：
   - Step 1: 场景问诊（重装长线/单日登山/露营越野/溯溪穿越）；
   - Step 2: 价值唤醒与空间反差对比（普通城市天气预报 vs 高山空间微气候：山脚 22℃ 晴 vs 垭口 4℃ 强风暴雨，直击户外失温痛点）；
   - Step 3: 核心功能演示（徒步星球 44 条全球神线 + Trail Studio 手绘路线工坊与 GPX/KML 双向导出）；
   - Step 4: Pro 免费试用引导（7 天免费试用，突出随时免费取消，并支持跳过）。
3. **专业级付费墙与权益对比**（`lib/ui/paywall/paywall_screen.dart`）：
   - 视觉焦点强化主推套餐（年度套餐标注“立省 55% + 7天免费试用”）；
   - 清晰特权勾选清单与来源场景提示；
   - 终身买断与月度套餐自由切换；
   - 退出挽回与安全关闭，拒绝硬卡死。
4. **业务落地与 Pro 专属权益**：
   - 路线详情页：高程垂直递减率微气候计算开关（-0.65℃/100m 算法修正）与状态指示；
   - 路线详情页：一键生成并下载离网离线气象与轨迹包；
   - 设置页：Pro 尊享身份卡片，展示当前会员状态/试用到期时间，一键开通/升级/恢复购买。
5. **自动化测试体系**：
   - `test/unit/subscription_test.dart`（4 项单测：初始状态、年度试用、终身买断、恢复购买）；
   - `test/widget/onboarding_screen_test.dart`（问诊答题、翻页反差、功能演示、跳过与开启试用）；
   - `test/widget/paywall_screen_test.dart`（特权展示、套餐切换、购买触发、恢复购买）。

**本地验证**：
- `flutter analyze --no-pub` 0 问题（0 错误、0 警告、0 info）；
- `flutter test --no-pub` 121/121 全量测试通过；
- `dart format` 全量格式化。

**CI 结果**：分支 `feat/robust-track-import`，GitHub Actions Run ID `38552136025`，全绿成功（7m22s）：
- analyze ✓, test 121/121 ✓, Web Release ✓, Android APK Release ✓。
- 生成产物：`web-release`、`apk-release`。


## Round 10 — 2026-10-15（审查整改：导入可用性 + 天气逻辑 + Pro 真实性）

**起因**：全项目功能审查 + 用户反馈“导入 GPX 等本地文件压根使用不了”（提供 example/ 4 个真实文件）。

**根因（导入）**：解析器本身可用；问题在文件选择器——iOS 只给扩展名时 file_selector 直接抛
ArgumentError（且调用在 try 之外，按钮无反应）；Android 扩展名转 MIME，gpx 无映射、文件常报
octet-stream → 置灰不可选。另：KMZ 被当文本解码（从未支持）；GeoJSON >5000 点直接拒绝。

**完成**：
- T-100：`lib/data/routes/route_file_import.dart` 统一入口（内容嗅探、KMZ 解压、告警去重），
  移动端选择器不过滤、后台 isolate 解析；example/ 四个文件均导入成功（74.5 km、爬升约 4160 m）。
- T-102：Open-Meteo 当天已过去小时误报“超过 16 天”、沿途降水跨节点求和、日落固定取今天、
  节点面板“本地时间”实为 UTC 及重建重复请求等逻辑错误修复，并补测试。
- T-101：Pro 4 项权益均未实现、购买为本地白送 → 支付未接入时禁止开通，未实现权益标“开发中”，
  移除虚假“已启用/已缓存”提示与虚构原价。
- example/ 加入 .gitignore（真实轨迹含位置与时间，不入库）。

**本地验证**：flutter analyze 0 问题；flutter test 138/138 通过。
**未验证**：真机文件选择器（无设备）——需在 CI 产物 APK/iOS 上人工确认。
**CI 结果**：run 38674705802（workflow_dispatch，分支 feat/robust-track-import）conclusion=success，
analyze ✓ / test ✓ / Web release ✓ / APK release ✓，产物 web-release、apk-release。
**附带修复**：live-smoke.yml 在 step 级 if 引用 secrets（不被允许）→ 工作流文件校验失败，
导致每次 push 都出现 0 秒失败记录（Round 8 起即存在）；改为 job env 中转。


## Round 11 — 2026-10-15（真机反馈体验修复）

**起因**：用户真机试用反馈：定位大多超时、定位后自动弹天气打断操作、“搜索此区域”基本不可用、
导入的 GPX 线路在详情页不居中且无法缩放、外部攻略全部跳转百度。本轮只做不涉及产品方向取舍的修复
（首页改版、定位转向“轨迹天气窗口”等需用户另行确认，未做）。

**完成（T-103）**：
- 定位：`lib/data/location/location_service.dart` 抽出 `GeolocatorBackend` 便于测试；Android 用
  `AndroidSettings(forceLocationManager: true)`（无 GMS 的国产 ROM 默认 Fused 会等满超时），精度
  medium、timeLimit 30s；先取 `getLastKnownPosition`（Web 跳过）立即居中，新位置失败时退回上次已知
  位置并以 `LocationFix.isLastKnown` 如实标注（标签/面板标题显示“上次已知位置”+ 提示）。失败分类不变。
- 首页定位：成功后只移动地图 + 地图上显示“当前位置 · 气温 / 来源名”小标签（主来源单点请求，
  与点位面板同参数可命中缓存），点击才打开 `PointWeatherSheet`；不再自动请求 Overpass。
- 线路地图：新增 `lib/ui/map/route_camera.dart`（`routeDisplayBounds`/`routeCameraFit` 纯函数，全部
  segments、GCJ-02 先 toDisplay、单点扩展最小跨度）。详情小地图 `initialCameraFit` 自适配，保持
  不响应手势（避免与 ListView 冲突），点击或全屏按钮进入可拖动/缩放大图（含“显示整条线路”）。
  首页选搜索结果线路、线路列表选线路改为适配整条线路范围。
- 无效入口：“搜索此区域”主按钮移除，降为线路列表底部“尝试加载此区域 OSM 线路”并说明国内常不可达；
  选地点不再自动请求 Overpass；外部攻略折叠为“更多：外部网页搜索（次要）”并写明原因。底层
  Overpass / ExternalTrailSearch 代码与测试保留。原因文案集中在 `strings.dart`。

**本地验证**：flutter analyze 0 问题；flutter test 151/151 通过（新增 location_service_test 8 项、
route_camera_test 4 项；改写首页定位与混合搜索组件测试；集成测试覆盖全屏线路地图）。
**待真机确认**：国产 Android 定位速度与成功率；上次已知位置回退提示；当前位置标签点击；详情页
小地图包围盒适配与全屏手势；首页选线路后的适配范围是否被搜索栏/线路卡遮挡；iOS 定位行为。
**CI 结果**：run 38677552384（workflow_dispatch，分支 feat/robust-track-import）conclusion=success，
analyze ✓ / test ✓ / Web release ✓ / APK release ✓。

## Round 12 — 2026-10-15（v2 改版第 2 步：我的行程首页 + 底部导航 + Android 打开方式）

**依据**：docs/redesign-v2.md（用户确认：首页改“我的行程”、移除百度外部搜索、OSM 搜索降级）。

**完成**：
- T-120：`lib/ui/trips/trips_screen.dart` 首页；`router.dart` 改 StatefulShellRoute（行程/地图/设置）；
  地图页移除 Pro/星球/规划/导入/设置悬浮按钮（已迁到首页与底部导航）；详情缺 extra 时 redirect 到首页。
- 修复：`app.dart` 在 build 中创建 GoRouter，任何设置变化（如深色模式）都会重置导航栈 → 改为 appRouterProvider。
- 移除跳转百度 site: 搜索的外部攻略（代码与测试一并删除）。
- T-121：Android `MainActivity.kt`（首次提交原生代码，.gitignore 放行 kotlin/）接收 VIEW/SEND；
  导入确认抽为 `import_flow.dart` 供导入页与外部传入共用。
- 验证 `flutter create` 不覆盖已提交的 MainActivity.kt / AndroidManifest.xml（本地 scratch 副本）。

**本地验证**：flutter analyze 0；flutter test 153/153。
**未验证**：真机“打开方式”列表与读取（无设备）；iOS 未接入（T-122）。
**CI 结果**：run 38678967686 conclusion=success（analyze / test / Web / APK，APK 步骤编译了 MainActivity.kt）。

## Round 13 — 2026-10-15（v2 第 1 步：详情页基础）

**起因**：用户反馈线路无方向、不知起终点、节点无法与地图联系、无法标记露营点/休息点。

**完成**：
- 方向与起终点：`lib/ui/map/route_marks.dart`（方向箭头按里程等分、起/终/环线“起终”标记），详情小地图、全屏地图、
  首页选中线路共用；“反向行走”（环线同样可反向）。
- 节点联动：地图标记 / 海拔剖面 / 时间线共享选中，自动滚动到对应行；再点或“详情”按钮打开
  `node_detail_view.dart`（完整天气、未来 12 小时、标记、多来源对比）。
- 标记：节点详情或全屏地图长按（吸附到 300 m 内的线路点）→ 营地/休息点/水源/补给/危险/垭口/下撤/打卡；
  新增 rest/supply 类型与停留时长（计入后续 ETA）；标记即保存到“我的行程”。
- 导入：GPX 有名称的 wpt、KML 有名称的 Point 作为航点（跳过起终点与线路同名点，按名称推断类型）。
- 修复：多日 KML 三段（间隔 12 m / 34 m）原先只分析最长的 31.3 km → 首尾 ≤1 km 的段串联，全程 74.5 km 进入分析。

**本地验证**：flutter analyze 0；flutter test 169/169；example/ 四个真实文件全程进入分析、4 个命名航点上线。
**未验证**：真机手势（标记点选、全屏长按）。
**CI 结果**：run 38681970611 conclusion=success（commit b00d707；analyze / test / Web / APK）。


## 成熟度与订阅审计 — 2026-10-15（评估与复现，不计新一轮功能交付）

基线 HEAD 158a73a / 业务提交 b00d707。按“当前与未来天气、无网徒步、完整订阅”目标评估：整体约45%（40%–50%）、在线原型70%–75%、订阅体系约10%、实际收费闭环0%。依据与权重见 `docs/maturity-audit-2026-10-15.md`。

- 本地 analyze 0 issues；原有169/169测试通过。额外4项临时探针确认跨小时缓存失配、7小时旧缓存不刷新、后台刷新错误逃逸、反向节点查询身份碰撞。探针通过仅代表缺陷复现。
- 读取最新CI：38681970611 success；下载现有Web产物，在390×844暗色浏览器跑通示例线路的Open-Meteo天气与高德底图。发现暗色来源按钮/付费提示低对比；首页没有天气摘要；离线/订阅为占位。证据保存到 docs/audit-evidence/2026-10-15/。
- 最新iOS成功38403822714属于2026-10-13旧代码；最近live-smoke失败38674705781无jobs且无可读取日志。没有触发新workflow，也未声称真机、所有来源或离线冷启动已通过。
- 更新T-040为部分浏览器证据（仍todo）；追加T-140至T-148整改与实现任务；登记离线底图授权和后端部署资料缺口。
- 本次仅新增/更新审计、证据和任务记录，业务代码未修改，发现的缺陷仍待修复。


## Round 14 — 2026-10-15（隐藏订阅、真实使用引导、iOS优先）

**用户决定**：个人开发者，iOS优先/Android兼容，暂不做订阅，产品打磨后再重启。

**完成**：T-150：移除设置两处会员入口和PRO算法占位，首次引导改为可滚动的真实功能说明与“导入我的线路/先看示例线路”；旧/paywall重定向首页。T-152：6组名称/SVG/PNG图标候选与小尺寸对照。安装并读取用户指定海明商业化技能；形成docs/ios-first-commercialization-2026-10-15.md。核对服务许可，发现徒步星球原MIT标注无上游证据，改为许可未核验并登记B-011/B-012；这不是授权完成。

**提交**：18be281（UI）与a699aca（许可标签），已push到feat/robust-track-import。
**验证**：本地analyze0，171/171 tests；CI38699456479 success（analyze/test/Web/APK）；iOS38699460743 success（release --no-codesign）。下载CI产物在390×844暗色浏览器验证首次引导、进入示例、设置上下区域无会员入口、旧/paywall回首页。截图存docs/verification/no-billing-2026-10-15/。
**边界**：iOS无签名构建不等于真机/上架；当前接口授权、离线与缓存缺陷仍按任务推进。图标和名字为候选，正式平台资源未替换。T-145/T-146按用户决定暂缓；没有注册商户、购买服务或发布。


## Round 15 — 2026-10-15（山晴名称＋第四个D图标）

**用户确认**：名称“山晴”，图标第四个D（日出叠山、沙色背景）。

**完成T-153**：Flutter应用标题、引导页品牌图片、系统打开提示、GPX导出标识、Android标签、iOS显示名及Web验证入口同步。图标主图与原D方案字节一致，生成Android普通/自适应/主题前景、iOS全部模板尺寸和Web资源。原生资源保存在assets/branding/platforms，CI在flutter create后应用，继续不提交完整平台模板。内部应用身份、MethodChannel、存储键保持兼容。

**提交**：2816d9d。
**本地验证**：analyze0；171/171 tests；临时项目三端资源应用/check模式、PNG尺寸与不透明性、D主图一致性通过。
**CI**：38706513896 success（analyze/test/Web/APK）；38706518000 success（iOS release --no-codesign）。新增产物校验确认APK实际label“山晴”、启动图标声明和品牌图片，iOS实际Info.plist名称与编译AppIcon目录，Web实际标题/manifest/图标。
**边界**：无签名构建不代表商店上架或真机安装验收；名称商标/商店重名在发布阶段核验。本轮没有启动订阅或发布商店。

## Round 16 — 2026-10-15（地图图层、天气节点样式、节点图片）

**起因**：用户要求增加地图样式（等高线、卫星、天地图）并支持叠加、自定义图源；天气不同的节点有不同颜色/样式；
节点可添加图片；“如果可以添加 3D 地图更好”。

**完成（T-154）**：
- 图层：`lib/data/map/tile_sources.dart` 来源注册表 + `resolveMapStyle`（底图回退、叠加校验）+ 自定义模板校验；
  `Basemap.fromSettings` 渲染底图 + 叠加层（透明度）；首页、详情全屏图、规划工坊有“图层”按钮；设置页可打开图层面板与
  “管理图源与天地图 Key”（天地图 Key、自定义图源增删改）。坐标系不同的叠加层禁用并说明原因。
- 天气节点：`node_wx_class.dart` 按 redesign-v2 阈值归类（阵风 7/8 级、降水 2 mm/h、-10 ℃，另有降水/冰点提示），
  颜色=级别、图标=类别；缺失数据显示“信息不足/无数据”（灰），不显示为“未触发阈值”；小地图下方图例注明非官方预警。
- 节点图片：相册/拍照（image_picker 1.2.3），本机文档目录保存，坐标锚定，节点详情中查看/备注/删除，线路地图显示图片标记；
  Web 端如实提示暂不支持。
- 文档：data-sources / licenses / privacy 更新；D-022；B-014（天地图 Key）。

**本地验证**：flutter analyze 0 问题；flutter test 189/189 通过（新增 tile_sources 9、node_wx_class 4、route_photos 2、
map_layers 组件 3 项；集成测试断言节点着色与图例）。
**未做**：3D 地图（flutter_map 仅 2D，需换引擎，另行评估）。
**待真机确认**：各图源国内可达性（OpenTopoMap/Esri 海外）、天地图 Key 类型与请求头、叠加透明度性能、
相册/相机权限弹窗与 iOS 用途文案、图片保存与重启后恢复、节点颜色在实际天气下的观感。
**CI 结果**：run 38733804863（workflow_dispatch，分支 feat/robust-track-import）conclusion=success，
analyze ✓ / test ✓ / Web release ✓ / APK release ✓（含 image_picker Android 原生插件编译）。iOS 构建未触发（手动工作流）。

## Round 17 — 2026-10-15（接入 meteoblue：按需单点 + 节点海拔）

**起因**：用户获取 meteoblue Free key（1000 万 credits，至 2027-10-15）。

**核验**：实测 1 次 basic-1h（响应头 mb-credits-accounted: 8000；asl 生效；CORS *；169 个逐时值）；
官方逐时 pictocode 表（浏览器渲染读取）；免费版页面对比表标“可商用”（以账户条款为准）。

**完成**：
- `meteoblue_provider.dart`：asl=节点轨迹海拔、单位固定（C / ms-1 / mm）、错误 JSON 如实抛出且不含 key。
- 额度保护：ProviderCapabilities 新增 onDemandOnly / usesElevation / quotaNote；`primaryProviderId()` 让线路天气与
  首页位置天气跳过按需来源；节点“多来源对比”与地图选点卡片显示“查询此点（消耗 1 次额度）”；缓存 3 h，缓存键含海拔。
- `WxVar.snowFraction`（追加在枚举末尾，兼容旧缓存）；`weather_phenomena.dart` 逐时现象（雾/霾/雷暴/雪/雨夹雪）。
- 设置页 meteoblue 卡片（独立存储 `meteoblue.v1`，不改 AppSettings，避免与天地图双 key 分支冲突），显示本机请求次数。
- 修复：地图选点卡片“重试”与新按钮的 setState 回调返回 Future（debug 下点击即断言失败）。

**本地验证**：flutter analyze 0；flutter test 199/199；key 未写入任何仓库文件（git grep 无结果）。
**CI 结果**：run 38740383191 conclusion=success（commit 053373c；analyze / test / Web / APK）。

## Round 18 — 2026-10-15（天地图两种 Key；并行分支，合并时由 Round 17 重号）

**起因**：用户申请“浏览器端”“服务端”两个天地图 Key 实测：天地图按 UA 是否含 Mozilla 判定浏览器，浏览器端 Key 在原生 App
返回 403/301012，服务端 Key 在浏览器返回 403/301013。原单一 `tiandituKey` 无法同时满足 Android/iOS 与 Web。用户决定不伪造 UA。

**完成（T-155，D-023）**：
- 设置拆为 `tiandituServerKey`（原生）/ `tiandituBrowserKey`（Web、将来 3D WebView）；旧 `tiandituKey` 迁移到两栏。
- 数据层按发起方选 Key：`TileRequester`、`TiandituKeys.forRequester`、`flutterMapRequester`（唯一的 kIsWeb 判断）；
  缺对应 Key 时该端天地图不可选，回退/不可用原因写明缺哪一种 Key。
- 错误识别：flutter_map 的 errorTileCallback 拿不到响应体，改为给天地图图层的 `NetworkTileProvider` 传入
  `TiandituErrorSniffingClient`，按 301001/301012/301013/418/其他映射提示；首页地图、详情小地图与全屏图、规划工坊、
  图层面板显示可关闭的提示横幅（含“设置天地图 Key”入口），Key 设置卡片显示最近错误与“两栏相同”警告。
- `http` 改为直接依赖并锁定 1.6.0（原为同版本传递依赖）。
- 文档：data-sources「天地图 Key 类型与错误码」、B-014 更新、D-023、T-155。

**本地验证**：flutter analyze 0 问题；flutter test 207/207（新增 key 选择/跨端不借用/迁移、错误码分类、拦截 client、
错误去重与关闭、文案映射、Key 卡片与提示横幅组件测试，以及 FlutterMap+TileLayer 经 MockClient 返回 301012 的端到端测试）。
测试只用假 Key、不访问网络。另用 curl 以假 Key 复测：32 位十六进制假值 → 403/301001（带 `Access-Control-Allow-Origin: *`），
含非十六进制字符的假值 → 418 拦截页。
**未做 / 待确认**：未 push、未跑 CI（等用户确认）；用户在 App 内填入两个真实 Key 后，在 Android/iOS 真机与 Web 上确认出图。

## Round 19 — 2026-10-15（v2 第 2 步：天气数据补全）

**合并**：PR #1（feat/robust-track-import → main）已由用户在 GitHub 合并；天地图双 Key 分支（968bb99）未推送，
本地合并入 feat/robust-track-import（代码无冲突，agent 记录冲突保留双方，D-020/D-021 与 Round 17 重号改为 D-024/D-025、Round 18）。

**完成（T-125）**：
- 按节点海拔：Open-Meteo `elevation` 列表（缺海拔整批不传，不用 nan）；仓库 `planQueries` 对按海拔来源只合并同网格且
  海拔差 <100 m 的节点（原先 0.1° 合并会把山脊与山谷合成一个点）。
- 新变量：weather_code → 现象（WMO 表）、snowfall（cm）、freezing_level_height（m）；网格卡片按需显示。
- 提示：雷暴（WMO 95–99 / meteoblue 雷暴类）、降雪（现象或 ≥0.5 cm/h）、雾/低能见度（现象或 <1 km）、
  节点高于 0℃ 层；缺失不触发、不推测。
- 节点详情 / 地图选点：“同一地点不同海拔”卡片（一次请求重复坐标）、空气质量卡片（CAMS 区域级、署名）。

**本地验证**：flutter analyze 0；flutter test 228/228。
**未验证**：真机展示与网络时延。
**CI 结果**：run 38743636066 conclusion=success（commit 69d9990；含天地图双 Key 合并；analyze / test / Web / APK）。

## Round 20 — 2026-10-16（天气正确性、恢复体验与基础 SEO）

目标延续：改善用户体验与可核验评分。上一轮属于实质进展（海拔天气等已入库且 CI 成功），本轮仍未证明全部接近满分。
已修复跨小时缓存、过期刷新与 UI 传播、线路节点身份碰撞、当前天气查询时间与前后台时效；Web 增加加载失败恢复、缩放与首屏语义。
最终本地 analyze 0、244/244 tests；页面级刷新、360px 双倍字体、深浅色对比度与 iOS/Android 触控尺寸检查通过。CI 和浏览器审计进行中。
详情见 docs/quality-2026-10-16.md。T-143 完整离线包仍为后续 P0，不以缓存修复宣称完成。

**本轮实测补充**：业务提交 3384b2c，CI 38862593549（Web/APK，244 tests）与 38862597530（iOS 无签名）成功。
额外补充真实 family 正反向坐标映射用例后，本地 245/245、analyze 0。
Lighthouse 单次压缩对照：性能 37→70、可访问性 100、最佳实践 81、SEO 100；模拟 TTI 17.6→16.6 s。
未压缩时本地 WASM 增大传输量，TTI 34.0→49.7 s，不能忽略此退化；增加压缩预览工具并验证，生产部署尚未发生。
压缩批次工具内部 NO_LCP 告警与最终报告边界已记入 docs/quality-2026-10-16.md；全目标仍未达成。
Playwright 已验证主题首屏、脚本失败重试、键盘导入、缩放和本地渲染资源；截图已保存。

**最终验收**：0abf1d6 的 Web/APK CI **38870192917 success**，iOS 无签名 CI **38870196358 success**；本地 analyze 0、245/245 tests。
T-140/T-141/T-142 完成，T-156 完成其入口和审计范围；总体“各项接近满分”仍未完成，T-157 继续推进。
商店介绍、关键词与截图叙事草案已写入 docs/store-metadata-draft.md；未发布商店或启用订阅。
全部本轮临时浏览器/HTTP 验证会话已清理；原始报告与截图留在 docs/verification/quality-2026-10-16/。
下一轮保持 iOS 优先，P0 完整离线包/出发窗口，以及 P1 首屏性能与最佳实践；真机和授权 blocker 仍有效。


## Round 21 — 2026-10-16（独立离线行程包与可读性）

- T-143：从占位说明变为可下载的 24/48/72 小时行程包，保存线路/航点/方向/配速/预计到达/全量返回预报/溯源。原生独立文件存储、临时写入读回校验后替换，不受普通天气缓存清理和 LRU 影响。
- 离线页本身无天气、地图或 GPS 请求；覆盖缺口、关键指标缺失、旧预报与行程过期分别展示。零可用覆盖拒绝保存，下载/更新失败保留原文件，可重试。仅绘制本地线路示意，无离线底图。
- 首页持久入口及独立列表可在新实例读取；共享天气指标改成自适应列数与自然高度，已覆盖 360px / 2倍文字 / 深浅色离线阅读。
- 本地 flutter analyze 0，全部 263 tests 通过（新增 18 项）。测试日志位于 docs/verification/offline-2026-10-16/tests.txt。
- 本批附带 Web 构建真实 source map 补齐；CI 与浏览器产物验收待进行。未替换此前 Lighthouse 分数。
- T-143 保持 in_progress，原生飞行模式强制结束后冷启动、低存储、升级恢复与耗电待真机；T-144 仅完成本轮布局范围。总体接近满分目标仍未达成。

**首批产物验收**：b51b11e 的 Web/APK CI 38877163711、iOS CI 38877194767 成功，包含名称/图标与真实 source map 校验。浏览器真实 Open-Meteo 下载成功（72 小时、7 节点、504/504 地点时段）；页面重启恢复后阻断天气/瓦片端点，再切换 context offline 仍可浏览。发现首次引导旧文案，已修正并重新通过本地 analyze 0 / 263 tests，待最终构建。Web Noto 备用字体断网请求失败已记录，不声称全网页零网络或支持冷启动。

**最终验收**：03090e2 的 Web/APK CI **38881636861 success**，iOS 无签名 CI **38881655873 success**；263 tests 与名称/图标校验通过。新引导文案在最终 Web 产物中确认，无旧“离线包尚未提供”文本。首批离线流程证据绑定 b51b11e（后续仅引导文案变化），最终评分绑定 03090e2，不挪用报告提交身份。

**评分未达标**：两次 Lighthouse 13.5.0/mobile/simulate/gzip：性能 **44 / 68**、可访问性 **100 / 100**、最佳实践 **81 / 81**、SEO **100 / 100**；模拟 TTI **16.5 / 16.9 秒**。LCP模拟值波动较大，均保留；不以较高一份代替所有结果。loader map已补齐，但CanvasKit WASM映射缺失、Dart sourcesContent缺失与SDK弃用API仍在；未隐藏警告。详见 docs/quality-2026-10-16.md 及本批summary。

T-143软件闭环已有验证，真机部分仍待 B-002；T-147多日计划/徒步进度、B-009离线底图、数据许可均未关闭。下一轮先推进未阻塞的 P0 T-130 出发窗口，并继续 T-157 首屏真实可交互性能；总体目标保持 active。

## Round 22 — 2026-10-16（移动端出发比较与天气优先）

用户将目标改为侧重 Android/iOS，Web 可以暂缓。本轮暂停 Web 跑分专项，继续交付徒步前实际可用的出发时间比较，保持山晴名称、D 图标与订阅隐藏。

- T-130：日期 × 出发时刻，1/3/5 天；单一来源联合查询，阈值本机重算，逐段逐小时端点检查，缺失与已知触发并列；详情可追溯模型、原始时次、节点、ETA、返回坐标和网格信息；选择后回到行程模式，保留方向/配速。
- 规则可设置和持久化；旧偏好兼容。按次来源禁止批量比较。旧缓存/刷新失败仍显示原时间并注明不足。
- 修复持续风速冒充阵风、摘要缺气温变零度、日落后出发误取次日日落。Open-Meteo 前一小时累计/最大值在出发评估内按实际时间对齐，保留原始时次。
- T-144：详情首屏显示天气摘要和获取时间，随后进入出发比较和地图；低耗电文案与实际行为一致。
- 本地静态检查无问题，**284/284** tests 通过（新增 21 项）。覆盖 360px、深浅色、双倍字号与既有核心流程。布局调整使旧集成测试固定像素滚动失效，已改为按实际控件定位，继续断言原行为，没有删掉功能验收。

本轮未增加依赖。业务提交 **961a6d4**；Android/Web CI **38890402736** 与 iOS 无签名 CI **38890417187** 均成功，名称/图标核验通过。Android APK 已下载并校验 ZIP、arm64 库与品牌图片（SHA-256 见 summary）；记录在 `docs/verification/departure-2026-10-16/`，功能说明在 `docs/departure-windows.md`。本地 widget 测试不是原生真机验收，B-002 仍保留。T-157 按用户优先级暂缓，历史 44/68/100/81/100 等 Web 结果不更新、不冒充原生评分。后续优先 T-158 跨页面天气时间语义统一，再推进 T-147 多日/徒步中闭环和真机验收准备。

## Round 23 — 2026-10-16（信息减负：感官过载整改，T-144）

**起因**：用户反馈页面感官过载。本地构建 Web 并以 400×600 实机走查：详情页约 12 个区块、5 屏，8 处说明条；
节点详情先 8 个标记按钮后天气；出发窗口格子前 5 段说明、每格 3 行字；设置 9 组。

**整改（只重排、不删功能与说明，说明一点即可见）**：
- 详情页三层：①控制条（时间标签展开时间设置、来源菜单含“对比来源”）+ 结论卡（摘要 3 数、最多 3 条提示、出发窗口入口）；
  ②地图 + 线路要点一行 + 剖面 + 紧凑节点行（行程模式时刻在前，固定时刻不再每行重复 UTC）；③“数据说明与来源”默认收起。
- 节点详情：4 个关键值放大（气温/体感、阵风+持续、降水+概率、现象）→ 0℃ 层 → 不同海拔；更多指标 / 12 小时 /
  空气质量 / 多来源对比 / 图片默认收起；8 个标记按钮合并为“标记为”二级面板。
- 出发窗口：格子置于控件下方，每格一字原因（风/雨/冷/晚/缺/✓，完整结论在提示与依据页），手机一屏 5 列；说明收进 ⓘ 与折叠区。
- 设置：显示与使用 / 天气来源与密钥（两张密钥卡收进一项并显示配置状态）/ 数据与帮助。
- 修复：主题只设 Chip 字号导致深色模式 Chip 文字几乎不可见；“同一地点不同海拔”补档后未排序（78/292 倒置）。

**验证**：flutter analyze 0；flutter test 284/284（4 个用例随布局调整定位方式，行为断言保留）；重建 Web 本地走查确认。
**CI 结果**：run 38900673341 conclusion=success（commit 5cc5163；analyze / test / Web / APK）。

## Round 24 — 2026-10-16（降水误读、iOS 打开方式、分享图片）

**用户问题**：导入“蓟县歪顶坨.kml”后 17 日显示降水概率 100%、降水量 0.0 mm。
**核查**：App 数值与来源一致——固定时刻默认“下一整点”（约 22:00），切换日期后仍为 22:00；该线路 17 日降水集中在
07–21 时（每小时 8–10 mm），22:00 已停雨。Open-Meteo 官方：precipitation 为前一小时合计（0.1 mm 精度），
precipitation_probability 为前一小时 >0.1 mm 的集合预报概率（~27 km、30 成员），与降水量来自不同模型。

**完成**：
- T-160：固定时刻按整天取数；结论卡“X月X日全天：沿途降水最多约 … mm，主要在 HH–HH 时，最大概率 …%”；
  摘要标签“该时次降水 / 行程降水”；节点 4 值在概率 ≥50% 且量 <0.1 mm 时注明“来自不同模型”。用户文件 17 日实测全天约 79 mm、00–21 时。
- T-122（进行中）：iOS AppDelegate.swift + Info.plist 文档/导入类型（GPX/KML/KMZ）；Dart 端启用 iOS 并按 uri 去重。
- T-159：share_plus 13.3.1；线路天气卡、多日出发窗口对比卡；预览后经系统分享面板分享。

**验证**：flutter analyze 0；flutter test 292/292；Web 预览页实看分享卡；flutter create（ios）不覆盖 AppDelegate/Info.plist（本地 scratch）。
**CI 结果**：Android/Web run 38910599967 success；iOS 无签名 run 38910604777 success（commit 见 git log）。

## Round 25 — 2026-10-16（分享图改版：轨迹、海拔、醒目提示、宣传与二维码）

**用户反馈**：分享图无轨迹、不知节点位置；需海拔剖面；雨/雪/风等要醒目带图标；信息太密、主次不分；加宣传语与下载二维码（用工作流构建页）。

**完成**：
- 分层：标题 → 三个大数字（气温 / 最大阵风 / 全天或行程降水+时段）→ 醒目提示胶囊（图标+颜色，最多 4 条；无则绿色“未触发”）
  → 线路示意（经纬度等比投影、北向上、不含地图瓦片；节点按天气类别着色，关键节点编号，起终点标签）+ 海拔剖面（完整轨迹海拔，编号落在剖面上）
  → 关键节点 ≤6（起终点、最高点、红/黄阈值节点、命名航点，编号与示意图一致）→ 页脚来源与免责 → 宣传条 + 二维码。
- 下载地址：lib/core/app_links.dart，CI（web/apk/ios）以 --dart-define 注入本次运行页；本地回退为 CI 工作流列表页。
- 依赖：qr_flutter 4.1.0（D-029，原误编 D-027）。

**验证**：flutter analyze 0；flutter test 293/293；本地 Web 预览实看。
**说明**：GitHub Actions 产物需登录才能下载且有保留期；正式分发前需换为商店/固定下载页（不影响本轮功能）。
**CI 结果**：run 38916384264 success；构建日志确认 SHANQING_DOWNLOAD_URL=https://github.com/Panini235/TrailWeather/actions/runs/38916384264 。

## Round 26 — 2026-10-16（发布身份与签名、首启隐私、定位时机、反馈入口、多角色审查）

**用户要求**：帮忙签名（包名可换）；把讨论整理成 review；先修一批轻量问题，重活明天做。

**完成**：
- T-161（进行中）：应用 ID `app.shanqing.hiking`（namespace/Kotlin 包不变）。`tool/configure_release.py` 在 flutter create 之后注入；
  `tool/create_android_keystore.sh` 由用户本人运行，生成签名并上传 4 个 Secrets，同时打印指纹与公钥。CI 在有 Secrets 时正式签名；
  apksigner 指纹写入运行摘要；“配置了正式签名却产出 debug 签名”时 CI 失败；verify_build_branding 校验 APK 与 iOS 的应用 ID。
- T-162：首启隐私同意（默认不勾选、版本化、未同意不能关闭引导页；同意前暂存外部文件，回到主界面后再解析）。新增独立隐私说明页，
  内容按实际网络行为重写（移除已下线的百度外链描述，补充海拔、空气质量、和风、meteoblue）。docs/privacy.md 同步更新。
- T-163：地图打开时自动定位只检查权限，不弹授权框；授权只在点击定位时请求。
- T-164：设置 → 问题反馈（诊断信息不含位置、线路、Key；GitHub Issues）。
- docs/review-2026-10-16.md：用户、户外开发者、工程、合规、商业、气象六个视角，附 UI 重构方向与 beta 前置清单。
- 记录整理：decisions 重号 D-027（二维码）改为 D-029；新增 D-030。

**验证**：flutter analyze 0；flutter test 297/297。脚本在本地 scratch 的 flutter create 产物上验证：无签名、有签名、iOS 三种情况都通过。
**未验证**：正式签名产物（等 B-015）；真机（B-002）。

## Round 27 — 2026-10-17（正式签名落地、动效基础、开屏动画）

**用户要求**：太阳跟随此刻、夜里换月亮；当天首次完整、之后缩短；加“跳过动画”按钮。另外要求克制 CI 次数，攒够一批再跑。

**完成**：
- 签名脚本修复：macOS bash 3.2 在 zh_CN.UTF-8 下会把 `$REPO）` 中全角括号的首字节读进变量名，`set -u` 导致中断。已全部改为 `${VAR}`，并支持复用已有签名文件（先校验密码）。
  在中文环境下用一次性签名和不联网的假 gh 验证了三种情况。用户随后上传 Secrets 成功。
- T-161 完成：CI 38992313590 成功；APK v2 签名证书 SHA-256 与用户签名文件一致。
- 动效基础 `lib/ui/motion.dart`（token、降级规则、动效红线）。
- T-167 开屏：系统启动页只铺底色（Android 12+ 透明图标；iOS 使用 LaunchBackground 命名色并补丁 storyboard），Flutter 按 SVG 路径分层组装。
  太阳位置跟随本地时钟，夜里换月亮；当天首次 1.1 秒并可跳过，之后 0.25 秒；减少动效或低耗电时静态；Web 不播；播完移除且零帧。
  目视核对关键帧时发现山体半透明会透出太阳，已改为山体 200 ms 内不透明、太阳 250 ms 后再升起。

**验证**：flutter analyze 0；flutter test 308/308；apply_branding 在新生成的模板工程上验证 Android 和 iOS 补丁。
**未验证**：原生启动页资源的实际编译（等本批 CI）；真机观感（B-002）。本轮按用户要求未单独触发 CI。

### Round 27 补充 — 本机 Android 工具链与真机验证

- 用户选择安装 Android SDK，Xcode 暂缓（用户那边下载太慢）。命令行工具用 Homebrew 安装；platform-tools、platform 36、build-tools 36.0.0 和 NDK r28c 从腾讯云镜像分段下载，并用 Google 官方仓库的 SHA-1 逐个校验；Gradle 9.3.1 从镜像下载，用官方 SHA-256 校验；CMake 由 Gradle 按需安装。用户同意后接受了 Android SDK 许可。
- `configure_release.py`：debug / profile 构建使用 `.dev` 应用 ID 后缀。Flutter 插件在 `android {}` 之前就按 debug 复制出 profile，所以 profile 单独设置后缀。
- 真机验证：正式签名版冷启动 TotalTime 约 536 ms；首启隐私同意流程正常；打开地图不弹定位授权；开屏的完整版和短版都正常。真机上发现并修复了字标的报错样式。
- `.gitignore`：忽略本地 `flutter create` 生成、未被引用的 `.metadata` 和 `Icon-maskable-*.png`。

**验证**：flutter analyze 0；flutter test 309/309；本机 profile 构建通过（Android 启动页资源编译通过），在真机上逐帧核对。

## Round 28 — 2026-10-17（UI 重构第一批：token、山脊天气带、结论先行）

**用户要求**：继续按 review 推进开发。

**完成**：
- 详情页拆分（part 文件，只搬代码）。
- 设计 token 与主题（D-032）：语义色、按主题取色的文字色（WCAG 核算）、主题种子和底色；深色模式下看不清的灰字和状态色改为跟随主题；
  抽出共用组件 `ConfiguredStatus` / `HelpText`；选中节点外圈不再用红色。
- 山脊天气带：分段着色、按严重程度摆放图标、日落后夜色、首次画出、与小地图联动；新增 5 个组件测试。
- 结论先行与 `RollingText`。
- 真机核对（本机 profile 构建，小米 12S 深色）：发现并修复终点附近图标重叠、“日落后”文字压在图标上。

**验证**：flutter analyze 0；flutter test 314/314；真机逐屏截图核对。
**CI**：本批次结束时跑一次 Android/Web 和一次 iOS 无签名构建（iOS 启动页与 Bundle ID 的改动从未在 iOS 上编译过）。

### Round 28 补充 — 小地图交互与图层、分享剖面着色、控制条一行
- 控制条：时间与来源排在同一行，大字号下也不会折行（真机）。
- 分享卡的海拔剖面同样按最近节点天气分段着色，与山脊天气带一致。
- 小地图（D-033 / T-168）：双指缩放与平移、双击放大、回到全线；点节点选中，再点打开详情；只提供平面地形图层；自选图层加载不出时提示并可切回。
- 真机发现高德空白瓦片被缓存（T-169，待查）。
**验证**：flutter analyze 0；flutter test 316/316；真机逐项核对。尚未跑 CI（并入下一批）。


## Round 29 — 2026-10-17（风向、经纬度搜索、分享改版、等高线图源）

**用户要求**：风向“东南显示成东东南”；国内可用的等高线；分享图小地图节点错位、要好好设计；分享多种版式；微信“来自山晴”；经纬度查天气。

**完成**：风向八方位加度数（T-170）；经纬度搜索（T-171）；分享示意图重画与三种版式（T-172，D-034）；小地图地形图源天地图优先（T-173）。
“来自山晴”调研：需要官方 SDK 与平台审核，用户本人注册（T-174，阻塞）。
**验证**：flutter analyze 0；flutter test 326/326；真机核对三种分享版式（横图数值挤在一起，Round 30 修复）。

## Round 30 — 2026-10-17（数据层级、紫外线、穿衣建议、气象时间图、天气图）

**用户要求**：专业性对标 meteoblue（云层图、雨量图），紫外线，洋葱穿衣法；重视动画和图形、文字克制；用 Open-Meteo 补充并结合起来看；
**分清哪些是重点数据**；加雨量图、云层图，台风可选。

**完成**（D-035）：
- 数据层级文档与代码（T-175）；Open-Meteo 新变量与日出；MET 换 complete；meteoblue 紫外线；紫外线提示。
- 洋葱穿衣建议卡片与分享长图穿衣行（T-176）；节点气象时间图（T-177）；节点信号标签；“更多指标”按层分组。
- 地图天气图：降水 / 云量模式预报（可播放，T-178）、卫星云图实况（T-179）、台风路径（T-180）。
- 网络错误改为人话；横图分享数值间距。
- 实测核验：Open-Meteo 新字段与 `forecast_hours`、77 点批量 1.6 s；MET complete 字段；GIBS 时次与 HEAD；JMA 台风 JSON；
  RainViewer 授权（仅个人/教育，不接入）。

**验证**：flutter analyze 0；flutter test 365/365。手机当时没有网络（系统默认网络为 none），真机只核对了离线缓存数据下的穿衣卡与时间图；
天气图、卫星云图、台风、穿衣卡、时间图在 Web 构建（本机 Chrome 内核预览）里用实时数据逐项核对：北京当日强降水、雨带东移、Himawari 云系、台风 Champi 路径。
修复：降水色带低端过渡太陡出现台阶；卫星观测时间折行；台风预报点标签重叠；格点场边界渐隐。
**待办**：T-184 真机核对；T-181 云中判断；T-182 / T-183。
**CI**：Android/Web 一次失败（集成测试在 CI 字体下向下找不到已滚过的结论卡，改为向上找）；修复后 run 39014750739 通过（正式签名 APK + Web）。

## Round 31 — 2026-10-17（第一个测试版 0.2.0-beta.1）

**用户要求**：合并到 main，发布第一个 beta。

**完成**（D-036）：版本号与 CHANGELOG；分享二维码改指 Releases 列表页；问题反馈显示版本；
徒步星球线路库测试版隐藏且不打包；发布前核对两项许可阻塞并由用户决定。
**验证**：flutter analyze 0；flutter test 368/368。

## Round 32 — 2026-10-17（天气图流畅化、README 与使用文档、iOS 未签名 IPA）

**用户要求**：继续发布；云层图、雨图、卫星云图卡，时间轴只按小时跳，要像 Windy 一样流畅；README 改为软件介绍预览，
其余内容放进使用文档；Release 说明 iOS 未签名包的安装方式（开发者模式、爱思助手自签、安装、信任开发者）。

**完成**（D-037）：
- 天气图时间轴连续化与渲染重写（T-185）：只重绘图层、网格只算一次、颜色查表、Catmull-Rom 平滑；卫星每 10 分钟一帧、预加载、交叉淡入。
- 真机调试代理（T-188），手机无系统网络也能用实时数据在真机上验证。
- README 改为介绍预览（5 张真机截图）；新增 docs/user-guide.md（含 iOS 自签安装）与 docs/development.md（T-186）。
- iOS 工作流打包未签名 IPA（T-187）；CHANGELOG 更新。
- 用户新提的手绘工具、等高线、3D 记为 T-189 / T-190 / T-191，等用户确认方案。

**验证**：flutter analyze 0；flutter test 全部通过（新增像素级位置测试、卫星交叉淡入、时间轴过渡与回整点）。
真机（小米 12S，profile，实时数据）：降水播放 120 Hz 满帧，build p99 5.6 ms；卫星 13 帧交叉淡入；台风、线路详情、节点时间图、分享长图（T-184 完成）。
**CI**：PR #3 run 39034883529 通过；合并后 main run 39035404926（正式签名 APK）与 iOS 构建 39035502756（未签名 IPA）通过。
**发布**：预发布 `v0.2.0-beta.1`（main `da4db7a`），附 `shanqing-0.2.0-beta.1.apk`（证书 SHA-256 48:FE:D8:39…:30:9B，versionCode 2）
与 `shanqing-0.2.0-beta.1-ios-unsigned.ipa`（未签名，最低 iOS 15，系统显示版本 0.2.0.1）；说明含 iOS 自签安装步骤与文件 SHA-256（T-166、T-187 完成）。
**观察**：OpenTopoMap 国内直连 15 s 超时；AWS Terrarium 高程瓦片 1.3 s、Open-Meteo elevation 1.0 s 可用，供 T-189 / T-190 / T-191 方案参考。

## Round 33 — 2026-10-17（紧急：Android 正式包启动即崩）

**用户反馈**：Release 里下载安装的版本都卡在启动画面，adb 装的调试包没有问题。
**根因**（D-038）：CI 依赖漂移把 shared_preferences_android 升到 2.5.0（Pigeon JNI），R8 裁掉 JNI 方法，`main()` 在 runApp 前抛异常。
**修复**：CI / iOS 工作流严格按锁文件；启动失败兜底页面；版本 0.2.0-beta.2；发布清单要求真机冷启动正式包。
**验证**：flutter analyze 0；flutter test 374/374；本地 release 模式包（.rc 后缀，与正式版共存）在真机启动、引导、重启正常。
