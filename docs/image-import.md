# 从图片识别残局

1. 在残局库右上角点击设置，选择 DeepSeek 官方或自定义服务，填写服务信息；思考强度在高级设置中，再点击“保存设置”。
2. 新建残局，点击顶部图片图标，从相册或文件选择清晰、完整的棋盘图片。
3. 检查图片预览，点击“识别棋盘”。完成后点击“导入并校正”才替换摆棋，不会立即保存。
4. 点击编辑器顶部原图入口，双击或捏合放大，对照图片校正棋子、名称与先行方，再保存或开始推演。

只有识别需要连接配置的服务，收费服务使用个人 API 额度。DeepSeek 与自定义密钥分别使用系统钥匙串保存，不写入残局 JSON；移除密钥在设置中暂存，点击保存才生效，取消不会移除。所选图片只供当次识别，暂存在识别工作目录供恢复与校正使用，不写入棋库，导入或停止后删除工作目录；编辑器暂留原图内存副本用于校正，保存或取消编辑后释放。摆棋、保存、研究和皮卡鱼 AI 继续离线工作。

## 切屏、锁屏与恢复

识别期间可以正常切换 App 或锁屏。iOS 使用固定标识的后台 `URLSession`，将包含图片的 JSON 请求体写入文件后调用 `uploadTask(with:fromFile:)`，由系统网络进程执行；请求仍为原来的非流式 POST，两种接口及 DeepSeek 参数不变。用户在前台点击识别时立即创建任务，`isDiscretionary=false`，网络资源总超时为 360 秒，保留请求自身的各档超时设置。Mac 使用同一文件上传和任务状态逻辑，但不需要 iOS 后台会话。

识别任务由应用级 `ImageRecognitionJob` 持有，页面的 `onDisappear` 只取消照片读取，不取消已发出的识别。返回或关闭识别页面不取消任务，回来后继续等待；完成结果始终由用户点击“导入并校正”送入编辑器；后台完成时先保存结果，不在后台修改棋盘。明确点击“停止”会取消传输、清理工作目录并清除任务 ID，之后收到的迟到回调不再生效。

工作目录保存单个任务的 Codable JSON 状态、校正用 JPEG，以及传输中的请求和响应文件，并排除系统备份；iOS 文件保护允许首次解锁后的锁屏传输。密钥只放在请求头，不写入这些文件。传输回调结束后清理原始请求与响应，图片和解析结果保留至导入、取消或开始下一次识别。恢复时如果完成回调尚未送达，暂留传输文件以接收剩余回调；取消或开始下一次识别也会清理。应用接收 `handleEventsForBackgroundURLSession`，使用同一会话标识重连系统任务并在回调处理完成后通知系统。App 被系统结束后重新打开，残局库显示识别状态入口；用户查看并主动导入结果，避免覆盖另一盘残局。该机制不自动保存或恢复原编辑器尚未保存的摆棋草稿。

用户从多任务界面强制关闭 App，iOS 会取消后台传输；网络断开、服务端超时或系统调度也可能造成失败。恢复时若没有对应的系统任务，会显示中断提示并保留图片供重试，不自动重新发起付费请求。当前同步接口不支持用任务 ID 取回服务器已生成但未成功收到的推理结果。

