# Localization audit

## Catalog migration status

`Localizable.xcstrings` is now the single source of truth. Xcode extracted 462 active SwiftUI strings from the app, and 276 matching entries from the retired `zh-Hans.lproj/Localizable.strings` were mechanically preserved. The resulting catalog currently contains 350 translated zh-Hans entries and 112 entries that still need product-language review or translation.

The student-first shell is translated: Today, Courses, GPA, Settings, global Add, course-detail progress, score entry, and the core GPA summary. Existing settings, import, calculation, and legacy planner phrases were retained where their source key still matched. New or changed phrases must not fall back silently before release.

## Required release audit

- Review each of the 112 untranslated catalog entries, prioritizing settings, syllabus import, advanced calculations, errors, and destructive confirmations.
- Verify English and zh-Hans on iPhone 17 Pro Simulator for Today, Add Assignment, course detail, grade breakdown, GPA, Settings, empty states, error states, and Dynamic Type.
- Confirm dates, decimal separators, percentages, and unit counts use the environment locale rather than translated format strings.
- Re-run the export after every new UI string is added; do not reintroduce an `.lproj` table beside the catalog.
