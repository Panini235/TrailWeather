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

## D-024 分析路径串联多段 + 航点即节点（原编号 D-020，与并行会话重号后改）
- 多日导出常为首尾相接的多段：≤1 km 串联（间隙按直线计入里程，近似），段起点保留为分天候选（第 3 步用）。
- 航点吸附到线路（≤300 m）后作为必选采样节点：营地/休息点处一定查天气；偏离的航点只在地图半透明显示。
- 反向行走为视图状态（不改存储）；标记修改的是原方向线路并保存到“我的行程”。



## D-020 iOS优先，先产品后订阅（2026-10-15用户决定）

- 开发者为个人；iOS优先，Android兼容；Web暂停作为公开产品的研发发布目标，保留现有验证通道。
- 当前免注册、不展示订阅；移除设置会员卡/入口、PRO算法占位和首次付费引导；旧/paywall路径回首页。订阅后台与支付任务只有在用户明确重启后推进。
- 未来按低频徒步使用周期先验证不自动续费的行程通行证，候选7天¥6–12；高频年费¥48–68仅为待测假设；不承诺永久在线服务。
- 采用用户指定haiming-app-monetization技能，强调先体验真实价值；用导入/示例入口替代没有实际配置作用的问卷与营销演示。
- 线路库公开不等于MIT；已纠正sourceLicense，但分发授权仍受阻。地图/天气服务授权按具体用途核对，隐藏收费不能自动解除授权义务。
- 生成6组原创矢量品牌候选，推荐“山晴｜徒步天气”；名称与正式图标替换等待用户选定和重名核验。


## D-021 正式名称“山晴”与D图标（2026-10-15用户确认）

- 用户确认“山晴这个名字可以，图标用第四个”，采用D（日出叠山、沙色）而非原推荐A。显示名严格为“山晴”。
- 应用标题、原生显示名、文件打开提示、引导页、导出标识和Web验证入口同步更新；内部包名、存储键和安装身份保持兼容。
- 原生图标放assets/branding/platforms，CI的flutter create之后用Python标准库脚本覆盖并验证，继续不提交完整平台模板。
- 增加产物品牌校验，确认APK与iOS包内名称和图标资源；不新增Flutter依赖，不启用订阅，不发布商店。

## D-022 地图图层体系、节点图片依赖（2026-10-15）
- `BasemapSource` 枚举改为来源注册表 + `baseLayerId`/`overlayLayers`/`customTileSources`/`tiandituKey`；
  旧设置 `basemap: amap|osm` 与新 id 同名，直接迁移。
- 叠加层必须与底图同坐标系，否则不渲染（不做逐瓦片重投影；GCJ-02 是非线性偏移，栅格无法精确纠偏）。
- 节点图片按坐标锚定（不按节点序号），因为采样间距/反向行走会重算节点；详情中 60 m 内视为该节点图片。
- 新依赖：`image_picker` 精确锁定 1.2.3（flutter.dev 官方，2026-06-30 发布；1.2.4 于 2026-10-06 发布不足 2 周，
  未采用），Android/iOS/Web 均有官方实现；`path_provider` 2.1.6 由传递依赖改为直接依赖（Web 走条件导入不调用）。
  iOS Info.plist 增加相册/相机用途说明。
- 3D 地图不在本轮：flutter_map 仅 2D 栅格，3D 需 MapLibre/Cesium 等引擎与 DEM 数据授权，需单独评估。

## D-025 meteoblue 作为按需单点来源（原编号 D-021，重号后改）
- 8000 credits/次、免费额度约 1,250 次/年，且无多点批量：若参与线路自动请求（24 节点）约 50 次查看即耗尽 → 只按需单点。
- 按节点轨迹海拔传 asl：这是“同一地点不同海拔”的来源侧修正，比本应用自行套用递减率更可信；溯源中标注“来源按海拔修正”。
- 密钥独立存储（meteoblue.v1）：额度计数频繁变化，且避免与并行的天地图双 key 改动冲突。


