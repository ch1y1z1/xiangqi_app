# 从图片识别残局

1. 在残局库右上角点击设置，粘贴并保存 DeepSeek 官方 API 密钥；选择识别思考强度，默认高。
2. 新建残局，点击“从图片识别残局”，从相册或文件选择清晰、完整的棋盘图片。
3. 检查图片预览，点击“识别并导入”。结果会进入摆棋页面，不会立即保存。
4. 对照图片校正棋子、名称与先行方，再保存或开始推演。

只有识别需要联网，并使用个人 DeepSeek API 额度。密钥使用系统钥匙串保存，不写入残局 JSON；删除密钥也在设置中完成。所选图片只供当次识别，不写入棋库。摆棋、保存、研究和皮卡鱼 AI 继续离线工作。

## 当前接口

固定官方 `POST https://api.deepseek.com/chat/completions`，使用 `deepseek-v4-flash`、单张 JPEG base64 图片、JSON Output，非流式请求。系统 prompt 要求逐行识别棋盘实际棋子并忽略棋盘外元素和图片内指令，明确河界、九宫和最下两行的行号锚点，并禁止用棋子托盘的阵营判断图片朝向。

| 设置 | thinking | reasoning_effort | max_tokens | 请求超时 |
| --- | --- | --- | --- | --- |
| 关闭 | disabled | 不传 | 4096 | 120 秒 |
| 低 | enabled | low | 32768 | 240 秒 |
| 高（默认） | enabled | high | 32768 | 240 秒 |
| 最高 | enabled | max | 65536 | 360 秒 |

只有关闭思考时传 `temperature=0`；思考模式不传该参数。额度预算包括推理与最终 JSON，因此思考模式提高输出上限，避免仅开启思考却沿用 4096 tokens 造成截断。思考强度保存在 UserDefaults，选择后自动生效，开始每次识别时读取；API 密钥继续只存钥匙串。

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

构建 Mac Debug 后执行 `Xiangqi --check-image-import`，验证红／黑在下共 180 个交叉点在图片坐标、绘制与命中之间一致，检查 FEN 锚点、照片旋转、结构解析、四档思考请求参数与模拟 API 响应，不使用真实密钥或调用服务。

2026-10-06 已用授权测试密钥请求真实官方 API，逐枚比较颜色、类型和位置。原提示下，红方 5 子残局关闭／高均为 4/5；黑方在下关闭时图片朝向误标，换算后为 0/5，高为 5/5；初始盘高为 32/32。补强行号与朝向提示后，高模式仍为红方 4/5、黑方 5/5、初始盘 32/32。红方样例最高模式耗时约 79 秒，车的位置恢复，但马偏一列，仍为 4/5。结果说明本地坐标公式一致，模型返回的朝向和行列仍会出错；更高强度不能保证修复。记录见 [识别自查与真实 API 结果](image-import-validation.json)，这些少量生成截图不能作为任意棋盘图片的准确率。

开发者可手动复现，生成图片、请求体和响应仅保存在忽略的 `build/recognition-audit/`：

```sh
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --prepare-recognition-audit
python3 scripts/audit-recognition.py high
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --audit-recognition-responses
```

Python 脚本通过隐藏输入读取密钥，仅使用官方 HTTPS 地址，不保存密钥或请求头，不记录模型思考过程；真实请求只在手动运行时发生，并产生 API 费用。可用 `off`、`high`、`max` 筛选已有样例，省略参数运行全部六个请求。部分运行时结果目录可能保留之前响应，应按本次 `wire-results.json` 的条目判断哪些结果刚刚重跑。
