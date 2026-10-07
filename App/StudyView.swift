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
    @State private var showingEvaluation = false
    private var startsAnalysis = true
    @AppStorage("hapticsEnabled") private var haptics = true

    init(study: Study, persist: @escaping (Study) throws -> Void) {
        _session = StateObject(wrappedValue: StudySession(study: study, persist: persist))
    }
    #if DEBUG
    init(previewSession: StudySession) { _session = StateObject(wrappedValue: previewSession); startsAnalysis = false }
    init(previewFork: Study) {
        _session = StateObject(wrappedValue: StudySession(study: previewFork, persist: { _ in }))
        _choosingBranch = State(initialValue: true)
    }
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
        .sheet(isPresented: $showingEvaluation) { EvaluationDetailView(session: session) }
        .sheet(isPresented: $choosingBranch, onDismiss: session.closeBranches) {
            if let parent = session.forkParentID {
                BranchComparisonView(session: session, parentID: parent) { node in
                    choosingBranch = false; session.jump(to: node.id)
                }
            }
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
        .onAppear {
            if startsAnalysis { session.activate(); if choosingBranch { session.openBranches() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { session.leave() }
            else if startsAnalysis { session.activate() }
        }
    }
    private func boardWidth(_ size: CGSize) -> CGFloat {
        min(max(1, size.width - 32), 478, max(1, size.height - (session.showLights ? 328 : 304)) * 0.9)
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
                Toggle("显示当前局面评分", isOn: Binding(get: { session.showEvaluation }, set: session.setShowEvaluation))
                Toggle("显示分支评分", isOn: Binding(get: { session.showBranchScores }, set: session.setShowBranchScores))
                Toggle("震动反馈", isOn: $haptics)
                Picker("思考时间", selection: Binding(get: { session.thinkMilliseconds }, set: session.setThinkMilliseconds)) {
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
            if session.showEvaluation {
                Button { showingEvaluation = true } label: {
                    Text(session.evaluationText(for: session.study.currentID)).monospacedDigit()
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                        .lineLimit(1).frame(minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("当前局面评分：" + session.evaluationText(for: session.study.currentID))
            }
            if !session.saved { Text("未保存").font(.system(size: 10)).foregroundStyle(Palette.red) }
        }.frame(height: 32)
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
            if session.forkParentID != nil {
                Button { openBranches() } label: {
                    Image(systemName: "arrow.triangle.branch").frame(width: 44, height: 44)
                }.buttonStyle(.plain).foregroundStyle(Palette.teal).accessibilityLabel("比较并选择推演分支")
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
    private func openBranches() {
        session.openBranches(); choosingBranch = true
    }
    @ViewBuilder private var analysis: some View {
        if let suggestion = session.suggestion, let move = suggestion.move {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("AI 建议").foregroundStyle(Palette.muted)
                        Button { showingEvaluation = true } label: {
                            Text(session.suggestionEvaluation?.text ?? "暂无评分").monospacedDigit().foregroundStyle(Palette.teal)
                        }.buttonStyle(.plain)
                    }.font(.system(size: 11))
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
                Button { openBranches() } label: { ToolbarTile(title: "选分支", icon: "arrow.triangle.branch") }
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

struct BranchComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: StudySession
    var parentID: UUID
    var onChoose: (StudyNode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("比较分支").font(.system(size: 17, weight: .semibold)); Spacer()
                Button("完成") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }
            Toggle("显示分支评分", isOn: Binding(get: { session.showBranchScores }, set: session.setShowBranchScores))
                .font(.system(size: 13))
            if session.showBranchScores {
                Text("红正黑负 · 比较各下一手后的局面，后续按最佳应对")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(session.branches(at: parentID)) { node in
                        Button { onChoose(node) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 8) {
                                        Text(session.study.label(for: node)).font(.system(size: 16, weight: .medium))
                                        if session.study.currentID == node.id { Text("当前").font(.system(size: 11)).foregroundStyle(Palette.teal) }
                                    }
                                    if session.showBranchScores {
                                        Text(branchDetail(node.id))
                                            .font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(2)
                                    }
                                }
                                Spacer(minLength: 4)
                                if session.showBranchScores {
                                    Text(session.evaluationText(for: node.id)).font(.system(size: 14, weight: .semibold))
                                        .monospacedDigit().foregroundStyle(Palette.teal)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.muted)
                            }.frame(minHeight: 56).padding(12)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
            if session.showBranchScores {
                HStack {
                    Text("分数用于比较优势，M 为将杀／判胜线的回合距离。")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer(minLength: 4)
                    Button("重新比较") { session.reanalyze(branches: parentID) }
                        .font(.system(size: 12)).frame(minHeight: 44).disabled(session.isThinking)
                }
            }
        }.padding(16).foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.teal)
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #else
            .frame(minWidth: 350, idealWidth: 430, minHeight: 350, idealHeight: 600)
            #endif
    }
    private func branchDetail(_ id: UUID) -> String {
        if let comparison = session.comparison(for: id, at: parentID), let value = session.evaluation(for: id) {
            return comparison + " · 深度 \(value.depth)"
        }
        return session.evaluation(for: id)?.detail ?? session.evaluationErrors[id] ?? "等待分析"
    }
}

struct EvaluationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var session: StudySession
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("局面评估").font(.system(size: 17, weight: .semibold)); Spacer()
                Button("完成") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(session.evaluationText(for: session.study.currentID)).font(.system(size: 28, weight: .semibold)).monospacedDigit()
                    if let value = session.evaluation(for: session.study.currentID) {
                        Text(value.detail).font(.system(size: 13)).foregroundStyle(Palette.muted)
                    }
                    if let error = session.evaluationErrors[session.study.currentID] {
                        Text(error).font(.system(size: 13)).foregroundStyle(Palette.red)
                    }
                    Text("普通分数采用红方视角：正分偏红，负分偏黑。M 表示将杀或规则判胜的回合距离，≈M 表示尚未精确定界的胜线；≥／≤ 表示普通评分的下界／上界。已终局直接显示胜方或和棋。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text("评分基于双方后续最佳应对，不代表胜率。比较候选着的差距，比当前评分与 AI 推荐评分的差值更有意义。")
                        .font(.system(size: 13)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if session.showEvaluation {
                ActionButton(title: "重新分析", icon: "arrow.clockwise", disabled: session.isThinking) { session.reanalyze() }
            }
        }.padding(20).foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.teal)
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #else
            .frame(minWidth: 350, idealWidth: 430, minHeight: 350)
            #endif
    }
}
