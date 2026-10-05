import Foundation

enum Side: String, Codable, CaseIterable, Identifiable {
    case red, black
    var id: String { rawValue }
    var title: String { self == .red ? "红方" : "黑方" }
    var opponent: Side { self == .red ? .black : .red }
    var fen: String { self == .red ? "w" : "b" }
}

enum PieceKind: String, Codable, CaseIterable, Identifiable {
    case king, advisor, elephant, horse, rook, cannon, pawn
    var id: String { rawValue }
    var limit: Int { self == .king ? 1 : self == .pawn ? 5 : 2 }
    var fen: String {
        switch self {
        case .king: return "k"
        case .advisor: return "a"
        case .elephant: return "b"
        case .horse: return "n"
        case .rook: return "r"
        case .cannon: return "c"
        case .pawn: return "p"
        }
    }
    func glyph(_ side: Side) -> String {
        switch self {
        case .king: return side == .red ? "帅" : "将"
        case .advisor: return side == .red ? "仕" : "士"
        case .elephant: return side == .red ? "相" : "象"
        case .horse: return "马"
        case .rook: return "车"
        case .cannon: return "炮"
        case .pawn: return side == .red ? "兵" : "卒"
        }
    }
}

struct BoardSquare: Codable, Hashable, Identifiable {
    var file: Int
    var rank: Int // Rank zero is always Red's home rank, irrespective of display orientation.
    var id: String { uci }
    var uci: String { String(UnicodeScalar(97 + file)!) + String(rank) }
    init(file: Int, rank: Int) { self.file = file; self.rank = rank }
    init?(uci: String) {
        let characters = Array(uci)
        guard characters.count == 2, let ascii = characters[0].asciiValue,
              (97...105).contains(ascii), let rank = Int(String(characters[1])), (0...9).contains(rank) else { return nil }
        self.file = Int(ascii) - 97
        self.rank = rank
    }
}

struct ChessPiece: Identifiable, Codable, Hashable {
    var id = UUID()
    var side: Side
    var kind: PieceKind
    var square: BoardSquare
}

struct ChessMove: Codable, Hashable {
    var from: BoardSquare
    var to: BoardSquare
    var uci: String { from.uci + to.uci }
    init(from: BoardSquare, to: BoardSquare) { self.from = from; self.to = to }
    init?(uci: String) {
        guard uci.count == 4, let from = BoardSquare(uci: String(uci.prefix(2))),
              let to = BoardSquare(uci: String(uci.suffix(2))), from != to else { return nil }
        self.from = from; self.to = to
    }
    func notation(in pieces: [ChessPiece]) -> String {
        guard let piece = pieces.first(where: { $0.square == from }) else { return uci }
        let chinese = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]
        func number(_ value: Int) -> String { piece.side == .red ? chinese[max(0, min(8, value - 1))] : String(value) }
        func fileName(_ file: Int) -> String { number(piece.side == .red ? 9 - file : file + 1) }
        let peers = pieces.filter { $0.side == piece.side && $0.kind == piece.kind && $0.square.file == from.file }
            .sorted { piece.side == .red ? $0.square.rank > $1.square.rank : $0.square.rank < $1.square.rank }
        var name = piece.kind.glyph(piece.side) + fileName(from.file)
        if peers.count > 1, let index = peers.firstIndex(where: { $0.id == piece.id }) {
            let prefix = index == 0 ? "前" : index == peers.count - 1 ? "后" : peers.count == 3 ? "中" : number(index + 1)
            name = prefix + piece.kind.glyph(piece.side)
        }
        if to.rank == from.rank { return name + "平" + fileName(to.file) }
        let forward = piece.side == .red ? to.rank > from.rank : to.rank < from.rank
        let target = [.horse, .elephant, .advisor].contains(piece.kind) ? fileName(to.file) : number(abs(to.rank - from.rank))
        return name + (forward ? "进" : "退") + target
    }
}