## D-023 天地图按请求发起方用两种 Key（2026-10-15）
- 依据：用户申请“浏览器端”“服务端”两个 Key 实测，天地图按 UA 是否含 `Mozilla` 判定浏览器，再校验 Key 类型
  （301012/301013，详见 docs/data-sources.md「天地图 Key 类型与错误码」）。用户决定不伪造浏览器 UA 绕过类型校验。
- 设置 `tiandituKey` 拆为 `tiandituServerKey`（Android/iOS 原生 flutter_map）与 `tiandituBrowserKey`（Web、将来 3D WebView）。
  选择逻辑在数据层：`TileRequester` + `TiandituKeys.forRequester`；`flutterMapRequester = kIsWeb ? browser : nativeApp`
  是唯一的平台判断。`resolveMapStyle` / `overlayBlockReason` 改为接收两种 Key 与发起方；缺对应 Key 时该端不可选，
  不借用另一端的 Key（必然 403）。
- 旧值迁移：旧版只有一个 Key，类型只在天地图服务端可知，离线无法判断。迁移时**两栏都填旧值**：原本能出图的一端不受影响
  （只迁到一栏会让另一半用户直接退化）；另一端会收到 301012/301013，地图上按错误码提示该改哪一栏，设置卡片也提示
  “两栏相同”。新字段存在时忽略旧字段；保存后不再写出 `tiandituKey`。
- 错误提示：flutter_map 8.3.2 的 `errorTileCallback` 只拿到 `NetworkImageLoadException`（状态码 + URL），拿不到响应体。
  `NetworkTileProvider` 支持外部传入 `httpClient`，因此天地图图层传入 `TiandituErrorSniffingClient`（包装 `RetryClient(Client())`，
  与 flutter_map 默认 client 相同）：只在天地图域名 ≥400 的响应上读取响应体并分类，再把相同字节交回 flutter_map；
  其余响应流式透传。外部传入的 client 不会被 TileLayer 关闭，由 `tiandituTileClientProvider` 统一持有。
  所以不需要退回“只提示加载失败”的方案。限制：断网等没有响应的失败不归为 Key 问题，不提示；Web 端依赖 403 响应的
  `Access-Control-Allow-Origin: *`（已复测存在）。
- 依赖：`http` 由传递依赖改为直接依赖，精确锁定 1.6.0（pub.dev 最新版，2025-11-10 发布；dart-lang 官方包，三端可用；
  与 flutter_map 8.3.2 要求的 `^1.5.0` 及 lock 中版本一致，lock 只把依赖类型改为 direct main，不新增代码面）。

## D-026 天气刷新流与质量评分边界（2026-10-16）
- 天气页面使用结果流：缓存、刷新成功、失败保留缓存三种状态可在同一页面传播。一次性调用等待最终结果。
- v3 缓存继续可读；只按相同来源/坐标顺序/海拔复用真实覆盖时段。不把近似网格当作跨请求缓存身份。
- 精确请求的来源覆盖限制可以缓存，避免计费来源因缺时段反复调用；仍显示覆盖不全。
- 当前位置的定位时间不再用作天气查询时间。前台定时检查与恢复刷新不自动追加定位或计费来源请求。
- Web 放开缩放并主动提供语义；加载/失败状态来自真实启动生命周期。工具分数与原生真机体验分别记录，不自评“满分”。
- 没有新增 Flutter 依赖；临时目录安装 Lighthouse 13.5.0 用于测量，不进入应用依赖。

## D-027 基础离线行程包与下载失败保护（2026-10-16）
- 独立于 CacheStore 存储；原生使用应用文档目录下的文件，临时写入读回核对后原子替换；Web 使用独立键并说明不保证网页断网冷启动。
- 复用与 v3 缓存兼容的 WeatherCodec，保存完整来源返回与原始溯源。包内 CRC32/长度用于意外损坏检测，不宣称密码学认证。
- 路线、方向、航点、节点映射、配速/预计到达、请求窗口作为快照保存；离线页零天气请求、零地图瓦片请求。底图和照片未打包。
- 缺口可部分保存并明确展示；零有效覆盖不保存；更新失败或可用时段减少不覆盖旧包；按原始获取时间显示旧预报。
- 来源先限 Open-Meteo / MET Norway；未复核离线权限的其他来源及按次计费源不批量下载。不重启订阅、不改变授权 blocker。
- 无新增 Flutter 依赖；CRC32 使用仓库已声明的 archive 4.3.0（已核对本地公开 API），文件目录使用已声明的 path_provider。
- Web CI 启用真实编译器 source maps，并复制同一 SDK 的 loader map；检查 bootstrap 前缀一致性，绝不合成映射或隐藏弃用警告来提高评分。

