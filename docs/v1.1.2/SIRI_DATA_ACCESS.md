# Siri data access

Last updated: 2026-07-23

## Storage model

Aggie GPA remains a local SwiftData app. The main app uses the versioned `AggieGPASchemaV2` store through `PersistentStoreService`. Siri integration adds a small local App Group boundary, not a cloud database:

- bundle identifier: `com.easonzhou.aggiegpa`;
- App Group: `group.com.easonzhou.aggiegpa`;
- shared snapshot key: `siriSharedSnapshot.v1`;
- pending navigation key: `pendingSiriNavigation`;
- execution trace keys: `siriExecutionTrace.v1` and `siriExecutionTraceHistory.v1`.

The app is installed as an update and does not replace, clear, or migrate existing terms, courses, official grades, projections, preferences, privacy settings, scenarios, or backups merely to enable Siri.

## Shared read snapshot

The snapshot is written by the main app after model/settings changes and contains only the fields needed for current low-risk Siri lookup:

- Siri enabled state and assignment-summary permission;
- course stable ID, code, title, term name, and local aliases;
- assignment stable ID, course ID/code, title, due date, category, and status.

It excludes official grades, calculated percentages, GPA values, points, forecast values, draft payloads, and unrelated preferences. Dropped/excused work and exam-category items are excluded from the assignment list.

The physical-device build 11 test proved that the out-of-process assignment intent could read this snapshot: the trace reported one item and Siri rendered `Homework 3` for `CHE 002A`.

## Fallback data access

When an entity or operation is not available in the snapshot, `AppIntentDataService` opens the same versioned app store through `PersistentStoreService.makeAppIntentContainer()`. The service returns value-type App Entities rather than live SwiftData models.

The fallback enforces the saved Siri settings:

- global Siri access is required for all reads;
- assignment/exam summaries require the assignment-summary switch;
- detailed course-grade/target calculations require detailed-score access;
- official/projected GPA requires GPA-response access;
- draft creation requires draft access.

This fallback is unit-tested at the service level, but only the shared-snapshot assignment path has been verified through the standalone Siri app on the physical device.

## Date and grade semantics

- “Next seven days” starts at the current calendar day's start and excludes the boundary at the start of day eight.
- An item needs a due date and must fall within the interval to appear.
- Ungraded work remains excluded from graded calculations; it is never silently treated as zero.
- Official grades and calculated/projected values are returned as distinct concepts and never overwrite one another.

## Navigation and draft data

Pending navigation contains only a route kind plus stable course/item IDs or a search term. It survives an app process launch and is cleared after the destination resolves.

Draft payloads contain the minimum fields needed for a visible in-app confirmation. Creating a draft is not the same as saving an assignment, exam, or grade. The user-facing confirmation remains the mutation boundary.

## Failure behavior

- If Siri access or a data category is disabled, the service returns an explicit permission error rather than an empty academic result.
- If an entity no longer exists, it returns a deleted-entity error.
- If the shared snapshot is absent, the guarded store path may be used; failure is surfaced and traced rather than creating or treating an empty database as authoritative.
- A system reply without an Aggie GPA start trace is classified as a planner/system fallback, not as an empty app query.
