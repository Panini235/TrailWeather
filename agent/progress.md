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
