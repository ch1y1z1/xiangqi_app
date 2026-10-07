import SwiftUI

enum Palette {
    static let paper = Color(hex: 0xF7F3EC)
    static let card = Color(hex: 0xFFFCF7)
    static let ink = Color(hex: 0x292D2C)
    static let muted = Color(hex: 0x68635D)
    static let red = Color(hex: 0xA64035)
    static let teal = Color(hex: 0x386B61)
    static let green = Color(hex: 0x429969)
    static let line = Color(hex: 0xE7DFD2)
    static let wood = Color(hex: 0xE9CE9F)
    static let boardInk = Color(hex: 0x7C5B37)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct Pill: View {
    var title: String
    var color: Color = Palette.muted
    var body: some View {
        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.08), in: Capsule())
    }
}

struct ActionButton: View {
    var title: String
    var icon: String
    var prominent = false
    var disabled = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(prominent ? Color.white : Palette.ink)
                .background(prominent ? Palette.teal : Palette.card, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(prominent ? Color.clear : Palette.line, lineWidth: 1))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1)
    }
}

struct ToolbarTile: View {
    var title: String
    var icon: String
    var prominent = false
    var enabled = true

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 17, weight: .medium))
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(prominent ? Color.white : Palette.teal)
        .background(prominent ? Palette.teal : Palette.card, in: RoundedRectangle(cornerRadius: 11))
        .opacity(enabled ? 1 : 0.4)
        .contentShape(Rectangle())
    }
}

extension View {
    func cardStyle() -> some View {
        self.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.line.opacity(0.8), lineWidth: 1))
    }
    @ViewBuilder func compactNavigation() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}
