import UIKit

@MainActor
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func longPress() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
