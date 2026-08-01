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
    @State private var showAllInsights = false
    @State private var selectedInsight: AcademicInsight?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: DesignSystem.Spacing.small) {
                Label("Academic Insights", systemImage: "lightbulb")
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .layoutPriority(1)
                Spacer(minLength: DesignSystem.Spacing.small)
                Button {
                    showAllInsights = true
                } label: {
                    HStack(spacing: 4) {
                        Text("See All")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: false)
                .buttonStyle(.plain)
                .accessibilityIdentifier("academicInsightsSeeAllButton")
            }
            .padding(.horizontal, DesignSystem.Spacing.medium)
            .padding(.top, DesignSystem.Spacing.medium)
            .padding(.bottom, DesignSystem.Spacing.small)

            if insights.isEmpty {
                Text("No deterministic alerts from the saved course data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, DesignSystem.Spacing.medium)
                    .padding(.bottom, DesignSystem.Spacing.medium)
            } else {
                let visibleInsights = Array(insights.prefix(limit))
                ForEach(Array(visibleInsights.enumerated()), id: \.element.id) { index, insight in
                    if let course = courses.first(where: { $0.id == insight.courseID }) {
                        if index > 0 {
                            Divider()
                                .padding(.leading, DesignSystem.Spacing.medium + 24 + DesignSystem.Spacing.small)
                        }
                        Button {
                            selectedInsight = insight
                        } label: {
                            AcademicInsightRow(insight: insight, showCourse: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, DesignSystem.Spacing.medium)
                        .padding(.vertical, DesignSystem.Spacing.small)
                        .accessibilityIdentifier("academicInsightSummaryRow-\(insight.id.uuidString)")
                    }
                }
            }
        }
        .contentSurface(radius: DesignSystem.Radius.section)
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
        .accessibilityHint("Opens the related course")
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
    var title: LocalizedStringKey {
        switch self {
        case .positive: "Positive"
        case .informative: "Information"
        case .attention: "Review"
        case .urgent: "Time-sensitive"
        }
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
