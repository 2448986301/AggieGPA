# Real-device Siri results

Last updated: 2026-07-23

Branch: `feature/v1.1.2-direct-siri-ai`

Device: Eason's iPhone, iPhone 17 Pro (`iPhone18,1`), iOS 27.0 build `24A5390f`

Device identifiers: CoreDevice `6B77880E-E0E6-5571-A5D1-32BCB7E83F65`; hardware UDID `00008150-001265EE0100C01C`

Toolchain: Xcode 27.0 beta build `27A5228h`, iOS 27.0 SDK

Bundle: `com.easonzhou.aggiegpa`; App Group: `group.com.easonzhou.aggiegpa`

## Evidence rules

A Siri route is counted as an Aggie GPA intent execution only when the visible result and the app's device-side execution trace agree. A system-generated reply that mentions the app is not enough. The trace stores only a stage name, timestamp, and optional item count; it does not store course names, grades, or spoken text.

`SiriExecutionTrace` stages beginning with `schema-search-`, `schema-open-course-`, or `assignments-` are emitted from inside the corresponding `perform()` implementation. Their absence means that the app has no evidence that the intent body ran.

## Preconditions observed

- The signed app was installed as an update with the existing bundle identity; it was not uninstalled and the existing student data remained visible.
- Build 11 was launched from Xcode on the physical device. The app showed four courses, including `CHE 002A` / General Chemistry, and an upcoming `Homework 3` due July 24, 2026.
- The developer profile was trusted, Developer Mode was enabled, and the device was connected and paired.
- Settings showed Apple Intelligence-powered Siri, Siri language English (United States), and both “Siri or Hey Siri” and the side-button invocation enabled.
- Aggie GPA's Siri access and assignment-summary permission were enabled. iOS settings allowed Siri to learn from the app and allowed the app and its content in Search.
- VPN was disabled during the successful networked Siri tests because the prior VPN state produced a connection error. No Apple ID, account region, or system region was changed.

## Verified test matrix

| Build | Surface and input | Visible result | Device trace | Classification |
| --- | --- | --- | --- | --- |
| 11 | Standalone Siri app: `View assignments in Aggie GPA` | Aggie GPA snippet: “Due in the next seven days”; `Homework 3`; `CHE 002A`; July 24 due date. The lower system status identified it as running the app's shortcut. | `assignments-started` → `snapshot-read` (`itemCount = 1`) → `assignments-completed` (`itemCount = 1`). | **Verified custom App Intent success through automatic App Shortcut registration.** No manually created Shortcut was used. This is not a native App Schema route. |
| 11 | Standalone Siri app: `What assignments are due this week in Aggie GPA` | Siri said it could not find assignments in Aggie GPA and offered to open the app. | No `assignments-started` and no schema-start stage for this attempt. | **System fallback, not an Aggie GPA intent result.** It reproduces the original failure appearance. |
| 11 | Standalone Siri app: `Search Aggie GPA for CHE 002A` | Siri said it could not search inside Aggie GPA and offered to open the app. | No `schema-search-started`. | **Native `.system.searchInApp` rejected before `perform()`.** |
| 11 | Standalone Siri app: `Open CHE 002A in Aggie GPA` | Siri did not execute the native app open flow. | No `schema-open-course-started`. | **Native `.system.open` rejected before `perform()`.** |
| 11 | iOS Spotlight search: `CHE 002A` | Result displayed under Aggie GPA as `CHE 002A`, subtitle `General Chemistry · Fall 2026`. | Index history recorded `spotlight-indexed` with four items. | **Core Spotlight/AppEntity indexing verified.** Selecting the result did not verify exact course deep-link delivery. |
| 12 | Standalone Siri app, in-app search A/B after changing the annotation from `.system.searchInApp` to legacy `.system.search` | Siri again reported that it could not search within Aggie GPA. | No `schema-search-started`. | **Legacy native search schema also rejected before `perform()` in this no-reboot A/B.** |

Build 13 restores the supported `.system.searchInApp` annotation after the build 12 A/B. At the time of this update, no build 13 native-search device success has been recorded; the build 11 and 12 results above remain the runtime evidence.

## Historical attempts retained from the 2026-07-22 record

These observations remain useful, but their earlier interpretation has been corrected.

The original record described a signed build from `feature/v1.1.2-direct-siri-ai` at `e4ad87e`. It observed the app in iPhone Mirroring with the app UI set to Simplified Chinese, all five then-present in-app Siri controls enabled, and Privacy Lock visibly enabled. It did not inspect Siri language, system language/region, Apple Intelligence state, or network diagnostics during that run.

| # | Input surface and text | Observed system behavior | Correct current interpretation |
| --- | --- | --- | --- |
| 1 | iPhone “Search or Ask”: `What assignments are due this week?` | Ordinary Spotlight results; Aggie GPA was not selected. | No Aggie GPA intent execution. |
| 2 | iPhone “Search or Ask”: `What assignments are due this week in Aggie GPA?`, then the shown “Ask Siri” option | “I'm having trouble with the connection. Please try again later.” | Network/system failure; no Aggie GPA intent execution. |
| 3 | Siri conversation: `What assignments are due thisweek in Aggie GPA` | “I couldn't find any assignments due this week in Aggie GPA.” | The earlier document classified this as Aggie GPA's empty response. The later execution-trace evidence shows that this wording alone cannot establish intent execution; this classification is withdrawn. |

### Superseded 2026-07-22 conclusion

For audit continuity, the earlier conclusion is retained below but is **withdrawn**. It must not be used as current evidence:

> “The first direct Siri invocation has now succeeded on the physical device. The app-name query reached Aggie GPA and produced its exact empty-result response.”

The earlier record also attributed the empty response to `AppIntentDataService` constructing its own container. Subsequent implementation and the build 11 non-empty snapshot trace resolved that suspected data-path defect for the verified assignment route. The response text alone never proved that the earlier intent ran.

## What is proved

- The app can expose a custom App Intent to the standalone Siri app without the user manually creating a Shortcut.
- The out-of-process intent can read the App Group snapshot and return the same non-empty assignment that the app shows.
- The response can render as an Aggie GPA card in the Siri UI.
- The device ingests the app's indexed course entities into Spotlight.

## What is not proved

- The iOS 27 beta standalone Siri planner does not yet select either tested native search schema annotation or the native open schema on this device.
- Natural paraphrases are not equivalent to the exact registered App Shortcut phrase. The full weekly-assignment wording was intermittent across attempts; the recorded standalone Siri attempt in the matrix failed before app execution.
- Chinese Siri invocation and Chinese result copy are not yet verified on the physical device.
- Grade, GPA, target-score, exam, draft creation, confirmation, authentication, exact entity deep links, deletion/reindexing, cold-start recovery, and locked-device behavior are not yet verified end to end.
- The search-schema failure has not been retested after a reboot. The no-reboot build 12 A/B cannot distinguish an SDK/runtime incompatibility from stale registration or an iOS 27 beta/region rollout restriction. Build 13's restored official schema still requires this retest.

## Current conclusion

The requested visual Siri presentation is achieved for one exact, automatically registered assignment phrase: the standalone Siri app shows a native-looking Aggie GPA result card populated with `Homework 3`. The evidence does **not** support claiming that the same query works as a pure system App Schema or that arbitrary Siri AI wording is fully bound to Aggie GPA. The installed SDK has no education schema, and the two applicable native schemas tested so far were rejected by the device before app code ran.
