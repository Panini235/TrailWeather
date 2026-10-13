# AGENTS.md — TrailWeather 自主研发工作协议

本文件面向在仓库内工作的 AI Agent / 自动化流程。人读版本见 README.md。

## 执行环境约束（最高优先级）

1. **构建与产物验证在 GitHub Actions 上完成**（web/apk 构建）；本地 Flutter 仅用于
   analyze/test 快速迭代（2026-10-13 用户批准本地安装，SDK 位于 `~/flutter-sdk`，
   走 flutter-io.cn 镜像，未安装模拟器/Android Studio）。
2. **尽可能降低 workflow 构建次数**：本地 analyze+test 全绿后才 push；CI 设
   `concurrency.cancel-in-progress`，同分支新 push 会取消进行中的旧运行。
3. 外网访问需走代理：`export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897`
4. 远端：`https://github.com/Panini235/TrailWeather.git`（gh CLI 已认证，SSH 推送）。
5. 平台目录策略：不提交 android/ios 模板；仅提交
   `android/app/src/main/AndroidManifest.xml`、`ios/Runner/Info.plist`、`web/`。
   CI 中用 `flutter create` 生成其余文件（步骤已内置，勿删）。本地 analyze/test
   不需要平台目录。

## 每轮迭代流程

1. 读取 `agent/tasks.json`、`agent/progress.md`、`agent/blockers.md` 与最近一次 CI 失败日志
   （`gh run list --limit 3` / `gh run view <id> --log-failed`）。
2. 选择最高优先级（P0>P1>P2>P3）且未阻塞的任务，明确本轮可验证产出。
3. 实现最小完整变更；新依赖必须先经 pub.dev / 官方文档核验版本与三端兼容，
   不得凭记忆硬编码版本。
4. 本地无法编译验证 → 依赖 CI；commit 前自查：import 完整、无未用符号、API 与
   所选依赖版本一致（flutter_map 8.x / riverpod 3.x 语法）。
5. push → `gh run watch` 或轮询 → 失败则修复再推。**没有实质改动不得声称完成新一轮迭代。**
6. 通过后更新 `agent/tasks.json`（状态/验证命令/实际结果）、`agent/progress.md`、
   相关 docs 与验证证据。

## 防空转

- 同一失败连续 3 轮无进展 → 根因分析、缩小任务或换方案（记录到 `agent/decisions.md`）。
- 外部权限/资源问题 → 登记 `agent/blockers.md`，转做其他任务，不反复询问。
- 每批时间/请求/token 预算耗尽 → 持久化进度到 agent/ 后结束本轮。

## 不可越权事项

不得自主：购买服务、注册账户、部署付费基础设施、发布商店版本、force push、
处理真实用户数据、提交真实密钥。均登记 blocker。

## 数据真实性红线（编码时强制）

- 缺失值 = null，UI 显示“此来源未提供”；绝不 0。
- 降水概率 ≠ 降水量；阵风 ≠ 持续风速；观测 ≠ 预报。
- 请求坐标 / 返回坐标 / 网格中心 / 分辨率分开建模（WxProvenance）。
- 同一来源多个 models ≠ 多个独立证据；跨来源可能共享底层模型，需标注。
- 近似网格合并、ETA、海拔修正都必须显式标注为估算/近似。
- 官方预警未接入就写“未接入”，不得显示“无预警”。
- 演示数据永久带“演示”标签。
- 不宣传“最准确”“绝对安全”。

## 当前技术栈锚点（变更前先核验）

Flutter 3.47.7 / flutter_map ^8.3 / latlong2 ^0.10 / flutter_riverpod ^3.4 /
go_router ^18 / dio ^5.11 / xml ^7.1 / shared_preferences ^2.5 / intl ^0.20 /
file_selector ^1.1 / geolocator ^14。版本以 pubspec.yaml 为准，改动需记录
`agent/decisions.md` 并核验变更日志与三端兼容。
