# Siri and Spotlight entity indexing

Last updated: 2026-07-23

## Purpose

Entity indexing gives iOS stable, searchable representations of Aggie GPA courses, assignments, and exams. It supports Spotlight discovery and is a prerequisite for reliable entity resolution, but it does not by itself cause the standalone Siri planner to select an App Schema.

## Indexed content

| Entity | Visible title/subtitle | Search attributes |
| --- | --- | --- |
| Course | Course code; course title and term | Code, title, term, `Aggie GPA`, `course`, `class`, and user aliases. |
| Assignment | Item title; course code | Title, course code, category, status, `Aggie GPA`, `assignment`, `homework`, and due date. |
| Exam | Item title; course code | Title, course code, exam type, status, `Aggie GPA`, `exam`, `test`, and due date. |

Academic terms and forecast scenarios remain App Entities but are not currently sent to Core Spotlight.

## Implementation lifecycle

1. `RootView` computes a fingerprint from current courses, grade items, and Siri permissions.
2. A change schedules a short coalesced integration refresh.
3. The index deletes previous Aggie GPA course/assignment/exam domains and associated App Entities.
4. `IndexedEntityQuery` implementations provide fresh entities.
5. Each value becomes `CSSearchableItem(appEntity:priority:)` with priority 100 and an Aggie GPA domain identifier.
6. Diagnostics record `spotlight-indexed` and the live course count, or `spotlight-index-failed`.

The main app also offers a manual refresh in Siri settings. App launch/foreground refreshes the shared snapshot and App Shortcut parameters.

## Verified physical-device result

Build 11 Spotlight search for `CHE 002A` displayed:

- app: Aggie GPA;
- title: `CHE 002A`;
- subtitle: `General Chemistry · Fall 2026`.

The trace history recorded `spotlight-indexed` with four courses. This verifies ingestion and visibility on the physical iPhone.

## Not yet verified

- Selecting the Spotlight result navigates to the exact course on cold launch.
- Updating or deleting a course removes every stale result without relaunching.
- Assignment and exam entries appear for expected queries.
- User aliases influence standalone Siri entity resolution.
- The native `.system.open` planner consumes the AppEntity association.
- English and Simplified Chinese keywords produce equivalent discovery.

## Privacy and correctness rules

- Do not index numeric grades, GPA values, earned points, possible points, or forecast values.
- Do not index deleted, dropped, or excused data as active coursework.
- Treat Spotlight visibility as device-visible metadata. The user must be able to disable Siri access in Aggie GPA; removal behavior after disabling remains part of the test plan.
- A successful index trace is not evidence of an intent execution. Native intent acceptance requires its own `schema-...-started` and completion traces.
