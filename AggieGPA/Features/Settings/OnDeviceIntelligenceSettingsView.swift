import SwiftUI

struct OnDeviceIntelligenceSettingsView: View {
    @Environment(\.locale) private var locale
    @State private var snapshot: AIModelStoreSnapshot?
    @State private var progress: ModelDownloadProgress?
    @State private var operationTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Active Model") {
                if let active = snapshot?.activeRecord {
                    modelSummary(active)
                } else {
                    Label("No model selected", systemImage: "cpu")
                        .foregroundStyle(.secondary)
                    Text("Download a model and choose it below. The app remains fully usable without one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Model Library") {
                ForEach(snapshot?.records ?? []) { record in
                    modelRow(record)
                }
            }

            Section("Power Preference") {
                Picker("Power Preference", selection: powerPreferenceBinding) {
                    Text("Prefer Battery Life").tag(AIPowerPreference.preferBatteryLife)
                    Text("Balanced").tag(AIPowerPreference.balanced)
                    Text("Prefer Quality").tag(AIPowerPreference.preferQuality)
                }
                .accessibilityIdentifier("aiPowerPreferencePicker")
                Toggle("Use Enhanced Model Only While Charging", isOn: chargingOnlyBinding)
                Text("Low Power Mode and serious thermal state can temporarily use a smaller downloaded model. Aggie GPA always tells you when that happens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Storage Used", value: storageUsedLabel)
                    .accessibilityIdentifier("aiStorageUsed")
                LabeledContent("Model Budget", value: storageBudgetLabel)
                Text("Models are stored outside the app bundle and excluded from device backups. Removing a model never removes course data.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let progress {
                Section("Download Progress") {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView()
                    }
                    Text(downloadProgressLabel(progress))
                        .font(.footnote)
                        .monospacedDigit()
                }
            }
        }
        .navigationTitle("On-Device Intelligence")
        .accessibilityIdentifier("onDeviceIntelligenceScreen")
        .task { await refresh() }
        .onDisappear {
            operationTask?.cancel()
            operationTask = nil
        }
        .alert("Model Manager", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var powerPreferenceBinding: Binding<AIPowerPreference> {
        Binding(
            get: { snapshot?.powerPreference ?? .balanced },
            set: { value in
                operationTask?.cancel()
                operationTask = Task {
                    await AIModelStore.shared.setPowerPreference(value)
                    await refresh()
                }
            }
        )
    }

    private var chargingOnlyBinding: Binding<Bool> {
        Binding(
            get: { snapshot?.useEnhancedOnlyWhileCharging ?? true },
            set: { value in
                operationTask?.cancel()
                operationTask = Task {
                    await AIModelStore.shared.setUseEnhancedOnlyWhileCharging(value)
                    await refresh()
                }
            }
        )
    }

    @ViewBuilder
    private func modelRow(_ record: AIModelRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(record.descriptor.tier.displayName)
                    .font(.headline)
                Spacer()
                if snapshot?.activeModelID == record.id, record.state == .ready {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tint)
                }
            }
            Text(record.descriptor.modelName)
            LabeledContent("Quantization", value: record.descriptor.quantization)
            LabeledContent("Download Size", value: record.descriptor.storageLabel)
            LabeledContent("Status", value: statusLabel(record))
            if let lastUsedAt = record.lastUsedAt {
                LabeledContent("Last Used", value: lastUsedAt.formatted(date: .abbreviated, time: .shortened))
            }

            HStack {
                switch record.state {
                case .notInstalled, .failed:
                    Button(isFailed(record) ? "Retry" : "Download", systemImage: "arrow.down.circle") {
                        download(record.descriptor)
                    }
                case .downloading:
                    Button("Pause", systemImage: "pause.circle") { pause(record.id) }
                    Button("Cancel", systemImage: "xmark.circle") { cancel(record.id) }
                case .paused:
                    Button("Resume", systemImage: "play.circle") { download(record.descriptor) }
                    Button("Cancel", systemImage: "xmark.circle") { cancel(record.id) }
                case .ready:
                    if snapshot?.activeModelID != record.id {
                        Button("Use This Model", systemImage: "checkmark.circle") { activate(record.id) }
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) { remove(record.id) }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("aiModelRow-\(record.id)")
    }

    private func modelSummary(_ record: AIModelRecord) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(record.descriptor.modelName, systemImage: "cpu.fill")
                .font(.headline)
            Text("\(record.descriptor.tier.displayName) · \(record.descriptor.quantization)")
                .foregroundStyle(.secondary)
            Text("Local inference is off until an analysis starts.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var storageUsedLabel: String {
        ByteCountFormatter.string(fromByteCount: snapshot?.storageUsedBytes ?? 0, countStyle: .file)
    }

    private var storageBudgetLabel: String {
        ByteCountFormatter.string(fromByteCount: snapshot?.storageBudgetBytes ?? AIModelStore.storageBudgetBytes, countStyle: .file)
    }

    private func statusLabel(_ record: AIModelRecord) -> String {
        switch record.state {
        case .notInstalled: "Not Downloaded"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .ready: "Downloaded"
        case .failed(let message): message
        }
    }

    private func isFailed(_ record: AIModelRecord) -> Bool {
        if case .failed = record.state { return true }
        return false
    }

    private func refresh() async {
        snapshot = await AIModelStore.shared.snapshot()
    }

    private func download(_ descriptor: AIModelDescriptor) {
        operationTask?.cancel()
        errorMessage = nil
        progress = .starting
        operationTask = Task {
            do {
                _ = try await AIModelStore.shared.download(descriptor: descriptor) { value in
                    Task { @MainActor in progress = value }
                }
                await refresh()
                progress = nil
            } catch is CancellationError {
                await refresh()
            } catch let error as AIModelStoreError {
                await refresh()
                errorMessage = error.message(locale: locale)
            } catch {
                await refresh()
                errorMessage = error.localizedDescription
            }
        }
    }

    private func pause(_ id: String) {
        operationTask = Task {
            await AIModelStore.shared.pauseDownload(id: id)
            await refresh()
        }
    }

    private func cancel(_ id: String) {
        operationTask = Task {
            await AIModelStore.shared.cancelDownload(id: id)
            await refresh()
            progress = nil
        }
    }

    private func activate(_ id: String) {
        operationTask = Task {
            do {
                _ = try await OnDeviceAIModelLibrary.setActiveModel(id: id)
                await refresh()
            } catch let error as AIModelStoreError {
                errorMessage = error.message(locale: locale)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ id: String) {
        operationTask = Task {
            do {
                try await OnDeviceAIModelLibrary.remove(id: id)
                await refresh()
            } catch let error as AIModelStoreError {
                errorMessage = error.message(locale: locale)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func downloadProgressLabel(_ value: ModelDownloadProgress) -> String {
        let received = ByteCountFormatter.string(fromByteCount: value.receivedBytes, countStyle: .file)
        let expected = ByteCountFormatter.string(fromByteCount: value.expectedBytes, countStyle: .file)
        let percent = Int(((value.fraction ?? 0) * 100).rounded())
        return String(format: "%lld%% · %@ of %@", Int64(percent), received, expected)
    }
}
