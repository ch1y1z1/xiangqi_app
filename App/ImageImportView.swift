import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImageImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var recognition: ImageRecognitionJob
    @State private var photo: PhotosPickerItem?
    @State private var image: RecognitionImage?
    @State private var pickingFile = false
    @State private var showingSettings = false
    @State private var viewingImage = false
    @State private var settings = RecognitionSettings.saved
    @State private var configured = false
    @State private var loading = false
    @State private var message: String?
    // Photo preparation belongs to this sheet; recognition belongs to the app.
    @State private var work: Task<Void, Never>?
    var onImport: (RecognizedSetup, Data?) -> Void
    private var busy: Bool { loading || recognition.isRunning }

    init(onImport: @escaping (RecognizedSetup, Data?) -> Void) { self.onImport = onImport }
    #if DEBUG
    init(previewImage: RecognitionImage, onImport: @escaping (RecognizedSetup, Data?) -> Void) {
        self.init(onImport: onImport)
        _image = State(initialValue: previewImage)
    }
    #endif

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("返回摆棋")
                Text("从图片摆棋").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity)
                Button { showingSettings = true } label: { Image(systemName: "gearshape").frame(width: 44, height: 44) }
                    .disabled(busy).accessibilityLabel("识别服务设置")
            }.buttonStyle(.plain).foregroundStyle(Palette.ink)
            GeometryReader { geometry in
                if let image {
                    Button { viewingImage = true } label: {
                        Image(decorative: image.preview, scale: 1).resizable().scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel("查看并放大棋盘图片")
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled").font(.system(size: 38, weight: .light)).foregroundStyle(Palette.teal)
                        Text("选择棋盘图片").font(.system(size: 18, weight: .medium))
                        Text("请保留完整棋盘与清晰的棋子").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(Palette.ink)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if image != nil && recognition.record?.status != .ready {
                sourceButtons(prominent: false)
            }
            footer
        }.padding(.horizontal, 16).padding(.vertical, 8).frame(maxWidth: 490)
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.paper).tint(Palette.teal)
            #if os(macOS)
            .frame(minWidth: 350, idealWidth: 430, minHeight: 530, idealHeight: 820)
            #endif
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                prepare {
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    return try Data(contentsOf: url)
                }
            case .failure(let error): message = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            prepare {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw ImageImportError(message: "无法读取这张照片，请重选或从文件导入。")
                }
                return data
            }
        }
        .sheet(isPresented: $showingSettings, onDismiss: refreshSettings) { SettingsView() }
        .sheet(isPresented: $viewingImage) { if let image { ImageReviewView(image: image, title: "棋盘图片") } }
        .onAppear {
            refreshSettings()
            if image == nil, let data = recognition.imageData { image = try? RecognitionImage(data: data) }
        }
        .onDisappear { work?.cancel() }
    }
    @ViewBuilder private var footer: some View {
        VStack(spacing: 10) {
            if loading {
                ProgressView("正在准备图片…").font(.system(size: 12))
            } else if recognition.isRunning {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在识别棋盘…").font(.system(size: 13))
                    Spacer()
                    Button("停止") { recognition.discard() }.frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(Palette.red).buttonStyle(.plain)
                }
            } else if let result = recognition.record?.result, recognition.record?.status == .ready {
                Text("已识别 \(result.chessPieces.count) 枚棋子，请校正棋子与先行方")
                    .font(.system(size: 12)).foregroundStyle(Palette.teal)
                ActionButton(title: "导入并校正", icon: "square.and.arrow.down", prominent: true, action: importResult)
            } else {
                if let message = message ?? recognition.record?.message {
                    Text(message).font(.system(size: 12)).foregroundStyle(Palette.red)
                        .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
                if !configured {
                    Text("先配置识别服务，再选择图片进行识别").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    ActionButton(title: "配置识别服务", icon: "gearshape", prominent: true) { showingSettings = true }
                    if image == nil { sourceButtons(prominent: false) }
                } else if image == nil {
                    sourceButtons(prominent: true)
                } else {
                    Text("图片将发送至\(serviceTitle)，联网识别可能消耗 API 额度。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading)
                    ActionButton(title: recognition.record?.status == .failed ? "重试识别" : "识别棋盘", icon: "sparkles", prominent: true, action: recognize)
                }
            }
        }.foregroundStyle(Palette.ink)
    }
    private var serviceTitle: String {
        if settings.provider == .deepSeek { return " DeepSeek" }
        return (try? settings.endpoint().host).map { " \($0)" } ?? "自定义服务"
    }
    private func sourceButtons(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            PhotosPicker(selection: $photo, matching: .images) {
                Label(image == nil ? "从相册选择" : "更换图片", systemImage: "photo")
                    .font(.system(size: 14, weight: .medium)).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(prominent ? Color.white : Palette.ink)
                    .background(prominent ? Palette.teal : Palette.card, in: RoundedRectangle(cornerRadius: 13))
            }.buttonStyle(.plain).disabled(busy)
            ActionButton(title: "选择文件", icon: "folder", disabled: busy) { pickingFile = true }
        }
    }
    private func refreshSettings() {
        settings = .saved
        do {
            try settings.validate(key: DeepSeekKeychain.load(for: settings.provider))
            configured = true
        } catch {
            configured = false
            if !(error is ImageImportError) { message = error.localizedDescription }
        }
    }
    private func prepare(_ read: @escaping () async throws -> Data) {
        work?.cancel(); recognition.discard()
        loading = true; message = nil
        work = Task { @MainActor in
            do {
                let data = try await read()
                try Task.checkCancellation()
                image = try RecognitionImage(data: data)
            } catch {
                if !Task.isCancelled { message = error.localizedDescription }
            }
            if !Task.isCancelled { loading = false }
        }
    }
    private func recognize() {
        guard let image, !busy else { return }
        message = nil
        do {
            let key = try DeepSeekKeychain.load(for: settings.provider)
            _ = try recognition.start(jpeg: image.jpeg, key: key, settings: settings)
        } catch { message = error.localizedDescription; refreshSettings() }
    }
    private func importResult() {
        guard scenePhase == .active, let result = recognition.record?.result else { return }
        onImport(result, recognition.imageData ?? image?.jpeg)
        recognition.discard()
        dismiss()
    }
}

