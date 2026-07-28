# English and Simplified Chinese localization baseline audit

Date: 2026-07-22  
Scope: pre-v1.1.2 source and automated-test audit. This document does not claim visual completion.

## What is present

- `AggieGPA/Resources/Localizable.xcstrings` is the only active catalog. It has 500 source keys and 500 non-empty, `translated` `zh-Hans` entries.
- The project declares English as the development region and `zh-Hans` as a known region.
- The UI selects `UserPreferences.language.locale` for its SwiftUI environment and exposes System, English, and Simplified Chinese choices in Settings.
- The simulator and signed device builds compile the catalog successfully.

## Findings

| Area | Finding | Severity | Required v1.1.2 action |
| --- | --- | --- | --- |
| Intent responses | Course grade, GPA, target-score, list, error, and open-result responses are assembled as English runtime strings. | P0 | Replace with typed bilingual response builders using localized format resources and `FormatStyle`. |
| Intent metadata | Titles and parameter summaries have catalog translations, but there is no test that extracted `en` and `zh-Hans` metadata uses the intended locale. | P1 | Add metadata assertions and locale-specific phrase tests. |
| Shortcut phrases | Every shortcut’s Chinese and English phrase is emitted into both language corpora. | P0 | Define separate natural language phrases per locale; test generated metadata. |
| Student settings | The user-facing entry says “Siri & Shortcuts” and includes an “Open Shortcuts” link. | P1 | Rename/reframe as “Siri AI”; do not present Shortcuts as necessary for direct use. |
| Terms | Existing catalog terminology predates the required v1.1.2 glossary and mixes “Quarter” with app strings that refer to course terms. | P1 | Add the canonical v1.1.2 glossary and align UI, entity, dialog, notification, and diagnostic copy. |
| App language | The in-app picker changes SwiftUI locale. It is not yet tested across navigation, alerts, sheets, notifications, or App Intents, and it is not documented relative to iOS Per-App Language. | P1 | Add visual matrix and clarify supported system Per-App Language behavior; do not claim complete switching yet. |
| Dynamic values | Several views and all current Siri responses use string interpolation rather than locale-aware plural/date/number format resources. | P1 | Convert counts, scores, dates, and percentage/GPA wording to locale-aware formatters and plural catalog variations. |
| Dynamic Type / VoiceOver | One existing UI test opens the gradebook at a large accessibility size. There is no full bilingual Dynamic Type or VoiceOver audit. | P1 | Add per-language UI/accessibility checks for requested settings, gradebook, confirmation, empty/error, and diagnostics screens. |
| Notifications and errors | Existing catalog contains many translated UI strings, but notification and runtime error output do not have a complete locale test matrix. | P1 | Audit notification text, deep-link errors, draft errors, and Siri settings diagnostics. |

## Coverage that remains unverified

The following surfaces have not been actually exercised in both languages in this baseline: onboarding, Today, Courses, course/item detail, adding items, score recording, grade breakdown, GPA/forecast, syllabus import, backups, privacy/Face ID, Siri settings, empty states, validation errors, notifications, and all App Intent dialogues.

The existing automated test suite does not contain a launch with `AppleLanguages`, an explicit `Locale(identifier: "zh-Hans")` test mode, English/Chinese screenshots, a spoken Siri test, or a localization completeness test for dynamically constructed output.

## Acceptance strategy

1. Preserve the single string catalog and move all newly user-visible text, including App Intent metadata and error/dialog templates, into it.
2. Use `Date.FormatStyle`, `Measurement`/number formatting, and catalog plural variations rather than sentence concatenation.
3. Add a v1.1.2 glossary before changing strings, then audit each requested page in English and Simplified Chinese.
4. Run English and `zh-Hans` UI tests plus visual checks at standard and accessibility text sizes. Record truncation, VoiceOver, empty/error, and notification outcomes.
5. Treat Siri language output as separately unverified until user-spoken physical-iPhone results are captured.

