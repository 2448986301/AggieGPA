# App Intents, Siri, Spotlight, and Shortcuts Specification

> Implementation status (2026-07-22): implemented with read, open, calculation, and draft-only intents plus eight bilingual App Shortcuts. Siri access remains off by default and private results require authentication.

## Data boundary

`AppIntentDataService` opens the same store and maps SwiftData records to Sendable snapshots. It applies Siri preference gates, date/calendar/time-zone logic, deletion handling, normalization, and the shared grade/GPA engines. No intent gets arbitrary database access, syllabus text, backup paths, private notes, or unrelated records.

App Entities: Course, Assignment, Exam, Academic Term, and Grade Scenario. Each uses stable IDs, bilingual display representation, and entity queries. Course matching normalizes case, spaces, and forms such as CHE 2A/CHE 002A; multiple matches require disambiguation. Assignment/exam queries support today, tomorrow, this week, next seven days, overdue, incomplete/ungraded, course, midterm, and final using the user's Calendar and time zone.

## Intents

Read-only: upcoming assignments/exams, course grade, quarter GPA, GPA overview, required final score, and attention items. Responses explicitly label official versus calculated/projected results.

Open: course, assignment, exam, and planner scenario. Each uses a stable deep link to its specific destination rather than the home screen.

Write: create assignment draft, create exam draft, and record-grade draft. Missing or ambiguous parameters trigger clarification. A visible confirmation summary precedes committing a draft; changing a score never happens silently. There are no destructive/reset/import/privacy intents.

## Privacy and discoverability

Private details and all write drafts require the strongest suitable device-unlocked/authentication policy available in the current public SDK. Settings provide gates for Siri access, assignment summaries, detailed scores, GPA responses, and draft creation. A disabled gate returns a clear explanation.

`AppShortcutsProvider` exposes bilingual phrases for weekly assignments, exams, grades, GPA, required final score, opening a course, and assignment/exam drafts. Entities are indexed for Spotlight only to the minimum allowed by settings. Screen context, where supported, contains only the current course/item.