struct ImageReviewView: View {
    @Environment(\.dismiss) private var dismiss
    var image: RecognitionImage
    var title: String
    var notes: String? = nil
    @State private var zoom: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.system(size: 17, weight: .semibold)); Spacer()
                Button("完成") { dismiss() }.frame(minWidth: 44, minHeight: 44)
            }.padding(.horizontal, 16)
            GeometryReader { geometry in
                let ratio = CGFloat(image.preview.width) / CGFloat(image.preview.height)
                let width = min(geometry.size.width, geometry.size.height * ratio)
                let scale = min(4, max(1, zoom * magnification))
                ScrollView([.horizontal, .vertical]) {
                    Image(decorative: image.preview, scale: 1).resizable()
                        .frame(width: width * scale, height: width / ratio * scale)
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                        .gesture(MagnificationGesture().updating($magnification) { value, state, _ in state = value }
                            .onEnded { zoom = min(4, max(1, zoom * $0)) })
                        .onTapGesture(count: 2) { withAnimation { zoom = zoom > 1 ? 1 : 2 } }
                        .accessibilityLabel("原图，双击或捏合缩放")
                }
            }
            if let notes, !notes.isEmpty {
                Text(notes).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
            }
        }.foregroundStyle(Palette.ink).background(Palette.paper).tint(Palette.teal)
            .frame(minWidth: 320, idealWidth: 430, minHeight: 450, idealHeight: 820)
            #if os(iOS)
            .presentationDetents([.large])
            #endif
    }
}
