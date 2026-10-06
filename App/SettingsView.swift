import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: RecognitionSettings
    @State private var deepSeekKey = ""
    @State private var customKey = ""
    @State private var savedKeys = Set<RecognitionProvider>()
    @State private var message: String?

    init(settings: RecognitionSettings = .saved) { _settings = State(initialValue: settings) }
    private var key: Binding<String> { settings.provider == .deepSeek ? $deepSeekKey : $customKey }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                Spacer()
                Button("取消") { dismiss() }.foregroundStyle(Palette.muted)
            }.buttonStyle(.plain).padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 23)).foregroundStyle(Palette.teal)
                                .frame(width: 46, height: 46).background(Palette.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("图片识别").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                Text("从棋盘截图，开始一局研究。")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                        }
                        Picker("识别服务", selection: $settings.provider) {
                            ForEach(RecognitionProvider.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        if settings.provider == .custom {
                            Divider().overlay(Palette.line)
                            fieldTitle("接口类型")
                            Picker("接口类型", selection: $settings.api) {
                                ForEach(RecognitionAPI.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            fieldTitle("API 地址")
                            input("https://example.com/v1", text: $settings.address)
                            Text("可填基础地址，或以 /chat/completions、/responses 结尾的完整接口地址。")
                                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                            if let endpoint = try? settings.endpoint() {
                                Text("请求地址：\(endpoint.absoluteString)")
                                    .font(.system(size: 11)).foregroundStyle(Palette.teal).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            fieldTitle("模型名称")
                            input("填写服务提供的视觉模型名称", text: $settings.model)
                        }
                        Divider().overlay(Palette.line)
                        fieldTitle(settings.provider == .deepSeek ? "API 密钥" : "API 密钥（可选）")
                        SecureField(settings.provider == .deepSeek ? "粘贴 DeepSeek API 密钥" : "无需鉴权的本地服务可留空", text: key)
                            .textFieldStyle(.plain).font(.system(size: 14)).padding(13)
                            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                        if savedKeys.contains(settings.provider) {
                            Button("删除此服务的密钥", role: .destructive, action: deleteKey)
                                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.red)
                        }
                        Divider().overlay(Palette.line)
                        fieldTitle("识别思考强度")
                        if settings.provider == .deepSeek {
                            Picker("识别思考强度", selection: $settings.deepSeekThinking) {
                                ForEach(RecognitionThinking.allCases) { Text($0.title).tag($0) }
                            }.pickerStyle(.segmented).labelsHidden()
                            Text(settings.deepSeekThinking.detail).font(.system(size: 12)).foregroundStyle(Palette.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Picker("识别思考强度", selection: $settings.customThinking) {
                                Text("服务默认").tag(Optional<RecognitionThinking>.none)
                                ForEach(RecognitionThinking.allCases) { Text($0.title).tag(Optional($0)) }
                            }.pickerStyle(.menu).labelsHidden()
                            Text("默认沿用服务设置。手动指定强度需模型支持标准 reasoning 参数；最高对应 xhigh。")
                                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        }
                    }.cardStyle()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("密钥分别保存在本机钥匙串", systemImage: "lock")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                        Text("仅在点击图片识别时，将所选图片发送给已保存的服务，需要模型支持图片输入和 JSON 输出。棋局保存、推演与皮卡鱼 AI 继续离线使用。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        if settings.provider == .deepSeek {
                            Link("获取 DeepSeek API 密钥", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                        }
                    }.padding(.horizontal, 4)
                }.padding(20).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
            ActionButton(title: "保存设置", icon: "checkmark", prominent: true, action: save).padding(20)
        }.background(Palette.paper).tint(Palette.teal)
        #if os(macOS)
        .frame(minWidth: 390, idealWidth: 430, minHeight: 530, idealHeight: 820)
        #endif
        .onAppear {
            do {
                deepSeekKey = try DeepSeekKeychain.load()
                customKey = try DeepSeekKeychain.load(for: .custom)
                if !deepSeekKey.isEmpty { savedKeys.insert(.deepSeek) }
                if !customKey.isEmpty { savedKeys.insert(.custom) }
            } catch { message = error.localizedDescription }
        }
        .alert("无法保存设置", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }

    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
    }
    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 14)).padding(13)
            .background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
            #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            #endif
    }
    private func save() {
        do {
            settings.address = settings.address.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if settings.provider == .custom { try settings.validate(key: key.wrappedValue) }
            try DeepSeekKeychain.save(key.wrappedValue, for: settings.provider)
            try settings.save()
            dismiss()
        } catch { message = error.localizedDescription }
    }
    private func deleteKey() {
        do {
            try DeepSeekKeychain.save("", for: settings.provider)
            key.wrappedValue = ""
            savedKeys.remove(settings.provider)
        } catch { message = error.localizedDescription }
    }
}
