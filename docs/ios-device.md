# IPA 与真机调试

当前可以在没有签名证书的环境中生成设备用 IPA，供个人签名工具重新签名。这个 IPA 不是模拟器包；它使用 arm64、iOS 17+，已包含离线 NNUE。

## 生成 IPA

```sh
zsh scripts/package-ipa.sh Debug
# 如需优化后的体验测试包：
zsh scripts/package-ipa.sh Release
```

脚本使用 Xcode 的 device archive，保留对应 dSYM，并将 App 打包为标准 `Payload/Xiangqi.app` 结构。输出位置：

- `build/ipa/Xiangqi-0.1.0-debug-unsigned.ipa`
- `build/Archives/Xiangqi-Debug-unsigned.xcarchive`
- 调试符号在该 archive 的 `dSYMs/Xiangqi.app.dSYM`。

Release 的文件名和目录对应替换为 `release`／`Release`。构建产物和个人签名信息均不提交 Git。

## 安装方式

**已有签名工具：** 导入未签名 IPA，使用自己的 iOS 证书和描述文件重新签名，再按该工具的流程安装。开发或设备测试描述文件需要覆盖目标手机；签名工具若更改 bundle identifier，需要保证相应描述文件匹配。不要把未签名 IPA 当成可直接安装的包。

**通过当前 Mac 的 Xcode 直接调试：**

1. 在 Xcode → Settings → Apple Accounts 登录自己的 Apple Account。
2. 打开 `Xiangqi.xcodeproj`，选择 Xiangqi target → Signing & Capabilities，选择自己的 Team，并启用 Automatically manage signing。
3. 连接并信任 iPhone，选择它作为运行设备。按 Xcode 提示启用手机的 Developer Mode，再运行 App。

Xcode 可创建开发描述文件并安装 App，适合断点和运行日志调试。安装流程依据 [Apple 设备运行说明](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices) 与 [Developer Mode 说明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。需要调试器附加时，重新签名应使用允许调试的开发签名；仅选择 Debug 编译配置不会自动授予调试权限。

工程生成脚本会重建 project 文件。个人 Team 应在最后一次生成之后配置；不要将个人签名配置、证书或描述文件推送到公开仓库。

## 本次归档记录

2026-10-05 的 Debug device archive 已成功生成：

- App `0.1.0 (1)`，bundle identifier `com.chiyizi.xiangqi`。
- Mach-O 平台 IOS、arm64，最低 iOS 17.0，SDK 26.4。
- ZIP 校验及 NNUE SHA-256 校验通过；App 与 dSYM UUID 匹配。
- 当前环境没有有效签名身份或描述文件，因此本次产物明确为未签名包。

首次真机使用只需确认一个闭环：摆棋与保存、回退产生分支、推荐与采用、对方托管；再看触摸／拖动、动画／震动、切后台和一次引擎内存。无需重跑全面测试矩阵。
