# Real-device Siri results

Date: 2026-07-22  
Device: connected iPhone 17 Pro (`6B77880E-E0E6-5571-A5D1-32BCB7E83F65`)  
Build: signed `AggieGPA` development build from `feature/v1.1.2-direct-siri-ai` at `e4ad87e`.

## Preconditions observed

- Xcode Build and Run launched Aggie GPA on the physical iPhone without uninstalling the existing app.
- The app was visible in iPhone Mirroring with the app UI set to Simplified Chinese.
- The Siri Access screen showed all five existing in-app controls enabled: Siri Access, Assignment Summaries, Detailed Scores, GPA Responses, and Creating Drafts.
- The Privacy Lock control was visibly enabled in Settings.
- Siri language, system language/region, Apple Intelligence state, and network diagnostics were not exposed by this test; do not infer them from the app language.

## Results

| # | Input surface and text | System behavior | Intent/entity/data result | Classification |
| --- | --- | --- | --- | --- |
| 1 | iPhone “Search or Ask”: `What assignments are due this week?` | Returned ordinary Spotlight results (music, Messages, websites). Aggie GPA was not selected. | No intent, entity, authentication request, or app data response observed. | Current Siri AI did not recognize this bare natural-language form. |
| 2 | iPhone “Search or Ask”: `What assignments are due this week in Aggie GPA?`, then Return on the shown “Ask Siri” option | Siri displayed: “I’m having trouble with the connection. Please try again later.” | No Aggie GPA intent name, resolved entity, dialog, authentication request, or app mutation was observed. | Current system connection limitation; not an App Intent success and not proof of phrase failure. |
| 3 | Siri conversation captured on the physical iPhone: `What assignments are due thisweek in Aggie GPA` | Siri answered: “I couldn't find any assignments due this week in Aggie GPA.” | This is Siri's rendered empty-result response for Aggie GPA's upcoming-assignment request. No assignment details or mutation occurred. | Direct Siri invocation succeeded; the result is a data-access defect. |

## Corrected conclusion

The first direct Siri invocation has now succeeded on the physical device. The app-name query reached Aggie GPA and produced its exact empty-result response. This verifies direct English Siri routing to the upcoming-assignment intent; it does **not** verify entity resolution, bilingual responses, opening content, confirmed writes, or a non-empty assignment result.

The app UI previously showed an upcoming `CHE002A` “Homework 3”, while Siri returned no assignments. The most likely cause is the current architecture: `AppIntentDataService` creates its own `ModelContainer` instead of using the app's `PersistentStoreService` factory. This must be treated as an integration defect until a single shared store path is verified with a non-empty real-device Siri result.
