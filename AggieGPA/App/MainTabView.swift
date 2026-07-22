import SwiftUI

struct MainTabView: View {
    let preferences: UserPreferences
    @State private var selection: AppTab

    init(preferences: UserPreferences) {
        self.preferences = preferences
        let arguments = ProcessInfo.processInfo.arguments
        let requestedTab = arguments.first(where: { $0.hasPrefix("--screenshot-tab=") })?
            .replacingOccurrences(of: "--screenshot-tab=", with: "")
        _selection = State(initialValue: AppTab(rawValue: requestedTab ?? "") ?? .dashboard)
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: .dashboard) {
                DashboardView(preferences: preferences)
            }
            Tab("Courses", systemImage: "books.vertical", value: .quarters) {
                QuartersView(preferences: preferences)
            }
            Tab("GPA", systemImage: "chart.line.uptrend.xyaxis", value: .planner) {
                PlannerView(preferences: preferences)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(preferences: preferences)
            }
        }
        .tint(DesignSystem.ColorToken.gold)
    }
}

private enum AppTab: String, Hashable {
    case dashboard
    case quarters
    case planner
    case settings
}
