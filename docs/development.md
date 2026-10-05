# 开发与运行

首版已实现共享 SwiftUI 界面、残局编辑与保存、多分支推演、离线 AI 推荐与接管，以及落点、上一手和吃子红绿灯。Mac 用于日常开发；iPhone 触感已实现，实际手感仍需真机确认。

## 准备工程

需要 Xcode、Python 3、Git；自动下载模型时还需要 7-Zip。工程生成脚本仅使用 Python 标准库，不依赖 XcodeGen。

```sh
git clone --recurse-submodules https://github.com/ch1y1z1/xiangqi_app.git
cd xiangqi_app
python3 scripts/prepare-engine.py
python3 scripts/generate-project.py
```

模型准备会从固定的官方发布包提取 `pikafish.nnue` 并校验 SHA-256。已有对应权重时，可以使用 `python3 scripts/prepare-engine.py --network /path/to/pikafish.nnue`。源码固定为 `4c17cee11f888ae1d48a9494f2e2239f019f0a1f`，模型不直接提交 Git。

准备阶段需要联网；构建完成的 App 已包含模型和运行资源，日常使用不联网。

## 构建与打开

```sh
zsh scripts/build.sh mac
zsh scripts/build.sh ios
zsh scripts/build.sh sim
```

Mac 产物为 `build/DerivedData/Build/Products/Debug/Xiangqi.app`，脚本会用本地 ad-hoc 签名，无需 Apple Developer 账号。可以通过 Finder 打开它，或在 Xcode 打开 `Xiangqi.xcodeproj`，选择 My Mac 后运行。

iOS 产物只做未签名构建检查。安装到自己的 iPhone 时，在 Xcode 配置个人 Team、连接手机并选择设备运行。

需要 IPA 时运行 `zsh scripts/package-ipa.sh Debug`，输出包含离线资源的未签名真机包；重新签名或 Xcode 安装步骤见 [IPA 与真机调试](ios-device.md)。

Xcode 的资产目录编译也可能需要已安装的 iOS Simulator runtime。缺少组件时可在 Xcode 的 Settings → Components 安装，或执行：

```sh
xcodebuild -downloadPlatform iOS -architectureVariant arm64
```

新增或删除源文件后重跑 `python3 scripts/generate-project.py`；修改引擎适配脚本后重跑 `python3 scripts/prepare-engine.py`。日常修改已有文件可以直接用 Xcode 构建。

## 只做关键验证

Mac Debug 版本提供开发命令，在创建窗口前运行：

```sh
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --check
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --render-preview
```

`--check` 检查合法走子、多分支复用、JSON 保存恢复、草稿校验、少量安全吃子样例、包内模型推荐与取消。它只使用临时残局目录，不改动用户棋库。`--render-preview` 将实际 SwiftUI 页面渲染到离屏视图，输出到 `build/previews/`；它不截取桌面，不模拟用户输入。

`--check` 也适用于 iOS Debug 版本；`--render-preview` 仅适用于 Mac Debug。可以选择并启动一个 iPhone 模拟器后，通过 Xcode 运行，或使用命令行安装与检查：

```sh
xcrun simctl install booted build/Simulator/Build/Products/Debug-iphonesimulator/Xiangqi.app
xcrun simctl launch --console booted com.chiyizi.xiangqi --check
# 检查结束后，正常启动 App：
xcrun simctl launch booted com.chiyizi.xiangqi
```

运行检查前需要先停止已运行的 App。上述命令要求只有一个目标模拟器处于启动状态；有多个时用其设备 UUID 替换 `booted`。Debug 检查结束会退出，不出现在正式使用界面中。

2026-10-05 已完成三平台完整构建、Mac 与 iPhone 17 Pro／iOS 26.4 模拟器中的关键流程检查及模拟器正常启动。记录见 [development-validation.json](development-validation.json)，页面预览见 [previews/pages.png](previews/pages.png)。

原生窗口的点击／拖动与手机手感仍需实际操作确认，不把离屏渲染称为交互测试。真机重点检查一次离线闭环、动画／震动、切后台和引擎内存即可。

## 代码位置

| 目录 | 内容 |
| --- | --- |
| App | SwiftUI 页面、棋盘绘制、研究数据与会话、JSON 存储、触感 |
| Engine | Objective-C++ 桥接、搜索取消与安全吃子规则扩展 |
| Vendor/Pikafish | 固定版本上游 submodule |
| Resources | 图标、上游说明与本地准备的 NNUE |
| scripts | 资源准备、共享 Xcode 工程生成与构建 |

引擎适配发生在忽略的 `build/engine` 源码副本中：启用上游的本地内存分配后端；在 `Position` 中声明项目的安全吃子辅助接口。原始 submodule 保持干净，具体扩展实现在 `Engine/RulesExtension.cpp`。
