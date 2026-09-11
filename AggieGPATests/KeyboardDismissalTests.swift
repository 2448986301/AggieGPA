import XCTest
import UIKit
@testable import AggieGPA

@MainActor
final class KeyboardDismissalTests: XCTestCase {
    func testInstallationDoesNotDelayOrCancelNativeTouches() throws {
        let window = UIWindow()
        KeyboardDismissalCoordinator.install(on: window)
        KeyboardDismissalCoordinator.install(on: window)
        let gestures = window.gestureRecognizers?.filter { $0.name == "AggieGPA.KeyboardDismissal" } ?? []
        XCTAssertEqual(gestures.count, 1)
        let gesture = try XCTUnwrap(gestures.first)
        XCTAssertFalse(gesture.cancelsTouchesInView)
        XCTAssertFalse(gesture.delaysTouchesBegan)
        XCTAssertFalse(gesture.delaysTouchesEnded)
        XCTAssertEqual(gesture.delegate?.gestureRecognizer?(gesture, shouldRecognizeSimultaneouslyWith: UITapGestureRecognizer()), true)
    }

    func testSearchAndControlDescendantsAreNotKeyboardDismissalTargets() {
        for control in [UIButton(), UITextField(), UITextView()] as [UIView] {
            let child = UIView()
            control.addSubview(child)
            XCTAssertTrue(KeyboardDismissalCoordinator.isControlOrEditor(child))
        }
        XCTAssertFalse(KeyboardDismissalCoordinator.isControlOrEditor(UIView()))
        XCTAssertFalse(KeyboardDismissalCoordinator.isControlOrEditor(nil))
    }
}