enum ChessPosition {
    static let initialFEN = "rnbakabnr/9/1c5c1/p1p1p1p1p/9/9/P1P1P1P1P/1C5C1/9/RNBAKABNR w - - 0 1"
    static func pieces(fen: String) -> [ChessPiece] {
        let board = fen.split(separator: " ").first ?? ""
        var result: [ChessPiece] = []
        for (row, content) in board.split(separator: "/").enumerated() {
            var file = 0
            for character in content {
                if let spaces = character.wholeNumberValue { file += spaces; continue }
                if let kind = PieceKind.allCases.first(where: { $0.fen == String(character).lowercased() }) {
                    result.append(ChessPiece(side: character.isUppercase ? .red : .black, kind: kind,
                                             square: BoardSquare(file: file, rank: 9 - row)))
                }
                file += 1
            }
        }
        return result
    }
    static func fen(pieces: [ChessPiece], side: Side) -> String {
        var rows: [String] = []
        for rank in (0...9).reversed() {
            var row = "", spaces = 0
            for file in 0...8 {
                if let piece = pieces.first(where: { $0.square == BoardSquare(file: file, rank: rank) }) {
                    if spaces > 0 { row += String(spaces); spaces = 0 }
                    row += piece.side == .red ? piece.kind.fen.uppercased() : piece.kind.fen
                } else { spaces += 1 }
            }
            if spaces > 0 { row += String(spaces) }
            rows.append(row)
        }
        return rows.joined(separator: "/") + " \(side.fen) - - 0 1"
    }
    static func applying(_ move: ChessMove, to pieces: [ChessPiece]) -> [ChessPiece] {
        var next = pieces.filter { $0.square != move.to }
        if let index = next.firstIndex(where: { $0.square == move.from }) { next[index].square = move.to }
        return next
    }
}

struct StudyNode: Identifiable, Codable, Hashable {
    var id = UUID()
    var parentID: UUID?
    var move: ChessMove?
    var children: [UUID] = []
}

struct Study: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var modifiedAt = Date()
    var initialPieces: [ChessPiece]
    var initialSide: Side
    var nodes: [StudyNode]
    var rootID: UUID
    var currentID: UUID
    var bottomSide: Side = .red
    var isDraft = true
    var schemaVersion = 1

    init(name: String, pieces: [ChessPiece], side: Side = .red) {
        self.name = name; initialPieces = pieces; initialSide = side
        let root = StudyNode()
        nodes = [root]; rootID = root.id; currentID = root.id
    }
    var initialFEN: String { ChessPosition.fen(pieces: initialPieces, side: initialSide) }
    var currentNode: StudyNode { node(currentID)! }
    var currentLine: [StudyNode] { line(to: currentID) }
    var currentPieces: [ChessPiece] {
        currentLine.reduce(initialPieces) { pieces, node in node.move.map { ChessPosition.applying($0, to: pieces) } ?? pieces }
    }
    var sideToMove: Side { currentLine.count.isMultiple(of: 2) ? initialSide : initialSide.opponent }
    var branchCount: Int { nodes.filter { $0.children.count > 1 }.count }
    func node(_ id: UUID) -> StudyNode? { nodes.first { $0.id == id } }
    func line(to id: UUID) -> [StudyNode] {
        var line: [StudyNode] = []
        var cursor = node(id)
        while let item = cursor, item.parentID != nil { line.append(item); cursor = item.parentID.flatMap(node) }
        return line.reversed()
    }
    func label(for node: StudyNode) -> String {
        guard let move = node.move, let parent = node.parentID else { return "起点" }
        let before = line(to: parent).reduce(initialPieces) { pieces, item in item.move.map { ChessPosition.applying($0, to: pieces) } ?? pieces }
        return move.notation(in: before)
    }
    mutating func play(_ move: ChessMove) {
        let parentIndex = nodes.firstIndex { $0.id == currentID }!
        if let existing = nodes[parentIndex].children.compactMap(node).first(where: { $0.move == move }) {
            currentID = existing.id
        } else {
            let child = StudyNode(parentID: currentID, move: move)
            nodes[parentIndex].children.append(child.id)
            nodes.append(child); currentID = child.id
        }
        modifiedAt = Date()
    }
    func duplicate() -> Study {
        var copy = self
        copy.id = UUID(); copy.name += " · 副本"; copy.createdAt = Date(); copy.modifiedAt = Date()
        return copy
    }
    func editingSetup(name: String, pieces: [ChessPiece], side: Side, bottom: Side) -> Study {
        var edited = self
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.name = trimmed.isEmpty ? "未命名残局" : trimmed
        edited.bottomSide = bottom
        edited.modifiedAt = Date()
        if initialFEN != ChessPosition.fen(pieces: pieces, side: side) {
            edited.initialPieces = pieces; edited.initialSide = side
            let root = StudyNode()
            edited.nodes = [root]; edited.rootID = root.id; edited.currentID = root.id
        }
        return edited
    }
    static var examples: [Study] {
        [
            Study(name: "单车研究", pieces: ChessPosition.pieces(fen: "3k5/9/4R4/9/9/9/9/9/9/4K4 w - - 0 1")),
            Study(name: "车马练习", pieces: ChessPosition.pieces(fen: "4k4/9/9/9/4p4/9/3N5/9/R8/4K4 w - - 0 1")),
            Study(name: "从开局开始", pieces: ChessPosition.pieces(fen: ChessPosition.initialFEN))
        ].map { var item = $0; item.isDraft = false; return item }
    }
}
