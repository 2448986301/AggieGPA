# Direct Siri integration design

Last updated: 2026-07-23

Target: Aggie GPA 1.1.2 on iOS 27

## Product goal

Students should be able to ask Siri for Aggie GPA information and receive a branded result in the Siri UI without opening the Shortcuts app or manually creating a Shortcut. When an operation must continue in Aggie GPA, the app should open the exact destination and preserve all existing v1.0/v1.1 data.

The design uses only public App Intents, App Entities, Core Spotlight, SwiftData, and App Group APIs. It does not use a private entitlement or mislabel grade data as an unrelated system domain.

## Terminology

- **Native App Schema**: a system-defined semantic contract such as system open or in-app search. Siri can reason about its known parameters without relying on an app-specific phrase.
- **Custom App Intent**: an Aggie GPA operation such as “get upcoming assignments” or “get projected GPA”.
- **Automatic App Shortcut**: a custom App Intent plus developer-supplied phrases registered by `AppShortcutsProvider`. The user does not create or maintain anything in the Shortcuts app, although iOS may visibly describe the execution as running the app's shortcut.
- **Standalone Siri app**: the iOS 27 conversational Siri surface used for the real-device acceptance tests. Spotlight's “Search or Ask” surface is recorded separately.

## Architecture

| Layer | Responsibility | Current implementation |
| --- | --- | --- |
| Siri surface | Select a schema or automatically registered app phrase and render dialog/snippet output. | Native search/open experiments plus automatic Aggie GPA App Shortcuts. |
| Intent layer | Enforce the operation's authentication and permission policy; return dialog, snippet, or app route. | App Intents in `AggieGPAIntents.swift` and schema experiments in `AggieGPASchemaIntents.swift`. |
| Entity layer | Give courses, assignments, and exams stable identities and searchable representations. | `IndexedEntity` plus `EntityStringQuery` / `IndexedEntityQuery`. |
| Read boundary | Let an out-of-process intent read a small, coherent view without contending with the live SwiftData store. | Local App Group snapshot with guarded SwiftData fallback. |
| Navigation boundary | Carry a stable course/item/search destination across process launch and model loading. | Typed pending navigation in the App Group; it is cleared only after resolution. |
| Discovery layer | Make app entities visible to Spotlight and available for system resolution. | Explicit `CSSearchableItem(appEntity:priority:)` indexing. |
| Diagnostics | Distinguish a system fallback from code that actually executed. | Privacy-safe ring buffer of stage, timestamp, and optional count. |

## Read flow

1. The main app observes course, grade-item, and Siri-setting changes.
2. After a short coalescing delay, it writes a local snapshot, updates App Shortcut parameters, and rebuilds indexed entities.
3. Siri selects either a native schema or a custom automatically registered phrase.
4. The intent records a start stage, checks the relevant privacy gate, reads the snapshot or guarded data service, and records completion/failure.
5. The result is rendered as an Aggie GPA dialog/snippet. No read operation changes official grades or projected values.

The build 11 phrase `View assignments in Aggie GPA` completed this flow and returned the real `Homework 3` item. This is the only custom read flow currently verified end to end on the physical device.

## Open/search flow

The desired pure-schema flow is:

1. Siri resolves an indexed `CourseEntity` or in-app search criterion.
2. The native system open/search intent records its start stage.
3. It writes a typed pending route into the App Group and requests app launch.
4. `RootView` waits for SwiftData results, resolves the stable UUID, navigates, and then acknowledges the route.

Build 11 emitted valid metadata for `.system.open` and `.system.searchInApp`, but the standalone Siri app rejected both tested requests before step 2. Build 12's no-reboot `.system.search` A/B was rejected at the same point. Build 13 restores the official `.system.searchInApp` annotation; it has no verified native-search success yet. Spotlight independently displayed `CHE 002A`, proving that indexing works but not that Siri's planner selects the schema.

## Write flow

Siri never writes an official score, assignment, or exam directly. A write intent may create a draft only when the corresponding setting is enabled. Aggie GPA then opens a visible confirmation screen; the user must confirm inside the app before the model changes. Official grades and projected/calculated values remain separate.

This design is implemented at the intent/draft level but is not yet verified end to end in the standalone Siri app.

## System-schema boundary

The installed iOS 27 SDK has no education, course, assignment, grade, or GPA App Schema. Consequently:

- native `.system.open` is appropriate for opening an indexed course;
- native search is appropriate for searching inside Aggie GPA;
- grade/GPA calculations and assignment summaries must remain accurately named custom App Intents;
- no permission relaxation can create a missing public schema or force Siri's planner to select an app intent.

## Acceptance boundary

The design is considered demonstrated only per operation, not globally. Each accepted operation needs:

- the exact tested utterance and surface;
- a visible result that contains the expected app data;
- a matching device-side start and completion trace;
- verification that existing app data was preserved;
- an explicit statement of whether the route was a native App Schema or an automatic App Shortcut.

Current accepted operation: upcoming assignments through the exact automatic App Shortcut phrase. Native schema acceptance remains open.
