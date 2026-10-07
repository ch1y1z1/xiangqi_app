#if DEBUG
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Small development-only check, run before creating any application window.
@MainActor
enum DevelopmentCheck {
    static var branchExample: Study {
        var study = Study.examples[1]
        let moves = RuleSnapshot(study: study, hints: false).legalMoves
        study.play(moves[0]); study.currentID = study.rootID; study.play(moves[1]); study.currentID = study.rootID
        return study
    }
    static func run() {
        var status: Int32 = 0
        do {
            func require(_ condition: Bool, _ message: String) throws {
                if !condition { throw NSError(domain: "XiangqiCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
            }
            var study = Study(name: "Development check", pieces: ChessPosition.pieces(fen: ChessPosition.initialFEN))
            study.isDraft = false
            try require(RuleSnapshot(study: study).legalMoves.count == 44, "Initial legal move generation")
            let first = ChessMove(uci: "b2e2")!, alternate = ChessMove(uci: "h2e2")!
            study.play(first)
            let firstID = study.currentID
            try require(RuleSnapshot(study: study).error == nil, "History replay")
            study.currentID = study.rootID; study.play(alternate)
            try require(study.node(study.rootID)!.children.count == 2, "Branch preservation")
            study.currentID = study.rootID; study.play(first)
            try require(study.currentID == firstID && study.nodes.count == 3, "Existing branch reuse")
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("xiangqi-check-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = StudyStore(directory: directory, seedExamples: false)
            try store.save(study)
            let restored = StudyStore(directory: directory, seedExamples: false)
            try require(restored.studies.first == study, "JSON save and restore")
            let session = StudySession(study: study, persist: { try store.save($0) })
            session.back(); session.play(alternate)
            try require(session.study.nodes.count == 3 && session.study.currentNode.move == alternate, "Session navigation and branch reuse")
            let alternateID = session.study.currentID
            session.back(); session.forward()
            try require(session.study.currentID == alternateID, "Forward follows the branch most recently chosen")
            var fork = study
            fork.currentID = fork.rootID
            let forkSession = StudySession(study: fork, persist: { _ in })
            try require(forkSession.preferredNext == nil && forkSession.forwardChoices.count == 2, "An unresolved fork requires an explicit choice")
            forkSession.jump(to: firstID); forkSession.back(); forkSession.forward()
            try require(forkSession.study.currentID == firstID, "Explicit branch choice is retained across navigation")

            var board = PositionEditorState(pieces: study.initialPieces)
            let occupied = BoardSquare(file: 0, rank: 0), other = BoardSquare(file: 1, rank: 0)
            _ = board.tap(occupied); _ = board.tap(other)
            try require(board.selected == other && board.pieces == study.initialPieces, "Selecting another piece never replaces it")
            try require(board.move(from: occupied, to: other) != nil && board.pieces == study.initialPieces, "Dragging onto an occupied square is rejected")
            board.deleteSelected(); board.undo()
            try require(board.pieces == study.initialPieces && board.redoStack.count == 1, "Piece deletion can be undone with identity intact")
            board.replace([]); board.undo()
            try require(board.pieces == study.initialPieces, "Clearing the board is reversible")
            var placement = PositionEditorState(pieces: [])
            placement.choose(.king, side: .red)
            _ = placement.tap(BoardSquare(file: 4, rank: 0))
            _ = placement.tap(BoardSquare(file: 3, rank: 0))
            try require(placement.pieces.count == 1 && placement.placementKind == nil, "Exhausted piece types end placement without creating extra pieces")
            try require(RuleSnapshot(study: Study(name: "Empty", pieces: [])).error != nil, "Draft validation")

            let editingStore = StudyStore(directory: directory.appendingPathComponent("editing"), seedExamples: false)
            try editingStore.save(study)
            let renamed = study.editingSetup(name: "  Renamed study  ", pieces: study.initialPieces, side: study.initialSide, bottom: .black)
            try editingStore.saveEdited(renamed)
            try require(renamed.name == "Renamed study" && renamed.id == study.id && renamed.nodes == study.nodes && renamed.currentID == study.currentID,
                        "Renaming preserves current branch and study identity")
            try require(editingStore.studies.count == 1, "Renaming does not duplicate a study")
            let editedPieces = study.initialPieces.filter { $0.square != BoardSquare(file: 0, rank: 3) }
            let edited = renamed.editingSetup(name: renamed.name, pieces: editedPieces, side: renamed.initialSide, bottom: .black)
            let editingSession = StudySession(study: renamed, persist: { try editingStore.saveEdited($0) })
            editingSession.setAI(.red)
            try editingSession.applyEdit(edited)
            let editedRestored = StudyStore(directory: directory.appendingPathComponent("editing"), seedExamples: false)
            try require(editedRestored.studies.count == 2 && editingSession.study.id == study.id && editingSession.study.nodes.count == 1,
                        "Setup edit replaces the study and resets its line")
            try require(editedRestored.studies.contains { $0.id != study.id && $0.nodes == study.nodes && $0.currentID == study.currentID },
                        "Original branches survive setup editing in a saved backup")
            try require(editingSession.rules.error == nil && editingSession.study.bottomSide == .black, "Edited session refreshes rules and orientation")
            try require(editingSession.aiPaused, "Setup editing pauses AI even if the new starting side belongs to AI")

            let target = ChessMove(uci: "a1c1")!
            func hints(_ fen: String) -> [SafeCapture] {
                RuleSnapshot(study: Study(name: "Hints", pieces: ChessPosition.pieces(fen: fen))).captures
            }
            try require(hints("4k4/9/9/9/4p4/9/9/9/R1p6/4K4 w - - 0 1").contains { $0.move == target }, "Unprotected capture hint")
            try require(!hints("4k4/2r6/9/9/4p4/9/9/9/R1p6/4K4 w - - 0 1").contains { $0.move == target }, "Legal recapture suppresses hint")
            try require(hints("R1r1k4/9/9/9/4p4/9/9/9/R1p6/4K4 w - - 0 1").contains { $0.move == target }, "Pinned defender cannot recapture")

            try checkEvaluation()
            try checkAdviceWithAIControl()

            let bridge = PikafishBridge()
            let network = Bundle.main.url(forResource: "pikafish", withExtension: "nnue")!.path
            let token = bridge.beginRequest()
            let result = AIResult(bridge.search(fen: study.initialFEN, moves: [], networkPath: network, milliseconds: 250, token: token))
            try require(result.error == nil && result.move.map { RuleSnapshot(study: Study(name: "Root", pieces: study.initialPieces)).legalMoves.contains($0) } == true, "Bundled NNUE recommendation")
            try require(PositionEvaluation(result: result, side: .red, milliseconds: 250) != nil, "Real search returns a displayable evaluation")
            let cancelToken = bridge.beginRequest()
            let stop = DispatchWorkItem { bridge.stop() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05, execute: stop)
            let cancelled = AIResult(bridge.search(fen: study.initialFEN, moves: [], networkPath: network, milliseconds: 3000, token: cancelToken))
            try require(cancelled.cancelled, "Search cancellation")
            print("CHECK_PASSED: legal moves, chosen branches, safe editor selection and undo, JSON restore, draft validation, rename and setup editing, capture hints, bundled AI, evaluation scheduling and cancellation, advice preserving AI control")
        } catch {
            fputs("CHECK_FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        exit(status)
    }

    private static func checkEvaluation() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "EvaluationCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let suite = "xiangqi-evaluation-check-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        func result(_ score: Int, mate: Bool = false, bound: String = "") -> AIResult {
            AIResult(["bestMove": "b2e2", "score": score, "mate": mate, "bound": bound, "depth": 18])
        }
        try require(PositionEvaluation(result: result(125, bound: "lowerbound"), side: .black, milliseconds: 1000)?.text == "红 ≤-1.25", "Black scores and bounds normalize to Red")
        try require(PositionEvaluation(result: result(3, mate: true), side: .black, milliseconds: 1000)?.text == "黑 M2", "Mate distance is separate from ordinary scores")
        try require(PositionEvaluation(result: AIResult(["score": 0]), side: .red, milliseconds: 1000) == nil, "Missing depth is never displayed as a zero evaluation")
        let terminal = Study(name: "Stalemate", pieces: ChessPosition.pieces(fen: "4k4/3R1R3/9/9/9/9/9/9/9/3K5 b - - 0 1"), side: .black)
        let outcome = RuleSnapshot(study: terminal, hints: false)
        try require(outcome.finished && outcome.winner == .red, "Stalemate is a loss for the side with no legal move")
        try require(PositionEvaluation(winner: nil, milliseconds: 1000).text == "和棋", "Terminal draw is explicit")

        var fork = Study(name: "Scores", pieces: ChessPosition.pieces(fen: ChessPosition.initialFEN))
        fork.play(ChessMove(uci: "b2e2")!); let firstID = fork.currentID
        fork.play(RuleSnapshot(study: fork, hints: false).legalMoves[0])
        fork.currentID = fork.rootID; fork.play(ChessMove(uci: "h2e2")!); let secondID = fork.currentID
        fork.currentID = fork.rootID
        let originalNodes = fork.nodes
        var requests: [(Study, Int, (AIResult) -> Void)] = []
        let session = StudySession(study: fork, persist: { _ in }, preferences: preferences,
                                   search: { requests.append(($0, $1, $2)) }, stopSearch: {})
        try require(session.showEvaluation && session.showBranchScores, "Research score switches default on")
        session.activate(); session.openBranches()
        try require(requests.count == 1 && requests[0].0.currentID == fork.rootID, "Current node is analyzed before its branches")
        session.recommend()
        try require(requests.count == 2 && session.isThinking, "Explicit AI advice preempts background analysis")
        requests[0].2(result(900))
        try require(session.evaluation(for: fork.rootID) == nil, "Preempted results are ignored")
        requests[1].2(result(260))
        try require(requests.count == 3 && session.suggestionEvaluation?.centipawns == 260 && requests[2].0.currentID == firstID, "Advice always includes a score and branch analysis resumes")
        try require(requests[2].0.currentLine.count == 1, "Branch evaluation uses the next move, not its saved leaf")
        requests[2].2(result(-240)); requests[3].2(result(-140))
        try require(session.comparison(for: firstID, at: fork.rootID) == "本组较优" && session.comparison(for: secondID, at: fork.rootID) == "较本组较优着差 1.00", "Red branch comparisons use normalized scores")
        try require(session.study.nodes == originalNodes && session.study.currentID == fork.rootID, "Evaluation does not play moves or add branches")
        session.flip(); session.jump(to: firstID); session.back()
        try require(requests.count == 4 && session.evaluation(for: firstID)?.centipawns == 240, "Navigation and board flip reuse node evaluations")
        session.openBranches(); session.reanalyze(branches: fork.rootID); session.closeBranches()
        requests[4].2(result(-500))
        try require(session.evaluation(for: firstID) == nil && requests.count == 5, "Closing comparison cancels its remaining analyses")
        session.setShowEvaluation(false); session.openBranches()
        try require(requests.count == 6 && requests[5].0.currentID == firstID, "Branch analysis works while current-score display is off")
        session.setShowBranchScores(false); requests[5].2(result(-500))
        try require(requests.count == 6 && session.evaluation(for: firstID) == nil, "Disabling both switches cancels background work")
        session.recommend(); requests[6].2(result(280))
        try require(session.suggestionEvaluation?.centipawns == 280 && requests.count == 7, "AI advice still has a score with both switches off")
        let restored = StudySession(study: fork, persist: { _ in }, preferences: preferences)
        try require(!restored.showEvaluation && !restored.showBranchScores, "Switch preferences persist independently")
        session.recommend(); session.jump(to: firstID); requests[7].2(result(990))
        try require(session.suggestion == nil && session.evaluation(for: firstID) == nil, "Advice cannot land on a different node")
        session.setThinkMilliseconds(300); session.setShowEvaluation(true); session.setThinkMilliseconds(1000)
        requests[8].2(result(-700))
        try require(session.evaluation(for: firstID) == nil && requests[8].1 == 300 && requests[9].1 == 1000, "Budget changes invalidate cached and pending evaluations")
        requests[9].2(result(100))
        try require(session.evaluation(for: firstID)?.centipawns == -100, "Accepted score belongs to the new budget and current side")
        session.reanalyze()
        let edited = session.study.editingSetup(name: "Edited", pieces: fork.initialPieces.filter { $0.square != BoardSquare(file: 0, rank: 3) }, side: .red, bottom: .red)
        try session.applyEdit(edited); requests[10].2(result(300)); session.leave(); requests[11].2(result(400))
        try require(session.evaluations.isEmpty && session.analyzingID == nil, "Setup edits and leaving reject late results")

        var blackFork = fork
        blackFork.currentID = firstID
        let reply = RuleSnapshot(study: blackFork, hints: false).legalMoves.last!
        blackFork.play(reply); blackFork.currentID = firstID
        var blackRequests: [(Study, Int, (AIResult) -> Void)] = []
        let black = StudySession(study: blackFork, persist: { _ in }, preferences: preferences,
                                 search: { blackRequests.append(($0, $1, $2)) }, stopSearch: {})
        black.setShowEvaluation(false); black.setShowBranchScores(true); black.activate(); black.openBranches()
        blackRequests[0].2(result(300)); blackRequests[1].2(result(100))
        let blackChildren = black.branches(at: firstID)
        try require(black.comparison(for: blackChildren[0].id, at: firstID) == "较本组较优着差 2.00" && black.comparison(for: blackChildren[1].id, at: firstID) == "本组较优", "Lower Red score favors Black at a Black fork")
        black.reanalyze(branches: firstID)
        blackRequests[2].2(result(300, bound: "lowerbound")); blackRequests[3].2(AIResult(["error": "Unavailable"]))
        black.activate()
        try require(black.comparison(for: blackChildren[0].id, at: firstID) == nil && blackRequests.count == 4 && black.evaluationText(for: blackChildren[1].id) == "未获评分", "Bounds and failures never form exact gaps or retry automatically")
        black.reanalyze(branches: firstID)
        try require(blackRequests.count == 5, "Failed analysis can be retried explicitly")
        black.leave()
    }

    private static func checkAdviceWithAIControl() throws {
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "AIControlCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        let suite = "xiangqi-ai-control-check-" + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(false, forKey: "showPositionEvaluation")
        preferences.set(false, forKey: "showBranchEvaluation")
        func result(_ move: ChessMove) -> AIResult {
            AIResult(["bestMove": move.uci, "score": 20, "depth": 12])
        }
        for human in [Side.red, .black] {
            for action in ["adopt", "other", "pending", "stop", "failure"] {
                let study = Study(name: "Advice and control", pieces: ChessPosition.pieces(fen: ChessPosition.initialFEN), side: human)
                var requests: [(Study, (AIResult) -> Void)] = []
                let session = StudySession(study: study, persist: { _ in }, preferences: preferences,
                                           search: { position, _, done in requests.append((position, done)) }, stopSearch: {})
                session.activate(); session.setAI(human.opponent)
                let recommended = session.rules.legalMoves[0], other = session.rules.legalMoves[1]
                session.recommend()
                try require(requests.count == 1 && session.aiSide == human.opponent && !session.aiPaused && session.study.currentID == study.rootID,
                            "Requesting human advice preserves AI control and does not play a move")
                switch action {
                case "failure":
                    requests[0].1(AIResult(["error": "Advice unavailable"]))
                    try require(session.errorMessage != nil && !session.aiPaused, "An advice failure must not pause the opponent's AI")
                case "stop":
                    session.stop(); requests[0].1(result(recommended))
                    try require(session.suggestion == nil && !session.aiPaused, "Stopping advice ignores its late result and preserves AI control")
                case "pending": break
                default:
                    requests[0].1(result(recommended))
                    try require(session.suggestion?.move == recommended && !session.aiPaused && session.study.currentID == study.rootID,
                                "Completed advice waits for the human move and preserves AI control")
                }
                if action == "adopt" { session.adopt() }
                else { session.drag(from: other.from, to: other.to) }
                try require(requests.count == 2 && requests[1].0.currentLine.count == 1 && requests[1].0.sideToMove == human.opponent && session.isThinking && !session.aiPaused,
                            "Adopting advice or playing another move starts the opponent's automatic reply")
                if action == "pending" {
                    requests[0].1(result(recommended))
                    try require(session.suggestion == nil && session.isThinking, "Advice cannot land after the human moves")
                }
                let reply = session.rules.legalMoves[0]
                requests[1].1(result(reply))
                try require(session.study.currentLine.count == 2 && session.side == human && !session.aiPaused && session.suggestion == nil,
                            "The controlled opponent plays its reply automatically")
                session.leave()
            }
        }
        var automaticRequests: [(AIResult) -> Void] = []
        let automatic = StudySession(study: Study.examples[2], persist: { _ in }, preferences: preferences,
                                     search: { _, _, done in automaticRequests.append(done) }, stopSearch: {})
        automatic.activate(); automatic.setAI(.red)
        automaticRequests[0](AIResult(["error": "Automatic search unavailable"]))
        try require(automatic.aiPaused && !automatic.isThinking, "An automatic reply failure still pauses AI control explicitly")
        automatic.recommend(); automaticRequests[1](result(automatic.rules.legalMoves[0]))
        try require(automatic.aiPaused && automatic.suggestion != nil, "Advice must also preserve an already paused control state")
        automatic.resumeAI(); automatic.stop(); automaticRequests[2](result(automatic.rules.legalMoves[0]))
        try require(automatic.aiPaused && automatic.study.currentID == automatic.study.rootID, "Stopping an automatic search still pauses control and rejects its late move")
        automatic.leave()

        preferences.set(true, forKey: "showPositionEvaluation")
        var scoredRequests: [(Study, (AIResult) -> Void)] = []
        let scored = StudySession(study: Study.examples[2], persist: { _ in }, preferences: preferences,
                                  search: { position, _, done in scoredRequests.append((position, done)) }, stopSearch: {})
        scored.activate(); scored.setAI(.black); scored.recommend()
        let move = scored.rules.legalMoves[0]
        scoredRequests[2].1(result(move)); scored.adopt()
        try require(scoredRequests.count == 4 && scored.isThinking && !scored.aiPaused, "Advice preempts position evaluation without disabling the automatic reply")
        scoredRequests[0].1(AIResult(["error": "Cancelled evaluation"]))
        scoredRequests[1].1(result(move))
        try require(scored.isThinking && scored.suggestion == nil && !scored.aiPaused, "Old evaluation callbacks cannot interrupt the automatic reply")
        scoredRequests[3].1(result(scored.rules.legalMoves[0]))
        try require(scored.study.currentLine.count == 2 && scoredRequests.count == 5 && scored.analyzingID == scored.study.currentID && !scored.aiPaused,
                    "Current-position evaluation resumes after the automatic reply")
        scored.leave()
    }

    #if os(macOS)
    static func render() {
        var status: Int32 = 0
        let folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/previews")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let study = Study.examples[1]
            let renderer = ImageRenderer(content:
                BoardView(pieces: study.initialPieces, interactive: false)
                    .frame(width: 398, height: 442).padding(16).background(Palette.paper)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let data = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data),
                  let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Render", code: 1) }
            try png.write(to: folder.appendingPathComponent("board-preview.png"))
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("xiangqi-preview-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let store = StudyStore(directory: temporary)
            let recognition = ImageRecognitionJob(directory: temporary.appendingPathComponent("Recognition"))
            let previewPreferences = UserDefaults(suiteName: "xiangqi-evaluation-preview")!
            previewPreferences.removePersistentDomain(forName: "xiangqi-evaluation-preview")
            defer { previewPreferences.removePersistentDomain(forName: "xiangqi-evaluation-preview") }
            let previewBridge = PikafishBridge()
            let network = Bundle.main.url(forResource: "pikafish", withExtension: "nnue")!.path
            func evaluated(_ position: Study) -> StudySession {
                let session = StudySession(study: position, persist: { _ in }, preferences: previewPreferences,
                    search: { position, budget, done in
                        let token = previewBridge.beginRequest()
                        done(AIResult(previewBridge.search(fen: position.initialFEN, moves: position.currentLine.compactMap { $0.move?.uci }, networkPath: network, milliseconds: budget, token: token)))
                    }, stopSearch: { previewBridge.stop() })
                session.activate()
                return session
            }
            let studySession = evaluated(study)
            var researched = store.studies.first(where: { $0.name == study.name }) ?? study
            let moves = RuleSnapshot(study: researched, hints: false).legalMoves
            researched.play(moves[0]); researched.currentID = researched.rootID; researched.play(moves[1])
            try store.save(researched)
            try renderScreen(LibraryView().environmentObject(store).environmentObject(recognition), name: "library", folder: folder)
            try renderScreen(EditorView(study: Study.examples[1], onSave: { _, _ in }), name: "editor", folder: folder)
            try renderScreen(SettingsView(), name: "settings", folder: folder)
            var custom = RecognitionSettings()
            custom.provider = .custom
            custom.address = "https://example.com/v1"
            custom.model = "vision-model"
            try renderScreen(SettingsView(settings: custom), name: "settings-custom", folder: folder)
            try renderScreen(ImageImportView(onImport: { _, _ in }).environmentObject(recognition), name: "image-import", folder: folder)
            try renderScreen(StudyView(previewSession: studySession), name: "study", folder: folder)
            let compact = NSSize(width: 375, height: 667)
            try renderScreen(EditorView(previewStudy: Study.examples[1], selected: Study.examples[1].initialPieces.first?.square), name: "editor-selected-compact", folder: folder, size: compact)
            try renderScreen(StudyView(previewSession: studySession), name: "study-compact", folder: folder, size: compact)
            let shortBody = NSSize(width: 375, height: 553)
            try renderScreen(EditorView(previewStudy: study, selected: study.initialPieces.first?.square), name: "editor-short-body", folder: folder, size: shortBody)
            try renderScreen(StudyView(previewSession: evaluated(researched)), name: "study-short-body", folder: folder, size: shortBody)
            studySession.recommend()
            try renderScreen(StudyView(previewSession: studySession), name: "study-suggestion", folder: folder)
            try renderScreen(EvaluationDetailView(session: studySession), name: "evaluation-detail", folder: folder, size: NSSize(width: 375, height: 350))
            var ordinaryFork = Study.examples[2]
            ordinaryFork.play(ChessMove(uci: "b2e2")!); ordinaryFork.currentID = ordinaryFork.rootID
            ordinaryFork.play(ChessMove(uci: "h2e2")!); ordinaryFork.currentID = ordinaryFork.rootID
            let branchSession = evaluated(ordinaryFork)
            branchSession.openBranches()
            try renderScreen(BranchComparisonView(session: branchSession, parentID: branchSession.study.rootID, onChoose: { _ in }), name: "branch-scores", folder: folder, size: NSSize(width: 430, height: 600))
            let original = try RecognitionImage(data: png)
            try renderScreen(EditorView(previewStudy: Study.examples[1], sourceImage: original), name: "editor-correction", folder: folder)
            try renderScreen(ImageReviewView(image: original, title: "原图"), name: "image-review", folder: folder)
            let readyFolder = temporary.appendingPathComponent("ReadyRecognition")
            try FileManager.default.createDirectory(at: readyFolder, withIntermediateDirectories: true)
            let result = RecognizedSetup(bottomSide: .red, pieces: study.initialPieces.map { .init(side: $0.side, kind: $0.kind, column: $0.square.file, row: 9 - $0.square.rank) })
            let record = ImageRecognitionJob.Record(id: UUID(), service: "预览", summary: "预览", api: .chatCompletions, status: .ready, result: result)
            try JSONEncoder().encode(record).write(to: readyFolder.appendingPathComponent("job.json"))
            let ready = ImageRecognitionJob(directory: readyFolder)
            try renderScreen(ImageImportView(previewImage: original, onImport: { _, _ in }).environmentObject(ready), name: "image-import-ready", folder: folder)
            print("Rendered actual SwiftUI pages and compact/state previews in build/previews/.")
        } catch { fputs("RENDER_FAILED: \(error)\n", stderr); status = 1 }
        exit(status)
    }
    static func renderScreen<V: View>(_ view: V, name: String, folder: URL, size: NSSize = NSSize(width: 430, height: 890)) throws {
        // Offscreen view rendering; no desktop capture, input, or foreground window.
        let hosting = NSHostingView(rootView: view.preferredColorScheme(.light))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw NSError(domain: "Render", code: 2) }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "Render", code: 3) }
        try png.write(to: folder.appendingPathComponent(name + ".png"))
    }
    #endif
}
#endif
