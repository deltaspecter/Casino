import UIKit

/// Dezentes haptisches Feedback (abschaltbar in den Einstellungen).
@MainActor
enum Haptics {
    static var isEnabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notification = UINotificationFeedbackGenerator()
    private static let selectionGenerator = UISelectionFeedbackGenerator()

    static func tap() { guard isEnabled else { return }; light.impactOccurred() }
    static func card() { guard isEnabled else { return }; light.impactOccurred(intensity: 0.6) }
    static func chip() { guard isEnabled else { return }; rigid.impactOccurred(intensity: 0.7) }
    static func thud() { guard isEnabled else { return }; medium.impactOccurred() }
    static func selection() { guard isEnabled else { return }; selectionGenerator.selectionChanged() }
    static func success() { guard isEnabled else { return }; notification.notificationOccurred(.success) }
    static func warning() { guard isEnabled else { return }; notification.notificationOccurred(.warning) }
    static func error() { guard isEnabled else { return }; notification.notificationOccurred(.error) }
}
