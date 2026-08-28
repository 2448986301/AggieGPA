import SwiftUI

/// Compatibility name retained for old deep links and migrations. Normal
/// navigation uses GPAFullSimulationView, so there is only one reachable GPA
/// simulation implementation.
@available(*, deprecated, message: "Use GPAFullSimulationView")
struct WhatIfView: View {
    let preferences: UserPreferences

    var body: some View {
        GPAFullSimulationView(preferences: preferences)
    }
}
