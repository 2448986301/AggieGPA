# Product Specification

## Goal

Aggie GPA v1.1.0 extends the installed v1.0 with a per-course gradebook, forecasts, syllabus-assisted setup, reminders, App Intents, Siri, Spotlight, and Shortcuts while preserving every v1.0 feature and record. The app identity, bundle identifier, navigation, icon, and local-first privacy model remain unchanged.

## Core user journey

The first release-quality vertical slice is:

1. Open an existing course.
2. Configure Homework, Midterm, and Final categories.
3. Add a homework item and record earned/possible points.
4. See graded-work average and earned course credit from the shared engine.
5. Create a non-destructive forecast and projected letter grade.
6. Opt the projection into GPA Planner without changing official GPA.
7. Ask Siri for the same calculated course result.

## Product principles

- Official, calculated, projected, What-If, and planner-selected grades are distinct concepts.
- Ambiguous rules produce `Manual Review Required`, not false precision.
- Syllabus/OCR/model output is always a draft preview that the user verifies.
- Siri writes create drafts and require confirmation; destructive intents do not exist.
- Data stays on device unless the user explicitly exports a file.
- v1.0 compatibility and recoverability take priority over convenience.

Detailed behavior is defined by `GRADEBOOK_SPEC.md`, `CALCULATION_SPEC.md`, `SYLLABUS_IMPORT_SPEC.md`, `APPLE_INTELLIGENCE_SPEC.md`, `APP_INTENTS_SPEC.md`, `NOTIFICATIONS_SPEC.md`, `DATA_MIGRATION_SPEC.md`, and `UI_UX_SPEC.md`. Completion is governed by `ACCEPTANCE_CRITERIA.md`.
