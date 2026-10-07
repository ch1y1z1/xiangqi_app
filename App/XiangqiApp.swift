import SwiftUI

@main
struct XiangqiApp: App {
    @StateObject private var store = StudyStore()
    @StateObject private var recognition = ImageRecognitionJob.shared
    #if os(iOS)
    @UIApplicationDelegateAdaptor(RecognitionAppDelegate.self) private var appDelegate
    #endif
    init() {
        #if DEBUG
        if CommandLine.arguments.contains("--check-image-import") { ImageImportCheck.run() }
        if CommandLine.arguments.contains("--check") { DevelopmentCheck.run() }
        #if os(macOS)
        if CommandLine.arguments.contains("--prepare-recognition-audit") { ImageImportCheck.prepareAudit() }
        if CommandLine.arguments.contains("--audit-recognition-responses") { ImageImportCheck.auditResponses() }
        if CommandLine.arguments.contains("--render-preview") { DevelopmentCheck.render() }
        #endif
        #endif
    }
    var body: some Scene {
        #if os(macOS)
        Window("象棋残局", id: "main") {
            rootView.frame(minWidth: 390, idealWidth: 430, minHeight: 740, idealHeight: 890)
        }
        .defaultSize(width: 430, height: 890)
        #else
        WindowGroup("象棋残局") { rootView }
        #endif
    }
    private var rootView: some View {
        content.environmentObject(store).environmentObject(recognition).preferredColorScheme(.light)
    }
    @ViewBuilder private var content: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--preview-editor") {
            EditorView(previewStudy: Study.examples[1], selected: Study.examples[1].initialPieces.first?.square)
        } else if CommandLine.arguments.contains("--preview-study") {
            NavigationStack { StudyView(study: Study.examples[1], persist: { _ in }) }
        } else {
            LibraryView()
        }
        #else
        LibraryView()
        #endif
    }
}
