# 决策记录（ADR 简版）

## D-001 地图方案：flutter_map（否决 maplibre_gl）
- 依据：flutter_map 8.3 纯 Dart，三端一致、瓦片供应商解耦、维护活跃（pub.dev/官方文档核验
  2026-10-13）；maplibre_gl Web 支持为 JS 桥接，体验与维护风险高。
- 影响：无 3D/矢量样式；对产品需求（线路+节点+命中）足够。

## D-002 平台目录：CI 内 flutter create 生成，仓库仅存定制文件
- 依据：手写 gradle/Xcode 模板与 pin 的 Flutter 版本易错配；flutter create 幂等不覆盖
  已存在文件；本地无 SDK 无法验证模板。
- 风险：flutter create 可能生成 test/widget_test.dart —— 已提交自有版本覆盖。

## D-003 批量 push 策略（降低 workflow 次数）
- 一次性实现 M0–M3 核心再推送；CI concurrency cancel-in-progress 防止排队浪费。

## D-004 Riverpod 3 经典 API（Provider/FutureProvider/Notifier）
- 避开 v3 legacy（StateNotifier 等）；全部用 v3 核心 API，降低升级面。

## D-005 时间解释：设备本地时区（A-001）
- 无离线坐标→时区映射；geocoding 的 IANA 时区仅展示。UTC 内部运算。

## D-006 MET Norway Web 端：保留尝试 + 如实标注，不做网关
- 浏览器禁自定义 UA，其条款要求标识。直连可能失败 → UI 显示来源错误（诚实）。
  不为单一来源加后端。

## D-007 近似网格去重 0.1°（请求策略，非分辨率声明）
- 来源无稳定网格标识；合并仅减少请求，UI 声明“共享同一网格预报”。
- 若来源未来提供网格 ID，改用其官方标识（任务挂起，见 tasks）。

## D-008 演示线路自制（不用 OSM 数据当示例）
- 避免 ODbL 边界争议与“看似真实”的误导；演示几何明确标注。

## D-009 缓存基于 shared_preferences
- 三端一致；Web localStorage 容量有限（~5MB）→ 条目上限 + LRU；重缓存场景未来换
  IndexedDB/文件（任务挂起）。

## D-010 单位换算在适配器内完成（km/h→m/s）
- 内部标准 m/s；发现于契约测试设计时（Open-Meteo 返回 km/h）。
