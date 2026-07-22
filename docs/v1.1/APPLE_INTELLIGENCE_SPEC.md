# Apple Intelligence Specification

Foundation Models is an optional device-side enhancement after local text extraction. Where the iOS 27 SDK exposes `SystemLanguageModel`, use compile-time and runtime availability checks and structured/guided output to propose categories, weights, points, boundaries, drop rules, and complexity flags.

Every model result is treated as untrusted candidate data and passes deterministic validation plus user confirmation. Unavailable hardware, disabled Apple Intelligence, unsupported language, or generation failure falls back without losing functionality:

`SystemLanguageModel` candidate parser → PDFKit/Vision text → local rule parser → manual entry.

Foundation Models is never the only implementation. The app does not request Private Cloud Compute entitlements, claim control over Apple internal models, use paid or remote AI, or upload syllabus content.
