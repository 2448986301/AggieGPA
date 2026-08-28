import Foundation
import SwiftUI

private struct TodayReferenceDateKey: EnvironmentKey {
    static let defaultValue: Date? = nil
}

extension EnvironmentValues {
    /// An optional clock override for deterministic Today previews and snapshots.
    /// The released app leaves this unset and uses the real current date.
    var todayReferenceDate: Date? {
        get { self[TodayReferenceDateKey.self] }
        set { self[TodayReferenceDateKey.self] = newValue }
    }
}
