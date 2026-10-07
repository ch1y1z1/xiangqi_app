import SwiftUI

@MainActor
final class StudySession: ObservableObject {
    @Published var study: Study
    @Published var rules: RuleSnapshot
    @Published var selected: BoardSquare?
    @Published var suggestion: AIResult?
    @Published var isThinking = false
    @Published var aiSide: Side?
    @Published var aiPaused = false
    @Published var errorMessage: String?
    @Published var saved = true
    @Published var showLights = true
    @Published var showLastMove = true
    @Published private(set) var thinkMilliseconds = 1000
    @Published private(set) var showEvaluation: Bool
    @Published private(set) var showBranchScores: Bool
    @Published private(set) var evaluations: [UUID: PositionEvaluation] = [:]
    @Published private(set) var evaluationErrors: [UUID: String] = [:]
    @Published private(set) var analyzingID: UUID?
    private(set) var branchParentID: UUID?
    private var active = false
    private var generation = 0
    private var preferredChildren: [UUID: UUID] = [:]
    private let persist: (Study) throws -> Void
    private let preferences: UserDefaults
    private let search: (Study, Int, @escaping (AIResult) -> Void) -> Void
    private let stopSearch: () -> Void

    init(study: Study, persist: @escaping (Study) throws -> Void,
         preferences: UserDefaults = .standard,
         search: @escaping (Study, Int, @escaping (AIResult) -> Void) -> Void = { study, time, done in
             EngineService.shared.search(study: study, milliseconds: time, completion: done)
         }, stopSearch: @escaping () -> Void = { EngineService.shared.stop() }) {
        self.study = study; self.persist = persist; self.preferences = preferences
        self.search = search; self.stopSearch = stopSearch
        showEvaluation = preferences.object(forKey: "showPositionEvaluation") == nil || preferences.bool(forKey: "showPositionEvaluation")
        showBranchScores = preferences.object(forKey: "showBranchEvaluation") == nil || preferences.bool(forKey: "showBranchEvaluation")
        rules = RuleSnapshot(study: study)
        rememberLine(to: study.currentID)
    }
    var pieces: [ChessPiece] { study.currentPieces }
    var side: Side { study.sideToMove }
    var lastMove: ChessMove? { study.currentNode.move }
    var destinations: Set<BoardSquare> { Set(rules.legalMoves.filter { $0.from == selected }.map(\.to)) }
    var controlledByAI: Bool { aiSide == side && !aiPaused }
    var forwardChoices: [StudyNode] { study.currentNode.children.compactMap(study.node) }
    var preferredNext: StudyNode? {
        if let id = preferredChildren[study.currentID], study.currentNode.children.contains(id) { return study.node(id) }
        return forwardChoices.count == 1 ? forwardChoices.first : nil
    }
    var forkParentID: UUID? {
        if forwardChoices.count > 1 { return study.currentID }
        if let parent = study.currentNode.parentID, (study.node(parent)?.children.count ?? 0) > 1 { return parent }
        return nil
    }
    func branches(at parent: UUID) -> [StudyNode] { study.node(parent)?.children.compactMap(study.node) ?? [] }
    var modeTitle: String { aiSide.map { "AI 执" + ($0 == .red ? "红" : "黑") } ?? "双方手动" }
    var status: String {
        if rules.error != nil { return "草稿 · 请编辑棋子后继续" }
        if rules.finished { return rules.outcome + " · 可回退继续研究" }
        if isThinking { return controlledByAI ? "\(side.title)正在思考" : "正在寻找下一步" }
        return rules.inCheck ? "\(side.title)被将军，请应将" : "\(side.title)行棋"
    }
    var controllerText: String {
        guard let aiSide else { return "双方手动" }
        return (aiPaused ? "托管已暂停 · " : "") + "AI 执" + (aiSide == .red ? "红" : "黑")
    }
    var suggestionEvaluation: PositionEvaluation? {
        suggestion.flatMap { PositionEvaluation(result: $0, side: side, milliseconds: thinkMilliseconds) }
    }
    func evaluation(for id: UUID) -> PositionEvaluation? {
        guard let value = evaluations[id], value.milliseconds == thinkMilliseconds else { return nil }
        return value
    }
    func evaluationText(for id: UUID) -> String {
        if let value = evaluation(for: id) { return value.text }
        if evaluationErrors[id] != nil { return "未获评分" }
        return analyzingID == id || (id == study.currentID && isThinking) ? "计算中…" : "待评估"
    }
    func comparison(for id: UUID, at parent: UUID) -> String? {
        let nodes = branches(at: parent)
        let scores = nodes.compactMap { evaluation(for: $0.id)?.centipawns }
        guard scores.count == nodes.count, nodes.count > 1,
              let mine = evaluation(for: id)?.centipawns else { return nil }
        var position = study; position.currentID = parent
        let best = position.sideToMove == .red ? scores.max()! : scores.min()!
        let difference = abs(best - mine)
        return difference == 0 ? "本组较优" : "较本组较优着差 " + String(format: "%.2f", Double(difference) / 100)
    }
    func activate() { active = true; continueWork() }
    func setShowEvaluation(_ value: Bool) {
        showEvaluation = value; preferences.set(value, forKey: "showPositionEvaluation")
        cancelAnalysis(); scheduleAnalysis()
    }
    func setShowBranchScores(_ value: Bool) {
        showBranchScores = value; preferences.set(value, forKey: "showBranchEvaluation")
        cancelAnalysis(); scheduleAnalysis()
    }
    func setThinkMilliseconds(_ value: Int) {
        guard value != thinkMilliseconds else { return }
        invalidate(); thinkMilliseconds = value; evaluations.removeAll(); evaluationErrors.removeAll()
        continueWork()
    }
    func openBranches() {
        if controlledByAI { stop() }
        branchParentID = forkParentID; scheduleAnalysis()
    }
    func closeBranches() {
        branchParentID = nil
        if analyzingID != nil && !(showEvaluation && analyzingID == study.currentID) { cancelAnalysis() }
        scheduleAnalysis()
    }
    func reanalyze(branches parent: UUID? = nil) {
        let ids = parent.map { branches(at: $0).map(\.id) } ?? [study.currentID]
        for id in ids { evaluations[id] = nil; evaluationErrors[id] = nil }
        cancelAnalysis(); scheduleAnalysis()
    }
    func tap(_ square: BoardSquare) {
        guard !rules.finished, rules.error == nil, !controlledByAI else { return }
        if let selected, selected != square, destinations.contains(square) {
            play(ChessMove(from: selected, to: square)); return
        }
        if let piece = pieces.first(where: { $0.square == square }), piece.side == side {
            selected = selected == square ? nil : square
            Feedback.selection()
        } else if selected != nil { selected = nil }
    }
    func drag(from: BoardSquare, to: BoardSquare) {
        guard !controlledByAI, let move = rules.legalMoves.first(where: { $0.from == from && $0.to == to }) else {
            Feedback.invalid(); return
        }
        play(move)
    }
    func play(_ move: ChessMove) {
        guard rules.legalMoves.contains(move), !rules.finished else { return }
        let capture = pieces.contains { $0.square == move.to }
        invalidate(); branchParentID = nil
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { study.play(move) }
        rememberLine(to: study.currentID)
        refresh(); save()
        Feedback.move(capture: capture)
        if rules.inCheck { Feedback.check() }
        continueWork()
    }
    func jump(to id: UUID) {
        guard study.node(id) != nil else { return }
        invalidate(); branchParentID = nil
        if aiSide != nil { aiPaused = true }
        rememberLine(to: id)
        withAnimation(.easeInOut(duration: 0.16)) { study.currentID = id }
        refresh(); save(); continueWork()
    }
    func back() { if let id = study.currentNode.parentID { jump(to: id) } }
    func forward() { if let next = preferredNext { jump(to: next.id) } }
    func flip() {
        withAnimation(.easeInOut(duration: 0.2)) { study.bottomSide = study.bottomSide.opponent }
        selected = nil; save()
    }
    func setAI(_ side: Side?) {
        invalidate(); aiSide = side; aiPaused = false; continueWork()
    }
    func resumeAI() { aiPaused = false; continueWork() }
    func recommend() { active = true; requestAI(automatic: false) }
    func adopt() { if let move = suggestion?.move { play(move) } }
    func stop() {
        if controlledByAI { aiPaused = true }
        invalidate()
    }
    func leave() { active = false; stop(); save() }
    func applyEdit(_ edited: Study) throws {
        stop()
        if aiSide != nil { aiPaused = true }
        try persist(edited)
        if edited.rootID != study.rootID {
            preferredChildren.removeAll(); evaluations.removeAll(); evaluationErrors.removeAll(); branchParentID = nil
        }
        withAnimation(.easeInOut(duration: 0.16)) { study = edited }
        rules = RuleSnapshot(study: edited, hints: showLights)
        rememberLine(to: edited.currentID)
        saved = true; continueWork()
    }
    func toggleLights() { showLights.toggle(); rules = RuleSnapshot(study: study, hints: showLights) }
    private func refresh() {
        selected = nil; rules = RuleSnapshot(study: study, hints: showLights)
        if let error = rules.error { errorMessage = error }
    }
    private func continueWork() {
        guard active, !isThinking else { return }
        if controlledByAI && !rules.finished && rules.error == nil { requestAI(automatic: true) }
        else { scheduleAnalysis() }
    }
    private func requestAI(automatic: Bool) {
        guard !rules.finished, rules.error == nil else { return }
        invalidate()
        let request = generation, node = study.currentID, position = study, budget = thinkMilliseconds
        isThinking = true
        search(position, budget) { [weak self] result in
            guard let self, self.active, self.generation == request, self.study.currentID == node else { return }
            self.isThinking = false
            guard !result.cancelled else { return }
            if let error = result.error { self.errorMessage = error; self.aiPaused = self.aiSide != nil; return }
            guard let move = result.move, self.rules.legalMoves.contains(move) else { return }
            if let value = PositionEvaluation(result: result, side: position.sideToMove, milliseconds: budget) {
                self.evaluations[node] = value; self.evaluationErrors[node] = nil
            }
            if automatic && self.controlledByAI { self.play(move) }
            else { self.suggestion = result; self.scheduleAnalysis() }
        }
    }
    private func scheduleAnalysis() {
        guard active, !isThinking, analyzingID == nil else { return }
        var ids = showEvaluation ? [study.currentID] : []
        if showBranchScores, let parent = branchParentID { ids += branches(at: parent).map(\.id) }
        guard let id = ids.first(where: { evaluation(for: $0) == nil && evaluationErrors[$0] == nil }) else { return }
        var position = study; position.currentID = id
        let snapshot = id == study.currentID ? rules : RuleSnapshot(study: position, hints: false)
        if let error = snapshot.error { evaluationErrors[id] = error; scheduleAnalysis(); return }
        if snapshot.finished {
            evaluations[id] = PositionEvaluation(winner: snapshot.winner, milliseconds: thinkMilliseconds)
            scheduleAnalysis(); return
        }
        let request = generation, current = study.currentID, budget = thinkMilliseconds
        analyzingID = id
        search(position, budget) { [weak self] result in
            guard let self, self.active, self.generation == request, self.study.currentID == current, self.analyzingID == id else { return }
            self.analyzingID = nil
            if let value = PositionEvaluation(result: result, side: position.sideToMove, milliseconds: budget) {
                self.evaluations[id] = value
            } else { self.evaluationErrors[id] = result.error ?? (result.cancelled ? "分析已中断，可重新分析。" : "本次分析未获得评分，可重新分析。") }
            self.scheduleAnalysis()
        }
    }
    private func cancelAnalysis() {
        guard analyzingID != nil else { return }
        generation += 1; stopSearch(); analyzingID = nil
    }
    private func invalidate() {
        generation += 1; stopSearch(); isThinking = false; analyzingID = nil; suggestion = nil; selected = nil
    }
    private func rememberLine(to id: UUID) {
        for node in study.line(to: id) { if let parent = node.parentID { preferredChildren[parent] = node.id } }
    }
    private func save() {
        study.modifiedAt = Date()
        do { try persist(study); saved = true }
        catch { saved = false; errorMessage = "保存失败：\(error.localizedDescription)" }
    }
}
