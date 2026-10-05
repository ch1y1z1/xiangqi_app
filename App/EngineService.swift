import Foundation

struct SafeCapture: Hashable {
    var move: ChessMove
    var side: Side
}

struct RuleSnapshot {
    var error: String?
    var legalMoves: [ChessMove] = []
    var inCheck = false
    var finished = false
    var outcome = ""
    var captures: [SafeCapture] = []
    init(study: Study, hints: Bool = true) {
        let data = PikafishBridge.inspect(fen: study.initialFEN, moves: study.currentLine.compactMap { $0.move?.uci }, hints: hints)
        error = (data["error"] as? String).map(Self.friendlyError)
        legalMoves = (data["legalMoves"] as? [String] ?? []).compactMap(ChessMove.init(uci:))
        inCheck = data["check"] as? Bool ?? false
        finished = data["finished"] as? Bool ?? false
        outcome = data["outcome"] as? String ?? ""
        captures = (data["captures"] as? [[String: String]] ?? []).compactMap {
            guard let raw = $0["move"], let move = ChessMove(uci: raw), let color = $0["side"], let side = Side(rawValue: color) else { return nil }
            return SafeCapture(move: move, side: side)
        }
    }
    static func friendlyError(_ text: String) -> String {
        if text.contains("number of kings") { return "红黑双方需要各放置一枚将帅。" }
        if text.contains("King can be captured") { return "将帅照面，或非行棋方的将帅正被将军。请调整摆子或先行方。" }
        let color = text.contains("WHITE") ? "红方" : "黑方"
        let kinds = [("advisor", "士"), ("bishop", "象"), ("king", "将帅"), ("pawn", "兵卒"), ("rook", "车"), ("knight", "马"), ("cannon", "炮")]
        if let kind = kinds.first(where: { text.contains($0.0) }) {
            if text.contains("invalid positions") { return "\(color)\(kind.1)不在标准规则允许的位置，请调整。" }
            if text.contains("more than") { return "\(color)\(kind.1)数量超过标准上限。" }
        }
        if text.contains("Illegal move") { return "这一步不符合象棋规则。" }
        if text.contains("More than 32") { return "棋子总数不能超过 32 枚。" }
        return "局面无法推演，请检查摆子与先行方。"
    }
}

struct AIResult {
    var move: ChessMove?
    var pv: [ChessMove]
    var depth: Int
    var score: Int
    var isMate: Bool
    var error: String?
    var cancelled: Bool
    init(_ data: [String: Any]) {
        move = (data["bestMove"] as? String).flatMap(ChessMove.init(uci:))
        pv = (data["pv"] as? String ?? "").split(separator: " ").compactMap { ChessMove(uci: String($0)) }
        depth = data["depth"] as? Int ?? 0
        score = data["score"] as? Int ?? 0
        isMate = data["mate"] as? Bool ?? false
        error = data["error"] as? String
        cancelled = data["cancelled"] as? Bool ?? false
    }
}

final class EngineService: @unchecked Sendable {
    static let shared = EngineService()
    private let bridge = PikafishBridge()
    private let queue = DispatchQueue(label: "xiangqi.engine", qos: .userInitiated)

    func stop() { bridge.stop() }
    func search(study: Study, milliseconds: Int, completion: @escaping (AIResult) -> Void) {
        bridge.stop()
        let token = bridge.beginRequest()
        let fen = study.initialFEN
        let moves = study.currentLine.compactMap { $0.move?.uci }
        let resource = Bundle.main.url(forResource: "pikafish", withExtension: "nnue")?.path ?? ""
        queue.async { [self] in
            let data = bridge.search(fen: fen, moves: moves, networkPath: resource, milliseconds: milliseconds, token: token)
            let result = AIResult(data)
            DispatchQueue.main.async { completion(result) }
        }
    }
}
