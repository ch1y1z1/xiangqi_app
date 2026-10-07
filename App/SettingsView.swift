import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings: RecognitionSettings
    @State private var deepSeekKey = ""
    @State private var customKey = ""
    @State private var originalKeys: [RecognitionProvider: String] = [:]
    @State private var pendingRemoval = Set<RecognitionProvider>()
    @State private var message: String?

    init(settings: RecognitionSettings = .saved) { _settings = State(initialValue: settings) }
    private var key: Binding<String> { settings.provider == .deepSeek ? $deepSeekKey : $customKey }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("取消") { dismiss() }.frame(minWidth: 44, minHeight: 44)
                Text("识别设置").font(.system(size: 17, weight: .semibold)).frame(maxWidth: .infinity)
                Color.clear.frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(Palette.ink).padding(.horizontal, 16).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    fieldTitle("识别服务")
                    Picker("识别服务", selection: $settings.provider) {
                        ForEach(RecognitionProvider.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden()
                    if settings.provider == .custom {
                        fieldTitle("接口类型")
                        Picker("接口类型", selection: $settings.api) {
                            ForEach(RecognitionAPI.allCases) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented).labelsHidden()
                        fieldTitle("API 地址")
                        input("https://example.com/v1", text: $settings.address)
                        fieldTitle("模型名称")
                        input("填写视觉模型名称", text: $settings.model)
                    }
                    fieldTitle(settings.provider == .deepSeek ? "API 密钥" : "API 密钥（可选）")
                    SecureField(settings.provider == .deepSeek ? "粘贴 DeepSeek API 密钥" : "无需鉴权的服务可留空", text: key)
                        .textFieldStyle(.plain).font(.system(size: 14)).padding(13)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                        #if os(iOS)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        #endif
                    if !key.wrappedValue.isEmpty {
                        Button("移除此服务的密钥", role: .destructive) {
                            pendingRemoval.insert(settings.provider); key.wrappedValue = ""
                        }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.red).frame(minHeight: 44)
                    } else if pendingRemoval.contains(settings.provider) {
                        Text("保存设置后移除密钥").font(.system(size: 12)).foregroundStyle(Palette.red)
                    }
                    if settings.provider == .deepSeek {
                        Link("获取 DeepSeek API 密钥", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                            .font(.system(size: 12)).frame(minHeight: 44)
                    }
                    DisclosureGroup("高级设置") {
                        VStack(alignment: .leading, spacing: 12) {
                            fieldTitle("识别思考强度")
                            if settings.provider == .deepSeek {
                                Picker("识别思考强度", selection: $settings.deepSeekThinking) {
                                    ForEach(RecognitionThinking.allCases) { Text($0.title).tag($0) }
                                }.pickerStyle(.segmented).labelsHidden()
                                Text(settings.deepSeekThinking.detail)
                            } else {
                                Picker("识别思考强度", selection: $settings.customThinking) {
                                    Text("服务默认").tag(Optional<RecognitionThinking>.none)
                                    ForEach(RecognitionThinking.allCases) { Text($0.title).tag(Optional($0)) }
                                }.pickerStyle(.menu)
                                Text("默认沿用服务设置。手动指定强度需模型支持 reasoning 参数，最高对应 xhigh。")
                                Text("API 地址可填写基础地址或完整的标准接口地址。")
                                if let endpoint = try? settings.endpoint() {
                                    Text("请求地址：\(endpoint.absoluteString)").textSelection(.enabled)
                                }
                            }
                        }.font(.system(size: 12)).foregroundStyle(Palette.muted).padding(.top, 12)
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.system(size: 14)).padding(.vertical, 8)
                    Text("密钥保存在本机钥匙串。仅在点击识别时发送所选图片。")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(16).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
            ActionButton(title: "保存设置", icon: "checkmark", prominent: true, action: save)
                .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: 490)
        }.background(Palette.paper).tint(Palette.teal)
        #if os(macOS)
        .frame(minWidth: 350, idealWidth: 430, minHeight: 530, idealHeight: 820)
        #endif
        .onAppear(perform: loadKeys)
        .alert("设置未保存", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func fieldTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
    }
    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text).textFieldStyle(.plain).font(.system(size: 14)).padding(13)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
            #if os(iOS)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            #endif
    }
    private func loadKeys() {
        for provider in RecognitionProvider.allCases {
            do {
                let value = try DeepSeekKeychain.load(for: provider)
                originalKeys[provider] = value
                if provider == .deepSeek { deepSeekKey = value } else { customKey = value }
            } catch { message = "读取密钥失败：\(error.localizedDescription)" }
        }
    }
    private func save() {
        do {
            settings.address = settings.address.trimmingCharacters(in: .whitespacesAndNewlines)
            settings.model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
            if settings.provider == .custom { try settings.validate(key: key.wrappedValue) }
            for provider in RecognitionProvider.allCases {
                let value = provider == .deepSeek ? deepSeekKey : customKey
                // A failed read must not turn an untouched field into a key deletion.
                let changed = originalKeys[provider].map { $0 != value } ?? (!value.isEmpty || pendingRemoval.contains(provider))
                if changed { try DeepSeekKeychain.save(value, for: provider) }
            }
            try settings.save()
            dismiss()
        } catch { message = error.localizedDescription }
    }
}
