import SwiftUI
import UIKit

/// Installs one window-level tap recognizer for the SwiftUI app. The recognizer
/// ignores text controls and native controls (including their subviews). Taps on
/// section headers, cards, and other non-editable surfaces end editing without
/// delaying or competing with navigation gestures.
///
/// Keeping this at the root avoids subtly different keyboard behavior between
/// forms and sheets and does not require every feature view to know about
/// UIKit. It is also safe for iPad's split view because the recognizer belongs
/// to the scene window, not to a particular column.
extension View {
    func dismissKeyboardOnOutsideTap() -> some View {
        background {
            KeyboardDismissalInstaller()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
    }
}

private struct KeyboardDismissalInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> InstallerView {
        InstallerView()
    }

    func updateUIView(_ uiView: InstallerView, context: Context) {}

    final class InstallerView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let window else { return }
            KeyboardDismissalCoordinator.install(on: window)
        }
    }
}

@MainActor
final class KeyboardDismissalCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissalCoordinator()
    private static let recognizerName = "AggieGPA.KeyboardDismissal"

    static func install(on window: UIWindow) {
        guard window.gestureRecognizers?.contains(where: { $0.name == recognizerName }) != true else {
            return
        }

        let recognizer = UITapGestureRecognizer(target: shared, action: #selector(handleTap(_:)))
        recognizer.name = recognizerName
        recognizer.cancelsTouchesInView = false
        // This convenience gesture must never hold up native tab/row touches.
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = shared
        window.addGestureRecognizer(recognizer)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, let window = recognizer.view as? UIWindow else { return }
        window.endEditing(true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !Self.isControlOrEditor(touch.view)
    }

    static func isControlOrEditor(_ touchedView: UIView?) -> Bool {
        var view = touchedView
        while let current = view {
            if current is UIControl || current is UITextView {
                return true
            }
            view = current.superview
        }
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
