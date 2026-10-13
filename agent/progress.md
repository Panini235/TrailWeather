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
