# Siri AI baseline audit

Date: 2026-07-22  
Scope: pre-implementation audit for `feature/v1.1.2-direct-siri-ai`.

> Historical baseline: the audit below records the state before the direct-Siri work. It is intentionally preserved. The verified device status as of 2026-07-23 is summarized here so the baseline is not mistaken for the current result.

## Current verified delta — 2026-07-23

- The current source version is Aggie GPA 1.1.2 build 13 on `feature/v1.1.2-direct-siri-ai`. The unchanged bundle identifier is `com.easonzhou.aggiegpa`.
- Xcode 27.0 beta build `27A5228h` and the iOS 27.0 SDK are in use. The connected physical iPhone is an iPhone 17 Pro on iOS 27.0 build `24A5390f`.
- The app now has the App Group `group.com.easonzhou.aggiegpa`, a local read-only Siri snapshot, privacy-safe execution breadcrumbs, indexed course/assignment/exam entities, and pending navigation stored in the App Group.
- Build 11 verified one end-to-end custom App Shortcut route in the standalone Siri app. The exact phrase `View assignments in Aggie GPA` rendered an Aggie GPA card containing `Homework 3`, `CHE 002A`, and its due date. The device-side trace recorded `assignments-started`, `snapshot-read` with one item, and `assignments-completed` with one item.
- The build 11 native `.system.searchInApp` experiment and native `.system.open` experiment were both recognized by the build metadata, but the standalone Siri app rejected the tested requests before either intent's `perform()` ran. No schema-start trace was recorded.
- Build 12 changed only the search-schema experiment to legacy `.system.search` for an A/B test. Without rebooting the device, Siri again rejected the tested in-app search before `perform()` and recorded no schema-start trace. This does not prove behavior after reboot or on a later seed. Build 13 restores the official `.system.searchInApp` annotation; no build 13 device success is claimed yet.
- Spotlight now displays the indexed `CHE 002A` result under Aggie GPA. This proves Core Spotlight ingestion; it does not prove that the standalone Siri planner will select the native open/search schema.
- The installed iOS 27 SDK exposes no education/course/grade/GPA/homework App Schema. Grade, GPA, target-score, and assignment-summary answers therefore remain custom App Intents surfaced through automatic `AppShortcutsProvider` registration. No manually created user Shortcut is required, but this route is not the same as a native system App Schema.
- A current iOS 27 beta, Siri-language, region/account eligibility, or post-install registration delay may explain the schema rejection. That remains a hypothesis, not a verified cause.

For the current design, evidence, and limits, use `DIRECT_SIRI_DESIGN.md`, `APP_SCHEMA_MAPPING.md`, `REAL_DEVICE_SIRI_RESULTS.md`, and `SIRI_KNOWN_LIMITATIONS.md`.

## Repository and build baseline

| Item | Verified state |
| --- | --- |
| Repository root / worktree | `/Users/easonzhou/Documents/UCD` (the only registered worktree) |
| Branch / commit | `feature/v1.1.2-direct-siri-ai` at `704f243` |
| Baseline | `origin/feature/v1.1.1-student-first-ux` also points at `704f243`; this is the latest committed Student-First UX baseline available locally. `main` was not checked out or modified. |
| Remote | `origin` = `https://github.com/2448986301/AggieGPA.git` |
| Existing unrelated state | untracked `Tools/`; not inspected, changed, staged, or used by this work. |
| Version | `MARKETING_VERSION = 1.1.1`, `CURRENT_PROJECT_VERSION = 3`; v1.1.2 has not yet been set. Bundle ID remains `com.easonzhou.aggiegpa`. |
| Toolchain | Xcode 27.0 (27A5228h), iPhoneOS 27.0 SDK, deployment target iOS 27.0. |
| Simulator build | `xcodebuild clean build ... iPhone 17 Pro ... CODE_SIGNING_ALLOWED=NO` succeeded. |
| Automated tests | `xcodebuild test ... iPhone 17 Pro ...` succeeded: 84 unit tests and 18 UI tests, 0 failures. |
| Physical-iPhone build | A signed build for connected iPhone 17 Pro `6B77880E-E0E6-5571-A5D1-32BCB7E83F65` succeeded using the unchanged bundle ID and the configured Development Team. It was **not installed or launched**. |
| Real Siri result | Not verified. No direct Siri, Shortcuts manual execution, Spotlight, or device runtime result exists for this baseline. |

