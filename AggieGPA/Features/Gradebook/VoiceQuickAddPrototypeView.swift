import Foundation
import SwiftUI

/// A visible, audit-gated Phase 10 boundary. It demonstrates the complete
/// transcript-to-preview handoff without pretending that simulator speech or
/// an unmeasured microphone dependency is production-ready.
struct VoiceQuickAddPrototypeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    let courses: [CourseRecord]
    let onContinue: (String) -> Void

    @State private var transcript = ""
    @State private var result: VoiceQuickAddPrototypeResult?
    @State private var showAuditNotice = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.large) {
                    AppSection("Hold to Speak") {
                        Button {
                            showAuditNotice = true
                        } label: {
                            Label("Hold to Speak", systemImage: "waveform")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .accessibilityIdentifier("voiceHoldToSpeakButton")

                        Text(AppCopy.voiceEntryNote(locale: locale))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    AppSection("Transcript", subtitle: "Say one sentence with the course, title, deadline, points, and reminder.") {
                        TextEditor(text: $transcript)
                            .frame(minHeight: 110)
                            .padding(DesignSystem.Spacing.small)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: DesignSystem.Radius.compact, style: .continuous)
                                    .strokeBorder(.primary.opacity(0.09), lineWidth: 1)
                            }
                            .accessibilityIdentifier("voiceTranscriptInput")
                            .overlay(alignment: .topLeading) {
                                if transcript.isEmpty {
                                    Text("CHE Lab 4 Friday 11:59 PM, 20 points, remind me one day before.\nCHE实验4周五晚上11:59截止，20分，提前一天。")
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, DesignSystem.Spacing.medium)
                                        .padding(.vertical, DesignSystem.Spacing.small + 2)
                                        .allowsHitTesting(false)
                                }
                            }

                        Button("Preview Transcript", systemImage: "text.magnifyingglass") {
                            preview()
                        }
                        .buttonStyle(.bordered)
                        .disabled(transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("voicePreviewButton")
                    }

                    if let result {
                        previewSection(result)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.large)
                .padding(.vertical, DesignSystem.Spacing.medium)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Voice Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert(AppCopy.voiceEntryUnavailableTitle(locale: locale), isPresented: $showAuditNotice) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(AppCopy.voiceEntryUnavailableMessage(locale: locale))
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func previewSection(_ value: VoiceQuickAddPrototypeResult) -> some View {
        AppSection("Preview", subtitle: "Nothing is saved until you confirm in Quick Add.") {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.small) {
                LabeledContent("Course", value: value.draft.courseCode.isEmpty ? "—" : value.draft.courseCode)
                LabeledContent("Title", value: value.draft.title.isEmpty ? "—" : value.draft.title)
                LabeledContent("Type") {
                    Text(value.draft.type.rawValue)
                }
                LabeledContent("Due date", value: value.draft.dueDate.map(dateLabel) ?? "Not set")
                LabeledContent("Possible points", value: value.draft.possiblePoints.map(DecimalFormatters.compact) ?? "Not set")
                LabeledContent("Reminder", value: reminderLabel(value.draft.reminderLeadTimeHours))
                LabeledContent("Source", value: AppLocalization.string("Manual fallback", locale: locale))
                    .foregroundStyle(.secondary)

                if !value.draft.warnings.isEmpty {
                    ForEach(value.draft.warnings, id: \.self) { warning in
                        Label(AppLocalization.string(warning, locale: locale), systemImage: "exclamationmark.circle")
                            .foregroundStyle(DesignSystem.ColorToken.warning)
                    }
                } else {
                    Label("Ready for review", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(DesignSystem.ColorToken.success)
                }

                Button("Continue to Quick Add", systemImage: "arrow.right") {
                    onContinue(value.transcript)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("voiceContinueToQuickAdd")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("voiceDraftPreview")
        }
    }

    private func preview() {
        let value = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        result = VoiceQuickAddPrototype.preview(
            transcript: value,
            referenceDate: .now,
            availableCourseCodes: courses.map(\.courseCode)
        )
    }

    private func dateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func reminderLabel(_ hours: Int?) -> String {
        guard let hours else { return AppLocalization.string("Not set", locale: locale) }
        if hours % 24 == 0 {
            return String(format: AppLocalization.string("%@ day(s) before", locale: locale), "\(hours / 24)")
        }
        return String(format: AppLocalization.string("%@ hour(s) before", locale: locale), "\(hours)")
    }
}
