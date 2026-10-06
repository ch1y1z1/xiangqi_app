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
                VStack(alignment: .leading, spacing: 24) {
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
                                    Text("\(job.summary) · 点击查看").font(.system(size: 11)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11))
                            }.foregroundStyle(Palette.teal).cardStyle()
                        }.buttonStyle(.plain)
                    }
                    if let recent = store.studies.first(where: { !$0.isDraft }) {
                        VStack(alignment: .leading, spacing: 12) {
                            sectionTitle("继续研究", detail: "\(store.studies.count) 个残局")
                            Button { path.append(recent.id) } label: { recentCard(recent) }.buttonStyle(.plain)
                        }
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("我的残局", detail: "本地保存")
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
                                        .foregroundStyle(Palette.teal).frame(width: 40, height: 50)
                                }.menuStyle(.borderlessButton).menuIndicator(.hidden)
                                    .accessibilityLabel("\(study.name)的操作")
                            }
                            .padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Palette.line.opacity(0.75), lineWidth: 1))
                            .contextMenu { studyActions(study) }
                        }
                    }
                    HStack(spacing: 5) {
                        Image(systemName: "internaldrive")
                        Text("棋局与推演，留在你的设备上")
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .padding(20).frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.paper)
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
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 15).fill(Palette.red)
                Text("棋").font(.custom("STKaiti", size: 29)).foregroundStyle(Color(hex: 0xFFF3DB))
            }.frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text("象棋残局").font(.system(size: 27, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                Text("摆一盘棋，慢慢推演。").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 4)
            Button { showingSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 18)).foregroundStyle(Palette.muted)
                    .frame(width: 34, height: 42)
            }.buttonStyle(.plain).accessibilityLabel("设置")
            Button { editor = Study(name: "新残局", pieces: []) } label: {
                Image(systemName: "plus").font(.system(size: 19, weight: .medium)).foregroundStyle(Palette.teal)
                    .frame(width: 42, height: 42).background(Palette.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).accessibilityLabel("新建残局")
        }.padding(.top, 8)
    }
    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
            Spacer()
            Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
    private func recentCard(_ study: Study) -> some View {
        HStack(spacing: 18) {
            BoardView(pieces: study.currentPieces, bottom: study.bottomSide, interactive: false)
                .frame(width: 128, height: 142)
            VStack(alignment: .leading, spacing: 10) {
                Pill(title: "离线研究", color: Palette.teal)
                Text(study.name).font(.system(size: 21, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink).lineLimit(2)
                Text(study.currentLine.isEmpty ? "从初始局面开始" : "研究到第 \(study.currentLine.count) 手")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Label("继续推演", systemImage: "arrow.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.teal)
            }
            Spacer(minLength: 0)
        }.cardStyle()
    }
    private func studyRow(_ study: Study) -> some View {
        HStack(spacing: 14) {
            BoardView(pieces: study.initialPieces, interactive: false).frame(width: 78, height: 87)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(study.name).font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1)
                    if study.isDraft { Pill(title: "草稿") }
                }
                Text("\(study.initialSide.title)先行 · \(study.initialPieces.count) 枚棋子")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                Text(study.branchCount > 0 ? "\(study.nodes.count - 1) 手 · \(study.branchCount) 处分支" : "\(study.nodes.count - 1) 手推演")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
