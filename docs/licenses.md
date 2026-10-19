# 许可证清单

> 2026-10-15更新：服务/数据许可见 `ios-first-commercialization-2026-10-15.md`。未核验项是发布阻塞，不能用网络可达或公开仓库代替授权。

> 2026-10-19：按用户决定移除徒步星球目录及其数据、加载器和页面。当前源码与后续构建不再携带该数据；
> 仅保留历史收藏/离线包来源枚举的读取兼容。此变更不删除公共 Git 历史或旧发布附件，也不改变高德授权待核验状态（B-012）。

## 应用代码

- 本仓库代码：见仓库根 LICENSE 决定（默认未指定，发布前补充；不阻碍原型开发）。

## 数据与在线服务

| 数据 | 提供方 | 许可 | App 内署名 |
| --- | --- | --- | --- |
| 天气预报（best_match / ECMWF IFS 0.25°） | Open-Meteo | CC BY 4.0；非商业免费额度（商用需付费或自托管） | “数据：Open-Meteo” |
| 天气预报 | MET Norway | NLOD 2.0 / CC BY 4.0 | “天气数据：MET Norway” |
| 地点搜索/地理编码 | Open-Meteo Geocoding（GeoNames 等） | 知识共享 | 设置页 |
| 地图瓦片 | OpenStreetMap 标准瓦片 | ODbL（数据）；瓦片使用政策（仅在线显示，不预下载） | 地图页脚 + 设置页 |
| 徒步线路几何 | OpenStreetMap（Overpass 查询） | ODbL 1.0 | 线路来源行 + 设置页 |
| 高德底图 | 高德直连栅格瓦片 | 本项目接入与授权范围待核验；需确认官方接入与所需书面许可 | 地图页脚 |
| 高德卫星/路网注记 | 高德直连栅格瓦片（style=6 / style=8 透明层） | 同高德底图，授权范围待核验（B-012） | 地图页脚 |
| 天地图矢量/影像/地形/注记 | 国家地理信息公共服务平台 | 用户自行申请的 Key 与平台服务条款；商用、流量与离线范围需用户确认（B-014） | 地图页脚 |
| 等高线地形图 | OpenTopoMap | CC-BY-SA（地图样式）；数据 © OSM 贡献者、SRTM；仅在线显示 | 地图页脚 |
| 高程数据（本机计算等高线、地形阴影、手绘海拔、3D 预览） | AWS Terrain Tiles（Mapzen / Tilezen joerd） | 开放数据；中国境内为 SRTM / GMTED2010（USGS，美国公有领域），按 joerd 署名说明标注 | 地图页脚、3D 预览页“高程：Terrain Tiles（AWS 开放数据）· SRTM（USGS）” |
| 卫星影像 | Esri World Imagery | Esri 使用条款；商用与账号要求待核验 | 地图页脚 |
| 用户自定义图源 | 用户填写 | 由用户自行确认可用性与授权；App 不内置、不分发 | 地图页脚（用户填写的署名） |
| 可选天气来源 | 和风天气 | 按当前开发者EULA与账号许可使用；用途、归因和缓存限制需确认 | 来源信息 |
| 示例线路 | 本项目自制 | 项目内 | “演示”标签 |

## 第三方 Dart/Flutter 依赖（以 pubspec 为准）

| 包 | 版本约束 | 许可 |
| --- | --- | --- |
| flutter / flutter_localizations | SDK | BSD-3-Clause |
| flutter_map | ^8.3 | BSD-3-Clause |
| latlong2 | ^0.10 | BSD-3-Clause |
| flutter_riverpod / riverpod | ^3.4 | MIT |
| go_router | ^18 | BSD-3-Clause |
| dio | ^5.11 | MIT |
| xml | ^7.1 | MIT |
| shared_preferences | ^2.5 | BSD-3-Clause |
| intl | ^0.20 | BSD-3-Clause |
| file_selector | ^1.1 | BSD-3-Clause |
| geolocator | ^14 | MIT |
| url_launcher | 6.3.3（精确锁定） | BSD-3-Clause |
| flutter_lints（dev） | ^6.0 | BSD-3-Clause |

发布前用 `flutter pub deps --style=compact` 复核传递依赖许可（任务 T-501）。

## 字体与图标

- Material Icons：Flutter SDK 附带（Apache-2.0 图标集）。
- 未打包第三方字体。

## 义务提示（发布前必须逐项核验）

1. OSM 衍生数据库（ODbL § 若做离线打包/再分发）。
2. Open-Meteo 商业授权（若商业化）。
3. OSM 瓦片使用政策（若流量增长，需换商用瓦片服务）。
4. MET Norway服务条款（移动端应用标识/联系信息、缓存、流量；浏览器可用Origin标识低流量请求）。
5. 高德接入方式和商业/离线授权范围。
6. 和风服务具体用途、数据缓存与归因约定。
