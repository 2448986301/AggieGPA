# AI syllabus import — 1.3.0

## Processing boundary

Aggie GPA uses PDFKit to preserve native PDF text per page. For scanned PDF pages,
camera scans, and images, it renders or receives an image and sends that image
directly to the current iOS Foundation Models multimodal attachment API. The app
does not import Vision or use `VNRecognizeTextRequest`, `RecognizeTextRequest`,
or any other OCR SDK.

The system language model is the default. Its availability, language support, and
vision capability are checked before a request. If it cannot analyze the document,
the app does not attempt to bypass Apple safety guardrails. For a text-native
document that is declined by the model, it automatically runs the deterministic
local rule parser and labels the resulting draft as local rule recognition. This
fallback does not use OCR or a network service; it cannot recover text from a
scanned image page.

## Privacy and confirmation

Syllabus content is treated as untrusted data. Model instructions explicitly ignore
document attempts to alter the app, request private data, or execute actions. PCC is
not a release claim: it is shown only after a distinct in-app permission and only
when Apple-managed entitlement and runtime availability checks succeed.

All model results are drafts. Page evidence, confidence, conflicts, and non-100%
weight totals are visible before confirmation. SwiftData is not changed during
selection, reading, analysis, cancellation, or review. Confirm Import is the only
write boundary; it adds reviewed records without overwriting existing course data.

## Validation limits

Build and unit tests verify the confirmation boundary and absence of Vision OCR.
Simulator cannot establish a real Apple Intelligence model result. A real iPhone
with Apple Intelligence enabled remains required to verify actual on-device model
availability and a complete visual document-analysis walkthrough.
