import SwiftUI

/// The single user-facing source for the current first-release notes. Keep
/// claims constrained to completed, verified product behavior.
struct AppVersionRelease: Identifiable {
    let version: String
    let status: LocalizedStringKey
    let summary: LocalizedStringKey
    let highlights: [LocalizedStringKey]

    var id: String { version }
}

enum AppVersionHistory {
    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown Version"
    }

    static var displayVersion: String {
        let components = currentVersion.split(separator: ".")
        guard components.count >= 2 else { return currentVersion }
        return components.prefix(2).joined(separator: ".")
    }

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionAndBuild: String {
        "\(displayVersion) (Build \(currentBuild))"
    }

    static let releases: [AppVersionRelease] = [
        AppVersionRelease(
            version: "1.0",
            status: "First Release",
            summary: "The first complete release of Aggie GPA, a native iPhone and iPad academic planning app.",
            highlights: [
                "Weighted categories, assignments, exams, and score entry",
                "Current grades use course work. Final grades replace estimates when the final report arrives.",
                "Forecasts, targets, syllabus import, and local reminders",
                "Added local academic insights based on calculated course data.",
                "Reviewable on-device syllabus understanding, with clearer evidence and control.",
                "Download, switch, or remove local models. Models stay on this device and are never required for the core gradebook.",
                "English and Simplified Chinese are supported. The app uses a local model when available and otherwise shows a deterministic manual fallback.",
                "Local backup, privacy lock, and bilingual support"
            ]
        )
    ]

    static var currentRelease: AppVersionRelease? {
        releases.first { $0.version == displayVersion }
    }
}

struct AboutView: View {
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section("Aggie GPA") {
                Text(AppLocalization.formatted(
                    "Version %@ (Build %@)",
                    locale: locale,
                    AppVersionHistory.displayVersion,
                    AppVersionHistory.currentBuild
                ))
                    .accessibilityIdentifier("appVersion")
                NavigationLink("What’s New") { VersionHistoryView() }
                    .accessibilityIdentifier("whatsNewLink")
            }
            Section("About") {
                NavigationLink("Privacy") { AboutInformationPage.privacy }
                NavigationLink("GPA Rules") { AboutInformationPage.gpaRules }
                NavigationLink("Open Source") { AboutInformationPage.openSource }
                NavigationLink("Disclaimer") { AboutInformationPage.disclaimer }
            }
            Section { DisclaimerBanner() }
        }
        .navigationTitle("About")
    }
}

private struct AboutInformationSection: Identifiable {
    let title: LocalizedStringKey
    let body: LocalizedStringKey

    var id: String { String(describing: title) }
}

private struct AboutInformationPage: View {
    let title: LocalizedStringKey
    let sections: [AboutInformationSection]

    static let privacy = AboutInformationPage(
        title: "Privacy",
        sections: [
            .init(title: "Privacy overview", body: "Your academic records stay on this device. Aggie GPA has no account, advertising, analytics tracking, remote logging, or cloud sync."),
            .init(title: "Backups and device security", body: "You control exported backups. Deleting the app can remove local data, so keep a backup before changing devices. Face ID, Touch ID, and passcode checks are performed by iOS; Aggie GPA never receives biometric information."),
            .init(title: "Syllabus import", body: "Syllabus analysis is performed on device. You review every proposed category, weight, assessment, and rule before anything is written to your course data.")
        ]
    )

    static let gpaRules = AboutInformationPage(
        title: "GPA Rules",
        sections: [
            .init(title: "Grade-point estimates", body: "Aggie GPA uses the UC Davis grade-point scale: A+ and A are both 4.0, and plus/minus grades differ by 0.3 except for A+. P, NP, S, U, I, IP, and NG are excluded from GPA estimates by default."),
            .init(title: "Repeated courses", body: "Undergraduate repeat replacement is estimated for up to 16 units. When a repeated course crosses that limit, Aggie GPA includes both attempts in the estimate and flags the result for review."),
            .init(title: "Verify official records", body: "Calculations are planning estimates, not official academic records. Confirm your transcript, degree progress, and any special program rules with UC Davis or your academic advisor.")
        ]
    )

