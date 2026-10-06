import Foundation

enum RecognitionThinking: String, Codable, CaseIterable, Identifiable {
    case off, low, high, max
    static let preferenceKey = "imageRecognitionThinking"
    static let defaultValue: Self = .high
    static var saved: Self {
        UserDefaults.standard.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? defaultValue
    }
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "关闭"
        case .low: return "低"
        case .high: return "高"
        case .max: return "最高"
        }
    }
    var detail: String {
        switch self {
        case .off: return "直接识别，响应较快。"
        case .low: return "进行少量思考，兼顾速度与核对。"
        case .high: return "默认使用更多思考核对棋盘，等待时间和额度消耗会增加。"
        case .max: return "使用最高思考强度，可能需要更长时间，也会消耗更多额度。"
        }
    }
    var maxTokens: Int { self == .off ? 4096 : self == .max ? 65536 : 32768 }
    var timeout: TimeInterval { self == .off ? 120 : self == .max ? 360 : 240 }
    var compatibleEffort: String { self == .off ? "none" : self == .max ? "xhigh" : rawValue }
}
