import SwiftUI

struct StudyView: View {
    @StateObject private var session: StudySession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var editor: Study?
    @State private var renaming = false
    @State private var name = ""
    @State private var showingVariation = false
    @State private var choosingBranch = false
    @State private var choosingController = false
    @AppStorage("hapticsEnabled") private var haptics = true

    init(study: Study, persist: @escaping (Study) throws -> Void) {
        _session = StateObject(wrappedValue: StudySession(study: study, persist: persist))
    }
    #if DEBUG
    init(previewSession: StudySession) { _session = StateObject(wrappedValue: previewSession) }
    #endif
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                header
                status
                BoardView(pieces: session.pieces, bottom: session.study.bottomSide, selected: session.selected,
                          destinations: session.destinations, lastMove: session.showLastMove ? session.lastMove : nil,
                          recommendation: session.suggestion?.move,
                          captures: session.showLights ? session.rules.captures : [],
                          checkedSide: session.rules.inCheck ? session.side : nil,
                          onTap: session.tap, onDrag: session.drag)
                    .frame(width: boardWidth(geometry.size), height: boardWidth(geometry.size) / 0.9)
                if session.showLights {
                    HStack(spacing: 12) {
                        lightLegend("可安全吃", color: Palette.green)
                        lightLegend("有被吃风险", color: Palette.red)
                        Spacer(minLength: 0)
                        Text("\(session.study.bottomSide.title)视角").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }.frame(height: 16)
                }
                linePanel.frame(height: 52)
                analysis.frame(height: 60)
                Spacer(minLength: 0)
                controls
            }.padding(.horizontal, 16).padding(.vertical, 8)
                .frame(maxWidth: 510).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Palette.paper).compactNavigation()
        .sheet(item: $editor) { study in
            EditorView(study: study) { edited, _ in try session.applyEdit(edited) }
        }
        .sheet(isPresented: $showingVariation) { variation }
        .confirmationDialog("选择下一手", isPresented: $choosingBranch, titleVisibility: .visible) {
            ForEach(session.forwardChoices) { node in Button(session.study.label(for: node)) { session.jump(to: node.id) } }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("操作方式", isPresented: $choosingController, titleVisibility: .visible) {
            Button("双方手动") { session.setAI(nil) }
            Button("我执红 · AI 执黑") { session.setAI(.black) }
            Button("我执黑 · AI 执红") { session.setAI(.red) }
            if session.aiPaused { Button("继续托管") { session.resumeAI() } }
            Button("取消", role: .cancel) {}
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
    private func boardWidth(_ size: CGSize) -> CGFloat {
        min(max(1, size.width - 32), 478, max(1, size.height - (session.showLights ? 320 : 296)) * 0.9)
    }
    private var header: some View {
        HStack(spacing: 4) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }.accessibilityLabel("返回残局库")
            Text(session.study.name).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                .frame(maxWidth: .infinity)
            Menu {
                Button("修改名称", systemImage: "pencil") { session.stop(); name = session.study.name; renaming = true }
                Button("编辑棋子与名称", systemImage: "square.and.pencil") { session.stop(); editor = session.study }
                Divider()
                Button(session.study.bottomSide == .red ? "黑方在下" : "红方在下", systemImage: "arrow.up.arrow.down") { session.flip() }
                Toggle("吃子红绿灯", isOn: Binding(get: { session.showLights }, set: { _ in session.toggleLights() }))
                Toggle("显示上一手", isOn: $session.showLastMove)
                Toggle("震动反馈", isOn: $haptics)
                Picker("思考时间", selection: $session.thinkMilliseconds) {
                    Text("快速 · 0.3 秒").tag(300)
                    Text("标准 · 1 秒").tag(1000)
                    Text("深入 · 3 秒").tag(3000)
                }
            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("研究设置")
        }.buttonStyle(.plain).foregroundStyle(Palette.ink).frame(height: 44)
    }
    private var status: some View {
        HStack(spacing: 6) {
            Circle().fill(session.side == .red ? Palette.red : Palette.ink).frame(width: 6, height: 6)
            Text(session.status).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(session.rules.inCheck ? Palette.red : Palette.ink)
            if session.isThinking { ProgressView().controlSize(.mini) }
            Spacer(minLength: 4)
            Text(session.saved ? "第 \(session.study.currentLine.count) 手" : "未保存")
                .font(.system(size: 11)).foregroundStyle(session.saved ? Palette.muted : Palette.red)
        }.frame(height: 24)
    }
    private func lightLegend(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(color).frame(width: 5, height: 5); Text(title) }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
    }
    private var linePanel: some View {
        HStack(spacing: 4) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        lineButton(id: session.study.rootID, title: "起点", detail: nil)
                        ForEach(Array(session.study.currentLine.enumerated()), id: \.element.id) { index, node in
                            lineButton(id: node.id, title: session.study.label(for: node), detail: String(index + 1))
                        }
                    }
                }
                .onAppear { proxy.scrollTo(session.study.currentID, anchor: .trailing) }
                .onChange(of: session.study.currentID) { _, id in withAnimation { proxy.scrollTo(id, anchor: .trailing) } }
            }
            if !branchChoices.isEmpty {
                Menu {
                    ForEach(branchChoices) { node in Button(session.study.label(for: node)) { session.jump(to: node.id) } }
                } label: {
                    Image(systemName: "arrow.triangle.branch").frame(width: 44, height: 44)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .foregroundStyle(Palette.teal).accessibilityLabel("选择推演分支")
            }
        }.padding(.horizontal, 8).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
    private func lineButton(id: UUID, title: String, detail: String?) -> some View {
        let current = session.study.currentID == id
        return Button { session.jump(to: id) } label: {
            HStack(spacing: 4) {
                if let detail { Text(detail).font(.system(size: 10)).opacity(0.75) }
                Text(title).font(.system(size: 12, weight: current ? .semibold : .regular))
                if (session.study.node(id)?.children.count ?? 0) > 1 { Image(systemName: "arrow.triangle.branch").font(.system(size: 9)) }
            }.foregroundStyle(current ? Color.white : Palette.ink)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(current ? Palette.teal : Palette.paper, in: RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).id(id)
    }
    private var branchChoices: [StudyNode] {
        if session.forwardChoices.count > 1 { return session.forwardChoices }
        if let parent = session.study.currentNode.parentID.flatMap(session.study.node), parent.children.count > 1 {
            return parent.children.compactMap(session.study.node)
        }
        return []
    }
    @ViewBuilder private var analysis: some View {
        if let suggestion = session.suggestion, let move = suggestion.move {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 建议").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Text(move.notation(in: session.pieces)).font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.teal)
                }
                Spacer()
                if suggestion.pv.count > 1 {
                    Button("查看变化") { showingVariation = true }.font(.system(size: 12, weight: .medium))
                        .frame(minHeight: 44).foregroundStyle(Palette.teal)
                }
            }.padding(.horizontal, 12).frame(maxHeight: .infinity)
                .background(Palette.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        } else if session.aiPaused && session.rules.error == nil {
            HStack {
                Label("\(session.modeTitle) · 已暂停", systemImage: "pause.circle").font(.system(size: 12))
                Spacer()
                Button("继续") { session.resumeAI() }.font(.system(size: 12, weight: .semibold)).frame(minHeight: 44)
            }.foregroundStyle(Palette.teal).padding(.horizontal, 12).frame(maxHeight: .infinity)
                .background(Palette.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        } else {
            Color.clear
        }
    }
    private var controls: some View {
        HStack(spacing: 6) {
            Button { session.jump(to: session.study.rootID) } label: {
                ToolbarTile(title: "起点", icon: "backward.end", enabled: session.study.currentID != session.study.rootID)
            }.disabled(session.study.currentID == session.study.rootID).accessibilityLabel("返回研究起点")
            Button { session.back() } label: {
                ToolbarTile(title: "回退", icon: "chevron.left", enabled: session.study.currentNode.parentID != nil)
            }.disabled(session.study.currentNode.parentID == nil)
            if session.preferredNext == nil && session.forwardChoices.count > 1 {
                Button { choosingBranch = true } label: { ToolbarTile(title: "选分支", icon: "arrow.triangle.branch") }
            } else {
                Button { session.forward() } label: {
                    ToolbarTile(title: "前进", icon: "chevron.right", enabled: session.preferredNext != nil)
                }.disabled(session.preferredNext == nil)
            }
            Button {
                if session.isThinking { session.stop() }
                else if session.suggestion != nil { session.adopt() }
                else { session.recommend() }
            } label: {
                ToolbarTile(title: session.isThinking ? "停止" : session.suggestion != nil ? "采用" : "AI 建议",
                            icon: session.isThinking ? "stop.fill" : session.suggestion != nil ? "checkmark" : "sparkles",
                            prominent: true, enabled: !session.rules.finished && session.rules.error == nil)
            }.disabled(session.rules.finished || session.rules.error != nil)
            Button { choosingController = true } label: {
                ToolbarTile(title: session.modeTitle, icon: session.aiSide == nil ? "hand.draw" : "person.crop.circle")
            }.accessibilityLabel("操作方式：\(session.controllerText)")
        }.buttonStyle(.plain).frame(height: 52)
    }
    private var variation: some View {
        VStack(spacing: 12) {
            HStack {
                Text("AI 参考变化").font(.system(size: 17, weight: .semibold)); Spacer()
                Button("完成") { showingVariation = false }.frame(minHeight: 44)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(variationLabels.enumerated()), id: \.offset) { index, label in
                        HStack { Text(String(index + 1)).foregroundStyle(Palette.muted).frame(width: 30); Text(label); Spacer() }
                            .font(.system(size: 15)).padding(.vertical, 12)
                    }
                }
            }
        }.padding(20).foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.teal)
            .frame(minWidth: 320, idealWidth: 430, minHeight: 300)
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
    }
    private var variationLabels: [String] {
        var pieces = session.pieces
        return (session.suggestion?.pv ?? []).map { move in
            let label = move.notation(in: pieces)
            pieces = ChessPosition.applying(move, to: pieces)
            return label
        }
    }
}
