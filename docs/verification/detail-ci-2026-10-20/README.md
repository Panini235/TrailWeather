# 详情页穿衣动画可见性与统一移动 CI（2026-10-20）

**最终要求更新**：用户在首版6614c5e后要求继续使用原衣物动画。最终默认显示原衣物叠层动画、三场景切换、穿着/背包行与配件，只将偏好与依据收起。下方文本摘要截图和三CLI投票属于首版过程证据；最终界面以新增的手机验收证据为准。手机已连接，独立.qa包验证进行中。

## 原因与修改

上轮穿衣卡默认折叠，只显示衣物名称串，无法区分穿着和备装；主页面把天气带放在穿衣卡前，增加了查找距离。
当前默认显示“出发穿 / 随身带”（含配件），紧接天气摘要。场景、偏好、图示和依据从“调整与详情”展开，非默认偏好有标签。
节点主面板保留关键天气、时段和信号；海拔、指标、空气质量、来源对比、照片集中从“更多天气与工具”进入。

## 执行证据

- 修改前已运行 `flutter test --no-pub test/widget/route_detail_v2_test.dart --plain-name '手机默认直接看见穿什么和带什么' --reporter expanded`，失败为 `Found 0 widgets with text containing 出发穿：`。
- 修改后 `flutter test --no-pub test/widget/route_detail_v2_test.dart --reporter expanded`：13/13通过，含手机默认可见、缺气温、场景/怕冷偏好、工具入口懒加载、390px与1.6倍字号深浅色。
- 大字号回归另发现顶部时间控件溢出63px；两个控件均约束宽度后通过，完整时间保留在tooltip和摘要时间模式中。
- 合并工作流YAML已解析：build=ubuntu-latest，ios=macos-latest且needs=build；旧ios-build.yml删除；原concurrency.cancel-in-progress=true保留。
- `flutter analyze --no-pub`：0 issues；`flutter test --no-pub --reporter expanded`：454/454通过。GitHub Actions结果待补充。

## 组件截图

390×844逻辑像素，2倍输出；使用集成测试的**合成线路、合成天气**和AppTheme。临时Flutter test截图夹具加载本机中文/图标字体，对根RepaintBoundary截图（含节点弹层），完成后删除夹具。
修改前来自公开提交93e7574；修改后来自本次工作树，四份实现文件临时恢复旧版本后已完整还原。
这些不是Android/iPhone设备截图：测试器不加载网络瓦片，地图背景为空；自绘图表文字仍受测试字体限制，截图不能证明真机字体、联网、帧率或系统无障碍。

| 状态 | 证据 |
| --- | --- |
| 原默认页：只有衣物名串 | [before.png](before.png) |
| 当前默认页：摘要后直接显示穿/带 | [after.png](after.png) |
| 原节点面板 | [node-before.png](node-before.png) |
| 当前节点面板：单一工具入口 | [node-after.png](node-after.png) |
| 深色1.6倍字号（滚到穿衣区） | [dark-large-after.png](dark-large-after.png) |

## CLI独立投票

[完整投票](votes.json)：Antigravity CLI的Gemini3.8 Flash High、Claude Code的DeepSeek v4.1 Flash、pi的GLM5.3（auto路由），三票均选择A（紧凑穿/带摘要，详情按需展开），B/C各0票。规则已由用户澄清为少数服从多数；本次没有分歧。
评审仅基于三份与公开GitHub分支blob完全一致的源码，未把评审冒充截图或设备测试。所有CLI显式使用用户指定的7897代理；GLM首路由429后更换到同模型已配置自动路由成功。原始输出只在临时目录，不入库任何凭据。
评审建议需核验：未采纳GLM测试项中的“缺失值仍为0”错误表述，缺失继续为null。

## 验证边界

iOS仅构建未签名IPA，仍需用户自行签名安装。本次不合并main，不发布Release或商店版本；Android/iOS真机视觉和性能另验。
