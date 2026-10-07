import SwiftUI

struct PositionEditorState {
    var pieces: [ChessPiece]
    var selected: BoardSquare?
    var placementSide: Side = .red
    var placementKind: PieceKind? = .rook
    private(set) var undoStack: [[ChessPiece]] = []
    private(set) var redoStack: [[ChessPiece]] = []

    mutating func choose(_ kind: PieceKind, side: Side) {
        placementSide = side; placementKind = kind; selected = nil
    }
    mutating func tap(_ square: BoardSquare) -> String? {
        if pieces.contains(where: { $0.square == square }) {
            selected = selected == square ? nil : square
            placementKind = nil
            return nil
        }
        if let selected { return move(from: selected, to: square) }
        guard let kind = placementKind else { return nil }
        guard pieces.filter({ $0.side == placementSide && $0.kind == kind }).count < kind.limit else {
            return "\(placementSide.title)\(kind.glyph(placementSide))已全部放置。"
        }
        replace(pieces + [ChessPiece(side: placementSide, kind: kind, square: square)], keepPlacement: true)
        if pieces.filter({ $0.side == placementSide && $0.kind == kind }).count == kind.limit { placementKind = nil }
        return nil
    }
    mutating func move(from: BoardSquare, to: BoardSquare) -> String? {
        guard from != to, pieces.contains(where: { $0.square == from }) else { return nil }
        selected = from; placementKind = nil
        guard !pieces.contains(where: { $0.square == to }) else { return "这个位置已有棋子，请选择空落点。" }
        replace(ChessPosition.applying(ChessMove(from: from, to: to), to: pieces))
        return nil
    }
    mutating func deleteSelected() {
        guard let selected else { return }
        replace(pieces.filter { $0.square != selected })
    }
    mutating func replace(_ next: [ChessPiece], keepPlacement: Bool = false) {
        guard next != pieces else { return }
        undoStack.append(pieces); redoStack.removeAll()
        pieces = next; selected = nil
        if !keepPlacement { placementKind = nil }
    }
    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(pieces); pieces = previous; selected = nil; placementKind = nil
    }
    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(pieces); pieces = next; selected = nil; placementKind = nil
    }
}

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Study
    @State private var board: PositionEditorState
    @State private var message: String?
    @State private var saveError: String?
    @State private var importingImage: Bool
    @State private var sourceImage: RecognitionImage?
    @State private var reviewNotes: String?
    @State private var viewingSource = false
    @State private var renaming = false
    @State private var editedName = ""
    private let original: Study
    private let onSave: (Study, Bool) throws -> Void

    init(study: Study, importingImage: Bool = false, onSave: @escaping (Study, Bool) throws -> Void) {
        original = study
        _draft = State(initialValue: study)
        _board = State(initialValue: PositionEditorState(pieces: study.initialPieces))
        _importingImage = State(initialValue: importingImage)
        self.onSave = onSave
    }
    #if DEBUG
    init(previewStudy: Study, selected: BoardSquare? = nil, sourceImage: RecognitionImage? = nil) {
        self.init(study: previewStudy, onSave: { _, _ in })
        _board = State(initialValue: PositionEditorState(pieces: previewStudy.initialPieces, selected: selected, placementKind: selected == nil ? .rook : nil))
        _sourceImage = State(initialValue: sourceImage)
    }
    #endif
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                header
                BoardView(pieces: board.pieces, bottom: draft.bottomSide, selected: board.selected,
                          onTap: tap, onDrag: move)
                    .frame(width: boardWidth(in: geometry.size), height: boardWidth(in: geometry.size) / 0.9)
                    .frame(maxWidth: .infinity)
                VStack(spacing: 4) {
                    tray(side: .red)
                    tray(side: .black)
                }
                tools
                Text(message ?? instruction)
                    .font(.system(size: 12)).foregroundStyle(message == nil ? Palette.muted : Palette.red)
                    .lineLimit(2).frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28, alignment: .leading)
                    .accessibilityIdentifier("editor-status")
                Spacer(minLength: 0)
                ActionButton(title: "开始推演", icon: "play.fill", prominent: true) { save(start: true) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: 490).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Palette.paper).tint(Palette.teal)
        .sheet(isPresented: $importingImage) {
            ImageImportView { result, image in
                withAnimation(.easeInOut(duration: 0.16)) { board.replace(result.chessPieces) }
                draft.initialSide = result.sideToMove ?? .red
                draft.bottomSide = .red
                sourceImage = image.flatMap { try? RecognitionImage(data: $0) }
                reviewNotes = result.notes.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)) }
                if draft.name == "新残局", let name = result.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                }
                message = result.sideToMove == nil ? "请对照原图校正棋子；先行方暂选红先。" : "请对照原图校正棋子与先行方。"
            }
        }
        .sheet(isPresented: $viewingSource) {
            if let sourceImage { ImageReviewView(image: sourceImage, title: "原图", notes: reviewNotes) }
        }
        .alert("残局名称", isPresented: $renaming) {
            TextField("残局名称", text: $editedName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.name = name.isEmpty ? "未命名残局" : name
            }
        }
        .alert("无法保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("知道了") { saveError = nil }
        } message: { Text(saveError ?? "") }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        #else
        .frame(minWidth: 350, idealWidth: 430, minHeight: 530, idealHeight: 820)
        #endif
    }
    private func boardWidth(in size: CGSize) -> CGFloat {
        min(max(1, size.width - 32), 458, max(1, size.height - 320) * 0.9)
    }
    private var instruction: String {
        if let selected = board.selected, let piece = board.pieces.first(where: { $0.square == selected }) {
            return "已选\(piece.side.title)\(piece.kind.glyph(piece.side)) · 点空落点移动"
        }
        if let kind = board.placementKind { return "放置\(board.placementSide.title)\(kind.glyph(board.placementSide)) · 点棋盘落点" }
        return "选择下方棋子放置，或选中棋盘棋子调整"
    }
    private var header: some View {
        HStack(spacing: 4) {
            Button("取消") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            Button {
                editedName = draft.name; renaming = true
            } label: {
                HStack(spacing: 5) {
                    Text(draft.name).font(.system(size: 17, weight: .semibold, design: .serif)).lineLimit(1)
                    Image(systemName: "pencil").font(.system(size: 11))
                }.foregroundStyle(Palette.ink).frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityLabel("修改残局名称")
            if sourceImage != nil {
                Button { viewingSource = true } label: {
                    Image(systemName: "photo.on.rectangle").frame(width: 44, height: 44)
                }.accessibilityLabel("查看原图")
            } else {
                Button { importingImage = true } label: {
                    Image(systemName: "photo.badge.plus").frame(width: 44, height: 44)
                }.accessibilityLabel("从图片导入")
            }
            Button("保存") { save(start: false) }.fontWeight(.semibold).frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.teal).frame(height: 44)
    }
    private func tray(side: Side) -> some View {
        HStack(spacing: 0) {
            ForEach(PieceKind.allCases) { kind in
                let count = board.pieces.filter { $0.side == side && $0.kind == kind }.count
                let remaining = max(0, kind.limit - count)
                Button {
                    board.choose(kind, side: side); message = nil; Feedback.selection()
                } label: {
                    PieceFace(piece: ChessPiece(side: side, kind: kind, square: BoardSquare(file: 0, rank: 0)),
                              diameter: 32, selected: remaining > 0 && board.placementSide == side && board.placementKind == kind)
                        .overlay(alignment: .bottomTrailing) {
                            Text("\(remaining)").font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Palette.muted).frame(width: 14, height: 14)
                                .background(Palette.card, in: Circle()).offset(x: 5, y: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(remaining == 0).opacity(remaining == 0 ? 0.42 : 1)
                .accessibilityLabel("\(side.title)\(kind.glyph(side))，剩余 \(remaining) 枚")
            }
        }.frame(height: 44).accessibilityIdentifier(side == .red ? "red-piece-tray" : "black-piece-tray")
    }
    private var tools: some View {
        HStack(spacing: 4) {
            Menu {
                Picker("先行方", selection: $draft.initialSide) {
                    Text("红先").tag(Side.red); Text("黑先").tag(Side.black)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(draft.initialSide == .red ? "红先" : "黑先")
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }.frame(width: 68, height: 44)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("先行方")
            Button { board.undo(); message = nil } label: {
                Image(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
            }.disabled(board.undoStack.isEmpty).accessibilityLabel("撤销摆棋")
            Button { board.redo(); message = nil } label: {
                Image(systemName: "arrow.uturn.forward").frame(width: 44, height: 44)
            }.disabled(board.redoStack.isEmpty).accessibilityLabel("重做摆棋")
            Spacer(minLength: 0)
            if board.selected != nil {
                Button(role: .destructive) {
                    withAnimation(.easeInOut(duration: 0.16)) { board.deleteSelected() }
                    message = nil; Feedback.move(capture: true)
                } label: {
                    Label("删除", systemImage: "trash").font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 64, minHeight: 44)
                }.foregroundStyle(Palette.red).accessibilityLabel("删除选中棋子")
            }
            Menu {
                Button(draft.bottomSide == .red ? "黑方在下" : "红方在下", systemImage: "arrow.up.arrow.down") {
                    draft.bottomSide = draft.bottomSide.opponent
                }
                if sourceImage != nil {
                    Button("查看原图", systemImage: "photo") { viewingSource = true }
                    Button("从图片重新导入", systemImage: "photo.badge.plus") { importingImage = true }
                }
                Divider()
                Button("初始盘", systemImage: "square.grid.3x3") { board.replace(ChessPosition.pieces(fen: ChessPosition.initialFEN)); message = nil }
                Button("清空棋盘", systemImage: "trash", role: .destructive) { board.replace([]); message = nil }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).accessibilityLabel("摆棋工具")
        }.buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(Palette.teal).frame(height: 44)
    }
    private func tap(_ square: BoardSquare) {
        withAnimation(.easeInOut(duration: 0.16)) { message = board.tap(square) }
        if message != nil { Feedback.invalid() } else { Feedback.selection() }
    }
    private func move(_ from: BoardSquare, _ to: BoardSquare) {
        withAnimation(.easeInOut(duration: 0.16)) { message = board.move(from: from, to: to) }
        if message != nil { Feedback.invalid() } else { Feedback.move(capture: false) }
    }
    private func save(start: Bool) {
        let edited = original.editingSetup(name: draft.name, pieces: board.pieces, side: draft.initialSide, bottom: draft.bottomSide)
        var result = edited
        let snapshot = RuleSnapshot(study: edited, hints: false)
        if start, let error = snapshot.error { message = error; return }
        result.isDraft = snapshot.error != nil
        do { try onSave(result, start); dismiss() }
        catch { saveError = error.localizedDescription }
    }
}
