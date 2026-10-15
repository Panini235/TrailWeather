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

## D-013 轨迹导入系统重构：容错清洗、自适应 RDP 抽稀与全格式扩展
- 放弃原有的 5,000 点和 2MB 硬上限：真实户外轨迹常包含万级密集打点，硬性拒绝严重伤害可用性，放宽至 30MB。
- 引入 `Geo.simplifyTrack`（自适应 Douglas-Peucker）：点数超过阈值（3,000 点）时自动抽稀，保留起点、终点以及最高/最低海拔极值点，保证高程与经纬度 1:1 对齐，并在 UI 中如实提示。
- 异常海拔容错清洗：遇到传感器漂移噪点（<-500m 或 >10000m）时置为 null 并提示警告，严格遵守“缺失值=null不编造”真实性红线，绝不因个别噪点使整条轨迹报错崩溃。
- 支持 KML 格式（奥维互动地图、两步路、Google Earth）：解析 LineString、MultiGeometry 与 gx:Track；文件选择器扩展至 gpx/kml/kmz/geojson/json/gsx；移动端配置 Intent-filter / Document Types 关联。

## D-014 融合 SpaceZephyr/trail-planet 徒步星球全球经典路线库
- 依据：SpaceZephyr/trail-planet 是开源的高质量全球经典徒步路线集（包含 TMB、冈仁波齐、EBC、虎跳峡等顶级神线），具备平滑海拔剖面与地貌标签，极大地弥补了初装冷启动时的优质路线匮乏。
- 实现：提取 44 条经典神线打包至本地资产 `assets/routes/planet_trails.json`（455KB），无需外部 API，离线即开即用；支持海拔高程线性插值与 8 大地形分类筛选。

## D-015 Trail Studio 线路规划工坊与 GPX/KML 双向导出
- 依据：参考两步路与奥维互动地图的手绘规划功能，满足户外领队与爱好者在行前自主画线、设计营地与打卡点、评估强度的需求。
- 核心功能：
  1. 触控打点画线与撤销重做（Undo Stack）；
  2. 航点系统：支持 6 类户外航点（营地、水源、险段、垭口、下撤点、打卡点）；
  3. 徒步耗时推演：采用平地 4.2 km/h 基准速度计算预计徒步耗时；
  4. 一键联动天气：保存后作为用户规划线路自动加入收藏，并立即跳转详情页推演沿途未来 7 天微气候；
  5. 互通导出：实现 `RouteExporter`，支持一键导出为标准 GPX 1.1 与 KML 2.2，可无缝粘贴导入两步路、奥维或佳明手表。

## D-016 海明商业化转化体系与 Pro 会员服务闭环架构
- 依据：深度落实海明Dev商业转化方法论（HammingDev/haiming-app-monetization），构建“痛点问诊唤醒 → 反差对比感知 → 功能赋能演示 → 付费墙引导”全流程，提升产品独特商业价值与付费订阅转化率。
- 架构设计：
  1. 会员层级模型 (`lib/data/monetization/subscription_models.dart`)：Free / Pro；定义年度套餐（主推，享 7 天免费试用，¥98/年）、月度套餐（¥18/月）、终身买断（¥198 一次性）。
  2. 痛点引导问诊 (`lib/ui/onboarding/onboarding_screen.dart`)：
     - Step 1: 场景问诊（重装长线/单日登山/露营越野/溯溪穿越），激发定制化心理；
     - Step 2: 价值反差（城市天气预报 vs 空间微气候实况：山脚 22℃ 晴 vs 垭口 4℃ 强风暴雨，失温风险巨大），直击用户核心安全痛点；
     - Step 3: 核心功能演示（全球 44 条顶级神线 + 路线规划工坊 + 双向 GPX/KML 导出）；
     - Step 4: Pro 免费试用引导（7 天免费试用，先尝后买，支持安全跳过）。
  3. 专业级付费墙 (`lib/ui/paywall/paywall_screen.dart`)：
     - 清晰展示 4 项核心特权对比（高程垂直递减修正、失温极端哨兵、离网轨迹气象包、等高线专业地形）；
     - 默认选中最具性价比与转化率的「年度会员」，突出「7 天免费试用」与免费取消承诺；
     - 支持「终身买断」满足国内不喜订阅用户的诉求；
     - 提供恢复购买与优雅退出，不产生强行硬卡死。
  4. 实际商业权益落地：
     - 在路线详情页提供「高程垂直递减率修正开关」与指示；
     - 提供「离网离线气象与轨迹包」下载；
     - 设置页展示专属 Pro 尊享卡片与一键续费/升级入口。



## D-017 KMZ 解压依赖与 Pro 真实性整改
- `archive` 精确锁定 4.3.0（2026-09-13 发布，>2 周）：已是 flutter_map→proj4dart→mgrs_dart→unicode
  的传递依赖，直接声明不新增代码面；主库纯 Dart、Web 可用（io 部分条件导入）。
- 移动端文件选择器不按扩展名过滤、改为内容嗅探：Android MimeTypeMap 无 gpx、iOS 需 UTI，
  扩展名过滤在移动端不可靠。
- 支付：未接入商店内购与验单前 `Billing.available=false`，purchase 抛错、不授予 Pro；
  修订 D-016 中“已落地”的 Pro 权益为“开发中”。真实支付接入为需授权事项（B-008）。

## D-018 定位参数与无效入口降级
- 定位：Android 强制 LocationManager（`AndroidSettings.forceLocationManager`），精度 medium、
  timeLimit 30s；先用上次已知位置居中，新位置失败退回上次已知位置并标注。无新增依赖（geolocator 14.1.1
  已导出 AndroidSettings）。
- 首页定位成功不再自动弹出天气面板、不自动请求 Overpass，改为地图上的小标签。
- Overpass 区域搜索与外部攻略（百度 site: 搜索）国内可用性差：从主界面降级为次要入口（线路列表底部、
  搜索结果折叠项），保留代码与测试，待产品方向确认后再决定去留。

## D-019 v2 改版：轨迹天气窗口
- 详见 docs/redesign-v2.md。首页“我的行程”，地图降为次要；移除百度外部搜索（不能产出可导入轨迹、质量不可控）。
- 接收外部文件选择自写 MethodChannel（Android MainActivity.kt）而非新增插件：零新依赖、逻辑仅 ~100 行、
  可被 CI APK 构建编译验证；Kotlin 文件提交入库，`flutter create` 不覆盖已存在文件（已验证）。
- intent-filter 去掉 BROWSABLE 与 `*/*`，改为明确 MIME 列表（含 octet-stream，因微信常以此传 GPX）。

## D-020 分析路径串联多段 + 航点即节点
- 多日导出常为首尾相接的多段：≤1 km 串联（间隙按直线计入里程，近似），段起点保留为分天候选（第 3 步用）。
- 航点吸附到线路（≤300 m）后作为必选采样节点：营地/休息点处一定查天气；偏离的航点只在地图半透明显示。
- 反向行走为视图状态（不改存储）；标记修改的是原方向线路并保存到“我的行程”。

