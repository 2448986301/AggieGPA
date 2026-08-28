import SwiftData
import SwiftUI

private enum AcademicCalendarTypeFilter: String, CaseIterable, Identifiable {
    case all
    case assignments
    case quizzes
    case labs
    case exams

    var id: String { rawValue }

    func title(locale: Locale) -> String {
        switch self {
        case .all: AppLocalization.string("All Types", locale: locale)
        case .assignments: AppLocalization.string("Assignments", locale: locale)
        case .quizzes: AppLocalization.string("Quizzes", locale: locale)
        case .labs: AppLocalization.string("Labs", locale: locale)
        case .exams: AppLocalization.string("Exams", locale: locale)
        }
    }

    func includes(_ type: GradeCategoryType) -> Bool {
        switch self {
        case .all:
            true
        case .assignments:
            type == .homework || type == .project || type == .presentation
        case .quizzes:
            type == .quiz
        case .labs:
            type == .lab
        case .exams:
            type == .midterm || type == .finalExam
        }
    }
}

struct AcademicCalendarView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query(sort: \CourseRecord.updatedAt, order: .reverse) private var courses: [CourseRecord]
    @Query(sort: \GradingCategory.updatedAt, order: .reverse) private var categories: [GradingCategory]
    @Query(sort: \GradeItem.updatedAt, order: .reverse) private var items: [GradeItem]

    let preferences: UserPreferences
    @State private var selectedTermID: UUID?
    @State private var selectedCourseID: UUID?
    @State private var selectedMonth = Date()
    @State private var selectedDay: Date?
    @State private var typeFilter = AcademicCalendarTypeFilter.all
    @State private var preparedCalendarItems: [AcademicCalendarItemSnapshot] = []
    @State private var preparedCalendarSignature: String?
    @State private var preparedMonthSummaries: [AcademicCalendarDaySummary] = []

    private let coursePalette: [Color] = [
        .blue, .purple, .orange, .green, .pink, .teal, DesignSystem.ColorToken.gold
    ]

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }

    private var liveTerms: [AcademicTerm] {
        terms.filter { !$0.isDeleted }
    }

    private var selectedTerm: AcademicTerm? {
        liveTerms.first { $0.id == selectedTermID } ?? liveTerms.last
    }

    private var termCourses: [CourseRecord] {
        guard let selectedTerm else { return [] }
        return courses
            .filter { !$0.isDeleted && $0.term?.persistentModelID == selectedTerm.persistentModelID }
            .sorted { $0.courseCode.localizedStandardCompare($1.courseCode) == .orderedAscending }
    }

    /// A scalar trigger for snapshot preparation. SwiftData models never leave the main
    /// actor; the detached task receives only immutable value inputs.
    private var calendarDataSignature: String {
        let selectedTermID = selectedTerm?.id.uuidString ?? "none"
        let liveTermCourses = courses.filter {
            !$0.isDeleted && $0.term?.persistentModelID == selectedTerm?.persistentModelID
        }
        let latestCourseUpdate = liveTermCourses.map(\.updatedAt).max()?.timeIntervalSinceReferenceDate ?? 0
        let latestItemUpdate = items.first?.updatedAt.timeIntervalSinceReferenceDate ?? 0
        let latestCategoryUpdate = categories.first?.updatedAt.timeIntervalSinceReferenceDate ?? 0
        return "\(selectedTermID)|c\(liveTermCourses.count)-\(latestCourseUpdate)|i\(items.count)-\(latestItemUpdate)|g\(categories.count)-\(latestCategoryUpdate)"
    }

    private var isCalendarReady: Bool {
        preparedCalendarSignature == calendarDataSignature
    }

    private var allowedMonthStarts: [Date] {
        guard let start = selectedTerm?.startDate,
              let end = selectedTerm?.endDate,
              end >= start else { return [] }
        let first = AcademicCalendarEngine.monthStart(for: start, calendar: calendar)
        let last = AcademicCalendarEngine.monthStart(for: end, calendar: calendar)
        var months: [Date] = []
        var cursor = first
        while cursor <= last, months.count < 24 {
            months.append(cursor)
            guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
            cursor = next
        }
        return months
    }

    private var effectiveMonth: Date {
        guard !allowedMonthStarts.isEmpty else {
            return AcademicCalendarEngine.monthStart(for: selectedMonth, calendar: calendar)
        }
        if let matching = allowedMonthStarts.first(where: {
            calendar.isDate($0, equalTo: selectedMonth, toGranularity: .month)
        }) {
            return matching
        }
        return allowedMonthStarts.min {
            abs($0.timeIntervalSince(selectedMonth)) < abs($1.timeIntervalSince(selectedMonth))
        } ?? allowedMonthStarts[0]
    }

    private var calendarItems: [AcademicCalendarItemSnapshot] {
        preparedCalendarItems
    }

    private var filteredItems: [AcademicCalendarItemSnapshot] {
        calendarItems.filter { item in
            (selectedCourseID == nil || item.courseID == selectedCourseID)
                && typeFilter.includes(item.categoryType)
        }
    }

    private var monthGrid: [Date] {
        AcademicCalendarEngine.monthGrid(for: effectiveMonth, calendar: calendar)
    }

    private var monthDays: [Date] {
        monthGrid.filter { calendar.isDate($0, equalTo: effectiveMonth, toGranularity: .month) }
    }

    private var monthSummaries: [AcademicCalendarDaySummary] {
        preparedMonthSummaries
    }

    private var selectedDayValue: Date {
        if let selectedDay,
           monthSummaries.contains(where: { calendar.isDate($0.date, inSameDayAs: selectedDay) }) {
            return selectedDay
        }
        return monthSummaries.first(where: { !$0.items.isEmpty })?.date ?? monthDays.first ?? effectiveMonth
    }

    private var selectedDaySummary: AcademicCalendarDaySummary {
        monthSummaries.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDayValue) })
            ?? AcademicCalendarEngine.daySummary(for: selectedDayValue, items: filteredItems, calendar: calendar)
    }

    private var monthItemCount: Int {
        monthSummaries.reduce(0) { $0 + $1.itemCount }
    }

    private var monthExamCount: Int {
        monthSummaries.reduce(0) { $0 + $1.examCount }
    }

    private var monthWeight: Decimal {
        monthSummaries.reduce(Decimal.zero) { $0 + $1.assessmentWeight }
    }

    private var busiestDay: AcademicCalendarDaySummary? {
        AcademicCalendarEngine.busiestDay(in: monthSummaries)
    }

    var body: some View {
        Group {
            if liveTerms.isEmpty {
                ContentUnavailableView(
                    "No semester yet",
                    systemImage: "calendar",
                    description: Text("Add a term and dated assignments to build your academic calendar.")
                )
            } else if selectedTerm?.startDate == nil || selectedTerm?.endDate == nil {
                ContentUnavailableView {
                    Label("Set Semester Dates", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Add the semester start and end dates before building its academic calendar.")
                }
            } else {
                ScrollView {
                    Group {
                        if !isCalendarReady {
                            calendarPreparingView
                        } else if horizontalSizeClass == .regular {
                            iPadCalendarContent
                        } else {
                            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                                loadSummary
                                filters
                                monthControls
                                monthGridSection
                                selectedDaySection
                            }
                        }
                    }
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .padding(DesignSystem.Spacing.medium)
                }
                .safeAreaPadding(.bottom, horizontalSizeClass == .compact ? 96 : DesignSystem.Spacing.large)
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle(Text(verbatim: AppLocalization.string("Academic Calendar", locale: locale)))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: liveTerms.map(\.id), initial: true) { _, ids in
            if selectedTermID == nil || !ids.contains(selectedTermID!) {
                selectedTermID = liveTerms.last?.id
            }
        }
        .onChange(of: selectedTermID) { _, _ in
            selectedCourseID = nil
            selectedDay = nil
            selectedMonth = preferredInitialMonth
            rebuildMonthSummaries()
        }
        .onChange(of: selectedCourseID) { _, _ in
            selectedDay = nil
            rebuildMonthSummaries()
        }
        .onChange(of: typeFilter) { _, _ in
            selectedDay = nil
            rebuildMonthSummaries()
        }
        .onChange(of: selectedMonth) { _, _ in rebuildMonthSummaries() }
        .task(id: calendarDataSignature) {
            await prepareCalendarSnapshot(for: calendarDataSignature)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Today", systemImage: "arrow.uturn.backward.circle") {
                    goToNearestTermMonth()
                }
                .accessibilityIdentifier("academicCalendarToday")
            }
        }
    }

    @MainActor
    private func prepareCalendarSnapshot(for signature: String) async {
        guard let selectedTerm else { return }
        guard !isCalendarReady else { return }

        let selectedTermModelID = selectedTerm.persistentModelID
        let selectedCourseModels = courses.filter {
            !$0.isDeleted && $0.term?.persistentModelID == selectedTermModelID
        }
        let selectedCourseIDs = Set(selectedCourseModels.map(\.id))
        let courseInputs = selectedCourseModels
            .sorted { $0.courseCode.localizedStandardCompare($1.courseCode) == .orderedAscending }
            .map { course in
                AcademicCalendarCourseInput(
                    id: course.id,
                    courseCode: course.courseCode,
                    courseTitle: course.courseTitle,
                    courseColorIndex: AcademicCalendarEngine.stableColorIndex(
                        seed: course.id,
                        paletteCount: coursePalette.count
                    )
                )
            }
        let categoryInputs = categories.map { category in
            AcademicCalendarCategoryInput(
                id: category.id,
                name: category.name,
                categoryType: category.categoryType,
                weight: category.weight,
                calculationMode: category.calculationMode
            )
        }
        let itemInputs = items.compactMap { item -> AcademicCalendarGradeItemInput? in
            guard let courseID = item.course?.id, selectedCourseIDs.contains(courseID) else { return nil }
            return AcademicCalendarGradeItemInput(
                id: item.id,
                courseID: courseID,
                categoryID: item.category?.id,
                title: item.title,
                dueDate: item.dueDate,
                earnedPoints: item.earnedPoints,
                percentageOverride: item.percentageOverride,
                possiblePoints: item.possiblePoints,
                multiplier: item.multiplier,
                status: item.status,
                isIncluded: item.isIncluded,
                isDropped: item.isDropped,
                isExcused: item.isExcused,
                isDeleted: item.isDeleted,
                isExtraCredit: item.isExtraCredit
            )
        }
        let otherCategoryName = AppLocalization.string("Other", locale: locale)

        let snapshots = await Task.detached(priority: .userInitiated) {
            AcademicCalendarEngine.makeItemSnapshots(
                courses: courseInputs,
                categories: categoryInputs,
                items: itemInputs,
                otherCategoryName: otherCategoryName
            )
        }.value

        guard !Task.isCancelled else { return }
        preparedCalendarItems = snapshots
        preparedCalendarSignature = signature
        rebuildMonthSummaries()
    }

    @MainActor
    private func rebuildMonthSummaries() {
        guard preparedCalendarSignature != nil else {
            preparedMonthSummaries = []
            return
        }
        preparedMonthSummaries = AcademicCalendarEngine.daySummaries(
            for: monthDays,
            items: filteredItems,
            calendar: calendar
        )
    }

    /// Keep the calendar itself as the anchored left card and let the selected
    /// day's reading list breathe on the right. The two columns remain aligned
    /// at the top so an iPad never presents a lone card floating beside a large
    /// empty surface.
    private var iPadCalendarContent: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.xLarge) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                loadSummary
                filters
                monthControls
                monthGridSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                selectedDayOpenSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var calendarPreparingView: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            Text(verbatim: AppLocalization.string("Academic Calendar", locale: locale))
                .font(.title2.bold())
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: AppLocalization.string("Preparing your calendar…", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .accessibilityIdentifier("academicCalendarPreparing")
    }

    private var preferredInitialMonth: Date {
        guard let first = allowedMonthStarts.first, let last = allowedMonthStarts.last else {
            return AcademicCalendarEngine.monthStart(for: .now, calendar: calendar)
        }
        let nowMonth = AcademicCalendarEngine.monthStart(for: .now, calendar: calendar)
        if nowMonth < first { return first }
        if nowMonth > last { return last }
        return nowMonth
    }

    private var loadSummary: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: AppLocalization.string("Academic Load", locale: locale))
                            .font(.title2.bold())
                        Text(verbatim: selectedTerm.map { AppCopy.termName($0, locale: locale) } ?? "")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: DesignSystem.Spacing.medium)
                    Text(monthTitle)
                        .font(.headline)
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: AppLocalization.string("Academic Load", locale: locale))
                        .font(.title2.bold())
                    Text(verbatim: selectedTerm.map { AppCopy.termName($0, locale: locale) } ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(monthTitle)
                        .font(.headline)
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: DesignSystem.Spacing.medium) {
                    loadMetric(
                        title: AppLocalization.string("Deadlines", locale: locale),
                        value: String(monthItemCount),
                        identifier: "academicCalendarDeadlineMetric"
                    )
                    loadMetric(
                        title: AppLocalization.string("Exams", locale: locale),
                        value: String(monthExamCount),
                        identifier: "academicCalendarExamMetric"
                    )
                    loadMetric(
                        title: AppLocalization.string("Assessment weight", locale: locale),
                        value: percent(monthWeight),
                        identifier: "academicCalendarWeightMetric"
                    )
                }
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    loadMetric(
                        title: AppLocalization.string("Deadlines", locale: locale),
                        value: String(monthItemCount),
                        identifier: "academicCalendarDeadlineMetric"
                    )
                    loadMetric(
                        title: AppLocalization.string("Exams", locale: locale),
                        value: String(monthExamCount),
                        identifier: "academicCalendarExamMetric"
                    )
                    loadMetric(
                        title: AppLocalization.string("Assessment weight", locale: locale),
                        value: percent(monthWeight),
                        identifier: "academicCalendarWeightMetric"
                    )
                }
            }

            if let busiestDay {
                Label {
                    Text(verbatim: busiestDayText(busiestDay))
                } icon: {
                    Image(systemName: "chart.bar.fill")
                        .foregroundStyle(DesignSystem.ColorToken.gold)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("academicCalendarBusiestDay")
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        // Preserve metric identifiers from the adaptive ViewThatFits branches.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("academicCalendarLoadSummary")
    }

    private func loadMetric(title: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: value)
                .font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.small) { filterControls }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) { filterControls }
        }
        .accessibilityIdentifier("academicCalendarFilters")
    }

    @ViewBuilder
    private var filterControls: some View {
        Menu {
            Picker("Semester", selection: $selectedTermID) {
                ForEach(liveTerms) { term in
                    Text(verbatim: AppCopy.termName(term, locale: locale)).tag(Optional(term.id))
                }
            }
        } label: {
            filterLabel(
                selectedTerm.map { AppCopy.termName($0, locale: locale) }
                    ?? AppLocalization.string("Semester", locale: locale),
                systemImage: "calendar"
            )
        }

        Menu {
            Picker("Course", selection: $selectedCourseID) {
                Text(verbatim: AppLocalization.string("All Courses", locale: locale)).tag(nil as UUID?)
                ForEach(termCourses) { course in
                    Text(verbatim: course.courseCode).tag(Optional(course.id))
                }
            }
        } label: {
            filterLabel(
                termCourses.first(where: { $0.id == selectedCourseID })?.courseCode
                    ?? AppLocalization.string("All Courses", locale: locale),
                systemImage: "books.vertical"
            )
        }

        Menu {
            Picker("Type", selection: $typeFilter) {
                ForEach(AcademicCalendarTypeFilter.allCases) { filter in
                    Text(verbatim: filter.title(locale: locale)).tag(filter)
                }
            }
        } label: {
            filterLabel(typeFilter.title(locale: locale), systemImage: "line.3.horizontal.decrease")
        }
    }

    private func filterLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.xSmall)
    }

    private var monthControls: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Button("Previous Month", systemImage: "chevron.left") {
                moveMonth(by: -1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass(.regular.interactive()))
            .buttonBorderShape(.circle)
            .disabled(monthIndex <= 0)
            .accessibilityLabel(Text(verbatim: AppLocalization.string("Previous Month", locale: locale)))
            .accessibilityIdentifier("academicCalendarPreviousMonth")

            Text(monthTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("academicCalendarMonthTitle")

            Button("Next Month", systemImage: "chevron.right") {
                moveMonth(by: 1)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass(.regular.interactive()))
            .buttonBorderShape(.circle)
            .disabled(monthIndex >= allowedMonthStarts.count - 1)
            .accessibilityLabel(Text(verbatim: AppLocalization.string("Next Month", locale: locale)))
            .accessibilityIdentifier("academicCalendarNextMonth")
        }
        .frame(minHeight: 44)
    }

    private var monthGridSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AppLocalization.string("Deadline density", locale: locale))
                    .font(DesignSystem.Typography.sectionTitle)
                Spacer(minLength: DesignSystem.Spacing.small)
                Text(verbatim: AppLocalization.string("Assessment weight", locale: locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            weekdayHeader

            let summaries = monthSummaries
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                spacing: 4
            ) {
                ForEach(monthGrid, id: \.self) { date in
                    dayCell(
                        date,
                        summary: summaries.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
                            ?? AcademicCalendarDaySummary(date: date, items: [], assessmentWeight: 0, examCount: 0, completedCount: 0)
                    )
                }
            }

            loadLegend
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        // Keep the month grid as a queryable container while preserving each
        // day button's identifier for UI automation and VoiceOver navigation.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("academicCalendarMonthGrid")
    }

    private var weekdayHeader: some View {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let reordered = (0..<symbols.count).map { index in
            symbols[(calendar.firstWeekday - 1 + index) % symbols.count]
        }
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
            spacing: 4
        ) {
            ForEach(Array(reordered.enumerated()), id: \.offset) { _, symbol in
                Text(verbatim: symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 24)
            }
        }
    }

    private func dayCell(_ date: Date, summary: AcademicCalendarDaySummary) -> some View {
        let isCurrentMonth = calendar.isDate(date, equalTo: effectiveMonth, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDayValue)
        return Button {
            select(date)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(verbatim: calendar.component(.day, from: date).description)
                        .font(.subheadline.weight(isSelected ? .bold : .medium))
                        .foregroundStyle(isCurrentMonth ? .primary : .tertiary)
                    Spacer(minLength: 0)
                    if summary.examCount > 0 {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(DesignSystem.ColorToken.warning)
                    }
                }
                if summary.itemCount > 0 {
                    HStack(spacing: 3) {
                        ForEach(Array(summary.items.prefix(3))) { item in
                            Circle()
                                .fill(courseColor(for: item))
                                .frame(width: 6, height: 6)
                        }
                        if summary.itemCount > 3 {
                            Text("+\(summary.itemCount - 3)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(percent(summary.assessmentWeight))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(summary.loadLevel == .peak ? DesignSystem.ColorToken.warning : .secondary)
                } else {
                    Spacer(minLength: 12)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .topLeading)
            .padding(DesignSystem.Spacing.xSmall)
            .background(
                isSelected
                    ? DesignSystem.ColorToken.gold.opacity(0.20)
                    : (isCurrentMonth ? Color.clear : Color(.tertiarySystemFill).opacity(0.34)),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                        .strokeBorder(DesignSystem.ColorToken.gold.opacity(0.65), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: dateAccessibilityLabel(date, summary: summary)))
        .accessibilityIdentifier("academicCalendarDay-\(dateKey(date))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var loadLegend: some View {
        HStack(spacing: DesignSystem.Spacing.small) {
            Text(verbatim: AppLocalization.string("Load", locale: locale))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach([AcademicLoadLevel.light, .moderate, .heavy, .peak], id: \.self) { level in
                HStack(spacing: 3) {
                    Circle()
                        .fill(loadColor(level))
                        .frame(width: 7, height: 7)
                    Text(loadLabel(level))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var selectedDaySection: some View {
        selectedDayContent
            .padding(DesignSystem.Spacing.medium)
            .contentSurface()
            .accessibilityIdentifier("academicCalendarSelectedDay")
    }

    private var selectedDayOpenSection: some View {
        selectedDayContent
            .accessibilityIdentifier("academicCalendarSelectedDay")
    }

    private var selectedDayContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: AppLocalization.string("Selected Day", locale: locale))
                    .font(DesignSystem.Typography.sectionTitle)
                Spacer(minLength: DesignSystem.Spacing.small)
                Text(selectedDayValue.formatted(.dateTime.month(.abbreviated).day().locale(locale)))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignSystem.ColorToken.gold)
            }

            if selectedDaySummary.items.isEmpty {
                Text(verbatim: AppLocalization.string("No assessments on this day.", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, DesignSystem.Spacing.small)
            } else {
                ForEach(selectedDaySummary.items) { item in
                    calendarItemRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func calendarItemRow(_ item: AcademicCalendarItemSnapshot) -> some View {
        if let course = termCourses.first(where: { $0.id == item.courseID }) {
            NavigationLink {
                CourseDetailView(course: course, preferences: preferences, initialScoringItemID: item.id)
            } label: {
                calendarItemLabel(item)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("academicCalendarItem-\(item.id.uuidString)")
        } else {
            calendarItemLabel(item)
                .accessibilityIdentifier("academicCalendarItem-\(item.id.uuidString)")
        }
    }

    private func calendarItemLabel(_ item: AcademicCalendarItemSnapshot) -> some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(courseColor(for: item))
                .frame(width: 5, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: DesignSystem.Spacing.xSmall) {
                    Text(verbatim: item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Spacer(minLength: DesignSystem.Spacing.small)
                    if item.isExam {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(DesignSystem.ColorToken.warning)
                    }
                }
                HStack(spacing: DesignSystem.Spacing.xSmall) {
                    Text(verbatim: item.courseCode)
                    Text(verbatim: item.categoryName)
                    if item.assessmentWeight > 0 {
                        Text(percent(item.assessmentWeight))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(verbatim: AppLocalization.string(item.status.localizedLabelKey, locale: locale))
                    .font(.caption2)
                    .foregroundStyle(item.isCompleted ? DesignSystem.ColorToken.success : .secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var monthIndex: Int {
        allowedMonthStarts.firstIndex(where: {
            calendar.isDate($0, equalTo: effectiveMonth, toGranularity: .month)
        }) ?? 0
    }

    private var monthTitle: String {
        effectiveMonth.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    private func moveMonth(by offset: Int) {
        let nextIndex = min(max(monthIndex + offset, 0), max(0, allowedMonthStarts.count - 1))
        guard allowedMonthStarts.indices.contains(nextIndex) else { return }
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            selectedMonth = allowedMonthStarts[nextIndex]
            selectedDay = nil
        }
    }

    private func goToNearestTermMonth() {
        withAnimation(DesignSystem.Motion.standard(reduceMotion: reduceMotion)) {
            selectedMonth = preferredInitialMonth
            selectedDay = nil
        }
    }

    private func select(_ date: Date) {
        guard let month = allowedMonthStarts.first(where: {
            calendar.isDate($0, equalTo: date, toGranularity: .month)
        }) else { return }
        withAnimation(DesignSystem.Motion.quick(reduceMotion: reduceMotion)) {
            selectedMonth = month
            selectedDay = calendar.startOfDay(for: date)
        }
    }

    private func courseColor(for item: AcademicCalendarItemSnapshot) -> Color {
        coursePalette[item.courseColorIndex % coursePalette.count]
    }

    private func percent(_ value: Decimal) -> String {
        "\(DecimalFormatters.compact(value))%"
    }

    private func dateKey(_ date: Date) -> String {
        // Accessibility identifiers are an API for UI tests and assistive
        // tooling, so keep them locale-independent even when the visible
        // calendar follows the user's regional date order.
        String(
            format: "%04d-%02d-%02d",
            calendar.component(.year, from: date),
            calendar.component(.month, from: date),
            calendar.component(.day, from: date)
        )
    }

    private func dateAccessibilityLabel(_ date: Date, summary: AcademicCalendarDaySummary) -> String {
        let dateText = date.formatted(.dateTime.weekday(.wide).month(.wide).day().locale(locale))
        if summary.items.isEmpty {
            return "\(dateText), \(AppLocalization.string("No assessments on this day.", locale: locale))"
        }
        return "\(dateText), \(summary.itemCount) \(AppLocalization.string("assessments", locale: locale)), \(summary.examCount) \(AppLocalization.string("exams", locale: locale)), \(percent(summary.assessmentWeight))"
    }

    private func busiestDayText(_ summary: AcademicCalendarDaySummary) -> String {
        let day = summary.date.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        return String(
            format: AppLocalization.string("Busiest day: %@ · %@ assessments · %@ weight", locale: locale),
            day,
            String(summary.itemCount),
            percent(summary.assessmentWeight)
        )
    }

    private func loadColor(_ level: AcademicLoadLevel) -> Color {
        switch level {
        case .light: .green
        case .moderate: DesignSystem.ColorToken.ice
        case .heavy: DesignSystem.ColorToken.gold
        case .peak: DesignSystem.ColorToken.warning
        case .none: .secondary
        }
    }

    private func loadLabel(_ level: AcademicLoadLevel) -> String {
        switch level {
        case .light: AppLocalization.string("Light load", locale: locale)
        case .moderate: AppLocalization.string("Moderate", locale: locale)
        case .heavy: AppLocalization.string("Heavy", locale: locale)
        case .peak: AppLocalization.string("Peak", locale: locale)
        case .none: AppLocalization.string("None", locale: locale)
        }
    }
}
