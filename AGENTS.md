# Aggie GPA

Aggie GPA is an existing iOS 27 SwiftUI and SwiftData app. v1.1 extends the shipped v1.0 in place; it is not a replacement project.

## Build and test

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild clean build -project AggieGPA.xcodeproj -scheme AggieGPA -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project AggieGPA.xcodeproj -scheme AggieGPA -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

## Non-negotiable rules

- Never destroy or hide v1.0 terms, courses, official grades, GPA data, preferences, privacy settings, scenarios, or backups.
- Never work directly on `main`; use `feature/v1.1-gradebook-siri`.
- Official grades and projected/calculated grades are separate and projected values never overwrite official records.
- Ungraded work is excluded, never silently treated as zero.
- Preserve the existing Liquid Glass visual language, navigation, and app icon.
- Detailed requirements and acceptance criteria live in `docs/v1.1`.

## Done

v1.1 is complete only when migration and backup recovery are verified, the gradebook vertical slice works, clean build and core tests pass, the unchanged bundle identity can update v1.0 in place, documentation is current, and an unmerged PR is open.
