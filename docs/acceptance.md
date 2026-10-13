# 验收矩阵

状态：✅ 已实现且验证｜🟡 已实现、验证待 CI/人工｜⬜ 未实现｜🚫 受阻。
验证证据：CI = GitHub Actions run；测试文件 = 仓库内自动化测试。

## 三、数据真实性（P0）

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| 请求坐标/返回坐标/分辨率/数据类型强制区分 | ✅ | `WxProvenance` 模型；test/weather/provider_contract_test.dart 断言 requestLat≠returnedLat |
| 缺失值显示“此来源未提供”，不为 0 | ✅ | weather_cells.dart MissingValue；契约测试断言 null 保持 |
| 降水概率与降水量分开 | ✅ | WxVar 独立键；risk_rules_test.dart「不等于」断言 |
| 阵风与持续风速分开 | ✅ | 同上 |
| “当前”数据明确类型（观测/估计/预报/趋势） | ✅ | WxDataKind + DataKindChip UI |
| 城市级数据不冒充点位 | ✅ | granularityStatement 文案 + 组件测试 |
| 同网格多节点不制造虚假差异 | ✅ | 近似网格合并 + sharedGridNote；weather_repository_test.dart |
| 多来源不默认平均 | ✅ | 每来源独立卡片，无平均逻辑（代码审查） |
| 模型重叠说明 | ✅ | caps.modelOverlapNote + UI 展示 |
| 官方预警未接入标注“未接入” | ✅ | officialAlertsNotAvailable + 集成测试断言 |
| 演示数据永久标注 | ✅ | DemoBadge + 集成测试断言 |
| 原始响应追踪不含坐标 | ✅ | WxHttp 异常仅端点+状态码 |

## 四、来源与时间窗口

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| WeatherProvider 抽象+能力声明 | ✅ | weather_provider.dart |
| ≥2 真实来源适配器 | ✅ | Open-Meteo（2 模型）+ MET Norway；不复制同一数据冒充 |
| 日常 CI 用 fixture 契约测试 | ✅ | test/weather/（不联网） |
| 真实联网 smoke 独立手动 | 🟡 | .github/workflows/live-smoke.yml（待手动触发留档） |
| 超 30 天/超 horizon 显示“此来源暂无该日期数据” | ✅ | WxOutOfRange + 详情页卡片；契约测试 |
| 不外推/不用历史均值 | ✅ | 无相关代码路径（代码审查） |
| 远期趋势产品 | ⬜ | 未接入（诚实：不显示趋势，任务 T-310） |
| 来源 Web 限制标注 | ✅ | MET User-Agent 说明 |

## 五、线路天气算法

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| 固定时刻模式 | ✅ | detail_state.dart + UI |
| 行程模式（出发时间+配速+休息） | ✅ | eta.dart + 单测（跨午夜/DST 安全由 UTC 运算保证） |
| ETA 标注为估算 | ✅ | 文案 + 假设展示（pace.assumptionNotes） |
| 采样含起终点/高点、间距可配、上限 | ✅ | route_sampling.dart + 单测 |
| 不为每个顶点请求 | ✅ | 采样+近似网格去重；repository 测试 |
| 采样密度≠空间精度声明 | ✅ | UI 文案 + assumptions A-002 |
| 海拔区分轨迹/来源模型地形 | ✅ | 节点海拔 vs provenance.elevationUsedM 分别展示 |
| 不用固定递减率制造山顶天气 | ✅ | 无海拔修正实现（未做=未伪造） |
| 摘要按选定来源、不跨源拼接 | ✅ | summarizeRows 单来源 |
| 关键数据缺失→“信息不足” | ✅ | risk_rules insufficient 分支 + 单测 |

## 六、地图与线路数据

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| 地图/线路/底图解耦 | ✅ | 架构分层（docs/architecture.md） |
| 三端一致的地图方案 | ✅ flutter_map 纯 Dart | CI web+apk 构建 |
| viewport+缩放获取、防抖、限制 | ✅ | 本地线路 bbox 过滤；Overpass 按需+跨度限制（单测） |
| OSM 关系多段/不连通正确处理 | ✅ | assembleSegments 单测（不连直线） |
| 不把普通道路标为徒步路线 | ✅ | 仅 relation[route=hiking] 查询 |
| 不声称路线可通行 | ✅ | 授权说明文案 |
| GPX/GeoJSON 导入+限制+校验 | ✅ | gpx/geojson_import + 单测（大小/点数/范围/损坏） |
| 瓦片不预下载 | ✅ | 无离线瓦片代码 |
| 署名展示 | ✅ | 地图页脚 + 设置页 |

## 七、跨端架构

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| Riverpod/go_router/可取消 HTTP | ✅ | dio CancelToken（详情页 autoDispose invalidate） |
| 缓存四命名空间+TTL+SWR+旧数据标记 | ✅ | CacheStore + StaleDataBanner |
| 缓存键含来源/网格/时间窗/参数版本 | ✅ | weather_repository._cacheKey + 单测 |
| Web 真实请求能力 | 🟡 | CORS 核验（data-sources.md）；端到端待人工开浏览器验证 |
| 无重型后端 | ✅ | 直连公开 API |

## 八、低耗电与流畅

| 要求 | 状态 | 证据 |
| --- | --- | --- |
| 默认无后台定位 | ✅ | 仅按钮触发 geolocator 一次 |
| 拖动期间不请求天气 | ✅ | 架构：选中才拉取 |
| 去重/取消/退避/有限并发 | ✅ | WxHttp 退避 + 近似网格合并 + 串行限速 |
| 429 不规避配额 | ✅ | 退避重试，无换端点绕过（Overpass 镜像轮换针对 5xx/504 过载，非配额规避） |
| 滑块预览已加载数据 | ✅ | onChanged 只更新预览状态，onChangeEnd 提交 |
| 缩放简化显示、保留原始几何计算 | ✅ | Geo.simplify 仅用于渲染 |
| 低耗电模式 | ✅ | 设置开关（采样加倍、节点减半，UI 说明） |
| 真机耗电测试 | 🚫 | 无真机；协议已定义（performance.md），标记未验证 |

## 十一、测试与构建

| 项 | 状态 | 证据 |
| --- | --- | --- |
| 单元（geo/units/eta/sampling/risk/cache/gpx/geojson/overpass） | ✅ | test/unit/ |
| 来源契约（正常/空/字段变化/点数不符/超范围/损坏） | ✅ | test/weather/ |
| 组件（缺失值/演示/颗粒度/过期/错误） | ✅ | test/widget/ |
| 集成（选线→详情→时间→收藏→恢复） | ✅ | test/integration/ |
| flutter analyze / test / web release / apk release | 🟡 | CI 定义完成，结果以 run 为准 |
| iOS 构建 | 🚫 | 手动工作流，未触发（无 macOS 本地环境） |
| 真实联网验证 | 🟡 | 本机已实测（data-sources.md）；CI smoke 手动 |

## 状态结论（当前批次）

**原型可运行；等 CI 首轮全绿后升级为“核心功能已验证（Android/Web 构建级）”。**
iOS、真机性能/耗电、生产环境核验未完成，不宣称“三端全部验证通过”与“可商用”。
