import Foundation

/// Phase 10 keeps the voice boundary deliberately audit-gated. This small
/// prototype owns the post-transcription hand-off so a future approved STT
/// adapter can feed the same preview-first parser without adding microphone,
/// network, or model side effects to the current release.
nonisolated struct VoiceQuickAddPrototypeResult: Equatable, Sendable {
    let transcript: String
    let draft: NaturalLanguageQuickAddDraft

    var requiresConfirmation: Bool { true }
}

nonisolated enum VoiceQuickAddPrototype {
    static let auditStatus = "prototype-only"
    static let flow = [
        "Hold to Speak",
        "On-device speech-to-text",
        "Local parser",
        "Preview",
        "Confirm"
    ]

    /// Converts an externally supplied transcript into the existing editable
    /// Quick Add draft. Audio capture and speech-model loading are intentionally
    /// not hidden here; they remain disabled until the Phase 10 device audit
    /// approves a production STT adapter.
    static func preview(
        transcript: String,
        referenceDate: Date,
        availableCourseCodes: [String]
    ) -> VoiceQuickAddPrototypeResult {
        VoiceQuickAddPrototypeResult(
            transcript: transcript,
            draft: NaturalLanguageQuickAddParser.parse(
                transcript,
                referenceDate: referenceDate,
                availableCourseCodes: availableCourseCodes
            )
        )
    }
}