The validated regression tests cover the existing Student-First gradebook flow, score entry, migration, backup safety, the rule that ungraded work is not zero, and current Siri-draft payload storage. They do not establish Siri recognition, entity resolution, index lifecycle, the shared-store behavior of intents, or bilingual Siri output.

## Existing implementation

### App Intents and entities

The main app target contains five `AppEntity` values and `EntityStringQuery`/`EntityQuery` implementations:

- `CourseEntity`, `AssignmentEntity`, `ExamEntity`, `AcademicTermEntity`, and `GradeScenarioEntity`.
- Query and dialog code runs through `AppIntentDataService`.
- Existing query intents: upcoming assignments/exams, a course grade, official quarter GPA, official cumulative GPA, required percentage, and overdue items.
- Existing open intents: course, assignment, exam, and planner scenario.
- Existing write intents create assignment, exam, or score **draft payloads**, then open the app for a second, visible confirmation.
- `AggieGPAAppShortcuts` publishes eight App Shortcut phrases. Compilation generated App Intents metadata and NLU training assets for `en` and `zh-Hans`.
- Detailed-data intents use `.requiresLocalDeviceAuthentication`; the settings model also defaults all Siri data switches to off.

### SwiftData and privacy

The main app uses `PersistentStoreService.makeContainer`, which creates the versioned `AggieGPASchemaV2` container with the configuration name `AggieGPA`. The intent service independently constructs a `ModelContainer` using the same configuration name, but does not reuse that factory or explicitly assert the resolved store URL/schema. There is no App Group, entitlement file, or App Intents Extension target.

The current signed device build only carries the app identifier, team identifier, and debug entitlement. No cloud or App Group entitlement is present. This preserves the local-only data model, but the same-store guarantee for an App Intent launched outside the running UI is currently untested.

### Navigation and discovery

`OpenCourseIntent` stores a course UUID in standard `UserDefaults`; `RootView` later presents a course sheet. Assignment and exam open intents only store their course ID, so they do not open a specific assignment/exam. There is no `OpenGPAForecastIntent`, URL/deep-link router, `OpenIntent` conformance, screen entity context, `NSUserActivity`, or cold-start delivery retry. In particular, the pending ID is removed even when the SwiftUI query has not yet loaded the course, so a cold-start request can be lost.

There is no `IndexedEntity`, `IndexedEntityQuery`, `CSSearchableIndex`, `CoreSpotlight`, reindex callback, or index lifecycle implementation. Therefore Spotlight and entity freshness/deletion behavior are not available.

## Why direct Siri cannot be claimed

### Code issues

1. The current phrases are broad templates that all include the app name. They do not train the requested natural Chinese or English utterances, course aliases, grade words, or score forms.
2. Course matching normalizes code forms such as `CHE 2A` to `CHE002A`, but only matches exact normalized codes, code substrings, or English titles. It has no persisted Siri aliases, Chinese aliases, title synonym mapping, or safe multi-course disambiguation policy.
3. Assignment and exam lookup only performs a case-insensitive title/course substring match. It does not normalize `HW3`, ordinal words, Chinese numeric forms, same-title conflicts, or exam aliases.
4. The existing course-grade response is a hard-coded English concatenation. It does not supply the required current/projected/final distinction, localized sentences, the no-graded-work result, or a selected target letter grade such as A-minus.
5. GPA intents return official GPA only. There is no projected-quarter GPA intent, no `OpenGPAForecastIntent`, and no direct target-letter-grade flow.
6. The draft intents do not ask for a Siri confirmation before their draft is produced. They rely on the in-app confirmation screen; this is safer than direct write, but does not meet the requested Siri confirmation dialogue and is not device-tested.
7. Write confirmation does not update a system entity index, and draft creation/confirmation does not use a unified post-save lifecycle.
8. There is no Siri diagnostics page, registration/re-registration action, student-facing direct-Siri teaching, screen context, or localized deep-link failure UI.

### SwiftData/data-access risks

