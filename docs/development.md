# 开发文档

面向参与开发的人。工作约定（迭代流程、CI 预算、数据真实性红线、不可越权事项）以仓库根目录的
`AGENTS.md` 为准；架构说明见 `CLAUDE.md` 与 `docs/architecture.md`。

## 环境要求

- Flutter stable **3.47.7**（Dart 3.13.5），CI 用同一版本
- Android：JDK 17 + Android SDK（CI 用 GitHub runner 自带）
- iOS：macOS + Xcode（仓库提供手动触发的 iOS 构建工作流）
- Web：无额外要求（Web 目前只用于工程验证，不作为公开发行产品）

国内网络建议使用镜像：

```bash
export PATH="$HOME/flutter-sdk/bin:$PATH"
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

不设镜像变量时 `flutter pub get` 会把 `pubspec.lock` 里的地址改成 pub.dev，提交前还原：
`git checkout pubspec.lock && flutter pub get --enforce-lockfile`。

## 平台目录（重要）

仓库**不提交** android/、ios/ 的模板目录，避免与 Flutter 版本错配。只提交定制文件：

- `android/app/src/main/AndroidManifest.xml`（权限、中文应用名、“用山晴打开”）
- `android/app/src/main/kotlin/.../MainActivity.kt`（接收外部文件）
- `ios/Runner/Info.plist`（中文显示名、定位用途说明）
- `web/`（中文标题、manifest）

其余平台文件在构建前生成（CI 已内置这些步骤，不会覆盖已存在的定制文件）：

```bash
flutter create --platforms=android,web --org dev.trailweather --project-name trailweather .
python3 tool/apply_branding.py --platforms android web     # 正式名称与图标，见 docs/branding.md
python3 tool/configure_release.py --platform android       # 应用 ID 设为 app.shanqing.hiking
```

iOS 对应 `--platforms ios` 与 `--platform ios`。Kotlin 包路径与 namespace 仍为
`dev.trailweather.trailweather`。

## 运行、测试与构建

```bash
flutter pub get
flutter analyze                    # info 级别的 lint 也会让 CI 失败，保持 0 issues
flutter test                       # 全部（fixture 契约测试，不联网）
flutter test test/weather          # 天气来源契约
flutter test test/integration      # 核心闭环
flutter run -d chrome              # 本地跑 Web

flutter build web --release
flutter build apk --release        # 本地为 debug 签名，非发布签名
flutter build ios --release --no-codesign   # 需 macOS/Xcode
```

真实联网 smoke（消耗外部配额，手动执行）：GitHub Actions → “Live Smoke (manual)”。

## 真机调试（Android）

本机 Android SDK、JDK 与镜像配置见 `CLAUDE.md`。用 profile 构建在真机上看性能：

```bash
flutter build apk --profile --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-profile.apk
flutter attach -d <设备> --app-id app.shanqing.hiking.dev   # 拿到 VM Service，可读帧耗时
```

debug / profile 构建的应用 ID 带 `.dev` 后缀，可与正式版并存。

**调试手机没有网络时**：把手机上的 7897 端口转到电脑上的代理，并让 App 走这个代理
（只在 debug / profile 构建生效，release 构建忽略；不改手机系统设置）：

```bash
adb reverse tcp:7897 tcp:7897
flutter build apk --profile --target-platform android-arm64 \
  --dart-define=SHANQING_DEV_PROXY=127.0.0.1:7897
```

## 签名与发布

### Android 正式签名

签名文件与密码只由维护者本人生成和保管，不进仓库。首次配置运行
`bash tool/create_android_keystore.sh`（需要 JDK 17 与已登录的 `gh`）：生成
`~/shanqing-release.jks`，上传 4 个 GitHub Secrets（`ANDROID_KEYSTORE_BASE64`、
`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`），并打印证书指纹与公钥。
CI 有这些 Secrets 时用正式签名构建 APK，没有时退回 debug 签名并在运行摘要中标注。

### iOS

“iOS Build (manual)”工作流做无签名 release 构建，并打包成未签名 IPA（产物 `ios-unsigned-ipa`），
供测试者用自己的 Apple ID 自签安装（步骤见 [使用文档](user-guide.md#ios自签安装)）。
正式分发需要 Apple 开发者账号与签名证书，尚未配置。

### 发布流程

发布前检查项见 `docs/release-checklist.md`。版本号在 `pubspec.yaml` 与 `lib/core/app_links.dart`
（`kAppVersion`）两处，`test/unit/app_version_test.dart` 校验二者一致。

## CI（`.github/workflows/`）

- `ci.yml`：push 到 `main`、pull request 与手动触发时运行；只改 `**.md`、`docs/**`、`agent/**` 时跳过。
  步骤：flutter create → analyze → test → web release → APK release → 上传产物。
  同一 ref 的新运行会取消旧运行。推到功能分支只有在开了 PR 时才会触发。
- `ios-build.yml`（iOS 构建）与 `live-smoke.yml`（真实网络 smoke，消耗外部 API 配额）只手动触发。
- 查看运行：`gh run list --limit 3`、`gh run watch`、`gh run view <id> --log-failed`。

## 配置

默认来源不需要密钥。和风天气、meteoblue 为可选来源，用户在“设置 → 数据源密钥”填入自己的 Key（只存本机）；
天地图图层同理。预留网关等变量见 `.env.example`。不要把任何真实密钥提交进仓库。

## 目录导览

```
lib/
  core/            地理计算、单位换算、HTTP（限流退避）、TTL 缓存、版本与链接
  data/weather/    统一数据模型（溯源）、各来源适配、仓库、ETA、风险规则、数据分级、穿衣、天气图数据
  data/routes/     线路模型、GPX/KML/KMZ/GeoJSON 导入、外部文件、Overpass、导出
  data/settings/   设置与收藏（shared_preferences）
  data/offline/    离线行程包
  ui/              行程首页、地图与天气图、线路详情、节点详情、分享、设置、导入、手绘规划
docs/              产品、架构、数据源、验收、性能、隐私、发布清单、许可证、使用文档
agent/             任务状态、进度、阻塞项、决策记录
test/              单元 / 来源契约（fixture）/ 组件 / 集成
tool/              品牌资源、发布配置、签名脚本
```

## 故障排查（开发）

| 现象 | 处理 |
| --- | --- |
| `flutter create` 会不会覆盖平台定制 | 不会覆盖已存在文件；定制文件在仓库中 |
| `pubspec.lock` 里的地址变成 pub.dev | 没设镜像变量；`git checkout pubspec.lock && flutter pub get --enforce-lockfile` |
| MET Norway 在 Web 失败 | 浏览器禁止自定义 User-Agent（服务条款要求标识），已在来源能力中标注 |
| “搜索此区域”失败 | Overpass 公共镜像过载（504）常见；App 内置镜像轮换，稍后重试 |
