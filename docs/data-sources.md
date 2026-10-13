# 数据源能力与授权对照

> 核验日期：2026-10-13。核验方式：官方文档 + 真实 API 实测（代理出口）。
> 日常 CI 使用 fixture 契约测试；真实联网验证用手动 “Live Smoke” workflow。

## 天气来源

### 1. Open-Meteo Forecast API

| 项 | 内容 |
| --- | --- |
| 端点 | `https://api.open-meteo.com/v1/forecast`（实测 200） |
| 密钥 | 不需要 |
| CORS | 允许（Web 直连可行） |
| 覆盖 | 全球（陆地为主） |
| 时效 | 最多 16 天；逐小时（1h） |
| 批量 | 支持（latitude/longitude 逗号列表，返回数组；实测验证） |
| 响应溯源 | 返回网格坐标（latitude/longitude）、模型地形海拔（elevation）、utc_offset_seconds；**不返回**模型起报时间与网格中心标识 |
| 我们接入的模型 | `best_match`（按区域自动选模型，响应不指明具体模型 → 按未知处理）、`ecmwf_ifs025` |
| 空间分辨率 | 响应不携带。best_match 分辨率随区域变化（未确认）；ecmwf_ifs025 为 0.25° 级全球模型（按模型名标注，以官方文档为准） |
| 授权 | CC BY 4.0；非商业用途免费额度（商业需付费计划或自托管） |
| 署名 | “数据：Open-Meteo（模型来自 NOAA/GFS 等机构，随 best_match 而定）” |
| 缓存 TTL | 30 min（自定） |
| 限制 | 非商业免费额度有调用上限（官方文档），实现分批 + 最小间隔 600ms + 退避 |

### 2. MET Norway Locationforecast 2.0 (compact)

| 项 | 内容 |
| --- | --- |
| 端点 | `https://api.met.no/weatherapi/locationforecast/2.0/compact`（实测 200） |
| 密钥 | 不需要，但**服务条款要求 User-Agent 标识自身**（已内置） |
| CORS | `Access-Control-Allow-Origin: *`（实测） |
| Web 限制 | 浏览器禁止自定义 User-Agent（浏览器安全机制）→ Web 端无法满足其标识条款，请求可能被拒。已在能力声明与 UI 标注；移动端正常 |
| 覆盖 | 全球（北欧分辨率更高） |
| 时效 | compact 实测约 2–3 天逐时（以 3 天标注） |
| 批量 | 不支持（单坐标/请求）；实现最小间隔 250ms |
| 响应溯源 | `meta.updated_at`（作为发布时间）；响应几何为请求坐标原样（不冒充实际网格坐标）；不提供来源使用海拔 |
| 缺失字段（实测） | 体感温度、降水概率、能见度、多数时次的阵风 → UI 显示“此来源未提供” |
| 空间分辨率 | 来源文档：北欧 HARMONIE 约 2.5 km，其他区域 ECMWF 约 9–22 km，随区域与时效变化；响应不携带网格信息 |
| 授权 | NLOD 2.0 / CC BY 4.0 |
| 署名 | “天气数据：MET Norway, CC BY 4.0 / NLOD” |
| 缓存 TTL | 20 min（自定，低于其典型更新节奏） |

### 模型重叠（诚实声明）

- Open-Meteo 的多个 `models` 参数（best_match / ecmwf_ifs025）来自**同一服务商接口**，
  不是相互独立的证据。
- MET Norway 全球部分使用 ECMWF 模型，与 Open-Meteo 的 ECMWF 系模型可能共享底层模型；
  未逐点识别，按“未知，可能重叠”标注。
- App 在来源卡片与设置页展示以上说明。

## 其他数据服务

### Open-Meteo Geocoding（地点搜索）

- 免费无密钥，CORS 开放（实测）。数据来自 GeoNames 等（知识共享署名）。
- 返回 IANA 时区字段（地理数据库属性，非天气分辨率）。

### Overpass API（OSM 徒步路线发现）

- 端点轮换：overpass-api.de / kumi.systems / private.coffee。
- 实测状态（2026-10-13）：主站对大查询返回 504（过载，外部状态）；退避与镜像轮换已实现，
  真实可用性以 Live Smoke 结果为准。
- 使用纪律：仅 zoom≥11 且用户点击“搜索此区域”时查询；bbox 跨度 ≤0.6°；单次 ≤30 条；
  结果缓存 10 min。不把公共查询服务当无限量生产数据库。
- 几何处理：relation 成员 way 乱序/缺失/不连通时按端点贪心串联，不共享端点的段独立，
  **绝不自动连直线**；行程模式基于最长连续段并标注。

### OpenStreetMap 标准瓦片（底图）

- `tile.openstreetmap.org`，仅在线显示，遵守瓦片使用政策，**不做离线预下载**。
- 署名：© OpenStreetMap 贡献者（地图页脚 RichAttributionWidget + 设置页说明）。
- 重负载生产环境应更换商用瓦片（发布前检查项，见 release-checklist.md）。

## OSM 衍生数据义务评估（简要）

- 展示 OSM 线路（ODbL）：当前 App 按 viewport 查询、缓存 10 分钟、附署名与许可说明，
  属于“生产数据库另行构建”之外的有限使用；若后续做离线打包/再分发，需要按 ODbL
  开放衍生数据库——已列入发布前检查项，不宣称已完全合规。

## 字体/图标

- Material Icons（Flutter SDK 自带，Apache-2.0 授权的图标集）。
- 系统默认字体，无打包字体。

## 完整第三方依赖许可

见 `docs/licenses.md`（由 pub 依赖树人工整理，发布前用 `flutter pub deps` 复核）。
