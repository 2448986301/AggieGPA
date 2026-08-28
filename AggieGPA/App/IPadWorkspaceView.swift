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
                selectedCourseID: $selectedCourseID
            )
        } detail: {
            selectedDetail
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
        List {
            Section("Productivity") {
                Button("Search", systemImage: "magnifyingglass") {
                    selection = .quarters
                    searchRequestID &+= 1
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .keyboardShortcut("k", modifiers: .command)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("ipadSearchButton")

                Button("Quick Add", systemImage: "text.badge.plus") {
                    showQuickAdd = true
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .keyboardShortcut("n", modifiers: .command)
                .hoverEffect(.highlight)
                .accessibilityIdentifier("ipadQuickAddButton")
            }

            Section {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .keyboardShortcut(shortcut(for: tab), modifiers: .command)
                    .hoverEffect(.highlight)
                    .accessibilityIdentifier("ipadSidebarTab-\(tab.rawValue)")
                    .accessibilitySortPriority(3)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
        }
        .navigationTitle("Aggie GPA")
        .listStyle(.sidebar)
        // Keep the system sidebar's compact rhythm.  The list supplies the
        // platform's accessible row hit target; adding a second fixed height
        // here was what made each row visibly taller than Apple's sidebar.
        .listRowSpacing(0)
        .listSectionSpacing(4)
        .safeAreaPadding(.vertical, 0)
        .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
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
                        .accessibilitySortPriority(2)
                        .contextMenu {
                            Button("Open Course", systemImage: "arrow.right") {
                                selectedCourseID = course.id
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
                NavigationLink {
                    CourseTemplatesView()
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
