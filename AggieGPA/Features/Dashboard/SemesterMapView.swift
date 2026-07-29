import SwiftData
import SwiftUI

nonisolated enum SemesterMapCalendar {
    static func startOfWeek(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
        return calendar.date(from: components) ?? day
    }

    static func weekStarts(
        termStart: Date?,
        termEnd: Date?,
        calendar: Calendar
    ) -> [Date] {
        guard let termStart, let termEnd, termEnd >= termStart else { return [] }
        let first = startOfWeek(containing: termStart, calendar: calendar)
        let last = startOfWeek(containing: termEnd, calendar: calendar)

        var weeks: [Date] = []
        var cursor = first
        while cursor <= last, weeks.count < 24 {
            weeks.append(cursor)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
            cursor = next
        }
        return weeks
    }
}

private enum SemesterMapTypeFilter: String, CaseIterable, Identifiable {
    case all, assignments, quizzes, labs, exams

    var id: String { rawValue }
    var title: LocalizedStringKey {
        switch self {
        case .all: "All Types"
        case .assignments: "Assignments"
        case .quizzes: "Quizzes"
        case .labs: "Labs"
        case .exams: "Exams"
        }
    }

    func includes(_ type: GradeCategoryType?) -> Bool {
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

struct SemesterMapView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var courses: [CourseRecord]
    @Query private var items: [GradeItem]
    @Query private var categories: [GradingCategory]

    let preferences: UserPreferences
    @State private var selectedTermID: UUID?
    @State private var selectedCourseID: UUID?
    @State private var typeFilter = SemesterMapTypeFilter.all
    @State private var selectedWeekStart: Date?
    @State private var editingItem: GradeItem?
    @State private var editingTerm: AcademicTerm?

    private var calendar: Calendar {
        var calendar = Calendar.autoupdatingCurrent
        calendar.locale = locale
        return calendar
    }
    private var liveTerms: [AcademicTerm] { terms.filter { !$0.isDeleted } }
    private var selectedTerm: AcademicTerm? {
        liveTerms.first { $0.id == selectedTermID } ?? liveTerms.last
    }
    private var termCourses: [CourseRecord] {
        guard let selectedTerm else { return [] }
        return courses
            .filter { !$0.isDeleted && $0.term?.persistentModelID == selectedTerm.persistentModelID }
            .sorted { $0.courseCode < $1.courseCode }
    }
    private var termCourseModelIDs: Set<PersistentIdentifier> {
        Set(termCourses.map(\.persistentModelID))
    }
    private var filteredItems: [GradeItem] {
        items
            .filter { item in
                guard !item.isDeleted,
                      let dueDate = item.dueDate,
                      let course = item.course,
                      termCourseModelIDs.contains(course.persistentModelID),
                      !item.isDropped,
                      !item.isExcused,
                      typeFilter.includes(item.category?.categoryType)
                else { return false }
                guard dueDate <= .distantFuture else { return false }
                return selectedCourseID == nil || course.id == selectedCourseID
            }
            .sorted { ($0.dueDate ?? .distantFuture, $0.title) < ($1.dueDate ?? .distantFuture, $1.title) }
    }
    private var weekStarts: [Date] {
        SemesterMapCalendar.weekStarts(
            termStart: selectedTerm?.startDate,
            termEnd: selectedTerm?.endDate,
            calendar: calendar
        )
    }
    private var currentWeekStart: Date {
        SemesterMapCalendar.startOfWeek(containing: .now, calendar: calendar)
    }
    private var effectiveSelectedWeek: Date {
        guard let selectedWeekStart, weekStarts.contains(where: { calendar.isDate($0, inSameDayAs: selectedWeekStart) })
        else {
            return weekStarts.min(by: {
                abs($0.timeIntervalSince(currentWeekStart)) < abs($1.timeIntervalSince(currentWeekStart))
            }) ?? currentWeekStart
        }
        return selectedWeekStart
    }

    var body: some View {
        Group {
            if liveTerms.isEmpty {
                ContentUnavailableView(
                    "No semester yet",
                    systemImage: "calendar",
                    description: Text("Add a term and dated assignments to build your semester map.")
                )
            } else if selectedTerm?.startDate == nil || selectedTerm?.endDate == nil {
                ContentUnavailableView {
                    Label("Set Semester Dates", systemImage: "calendar.badge.plus")
                } description: {
                    Text("Add the semester start and end dates before building its timeline.")
                } actions: {
                    Button("Set Semester Dates") {
                        editingTerm = selectedTerm
                    }
                    .buttonStyle(.glass(.regular.tint(DesignSystem.ColorToken.gold.opacity(0.24)).interactive()))
                    .buttonBorderShape(.capsule)
                    .fixedSize()
                    .accessibilityIdentifier("setSemesterDatesButton")
                }
                .padding(DesignSystem.Spacing.large)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
                        overview
                        filters
                        if filteredItems.isEmpty {
                            ContentUnavailableView(
                                "No dated work",
                                systemImage: "calendar.badge.exclamationmark",
                                description: Text("Try another filter or add a due date to an assignment or exam.")
                            )
                            .frame(maxWidth: .infinity)
                            .contentSurface()
                        } else if horizontalSizeClass == .regular {
                            expandedTimeline
                        } else {
                            compactTimeline
                        }
                    }
                    .frame(maxWidth: 1_180, alignment: .leading)
                    .padding(DesignSystem.Spacing.medium)
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
            }
        }
        .navigationTitle("Semester Map")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: liveTerms.map(\.id), initial: true) { _, ids in
            if selectedTermID == nil || !ids.contains(selectedTermID!) {
                selectedTermID = liveTerms.last?.id
            }
        }
        .onChange(of: selectedTermID) { _, _ in
            selectedCourseID = nil
            selectedWeekStart = nil
        }
        .sheet(item: $editingItem) { item in
            if let course = item.course {
                GradeItemEditorView(course: course, categories: categories(for: item), item: item)
                    .id(item.id)
            }
        }
        .sheet(item: $editingTerm) { term in
            TermEditorView(defaultAcademicYear: preferences.firstAcademicYear, term: term)
        }
        .toolbar {
            if let selectedTerm {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit Semester Dates", systemImage: "calendar.badge.clock") {
                        editingTerm = selectedTerm
                    }
                    .accessibilityIdentifier("editSemesterDatesButton")
                }
            }
        }
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.medium) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(selectedTerm?.displayName ?? "Semester"))
                    .font(.title2.bold())
                if let selectedTerm, let start = selectedTerm.startDate, let end = selectedTerm.endDate {
                    Text(dateRange(start: start, end: end))
                        .font(.subheadline.weight(.medium))
                }
                Text(progressDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(todayContextTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(todayContextValue)
                    .font(.headline.monospacedDigit())
            }
        }
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .accessibilityIdentifier("semesterMapOverview")
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignSystem.Spacing.small) { filterControls }
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) { filterControls }
        }
    }

    @ViewBuilder private var filterControls: some View {
        Menu {
            Picker("Semester", selection: $selectedTermID) {
                ForEach(liveTerms) { term in
                    Text(LocalizedStringKey(term.displayName)).tag(Optional(term.id))
                }
            }
        } label: {
            filterLabel(selectedTerm?.displayName ?? "Semester", systemImage: "calendar")
        }

        Menu {
            Picker("Course", selection: $selectedCourseID) {
                Text("All Courses").tag(nil as UUID?)
                ForEach(termCourses) { course in
                    Text(course.courseCode).tag(Optional(course.id))
                }
            }
        } label: {
            filterLabel(
                termCourses.first(where: { $0.id == selectedCourseID })?.courseCode
                    ?? (AppCopy.isChinese(locale) ? "全部课程" : "All Courses"),
                systemImage: "books.vertical"
            )
        }

        Menu {
            Picker("Type", selection: $typeFilter) {
                ForEach(SemesterMapTypeFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            filterLabel(typeFilter.title, systemImage: "line.3.horizontal.decrease")
        }
    }

    private func filterLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.xSmall)
    }

    private func filterLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, DesignSystem.Spacing.small)
            .padding(.vertical, DesignSystem.Spacing.xSmall)
    }

    private var compactTimeline: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            ScrollView(.horizontal) {
                HStack(spacing: DesignSystem.Spacing.small) {
                    ForEach(weekStarts, id: \.self) { weekStart in
                        Button {
                            selectedWeekStart = weekStart
                        } label: {
                            VStack(spacing: 2) {
                                Text(weekLabel(weekStart))
                                    .font(.subheadline.weight(.semibold))
                                Text(weekRange(weekStart))
                                    .font(.caption2)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.small)
                            .padding(.vertical, DesignSystem.Spacing.xSmall)
                        }
                        .buttonStyle(
                            .glass(
                                .regular
                                    .tint(calendar.isDate(weekStart, inSameDayAs: effectiveSelectedWeek)
                                          ? DesignSystem.ColorToken.gold.opacity(0.32)
                                          : .clear)
                                    .interactive()
                            )
                        )
                        .buttonBorderShape(.capsule)
                        .accessibilityAddTraits(
                            calendar.isDate(weekStart, inSameDayAs: effectiveSelectedWeek) ? .isSelected : []
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            weekSection(effectiveSelectedWeek)
        }
        .accessibilityIdentifier("semesterMapCompactTimeline")
    }

    private var expandedTimeline: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 270), spacing: DesignSystem.Spacing.medium, alignment: .top)],
            alignment: .leading,
            spacing: DesignSystem.Spacing.medium
        ) {
            ForEach(weekStarts, id: \.self) { weekStart in
                weekSection(weekStart)
            }
        }
        .accessibilityIdentifier("semesterMapExpandedTimeline")
    }

    private func weekSection(_ weekStart: Date) -> some View {
        let weekItems = items(inWeekStarting: weekStart)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
            HStack {
                Text(weekLabel(weekStart))
                    .font(.headline)
                Spacer()
                Text(weekRange(weekStart))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if containsToday(weekStart) {
                Label("Today", systemImage: "circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignSystem.ColorToken.gold)
                    .accessibilityIdentifier("semesterMapTodayMarker")
            }
            if weekItems.isEmpty {
                Text("No dated work")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, DesignSystem.Spacing.small)
            } else {
                ForEach(weekItems) { item in
                    itemNode(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .contentSurface()
        .accessibilityIdentifier(
            containsToday(weekStart)
                ? "semesterMapCurrentWeek"
                : "semesterMapWeek-\(weekStart.timeIntervalSinceReferenceDate)"
        )
    }

    private func itemNode(_ item: GradeItem) -> some View {
        NavigationLink {
            if let course = item.course {
                CourseDetailView(course: course, preferences: preferences, initialScoringItemID: item.id)
            }
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.small) {
                Image(systemName: statusSymbol(item))
                    .foregroundStyle(statusColor(item))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(verbatim: item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: DesignSystem.Spacing.small)
                        Text(item.dueDate ?? .now, style: .time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: DesignSystem.Spacing.xSmall) {
                        Text(item.course?.courseCode ?? "Course")
                        Text(statusLabel(item))
                        if let category = item.category, category.weight > 0 {
                            Text("\(compact(category.weight))%")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Assignment Details", systemImage: "pencil") {
                editingItem = item
            }
        }
        .accessibilityIdentifier("semesterMapItem-\(item.title)")
    }

    private var progressDescription: String {
        guard let selectedTerm else { return "" }
        let currentIndex = weekStarts.firstIndex { containsToday($0) }
        if let currentIndex {
            return AppCopy.isChinese(locale)
                ? "第 \(currentIndex + 1) 周，共 \(weekStarts.count) 周"
                : "Week \(currentIndex + 1) of \(weekStarts.count)"
        }
        if let start = selectedTerm.startDate, .now < start {
            return AppCopy.isChinese(locale) ? "这个学期还未开始" : "This semester has not started yet"
        }
        if let end = selectedTerm.endDate, .now > end {
            return AppCopy.isChinese(locale) ? "这个学期已经结束" : "This semester has ended"
        }
        return selectedTerm.displayName
    }

    private var todayContextTitle: LocalizedStringKey {
        guard let start = selectedTerm?.startDate, let end = selectedTerm?.endDate else {
            return "Today"
        }
        if .now < start { return "Starts" }
        if .now > end { return "Ended" }
        return "Current Week"
    }

    private var todayContextValue: String {
        guard let start = selectedTerm?.startDate, let end = selectedTerm?.endDate else { return "" }
        if .now < start {
            return start.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }
        if .now > end {
            return end.formatted(.dateTime.month(.abbreviated).day().locale(locale))
        }
        return weekLabel(currentWeekStart)
    }

    private func dateRange(start: Date, end: Date) -> String {
        if AppCopy.isChinese(locale) {
            return "\(start.formatted(.dateTime.year().month().day().locale(locale))) – \(end.formatted(.dateTime.month().day().locale(locale)))"
        }
        return "\(start.formatted(.dateTime.month(.abbreviated).day().locale(locale))) – \(end.formatted(.dateTime.year().month(.abbreviated).day().locale(locale)))"
    }

    private func weekLabel(_ start: Date) -> String {
        guard let index = weekStarts.firstIndex(where: { calendar.isDate($0, inSameDayAs: start) }) else {
            return String(localized: "Week")
        }
        return AppCopy.isChinese(locale) ? "第 \(index + 1) 周" : "Week \(index + 1)"
    }

    private func weekRange(_ start: Date) -> String {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(start.formatted(.dateTime.month(.abbreviated).day().locale(locale)))–\(end.formatted(.dateTime.month(.abbreviated).day().locale(locale)))"
    }

    private func items(inWeekStarting start: Date) -> [GradeItem] {
        guard let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return [] }
        return filteredItems.filter {
            guard let due = $0.dueDate else { return false }
            return due >= start && due < end
        }
    }

    private func containsToday(_ start: Date) -> Bool {
        calendar.isDate(start, inSameDayAs: currentWeekStart)
    }

    private func categories(for item: GradeItem) -> [GradingCategory] {
        guard let course = item.course else { return [] }
        return categories
            .filter { !$0.isDeleted && $0.course?.persistentModelID == course.persistentModelID }
            .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
    }

    private func statusSymbol(_ item: GradeItem) -> String {
        if item.earnedPoints != nil || item.status == .graded { return "checkmark.circle.fill" }
        if (item.dueDate ?? .distantFuture) < .now || item.status == .missing { return "exclamationmark.circle.fill" }
        return item.category?.categoryType == .finalExam || item.category?.categoryType == .midterm
            ? "calendar.badge.clock"
            : "circle"
    }

    private func statusColor(_ item: GradeItem) -> Color {
        if item.earnedPoints != nil || item.status == .graded { return .green }
        if (item.dueDate ?? .distantFuture) < .now || item.status == .missing { return DesignSystem.ColorToken.warning }
        return DesignSystem.ColorToken.gold
    }

    private func statusLabel(_ item: GradeItem) -> LocalizedStringKey {
        if item.earnedPoints != nil || item.status == .graded { return "Completed" }
        if (item.dueDate ?? .distantFuture) < .now || item.status == .missing { return "Overdue" }
        return "Upcoming"
    }
}
