# Siri known limitations

Last updated: 2026-07-23

## Public API limits

- The installed iOS 27 SDK has no education, course, homework, assignment, grade, GPA, or academic-planning App Schema.
- Aggie GPA therefore cannot truthfully make grade/GPA/assignment answers a native education schema. They are custom App Intents registered automatically through `AppShortcutsProvider`.
- The user does not need to create a Shortcut or use the Shortcuts app. However, iOS may label the successful execution as running the app's shortcut. This system wording cannot be removed by an app permission.
- Private entitlements or pretending academic records belong to an unrelated schema are not acceptable solutions.

## Current physical-device limits

- Build 11's `.system.searchInApp` and `.system.open` declarations compiled and appeared in metadata, but the standalone Siri app rejected both tested requests before Aggie GPA's `perform()` executed.
- Build 12's legacy `.system.search` A/B was also rejected before `perform()` in a test performed without rebooting the device.
- Build 13 restores the official `.system.searchInApp` annotation. No build 13 native-search success has been recorded yet.
- No conclusion has been drawn about the post-reboot state. Stale registration remains possible.
- Spotlight successfully shows `CHE 002A`; this does not prove that Siri consumes the same entity for native open/search.
- Selecting the Spotlight result did not yet verify exact deep-link navigation.

## Language and planner limits

- One exact English registered phrase is verified: `View assignments in Aggie GPA`.
- The full natural weekly-assignment wording from the original screenshot was intermittent. The recorded standalone Siri retest was not routed to Aggie GPA, while the shorter exact automatic phrase was reliable in the successful demonstration.
- Custom intent phrase matching does not guarantee arbitrary paraphrase understanding.
- Simplified Chinese invocation and response rendering are not yet verified on the physical device.
- Siri/Apple Intelligence beta rollout, language, account/region eligibility, registration delay, or a runtime defect may explain native-schema rejection. This is a hypothesis. The tests did not change Apple ID or region, so the cause remains unresolved.

## Network and state limits

- Earlier attempts failed with a generic connection error while a VPN was active. The successful assignment-card test was performed with VPN off.
- The native search A/B has not yet been repeated after reboot, OS update, or an extended registration wait.
- Locked-device, terminated-app, offline, poor-network, privacy-lock, and authentication behavior remain unverified.

## Feature coverage limits

Only the upcoming-assignment custom intent has an end-to-end standalone Siri success with a non-empty real result and device trace. These remain unverified end to end:

- exams;
- official/current/projected course grade distinctions;
- official and projected GPA;
- target-grade/required-final calculations;
- assignment/exam/score drafts and in-app confirmation;
- precise course/item/forecast opening;
- deleted/ambiguous entity handling;
- index removal and refresh after edits;
- bilingual and accessibility behavior.

## Data and presentation limits

- The successful read uses a local App Group snapshot. Other intents may use the guarded SwiftData fallback; those paths have automated coverage but no standalone Siri device result.
- Current dynamically assembled intent replies are predominantly English. String-catalog coverage does not establish natural bilingual Siri output.
- The assignment card proves current snapshot consistency for one item, not continuous synchronization under every edit or process state.

## Safe product claim

The strongest currently supported statement is:

> On the tested iOS 27 beta, Aggie GPA can show a real upcoming-assignment card directly in the standalone Siri app for an exact automatically registered phrase, without the user manually creating a Shortcut. Native system search/open binding and broader natural-language coverage are not yet verified.
