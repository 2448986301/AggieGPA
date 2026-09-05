import SwiftData
import SwiftUI

struct CourseTemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \CourseTemplate.updatedAt, order: .reverse) private var templates: [CourseTemplate]
    @State private var selectedTemplateID: UUID?

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    templateList(selection: $selectedTemplateID)
                } detail: {
                    if let template = selectedTemplate {
                        CourseTemplateDetailView(template: template)
                    } else {
                        ContentUnavailableView("Select a course template", systemImage: "rectangle.3.group")
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack {
                    List {
                        Section("Choose Template") {
                            ForEach(templates) { template in
                                NavigationLink {
                                    CourseTemplateDetailView(template: template)
                                } label: {
                                    CourseTemplateRow(template: template)
                                }
                            }
                        }
                    }
                    .navigationTitle("Course Templates")
                    .overlay {
                        if templates.isEmpty {
                            ContentUnavailableView("No course templates", systemImage: "rectangle.3.group")
                        }
                    }
                }
            }
        }
        .task { CourseTemplateService.seedBuiltInsIfNeeded(context: modelContext, templates: templates) }
        .onChange(of: templates.map(\.id), initial: true) { _, ids in
            if selectedTemplateID == nil || !ids.contains(selectedTemplateID!) {
                selectedTemplateID = ids.first
            }
        }
    }

    private var selectedTemplate: CourseTemplate? {
        templates.first { $0.id == selectedTemplateID }
    }

    private func templateList(selection: Binding<UUID?>) -> some View {
        List(selection: selection) {
            Section("Choose Template") {
                ForEach(templates) { template in
                    CourseTemplateRow(template: template)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(template.id)
                }
            }
        }
        .navigationTitle("Course Templates")
        .overlay {
            if templates.isEmpty {
                ContentUnavailableView("No course templates", systemImage: "rectangle.3.group")
            }
        }
        .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 420)
    }
}

private struct CourseTemplateRow: View {
    let template: CourseTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if template.isBuiltIn {
                    Text(LocalizedStringKey(template.name)).font(.headline)
                } else {
                    Text(verbatim: template.name).font(.headline)
                }
                Spacer()
                if template.isBuiltIn { Image(systemName: "checkmark.seal").foregroundStyle(DesignSystem.ColorToken.gold) }
            }
            HStack(spacing: 3) {
                Text("\(template.categories.count) categories")
                Text("·").accessibilityHidden(true)
                Text(template.gradingMethod.localizedDisplayName)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("courseTemplateRow-\(template.id.uuidString)")
    }
}

struct CourseTemplateDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let template: CourseTemplate
    @State private var showCreateCourse = false
    @State private var showRename = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                    Label(template.isBuiltIn ? "Built-in Template" : "Saved Template", systemImage: template.isBuiltIn ? "checkmark.seal" : "rectangle.3.group")
                        .font(.caption.weight(.semibold)).foregroundStyle(DesignSystem.ColorToken.gold)
                    if template.isBuiltIn {
                        Text(LocalizedStringKey(template.name)).font(.title2.bold())
                    } else {
                        Text(verbatim: template.name).font(.title2.bold())
                    }
                    Text(template.gradingMethod.localizedDisplayName).foregroundStyle(.secondary)
                }
                .padding(.vertical, DesignSystem.Spacing.small)
            }

            Section("Categories") {
                if template.categories.isEmpty {
                    Text("No categories saved").foregroundStyle(.secondary)
                }
                ForEach(template.categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) { category in
                    LabeledContent {
                        Text(DecimalFormatters.compact(category.weight) + "%")
                            .monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: category.name)
                            Text(category.calculationMode.localizedDisplayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let scale = template.gradeScale {
                Section("Grade Scale") {
                    Text(verbatim: scale.name)
                    ForEach(scale.boundaries, id: \.letter) { boundary in
                        LabeledContent(boundary.letter.rawValue, value: DecimalFormatters.compact(boundary.minimumPercentage) + "%")
                    }
                }
            }

            Section {
                Button("Create Course", systemImage: "plus.circle.fill") { showCreateCourse = true }
                    .buttonStyle(.glass(.regular.tint(DesignSystem.ColorToken.gold.opacity(0.30)).interactive()))
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .accessibilityIdentifier("createCourseFromTemplateButton")
                Button("Rename Template", systemImage: "pencil") { showRename = true }
                Button("Delete Template", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("Preview Template")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCreateCourse) { TemplateCourseCreationView(template: template) }
        .sheet(isPresented: $showRename) { TemplateRenameView(template: template) }
        .alert("Delete this template?", isPresented: $confirmDelete) {
            Button("Delete Template", role: .destructive) {
                modelContext.delete(template)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Courses created from this template are not changed.")
        }
        .alert("Couldn’t complete that action", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") {} } message: { Text(errorMessage ?? "Please try again.") }
        .animation(DesignSystem.Motion.standard(reduceMotion: reduceMotion), value: showCreateCourse)
        .accessibilityIdentifier("courseTemplatePreview")
    }
}

private struct TemplateRenameView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let template: CourseTemplate
    @State private var name: String

    init(template: CourseTemplate) {
        self.template = template
        _name = State(initialValue: template.name)
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Template name", text: $name).textInputAutocapitalization(.words) }
                .navigationTitle("Rename Template")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            template.name = trimmed
                            template.isBuiltIn = false
                            template.updatedAt = .now
                            try? modelContext.save(); dismiss()
                        }
                    }
                }
        }
    }
}

