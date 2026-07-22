# Acceptance Criteria

> Implementation status (2026-07-22): implemented. Automated coverage includes 84 unit tests and 18 UI tests. The iPhone-mirror smoke check verified that each existing Fall 2026 term opens and returns to the list without crashing after the stale-relationship repair. Notification authorization and Siri speech recognition remain device-only manual checks.

## Data and identity

- The existing project, bundle identifier `com.easonzhou.aggiegpa`, signing team, navigation, and icon remain intact.
- A v1.0 store upgrades without losing terms, courses, official grades, GPA inputs, settings, scenarios, privacy state, or backup metadata; failure is recoverable.
- `MARKETING_VERSION` is 1.1.1 and build number is 3.

## Gradebook and prediction

- Users can configure weights/scales, add assignments/exams, record optional earned/possible points, and use batch-confirmed entry.
- Ungraded work is not zero; explicit missing policy, drops, excuses, extra credit, and invalid weights behave as specified and are tested.
- Official, calculated, projected, What-If, and planner-selected values never overwrite one another.
- Shared-engine current grade, earned credit, forecast, required remaining/final score, and projected GPA are correct or explicitly require manual review.

## Import, reminders, and intelligence

- PDF, image/camera, text, and manual syllabus workflows produce local editable previews and save only after confirmation.
- Deterministic parsing works without Foundation Models; device-model unavailability degrades normally.
- Local assignment/exam reminders reconcile without duplication and route to the correct item; denial is safe.

## Siri and system integration

- App Intents query assignments, exams, course grade, and GPA with privacy gates and exact official/projected wording.
- Open intents deep-link to specific records; write intents create confirmed drafts only.
- Bilingual App Shortcuts are discoverable; Spotlight/context exposure is minimal and preference-controlled.

## Quality and delivery

- Existing v1.0 features regress neither functionally nor visually; accessibility requirements are met.
- JSON schema v2 round-trips and v1 imports safely; import failures do not mutate current data.
- Clean simulator build and core automated tests pass; device-only results are listed honestly.
- The same signed bundle installs over v1.0 without uninstalling it and retained data is manually verified.
- Documentation is current, commits are scoped, the feature branch is pushed, and the requested PR is open but not merged; no release tag is created.
