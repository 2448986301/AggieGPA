import SwiftUI

/// The single user-facing source for release notes. Keep claims constrained to
/// completed, documented work; technical evidence remains in `docs/v1.2`.
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

    static var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionAndBuild: String {
        "\(currentVersion) (Build \(currentBuild))"
    }

    static let releases: [AppVersionRelease] = [
        AppVersionRelease(
            version: "1.3.0",
            status: "Current Version",
            summary: "Reviewable on-device syllabus understanding, with clearer evidence and control.",
            highlights: [
                "On-device AI reads syllabus text and scanned pages without OCR",
                "Clearer grading categories, weights, assessments, and special rules",
                "Page evidence and review flags for every uncertain result",
                "Nothing changes course data until you choose Confirm Import",
                "Improved English and Simplified Chinese syllabus-import guidance"
            ]
        ),
        AppVersionRelease(
            version: "1.2.0",
            status: "Unreleased development version",
            summary: "A calmer, more consistent way to track your grades.",
            highlights: [
                "A unified Apple-inspired design system",
                "Clearer Today, Courses, and Course Detail experiences",
                "Simpler assignment, exam, and score-entry flows",
                "Clearer official and estimated GPA",
                "Improved English, Simplified Chinese, and accessibility support"
            ]
        ),
        AppVersionRelease(
            version: "1.1.2",
            status: "Documented development version",
            summary: "Privacy-controlled Siri access and course search improvements.",
            highlights: [
                "Optional Siri access controls for private GPA data",
                "Confirmed drafts before Siri writes any grades",
                "Spotlight indexing for courses"
            ]
        ),
        AppVersionRelease(
            version: "1.1.1",
            status: "Documented development checkpoint",
            summary: "A more reachable student-first grade workflow.",
            highlights: [
                "Easier first-term and course-grade setup",
                "Clearer Today, global add, and course-detail flow",
                "Ungraded work stays out of current-grade calculations"
            ]
        ),
        AppVersionRelease(
            version: "1.1.0",
            status: "Documented development version",
            summary: "Detailed course-grade tracking and safer planning tools.",
            highlights: [
                "Weighted categories, assignments, exams, and score entry",
                "Forecasts, targets, syllabus import, and local reminders",
                "Safer data migration and backup recovery"
            ]
        ),
        AppVersionRelease(
            version: "1.0",
            status: "Documented baseline",
            summary: "The offline GPA planner foundation.",
            highlights: [
                "Terms, courses, official GPA, and planning tools",
                "Local backup, privacy lock, and bilingual support"
            ]
        )
    ]

    static var currentRelease: AppVersionRelease? {
        releases.first { $0.version == currentVersion }
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section("Aggie GPA") {
                Text("Version \(AppVersionHistory.currentVersion) (Build \(AppVersionHistory.currentBuild))")
                    .accessibilityIdentifier("appVersion")
                NavigationLink("What’s New") { VersionHistoryView() }
                    .accessibilityIdentifier("whatsNewLink")
            }
            Section("About") {
                NavigationLink("Privacy") { InformationPage(title: "Privacy", text: "Privacy details") }
                NavigationLink("GPA Rules") { InformationPage(title: "GPA Rules", text: "GPA rules details") }
                NavigationLink("Disclaimer") { InformationPage(title: "Disclaimer", text: "Disclaimer details") }
            }
            Section { DisclaimerBanner() }
        }
        .navigationTitle("About")
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

            Section("Version History") {
                ForEach(AppVersionHistory.releases.filter { $0.version != AppVersionHistory.currentVersion }) { release in
                    DisclosureGroup {
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
        }
        .navigationTitle("What’s New")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("versionHistoryView")
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
    let markSeen: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    if let current = AppVersionHistory.currentRelease {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                            Text(current.version)
                                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                .accessibilityLabel("Version \(current.version)")
                            Text(current.status)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(current.summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .padding(.top, DesignSystem.Spacing.xSmall)
                        }

                        Divider()

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
