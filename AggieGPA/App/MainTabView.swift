import SwiftUI

struct MainTabView: View {
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
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
        Group {
            // iPad portrait keeps a compact, Music-like top navigation with an
            // expandable system sidebar. The persistent split workspace is reserved
            // for the broader landscape context where all columns remain legible.
            if horizontalSizeClass == .regular && verticalSizeClass == .compact {
                IPadWorkspaceView(preferences: preferences, selection: $selection, siriSearchQuery: $siriSearchQuery)
            } else {
                phoneTabs
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

    private var phoneTabs: some View {
        Group {
            if horizontalSizeClass == .regular {
                tabs.tabViewStyle(.sidebarAdaptable)
            } else {
                tabs
            }
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: .dashboard) {
                DashboardView(preferences: preferences) {
                    selection = .planner
                }
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

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case dashboard
    case quarters
    case planner
    case settings

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self { case .dashboard: "Today"; case .quarters: "Courses"; case .planner: "GPA"; case .settings: "Settings" }
    }
    var symbol: String {
        switch self { case .dashboard: "sun.max"; case .quarters: "books.vertical"; case .planner: "chart.line.uptrend.xyaxis"; case .settings: "gearshape" }
    }
}
