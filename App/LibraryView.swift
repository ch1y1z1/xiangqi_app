import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: StudyStore
    @EnvironmentObject private var recognition: ImageRecognitionJob
    @State private var path: [UUID] = []
    @State private var editor: Study?
    @State private var renaming: Study?
    @State private var name = ""
    @State private var deleting: Study?
    @State private var showingSettings = false
    @State private var resumingRecognition = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let job = recognition.record {
                        Button {
                            resumingRecognition = true
                            editor = Study(name: "新残局", pieces: [])
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: job.status == .running ? "photo" : job.status == .ready ? "checkmark.circle" : "exclamationmark.circle")
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(job.status == .running ? "图片正在识别" : job.status == .ready ? "图片识别已完成" : "图片识别未完成")
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(job.status == .ready ? "\(job.result?.chessPieces.count ?? 0) 枚棋子待校正" : job.status == .running ? "点击查看进度" : "查看或重新识别").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11))
                            }.foregroundStyle(Palette.teal).cardStyle()
                        }.buttonStyle(.plain)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("我的残局", detail: "\(store.studies.count) 个")
                        if store.studies.isEmpty {
                            ContentUnavailableView("还没有残局", systemImage: "square.grid.3x3",
                                                   description: Text("从一张空棋盘开始，摆出你的第一局。"))
                        }
                        ForEach(store.studies) { study in
                            HStack(spacing: 0) {
                                Button {
                                    if study.isDraft { editor = study } else { path.append(study.id) }
                                } label: { studyRow(study).contentShape(Rectangle()) }
                                    .buttonStyle(.plain)
                                Menu { studyActions(study) } label: {
                                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(Palette.teal).frame(width: 44, height: 44)
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                                    .accessibilityLabel("\(study.name)的操作")
                            }
                            .padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.75), lineWidth: 1))
                            .contextMenu { studyActions(study) }
                        }
                    }
                }
                .padding(16).frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper).compactNavigation()
            .navigationDestination(for: UUID.self) { id in
                if let study = store.studies.first(where: { $0.id == id }) {
                    StudyView(study: study, persist: { try store.saveEdited($0) })
                }
            }
            .sheet(item: $editor, onDismiss: { resumingRecognition = false }) { draft in
                EditorView(study: draft, importingImage: resumingRecognition) { study, start in
                    try store.saveEdited(study); editor = nil
                    if start { path.append(study.id) }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .alert("为残局命名", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("名称", text: $name)
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") {
                    if var study = renaming {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        study.name = trimmed.isEmpty ? "未命名残局" : trimmed
                        study.modifiedAt = Date()
                        do { try store.save(study) } catch { store.errorMessage = error.localizedDescription }
                    }
                    renaming = nil
                }
            }
            .confirmationDialog("删除这个残局及其全部推演？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
                Button("删除残局", role: .destructive) { if let study = deleting { store.delete(study) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            }
            .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("知道了") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
        .tint(Palette.teal)
    }
    @ViewBuilder private func studyActions(_ study: Study) -> some View {
        Button("修改名称", systemImage: "pencil") { name = study.name; renaming = study }
        Button("编辑棋子与名称", systemImage: "square.and.pencil") { editor = study }
        Button("复制", systemImage: "doc.on.doc") { store.copy(study) }
        Button("删除残局", systemImage: "trash", role: .destructive) { deleting = study }
    }
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(Palette.red)
                Text("棋").font(.custom("STKaiti", size: 25)).foregroundStyle(Color(hex: 0xFFF3DB))
            }.frame(width: 40, height: 40)
            Text("象棋残局").font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("设置")
            Button { editor = Study(name: "新残局", pieces: []) } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.teal)
                    .frame(width: 44, height: 44).background(Palette.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain).accessibilityLabel("新建残局")
        }
    }
    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
    }
    private var recentID: UUID? { store.studies.first(where: { !$0.isDraft && $0.nodes.count > 1 })?.id }
    private func studyRow(_ study: Study) -> some View {
        HStack(spacing: 12) {
            BoardView(pieces: study.isDraft ? study.initialPieces : study.currentPieces, bottom: study.bottomSide, interactive: false)
                .frame(width: 72, height: 80)
            VStack(alignment: .leading, spacing: 7) {
                Text(study.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(2)
                if study.isDraft {
                    Pill(title: "草稿")
                } else if study.id == recentID {
                    Pill(title: "继续研究", color: Palette.teal)
                }
                Text(study.nodes.count > 1 ? "第 \(study.currentLine.count) 手" + (study.branchCount > 0 ? " · \(study.branchCount) 处分支" : "") : "\(study.initialSide.title)先行 · \(study.initialPieces.count) 枚棋子")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
