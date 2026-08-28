import AppIntents
import SwiftData
import SwiftUI

struct RootView: View {
    let storeErrorMessage: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PrivacyLockService.self) private var privacyLock
    @Environment(\.modelContext) private var modelContext
    @Query private var preferences: [UserPreferences]
    @Query private var courses: [CourseRecord]
    @Query private var gradeItems: [GradeItem]
    @Query private var siriAccessSettings: [SiriAccessSettings]
    @State private var notificationCourse: CourseRecord?
    @State private var pendingSiriItemID: UUID?
    @State private var pendingSiriDraft: SiriDraftPayload?
    @AppStorage("lastSeenReleaseNotesVersion") private var lastSeenReleaseNotesVersion = ""
    @State private var showWhatsNew = false

    private var preference: UserPreferences? { preferences.first }
    private var preferredColorScheme: ColorScheme? {
        switch preference?.appearance ?? .system {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    private var effectivePreferredColorScheme: ColorScheme? {
        // The activity review route must be deterministic. Do not let a
        // persisted student appearance preference override its explicit
        // light/dark screenshot argument.
        if ProcessInfo.processInfo.arguments.contains("--screenshot-ai-activity") {
            return ProcessInfo.processInfo.arguments.contains("--screenshot-dark") ? .dark : .light
        }
        return preferredColorScheme
    }
    private var siriDataFingerprint: SiriDataFingerprint {
        SiriDataFingerprint(
            courses: courses.map { course in
                SiriCourseFingerprint(
                    id: course.id,
                    code: course.courseCode,
                    title: course.courseTitle,
                    termName: course.term?.displayName,
                    isDeleted: course.isDeleted,
                    updatedAt: course.updatedAt
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            gradeItems: gradeItems.map { item in
                SiriGradeItemFingerprint(
                    id: item.id,
                    courseID: item.course?.id,
                    title: item.title,
                    dueDate: item.dueDate,
                    categoryName: item.category?.name,
                    categoryType: item.category?.categoryType.rawValue,
                    status: item.status.rawValue,
                    isDropped: item.isDropped,
                    isExcused: item.isExcused
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString },
            settings: siriAccessSettings.map { settings in
                SiriSettingsFingerprint(
                    id: settings.id,
                    isEnabled: settings.isSiriAccessEnabled,
                    allowsAssignmentSummaries: settings.allowAssignmentSummaries,
                    allowsDetailedScores: settings.allowDetailedScores,
                    allowsGPAResponses: settings.allowGPAResponses,
                    allowsCreatingDrafts: settings.allowCreatingDrafts
                )
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--screenshot-ai-activity") {
                AcademicAIActivityReviewView()
                    .environment(
                        \.locale,
                        ProcessInfo.processInfo.arguments.contains("--screenshot-chinese")
                            ? Locale(identifier: "zh-Hans")
                            : Locale(identifier: "en")
                    )
            } else if let storeErrorMessage {
                StoreRecoveryView(message: storeErrorMessage)
            } else if let preference, preference.onboardingCompleted {
                MainTabView(preferences: preference)
            } else {
                OnboardingView(existingPreferences: preference)
            }
        }
        // Keep the system scroll-edge treatment available to each feature's
        // native navigation bar.  Hiding it at the root made GPA Overview
        // and Full Simulation fall back to a flat background after scrolling,
        // even though their bars explicitly use iOS 27 material.
        .scrollEdgeEffectHidden(false, for: [.top, .bottom])
        .dismissKeyboardOnOutsideTap()
        .preferredColorScheme(effectivePreferredColorScheme)
        .environment(\.locale, preference?.language.locale ?? .autoupdatingCurrent)
        .task {
            bootstrapScreenshotModeIfNeeded()
            handlePendingIntentNavigation()
        }
        .task(id: preference?.onboardingCompleted) {
            updateReleaseNotesPresentation()
        }
        .task(id: siriDataFingerprint) {
            // Coalesce the group of model notifications emitted by a single save.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            await refreshSiriIntegration()
        }
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
                Task { await AIResourceManager.shared.cancelCurrentInference() }
            case .active:
                Task { await privacyLock.handleForeground(preferences: preference) }
                Task { await AIResourceManager.shared.handleThermalState() }
                handlePendingIntentNavigation()
                refreshSiriSnapshotAndShortcutParameters()
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)) { _ in
            Task { await AIResourceManager.shared.handleThermalState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openGradeItemFromNotification)) { notification in
            guard let rawID = notification.object as? String, let id = UUID(uuidString: rawID) else { return }
            notificationCourse = courses.first { $0.id == id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCourseFromSiri)) { notification in
            guard let rawID = notification.object as? String, let id = UUID(uuidString: rawID) else { return }
            guard let course = courses.first(where: { $0.id == id }) else { return }
            notificationCourse = course
            PendingSiriNavigationStore.clear()
        }
        .onChange(of: courses.map(\.id)) { _, _ in handlePendingIntentNavigation() }
        .sheet(item: $notificationCourse) { course in
            if let preference {
                NavigationStack { CourseDetailView(course: course, preferences: preference, initialItemID: pendingSiriItemID) }
            }
        }
        .sheet(item: $pendingSiriDraft) { draft in
            SiriDraftConfirmationView(draft: draft)
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            lastSeenReleaseNotesVersion = AppVersionHistory.currentVersion
        }) {
            WhatsNewSheet {
                lastSeenReleaseNotesVersion = AppVersionHistory.currentVersion
            }
            .environment(\.locale, preference?.language.locale ?? .autoupdatingCurrent)
        }
    }

    private func bootstrapScreenshotModeIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--screenshot-demo") {
            UserDefaults.standard.set(true, forKey: "showFocusNext")
        }
        guard arguments.contains("--screenshot-demo"), preferences.isEmpty else { return }
        let preference = UserPreferences(displayName: "Alex", appearance: arguments.contains("--screenshot-dark") ? .dark : .light,
                                         language: arguments.contains("--screenshot-chinese") ? .simplifiedChinese : .english,
                                         onboardingCompleted: true)
        modelContext.insert(preference)
        DemoDataService.load(into: modelContext, preferences: preference)
    }

    private func updateReleaseNotesPresentation() {
        let arguments = ProcessInfo.processInfo.arguments
        guard preference?.onboardingCompleted == true else { return }
        if arguments.contains("--screenshot-whats-new") {
            showWhatsNew = true
            return
        }
        guard !arguments.contains("--screenshot-demo"), lastSeenReleaseNotesVersion != AppVersionHistory.currentVersion else { return }
        showWhatsNew = true
    }

    private func refreshSiriSnapshotAndShortcutParameters() {
        SiriSharedSnapshotStore.save(courses: courses, gradeItems: gradeItems, settings: siriAccessSettings.first)
        AggieGPAAppShortcuts.updateAppShortcutParameters()
    }

    private func refreshSiriIntegration() async {
        refreshSiriSnapshotAndShortcutParameters()
        // Spotlight rebuilding walks the full SwiftData graph. It is only
        // useful when the student has enabled Siri access; keeping it behind
        // this gate prevents ordinary saves and navigation from doing hidden
        // indexing work for users who opted out.
        guard siriAccessSettings.first?.isSiriAccessEnabled == true else { return }
        do {
            try await SiriSpotlightIndex.rebuildAll()
            SiriExecutionTrace.record("spotlight-indexed", itemCount: courses.filter { !$0.isDeleted }.count)
        } catch is CancellationError {
            return
        } catch {
            SiriExecutionTrace.record("spotlight-index-failed")
        }
    }

    private func handlePendingIntentNavigation() {
        if let navigation = PendingSiriNavigationStore.peek() {
            switch navigation.kind {
            case .course:
                guard let id = navigation.courseID.flatMap(UUID.init(uuidString:)),
                      let course = courses.first(where: { $0.id == id }) else { return }
                notificationCourse = course
                PendingSiriNavigationStore.clear()
            case .assignment, .exam:
                pendingSiriItemID = navigation.itemID.flatMap(UUID.init(uuidString:))
                guard let course = navigation.courseID.flatMap(UUID.init(uuidString:)).flatMap({ id in courses.first { $0.id == id } }) else { return }
                notificationCourse = course
                PendingSiriNavigationStore.clear()
            case .gpaForecast:
                NotificationCenter.default.post(name: .openGPAForecastFromSiri, object: nil)
                PendingSiriNavigationStore.clear()
            case .search:
                break
            }
        }
        if pendingSiriDraft == nil { pendingSiriDraft = PendingSiriDraftStore.take() }
    }
}

private struct SiriDataFingerprint: Equatable {
    let courses: [SiriCourseFingerprint]
    let gradeItems: [SiriGradeItemFingerprint]
    let settings: [SiriSettingsFingerprint]
}

private struct SiriCourseFingerprint: Equatable {
    let id: UUID
    let code: String
    let title: String
    let termName: String?
    let isDeleted: Bool
    let updatedAt: Date
}

private struct SiriGradeItemFingerprint: Equatable {
    let id: UUID
    let courseID: UUID?
    let title: String
    let dueDate: Date?
    let categoryName: String?
    let categoryType: String?
    let status: String
    let isDropped: Bool
    let isExcused: Bool
}

private struct SiriSettingsFingerprint: Equatable {
    let id: UUID
    let isEnabled: Bool
    let allowsAssignmentSummaries: Bool
    let allowsDetailedScores: Bool
    let allowsGPAResponses: Bool
    let allowsCreatingDrafts: Bool
}

extension Notification.Name {
    nonisolated static let openCourseFromSiri = Notification.Name("openCourseFromSiri")
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
