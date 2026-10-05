# 象棋残局研究 App

面向个人使用的离线象棋残局研究工具，主要支持 iPhone。采用 Swift／SwiftUI 与进程内 Pikafish，初期使用原生 macOS 入口快速开发调试，同时保持 iOS 目标可编译。

## 首版功能

- 自由摆放残局，选择红先／黑先，保存与查看残局。
- 默认双方手动推演，回退改走保留多个分支。
- 离线 AI 推荐下一步、采用建议，以及 AI 接管对方。
- 合法落点、上一手、将军与安全吃子红绿灯。
- 默认红方在下，可切换黑方在下；落子动画与 iPhone 震动反馈。

首版优先完成可用闭环，使用 Codable JSON 保存，采用一套浅木棋桌视觉，仅做关键流程验证。

## 当前状态与文档

当前已完成需求调研和独立引擎探针，尚未创建完整 App 工程。

- [首版产品规格与页面布局](docs/product-spec.md)
- [需求与技术调研报告](docs/xiangqi-ios-research-report.md)
- [引擎探针与复现方法](docs/research/README.md)
- [实际探针结果](docs/research/validation-results.json)

已验证 Pikafish 在 Mac 上的进程内搜索，以及 iOS／模拟器目标的 C++ 编译与链接；这些结果不代表完整 App 或 iPhone 运行已经验证。

## 开发顺序

1. 共享 SwiftUI 工程、棋盘、编辑、保存、多分支手动研究，Mac 可运行。
2. Pikafish 桥接、推荐与托管、落点与红绿灯。
3. iPhone 布局、动画、震动与个人设备安装。

## 许可证与上游

本仓库代码采用 [GPL-3.0](LICENSE)。Pikafish 接入时保留上游许可证、版本与修改记录。

当前仓库不包含 Pikafish 源码或 NNUE 权重。权重按[官方独立使用条款](https://github.com/official-pikafish/Networks/blob/master/README.md)管理，后续资源准备步骤会固定对应版本与校验值；App 安装包将包含离线所需资源。

上游：[Pikafish](https://github.com/official-pikafish/Pikafish)，技术验证固定为 `Pikafish-2026-09-06`。
