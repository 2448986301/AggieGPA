# Test Plan

> Execution status (2026-07-22): 84 unit tests pass on iPhone 17 Pro Simulator. The 18-test UI suite covers the critical v1.0 flows plus gradebook entry, syllabus review, Siri-default privacy, Accessibility XXXL, demo-data cleanup, and deletion navigation. On the iPhone mirror, both existing Fall 2026 terms opened and returned to the list without a crash. Real-device Siri speech recognition and notification authorization remain manual checks.

All engines use deterministic value inputs and exhaustive unit tests. Persistent features use in-memory containers plus v1.0-compatible disk fixtures. UI tests run serially on Xcode 27 beta because the baseline parallel runner can remove the application bundle between simulator clones.

## Required suites

- Calculation: weighted, total-points, hybrid, equal-items, category points, ungraded/missing/excused/dropped/drop-lowest, extra credit, override, multiplier, earned credit, weights under/over 100%, zero cases, empty book, above maximum, missing/different scales.
- Forecast/GPA: official separation, projected quarter/cumulative GPA, final/remaining needed, impossible target, best/worst, multiple remaining items, invalid-policy manual review.
- Syllabus: common percentage/point forms, drops/replacement, conflicts, low OCR confidence, confirmation boundary, model fallback, failed parse preserving policy.
- Migration/backup: terms/courses/official grades/GPA/settings/path preserved, rollback, schema v1 import, schema v2 round trip.
- App Intents: stable IDs and course normalization, ambiguity, calendar/time-zone boundaries, deleted entities, shared-engine parity, authentication/settings gates, draft confirmation, deep links, shortcut discovery, empty state.
- Notifications: create/update/delete/deduplicate, denied permission, deep-link response.
- UI: existing course, category/item/exam entry, score, forecast/import/confirmation, Upcoming/Attention, undo, dark mode, Dynamic Type, and Siri draft confirmation.

Every phase runs targeted tests and a project build. Phase 12 runs a clean build, all unit tests, serial UI tests, migration fixture tests, and records any manual device-only verification separately.
