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
    @State private var importingImage = false
    @State private var importNotice: String?
    private let original: Study
    private let onSave: (Study, Bool) throws -> Void

    init(study: Study, onSave: @escaping (Study, Bool) throws -> Void) {
        original = study
        _draft = State(initialValue: study)
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
                    VStack(alignment: .leading, spacing: 7) {
                        Label("残局名称", systemImage: "pencil").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        TextField("残局名称", text: $draft.name).textFieldStyle(.plain)
                            .font(.system(size: 21, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                        if original.nodes.count > 1 {
                            Text("正在编辑初始局面。只改名会保留推演；修改棋子或先行方后，原线路保存为“编辑前”副本。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    Button { importingImage = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(Palette.teal)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("从图片识别残局").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.ink)
                                Text("DeepSeek 识别，导入后可校正").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.teal)
                        }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 1))
                    }.buttonStyle(.plain)
                    if let importNotice {
                        Text(importNotice).font(.system(size: 11)).foregroundStyle(Palette.teal)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    }
                    BoardView(pieces: draft.initialPieces, bottom: draft.bottomSide, selected: selected,
                              onTap: place, onDrag: move)
                    HStack {
                        Text(removing ? "删除模式：点击棋子删除，可连续删除" : selected != nil ? "点击落点移动，或点下方“删除选中棋子”" : "选择棋子，再点棋盘放置")
                            .font(.system(size: 11)).foregroundStyle(removing ? Palette.red : Palette.muted)
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
                        Spacer()
                        Button("初始盘") { replace(ChessPosition.pieces(fen: ChessPosition.initialFEN)) }
                        Button("清空") { replace([]) }
                    }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(Palette.teal).padding(.horizontal, 4)
                }.padding(.horizontal, 20).padding(.bottom, 18).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Button { history(back: true) } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44) }
                        .disabled(undoStack.isEmpty).opacity(undoStack.isEmpty ? 0.35 : 1).accessibilityLabel("撤销摆棋")
                    Button { history(back: false) } label: { Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44) }
                        .disabled(redoStack.isEmpty).opacity(redoStack.isEmpty ? 0.35 : 1).accessibilityLabel("重做摆棋")
                    Spacer(minLength: 0)
                    Button {
                        if let selected { remove(selected) }
                        else { removing.toggle(); Feedback.selection() }
                    } label: {
                        Label(selected != nil ? "删除选中棋子" : removing ? "完成删除" : "删除棋子", systemImage: removing ? "checkmark" : "trash")
                            .font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(height: 44)
                            .foregroundStyle(Palette.red)
                            .background(Palette.red.opacity(removing ? 0.16 : 0.07), in: RoundedRectangle(cornerRadius: 12))
                    }
                }.buttonStyle(.plain).foregroundStyle(Palette.teal)
                ActionButton(title: "开始推演", icon: "play.fill", prominent: true) { save(start: true) }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 16).background(Palette.paper)
        }
        .background(Palette.paper).tint(Palette.teal)
        .sheet(isPresented: $importingImage) {
            ImageImportView { result in
                replace(result.chessPieces)
                draft.initialSide = result.sideToMove ?? .red
                draft.bottomSide = .red
                removing = false
                if draft.name == "新残局", let name = result.name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    draft.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
                }
                importNotice = result.reviewMessage
            }
        }
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
            remove(square)
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
        guard !removing, from != to, draft.initialPieces.contains(where: { $0.square == from }) else { return }
        replace(ChessPosition.applying(ChessMove(from: from, to: to), to: draft.initialPieces))
    }
    private func remove(_ square: BoardSquare) {
        guard draft.initialPieces.contains(where: { $0.square == square }) else { return }
        replace(draft.initialPieces.filter { $0.square != square })
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
        var edited = original.editingSetup(name: draft.name, pieces: draft.initialPieces, side: draft.initialSide, bottom: draft.bottomSide)
        let snapshot = RuleSnapshot(study: edited, hints: false)
        if start, let error = snapshot.error { message = error; return }
        edited.isDraft = snapshot.error != nil
        do { try onSave(edited, start); dismiss() }
        catch { message = "保存失败：\(error.localizedDescription)" }
    }
}
