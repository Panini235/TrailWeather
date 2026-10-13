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
