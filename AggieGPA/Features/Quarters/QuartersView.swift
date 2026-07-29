import SwiftData
import SwiftUI

struct QuartersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var courses: [CourseRecord]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let preferences: UserPreferences
    let initialSearchQuery: String
    @State private var searchText = ""
    @State private var selectedYear = "All"
    @State private var showNewTerm = false
    @State private var editingTerm: AcademicTerm?
    @State private var pendingDelete: AcademicTerm?

    init(preferences: UserPreferences, initialSearchQuery: String = "") {
        self.preferences = preferences
        self.initialSearchQuery = initialSearchQuery
    }

    private var liveTerms: [AcademicTerm] { terms.filter { !$0.isDeleted } }
    private var years: [String] { ["All"] + Array(Set(liveTerms.map(\.academicYear))).sorted() }
    private var filtered: [AcademicTerm] {
        liveTerms.filter { term in
            (selectedYear == "All" || term.academicYear == selectedYear) &&
            (searchText.isEmpty || term.displayName.localizedCaseInsensitiveContains(searchText) ||
             courses(for: term).contains { $0.courseCode.localizedCaseInsensitiveContains(searchText) || $0.courseTitle.localizedCaseInsensitiveContains(searchText) } ||
             items.contains { item in
                 item.course?.term?.persistentModelID == term.persistentModelID &&
                 item.title.localizedCaseInsensitiveContains(searchText)
             })
        }
    }

    private func courses(for term: AcademicTerm) -> [CourseRecord] {
        courses.filter { course in
            !course.isDeleted && course.term?.persistentModelID == term.persistentModelID
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        liveTerms.isEmpty ? "No quarters yet" : "No matching quarters",
                        systemImage: liveTerms.isEmpty ? "calendar.badge.plus" : "magnifyingglass",
                        description: liveTerms.isEmpty ? Text("Create a quarter, then add courses and grades.") : Text("Try a different search or academic year.")
                    )
                } else {
                    List {
                        ForEach(Dictionary(grouping: filtered, by: \.academicYear).keys.sorted(), id: \.self) { year in
                            Section("Academic Year \(year)") {
                                ForEach(filtered.filter { $0.academicYear == year }) { term in
                                    NavigationLink(value: term) { TermRow(term: term, courses: courses(for: term), precision: preferences.decimalPrecision) }
                                        .contextMenu {
                                            Button("Edit Term", systemImage: "calendar.badge.clock") {
                                                editingTerm = term
                                            }
                                            Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(term) }
                                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = term }
                                        }
                                        .swipeActions(edge: .trailing) {
                                            Button("Delete", role: .destructive) { pendingDelete = term }
                                        }
                                }
                                .onMove { source, destination in move(year: year, from: source, to: destination) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Quarters")
            .searchable(text: $searchText, prompt: "Course, coursework, or quarter")
            .onChange(of: initialSearchQuery, initial: true) { _, query in
                searchText = query
            }
            .navigationDestination(for: AcademicTerm.self) { term in
                TermDetailView(term: term, preferences: preferences)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("Academic year", systemImage: "line.3.horizontal.decrease.circle") {
                        Picker("Academic year", selection: $selectedYear) {
                            ForEach(years, id: \.self) { year in
                                if year == "All" { Text("All").tag(year) } else { Text(year).tag(year) }
                            }
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add Quarter", systemImage: "plus") { showNewTerm = true }
                        .accessibilityIdentifier("addQuarterButton")
                }
            }
            .sheet(isPresented: $showNewTerm) { TermEditorView(defaultAcademicYear: preferences.firstAcademicYear) }
            .sheet(item: $editingTerm) { term in
                TermEditorView(defaultAcademicYear: preferences.firstAcademicYear, term: term)
            }
            .confirmationDialog("Delete this quarter and all of its courses?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete Quarter", role: .destructive) {
                    if let pendingDelete { delete(pendingDelete) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This action cannot be undone from this screen. Export a backup first if needed.")
            }
        }
    }

    private func duplicate(_ term: AcademicTerm) {
        let copy = AcademicTerm(academicYear: term.academicYear, termType: term.termType,
                                displayName: term.displayName + " Copy",
                                startDate: term.startDate, endDate: term.endDate, notes: term.notes,
                                sortOrder: (terms.map(\.sortOrder).max() ?? 0) + 1)
        modelContext.insert(copy)
        for course in courses(for: term) {
            modelContext.insert(CourseRecord(courseCode: course.courseCode, courseTitle: course.courseTitle,
                                             units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                             institution: course.institution, term: copy, isMajorCourse: course.isMajorCourse,
                                             isUpperDivision: course.isUpperDivision, isIncludedInGPA: course.isIncludedInGPA,
                                             isTransferCourse: course.isTransferCourse, notes: course.notes))
        }
        try? modelContext.save()
    }

    private func delete(_ term: AcademicTerm) {
        let termCourses = courses(for: term)
        let courseModelIDs = Set(termCourses.map(\.persistentModelID))
        func belongsToDeletedCourse(_ course: CourseRecord?) -> Bool {
            course.map { courseModelIDs.contains($0.persistentModelID) } ?? false
        }
        let deletedItems = items.filter { belongsToDeletedCourse($0.course) }
        let notificationIdentifiers = deletedItems.map(\.notificationIdentifier)
        deletedItems.forEach(modelContext.delete)
        categories.filter { belongsToDeletedCourse($0.course) }.forEach(modelContext.delete)
        policies.filter { belongsToDeletedCourse($0.course) }.forEach(modelContext.delete)
        scales.filter { belongsToDeletedCourse($0.course) }.forEach(modelContext.delete)
        forecasts.filter { belongsToDeletedCourse($0.course) }.forEach(modelContext.delete)
        termCourses.forEach { course in
            course.term = nil
            modelContext.delete(course)
        }
        modelContext.delete(term)
        do {
            try modelContext.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
        } catch {
            modelContext.rollback()
        }
    }

    private func move(year: String, from source: IndexSet, to destination: Int) {
        var yearTerms = liveTerms.filter { $0.academicYear == year }
        yearTerms.move(fromOffsets: source, toOffset: destination)
        for (index, term) in yearTerms.enumerated() { term.sortOrder = index; term.updatedAt = .now }
        try? modelContext.save()
    }
}

private struct TermRow: View {
    @Environment(\.locale) private var locale
    let term: AcademicTerm
    let courses: [CourseRecord]
    let precision: Int
    private var result: GPAResult { GPAService.quarter(courses.map(CourseCalculationInput.init), termID: term.id) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Image(systemName: courses.contains(where: { $0.grade.isPending }) ? "calendar.badge.exclamationmark" : "calendar")
                .foregroundStyle(DesignSystem.ColorToken.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(term.displayName)).font(.headline)
                Text(verbatim: AppCopy.termSummary(units: result.attemptedUnits, courseCount: courses.count, locale: locale))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(DecimalFormatters.string(result.gpa, precision: precision)).font(.headline)
                Text(term.isIncludedInCumulativeGPA ? "Included" : "Excluded").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TermEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let defaultAcademicYear: String
    let term: AcademicTerm?
    @State private var academicYear: String
    @State private var termType: TermType
    @State private var displayName: String
    @State private var notes: String
    @State private var include: Bool
    @State private var includesDates: Bool
    @State private var startDate: Date
    @State private var endDate: Date

    init(defaultAcademicYear: String, term: AcademicTerm? = nil) {
        self.defaultAcademicYear = defaultAcademicYear
        self.term = term
        let calendar = Calendar.autoupdatingCurrent
        let defaultStart = calendar.startOfDay(for: .now)
        let defaultEnd = calendar.date(byAdding: .weekOfYear, value: 10, to: defaultStart) ?? defaultStart
        _academicYear = State(initialValue: term?.academicYear ?? defaultAcademicYear)
        _termType = State(initialValue: term?.termType ?? .fall)
        _displayName = State(initialValue: term?.displayName ?? "")
        _notes = State(initialValue: term?.notes ?? "")
        _include = State(initialValue: term?.isIncludedInCumulativeGPA ?? true)
        _includesDates = State(initialValue: term == nil || term?.startDate != nil || term?.endDate != nil)
        _startDate = State(initialValue: term?.startDate ?? defaultStart)
        _endDate = State(initialValue: term?.endDate ?? defaultEnd)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quarter") {
                    TextField("Academic year, e.g. 2026–2027", text: $academicYear)
                    Picker("Term", selection: $termType) {
                        ForEach(TermType.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    TextField("Custom display name (optional)", text: $displayName)
                    Toggle("Include in cumulative GPA", isOn: $include)
                }
                Section {
                    Toggle("Add start and end dates", isOn: $includesDates)
                    if includesDates {
                        DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                            .accessibilityIdentifier("termStartDatePicker")
                        DatePicker("End Date", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .accessibilityIdentifier("termEndDatePicker")
                    }
                } header: {
                    Text("Semester Dates")
                } footer: {
                    Text("Semester Map uses these dates and never guesses your academic calendar.")
                }
                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
                Section { DisclaimerBanner() }
            }
            .navigationTitle(term == nil ? "New Quarter" : "Edit Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(
                            academicYear.trimmingCharacters(in: .whitespaces).isEmpty
                                || (includesDates && endDate < startDate)
                        )
                        .accessibilityIdentifier("saveQuarterButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let year = academicYear.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "\(termType.rawValue) \(year.prefix(4))"
        if let term {
            term.academicYear = year
            term.termType = termType
            term.displayName = displayName.isEmpty ? fallbackName : displayName
            term.isIncludedInCumulativeGPA = include
            term.startDate = includesDates ? startDate : nil
            term.endDate = includesDates ? endDate : nil
            term.notes = notes
            term.updatedAt = .now
        } else {
            let newTerm = AcademicTerm(
                academicYear: year,
                termType: termType,
                displayName: displayName.isEmpty ? fallbackName : displayName,
                startDate: includesDates ? startDate : nil,
                endDate: includesDates ? endDate : nil,
                isIncludedInCumulativeGPA: include,
                notes: notes
            )
            modelContext.insert(newTerm)
        }
        try? modelContext.save()
        dismiss()
    }
}
