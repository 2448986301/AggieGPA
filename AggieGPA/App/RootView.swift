import SwiftData
import SwiftUI

struct RootView: View {
    let storeErrorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PrivacyLockService.self) private var privacyLock
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @Query private var courses: [CourseRecord]
    @State private var notificationCourse: CourseRecord?
    @State private var pendingSiriDraft: SiriDraftPayload?

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
            if let storeErrorMessage {
                StoreRecoveryView(message: storeErrorMessage)
            } else if let preference, preference.onboardingCompleted {
                MainTabView(preferences: preference)
            } else {
                OnboardingView(existingPreferences: preference)
            }
        }
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, preference?.language.locale ?? .autoupdatingCurrent)
        .task { bootstrapScreenshotModeIfNeeded(); handlePendingIntentNavigation() }
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
                handlePendingIntentNavigation()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGradeItemFromNotification)) { notification in
            guard let rawID = notification.object as? String, let id = UUID(uuidString: rawID) else { return }
            notificationCourse = courses.first { $0.id == id }
        }
        .sheet(item: $notificationCourse) { course in
            if let preference {
                NavigationStack { CourseDetailView(course: course, preferences: preference) }
            }
        }
        .sheet(item: $pendingSiriDraft) { draft in
            SiriDraftConfirmationView(draft: draft)
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

    private func handlePendingIntentNavigation() {
        if let rawID = UserDefaults.standard.string(forKey: "pendingOpenCourseID"), let id = UUID(uuidString: rawID) {
            notificationCourse = courses.first { $0.id == id }
            UserDefaults.standard.removeObject(forKey: "pendingOpenCourseID")
        }
        if pendingSiriDraft == nil { pendingSiriDraft = PendingSiriDraftStore.take() }
    }
}

private struct StoreRecoveryView: View {
    let message: String

    var body: some View {
        ZStack {
            CampusBackground()
            VStack(spacing: DesignSystem.Spacing.large) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(DesignSystem.ColorToken.gold)
                Text("Your data needs attention")
                    .font(.title2.bold())
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(DesignSystem.Spacing.xLarge)
        }
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
