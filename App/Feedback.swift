import Foundation
#if os(iOS)
import UIKit
#endif

@MainActor
enum Feedback {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "hapticsEnabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "hapticsEnabled") }
    }
    static func selection() {
        #if os(iOS)
        if enabled { UISelectionFeedbackGenerator().selectionChanged() }
        #endif
    }
    static func move(capture: Bool) {
        #if os(iOS)
        if enabled { UIImpactFeedbackGenerator(style: capture ? .medium : .light).impactOccurred() }
        #endif
    }
    static func invalid() {
        #if os(iOS)
        if enabled { UINotificationFeedbackGenerator().notificationOccurred(.error) }
        #endif
    }
    static func check() {
        #if os(iOS)
        if enabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        #endif
    }
}
