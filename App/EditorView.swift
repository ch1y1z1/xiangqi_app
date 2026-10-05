import SwiftUI

struct EditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Study
    @State private var traySide: Side = .red
    @State private var kind: PieceKind = .rook
    @State private var selected: BoardSquare?
    @State private var removing = false
    @State private var undoStack: [[ChessPiece]] = []
    @State private var redoStack: [[ChessPiece]] = []
    @State private var message: String?
    private let onSave: (Study, Bool) -> Bool

    init(study: Study, onSave: @escaping (Study, Bool) -> Bool) {
        var initial = study
        if study.nodes.count > 1 {
            initial = Study(name: study.name + " · 新起点", pieces: study.initialPieces, side: study.initialSide)
            initial.bottomSide = study.bottomSide
        }
        _draft = State(initialValue: initial)
        self.onSave = onSave
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }.foregroundStyle(Palette.muted)
                Spacer()
                Text("摆一盘残局").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Button("保存") { save(start: false) }.fontWeight(.semibold).foregroundStyle(Palette.teal)
            }.buttonStyle(.plain).padding(20)
            ScrollView {
                VStack(spacing: 16) {
                    TextField("残局名称", text: $draft.name).textFieldStyle(.plain)
                        .font(.system(size: 21, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                        .padding(.horizontal, 4)
                    BoardView(pieces: draft.initialPieces, bottom: draft.bottomSide, selected: selected,
                              onTap: place, onDrag: move)
                    HStack {
                        Text(removing ? "点击棋子移除" : selected != nil ? "点击落点，移动选中的棋子" : "选择棋子，再点棋盘放置")
                            .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        Spacer()
                        Button { draft.bottomSide = draft.bottomSide.opponent } label: { Image(systemName: "arrow.up.arrow.down") }
                            .buttonStyle(.plain).foregroundStyle(Palette.teal).accessibilityLabel("翻转棋盘")
                    }
                    tray
                    HStack(spacing: 12) {
                        Text("先行方").font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink)
                        Picker("先行方", selection: $draft.initialSide) {
                            Text("红先").tag(Side.red); Text("黑先").tag(Side.black)
                        }.pickerStyle(.segmented).labelsHidden()
                    }.padding(.horizontal, 4)
                    HStack(spacing: 16) {
                        Button { history(back: true) } label: { Image(systemName: "arrow.uturn.backward") }
                            .disabled(undoStack.isEmpty).accessibilityLabel("撤销摆棋")
                        Button { history(back: false) } label: { Image(systemName: "arrow.uturn.forward") }
                            .disabled(redoStack.isEmpty).accessibilityLabel("重做摆棋")
                        Spacer()
                        Button("初始盘") { replace(ChessPosition.pieces(fen: ChessPosition.initialFEN)) }
                        Button("清空") { replace([]) }
                        Button { removing.toggle(); selected = nil } label: {
                            Label("移除", systemImage: "eraser").foregroundStyle(removing ? Palette.red : Palette.teal)
                        }
                    }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Palette.teal).padding(.horizontal, 4)
                }.padding(.horizontal, 20).padding(.bottom, 18).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
            ActionButton(title: "开始推演", icon: "play.fill", prominent: true) { save(start: true) }
                .padding(20).background(Palette.paper)
        }
        .background(Palette.paper).tint(Palette.teal)
        #if os(macOS)
        .frame(minWidth: 350, idealWidth: 430, maxWidth: .infinity, minHeight: 620, idealHeight: 880)
        #endif
        .alert("请调整局面", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("继续摆棋") { message = nil }
        } message: { Text(message ?? "") }
    }
    private var tray: some View {
        VStack(spacing: 12) {
            HStack {
                Picker("棋子阵营", selection: $traySide) {
                    Text("红方棋子").tag(Side.red); Text("黑方棋子").tag(Side.black)
                }.pickerStyle(.segmented).labelsHidden().onChange(of: traySide) { _, _ in selected = nil; removing = false }
            }
            HStack(spacing: 0) {
                ForEach(PieceKind.allCases) { item in
                    let count = draft.initialPieces.filter { $0.side == traySide && $0.kind == item }.count
                    let remaining = max(0, item.limit - count)
                    Button { kind = item; selected = nil; removing = false; Feedback.selection() } label: {
                        VStack(spacing: 5) {
                            PieceFace(piece: ChessPiece(side: traySide, kind: item, square: BoardSquare(file: 0, rank: 0)),
                                      diameter: 34, selected: kind == item && selected == nil && !removing)
                            Text("\(remaining)").font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity).opacity(remaining == 0 ? 0.45 : 1)
                    }.buttonStyle(.plain).accessibilityLabel("\(traySide.title)\(item.glyph(traySide))，剩余 \(remaining) 枚")
                }
            }
        }.padding(13).background(Palette.card, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(Palette.line, lineWidth: 1))
    }
    private func place(_ square: BoardSquare) {
        if removing {
            if draft.initialPieces.contains(where: { $0.square == square }) { replace(draft.initialPieces.filter { $0.square != square }) }
            return
        }
        if let origin = selected {
            if origin == square { selected = nil } else { move(origin, square) }
            return
        }
        if draft.initialPieces.contains(where: { $0.square == square }) { selected = square; Feedback.selection(); return }
        let count = draft.initialPieces.filter { $0.side == traySide && $0.kind == kind }.count
        guard count < kind.limit else { Feedback.invalid(); message = "\(traySide.title)\(kind.glyph(traySide))已经全部放到棋盘上了。"; return }
        replace(draft.initialPieces + [ChessPiece(side: traySide, kind: kind, square: square)])
    }
    private func move(_ from: BoardSquare, _ to: BoardSquare) {
        guard from != to, draft.initialPieces.contains(where: { $0.square == from }) else { return }
        replace(ChessPosition.applying(ChessMove(from: from, to: to), to: draft.initialPieces))
    }
    private func replace(_ pieces: [ChessPiece]) {
        undoStack.append(draft.initialPieces); redoStack.removeAll()
        withAnimation(.easeInOut(duration: 0.16)) { draft.initialPieces = pieces }
        selected = nil; Feedback.move(capture: false)
    }
    private func history(back: Bool) {
        if back, let pieces = undoStack.popLast() { redoStack.append(draft.initialPieces); draft.initialPieces = pieces }
        else if !back, let pieces = redoStack.popLast() { undoStack.append(draft.initialPieces); draft.initialPieces = pieces }
        selected = nil
    }
    private func save(start: Bool) {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.name.isEmpty { draft.name = "未命名残局" }
        let snapshot = RuleSnapshot(study: draft, hints: false)
        if start, let error = snapshot.error { message = error; return }
        draft.isDraft = snapshot.error != nil
        draft.modifiedAt = Date()
        if onSave(draft, start) { dismiss() }
    }
}
