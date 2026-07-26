# App Schema mapping

Last updated: 2026-07-23

SDK inspected: iOS 27.0 from Xcode 27.0 beta `27A5228h`

## Mapping rules

Use a system schema only when its published semantics exactly match the operation. Otherwise use a custom App Intent with a precise title and typed parameters. Never map academic data onto Calendar, Reminders, Notes, or another unrelated schema merely to obtain broader Siri recognition.

## Capability map

| Student request | Public system schema in installed SDK | Aggie GPA mapping | Device status |
| --- | --- | --- | --- |
| Open a course | `.system.open` | `OpenCourseIntent` with `CourseEntity` target | Build 11 metadata present; standalone Siri rejected before `perform()`. |
| Search inside Aggie GPA | `.system.searchInApp` | `SearchAggieGPAIntent` with `StringSearchCriteria` | Build 11 metadata present but standalone Siri rejected before `perform()`; restored as the current annotation in build 13, not yet device-verified. |
| Search inside Aggie GPA, compatibility A/B | Legacy `.system.search` | Same `ShowInAppSearchResultsIntent` implementation | Build 12 no-reboot test rejected before `perform()`. |
| List assignments due soon | No education/homework schema | `GetUpcomingAssignmentsIntent` + automatic App Shortcut phrases | Build 11 exact phrase verified with one real item. |
| List upcoming exams | No education/exam schema | `GetUpcomingExamsIntent` | Compiles; not device-verified. |
| Read current/projected course grade | No course/grade schema | `GetCourseGradeIntent` | Compiles; not device-verified. |
| Read official or projected GPA | No GPA schema | `GetQuarterGPAIntent`, `GetGPAOverviewIntent`, `GetProjectedGPAIntent` | Compiles; not device-verified. |
| Calculate required remaining/final score | No academic-calculation schema | `CalculateRequiredFinalScoreIntent`, `CalculateTargetLetterGradeIntent` | Compiles; not device-verified. |
| Open GPA forecast | No GPA schema | Custom `OpenGPAForecastIntent` | Compiles; not device-verified. |
| Create assignment/exam or record grade | No education-write schema | Authenticated draft intent followed by in-app confirmation | Implemented; not device-verified. |

## Entity map

| Entity | Stable identifier | Query/index role | Native-schema role |
| --- | --- | --- | --- |
| `CourseEntity` | Course UUID string | String query, suggestions, Spotlight index | Target for `.system.open`. |
| `AssignmentEntity` | Grade-item UUID string | String query, upcoming suggestions, Spotlight index | Parameter for custom assignment/open/draft intents. |
| `ExamEntity` | Grade-item UUID string | String query, upcoming suggestions, Spotlight index | Parameter for custom exam/open/draft intents. |
| `AcademicTermEntity` | Term UUID string | String query | Parameter for GPA intents. |
| `GradeScenarioEntity` | Forecast UUID string | Entity query | Parameter for custom scenario opening. |

## Metadata versus runtime

Successful App Intents metadata extraction proves only that Xcode understood the declaration and embedded it in the app. It does not prove that the iOS Siri planner registered, selected, or executed the schema. The build 11 search/open experiments demonstrate this distinction: metadata was present, but no corresponding start trace appeared on the device.

## Current product wording

- Correct: “Works directly from Siri with automatically registered Aggie GPA phrases; no user-created Shortcut is needed.”
- Correct for the successful test: “Siri showed the Aggie GPA assignment card.”
- Incorrect: “All Aggie GPA questions are natively understood by Siri AI.”
- Incorrect: “Assignments and grades use an iOS education App Schema.” No such schema exists in the inspected SDK.
