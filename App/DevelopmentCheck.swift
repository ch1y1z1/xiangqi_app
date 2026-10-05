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
            try require(RuleSnapshot(study: Study(name: "Empty", pieces: [])).error != nil, "Draft validation")

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
            print("CHECK_PASSED: legal moves, branches, JSON restore, draft validation, capture hints, bundled AI, cancellation")
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
                VStack(alignment: .leading, spacing: 15) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("车马练习").font(.system(size: 25, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                            Text("双方手动 · 红方行棋").font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }
                        Spacer(); Pill(title: "离线研究", color: Palette.teal)
                    }
                    BoardView(pieces: study.initialPieces, interactive: false)
                    HStack(spacing: 14) {
                        Label("可安全吃", systemImage: "circle.fill").foregroundStyle(Palette.green)
                        Label("有被吃风险", systemImage: "circle.fill").foregroundStyle(Palette.red)
                    }.font(.system(size: 10))
                    HStack { Text("推演线路").font(.system(size: 12, weight: .semibold)); Spacer(); Pill(title: "起点", color: Palette.teal) }.cardStyle()
                    HStack(spacing: 10) {
                        ActionButton(title: "AI 建议", icon: "sparkles", prominent: true) {}
                        ActionButton(title: "托管", icon: "person.crop.circle") {}
                    }
                }.padding(22).frame(width: 430).background(Palette.paper)
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
            try renderScreen(LibraryView().environmentObject(store), name: "library", folder: folder)
            try renderScreen(EditorView(study: Study.examples[1], onSave: { _, _ in false }), name: "editor", folder: folder)
            try renderScreen(StudyView(study: Study.examples[1], persist: { _ in }), name: "study", folder: folder)
            print("Rendered build/previews/board-preview.png from actual SwiftUI board components.")
        } catch { fputs("RENDER_FAILED: \(error)\n", stderr); status = 1 }
        exit(status)
    }
    private static func renderScreen<V: View>(_ view: V, name: String, folder: URL) throws {
        // Offscreen view rendering; no desktop capture, input, or foreground window.
        let size = NSSize(width: 430, height: 890)
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
