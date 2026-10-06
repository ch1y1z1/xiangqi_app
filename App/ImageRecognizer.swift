import Foundation

struct ImageRecognizer {
    static let sharedSession = URLSession(configuration: .ephemeral)
    var session: URLSession = Self.sharedSession

    static func request(jpeg: Data, key: String, settings: RecognitionSettings) throws -> URLRequest {
        try settings.validate(key: key)
        if settings.provider == .deepSeek {
            return try DeepSeekRecognizer.request(jpeg: jpeg, key: key, thinking: settings.deepSeekThinking)
        }
        var request = URLRequest(url: try settings.endpoint(), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: settings.thinking?.timeout ?? 240)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let imageURL = "data:image/jpeg;base64," + jpeg.base64EncodedString()
        let instruction = "请识别这张图片里的中国象棋残局，按约定输出 JSON。"
        var body: [String: Any] = ["model": settings.model.trimmingCharacters(in: .whitespacesAndNewlines), "stream": false]
        switch settings.api {
        case .chatCompletions:
            body["messages"] = [
                ["role": "system", "content": DeepSeekRecognizer.prompt],
                ["role": "user", "content": [
                    ["type": "text", "text": instruction],
                    ["type": "image_url", "image_url": ["url": imageURL, "detail": "high"]]
                ]]
            ]
            body["response_format"] = ["type": "json_object"]
            if let thinking = settings.customThinking {
                body["reasoning_effort"] = thinking.compatibleEffort
                body["max_completion_tokens"] = thinking.maxTokens
            }
        case .responses:
            body["instructions"] = DeepSeekRecognizer.prompt
            body["input"] = [["role": "user", "content": [
                ["type": "input_text", "text": instruction],
                ["type": "input_image", "image_url": imageURL, "detail": "high"]
            ]]]
            body["text"] = ["format": ["type": "json_object"]]
            body["store"] = false
            if let thinking = settings.customThinking {
                body["reasoning"] = ["effort": thinking.compatibleEffort]
                body["max_output_tokens"] = thinking.maxTokens
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func recognize(jpeg: Data, key: String, settings: RecognitionSettings) async throws -> RecognizedSetup {
        let (data, response) = try await session.data(for: Self.request(jpeg: jpeg, key: key, settings: settings))
        try Task.checkCancellation()
        let service = settings.serviceName
        guard let response = response as? HTTPURLResponse else { throw ImageImportError(message: "\(service)未返回有效响应。") }
        switch response.statusCode {
        case 200...299: break
        case 400: throw ImageImportError(message: "\(service)不接受当前请求，请检查模型、接口类型、图片与 JSON 输出支持；自定义服务可将思考强度设为服务默认。")
        case 401, 403: throw ImageImportError(message: "\(service)密钥无效或没有权限，请在设置中检查。")
        case 402: throw ImageImportError(message: "\(service)账户余额不足，请充值后重试。")
        case 404: throw ImageImportError(message: "未找到\(service)的接口或模型，请检查 API 地址、接口类型与模型名称。")
        case 429: throw ImageImportError(message: "\(service)请求过于频繁或额度不足，请稍后重试。")
        default: throw ImageImportError(message: "\(service)请求失败（\(response.statusCode)），请稍后重试。")
        }
        let api: RecognitionAPI = settings.provider == .deepSeek ? .chatCompletions : settings.api
        let content: String
        do { content = try Self.content(from: data, api: api, service: service) }
        catch let error as ImageImportError { throw error }
        catch { throw ImageImportError(message: "无法读取\(service)的识别响应，请检查接口类型。") }
        return try RecognizedSetup.parse(content)
    }

    private static func content(from data: Data, api: RecognitionAPI, service: String) throws -> String {
        switch api {
        case .chatCompletions:
            struct Completion: Decodable {
                struct Choice: Decodable {
                    struct Message: Decodable { var content: String?; var refusal: String? }
                    var message: Message
                    var finish_reason: String?
                }
                var choices: [Choice]
            }
            let completion = try JSONDecoder().decode(Completion.self, from: data)
            guard let choice = completion.choices.first else { throw ImageImportError(message: "\(service)没有返回识别结果，请重试。") }
            guard choice.finish_reason != "length" else { throw ImageImportError(message: "识别结果不完整，请重试。") }
            guard choice.message.refusal == nil, choice.finish_reason != "content_filter" else {
                throw ImageImportError(message: "模型拒绝识别这张图片，请更换图片或模型。")
            }
            guard let content = choice.message.content, !content.isEmpty else {
                throw ImageImportError(message: "\(service)没有返回识别结果，请重试。")
            }
            return content
        case .responses:
            struct Response: Decodable {
                struct Output: Decodable {
                    struct Part: Decodable { var type: String; var text: String? }
                    var type: String
                    var role: String?
                    var status: String?
                    var content: [Part]?
                }
                var status: String?
                var output: [Output]
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard response.status != "incomplete" else { throw ImageImportError(message: "识别结果不完整，请重试。") }
            guard response.status == nil || response.status == "completed" else {
                throw ImageImportError(message: "\(service)未完成识别，请检查模型或稍后重试。")
            }
            let messages = response.output.filter { $0.type == "message" && $0.role == "assistant" }
            guard !messages.contains(where: { $0.status == "incomplete" }) else {
                throw ImageImportError(message: "识别结果不完整，请重试。")
            }
            guard messages.allSatisfy({ $0.status == nil || $0.status == "completed" }) else {
                throw ImageImportError(message: "\(service)未完成识别，请稍后重试。")
            }
            let parts = messages.flatMap { $0.content ?? [] }
            guard !parts.contains(where: { $0.type == "refusal" }) else {
                throw ImageImportError(message: "模型拒绝识别这张图片，请更换图片或模型。")
            }
            let content = parts.filter { $0.type == "output_text" }.compactMap(\.text).joined()
            guard !content.isEmpty else { throw ImageImportError(message: "\(service)没有返回识别结果，请重试。") }
            return content
        }
    }
}
