import SwiftUI

struct StudyView: View {
    @StateObject private var session: StudySession
    @Environment(\.scenePhase) private var scenePhase
    @State private var controllerSheet = false
    @State private var editor: Study?
    @State private var renaming = false
    @State private var name = ""
    @AppStorage("hapticsEnabled") private var haptics = true

    init(study: Study, persist: @escaping (Study) throws -> Void) {
        _session = StateObject(wrappedValue: StudySession(study: study, persist: persist))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                BoardView(pieces: session.pieces, bottom: session.study.bottomSide, selected: session.selected,
                          destinations: session.destinations, lastMove: session.showLastMove ? session.lastMove : nil,
                          recommendation: session.suggestion?.move,
                          captures: session.showLights ? session.rules.captures : [],
                          checkedSide: session.rules.inCheck ? session.side : nil,
                          onTap: session.tap, onDrag: session.drag)
                HStack(spacing: 12) {
                    lightLegend("可安全吃", color: Palette.green)
                    lightLegend("有被吃风险", color: Palette.red)
                    Spacer(minLength: 0)
                    Text("\(session.study.bottomSide.title)视角").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }.opacity(session.showLights ? 1 : 0)
                linePanel
                if let suggestion = session.suggestion, let move = suggestion.move { suggestionPanel(suggestion, move: move) }
                if session.aiPaused && session.rules.error == nil {
                    Button { session.resumeAI() } label: {
                        HStack {
                            Image(systemName: "pause.circle"); Text("托管已暂停"); Spacer(); Text("继续托管"); Image(systemName: "play.fill")
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                            .padding(13).background(Palette.teal.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 18)
                .frame(maxWidth: 510).frame(maxWidth: .infinity)
        }
        .background(Palette.paper).inlineNavigation()
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
        .sheet(isPresented: $controllerSheet) { controllerPanel }
        .sheet(item: $editor) { study in
            EditorView(study: study) { edited, _ in try session.applyEdit(edited) }
        }
        .alert("修改残局名称", isPresented: $renaming) {
            TextField("残局名称", text: $name)
            Button("取消", role: .cancel) {}
            Button("保存") {
                let study = session.study
                do {
                    try session.applyEdit(study.editingSetup(name: name, pieces: study.initialPieces, side: study.initialSide, bottom: study.bottomSide))
                } catch { session.errorMessage = "保存失败：\(error.localizedDescription)" }
            }
        }
        .alert("提示", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("知道了") { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .onDisappear { session.leave() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.leave() } }
    }
    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.study.name).font(.system(size: 24, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                    Text(session.controllerText).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Menu {
                    Button("修改名称", systemImage: "pencil") { session.stop(); name = session.study.name; renaming = true }
                    Button("编辑棋子与名称", systemImage: "square.and.pencil") { session.stop(); editor = session.study }
                    Divider()
                    Button("返回研究起点", systemImage: "backward.end") { session.jump(to: session.study.rootID) }
                    Button(session.study.bottomSide == .red ? "黑方在下" : "红方在下", systemImage: "arrow.up.arrow.down") { session.flip() }
                    Toggle("吃子红绿灯", isOn: Binding(get: { session.showLights }, set: { _ in session.toggleLights() }))
                    Toggle("显示上一手", isOn: $session.showLastMove)
                    Toggle("震动反馈", isOn: $haptics)
                    Picker("思考时间", selection: $session.thinkMilliseconds) {
                        Text("快速 · 0.3 秒").tag(300)
                        Text("标准 · 1 秒").tag(1000)
                        Text("深入 · 3 秒").tag(3000)
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.ink)
                        .frame(width: 40, height: 36).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("研究设置")
            }
            HStack(spacing: 8) {
                Circle().fill(session.side == .red ? Palette.red : Palette.ink).frame(width: 7, height: 7)
                Text(session.status).font(.system(size: 12, weight: .medium)).foregroundStyle(session.rules.inCheck ? Palette.red : Palette.ink)
                if session.isThinking { ProgressView().controlSize(.mini) }
                Spacer()
                Text(session.saved ? "已保存" : "未保存").font(.system(size: 10)).foregroundStyle(session.saved ? Palette.muted : Palette.red)
            }
        }
    }
    private func lightLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 5, height: 5); Text(title) }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
    private var linePanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("推演线路").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if !branchChoices.isEmpty {
                    Menu {
                        ForEach(branchChoices) { node in Button(session.study.label(for: node)) { session.jump(to: node.id) } }
                    } label: {
                        Label("\(branchChoices.count) 个变化", systemImage: "arrow.triangle.branch")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.teal)
                    }.menuStyle(.borderlessButton).fixedSize()
                } else {
                    Text("第 \(session.study.currentLine.count) 手").font(.system(size: 10)).foregroundStyle(Palette.muted)
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        lineButton(id: session.study.rootID, title: "起点", detail: nil)
                        ForEach(Array(session.study.currentLine.enumerated()), id: \.element.id) { index, node in
                            lineButton(id: node.id, title: session.study.label(for: node), detail: String(index + 1))
                        }
                    }
                }
                .onChange(of: session.study.currentID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .trailing) } }
            }
        }.padding(14).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line, lineWidth: 1))
    }
    private func lineButton(id: UUID, title: String, detail: String?) -> some View {
        let current = session.study.currentID == id
        return Button { session.jump(to: id) } label: {
            HStack(spacing: 4) {
                if let detail { Text(detail).font(.system(size: 9)).opacity(0.55) }
                Text(title).font(.system(size: 12, weight: current ? .semibold : .regular))
                if (session.study.node(id)?.children.count ?? 0) > 1 { Image(systemName: "arrow.triangle.branch").font(.system(size: 9)) }
            }
            .foregroundStyle(current ? Color.white : Palette.ink)
            .padding(.horizontal, 10).padding(.vertical, 9)
            .background(current ? Palette.teal : Palette.paper, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).id(id)
    }
    private var branchChoices: [StudyNode] {
        let current = session.study.currentNode
        if current.children.count > 1 { return current.children.compactMap(session.study.node) }
        if let parent = current.parentID.flatMap(session.study.node), parent.children.count > 1 { return parent.children.compactMap(session.study.node) }
        return []
    }
    private func suggestionPanel(_ result: AIResult, move: ChessMove) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("下一步建议", systemImage: "sparkles").font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.teal)
                    Text(move.notation(in: session.pieces)).font(.system(size: 23, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                }
                Spacer()
                Button { session.adopt() } label: {
                    Label("采用此步", systemImage: "checkmark").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white).padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Palette.teal, in: RoundedRectangle(cornerRadius: 11))
                }.buttonStyle(.plain)
            }
            if result.pv.count > 1 {
                Text(previewLine(result.pv)).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            }
        }.padding(16).background(Palette.teal.opacity(0.065), in: RoundedRectangle(cornerRadius: 16))
    }
    private func previewLine(_ moves: [ChessMove]) -> String {
        var pieces = session.pieces
        return moves.prefix(4).map { move in
            let text = move.notation(in: pieces); pieces = ChessPosition.applying(move, to: pieces); return text
        }.joined(separator: "  →  ")
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { session.back() } label: { Image(systemName: "chevron.left").frame(width: 43, height: 45) }
                .disabled(session.study.currentNode.parentID == nil).opacity(session.study.currentNode.parentID == nil ? 0.35 : 1).accessibilityLabel("上一手")
            Button { session.forward() } label: { Image(systemName: "chevron.right").frame(width: 43, height: 45) }
                .disabled(session.study.currentNode.children.isEmpty).opacity(session.study.currentNode.children.isEmpty ? 0.35 : 1).accessibilityLabel("下一手")
            ActionButton(title: session.isThinking ? "停止" : "AI 建议", icon: session.isThinking ? "stop.fill" : "sparkles", prominent: true,
                         disabled: session.rules.finished || session.rules.error != nil) {
                if session.isThinking { session.stop() } else { session.recommend() }
            }
            Button { controllerSheet = true } label: {
                Label("托管", systemImage: "person.crop.circle.badge.checkmark").font(.system(size: 13, weight: .medium))
                    .frame(width: 78, height: 45).background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
            }
        }.buttonStyle(.plain).foregroundStyle(Palette.teal)
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 14)
            .frame(maxWidth: 510).frame(maxWidth: .infinity)
            .background(Palette.paper.opacity(0.97))
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
    private var controllerPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("选择操作方式").font(.system(size: 22, weight: .semibold, design: .serif)); Spacer(); Button("完成") { controllerSheet = false } }
            Text("回退或切换分支时，托管会暂停。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            controllerButton("双方手动", detail: "自由研究，轮流操作红黑双方", ai: nil, icon: "hand.draw")
            controllerButton("我执红 · AI 执黑", detail: "你走红棋，皮卡鱼走黑棋", ai: .black, icon: "person.fill")
            controllerButton("我执黑 · AI 执红", detail: "你走黑棋，皮卡鱼走红棋", ai: .red, icon: "person.fill")
        }.foregroundStyle(Palette.ink).padding(24).frame(minWidth: 330, idealWidth: 410)
            .background(Palette.paper).tint(Palette.teal)
            #if os(iOS)
            .presentationDetents([.height(355)])
            #endif
    }
    private func controllerButton(_ title: String, detail: String, ai: Side?, icon: String) -> some View {
        Button { session.setAI(ai); controllerSheet = false } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 19)).foregroundStyle(Palette.teal).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                if session.aiSide == ai { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.teal) }
            }.padding(15).background(Palette.card, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
