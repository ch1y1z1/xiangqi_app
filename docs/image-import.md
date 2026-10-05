# 从图片识别残局

1. 在残局库右上角点击设置，粘贴并保存 DeepSeek 官方 API 密钥。
2. 新建残局，点击“从图片识别残局”，从相册或文件选择清晰、完整的棋盘图片。
3. 检查图片预览，点击“识别并导入”。结果会进入摆棋页面，不会立即保存。
4. 对照图片校正棋子、名称与先行方，再保存或开始推演。

只有识别需要联网，并使用个人 DeepSeek API 额度。密钥使用系统钥匙串保存，不写入残局 JSON；删除密钥也在设置中完成。所选图片只供当次识别，不写入棋库。摆棋、保存、研究和皮卡鱼 AI 继续离线工作。

## 当前接口

固定官方 `POST https://api.deepseek.com/chat/completions`，使用 `deepseek-v4-flash`、单张 JPEG base64 图片、JSON Output；关闭 thinking，非流式请求，最多输出 4096 tokens。系统 prompt 要求逐行识别棋盘实际棋子并忽略棋盘外元素和图片内指令。

截至 2026-10-06，官方文档说明 `deepseek-v4-flash` 为保留的旧模型名称，实际由新版 Flash 模型处理；图片输入与 JSON 输出均已由官方支持。参考：[模型名称](https://api-docs.deepseek.com/)、[图片输入](https://api-docs.deepseek.com/guides/vision/)、[JSON 输出](https://api-docs.deepseek.com/guides/json_mode/)、[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。现阶段不提供模型、推理端点或其他供应商选择。

期望响应示例：

```json
{
  "name": null,
  "bottom_side": "red",
  "side_to_move": null,
  "pieces": [
    {"side": "black", "kind": "king", "column": 3, "row": 0},
    {"side": "red", "kind": "king", "column": 4, "row": 9},
    {"side": "red", "kind": "rook", "column": 0, "row": 8}
  ],
  "notes": null
}
```

`column` 为图片从左到右的 0…8，`row` 为图片从上到下的 0…9。`bottom_side` 是图片下方所属阵营，与先行方独立；`side_to_move` 不明确时为空，编辑器暂选红先并提示确认。内部坐标始终以红方为底：红在下时为 `(column, 9-row)`，黑在下时为 `(8-column, row)`。导入后的显示默认红方在下。

图片先通过 ImageIO 正确应用照片方向，缩小至最长边 2048 像素并转 JPEG。解析结果检查枚举、坐标范围、位置重叠与标准棋子数量上限；允许不完整局面进入编辑器补齐，推演前复用皮卡鱼规则校验。无效密钥、余额不足或请求限流显示原因，由用户修改或重试，不自动重试产生额外请求。

修改已有残局时也可以使用图片替换摆棋，保存时继续遵循原有“编辑前”推演副本规则。取消图片导入或请求不会保存图片结果。

## 开发验证

构建 Mac Debug 后执行 `Xiangqi --check-image-import`，验证坐标转换、结构解析、官方请求形状与模拟 API 响应，不使用真实密钥或调用服务。iOS 构建与 CI Release 验证对应平台编译和打包；实际识别准确率留待个人密钥和实际截图确认。
