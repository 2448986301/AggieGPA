# Localization audit

## Catalog migration status

`Localizable.xcstrings` is now the single source of truth. Xcode extracted 463 active SwiftUI strings from the app, and 276 matching entries from the retired `zh-Hans.lproj/Localizable.strings` were mechanically preserved. The catalog now contains 500 entries: all 463 extracted entries plus 37 manually cataloged persisted-enum and status values used by pickers and grade items. Every entry has a translated `zh-Hans` value, including accessibility labels, Siri and Shortcuts phrasing, score-entry confirmation, backup summaries, and format-only values.

The student-first shell is translated: Today, Courses, GPA, Settings, global Add, course-detail progress, score entry, and the core GPA summary. Existing settings, import, calculation, and legacy planner phrases were retained where their source key still matched. New or changed phrases must not fall back silently before release.

## Release verification status

- Catalog coverage is complete: 500/500 entries have a usable English source key and a `zh-Hans` value. JSON validation is part of the release check so malformed catalog edits cannot ship.
- English and `zh-Hans` smoke checks cover Today, the global Add flow, the course-detail gradebook, visible grade-item statuses, score entry, GPA, and Settings on iPhone 17 Pro Simulator. Continue the visual matrix for empty and error states, Dynamic Type, and light/dark appearance whenever those screens change.
- Keep dates, decimal separators, percentages, and unit counts driven by the environment locale rather than translated format strings.
- Re-run extraction after every new UI string is added; do not reintroduce an `.lproj` table beside the catalog.
