import SwiftData
import SwiftUI

/// One system-owned tab hierarchy for every iPad window size. Switching areas
/// no longer destroys and rebuilds the entire two/three-column navigation root.
struct IPadWorkspaceView: View {
    let preferences: UserPreferences
    @Binding var selection: AppTab
    @Binding var siriSearchQuery: String
    @Query private var courses: [CourseRecord]
    @State private var showQuickAdd = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("Today", systemImage: "sun.max", value: AppTab.dashboard) {
                DashboardView(preferences: preferences) { selection = .planner }
            }
            .accessibilityIdentifier("ipadSidebarTab-dashboard")
            Tab("Courses", systemImage: "books.vertical", value: AppTab.quarters) {
                IPadCourseWorkspace(preferences: preferences, searchText: .constant(""), isSearch: false)
            }
            .accessibilityIdentifier("ipadSidebarTab-quarters")
            Tab("GPA", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.planner) {
                PlannerView(preferences: preferences)
            }
            .accessibilityIdentifier("ipadSidebarTab-planner")
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView(preferences: preferences)
            }
            .accessibilityIdentifier("ipadSidebarTab-settings")
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search, role: .search) {
                IPadCourseWorkspace(preferences: preferences, searchText: $siriSearchQuery, isSearch: true)
            }
            .accessibilityIdentifier("ipadSearchButton")
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.ipadQuickAddAction, { showQuickAdd = true })
        .background {
            // Commands work in both presentations without a second search button.
            Group {
                Button("Search") { selection = .search }.keyboardShortcut("k", modifiers: .command)
                Button("Quick Add") { showQuickAdd = true }.keyboardShortcut("n", modifiers: .command)
                Button("Today") { selection = .dashboard }.keyboardShortcut("1", modifiers: .command)
                Button("Courses") { selection = .quarters }.keyboardShortcut("2", modifiers: .command)
                Button("GPA") { selection = .planner }.keyboardShortcut("3", modifiers: .command)
                Button("Settings") { selection = .settings }.keyboardShortcut(",", modifiers: .command)
            }
            .hidden()
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $showQuickAdd) {
            let liveCourses = courses.filter { !$0.isDeleted }
            if liveCourses.isEmpty {
                ContentUnavailableView("Add a course first", systemImage: "book.closed",
                    description: Text("Create a course before adding work or scores."))
                    .presentationDetents([.medium])
            } else {
                NaturalLanguageQuickAddView(courses: liveCourses)
            }
        }
    }
}

private struct IPadQuickAddActionKey: EnvironmentKey {
    static var defaultValue: (@MainActor () -> Void)? { nil }
}

extension EnvironmentValues {
    var ipadQuickAddAction: (@MainActor () -> Void)? {
        get { self[IPadQuickAddActionKey.self] }
        set { self[IPadQuickAddActionKey.self] = newValue }
    }
}

extension View {
    func ipadProductivityToolbar() -> some View { modifier(IPadProductivityToolbar()) }
}

private struct IPadProductivityToolbar: ViewModifier {
    @Environment(\.ipadQuickAddAction) private var action
    func body(content: Content) -> some View {
        content.toolbar {
            if let action {
                ToolbarItem(placement: .primaryAction) {
                    Button("Quick Add", systemImage: "text.badge.plus", action: action)
                        .keyboardShortcut("n", modifiers: .command)
                        .accessibilityIdentifier("ipadQuickAddButton")
                }
            }
        }
    }
}

