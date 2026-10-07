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
    @Published var thinkMilliseconds = 1000
    private var generation = 0
    private var preferredChildren: [UUID: UUID] = [:]
    private let persist: (Study) throws -> Void

    init(study: Study, persist: @escaping (Study) throws -> Void) {
        self.study = study; self.persist = persist; rules = RuleSnapshot(study: study)
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
    func tap(_ square: BoardSquare) {
        guard !rules.finished, rules.error == nil else { return }
        if controlledByAI { return }
        if let selected, selected != square, destinations.contains(square) {
            play(ChessMove(from: selected, to: square)); return
        }
        if let piece = pieces.first(where: { $0.square == square }), piece.side == side {
            selected = selected == square ? nil : square
            Feedback.selection()
        } else if selected != nil {
            selected = nil
        }
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
        invalidate()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.86)) { study.play(move) }
        rememberLine(to: study.currentID)
        refresh()
        save()
        Feedback.move(capture: capture)
        if rules.inCheck { Feedback.check() }
        continueAI()
    }
    func jump(to id: UUID) {
        guard study.node(id) != nil else { return }
        invalidate()
        if aiSide != nil { aiPaused = true }
        rememberLine(to: id)
        withAnimation(.easeInOut(duration: 0.16)) { study.currentID = id }
        refresh(); save()
    }
    func back() { if let id = study.currentNode.parentID { jump(to: id) } }
    func forward() { if let next = preferredNext { jump(to: next.id) } }
    func flip() {
        withAnimation(.easeInOut(duration: 0.2)) { study.bottomSide = study.bottomSide.opponent }
        selected = nil; save()
    }
    func setAI(_ side: Side?) {
        invalidate(); aiSide = side; aiPaused = false
        continueAI()
    }
    func resumeAI() { aiPaused = false; continueAI() }
    func recommend() { requestAI(automatic: false) }
    func adopt() { if let move = suggestion?.move { play(move) } }
    func stop() {
        if controlledByAI { aiPaused = true }
        invalidate()
    }
    func leave() { stop(); save() }
    func applyEdit(_ edited: Study) throws {
        stop()
        if aiSide != nil { aiPaused = true }
        try persist(edited)
        if edited.rootID != study.rootID { preferredChildren.removeAll() }
        withAnimation(.easeInOut(duration: 0.16)) { study = edited }
        rules = RuleSnapshot(study: edited, hints: showLights)
        rememberLine(to: edited.currentID)
        saved = true
    }
    func toggleLights() { showLights.toggle(); rules = RuleSnapshot(study: study, hints: showLights) }
    private func refresh() {
        selected = nil; rules = RuleSnapshot(study: study, hints: showLights)
        if let error = rules.error { errorMessage = error }
    }
    private func continueAI() {
        if controlledByAI && !rules.finished && rules.error == nil { requestAI(automatic: true) }
    }
    private func requestAI(automatic: Bool) {
        guard !rules.finished, rules.error == nil else { return }
        invalidate()
        let request = generation
        let node = study.currentID
        isThinking = true
        EngineService.shared.search(study: study, milliseconds: thinkMilliseconds) { [weak self] result in
            guard let self, self.generation == request, self.study.currentID == node else { return }
            self.isThinking = false
            guard !result.cancelled else { return }
            if let error = result.error { self.errorMessage = error; self.aiPaused = self.aiSide != nil; return }
            guard let move = result.move, self.rules.legalMoves.contains(move) else { return }
            if automatic && self.controlledByAI { self.play(move) }
            else { self.suggestion = result }
        }
    }
    private func invalidate() {
        generation += 1; EngineService.shared.stop(); isThinking = false; suggestion = nil; selected = nil
    }
    private func rememberLine(to id: UUID) {
        for node in study.line(to: id) {
            if let parent = node.parentID { preferredChildren[parent] = node.id }
        }
    }
    private func save() {
        study.modifiedAt = Date()
        do { try persist(study); saved = true }
        catch { saved = false; errorMessage = "保存失败：\(error.localizedDescription)" }
    }
}
