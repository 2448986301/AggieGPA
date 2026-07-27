import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    let existingPreferences: UserPreferences?

    @State private var page = 0
    @State private var name = ""
    @State private var major = "Biological Sciences"
    @State private var academicYear = "2026–2027"
    @State private var targetGPA = "3.50"
    @State private var loadDemoData = false

    private let pages: [(String, LocalizedStringKey, LocalizedStringKey)] = [
        ("calendar.badge.checkmark", "Track every quarter", "Record courses, units, grades, and GPA trends in one place."),
        ("wand.and.stars", "Plan before grades arrive", "Use What-If scenarios and target calculations without changing official records."),
        ("iphone.gen3.radiowaves.left.and.right", "Your data stays on this iPhone", "No account, no ads, no server, and no tracking.")
    ]

    var body: some View {
        ZStack {
            CampusBackground()
            VStack(spacing: DesignSystem.Spacing.large) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        onboardingPage(pages[index]).tag(index)
                    }
                    setupPage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button(page < 3 ? "Continue" : "Start using Aggie GPA") {
                    if page < 3 {
                        withAnimation(DesignSystem.Motion.spring) { page += 1 }
                    } else {
                        finish()
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .accessibilityIdentifier(page < 3 ? "onboardingContinue" : "onboardingFinish")

                DisclaimerBanner()
            }
            .padding(DesignSystem.Spacing.large)
        }
    }

    private func onboardingPage(_ item: (String, LocalizedStringKey, LocalizedStringKey)) -> some View {
        VStack(spacing: DesignSystem.Spacing.large) {
            Spacer()
            Image(systemName: item.0)
                .font(.system(size: 62, weight: .semibold))
                .foregroundStyle(DesignSystem.ColorToken.gold)
                .symbolEffect(.breathe, isActive: page < 3)
                .accessibilityHidden(true)
            Text(item.1)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(item.2)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.bottom, 30)
    }

    private var setupPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                Text("Make it yours")
                    .font(.largeTitle.bold())
                TextField("Name or nickname (optional)", text: $name)
                    .textContentType(.nickname)
                TextField("Major", text: $major)
                TextField("Starting academic year", text: $academicYear)
                TextField("Target GPA", text: $targetGPA)
                    .keyboardType(.decimalPad)
                Toggle("Load clearly labeled demo data", isOn: $loadDemoData)
                Label("You can enable Face ID later in Settings.", systemImage: "faceid")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .padding(DesignSystem.Spacing.large)
            .contentSurface()
            .padding(.vertical, DesignSystem.Spacing.xLarge)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func finish() {
        let preference = existingPreferences ?? UserPreferences()
        if existingPreferences == nil { modelContext.insert(preference) }
        preference.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        preference.major = major.isEmpty ? "Biological Sciences" : major
        preference.firstAcademicYear = academicYear.isEmpty ? "2026–2027" : academicYear
        if let target = DecimalFormatters.decimal(from: targetGPA), InputValidator.validGPA(target) {
            preference.targetGPA = target
        }
        preference.onboardingCompleted = true
        if loadDemoData { DemoDataService.load(into: modelContext, preferences: preference) }
        try? modelContext.save()
    }
}
