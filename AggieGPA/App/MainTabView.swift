import SwiftUI

struct MainTabView: View {
    @Environment(\.locale) private var locale
    let preferences: UserPreferences
    @State private var selection: AppTab
    @State private var siriSearchQuery = ""

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
                QuartersView(preferences: preferences, initialSearchQuery: siriSearchQuery)
            }
            Tab("GPA", systemImage: "chart.line.uptrend.xyaxis", value: .planner) {
                PlannerView(preferences: preferences)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                SettingsView(preferences: preferences)
            }
        }
        .tint(DesignSystem.ColorToken.gold)
        .id(locale.identifier)
        .onReceive(NotificationCenter.default.publisher(for: .openGPAForecastFromSiri)) { _ in
            selection = .planner
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSearchFromSiri)) { notification in
            openSearch(notification.object as? String)
        }
        .task {
            guard let route = PendingSiriNavigationStore.peek(), route.kind == .search else { return }
            openSearch(route.query)
        }
    }

    private func openSearch(_ query: String?) {
        siriSearchQuery = query ?? ""
        selection = .quarters
        PendingSiriNavigationStore.clear()
    }
}

extension Notification.Name {
    static let openGPAForecastFromSiri = Notification.Name("openGPAForecastFromSiri")
    nonisolated static let openSearchFromSiri = Notification.Name("openSearchFromSiri")
}

private enum AppTab: String, Hashable {
    case dashboard
    case quarters
    case planner
    case settings
}
