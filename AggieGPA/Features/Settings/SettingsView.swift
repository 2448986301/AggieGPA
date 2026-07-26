import LocalAuthentication
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var courses: [CourseRecord]
    let preferences: UserPreferences
    @State private var dataError: String?

    var body: some View {
        @Bindable var preferences = preferences
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Name or nickname", text: $preferences.displayName)
                    TextField("Major", text: $preferences.major)
                    TextField("First academic year", text: $preferences.firstAcademicYear)
                    DecimalPreferenceField(title: "Target GPA", value: $preferences.targetGPA, range: 0...4)
                    Picker("Default grading basis", selection: $preferences.defaultGradingBasisRaw) {
                        ForEach(GradingBasis.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                    }
                }
                Section("Display") {
                    Picker("Language", selection: $preferences.languageRaw) {
                        ForEach(AppLanguage.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                    }
                    Picker("GPA decimal places", selection: $preferences.decimalPrecision) {
                        Text("2").tag(2); Text("3").tag(3); Text("4").tag(4)
                    }
                    Picker("Appearance", selection: $preferences.appearanceRaw) {
                        ForEach(AppAppearance.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                    }
                    Toggle("Show Major GPA", isOn: $preferences.showMajorGPA)
                    Toggle("Show Upper-Division GPA", isOn: $preferences.showUpperDivisionGPA)
                    Toggle("Show repeat summary", isOn: $preferences.showRepeatSummary)
                    Toggle("Haptics", isOn: $preferences.hapticsEnabled)
                    LabeledContent("App icon appearance", value: "Managed by iOS")
                    Text("Default, Dark, Clear, Tinted, and Monochrome appearances are selected by the iOS Home Screen. Aggie GPA does not pretend to switch unsupported system icon modes at runtime.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy Lock") {
                    Toggle("Require Face ID, Touch ID, or passcode", isOn: $preferences.privacyLockEnabled)
                        .accessibilityIdentifier("privacyLockToggle")
                    Picker("Lock delay", selection: $preferences.privacyLockDelayRaw) {
                        ForEach(PrivacyLockDelay.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0.rawValue) }
                    }.disabled(!preferences.privacyLockEnabled)
                    Text("Aggie GPA never receives or stores biometric data. Authentication is performed by iOS.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Notifications") {
                    NavigationLink("Assignment & Exam Reminders") { NotificationSettingsView() }
                    Text("Reminders are local to this device and can be enabled per grade item.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Siri AI") {
                    NavigationLink("Siri AI") { SiriAccessSettingsView() }
                    Text("Siri access is off by default. Each category of private data must be enabled explicitly.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Data") {
                    if preferences.demoDataLoaded {
                        Button("Clear Demo Data", role: .destructive) {
                            do {
                                try DemoDataService.clear(from: modelContext, courses: courses, preferences: preferences)
                            } catch {
                                dataError = "Demo data could not be cleared. Your academic data was not changed."
                            }
                        }
                    } else {
                        Button("Load Demo Data") { DemoDataService.load(into: modelContext, preferences: preferences) }
                    }
                    NavigationLink("Import, Export & Backups") { DataManagementView(preferences: preferences) }
                }
                Section("About") {
                    NavigationLink("Privacy") { InformationPage(title: "Privacy", text: "Privacy details") }
                    NavigationLink("GPA Rules") { InformationPage(title: "GPA Rules", text: "GPA rules details") }
                    NavigationLink("Disclaimer") { InformationPage(title: "Disclaimer", text: "Disclaimer details") }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                Section { DisclaimerBanner() }
            }
            .navigationTitle("Settings")
            .onChange(of: preferences.displayName) { _, _ in save() }
            .onChange(of: preferences.major) { _, _ in save() }
            .onChange(of: preferences.appearanceRaw) { _, _ in save() }
            .onChange(of: preferences.languageRaw) { _, _ in save() }
            .onChange(of: preferences.decimalPrecision) { _, _ in save() }
            .alert("Couldn’t clear demo data", isPresented: Binding(
                get: { dataError != nil }, set: { if !$0 { dataError = nil } }
            )) { Button("OK") { dataError = nil } } message: {
                Text(LocalizedStringKey(dataError ?? ""))
            }
        }
    }

    private func save() { try? modelContext.save() }
}

private struct SiriAccessSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [SiriAccessSettings]
    @Query private var courses: [CourseRecord]
    @Query private var gradeItems: [GradeItem]
    private var settings: SiriAccessSettings? { records.first }
    @State private var indexStatus = "Not verified"
    @State private var diagnosticStatus = "Not verified"
    @State private var lastSiriEvent = "No execution recorded"

    var body: some View {
        Form {
            if let settings {
                @Bindable var settings = settings
                Section("Access") {
                    Toggle("Enable Siri Access", isOn: $settings.isSiriAccessEnabled)
                    Toggle("Allow Assignment Summaries", isOn: $settings.allowAssignmentSummaries).disabled(!settings.isSiriAccessEnabled)
                    Toggle("Allow Detailed Scores", isOn: $settings.allowDetailedScores).disabled(!settings.isSiriAccessEnabled)
                    Toggle("Allow GPA Responses", isOn: $settings.allowGPAResponses).disabled(!settings.isSiriAccessEnabled)
                    Toggle("Allow Creating Drafts", isOn: $settings.allowCreatingDrafts).disabled(!settings.isSiriAccessEnabled)
                }
                Section("Try Siri") {
                    Text("You do not need to create a Shortcut. Try: “What assignments are due this week in Aggie GPA?”, “What is my current grade in CHE 002A?”, or “Open CHE 002A.”")
                }
                Section("Siri Diagnostics") {
                    LabeledContent("App Intents", value: "Registered after app launch")
                    LabeledContent("Courses", value: "\(courses.filter { !$0.isDeleted }.count)")
                    LabeledContent("Assignments and exams", value: "\(gradeItems.count)")
                    LabeledContent("Search index", value: indexStatus)
                    LabeledContent("Data access", value: diagnosticStatus)
                    LabeledContent("Last Siri execution", value: lastSiriEvent)
                    Button("Rebuild Search Index") {
                        Task {
                            do {
                                try await SiriSpotlightIndex.rebuildAll()
                                indexStatus = "Working"
                            } catch {
                                indexStatus = "Needs attention"
                            }
                        }
                    }
                    Button("Run Siri Diagnostics") {
                        Task {
                            do {
                                _ = try await AppIntentDataService.shared.courses(ids: nil)
                                diagnosticStatus = "Working"
                            } catch {
                                diagnosticStatus = "Needs attention"
                            }
                        }
                    }
                    Link("Open App Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                }
                Section { Text("Private intents require local device authentication. Draft intents never change scores until you confirm inside Aggie GPA.").font(.footnote).foregroundStyle(.secondary) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Siri AI")
        .task {
            if settings == nil { modelContext.insert(SiriAccessSettings()); try? modelContext.save() }
            refreshLastSiriEvent()
        }
        .onDisappear { settings?.updatedAt = .now; try? modelContext.save() }
    }

    private func refreshLastSiriEvent() {
        guard let event = SiriExecutionTrace.latestIntentExecution() ?? SiriExecutionTrace.latest() else {
            lastSiriEvent = "No execution recorded"
            return
        }
        let count = event.itemCount.map { " · \($0) item\($0 == 1 ? "" : "s")" } ?? ""
        lastSiriEvent = "\(event.stage)\(count)"
    }
}

private struct NotificationSettingsView: View {
    @State private var status = "Checking…"
    var body: some View {
        Form {
            Section("Permission") {
                LabeledContent("Status", value: status)
                Button("Request Notification Permission") {
                    Task {
                        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
                        await refresh()
                    }
                }
            }
            Section { Text("Changing a due date updates its reminder. Deleting an item cancels it. If permission is denied, the gradebook continues to work normally.").font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle("Reminders")
        .task { await refresh() }
    }

    private func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        status = switch settings.authorizationStatus {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .provisional: "Provisional"
        case .ephemeral: "Temporary"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
}

private struct DecimalPreferenceField: View {
    let title: String
    @Binding var value: Decimal
    let range: ClosedRange<Decimal>
    @State private var text = ""

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .onAppear { text = DecimalFormatters.compact(value) }
            .onChange(of: text) { _, newValue in
                if let decimal = DecimalFormatters.decimal(from: newValue), range.contains(decimal) { value = decimal }
            }
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AcademicTerm.sortOrder) private var terms: [AcademicTerm]
    @Query private var courses: [CourseRecord]
    @Query(sort: \PlannerScenario.sortOrder) private var scenarios: [PlannerScenario]
    @Query(sort: \BackupSnapshot.createdAt, order: .reverse) private var snapshots: [BackupSnapshot]
    @Query private var gradePlans: [CourseGradePlan]
    @Query private var gradingPolicies: [CourseGradingPolicy]
    @Query private var gradingCategories: [GradingCategory]
    @Query private var gradeItems: [GradeItem]
    @Query private var gradeScales: [GradeScale]
    @Query private var forecasts: [ForecastScenario]
    @Query private var siriSettings: [SiriAccessSettings]
    let preferences: UserPreferences

    @State private var jsonDocument = JSONBackupDocument()
    @State private var csvDocument = CSVExportDocument(text: "")
    @State private var exportingJSON = false
    @State private var exportingCSV = false
    @State private var importing = false
    @State private var importPreview: ImportPreview?
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var confirmReset = false
    @State private var shareURL: URL?

    var body: some View {
        List {
            Section("Export") {
                Button("Export JSON Backup", systemImage: "doc.badge.arrow.up") { prepareJSONExport() }
                    .accessibilityIdentifier("exportJSONButton")
                Button("Export CSV", systemImage: "tablecells") { prepareCSVExport() }
                if let shareURL {
                    ShareLink(item: shareURL, subject: Text("Aggie GPA Backup"), message: Text("Offline backup from Aggie GPA")) {
                        Label("Share latest JSON backup", systemImage: "square.and.arrow.up")
                    }
                }
            }
            Section("Import") {
                Button("Import JSON Backup", systemImage: "doc.badge.arrow.down") { importing = true }
            }
            Section("Local snapshots") {
                if snapshots.isEmpty { Text("No automatic snapshots yet").foregroundStyle(.secondary) }
                ForEach(snapshots) { snapshot in
                    VStack(alignment: .leading) {
                        Text(snapshot.reason).font(.headline)
                        Text(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("Up to five small JSON snapshots are retained on this device. A snapshot is created before imports and resets.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Danger Zone") {
                Button("Reset All Academic Data", role: .destructive) { confirmReset = true }
            }
            if let statusMessage { Section { Text(LocalizedStringKey(statusMessage)).foregroundStyle(.secondary) } }
        }
        .navigationTitle("Data & Backups")
        .onAppear { prepareShareFile() }
        .fileExporter(isPresented: $exportingJSON, document: jsonDocument, contentType: .json,
                      defaultFilename: "Aggie-GPA-Backup") { handleExport($0) }
        .fileExporter(isPresented: $exportingCSV, document: csvDocument, contentType: .commaSeparatedText,
                      defaultFilename: "Aggie-GPA-Courses") { handleExport($0) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let envelope = try BackupService.decode(data)
                importPreview = BackupService.preview(envelope, existingTerms: terms, existingCourses: courses)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "The backup could not be read. Your current data was not changed."
            }
        }
        .confirmationDialog("Import backup", isPresented: Binding(
            get: { importPreview != nil }, set: { if !$0 { importPreview = nil } }
        ), titleVisibility: .visible) {
            Button("Merge") { applyImport(.merge) }
            Button("Replace Current Data", role: .destructive) { applyImport(.replace) }
            Button("Cancel", role: .cancel) { importPreview = nil }
        } message: {
            if let preview = importPreview {
                Text("\(preview.envelope.terms.count) quarters, \(preview.envelope.courses.count) courses, and \(preview.envelope.plannerScenarios.count) scenarios. Potential duplicates: \(preview.duplicateTermCount) quarters and \(preview.duplicateCourseCount) courses.")
            }
        }
        .confirmationDialog("Reset all academic data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Create Snapshot and Reset", role: .destructive) { resetAllData() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Quarters, courses, scenarios, and grade plans will be removed. Your profile settings remain.") }
        .alert("Couldn’t complete that action", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(LocalizedStringKey(errorMessage ?? "Please try again.")) }
    }

    private var envelope: BackupEnvelope {
        BackupService.makeEnvelope(terms: terms, courses: courses, scenarios: scenarios, preferences: preferences,
                                   policies: gradingPolicies, categories: gradingCategories, items: gradeItems,
                                   scales: gradeScales, forecasts: forecasts, siriSettings: siriSettings.first)
    }

    private func prepareJSONExport() {
        do { jsonDocument = JSONBackupDocument(data: try BackupService.encode(envelope)); exportingJSON = true }
        catch { errorMessage = "The JSON backup could not be created. Your data is unchanged." }
    }

    private func prepareCSVExport() {
        csvDocument = CSVExportDocument(text: CSVService.export(terms: terms, courses: courses)); exportingCSV = true
    }

    private func prepareShareFile() {
        do {
            let url = FileManager.default.temporaryDirectory.appending(path: "Aggie-GPA-Backup.json")
            try BackupService.encode(envelope).write(to: url, options: .atomic)
            shareURL = url
        } catch { shareURL = nil }
    }

    private func handleExport(_ result: Result<URL, any Error>) {
        switch result { case .success: statusMessage = "Export completed."; case .failure: errorMessage = "The export was cancelled or the destination was unavailable." }
    }

    private func applyImport(_ mode: ImportMode) {
        guard let preview = importPreview else { return }
        do {
            try SnapshotService.create(envelope: envelope, reason: "Before import", context: modelContext, existing: snapshots)
            try BackupService.apply(preview.envelope, mode: mode, context: modelContext,
                                    existingTerms: terms, existingScenarios: scenarios, preferences: preferences)
            statusMessage = "Import completed. A pre-import snapshot was saved."
            importPreview = nil
            prepareShareFile()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Import failed. Your existing data was preserved."
        }
    }

    private func resetAllData() {
        do {
            try SnapshotService.create(envelope: envelope, reason: "Before reset", context: modelContext, existing: snapshots)
            let notificationIdentifiers = gradeItems.map(\.notificationIdentifier)
            gradeItems.forEach(modelContext.delete)
            gradingCategories.forEach(modelContext.delete)
            gradingPolicies.forEach(modelContext.delete)
            gradeScales.forEach(modelContext.delete)
            forecasts.forEach(modelContext.delete)
            scenarios.forEach(modelContext.delete)
            gradePlans.forEach(modelContext.delete)
            terms.forEach(modelContext.delete)
            preferences.demoDataLoaded = false
            try modelContext.save()
            notificationIdentifiers.forEach { GradeItemNotificationService.cancel(identifier: $0) }
            statusMessage = "Academic data reset. A local snapshot was created first."
        } catch {
            modelContext.rollback()
            errorMessage = "Reset could not be completed. Your existing data was preserved."
        }
    }
}

private struct InformationPage: View {
    let title: LocalizedStringKey
    let text: LocalizedStringKey
    var body: some View {
        ScrollView { Text(text).frame(maxWidth: .infinity, alignment: .leading).padding() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
