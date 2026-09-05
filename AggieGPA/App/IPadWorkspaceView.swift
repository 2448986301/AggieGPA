import SwiftData
import SwiftUI

/// iPad's regular-width composition. It reuses the phone feature views and their
/// SwiftData queries while giving navigation, selection, and detail their own space.
struct IPadWorkspaceView: View {
    let preferences: UserPreferences
    @Binding var selection: AppTab
    @Binding var siriSearchQuery: String
    @Query private var courses: [CourseRecord]
    @State private var selectedCourseID: UUID?
    @State private var searchRequestID = 0
    @State private var showQuickAdd = false
    @State private var showCourseTemplates = false

    private var liveCourses: [CourseRecord] {
        courses.filter { !$0.isDeleted }
    }

    var body: some View {
        Group {
            if selection == .quarters {
                coursesWorkspace
            } else {
                singleColumnWorkspace
            }
        }
        // Search and Quick Add already live in the system sidebar. Keeping a
        // second toolbar copy here produced a stacked floating control layer
        // on iPad, especially while a sheet was presented.
        .sheet(isPresented: $showQuickAdd) {
            if liveCourses.isEmpty {
                ContentUnavailableView(
                    "Add a course first",
                    systemImage: "book.closed",
                    description: Text("Create a course before adding work or scores.")
                )
                .presentationDetents([.medium])
            } else {
                NaturalLanguageQuickAddView(courses: liveCourses)
            }
        }
    }

    private var coursesWorkspace: some View {
        NavigationSplitView {
            sidebar
        } content: {
            IPadCourseList(
                preferences: preferences,
                searchQuery: siriSearchQuery,
                searchRequestID: searchRequestID,
                selectedCourseID: $selectedCourseID,
                onCourseSelection: { showCourseTemplates = false },
                showCourseTemplates: $showCourseTemplates
            )
        } detail: {
            if showCourseTemplates {
                CourseTemplatesView()
            } else {
                selectedDetail
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var singleColumnWorkspace: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            selectedDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private var sidebar: some View {
        List(selection: sidebarSelection) {
            Section("Productivity") {
                Button("Search", systemImage: "magnifyingglass") {
                    selection = .quarters
                    searchRequestID &+= 1
                    showCourseTemplates = false
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .keyboardShortcut("k", modifiers: .command)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("ipadSearchButton")

                Button("Quick Add", systemImage: "text.badge.plus") {
                    showQuickAdd = true
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .keyboardShortcut("n", modifiers: .command)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("ipadQuickAddButton")
            }

            Section {
                ForEach(AppTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .tag(tab)
                        .keyboardShortcut(shortcut(for: tab), modifiers: .command)
                        .hoverEffect(.highlight)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("ipadSidebarTab-\(tab.rawValue)")
                        .accessibilitySortPriority(3)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Aggie GPA")
        .listStyle(.sidebar)
        // Native list selection makes the full visible row the hit target and
        // supplies first-party pointer, keyboard, and selected-state behavior.
        .listRowSpacing(0)
        .listSectionSpacing(4)
        .safeAreaPadding(.vertical, 0)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
    }

    private var sidebarSelection: Binding<AppTab?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    selection = newValue
                    if newValue != .quarters { showCourseTemplates = false }
                }
            }
        )
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection {
        case .dashboard:
            DashboardView(preferences: preferences) { selection = .planner }
        case .quarters:
            IPadCourseDetailDestination(preferences: preferences, selectedCourseID: selectedCourseID)
        case .planner:
            PlannerView(preferences: preferences)
        case .settings:
            SettingsView(preferences: preferences)
        }
    }

    private func shortcut(for tab: AppTab) -> KeyEquivalent {
        switch tab { case .dashboard: "1"; case .quarters: "2"; case .planner: "3"; case .settings: "," }
    }
}

struct IPadCourseList: View {
    @Query(sort: \CourseRecord.updatedAt, order: .reverse) private var courses: [CourseRecord]
    let preferences: UserPreferences
    let searchQuery: String
    let searchRequestID: Int
    @Binding var selectedCourseID: UUID?
    let onCourseSelection: () -> Void
    @Binding var showCourseTemplates: Bool
    @State private var searchText = ""
    @FocusState private var searchFieldFocused: Bool

    private var liveCourses: [CourseRecord] {
        let query = searchText.isEmpty ? searchQuery : searchText
        return courses.filter { !$0.isDeleted && ($0.courseCode.localizedCaseInsensitiveContains(query) || $0.courseTitle.localizedCaseInsensitiveContains(query) || query.isEmpty) }
    }
    private var selectedCourse: CourseRecord? { liveCourses.first { $0.id == selectedCourseID } }
    private var phaseFourScreenshotCourseID: UUID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-course-detail")
                || arguments.contains("--screenshot-grade-breakdown") else {
            return nil
        }
        return liveCourses.first { $0.courseCode == "CHE 002A" }?.id
    }

    var body: some View {
        List(selection: $selectedCourseID) {
                if liveCourses.isEmpty {
                    ContentUnavailableView("No courses", systemImage: "books.vertical", description: Text("Add a course from Today or a quarter."))
                } else {
                    ForEach(liveCourses) { course in
                        // Keep iPad's list and the phone term list on the same
                        // resolved grade surface. CourseRow owns the shared
                        // Current / Projected / Final presentation and resolver
                        // inputs, so a saved plan cannot drift between columns.
                        CourseRow(course: course)
                        .tag(course.id)
                        .contentShape(Rectangle())
                        .hoverEffect(.highlight)
                        // Keep the native List(selection:) interaction while
                        // also returning the outer detail column to the course
                        // when the already-selected row is tapped again.
                        .simultaneousGesture(TapGesture().onEnded {
                            selectedCourseID = course.id
                            onCourseSelection()
                        })
                        .accessibilitySortPriority(2)
                        .contextMenu {
                            Button("Open Course", systemImage: "arrow.right") {
                                selectedCourseID = course.id
                                onCourseSelection()
                            }
                        }
                    }
                }
        }
        .navigationTitle("Courses")
        .searchable(text: $searchText, prompt: "Course")
        .searchFocused($searchFieldFocused)
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 340)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCourseTemplates = true
                } label: {
                    Label("Course Templates", systemImage: "rectangle.3.group")
                }
                .accessibilityIdentifier("courseTemplatesButton")
            }
        }
        .onChange(of: liveCourses.map(\.id), initial: true) { _, ids in
            if let phaseFourScreenshotCourseID {
                selectedCourseID = phaseFourScreenshotCourseID
            } else if selectedCourseID == nil || !ids.contains(selectedCourseID!) {
                selectedCourseID = ids.first
            }
        }
        .onChange(of: searchQuery, initial: true) { _, query in searchText = query }
        .onChange(of: searchRequestID) { _, _ in
            searchText = ""
            searchFieldFocused = true
        }
    }
}

struct IPadCourseDetailDestination: View {
    @Query private var courses: [CourseRecord]
    let preferences: UserPreferences
    let selectedCourseID: UUID?
    var body: some View {
        if let course = courses.first(where: { $0.id == selectedCourseID && !$0.isDeleted }) {
            CourseDetailView(course: course, preferences: preferences)
        } else {
            ContentUnavailableView("Select a course", systemImage: "rectangle.split.2x1", description: Text("Choose a course to keep its gradebook visible here."))
        }
    }
}