struct CourseTemplateSaveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allItems: [GradeItem]
    let course: CourseRecord
    let policy: CourseGradingPolicy?
    let categories: [GradingCategory]
    let scale: GradeScale?
    @State private var name: String

    init(course: CourseRecord, policy: CourseGradingPolicy?, categories: [GradingCategory], scale: GradeScale?) {
        self.course = course; self.policy = policy; self.categories = categories; self.scale = scale
        _name = State(initialValue: course.courseCode + " Template")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template") {
                    TextField("Template name", text: $name)
                    Text("Only the grading structure and scale are saved. Course grades, assignments, exams, and private notes are not copied.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Preview") {
                    LabeledContent("Source Course", value: course.courseCode)
                    LabeledContent("Categories", value: "\(categories.count)")
                    LabeledContent("Grade Scale", value: scale == nil ? "None" : "Included")
                }
            }
            .navigationTitle("Save Course Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        modelContext.insert(CourseTemplateService.capture(
                            name: trimmed, course: course, policy: policy, categories: categories,
                            scale: scale, items: allItems.filter { !$0.isDeleted && $0.course?.id == course.id }
                        ))
                        try? modelContext.save(); dismiss()
                    }
                }
            }
        }
    }
}

struct TemplateCourseCreationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    let template: CourseTemplate
    @State private var selectedTermID: UUID?
    @State private var courseCode = ""
    @State private var courseTitle = ""
    @State private var units = "4"
    @State private var gradingBasis: GradingBasis = .letter
    @State private var copyCommonSettings = true
    @State private var copyReminders = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if terms.isEmpty {
                    ContentUnavailableView("Add a quarter first", systemImage: "calendar.badge.plus")
                } else {
                    Section("New Course") {
                        Picker("Quarter", selection: $selectedTermID) {
                            ForEach(terms.filter { !$0.isDeleted }) { term in
                                Text(verbatim: AppCopy.termName(term, locale: locale)).tag(Optional(term.id))
                            }
                        }
                        TextField("Course code", text: $courseCode)
                            .accessibilityIdentifier("templateCourseCodeField")
                        TextField("Course title", text: $courseTitle)
                        TextField("Units", text: $units).keyboardType(.decimalPad)
                        Picker("Grading basis", selection: $gradingBasis) {
                            ForEach(GradingBasis.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                    }
                    Section("Copy Options") {
                        Toggle("Copy common grading settings", isOn: $copyCommonSettings)
                        Toggle("Copy reminder defaults for future items", isOn: $copyReminders)
                        Text("Assignments, exams, grades, and private notes are never copied.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Section("Template Preview") {
                        ForEach(template.categories.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }) { category in
                            HStack {
                                Text(verbatim: category.name)
                                Spacer()
                                Text(DecimalFormatters.compact(category.weight) + "%")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Create Course")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create Course") { create() }
                        .disabled(terms.isEmpty)
                        .accessibilityIdentifier("confirmTemplateCourseButton")
                }
            }
            .onAppear { selectedTermID = selectedTermID ?? terms.first(where: { !$0.isDeleted })?.id }
            .alert("Couldn’t create course", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK") {} } message: { Text(errorMessage ?? "Please check the course details.") }
        }
    }

    private func create() {
        guard let term = terms.first(where: { $0.id == selectedTermID }),
              !courseCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let unitValue = DecimalFormatters.decimal(from: units), unitValue > 0 else {
            errorMessage = "Enter a course code, a quarter, and positive units."
            return
        }
        do {
            _ = try CourseTemplateService.createCourse(
                from: template, courseCode: courseCode, courseTitle: courseTitle,
                units: unitValue, term: term, gradingBasis: gradingBasis,
                copyCommonSettings: copyCommonSettings, copyReminders: copyReminders,
                context: modelContext
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension GradingMethod {
    var localizedDisplayName: LocalizedStringKey {
        switch self {
        case .weightedCategories: "Weighted Categories"
        case .totalPoints: "Points Based"
        case .hybrid: "Hybrid"
        case .manualLetterGradeOnly: "Manual Letter Grade"
        }
    }
}

private extension CategoryCalculationMode {
    var localizedDisplayName: LocalizedStringKey {
        switch self {
        case .weightedCategory: "Weighted category"
        case .totalPoints: "Total points"
        case .equalItems: "Equal items"
        case .custom: "Custom"
        }
    }
}
