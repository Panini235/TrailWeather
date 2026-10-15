# 山晴品牌资源

2026-10-15用户选定：**应用显示名称“山晴”＋第四个图标D（日出叠山、沙色背景）**。

![山晴图标](../assets/branding/preview.png)

## 已应用的位置

- Flutter应用标题、首次使用页面、系统文件打开提示与导出GPX的creator。
- Android安装后的应用标签；普通启动图标、Android自适应图标与主题单色前景。
- iOS的CFBundleDisplayName/CFBundleName及AppIcon资产目录（iPhone/iPad/App Store尺寸）。
- 保留的Web验证入口：页面标题、manifest、favicon与图标。
- 隐藏中的旧付费页面文案同步名称，但入口仍保持隐藏。

现有Dart包名、Android/iOS应用标识、仓库地址、MethodChannel和本地数据键保持兼容；HTTP标识沿用与仓库对应的技术标识，不把显示名称变更当作新应用或数据迁移。

## 文件

- `assets/branding/selection.json`：正式选择记录。
- `assets/branding/app-icon.svg`：D方案矢量原稿。
- `assets/branding/app-icon.png`：原始1024×1024不透明主图，与用户选中的D方案PNG完全一致。
- `assets/branding/platforms/`：预生成的原生和Web资源。
- `assets/branding/preview.png`：仅用于文档展示的圆角预览；不作为原生主图。

只有主图PNG作为Flutter资源打入应用，平台不同尺寸图标不重复打入Flutter资源包。

## 构建流程

仓库继续在CI用`flutter create`生成平台目录，不提交完整android/ios工程。必须在生成之后应用图标：

```sh
# Android + Web
python3 tool/apply_branding.py --platforms android web

# iOS
python3 tool/apply_branding.py --platforms ios

# 已应用后，可只检查，不写文件
python3 tool/apply_branding.py --platforms android web --check
```

脚本只使用Python标准库，不增加Flutter/CI图像依赖。它会核对图标尺寸、iOS图标不透明性、平台资源内容和应用显示名，避免产物退回Flutter模板图标。

CI构建后还运行`tool/verify_build_branding.py`：检查APK的实际application-label、启动图标声明和品牌图片；检查iOS产物Info.plist及编译的AppIcon目录；检查Web实际输出的标题、manifest与图标。

## 编辑与导出

`tool/render_brand_icons.mjs`是可选的PNG导出工具，需要开发环境提供sharp（本轮使用已有的工作区运行时）。可通过`TRAILWEATHER_SHARP_PATH`指定sharp位置；CI只使用已提交PNG，不运行此工具。

iOS尺寸清单来自当前Flutter 3.47.7的AppIcon模板。Android自适应前景由同一D方案几何转写，核心山峰与太阳保留，外部轮廓由系统图标形状裁切；修改SVG后应同步核对Android矢量前景、主题单色资源与小尺寸效果。

名称和图标已按用户选择应用；商标、商店重名和正式发行许可仍需在上架阶段核验。本轮不做商店发布。

## 验证记录

- 业务提交：2816d9d。
- 本地：analyze无问题、171项测试通过；临时项目三端图标应用和只读校验通过；1024主图与用户选中的D图片字节相同。
- CI38706513896成功：Web/APK构建、APK实际application-label与图标资源检查、Web实际标题/manifest/图标检查。
- iOS38706518000成功：无签名release构建、实际Info.plist显示名、编译AppIcon目录检查。
- 不代表商店发布或真机操作验收。
