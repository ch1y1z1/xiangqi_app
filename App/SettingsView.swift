import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var hasSavedKey = false
    @State private var message: String?
    @AppStorage(RecognitionThinking.preferenceKey) private var thinking = RecognitionThinking.defaultValue.rawValue

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.system(size: 20, weight: .semibold, design: .serif)).foregroundStyle(Palette.ink)
                Spacer()
                Button("完成") { dismiss() }.foregroundStyle(Palette.teal)
            }.buttonStyle(.plain).padding(20)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "sparkles").font(.system(size: 23)).foregroundStyle(Palette.teal)
                                .frame(width: 46, height: 46).background(Palette.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                            VStack(alignment: .leading, spacing: 5) {
                                Text("DeepSeek 图片识别").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                                Text("从棋盘截图，开始一局研究。")
                                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                            }
                        }
                        Divider().overlay(Palette.line)
                        Text("识别思考强度").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                        Picker("识别思考强度", selection: $thinking) {
                            ForEach(RecognitionThinking.allCases) { level in Text(level.title).tag(level.rawValue) }
                        }.pickerStyle(.segmented).labelsHidden()
                        Text((RecognitionThinking(rawValue: thinking) ?? .defaultValue).detail)
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        Divider().overlay(Palette.line)
                        Text("API 密钥").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                        SecureField("粘贴 DeepSeek API 密钥", text: $key).textFieldStyle(.plain)
                            .font(.system(size: 14)).padding(13).background(Palette.paper, in: RoundedRectangle(cornerRadius: 10))
                            #if os(iOS)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            #endif
                        ActionButton(title: "保存密钥", icon: "key.fill", prominent: true,
                                     disabled: key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                            do { try DeepSeekKeychain.save(key); dismiss() }
                            catch { message = error.localizedDescription }
                        }
                        if hasSavedKey {
                            Button("删除密钥", role: .destructive) {
                                do { try DeepSeekKeychain.save(""); key = ""; hasSavedKey = false }
                                catch { message = error.localizedDescription }
                            }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.red)
                        }
                    }.cardStyle()
                    VStack(alignment: .leading, spacing: 10) {
                        Label("保存在本机钥匙串", systemImage: "lock").font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                        Text("仅在点击图片识别时，将所选图片发送给 DeepSeek 官方服务，需要联网并消耗 API 额度。棋局保存、推演与皮卡鱼 AI 继续离线使用。")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                        Link("获取 DeepSeek API 密钥", destination: URL(string: "https://platform.deepseek.com/api_keys")!)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.teal)
                    }.padding(.horizontal, 4)
                }.padding(20).frame(maxWidth: 490).frame(maxWidth: .infinity)
            }
        }.background(Palette.paper).tint(Palette.teal)
        #if os(macOS)
        .frame(minWidth: 390, idealWidth: 430, minHeight: 530)
        #endif
        .onAppear {
            do { key = try DeepSeekKeychain.load(); hasSavedKey = !key.isEmpty }
            catch { message = error.localizedDescription }
        }
        .alert("密钥操作失败", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("知道了") { message = nil }
        } message: { Text(message ?? "") }
    }
}
