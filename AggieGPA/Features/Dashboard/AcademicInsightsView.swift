import SwiftData
import SwiftUI

struct AcademicInsightsView: View {
    @Environment(\.locale) private var locale
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var allCourses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]

    let preferences: UserPreferences
    @State private var selectedInsightID: UUID?

    private var courses: [CourseRecord] { allCourses.filter { !$0.isDeleted } }
    private var insights: [AcademicInsight] {
        AcademicInsightsService.makeInsights(
            courses: courses, policies: policies, categories: categories, items: items,
            scales: scales, forecasts: forecasts, locale: locale
        )
    }
    private var selectedInsight: AcademicInsight? {
        insights.first { $0.id == selectedInsightID }
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    insightList(selection: $selectedInsightID)
                } detail: {
                    if let selectedInsight {
                        AcademicInsightDetailView(
                            insight: selectedInsight,
                            course: course(for: selectedInsight),
                            item: item(for: selectedInsight),
                            preferences: preferences
                        )
                    } else {
                        ContentUnavailableView("Select an insight", systemImage: "lightbulb")
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                List {
                    ForEach(insights) { insight in
                        NavigationLink {
                            AcademicInsightDetailView(
                                insight: insight,
                                course: course(for: insight),
                                item: item(for: insight),
                                preferences: preferences
                            )
                        } label: {
                            AcademicInsightRow(insight: insight)
                        }
                        .accessibilityIdentifier("academicInsightRow-\(insight.id.uuidString)")
                    }
                }
                .overlay {
                    if insights.isEmpty {
                        ContentUnavailableView("No academic insights yet", systemImage: "lightbulb", description: Text("Add actual course scores to see deterministic guidance."))
                    }
                }
                .navigationTitle("Academic Insights")
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .onChange(of: insights.map(\.id), initial: true) { _, ids in
            if selectedInsightID == nil || !ids.contains(selectedInsightID!) {
                selectedInsightID = ids.first
            }
        }
    }

    private func insightList(selection: Binding<UUID?>) -> some View {
        List(selection: selection) {
            ForEach(insights) { insight in
                AcademicInsightRow(insight: insight)
                    .tag(insight.id)
            }
        }
        .navigationTitle("Academic Insights")
        .overlay {
            if insights.isEmpty {
                ContentUnavailableView("No academic insights yet", systemImage: "lightbulb", description: Text("Add actual course scores to see deterministic guidance."))
            }
        }
        .navigationSplitViewColumnWidth(min: 300, ideal: 380, max: 480)
    }

    private func course(for insight: AcademicInsight) -> CourseRecord? {
        courses.first { $0.id == insight.courseID }
    }

    private func item(for insight: AcademicInsight) -> GradeItem? {
        guard let itemID = insight.itemID else { return nil }
        return items.first { $0.id == itemID && !$0.isDeleted }
    }
}

/// A dedicated presentation boundary keeps the complete insight flow out of the
/// parent course/dashboard navigation path. This avoids a nested push returning to
/// the wrong tab while still giving iPhone its own navigation stack and iPad its
/// native split layout.
struct AcademicInsightsFlowView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let preferences: UserPreferences

    var body: some View {
        if horizontalSizeClass == .regular {
            AcademicInsightsView(preferences: preferences)
        } else {
            NavigationStack {
                AcademicInsightsView(preferences: preferences)
            }
        }
    }
}

struct AcademicInsightsSummaryView: View {
    let insights: [AcademicInsight]
    let courses: [CourseRecord]
    let items: [GradeItem]
    let preferences: UserPreferences
    var limit: Int = 3
    var usesOuterSurface: Bool = false
    @State private var showAllInsights = false
    @State private var selectedInsight: AcademicInsight?

    private var focusInsight: AcademicInsight? { insights.first }
    private var needsAttention: [AcademicInsight] {
        insights.filter { $0.severity == .urgent || $0.severity == .attention }
    }
    private var opportunities: [AcademicInsight] {
        insights.filter { $0.severity == .informative || $0.severity == .positive }
    }
    private var belowTarget: [AcademicInsight] {
        insights.filter { $0.symbolName == "arrow.down.right" }
    }
    private var remainingInsights: [AcademicInsight] {
        Array(insights.dropFirst().filter { $0.symbolName != "arrow.down.right" }.prefix(max(1, limit - 1)))
    }

