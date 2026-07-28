# Aggie GPA v1.1 Baseline Audit

> Final status (2026-07-22): baseline identity, navigation, icon, data store, v1.0 behavior, Xcode/SDK, simulator, signing settings, build, and tests were preserved throughout implementation.

Audit date: 2026-07-22. Baseline is commit `6a80167` (`Fix app icon and privacy lock loop`). No v1.0 tag was created because the worktree contains the unrelated untracked `Tools/GitHubCLI` directory; the immutable commit SHA is the baseline reference.

## Repository and Git

- Root: `/Users/easonzhou/Documents/UCD`
- Branch: `feature/v1.1-gradebook-siri`
- `main` and `origin/main` also point to baseline `6a80167`.
- Remote: `origin`, `https://github.com/2448986301/AggieGPA.git`
- Tracked files were clean before v1.1 work. Untracked `Tools/GitHubCLI/gh_2.96.0_macOS_arm64` was preserved and is excluded from v1.1 commits.
- No history rewrite, reset, force push, release tag, or merge was performed.

## Project identity and toolchain

- Project: `AggieGPA.xcodeproj`; scheme: `AggieGPA`
- Targets: `AggieGPA`, `AggieGPATests`, `AggieGPAUITests`
- App bundle identifier: `com.easonzhou.aggiegpa`
- Signing team: `LWND9UDGR2`
- `MARKETING_VERSION`: `1.0`
- `CURRENT_PROJECT_VERSION`: `1`
- Deployment target: iOS 27.0
- Project Swift language version: Swift 6.0
- Toolchain: Xcode 27.0 beta, build `27A5228h`; compiler Swift 6.4
- Available SDKs include iOS 27.0 and iOS Simulator 27.0.
- System `xcode-select` points to Command Line Tools. Commands must set `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`; the global developer directory was not changed.

## SwiftData and persistence

The v1.0 schema is created directly in `AggieGPAApp` and contains:

- `AcademicTerm`
- `CourseRecord`
- `PlannerScenario`
- `SimulatedCourse`
- `GradeCategory`
- `CourseGradePlan`
- `UserPreferences`
- `BackupSnapshot`

The persistent configuration is named `AggieGPA` and uses SwiftData's default Application Support location (`ModelConfiguration("AggieGPA", ...)`). UI/screenshot tests use an in-memory configuration. Container initialization currently falls back to a temporary in-memory `AggieGPARecovery` store if the persistent store cannot open; this can make data appear absent and must be replaced in v1.1 with explicit migration/recovery UI that never presents an empty store as success.

There is no App Group entitlement, entitlements file, shared container, or custom store URL. v1.1 should keep this store location unless a proven App Intent requirement makes a move unavoidable.

## Existing product surfaces

- Main tabs: Dashboard, Quarters, Planner, Settings.
- Existing calculations: official cumulative/term/major/upper-division GPA, repeats, What-If, Target GPA, and Final Grade calculator.
- Backups: JSON schema version 1, CSV export, and local snapshots.
- Privacy: local Face ID/passcode-backed lock setting.
- Localization: English source strings plus Simplified Chinese strings.
- No App Intents, App Entities, App Shortcuts, Spotlight indexing, deep links, URL scheme, local notifications, syllabus OCR, PDF import, or Foundation Models integration exists at baseline.

## Baseline verification

Clean build command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild clean build -project AggieGPA.xcodeproj -scheme AggieGPA -destination 'platform=iOS Simulator,id=35DE4728-DCF7-4FD6-A1EE-65DF0739A110' CODE_SIGNING_ALLOWED=NO
```

Result: passed on iPhone 17 Pro / iOS 27.0 Simulator.

Unit test command used `-only-testing:AggieGPATests`; all 41 existing unit tests passed.

The first UI run used Xcode's default parallel testing. Seven of ten tests passed, then three failed before assertions because Xcode's simulator clone could no longer find the built `AggieGPA.app`. The affected tests were `testOpenPrivacyLockSetting`, `testOpenSettings`, and `testOpenWhatIfAndCreateScenario`. Re-running those exact tests with `-parallel-testing-enabled NO` executed all three and all passed. This is recorded as an Xcode 27 beta runner limitation, not hidden as a green first run. Full v1.1 UI runs should be serial.

## Warnings and limitations

- Xcode reports `IDERunDestination: Supported platforms for the buildables in the current scheme is empty` even though the simulator build succeeds.
- At baseline, metadata extraction warns that no `AppIntents.framework` dependency exists and no App Shortcuts are present; this matches the implementation.
- Xcode 27 beta logs debugger-version and duplicate simulator accessibility class diagnostics during UI tests.
- No physical-device build, signing, notification authorization, Siri, Shortcuts, Spotlight, or in-place install was claimed during this audit.