1. The intent service creates its own container rather than calling `PersistentStoreService`; same configuration name is evidence of intent, not proof that all execution contexts resolve the same live store.
2. No test proves that an intent reads a course written by the main app from the on-disk store, nor that it handles unavailable/migration-failed storage without opening a separate empty database.
3. The service is `@MainActor` and creates fresh `ModelContext` values, which avoids passing models out directly, but its API returns hand-assembled entities with incomplete snapshots and no index/update boundary.
4. Pending navigation and draft data use standard `UserDefaults`, not a typed routing/draft service with delivery acknowledgement. This is especially fragile for cold start.

### System-discovery gaps

1. Compile-time metadata extraction and NLU asset generation succeeded for the main target. That proves the target includes the files and that metadata can be produced; it does not prove iOS registered or selected the app.
2. There is no device install/launch after this audit build, no first-launch registration observation, no Shortcuts manual run result, no Spotlight result, and no direct Siri result.
3. There is no App Intents Extension. It is not currently proven necessary, and adding one before establishing the shared-store design could create a second-data-store failure.

### Localization gaps

1. The string catalog has 500 keys with translated, non-empty `zh-Hans` entries. This is catalog coverage, not a visual or spoken-language acceptance result.
2. App Intent dialogs and service errors are dynamically assembled English strings. A dynamic `IntentDialog(stringLiteral:)` cannot provide natural Chinese grammar, localized plural behavior, or the required date/time wording merely because a source key exists in the catalog.
3. App Shortcut training combines English and Chinese utterances in every locale corpus; the generated `root.ssu.yaml` demonstrates that the English corpus receives Chinese phrases and vice versa. Phrases must be locale-specific and natural.
4. No English/Chinese UI test launches under either language, and no Siri metadata/dialog localization test exists.

### Signing, language, and system limits

- The connected iPhone can build against the configured development signing profile. Installation, launch, trust state, Siri language, app language, system language/region, Apple Intelligence status, lock/authentication behavior, and Personal Team capability constraints were not inspected at runtime.
- The iOS 27 SDK contains `AppSchema`, `AssistantSchema`, `IndexedEntity`, `IndexedEntityQuery`, `EntityStringQuery`, `OpenIntent`, `AppDependencyManager`, and `AppIntentsExtension`. Its exposed semantic schemas list domains such as Calendar, Reminders, Mail, Notes, Books, and others, but no education/course/grade/homework schema. v1.1.2 should use custom, accurately named App Intents and entities rather than misrepresent academic records as another domain.
- Siri may still require the app name for custom phrases, may request device unlock for private data, and may be affected by the selected Siri language/region or iOS beta behavior. None of these limits can be resolved by a simulator build.

## Reliable, partial, and unverified behavior

| Category | Current status |
| --- | --- |
| Existing grade calculations and distinction between official/projection models | Automated tests pass; suitable for reuse after intent integration tests. |
| Existing metadata and App Shortcut asset extraction | Compiled successfully for the main app target. |
| Intent-level data access, draft payload creation, and setting gates | Unit-level partial coverage only; not a real Siri result. |
| Direct natural-language Siri, bilingual response quality, entity resolution, Spotlight, screen context, and deep links | Not verified; several code gaps are known. |
| Physical device build/signing | Succeeded. Install, first launch, direct Siri, Shortcuts, and Spotlight are not verified. |

## Implementation order

1. Add v1.1.2 migration-safe fields for aliases/settings and make a single `PersistentStoreService` entry point for app and intent access; test both readers against the same disk store.
2. Create stable, Sendable course/assignment/exam/term/scenario snapshots with normalized English/Chinese matching and explicit disambiguation.
3. Implement `IndexedEntity`/`IndexedEntityQuery`, a resilient index coordinator, lifecycle hooks, and tests before claiming Spotlight support.
4. Replace the generic English dialogs with localized result builders; add custom, privacy-gated query intents for the requested grade, projected GPA, target-grade, assignment, and exam workflows.
5. Replace UserDefaults-only navigation with stable-ID routing that targets exact course/item/forecast pages and survives cold start/deletion.
6. Add confirmed draft flows that require an explicit confirmation before mutation, then update notifications/indexes after the visible app confirmation.
7. Build the Siri AI settings/diagnostics and in-context teaching UI; perform English and Simplified Chinese simulator visual checks.
8. Install as an update on the physical iPhone, launch once, inspect language/region/Siri/Apple Intelligence state, then conduct the one-command-at-a-time user-spoken device test matrix. Record only observed results in `REAL_DEVICE_SIRI_RESULTS.md`.