    var body: some View {
        Group {
            if usesOuterSurface {
                summaryContent
                    .padding(.vertical, DesignSystem.Spacing.small)
                    .contentSurface()
            } else {
                summaryContent
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("academicInsightsSummary")
        .sheet(isPresented: $showAllInsights) {
            AcademicInsightsFlowView(preferences: preferences)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedInsight) { insight in
            AcademicInsightDetailSheetView(
                insight: insight,
                course: courses.first(where: { $0.id == insight.courseID }),
                item: insight.itemID.flatMap { itemID in items.first(where: { $0.id == itemID }) },
                preferences: preferences
            )
        }
    }

    private var summaryContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            Text("Academic Insights")
                .font(DesignSystem.Typography.sectionTitle)
                .padding(.horizontal, DesignSystem.Spacing.medium)

            if insights.isEmpty {
                Text("No deterministic alerts from the saved course data.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.large) {
                    summaryMetric(value: needsAttention.count, label: "need attention")
                    summaryMetric(value: opportunities.count, label: "opportunities")
                }
                .padding(.horizontal, DesignSystem.Spacing.medium)
                .accessibilityElement(children: .combine)

                if let focusInsight {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                        Text("Focus Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DesignSystem.Spacing.medium)
                        Button {
                            selectedInsight = focusInsight
                        } label: {
                            if usesOuterSurface {
                                AcademicInsightRow(insight: focusInsight, showCourse: false)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, DesignSystem.Spacing.medium)
                            } else {
                                AppCard {
                                    AcademicInsightRow(insight: focusInsight, showCourse: false)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("academicInsightFocusNow")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if belowTarget.count > 1 {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xSmall) {
                        HStack(spacing: 4) {
                            Text(verbatim: "\(belowTarget.count)")
                            Text("categories below target")
                        }
                        .font(.headline)
                        ForEach(belowTarget.prefix(3)) { insight in
                            Text(verbatim: insight.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.vertical, DesignSystem.Spacing.xSmall)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("academicInsightAggregation")
                }

                ForEach(remainingInsights) { insight in
                    Button {
                        selectedInsight = insight
                    } label: {
                        AcademicInsightRow(insight: insight)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .accessibilityIdentifier("academicInsightSummaryRow-\(insight.id.uuidString)")
                }

                Button("View All") { showAllInsights = true }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                .accessibilityIdentifier("academicInsightsSeeAllButton")
            }
        }
    }

    private func summaryMetric(value: Int, label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(DesignSystem.Typography.metric)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AcademicInsightDetailSheetView: View {
    let insight: AcademicInsight
    let course: CourseRecord?
    let item: GradeItem?
    let preferences: UserPreferences

    var body: some View {
        NavigationStack {
            AcademicInsightDetailView(
                insight: insight,
                course: course,
                item: item,
                preferences: preferences
            )
        }
    }
}

private struct AcademicInsightRow: View {
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.locale) private var locale
    let insight: AcademicInsight
    var showCourse = false

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            Image(systemName: insight.symbolName)
                .foregroundStyle(insight.severity.color)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: insight.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if differentiateWithoutColor {
                    Text(insight.severity.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if showCourse {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 44, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text(verbatim: AppLocalization.string("Opens the related course", locale: locale)))
        .accessibilityValue(Text(verbatim: AppLocalization.string(insight.severity.localizationKey, locale: locale)))
    }
}

private struct AcademicInsightDetailView: View {
    let insight: AcademicInsight
    let course: CourseRecord?
    let item: GradeItem?
    let preferences: UserPreferences

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Label(insight.severity.title, systemImage: insight.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(insight.severity.color)
                    Text(verbatim: insight.title)
                        .font(.title2.bold())
                    Text(verbatim: insight.detail)
                        .font(.body)
                }
                .padding(DesignSystem.Spacing.large)
                .contentSurface()

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Label("Calculation Basis", systemImage: "function")
                        .font(.headline)
                    Text(verbatim: insight.calculationBasis)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .padding(DesignSystem.Spacing.medium)
                .contentSurface()

                if let course {
                    NavigationLink {
                        // Opening an insight should land on the gradebook, not
                        // unexpectedly present the score editor. The user can
                        // explicitly choose Record/Edit Score from the item row.
                        CourseDetailView(course: course, preferences: preferences)
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.small) {
                            Image(systemName: item == nil ? "book.closed" : "checklist")
                            VStack(alignment: .leading, spacing: 2) {
                                if item == nil {
                                    Text("Open Course")
                                } else {
                                    Text("Open Assignment")
                                }
                                Text(verbatim: item?.title ?? course.courseCode)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: DesignSystem.Spacing.small)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.glass(.regular.tint(DesignSystem.ColorToken.gold.opacity(0.30)).interactive()))
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
            .padding(DesignSystem.Spacing.medium)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Insight Details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("academicInsightDetail")
    }
}

private extension AcademicInsightSeverity {
    var localizationKey: String {
        switch self {
        case .positive: "Positive"
        case .informative: "Information"
        case .attention: "Review"
        case .urgent: "Time-sensitive"
        }
    }

    var title: LocalizedStringKey {
        LocalizedStringKey(localizationKey)
    }

    var color: Color {
        switch self {
        case .positive: DesignSystem.ColorToken.success
        case .informative: .secondary
        case .attention: DesignSystem.ColorToken.gold
        case .urgent: DesignSystem.ColorToken.warning
        }
    }
}
