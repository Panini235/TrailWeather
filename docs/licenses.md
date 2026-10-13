# 许可证清单

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
| flutter_lints（dev） | ^6.0 | BSD-3-Clause |

发布前用 `flutter pub deps --style=compact` 复核传递依赖许可（任务 T-501）。

## 字体与图标

- Material Icons：Flutter SDK 附带（Apache-2.0 图标集）。
- 未打包第三方字体。

## 义务提示（发布前必须逐项核验）

1. OSM 衍生数据库（ODbL § 若做离线打包/再分发）。
2. Open-Meteo 商业授权（若商业化）。
3. OSM 瓦片使用政策（若流量增长，需换商用瓦片服务）。
4. MET Norway 服务条款（User-Agent 标识；Web 端限制已标注）。
