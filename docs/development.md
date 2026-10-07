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

准备阶段需要联网；构建完成的 App 已包含皮卡鱼模型和运行资源，摆棋与推演不联网。选用的图片识别连接 DeepSeek 官方或配置的自定义服务；无需鉴权的本地服务可以不填密钥。

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
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --check-image-import
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --render-preview
```

`--check` 检查合法走子、多分支复用、前进沿已选分支／未选分支需选择、摆棋选择不覆盖棋子、占位拖动拒绝与删除／清空撤销、JSON 保存恢复、改名保留分支、重新摆棋的历史副本与 AI 暂停、草稿校验、少量安全吃子样例、包内模型推荐与取消。它只使用临时残局目录，不改动用户棋库。`--render-preview` 将实际 SwiftUI 页面渲染到离屏视图，输出到 `build/previews/`；它包含普通页面、选中棋子、AI 建议、识别完成与原图校正状态，以及 375×667 和 375×553 pt 的紧凑内容区域；不截取桌面，不模拟用户输入。

`--check-image-import` 只验证图片导入：坐标换算、照片旋转与结构校验，DeepSeek 四档思考兼容，自定义地址解析、可选鉴权、Completions／Responses 图片与 JSON 请求格式、标准思考参数、模拟 HTTP 导入与不完整响应拒绝，以及文件上传、结果保存恢复、取消后迟到回调、HTTP 错误与中断任务恢复。使用虚拟密钥并拦截 HTTP，不读取个人密钥，不请求外网，不消耗额度；图片功能变更不需要重跑引擎探针。真实 DeepSeek／GPT Luna 测试和手动复现方法见 [图片识别说明](image-import.md)。

Mac Debug 的 `--prepare-recognition-audit` 可配合 `--audit-endpoint`、`--audit-model`、`--audit-api` 生成自定义服务的真实请求样例；`--audit-output` 指定输出目录，`--audit-thinking` 指定可选思考档位。准备步骤不连接服务，真实调用只在手动运行 `scripts/audit-custom-recognition.py` 并输入密钥时发生。`--audit-recognition-responses --audit-output …` 使用实际 Swift 解析器核对指定目录的响应。

`--audit-input` 支持提供本地图片样例及预先标定的 FEN，字段见 [图片识别说明](image-import.md)。真实 JJ 截图的 DeepSeek／Luna 全档测试结果见 [对照表格](jj-recognition-comparison.md)。审计会分别记录导入校验是否通过、正确棋子数及整盘是否完全匹配，避免把结构无效的部分正确结果当作可直接使用的棋局。

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

图片后台识别改动需在真机做一次长请求验证：开始识别后切换 App 或锁屏，等待结果返回再打开；确认原页面恢复结果、明确取消不导入迟到结果。强制关闭 App 后重新打开应显示中断状态，或恢复已经保存的完成结果，不应卡在无限等待或自动重新请求。可分别使用 DeepSeek 与自定义 Responses 服务，无需重新运行引擎探针。

2026-10-06 后台识别实现已通过 Xcode 26.4 的 Mac 与未签名 iOS 构建、`--check-image-import` 和实际 SwiftUI 离屏预览。本地 HTTP 服务额外核对文件 POST 请求体、鉴权、两种接口、分段响应及取消后立即重启，共收到 4 次主动发起的请求。此次没有请求真实付费模型，本机真机不可连接，尚未验证 iOS 系统挂起后的传输和唤醒。

2026-10-07 UI 优化将摆棋与推演改为固定整页布局：同时显示两排棋子、删除只对选中棋子出现、常驻起点与 AI 操作，识别完成后明确导入并保留原图供校正，设置移除密钥延迟到保存。三平台构建及检查结果见 [UI 验证记录](ui-validation.json)，当前页面见 [SwiftUI 预览](previews/pages.png) 与 [iPhone 模拟器截图](previews/ios-pages.png)。

Debug 版本可使用 `--preview-editor` 或 `--preview-study` 直接打开示例页面，用于模拟器布局截图；这些入口不保存示例编辑或推演，也不会发起识别。正常启动不带参数即可。它们只用于检查布局，不能替代从残局库导航、真实手势及真机触感验证。

## 代码位置

| 目录 | 内容 |
| --- | --- |
| App | SwiftUI 页面、棋盘绘制、研究数据与会话、JSON 存储、触感 |
| Engine | Objective-C++ 桥接、搜索取消与安全吃子规则扩展 |
| Vendor/Pikafish | 固定版本上游 submodule |
| Resources | 图标、上游说明与本地准备的 NNUE |
| scripts | 资源准备、共享 Xcode 工程生成与构建 |

引擎适配发生在忽略的 `build/engine` 源码副本中：启用上游的本地内存分配后端；在 `Position` 中声明项目的安全吃子辅助接口。原始 submodule 保持干净，具体扩展实现在 `Engine/RulesExtension.cpp`。
