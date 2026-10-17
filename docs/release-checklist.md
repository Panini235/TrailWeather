# 发布清单与状态分级

## 状态分级（当前：原型可运行）

1. **原型可运行** ← 当前（CI 通过后进入下一级）
2. **核心功能已验证**（Android/Web CI 构建绿 + 核心闭环集成测试绿 + Web 端人工冒烟）
3. **发布候选**（下述全部 ✅ + iOS 构建绿 + 真机性能记录）
4. **可商用授权已完成**（天气托管商业授权、瓦片/线路服务条款、离线权利、成本配额）
5. **已正式发布**（商店上架，当前未发生）

## 发布候选前检查

### 构建
- [ ] CI：analyze/test/web release/apk release 全绿
- [ ] iOS：手动触发 ios-build 工作流通过（无签名构建，产出未签名 IPA `shanqing-<版本>-ios-unsigned.ipa`，Release 说明附自签安装步骤）
- [ ] 版本号 pubspec version 与 tag 一致
- [ ] Android 正式签名：Secrets 已配置（`tool/create_android_keystore.sh`），CI 运行摘要显示“正式签名”且证书指纹与备案一致
- [ ] 应用 ID `app.shanqing.hiking`（`tool/configure_release.py`；CI 的 verify_build_branding 校验 APK / iOS）

### 数据与授权
- [ ] docs/data-sources.md 全表复核（限额/条款可能变化）
- [ ] OSM：若加离线/再分发能力 → ODbL 衍生库义务评估
- [ ] Open-Meteo：商业化前购买或自托管
- [ ] 瓦片流量评估，必要时切换商用底图
- [ ] 图标/字体/依赖许可清单复核（flutter pub deps）

### 功能与质量
- [ ] 核心闭环集成测试绿；Live Smoke 手动留档
- [ ] 真机（Android+iOS 各一台）：冷启动、平移流畅度、耗电协议（docs/performance.md）
- [ ] 弱网/离线/限流状态人工过一遍（飞行模式、代理限速）
- [ ] 定位拒绝路径可用

### 合规与安全
- [ ] 隐私政策页面与实际行为一致（docs/privacy.md 与 App 内 S.privacySections）
- [x] 首次启动隐私同意（不默认勾选；同意前不处理外部文件）
- [x] 打开地图不弹定位授权，授权只在用户点击定位时请求
- [ ] 无密钥入库（.gitignore 生效）
- [ ] GPX/XML 解析无外部实体（xml 包默认，已测）
- [ ] 商店素材与说明不使用“最准确/绝对安全”表述

### 运维
- [ ] 崩溃监控方案（当前无后端，需先决策：无监控发布 or 接入自托管）
- [x] 用户反馈入口（设置 → 问题反馈：复制诊断信息 + GitHub Issues）
- [ ] 回滚：商店版本回退流程 + git tag

## 回滚策略

- 代码：git tag 每个发布候选；问题版本 revert tag。
- 数据源：ProviderRegistry 增删来源不影响缓存结构（键含 providerId）。
- 配置：无远端配置，全部本地。

## 当前 blocker（阻塞正式发布）

见 agent/blockers.md（iOS 环境、真机测试、商业授权决策、Overpass 生产化方案）。
