#if DEBUG
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Small development-only check, run before creating any application window.
@MainActor
enum DevelopmentCheck {
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

            let bridge = PikafishBridge()
            let network = Bundle.main.url(forResource: "pikafish", withExtension: "nnue")!.path
            let token = bridge.beginRequest()
            let result = AIResult(bridge.search(fen: study.initialFEN, moves: [], networkPath: network, milliseconds: 250, token: token))
            try require(result.error == nil && result.move.map { RuleSnapshot(study: Study(name: "Root", pieces: study.initialPieces)).legalMoves.contains($0) } == true, "Bundled NNUE recommendation")
            let cancelToken = bridge.beginRequest()
            let stop = DispatchWorkItem { bridge.stop() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.05, execute: stop)
            let cancelled = AIResult(bridge.search(fen: study.initialFEN, moves: [], networkPath: network, milliseconds: 3000, token: cancelToken))
            try require(cancelled.cancelled, "Search cancellation")
            print("CHECK_PASSED: legal moves, chosen branches, safe editor selection and undo, JSON restore, draft validation, rename and setup editing, capture hints, bundled AI, cancellation")
        } catch {
            fputs("CHECK_FAILED: \(error.localizedDescription)\n", stderr)
            status = 1
        }
        exit(status)
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
            try renderScreen(StudyView(study: Study.examples[1], persist: { _ in }), name: "study", folder: folder)
            let compact = NSSize(width: 375, height: 667)
            try renderScreen(EditorView(previewStudy: Study.examples[1], selected: Study.examples[1].initialPieces.first?.square), name: "editor-selected-compact", folder: folder, size: compact)
            try renderScreen(StudyView(study: Study.examples[1], persist: { _ in }), name: "study-compact", folder: folder, size: compact)
            let shortBody = NSSize(width: 375, height: 553)
            try renderScreen(EditorView(previewStudy: study, selected: study.initialPieces.first?.square), name: "editor-short-body", folder: folder, size: shortBody)
            try renderScreen(StudyView(study: researched, persist: { _ in }), name: "study-short-body", folder: folder, size: shortBody)
            let suggestion = StudySession(study: study, persist: { _ in })
            var following = study
            following.play(moves[0])
            let reply = RuleSnapshot(study: following, hints: false).legalMoves.first?.uci ?? ""
            suggestion.suggestion = AIResult(["bestMove": moves[0].uci, "pv": moves[0].uci + " " + reply])
            try renderScreen(StudyView(previewSession: suggestion), name: "study-suggestion", folder: folder)
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