/// Courses and search keep separate selections and share the canonical detail.
private struct IPadCourseWorkspace: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let preferences: UserPreferences
    @Binding var searchText: String
    let isSearch: Bool
    @State private var selectedCourseID: UUID?
    @State private var showCourseTemplates = false
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .sidebar
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            if isSearch {
                courseList
                    .searchable(text: $searchText, placement: .sidebar, prompt: "Search courses")
                    .searchFocused($searchFieldFocused)
                    .onAppear { searchFieldFocused = true }
            } else {
                courseList
            }
        } detail: {
            if showCourseTemplates {
                CourseTemplatesView()
            } else {
                IPadCourseDetailDestination(preferences: preferences, selectedCourseID: selectedCourseID)
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Let the split container continue behind the enclosing tab bar. Its
        // native column navigation bars still inset controls and scroll content.
        .ignoresSafeArea(.container, edges: .top)
        // Extend only the canvas through the enclosing tab's safe area. Mirroring
        // this entire navigation container would also reflect toolbar text.
        .background { Color(.systemGroupedBackground).ignoresSafeArea() }
        .onChange(of: showCourseTemplates) { _, shown in
            if shown { preferredCompactColumn = .detail }
        }
    }

    private var courseList: some View {
        IPadCourseList(
            preferences: preferences, searchQuery: searchText, isSearch: isSearch,
            automaticallySelectFirstCourse: horizontalSizeClass == .regular,
            selectedCourseID: $selectedCourseID,
            onCourseSelection: { showCourseTemplates = false },
            showCourseTemplates: $showCourseTemplates
        )
    }
}

struct IPadCourseList: View {
    @Query(sort: \CourseRecord.updatedAt, order: .reverse) private var courses: [CourseRecord]
    let preferences: UserPreferences
    let searchQuery: String
    let isSearch: Bool
    let automaticallySelectFirstCourse: Bool
    @Binding var selectedCourseID: UUID?
    let onCourseSelection: () -> Void
    @Binding var showCourseTemplates: Bool

    private var liveCourses: [CourseRecord] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return courses.filter { !$0.isDeleted && (query.isEmpty
            || $0.courseCode.localizedCaseInsensitiveContains(query)
            || $0.courseTitle.localizedCaseInsensitiveContains(query)) }
    }

    private var screenshotCourseID: UUID? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--screenshot-course-detail")
                || arguments.contains("--screenshot-grade-breakdown") else { return nil }
        return liveCourses.first { $0.courseCode == "CHE 002A" }?.id
    }

    var body: some View {
        List(selection: $selectedCourseID) {
            if liveCourses.isEmpty {
                if isSearch && !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // The query already appears in the search field. Keep the
                    // native empty-state title short enough for the sidebar.
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                        description: Text("Check the spelling or try a new search."))
                } else {
                    ContentUnavailableView("No courses", systemImage: "books.vertical",
                        description: Text("Add a course from Today or a quarter."))
                }
            } else {
                ForEach(liveCourses) { course in
                    NavigationLink(value: course.id) { CourseRow(course: course, compactLayout: true) }
                        .contextMenu {
                            Button("Open Course", systemImage: "arrow.right") {
                                selectedCourseID = course.id
                                onCourseSelection()
                            }
                        }
                }
            }
        }
        .ipadProductivityToolbar()
        // Let NavigationLink own taps; an extra row gesture can prevent its
        // native selection action. React to the resulting selection instead.
        .onChange(of: selectedCourseID) { _, id in
            if id != nil { onCourseSelection() }
        }
        .navigationTitle(isSearch ? LocalizedStringKey("Search") : LocalizedStringKey("Courses"))
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 380)
        .toolbar {
            if !isSearch {
                ToolbarItem(placement: .primaryAction) {
                    Button("Course Templates", systemImage: "rectangle.3.group") {
                        // Templates are a different destination. Clear the row
                        // highlight so reselecting the same course navigates back.
                        selectedCourseID = nil
                        showCourseTemplates = true
                    }
                    .accessibilityIdentifier("courseTemplatesButton")
                }
            }
        }
        .onChange(of: liveCourses.map(\.id), initial: true) { _, ids in
            if let screenshotCourseID {
                selectedCourseID = screenshotCourseID
            } else if let selectedCourseID, !ids.contains(selectedCourseID) {
                self.selectedCourseID = automaticallySelectFirstCourse ? ids.first : nil
            } else if selectedCourseID == nil, automaticallySelectFirstCourse {
                selectedCourseID = ids.first
            }
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
            ContentUnavailableView("Select a course", systemImage: "rectangle.split.2x1",
                description: Text("Choose a course to keep its gradebook visible here."))
        }
    }
}
