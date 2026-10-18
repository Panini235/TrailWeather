# T-158 / T-194 验证（2026-10-18）

代码：`04011d2`，分支 `codex/weather-time-and-import`，基于 main `cd7be28`。
[CI 39120608464](https://github.com/Panini235/TrailWeather/actions/runs/39120608464) 成功：analyze、451 tests、Web release、正式签名 Android release、独立 .qa profile 包。
无本地 APK 构建，未触发额外 CI。iOS 本轮未构建、无 iOS 真机测试。

设备：小米 12S / HyperOS 3 / Android 15。测试包 `app.shanqing.hiking.qa`（versionCode 3），CI debug 签名；
没有覆盖正式版或既有 `.dev` 包。首次安装被系统取消，用户在手机允许后第二次安装成功。
使用合成 GPX“时间语义回归测试”（2 点，1.1 km，100→300 m），无真实用户轨迹、无账号或密钥。

## 文件打开回归

先在旧 `.dev` 包运行 `tool/device_incoming_smoke.py`：file/content VIEW 冷启动均失败，
`no_router_error=false`，画面为 GoRouter `Page Not Found`。`before-*` 记录结果及截图。
修复后，同一脚本检查 .qa 包；每次必须同时满足“没有路由错误”和“显示合成线路的导入确认框”。

| 用例 | 结果 | 证据 |
|---|---|---|
| VIEW / file / 冷启动 | 通过 | green-file-cold.json |
| VIEW / file / 运行中 | 通过 | green-file-warm.json |
| VIEW / content / 冷启动 | 通过 | green-content-cold.json |
| VIEW / content / 运行中 | 通过 | green-content-warm.json |
| SEND / file / 冷启动（无 data，仅 EXTRA_STREAM） | 通过 | green-send-cold.json |
| SEND / content / 运行中（无 data，仅 EXTRA_STREAM） | 通过 | green-send-warm.json |
| 保存后强制结束、普通入口冷启动 | 通过：只保存 1 条合成线路，无重复导入，无 404 | restart-check.json / normal-restart.xml |

命令样例：

```bash
python3 tool/device_incoming_smoke.py --adb "$ANDROID_HOME/platform-tools/adb" \
  --package app.shanqing.hiking.qa --uri content://media/external/file/1000121404 \
  --cold --output /tmp/shanqing-time-check/green-content-cold
```

夹具授权边界：
- file URI 使用 `run-as app.shanqing.hiking.qa` 写入本包 `files/` 的合成文件。直接 adb push 到 shell 创建的外部目录会因所有权返回 EACCES，不能作为导入功能失败。
- content VIEW 用 `--grant-read-uri-permission`；纯 SEND 的 am CLI 不自动生成真实分享方的 ClipData。
  运行中 SEND 检查先用 MAIN + data + grant 准备本测试 URI 的授权（不触发导入），再发送无 data 的 SEND + EXTRA_STREAM。
  冷启动 SEND 使用包内 file URI，不需要额外授权。没有修改系统存储权限来绕过隔离。
- 运行中用新的文件标识，避免“已消费”去重使测试自己失效。
- 覆盖 Android 原生 VIEW/SEND 通道；未逐一打开微信、两步路、奥维真实应用，不能视为所有第三方应用的逐项验收。

## 天气时间语义

本地完整测试 451/451（tests.txt）；analyze 零问题（analyze.txt）。
包含跨午夜、Open-Meteo 四项区间指标、MET next_1_hours、meteoblue basic 三小时概率、缺端点、
旧缓存往返不二次偏移、旧离线包末小时核心指标覆盖、全天边界、天气图层及时间图/指标格一致性。

真机：保存合成线路，默认固定 10/18 20:00，Open-Meteo best_match，起点海拔 100 m。
独立请求同一公开测试坐标与海拔，原始响应见 raw-open-meteo.json；来源更新可能有时间差，
此处的记录只证明本次取样，不是以后每次联网的固定预期。

| 指标 | 来源原始时次（UTC） | 原始值 | 真机 |
|---|---|---|---|
| 20:00 气温（瞬时） | 10-18 12:00 | 10.2°C | 10°C |
| 20:00–21:00 最大小时阵风 | 10-18 13:00 | 13.3 km/h | 13 km/h |
| 20:00–21:00 降水量 / 概率 | 10-18 13:00 | 0 mm / 0% | 0.0 mm / 0% |

区分错位的信号：下一小时气温为 9.1°C、前一小时阵风为 12.2 km/h，均与界面正确值不同。
节点详情与时间图都标出 20:00–21:00，并显示同一组值（node-weather.png/xml，numeric-check.json）。
本次实时降水两小时均为 0；降水错位由确定性 fixture 的 0→8 mm 跨午夜用例验证，不把此次实况截图当成非零降水验证。

T-195 的本地午夜/UTC 请求窗缺口仍在，界面全天统计如实显示仅覆盖 16 小时。本次未变更离线包起始日期策略。
T-143 的真实 24/48/72 小时老化、跨版本升级及 iOS 真机仍未完成，不因本次对齐回归而关闭。

## 清理

测试后卸载本轮新建 .qa 包（仅含合成数据），删除合成 GPX 与媒体记录，移除本轮新增的 adb tcp:7897 反向代理，回到手机桌面。正式版及原有 .dev 包与其数据保留；未改系统时间、系统代理、飞行模式或常亮设置。

画面对照：[修复前 404](before-content-404.png) · [修复后导入确认](after-content-confirm.png) · [节点与时间图](node-weather.png)。