## D-028 原生优先与出发窗口（2026-10-16）
- 用户本轮将目标调整为侧重 Android/iOS，Web 可暂缓。暂停 T-157 的 Web 跑分专项；现有 CI 的 Web 构建暂保留为共享 UI 的辅助验证，不再以其分数衡量原生体验。
- T-130 按单日、单一来源、日期 × 出发时刻实现，保持订阅隐藏和无需账号。一个联合天气窗供所有格子本地计算；改阈值不重建天气服务，按次来源不进入此流程。
- 逐路段检查经过小时的两端，包含航点停留；气温、阵风、降水独立判断，缺失不替代。保留已知触发项和缺口两个维度。
- 按 Open-Meteo 官方字段语义对齐降水/阵风的前一小时时段，并保留原始时次。终点日落用经度近似归属出发日期，避免只取 nextSunsetAfter 导致日落后出发误取明天。
- 多日拆分、实际日出/山体遮挡、官方预警和原生真机性能仍未完成。不将局部测试通过或构建成功表述为全软件满分。本轮无新增依赖。

## D-026 分享图片依赖与卡片原则（2026-10-16）
- share_plus 精确锁定 13.3.1（2026-10-01 发布，≥2 周；Dart ≥3.10 / Flutter ≥3.38.1；fluttercommunity 维护；
  Android 自带 FileProvider，不改已提交 manifest）。新增传递依赖仅 share_plus_platform_interface 7.2.0。
- 分享的是专门排版的卡片而非截图：不含地图瓦片（避免瓦片授权进入图片），必含来源、获取时间、非实测/非安全评分说明。
- iOS 打开方式：沿用 Android 的 MethodChannel 协议，AppDelegate 在安全作用域内复制到临时目录后交给 Dart；
  冷启动经 getInitialFile 取，运行中经 onFile 推送，Dart 确认后清 pending，Dart 端按 uri 去重。

## D-029 分享图二维码与下载地址（2026-10-16；原误编为 D-027，与离线行程包重号）
- qr_flutter 精确锁定 4.1.0（2023-05 发布、pub 150/160、六平台、纯 Dart 绘制；传递依赖 qr 3.0.2）。
- 下载地址编译期注入（SHANQING_DOWNLOAD_URL = 本次 Actions 运行页），因“每次构建地址不同”只能在构建时确定；
  本地构建回退为工作流列表页。Actions 产物需登录下载、默认保留期有限，正式分发前替换为商店或固定下载页。
- 分享图的轨迹为矢量示意（不含地图瓦片），避免把瓦片授权带进外发图片。

## D-030 发布身份、正式签名与首启隐私（2026-10-16）
- 应用 ID 改为 `app.shanqing.hiking`（Android applicationId 与 iOS Bundle ID）。namespace 与 Kotlin 包路径保持
  `dev.trailweather.trailweather`，因此已提交的 MainActivity.kt、`flutter create --org dev.trailweather` 都不用动。
  改动在 `flutter create` 之后由 `tool/configure_release.py` 注入，CI 用 `verify_build_branding.py` 校验产物。
  旧包名的测试安装与新包是两个独立 App，本机数据不会迁移。
- 正式签名：签名文件与密码只由用户本人生成和保管（`tool/create_android_keystore.sh`：PKCS12、RSA 2048、有效期 10000 天，
  上传 4 个 GitHub Secrets，打印 SHA-1/SHA-256/MD5 与公钥供备案）。CI 把签名文件解码到 RUNNER_TEMP，密码只在 APK 构建步骤以环境变量提供，
  Gradle 运行时读取，不写入文件。没有 Secrets 时退回 debug 签名，运行摘要中标注。用 apksigner（而非 keytool -printcert，
  后者读不到 v2/v3 签名）记录证书；配置了正式签名却产出 debug 签名时 CI 失败。
