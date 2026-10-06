import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ImageImportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var image: RecognitionImage?
    @State private var pickingFile = false
    @State private var showingSettings = false
    @State private var settings = RecognitionSettings.saved
    @State private var configured = false
    @State private var loading = false
    @State private var recognizing = false
    @State private var message: String?
    @State private var work: Task<Void, Never>?
    var onImport: (RecognizedSetup) -> Void
    private var busy: Bool { loading || recognizing }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("从图片摆棋").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                Spacer()
                Button(recognizing ? "取消识别" : "取消") { work?.cancel(); dismiss() }.foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).padding(20)
            ScrollView {
                VStack(spacing: 18) {
                    if let image {
                        Image(decorative: image.preview, scale: 1).resizable().scaledToFit()
                            .frame(maxHeight: 390).clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("待识别的棋盘图片")
                    } else {
                        VStack(spacing: 14) {
                            Image(systemName: "photo.on.rectangle.angled").font(.system(size: 43, weight: .light)).foregroundStyle(Palette.teal)
                            Text("选一张棋盘截图").font(.system(size: 18, weight: .medium, design: .serif)).foregroundStyle(Palette.ink)
                            Text("完整的棋盘、清楚的棋子，识别更准确。")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        }.frame(maxWidth: .infinity).frame(height: 220).cardStyle()
                    }
                    HStack(spacing: 12) {
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("相册", systemImage: "photo").font(.system(size: 14, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 13))
                                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Palette.line, lineWidth: 1))
                        }.buttonStyle(.plain).disabled(busy)
                        ActionButton(title: "选择文件", icon: "folder", disabled: busy) { pickingFile = true }
                    }.foregroundStyle(Palette.ink)
                    if loading {
                        ProgressView("正在准备图片…").font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Button { showingSettings = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "key")
                            Text(configured ? settings.description : "先配置图片识别服务")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }.font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.teal)
                    }.buttonStyle(.plain).disabled(busy).cardStyle()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("识别后仍可自由调整", systemImage: "square.and.pencil")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                        Text("点击识别会将这张图片发送给\(settings.serviceName)，需要联网；收费服务会消耗 API 额度。识别成功后替换当前摆棋，进入编辑器检查棋子、名称与先行方，再保存残局。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                    if let message {
                        Text(message).font(.system(size: 12)).foregroundStyle(Palette.red)
                            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    }
                }.padding(20).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                if recognizing { ProgressView("\(settings.serviceName)正在识别棋盘…").font(.system(size: 12)).foregroundStyle(Palette.muted) }
                ActionButton(title: recognizing ? "正在识别…" : "识别并导入", icon: "sparkles", prominent: true,
                             disabled: busy || image == nil || !configured, action: recognize)
            }.padding(20).background(Palette.paper)
        }.background(Palette.paper).tint(Palette.teal)
        #if os(macOS)
        .frame(minWidth: 390, idealWidth: 430, minHeight: 650, idealHeight: 820)
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
        .onAppear(perform: refreshSettings)
        .onDisappear { work?.cancel() }
        .interactiveDismissDisabled(recognizing)
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
        work?.cancel()
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
        work?.cancel()
        recognizing = true; message = nil
        work = Task { @MainActor in
            do {
                let configuration = settings
                let key = try DeepSeekKeychain.load(for: configuration.provider)
                let result = try await ImageRecognizer().recognize(jpeg: image.jpeg, key: key, settings: configuration)
                try Task.checkCancellation()
                recognizing = false
                onImport(result)
                dismiss()
            } catch {
                if !Task.isCancelled { recognizing = false; message = error.localizedDescription; refreshSettings() }
            }
        }
    }
}