    static let openSource = AboutInformationPage(
        title: "Open Source",
        sections: [
            .init(title: "Local inference architecture", body: "Aggie GPA keeps optional on-device AI behind a provider boundary. The verified llama.cpp runtime runs on this device; inference begins only when you choose a local model."),
            .init(title: "Local language models", body: "Choose from the available local model sizes in On-Device Intelligence. Models are downloaded only when you request them and remain on this device."),
            .init(title: "Manual access remains available", body: "You can use manual grading setup and local rule recognition without downloading a language model.")
        ]
    )

    static let disclaimer = AboutInformationPage(
        title: "Disclaimer",
        sections: [
            .init(title: "Independent student tool", body: "Aggie GPA is an unofficial student tool and is not affiliated with UC Davis."),
            .init(title: "What this app cannot decide", body: "This app does not determine official academic standing, graduation eligibility, repeat-course notation, transfer credit, major requirements, or Registrar decisions."),
            .init(title: "Keep records current", body: "University policies and program requirements can change. Use Aggie GPA to plan, then verify important decisions with official university records.")
        ]
    )

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    Text(section.body)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct VersionHistoryView: View {
    var body: some View {
        List {
            if let current = AppVersionHistory.currentRelease {
                Section("Current Version") {
                    VersionReleaseContent(release: current, isCurrent: true)
                }
            } else {
                Section("Current Version") {
                    ContentUnavailableView("Release notes unavailable", systemImage: "clock.badge.exclamationmark", description: Text("This app version does not have release notes yet."))
                }
            }

            if AppVersionHistory.releases.count > 1 {
                Section("Version History") {
                    ForEach(AppVersionHistory.releases.dropFirst()) { release in
                        VersionHistoryDisclosureRow(release: release)
                    }
                }
            }
        }
        .navigationTitle("What’s New")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("versionHistoryView")
    }
}

private struct VersionHistoryDisclosureRow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let release: AppVersionRelease
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded },
            set: { newValue in
                withAnimation(reduceMotion ? nil : DesignSystem.Motion.standard) {
                    isExpanded = newValue
                }
            }
        )) {
            VersionReleaseContent(release: release, isCurrent: false)
                .padding(.top, DesignSystem.Spacing.xSmall)
        } label: {
            HStack(spacing: DesignSystem.Spacing.small) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(release.version)")
                        .font(.headline)
                    Text(release.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct VersionReleaseContent: View {
    let release: AppVersionRelease
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Version \(release.version)")
                    .font(.title3.weight(.semibold))
                Spacer(minLength: DesignSystem.Spacing.small)
                if isCurrent {
                    Text(release.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
            }
            Text(release.summary)
                .foregroundStyle(.secondary)
            ForEach(Array(release.highlights.enumerated()), id: \.offset) { _, highlight in
                Label { Text(highlight) } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct WhatsNewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let markSeen: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    if let current = AppVersionHistory.currentRelease {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                            Text(current.version)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .accessibilityLabel(Text(verbatim: AppLocalization.formatted(
                                    "Version %@", locale: locale, current.version
                                )))
                            Text(current.status)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(current.summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, DesignSystem.Spacing.xSmall)
                        }

                        Divider()

                        if !current.highlights.isEmpty {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                Text("Highlights")
                                    .font(.headline)
                                ForEach(Array(current.highlights.prefix(4).enumerated()), id: \.offset) { index, highlight in
                                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                        Label { Text(highlight) } icon: {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(DesignSystem.ColorToken.gold)
                                        }
                                        .font(.body)
                                        if index < current.highlights.prefix(4).count - 1 { Divider() }
                                    }
                                }
                            }
                        }

                        NavigationLink {
                            VersionHistoryView()
                        } label: {
                            Label("View Full Release Notes", systemImage: "clock.arrow.circlepath")
                                .font(.body.weight(.medium))
                        }
                        .padding(.top, DesignSystem.Spacing.small)
                    }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, DesignSystem.Spacing.large)
                .padding(.top, DesignSystem.Spacing.large)
                .padding(.bottom, DesignSystem.Spacing.xLarge)
            }
            .navigationTitle("What’s New")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Get Started") {
                    markSeen()
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, DesignSystem.Spacing.large)
                .padding(.vertical, DesignSystem.Spacing.small)
                .accessibilityIdentifier("whatsNewGetStarted")
            }
        }
        .tint(DesignSystem.ColorToken.gold)
        .interactiveDismissDisabled(false)
        .accessibilityIdentifier("whatsNewSheet")
    }
}