- 首启隐私：`AppSettings.privacyAcceptedVersion` 记录已同意的版本；内容有实质变化时提升 `privacyNoticeVersion`，老用户会再次确认。
  同意项默认不勾选，未同意前引导页不能返回关闭。外部传入的文件暂存，等用户同意并回到主界面（依赖 ModalRoute.isCurrent）后再解析，
  避免确认框挂在即将移除的引导页上。
- 定位授权时机：`LocationService.currentPosition(requestPermission: false)` 只检查权限。地图打开时的自动定位走这条路径，失败时静默；
  系统授权只在用户点击“定位”时请求。
- 反馈：GitHub Issues 加上手动复制的诊断信息（不含位置、线路或 Key）。不接入崩溃上报 SDK，是否接入留待 beta 反馈后决定。
- 无新增依赖（使用已声明的 url_launcher）。

## D-031 动效规则与开屏动画（2026-10-17）
- 动效原则（`lib/ui/motion.dart`）：只在状态变化或手势时动，静止时不画帧，不用无限循环动画。系统减少动效或 App 低耗电时降级为终态。
  动效不能伪造数据：数值不从 0 计数上来，预报不配“实时”呼吸灯，加载不显示编造的进度，“适合出发”不配庆祝动画。
  Token：120 / 200 / 320 / 600 ms，进入用 easeOutCubic，退出用 easeInCubic。不引入 Lottie 或 Rive。
- 开屏：系统启动页只铺品牌底色（Android 12+ 透明图标，iOS 使用命名颜色），由 Flutter 首帧接着绘制，避免白屏和图标跳变。
  图标按 SVG 原路径分层绘制，太阳位置跟随设备本地时钟，夜里换成月亮。用户 2026-10-17 选定：当天第一次完整播放（约 1.1 秒，有“跳过动画”按钮），
  之后当天再启动缩短为 0.25 秒淡入；减少动效或低耗电时静态；Web 不播。开屏盖在路由之上，首页同时在下面加载，播完从树上移除。
  播完整版的日期记在 SharedPreferences 的 `splash.lastFullDay`。
- 测试要求：开屏结束后 `transientCallbackCount == 0` 且没有待调度的帧，并断言各模式的总时长上限。无新增依赖。
- 附：签名别名 `shanqing` 存在 Secret 里，GitHub 会把日志中所有 “shanqing” 打码（例如 `app.***.hiking`），只影响日志显示。

## D-032 设计 token、山脊天气带与结论先行（2026-10-17）
- `lib/ui/tokens.dart` 是颜色的唯一来源。品牌色取自“观山”图标；语义标记色（danger / caution / go / cold / ice / unknown / route）
  深浅主题共用，因为地图底图始终是浅色；文字使用 `SemanticInk`，按主题取色，用 WCAG 公式核算：浅底 ≥5.7:1，深底 ≥7.7:1。
  主题以图标松绿为种子，浅色底 paper、深色底 ink，与开屏衔接。灰色说明文字改用 `onSurfaceVariant`（`HelpText`），修正深色模式下看不清。
  航点的分类色保留；付费墙页面隐藏中，未改。
- 详情页 1889 行拆成 part 文件（只搬代码），主文件 882 行。
- 山脊天气带（`lib/ui/detail/ridge_band.dart`）取代原来的单色剖面，放在结论卡下方：
  完整轨迹海拔画轮廓；山脊线按“最近节点”的天气分类分段着色（节点之间不插值，和地图标记用同一套颜色）；
  触发提示的节点画图标，按严重程度摆放，避免重叠；行程模式下日落后到达的路段铺夜色；无海拔时画平线并注明。
  首次拿到数据时画出一次（600 ms），之后切换时间或来源不重播；减少动效或低耗电时直接显示；点击选中最近节点，与小地图联动。
- 结论先行：卡片顶部是按级别排第一的提示及“等 N 项”；未触发时如实写“这不代表安全”，不写“适合出发”。
  三个数值用 `RollingText` 滑动切换：只在新旧两个真实值之间过渡，不做数字插值计数。
- 小地图选中外圈从红色改为松绿：红色只表示红色阈值。

