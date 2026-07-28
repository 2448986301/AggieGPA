# Siri test plan

Last updated: 2026-07-23

Primary acceptance device: iPhone 17 Pro, iOS 27.0 build `24A5390f`

## Test evidence standard

Every device case records:

1. app build number, iOS build, Siri language, lock state, network/VPN state, and whether the app is foreground/background/terminated;
2. exact input text and the surface used;
3. screenshot or mirrored visible result;
4. device-side execution trace after the attempt;
5. resulting app destination or data mutation, if any;
6. pass/fail classification that names native App Schema versus automatic App Shortcut.

A matching visible answer without a start/completion trace is not an app-intent pass. A metadata file or successful build is not a runtime pass.

## Completed cases

| ID | Build | Case | Result |
| --- | --- | --- | --- |
| D-01 | 11 | Standalone Siri app, exact `View assignments in Aggie GPA` with one upcoming assignment | Pass: Aggie GPA card showed `Homework 3`; trace showed snapshot read/completion with one item. Automatic App Shortcut route. |
| D-02 | 11 | Natural `What assignments are due this week in Aggie GPA` | Fail: system fallback; no app-intent start trace. |
| D-03 | 11 | Native `.system.searchInApp`: `Search Aggie GPA for CHE 002A` | Fail before `perform()`; no schema trace. |
| D-04 | 11 | Native `.system.open`: `Open CHE 002A in Aggie GPA` | Fail before `perform()`; no schema trace. |
| D-05 | 11 | Spotlight query `CHE 002A` | Partial pass: indexed result visible; exact deep link not verified. |
| D-06 | 12 | Legacy `.system.search` no-reboot A/B | Fail before `perform()`; no schema trace. |

## Required next device matrix

### Registration and runtime isolation

- Reboot once, launch build 13 with the restored official `.system.searchInApp` annotation, wait for registration/indexing, and rerun native search.
- Repeat after app foreground, background, terminated, and cold launch.
- Compare standalone Siri app, side-button Siri, and Spotlight; never combine their outcomes.
- Reinstall only as an update. Verify terms, courses, grades, preferences, scenarios, and backups before and after.

### Assignment route

- Exact English phrase with non-empty, empty, boundary-date, dropped, excused, and no-due-date data.
- Each registered English paraphrase individually.
- Registered Simplified Chinese phrases with Siri language set to a supported Chinese language.
- Siri access off and assignment summaries off; expect explicit denial, never silent data.
- Locked/unlocked behavior and privacy-lock interaction.

### Entity open/search

- Exact course code variants: `CHE 002A`, `CHE2A`, and saved aliases.
- Ambiguous/missing/deleted course.
- Search for a course title and an assignment title.
- Select Spotlight course/assignment/exam result and verify exact destination after cold launch.
- Rename/delete data, rebuild, and verify stale results are gone.

### Grade and GPA reads

- Official grade only, calculated current grade, projected grade, and no graded work.
- Official GPA versus projected GPA; verify wording never mixes them.
- Detailed-score/GPA permissions off; locked-device authentication.
- Decimal accuracy against the app UI without premature rounding.

### Draft operations

- Assignment, exam, and score draft with authentication.
- Cancel in Siri/app and verify no model change.
- Confirm in app and verify one change, notification/index refresh, and no duplicate on relaunch.
- Verify projected values never replace official records.

### Localization and accessibility

- English and Simplified Chinese metadata, invocation, dialog, snippet, error, and confirmation copy.
- Dynamic Type and VoiceOver in the Siri settings/confirmation screens.
- Natural date, percentage, plural, and course-code pronunciation.

## Native-schema investigation gates

Before changing the product claim, rerun native search/open after:

1. a device reboot and one foreground app launch;
2. an iOS/Xcode beta update;
3. confirmation of Siri/Apple Intelligence language and region availability;
4. inspection of extracted action metadata for the installed build.

If `schema-...-started` remains absent, classify the block as system planner/registration and do not rewrite app result logic as a speculative fix.

## Exit criteria

Siri v1.1.2 is not “fully bound” until the requested English and Chinese read/open/write flows have matching UI, trace, data, navigation, privacy, and regression evidence. The current physical-device acceptance is intentionally narrower: one exact English assignment-summary phrase and one Spotlight course result.