参考：[后台文件传输](https://developer.apple.com/documentation/foundation/downloading-files-in-the-background)、[上传任务与响应](https://developer.apple.com/documentation/foundation/urlsessionuploadtask)、[后台会话与强制关闭限制](https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:))。

## DeepSeek 官方

固定官方 `POST https://api.deepseek.com/chat/completions`，使用 `deepseek-v4-flash`、单张 JPEG base64 图片、JSON Output，非流式请求。系统 prompt 要求逐行识别棋盘实际棋子并忽略棋盘外元素和图片内指令，明确河界、九宫和最下两行的行号锚点，并禁止用棋子托盘的阵营判断图片朝向。

| 设置 | thinking | reasoning_effort | max_tokens | 请求超时 |
| --- | --- | --- | --- | --- |
| 关闭 | disabled | 不传 | 4096 | 120 秒 |
| 低 | enabled | low | 32768 | 240 秒 |
| 高（默认） | enabled | high | 32768 | 240 秒 |
| 最高 | enabled | max | 65536 | 360 秒 |

只有关闭思考时传 `temperature=0`；思考模式不传该参数。额度预算包括推理与最终 JSON，因此思考模式提高输出上限，避免仅开启思考却沿用 4096 tokens 造成截断。配置保存在 UserDefaults，点击保存后生效，开始每次识别时固定读取这份配置；API 密钥继续只存钥匙串。已有 DeepSeek 密钥与思考设置继续可用。

截至 2026-10-06，官方文档说明 `deepseek-v4-flash` 为保留的旧模型名称，实际由新版 Flash 模型处理；图片输入与 JSON 输出均已由官方支持。参考：[模型名称](https://api-docs.deepseek.com/)、[图片输入](https://api-docs.deepseek.com/guides/vision/)、[JSON 输出](https://api-docs.deepseek.com/guides/json_mode/)、[思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)。

## 自定义服务

选择 OpenAI 兼容的 **Chat Completions** 或 **Responses**，填写 API 地址、模型名称与可选 Bearer 密钥。模型必须支持图片输入及 JSON 对象输出；旧式纯文本 `/completions` 不在范围内。

| 接口类型 | 基础地址示例 | 最终请求地址 |
| --- | --- | --- |
| Chat Completions | `https://example.com/v1` | `https://example.com/v1/chat/completions` |
| Responses | `https://example.com/v1` | `https://example.com/v1/responses` |

也可以直接粘贴表中的完整请求地址。切换类型时替换标准接口后缀，保留前面的服务路径和查询参数；不会额外添加 `/v1`。设置的高级区域显示最终请求地址。支持 HTTPS 及自建服务的 HTTP 地址，例如 `http://192.168.1.10:8000/v1`；iPhone 上的 localhost 指手机本身，访问 Mac 的服务请填 Mac 的局域网地址，并允许系统的本地网络访问。

两种接口共用 DeepSeek 识别 prompt、照片处理、坐标换算和结构校验，都使用非流式请求，不自动重试或切换接口。

| 内容 | Chat Completions | Responses |
| --- | --- | --- |
| 图片输入 | `messages[].content` 的 `image_url` 对象 | `input[].content` 的 `input_image`，`image_url` 为字符串 |
| JSON 输出 | `response_format.type=json_object` | `text.format.type=json_object` |
| 最终文本 | `choices[0].message.content` | `output` 中 assistant message 的 `output_text.text`；不读取 reasoning 内容 |
| 手动思考强度 | `reasoning_effort` | `reasoning.effort` |
| 手动输出预算 | `max_completion_tokens` | `max_output_tokens` |

自定义思考默认“服务默认”，不传思考参数或输出上限，以兼容非推理模型。手动选关闭／低／高／最高分别传 `none/low/high/xhigh`，预算和超时沿用上表，需要服务和模型支持这些标准参数；自定义请求不传 DeepSeek 专用 `thinking` 或 `temperature`。Responses 另传 `store=false`，不建立会话。服务返回截断、拒绝或未完成结果时提示错误，不导入部分棋谱。

格式参考：[Chat Completions API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create)、[图片输入](https://developers.openai.com/api/docs/guides/images-vision)、[两种接口的格式区别](https://developers.openai.com/api/docs/guides/migrate-to-responses)。

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

修改已有残局时也可以使用图片替换摆棋，保存时继续遵循原有“编辑前”推演副本规则。停止识别不会导入结果；返回识别页保留任务。编辑器中未保存的识别校正随取消编辑丢弃。

## 开发验证

构建 Mac Debug 后执行 `Xiangqi --check-image-import`，验证坐标、照片旋转与结构解析、DeepSeek 四档请求、自定义地址与可选鉴权、两种接口的请求和模拟响应、标准思考参数及截断拒绝，以及文件上传、完成结果恢复、取消后迟到回调、HTTP 错误和缺失系统任务的中断恢复，不使用真实密钥或调用服务。iOS 后台网络由系统控制，Mac 模拟请求不能替代真机切屏／锁屏验证。

2026-10-06 已用授权测试密钥请求真实官方 API，逐枚比较颜色、类型和位置。原提示下，红方 5 子残局关闭／高均为 4/5；黑方在下关闭时图片朝向误标，换算后为 0/5，高为 5/5；初始盘高为 32/32。补强行号与朝向提示后，高模式仍为红方 4/5、黑方 5/5、初始盘 32/32。红方样例最高模式耗时约 79 秒，车的位置恢复，但马偏一列，仍为 4/5。结果说明本地坐标公式一致，模型返回的朝向和行列仍会出错；更高强度不能保证修复。记录见 [识别自查与真实 API 结果](image-import-validation.json)，这些少量生成截图不能作为任意棋盘图片的准确率。

开发者可手动复现，生成图片、请求体和响应仅保存在忽略的 `build/recognition-audit/`：

```sh
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --prepare-recognition-audit
python3 scripts/audit-recognition.py high
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --audit-recognition-responses
```

Python 脚本通过隐藏输入读取密钥，仅使用官方 HTTPS 地址，不保存密钥或请求头，不记录模型思考过程；真实请求只在手动运行时发生，并产生 API 费用。可用 `off`、`high`、`max` 筛选已有样例，省略参数运行全部六个请求。部分运行时结果目录可能保留之前响应，应按本次 `wire-results.json` 的条目判断哪些结果刚刚重跑。

### GPT Luna 自定义服务实测

2026-10-06 从用户授权的自定义端点读取到 18 个模型条目，其中 Luna 为 `cx/gpt-5.6-luna` 与同版本 `cx/gpt-5.6-luna-review`。列表没有创建时间，按可用 Luna 的最高版本号选择普通路由 `cx/gpt-5.6-luna`；不把 review 路由当作更新版本。

使用当前 App 的图片处理、prompt、请求生成器及服务默认思考设置；Python 发送真实 HTTP 请求，返回的最终文本交给 Swift 的实际解析器与坐标换算，逐枚对比已知 FEN。4 张实际 SwiftUI 编辑器截图各在两种接口下请求一次，结果如下：

| 截图 | Chat Completions 正确棋子／耗时 | Responses 正确棋子／耗时 |
| --- | --- | --- |
| 红方在下，5 子残局 | 5/5 · 13.04 秒 | 5/5 · 10.63 秒 |
| 黑方在下，5 子残局 | 5/5 · 10.35 秒 | 5/5 · 12.08 秒 |
| 红方在下，32 子初始盘 | 32/32 · 28.55 秒 | 32/32 · 40.98 秒 |
| 黑方在下，32 子初始盘 | 32/32 · 25.07 秒 | 32/32 · 7.29 秒 |

HTTP 成功 8/8、整盘完全匹配 8/8、朝向正确 8/8；148 次棋子核对均正确，没有漏子或多子。两种接口平均耗时分别为 19.25 秒与 17.75 秒，全部请求平均 18.50 秒。此前 DeepSeek 红方 5 子样例的车位偏一行，本轮两种接口均正确识别为 a1。

这里的 100% 仅表示 4 张生成截图的观测结果，包含同一图片在两种接口下的重复测试；样本仅有两种不同局面，不能推断拍照、模糊图片或其他象棋 App 截图的普遍成功率。未测试 review 路由或手动思考档位。Chat Completions 返回模型名 `gpt-5.6-luna`；Responses 的返回体未标明模型名。详细计数与每次请求记录见 [自定义服务验证结果](custom-recognition-validation.json)。

开发者可复现自定义服务测试；以下地址为占位示例，换成已授权的服务地址：

```sh
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --prepare-recognition-audit --audit-endpoint https://example.com/v1 --audit-model cx/gpt-5.6-luna --audit-api responses --audit-output build/custom-audit/responses
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --prepare-recognition-audit --audit-endpoint https://example.com/v1 --audit-model cx/gpt-5.6-luna --audit-api chatCompletions --audit-output build/custom-audit/completions
python3 scripts/audit-custom-recognition.py https://example.com/v1 build/custom-audit/responses build/custom-audit/completions
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --audit-recognition-responses --audit-output build/custom-audit/responses
build/DerivedData/Build/Products/Debug/Xiangqi.app/Contents/MacOS/Xiangqi --audit-recognition-responses --audit-output build/custom-audit/completions
```

省略 `--audit-thinking` 使用服务默认，也可指定 `off/low/high/max`。准备步骤只生成截图和无密钥请求体；Python 脚本通过隐藏输入读取密钥，两路并发，只向命令指定来源发请求，不跟随重定向、不自动重试；请求前删除该样例的旧响应，避免旧结果误计为本次成功。密钥不写入 App 配置或钥匙串，生成文件仅保存在忽略的 `build/`。

### 用户提供的 JJ 象棋实图与全部思考档位

2026-10-06 使用用户提供的第 32 关（14 子）和第 31 关（16 子）完整截图，分别测试 DeepSeek 关闭／低／高／最高四档，以及 Luna 服务默认／关闭／低／高／最高五档，共 18 次真实请求。所有请求使用相同 prompt 和同一图片对应的相同 JPEG，没有裁剪或添加网格。人工棋子基准在请求前标定。

本轮唯一整盘完全匹配的是 DeepSeek 高档的第 31 关；第 32 关所有设置均有错误或无最终输出。Luna 低档的棋子匹配最好，为 27/30，但两张图仍需校正。DeepSeek 高档第 32 关耗尽 32768 tokens 而未返回最终 JSON；Luna 第 31 关的部分结果因重复位置或黑士数量超限被 App 拒绝导入。提高强度未稳定提升结果，先前生成截图的 100% 不能外推到真实 JJ 截图。

完整耗时、正确棋子数、整盘成功和 tokens 对照见 [JJ 实图测试表格](jj-recognition-comparison.md)，人工基准、请求参数与逐枚差异见 [原始验证记录](jj-recognition-validation.json)。每张图在每档只测一次，尚不能估计普遍成功率。原图与密钥不提交仓库。

可用 `--audit-input` 指定本地 JSON 样例列表，每项包含 `test`、`image`、`expected_fen`、`expected_bottom_side`。不指定自定义服务参数时，生成所给图片的 DeepSeek 全四档请求；自定义服务继续用 `--audit-thinking` 指定当前档。Swift 审计区分结构校验是否通过与棋子匹配情况，对可解码但校验失败的结果保留诊断计数。
