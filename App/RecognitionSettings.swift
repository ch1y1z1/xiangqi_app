import Foundation

enum RecognitionProvider: String, Codable, CaseIterable, Identifiable {
    case deepSeek, custom
    var id: String { rawValue }
    var title: String { self == .deepSeek ? "DeepSeek 官方" : "自定义服务" }
    var keychainSuffix: String { self == .deepSeek ? ".deepseek" : ".recognition-custom" }
}

enum RecognitionAPI: String, Codable, CaseIterable, Identifiable {
    case chatCompletions, responses
    var id: String { rawValue }
    var title: String { self == .chatCompletions ? "Chat Completions" : "Responses" }
    var path: String { self == .chatCompletions ? "/chat/completions" : "/responses" }
}

struct RecognitionSettings: Codable {
    var provider: RecognitionProvider = .deepSeek
    var address = ""
    var model = ""
    var api: RecognitionAPI = .chatCompletions
    var deepSeekThinking: RecognitionThinking = .saved
    // nil leaves reasoning and token limits to the custom service.
    var customThinking: RecognitionThinking?

    private static let preferenceKey = "imageRecognitionSettings"
    static var saved: Self {
        guard let data = UserDefaults.standard.data(forKey: preferenceKey),
              let settings = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return settings
    }
    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.preferenceKey)
        UserDefaults.standard.set(deepSeekThinking.rawValue, forKey: RecognitionThinking.preferenceKey)
    }
    var thinking: RecognitionThinking? { provider == .deepSeek ? deepSeekThinking : customThinking }
    var serviceName: String { provider == .deepSeek ? "DeepSeek" : "自定义服务" }
    var description: String { provider == .deepSeek ? "DeepSeek · \(deepSeekThinking.title)思考" : "\(model) · \(api.title)" }

    func endpoint() throws -> URL {
        if provider == .deepSeek { return DeepSeekRecognizer.endpoint }
        guard var parts = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, parts.fragment == nil else {
            throw ImageImportError(message: "请填写有效的 HTTP 或 HTTPS API 地址。")
        }
        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        // A full standard endpoint can be pasted; switching API changes only its suffix.
        for format in RecognitionAPI.allCases where path.hasSuffix(format.path) {
            path.removeLast(format.path.count)
            break
        }
        parts.path = path + api.path
        guard let url = parts.url else { throw ImageImportError(message: "API 地址格式不正确。") }
        return url
    }

    func validate(key: String) throws {
        _ = try endpoint()
        if provider == .deepSeek {
            guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ImageImportError(message: "请先在设置中保存 DeepSeek API 密钥。")
            }
        } else if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ImageImportError(message: "请先在设置中填写自定义模型名称。")
        }
    }
}
