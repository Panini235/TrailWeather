# TrailWeather 徒步天气

面向徒步爱好者的天气 App：在地图上发现徒步线路 → 查看线路沿途天气 →
按出发时间分析各路段天气 → 比较多个天气来源。

**最高产品原则：数据真实性。** 请求坐标不等于数据实际对应位置；网格预报不是点位实测；
缺失数据不显示为 0；不同来源不默认平均。详见 `docs/data-sources.md` 与 `docs/acceptance.md`。

## 平台

- Android / iOS / Web（Flutter，纯 Dart 地图方案 flutter_map 三端一致）
- 默认中文界面；文案集中于 `lib/ui/strings.dart`，可迁移 ARB（见 `docs/architecture.md`）

## 环境要求

- Flutter stable（CI 使用 **3.47.7**，Dart 3.13.5）
- Android：JDK 17 + Android SDK（CI 用 GitHub runner 自带）
- iOS：macOS + Xcode（本仓库 CI 提供手动触发的 iOS 构建工作流）
- Web：无额外要求

## 平台目录说明（重要）

仓库**不提交** android/ ios/ 的模板目录，避免与 Flutter 版本错配。
仅提交定制文件：

- `android/app/src/main/AndroidManifest.xml`（权限、中文应用名）
- `ios/Runner/Info.plist`（中文显示名、定位用途说明）
- `web/`（中文标题、manifest）

其余平台文件在构建前由 `flutter create --platforms=android,web --org dev.trailweather --project-name trailweather .`
生成（CI 已内置此步骤；本地构建同样先执行一次该命令）。

## 运行

```bash
flutter create --platforms=android,web --org dev.trailweather --project-name trailweather .
flutter pub get
flutter run            # 选择设备/浏览器
```

## 测试

```bash
flutter test                       # 全部（fixture 契约测试，不联网）
flutter test test/weather          # 来源契约
flutter test test/integration      # 核心闭环
```

真实联网 smoke（消耗外部配额，手动执行）：GitHub Actions → “Live Smoke (manual)”。

## 构建

```bash
flutter build web --release
flutter build apk --release        # 使用模板 debug 签名，非发布签名
flutter build ios --release --no-codesign   # 需 macOS/Xcode
```

CI（push 到 main 自动触发）：analyze → test → web release → apk release，产物上传 Artifacts。
iOS 构建为手动工作流（节省 runner 分钟）。

## 配置

默认来源无需密钥；和风天气为可选来源，需要用户自己的 API Host 与 Key（仅存本机）。预留网关等变量见 `.env.example`。

## 故障排查

| 现象 | 处理 |
| --- | --- |
| `flutter create` 覆盖了我的平台定制 | 不会覆盖已存在文件；定制文件在仓库中 |
| 地图瓦片不显示 | 默认高德瓦片（大陆直连）；海外网络可在 设置→地图底图 切换为 OSM |
| 和风天气显示“未配置” | 在 设置→数据源密钥 填入和风 API Host 与 Key（dev.qweather.com 免费注册） |
| MET Norway 在 Web 失败 | 浏览器禁止自定义 User-Agent（服务条款要求标识），已在来源能力中标注 |
| “搜索此区域”失败 | Overpass 公共镜像过载（504）常见；稍后重试，App 内置镜像轮换 |
| Android 定位无权限 | 首页会请求一次前台定位；拒绝后仍可点选地图查天气。永久拒绝可点“打开设置”；定位按钮每次请求结束后恢复可用 |

## 目录导览

```
lib/
  core/            地理计算、单位换算、HTTP（限流退避）、TTL 缓存
  data/weather/    统一数据模型（溯源）、Open-Meteo、MET Norway、仓库、ETA、风险规则
  data/routes/     线路模型、GPX/GeoJSON 导入、Overpass、示例线路
  data/settings/   设置与收藏（shared_preferences）
  ui/              地图首页 / 线路详情 / 节点对比 / 设置 / 导入
docs/              产品、架构、数据源、验收、性能、隐私、发布清单、许可证
agent/             任务状态、进度、阻塞项、决策记录
test/              单元 / 来源契约(fixture) / 组件 / 集成
```

详细文档入口：`docs/product.md`（产品）、`docs/architecture.md`（架构）、
`docs/data-sources.md`（数据源与授权）、`docs/acceptance.md`（验收矩阵）、
`agent/tasks.json`（任务状态）。

## 当前状态

2026-10-15：个人开发者、iOS优先、Android兼容；Web暂停作为公开发行产品，保留工程验证能力。
当前免注册、不展示订阅。首次引导直接导入或查看示例线路，设置会员入口已移除，旧付费链接返回首页。

业务提交 `a699aca`（含 `18be281` UI改动）：本地 analyze 0 issues、171项测试通过；
CI **38699456479**（Web/APK）与 **38699460743**（iOS release --no-codesign）成功。
iOS无签名构建不能替代真机验收或商店发布。

天气缓存/离线可靠性仍按任务推进。高德接入授权和内置徒步星球目录许可未解决，
不宣称可正式商用分发。详见 `docs/ios-first-commercialization-2026-10-15.md`、
`agent/blockers.md`。名称/图标候选位于 `design/brand-options/2026-10-15/`。

## 本地开发

已配置本地 Flutter 3.47.7（`~/flutter-sdk`，flutter-io.cn 镜像，无模拟器）：

```bash
export PATH="$HOME/flutter-sdk/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
flutter pub get && flutter analyze && flutter test   # 全绿后再推送，减少 CI 次数
flutter run -d chrome                                  # 本地跑 Web 端
```
