# Syllabus Import Specification

## Inputs and pipeline

Accept Files PDFs, images/screenshots, camera scans, pasted text, and manual entry. Use only Apple-local PDFKit, Vision, VisionKit, NaturalLanguage, Foundation, and deterministic parsing.

Pipeline: extract text; locate grading sections; identify categories, weights, points, grade scale, drops, replacements, and extra credit; retain original text locally; produce editable candidates and confidence; validate numbers; show preview; require explicit confirmation; then save atomically.

The parser recognizes common forms such as `Homework: 20%`, `Homework (20%)`, `Two Midterms, 15% each`, `Midterm Exams: 30% total`, point totals, drop-lowest/best-N, final replacement, and extra credit.

Manual review is mandatory for totals other than 100%, mixed points and percentages, conflicts, replacement rules, curves, section-specific or multiple policies, low OCR confidence, ambiguous drops, and unclear extra credit. The review always says: “Please verify these rules against your syllabus.” No professor rule is silently changed.

No syllabus or OCR text is uploaded, logged to a remote service, exposed to App Intents, or included in unrelated exports.
