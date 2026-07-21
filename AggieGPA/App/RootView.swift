import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PrivacyLockService.self) private var privacyLock
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]

    private var preference: UserPreferences? { preferences.first }
    private var preferredColorScheme: ColorScheme? {
        switch preference?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var body: some View {
        Group {
            if let preference, preference.onboardingCompleted {
                MainTabView(preferences: preference)
            } else {
                OnboardingView(existingPreferences: preference)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, preference?.language.locale ?? .autoupdatingCurrent)
        .task { bootstrapScreenshotModeIfNeeded() }
        .overlay {
            if privacyLock.isLocked {
                PrivacyLockView()
                    .transition(.opacity)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                privacyLock.prepareForBackground()
            case .active:
                Task { await privacyLock.handleForeground(preferences: preference) }
            default:
                break
            }
        }
    }

    private func bootstrapScreenshotModeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-demo"), preferences.isEmpty else { return }
        let preference = UserPreferences(displayName: "Alex", appearance: arguments.contains("--screenshot-dark") ? .dark : .light,
                                         language: arguments.contains("--screenshot-chinese") ? .simplifiedChinese : .english,
                                         onboardingCompleted: true)
        modelContext.insert(preference)
        DemoDataService.load(into: modelContext, preferences: preference)
    }
}

private struct PrivacyLockView: View {
    @Environment(PrivacyLockService.self) private var privacyLock

    var body: some View {
        ZStack {
            CampusBackground()
            VStack(spacing: DesignSystem.Spacing.large) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(DesignSystem.ColorToken.gold)
                    .accessibilityHidden(true)
                Text("Aggie GPA is locked")
                    .font(.title2.bold())
                Text(LocalizedStringKey(privacyLock.errorMessage ?? "Authenticate to view your GPA records."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Unlock") {
                    Task { await privacyLock.authenticate() }
                }
                .buttonStyle(.glassProminent)
                .accessibilityIdentifier("unlockButton")
            }
            .padding(DesignSystem.Spacing.xLarge)
        }
    }
}
