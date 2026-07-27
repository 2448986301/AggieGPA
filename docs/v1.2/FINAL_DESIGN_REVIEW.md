# Aggie GPA 1.2 final design review

Review date: 2026-07-28

## Design-system result

The iPhone app now uses the same hierarchy across its student-facing flows:

- System typography with Dynamic Type-friendly vertical layouts.
- Shared spacing and continuous corner radii from `DesignSystem`.
- Gold only for meaningful emphasis and actions; semantic system colors for success,
  warning, and error states.
- SF Symbols that describe the action or state, with decorative symbols hidden from
  VoiceOver where appropriate.
- Liquid Glass reserved for navigation, top summaries, and floating actions. Forms,
  lists, grade items, and release notes remain native, lightweight surfaces.

## Surface review

| Area | Result |
| --- | --- |
| Today | Student-first summary, quick add, native empty states, and selected-tab navigation are aligned. |
| Courses and Course Detail | Term summary geometry, current grade, next work, grade breakdown, categories, and advanced paths use the shared hierarchy. |
| Grade entry | Assignment, exam, and score sheets prioritize required fields, keep Save reachable, expose categories, and avoid layered glass. |
| GPA | Official and estimated results are grouped with plain-language labels; current and historical values are visually distinct. |
| Settings and support | Settings follows student tasks; syllabus import, Siri drafts, backup, What-If, and global feedback use native Form, Alert, and Sheet patterns. |
| Release notes | Settings > About > What’s New uses List, Section, DisclosureGroup, and a compact single-use sheet rather than stacked cards. |

## Accessibility and adaptation

- The release-note sheet and history use semantic Labels and readable list rows.
- The onboarding symbol effect honors Reduce Motion.
- Content surfaces become more opaque when Reduce Transparency is enabled.
- Current release-note UI has targeted UI coverage at the largest accessibility text
  category, plus English and Simplified Chinese simulator checks.
- Full VoiceOver traversal and every hardware/device permutation remain a manual
  release validation responsibility; no unsupported claim is made here.

## Review findings resolved in 1.2

- Eliminated double Liquid Glass in grade-entry and save-action surfaces.
- Aligned term GPA summary geometry with course-list content.
- Clarified category selection and grade-entry context for custom categories.
- Corrected GPA wording and Chinese hierarchy for official versus estimated values.
- Added semantic loading, success, and error feedback to supporting workflows.
- Ensured the first-update sheet receives the selected in-app language environment.
