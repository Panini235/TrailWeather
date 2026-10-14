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


## D-011 第三方线路平台：不逆向目录，优先开放数据与用户导入
- 两步路、六只脚本轮未核验到面向第三方 App 的公开线路目录 API 和明确商用再分发授权；
  不把公开网页等同于 API，不用爬虫或私人接口支撑生产功能。
- 奥维官方第三方接口面向 Windows 客户端，通过消息/WebSocket 读写当前用户收藏夹对象，
  不是公共线路目录，也不能直接覆盖 Flutter Android/iOS/Web。
- 当前用 OSM 正式徒步路线 + 具名路径段提升覆盖，并继续支持 GPX/GeoJSON；未来只在拿到
  正式 SDK/API、用户授权和商用条款后接第三方账号或深链导入。


## D-012 混合线路搜索：可分析数据与外部线索分层
- 搜索结果分为：本地/已加载线路（有几何，可直接分析）、地点候选（再查附近 OSM）、
  外部攻略与轨迹线索（用户主动打开浏览器）、合法轨迹导入。
- 小红书/两步路/六只脚入口使用百度 `site:` 限定 HTTPS 查询；不嵌入 WebView、不读取 Cookie、
  不抓取/解析/缓存结果内容。原因：网页可访问不等于拥有程序化抽取与商用再分发权。
- `url_launcher` 精确锁定 6.3.3，官方 flutter.dev 包，覆盖 Android/iOS/Web；通过可注入
  `ExternalUrlLauncher` 测试边界，避免组件测试真的打开浏览器。
- 真正线路目录下一阶段优先评测自建 Waymarked Trails/OSM；路线生成另行评测
  openrouteservice `foot-hiking` 与 GraphHopper `hike`，不把规划器冒充热门线路库。
