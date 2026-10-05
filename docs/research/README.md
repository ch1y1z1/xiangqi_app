# 独立引擎技术探针

这些文件保留前期独立引擎探针，用于复核调研结论。该探针没有 Swift UI、签名或 iOS 沙盒容器；其 iOS 产物只进行了编译、链接与平台检查，运行仅在 Mac 上执行。后续产品 App 的三平台构建与模拟器沙盒检查另见 [开发说明](../development.md) 和 [App 验证记录](../development-validation.json)。

测试版本为官方 Pikafish-2026-09-06，提交 `4c17cee11f888ae1d48a9494f2e2239f019f0a1f`。调研探针当时使用临时目录；产品现在通过 submodule 引入源码，准备脚本校验并打包权重。[固定版本源码](https://github.com/official-pikafish/Pikafish/tree/Pikafish-2026-09-06)、[正式发布包](https://github.com/official-pikafish/Pikafish/releases/tag/Pikafish-2026-09-06)。

本轮实际结果见 [validation-results.json](validation-results.json)。`compile-engine-probe.py` 将本轮构建步骤整理为可重跑脚本，`inprocess-probe.cpp` 保留了实际运行的 C++ 测试。

在 Apple Silicon Mac 上准备固定版本源码与对应 NNUE 后运行：

```sh
python3 docs/research/compile-engine-probe.py \
  --source /path/to/Pikafish \
  --network /path/to/pikafish.nnue \
  --output /tmp/xiangqi-probe-output
```

需要已选择的 Xcode 与对应 SDK。脚本不会下载源码、权重或模拟器 runtime，不会运行 iOS 探针，也不会修改引擎源码。只想编译单个平台可以传入 `--target ios`、`--target sim` 或 `--target mac`。

构建参数是技术验证参数，未经手机调优。不同 SDK、编译器、系统状态会改变运行输出、搜索结果与内存峰值；不要将桌面数值当作 iPhone 性能指标。
