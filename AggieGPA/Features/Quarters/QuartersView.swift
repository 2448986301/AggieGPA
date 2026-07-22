import SwiftData
import SwiftUI

struct QuartersView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var policies: [CourseGradingPolicy]
    @Query private var categories: [GradingCategory]
    @Query private var items: [GradeItem]
    @Query private var scales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    let preferences: UserPreferences
    @State private var searchText = ""
    @State private var selectedYear = "All"
    @State private var showNewTerm = false
    @State private var pendingDelete: AcademicTerm?

    private var years: [String] { ["All"] + Array(Set(terms.map(\.academicYear))).sorted() }
    private var filtered: [AcademicTerm] {
        terms.filter { term in
            (selectedYear == "All" || term.academicYear == selectedYear) &&
            (searchText.isEmpty || term.displayName.localizedCaseInsensitiveContains(searchText) ||
             term.courses.contains { $0.courseCode.localizedCaseInsensitiveContains(searchText) || $0.courseTitle.localizedCaseInsensitiveContains(searchText) })
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        terms.isEmpty ? "No quarters yet" : "No matching quarters",
                        systemImage: terms.isEmpty ? "calendar.badge.plus" : "magnifyingglass",
                        description: terms.isEmpty ? Text("Create a quarter, then add courses and grades.") : Text("Try a different search or academic year.")
                    )
                } else {
                    List {
                        ForEach(Dictionary(grouping: filtered, by: \.academicYear).keys.sorted(), id: \.self) { year in
                            Section("Academic Year \(year)") {
                                ForEach(filtered.filter { $0.academicYear == year }) { term in
                                    NavigationLink(value: term) { TermRow(term: term, precision: preferences.decimalPrecision) }
                                        .contextMenu {
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
            .searchable(text: $searchText, prompt: "Course, title, or quarter")
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
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("addQuarterButton")
                }
            }
            .sheet(isPresented: $showNewTerm) { TermEditorView(defaultAcademicYear: preferences.firstAcademicYear) }
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
                                displayName: term.displayName + " Copy", notes: term.notes,
                                sortOrder: (terms.map(\.sortOrder).max() ?? 0) + 1)
        modelContext.insert(copy)
        for course in term.courses {
            modelContext.insert(CourseRecord(courseCode: course.courseCode, courseTitle: course.courseTitle,
                                             units: course.units, grade: course.grade, gradingBasis: course.gradingBasis,
                                             institution: course.institution, term: copy, isMajorCourse: course.isMajorCourse,
                                             isUpperDivision: course.isUpperDivision, isIncludedInGPA: course.isIncludedInGPA,
                                             isTransferCourse: course.isTransferCourse, notes: course.notes))
        }
        try? modelContext.save()
    }

    private func delete(_ term: AcademicTerm) {
        let courseIDs = Set(term.courses.map(\.id))
        let deletedItems = items.filter { item in item.course.map { courseIDs.contains($0.id) } ?? false }
        let notificationIdentifiers = deletedItems.map(\.notificationIdentifier)
        deletedItems.forEach(modelContext.delete)
        categories.filter { category in category.course.map { courseIDs.contains($0.id) } ?? false }.forEach(modelContext.delete)
        policies.filter { policy in policy.course.map { courseIDs.contains($0.id) } ?? false }.forEach(modelContext.delete)
        scales.filter { scale in scale.course.map { courseIDs.contains($0.id) } ?? false }.forEach(modelContext.delete)
        forecasts.filter { forecast in forecast.course.map { courseIDs.contains($0.id) } ?? false }.forEach(modelContext.delete)
        modelContext.delete(term)
        do {
            try modelContext.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
        } catch {
            modelContext.rollback()
        }
    }

    private func move(year: String, from source: IndexSet, to destination: Int) {
        var yearTerms = terms.filter { $0.academicYear == year }
        yearTerms.move(fromOffsets: source, toOffset: destination)
        for (index, term) in yearTerms.enumerated() { term.sortOrder = index; term.updatedAt = .now }
        try? modelContext.save()
    }
}

private struct TermRow: View {
    @Environment(\.locale) private var locale
    let term: AcademicTerm
    let precision: Int
    private var result: GPAResult { GPAService.quarter(term.courses.map(CourseCalculationInput.init), termID: term.id) }

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.medium) {
            Image(systemName: term.courses.contains(where: { $0.grade.isPending }) ? "calendar.badge.exclamationmark" : "calendar")
                .foregroundStyle(DesignSystem.ColorToken.gold)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(term.displayName).font(.headline)
                Text(verbatim: AppCopy.termSummary(units: result.attemptedUnits, courseCount: term.courses.count, locale: locale))
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
    @State private var academicYear: String
    @State private var termType = TermType.fall
    @State private var displayName = ""
    @State private var notes = ""
    @State private var include = true

    init(defaultAcademicYear: String) {
        self.defaultAcademicYear = defaultAcademicYear
        _academicYear = State(initialValue: defaultAcademicYear)
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
                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
                Section { DisclaimerBanner() }
            }
            .navigationTitle("New Quarter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(academicYear.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("saveQuarterButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let year = academicYear.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = "\(termType.rawValue) \(year.prefix(4))"
        let term = AcademicTerm(academicYear: year, termType: termType,
                                displayName: displayName.isEmpty ? fallbackName : displayName,
                                isIncludedInCumulativeGPA: include, notes: notes)
        modelContext.insert(term)
        try? modelContext.save()
        dismiss()
    }
}
