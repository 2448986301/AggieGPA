import SwiftData
import SwiftUI

/// iPad's regular-width composition. It reuses the phone feature views and their
/// SwiftData queries while giving navigation, selection, and detail their own space.
struct IPadWorkspaceView: View {
    let preferences: UserPreferences
    @Binding var selection: AppTab
    @Binding var siriSearchQuery: String
    @State private var selectedCourseID: UUID?

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(AppTab.allCases) { tab in
                    Button {
                        selection = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                    .keyboardShortcut(shortcut(for: tab), modifiers: .command)
                    .accessibilityAddTraits(selection == tab ? .isSelected : [])
                }
            }
            .navigationTitle("Aggie GPA")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
        } content: {
            if selection == .quarters {
                IPadCourseList(preferences: preferences, searchQuery: siriSearchQuery, selectedCourseID: $selectedCourseID)
            } else {
                ContentUnavailableView("Select an area", systemImage: "rectangle.split.2x1")
            }
        } detail: {
            Group {
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
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func shortcut(for tab: AppTab) -> KeyEquivalent {
        switch tab { case .dashboard: "1"; case .quarters: "2"; case .planner: "3"; case .settings: "4" }
    }
}

struct IPadCourseList: View {
    @Query(sort: \CourseRecord.updatedAt, order: .reverse) private var courses: [CourseRecord]
    let preferences: UserPreferences
    let searchQuery: String
    @Binding var selectedCourseID: UUID?
    @State private var searchText = ""

    private var liveCourses: [CourseRecord] {
        let query = searchText.isEmpty ? searchQuery : searchText
        return courses.filter { !$0.isDeleted && ($0.courseCode.localizedCaseInsensitiveContains(query) || $0.courseTitle.localizedCaseInsensitiveContains(query) || query.isEmpty) }
    }
    private var selectedCourse: CourseRecord? { liveCourses.first { $0.id == selectedCourseID } }

    var body: some View {
        List(selection: $selectedCourseID) {
                if liveCourses.isEmpty {
                    ContentUnavailableView("No courses", systemImage: "books.vertical", description: Text("Add a course from Today or a quarter."))
                } else {
                    ForEach(liveCourses) { course in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(course.courseCode).font(.headline)
                            Text(LocalizedStringKey(course.courseTitle.isEmpty ? course.term?.displayName ?? "Course" : course.courseTitle))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .tag(course.id)
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
        .navigationSplitViewColumnWidth(min: 240, ideal: 300, max: 340)
        .onChange(of: liveCourses.map(\.id), initial: true) { _, ids in
            if selectedCourseID == nil || !ids.contains(selectedCourseID!) {
                selectedCourseID = ids.first
            }
        }
        .onChange(of: searchQuery, initial: true) { _, query in searchText = query }
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
