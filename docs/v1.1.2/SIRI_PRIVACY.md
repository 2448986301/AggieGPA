# Siri privacy model

Last updated: 2026-07-23

## Principles

1. Existing Aggie GPA student data remains local unless the user separately authorizes a different product design.
2. Siri access is opt-in inside Aggie GPA and divided by data sensitivity.
3. Read operations do not modify grades or coursework.
4. Write-like requests create drafts only; the app requires visible confirmation before mutation.
5. Diagnostics must prove execution without recording the user's academic content.

## In-app controls

All controls default to off for a new settings record:

| Control | Protects |
| --- | --- |
| Enable Siri Access | Master gate for Aggie GPA entities and answers. |
| Allow Assignment Summaries | Assignment and exam titles, courses, statuses, and due dates. |
| Allow Detailed Scores | Course percentages, graded weight, and target-score calculations. |
| Allow GPA Responses | Official and projected GPA output. |
| Allow Creating Drafts | Assignment, exam, and score-entry draft creation. |

The physical-device assignment demonstration was performed with Siri access and assignment summaries enabled.

## Local shared data

The App Group snapshot is stored on the device and is available only to processes signed for Aggie GPA's App Group. It contains course/assignment discovery fields and the relevant permission bits; it does not contain GPA or score values. The App Group is a process-sharing mechanism, not an iCloud or upload feature.

Core Spotlight indexes course/work metadata needed for discovery. Current attributes intentionally omit official grades, points, percentages, GPA, and forecasts. Students should still treat indexed titles and due dates as information that may appear in system search on their unlocked device.

## Authentication and mutation

- Upcoming assignments currently use `.alwaysAllowed` at the App Intent layer, subject to the app's own master and assignment-summary gates.
- Exams, detailed grades, GPA, target calculations, and draft intents require local device authentication.
- An accepted Siri draft does not change the SwiftData model. Aggie GPA opens a confirmation screen where the user can review and confirm.
- Official and projected records remain separate and a projected value never overwrites an official grade.

## Diagnostics

The local trace records only:

- an implementation stage such as `assignments-started` or `schema-search-started`;
- a timestamp;
- an optional item count.

It does not record the utterance, course code/title, assignment name, grade, GPA, points, search text, or Apple ID. The history is bounded to 24 entries.

## Platform boundary

Aggie GPA can control what its own process reads, indexes, and returns. It cannot promise that Siri speech recognition or Apple Intelligence processing is wholly offline, because that behavior belongs to iOS and the user's Apple Intelligence/Siri settings. Relaxing app permissions cannot manufacture a missing education App Schema, bypass device authentication, or guarantee third-party schema availability in a region/beta rollout.

## Operational caution

VPN was turned off during the successful real-device test after a connection error. That is a network test condition, not an Aggie GPA privacy requirement. No Apple ID or region setting was changed.
