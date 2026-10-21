# 详情地图、节点编号与3D手势（2026-10-20）

## 范围

按用户九项详情反馈及追加的3D水平拖动反向集中处理：中性阈值图标；全屏+菜单；减细半透明线路与临时隐藏/直接恢复；小地图单指平移；剖面/列表统一路线顺序序号（命名航点也编号，折叠行显示范围）；点选联动高亮和交互提示；海拔网格与自适应距离刻度；整行打开节点详情；来源标题降级；选定时段与当天降水分隔；3D水平旋转跟随拖动。衣物动画保留。

## 回归与边界

- 单指平移先验证地图中心不变而失败，开启drag后中心变化；菜单隐藏后所有线路层消失，直接恢复后出现。
- 命名航点原无可见序号，修复后显示节点3；剖面点终点后，编号5与列表选中同步。
- calm原为绿色check，修复为灰色info；分享图同步。起点绿色只表示起点。
- 3D持续右拖时指北针原+0.6，修复后负角；持续左拖回到正角。双指缩放/扭转与松手不再出帧仍通过。
- 当天汇总保留来源覆盖不足与原小时区间说明，数据计算/采样/ETA/依赖未变。栅格底图的地名无法单独调整图层，隐藏线路提供完整阅读入口。
- 地图内单指拖动优先于页面滚动；地图外仍可滚页面。完整闭环测试相应从页面边缘滚动。

## CLI投票

[独立结果](votes.json)：B=3/A=0，保留全屏一级入口，其余收菜单。仅通用设计说明，经7897代理；本机网关NO_PROXY。此为方案复核，不是设备测试。

## 验证结果

业务提交 **6836d828d7792b17c13f6878eaed1e6869bbc7cd**。

- [本地结果](local.json)：analyze无问题，**461/461**测试通过。含原衣物动画、缺失/区间口径、390px/1.6x深浅色、地图/节点/3D与完整闭环。本地未构建。
- [CI 39394169941](https://github.com/Panini235/TrailWeather/actions/runs/39394169941)：Linux与macOS均成功，Web/APK/android-device-test/未签名IPA全部完成，[详情](ci.json)。本批只运行这一次，收尾证据skip ci不重复构建。
- [手机结果](device/result.json)：小米12S / Android15，安装此CI的独立profile QA包，使用自制40点约5.5km/780m并带命名营地的GPX。公开Open-Meteo预报在旧QA中获取，修复版从测试缓存读取，UI如实显示已保存及覆盖不足；不是实测天气。
- [摘要与衣物动画](device/01-summary-clothing.png)、[实际底图与剖面](device/06-map-with-tiles.png)、[单指平移后](device/07-map-pan-with-tiles.png)、[隐藏线路看地名](device/08-visible-labels-without-route.png)、[节点3同步高亮](device/09-numbered-selected-nodes.png)、[单击进详情](device/10-single-tap-node-detail.png)。[平移记录](device/map-pan-with-tiles.json)、[节点联动](device/node-link.json)。
- [3D新旧方向对照](device/3d-direction-before.json)、[修复后角度](device/3d-direction.json)：同一手势，旧右拖减0.68989rad；新右拖增0.68989rad，左拖减0.82066rad。[新右拖图](device/3d-right.png)、[新左拖图](device/3d-left.png)。profile/AOT的getObject把未装箱double字段以Int位模式暴露，按IEEE754 float64解码；首次误把原始Int当角度的临时采集已丢弃，旧/新版均重新采集。不据此宣称完整帧率/性能。
- [新QA进程错误检查](device/error-check.json)：无Fatal/Flutter错误。[清理](device/cleanup.json)：本轮新旧QA卸载，测试数据和临时XML随之清理，新增ADB反向代理移除。正式版和原.dev保留，系统代理/字体/主题未变。

## 未验证边界

高德在旧/新版QA中均灰底，OpenTopoMap实际瓦片正常。桌面请求代表性高德瓦片200且有图并不证明手机加载通过，已登记B-016继续定位，不因本次手势修复而声称高德已验收；高德仍保留，未改默认配置。截图底图来源为OpenTopoMap（© OpenStreetMap贡献者、SRTM；© OpenTopoMap，CC-BY-SA）。

手机为深色/字体1.0x；大字号与浅色验证来自组件测试。iOS仅编译未签名IPA，未进行iPhone真机验收。本PR未合并main，也未发布Release或商店版本。
