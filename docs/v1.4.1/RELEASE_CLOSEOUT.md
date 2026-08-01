# Aggie GPA 1.4.1 release closeout

**Scope:** the existing universal iOS/iPadOS Aggie GPA app only. This release keeps
the existing project, bundle identity, SwiftData store, app icon, navigation, and
offline-first privacy model.

## Release identity

| Item | Value |
| --- | --- |
| Marketing Version | `1.4.1` |
| Build Number | `21` |
| Bundle Identifier | `com.easonzhou.aggiegpa` |
| Signing Team | `LWND9UDGR2` |
| Target / Scheme | `AggieGPA` / `AggieGPA` |
| Supported platforms | `iphoneos iphonesimulator` |
| Targeted device family | iPhone and iPad (`1,2`) |

## App-facing release note

English:

- Added course templates for quickly reusing grading structures.
- Added bulk creation for assignments, exams, and labs.
- Added local academic insights based on calculated course data.
- Improved local backup, restore, and data export.
- Improved assignment editing, deletion, and undo.
- Resolved some known issues and improved app stability.

简体中文：

- 新增课程模板，可快速复用课程评分结构；
- 新增批量创建作业、考试和实验；
- 新增基于实际成绩计算的本地学业提示；
- 改进本地备份、恢复和数据导出；
- 优化作业编辑、删除和撤销体验；
- 解决了一些已知问题，并改进应用稳定性。

The final note will include only the four local capabilities and interaction fixes
that are implemented and verified on this branch.

## Release constraints

- Keep full-swipe deletion, but require confirmation before SwiftData mutation.
- Keep Undo in the existing Liquid Glass feedback banner and above the tab bar.
- Keep official grades separate from projected or simulated calculations.
- Do not add a macOS target, AppKit, Mac Catalyst, CloudKit, PCC, Foundation Models,
  push notifications, App Groups, or other new Personal-Team-incompatible
  entitlements. Existing optional Siri/App Group compatibility code is retained
  only to preserve the existing store path and safe fallback behavior.
- Do not uninstall the existing app, clear user data, modify `main`, force-push, or
  create a release tag.

## Verification record

This table is updated only with evidence from the current 1.4.1 checkout.

| Area | Result | Evidence |
| --- | --- | --- |
| Project identity and iOS-only target | Verified | `MARKETING_VERSION = 1.4.1`, `CURRENT_PROJECT_VERSION = 21`, iOS device families `1,2`; branch `feature/v1.4.1-local-improvements` |
| Clean iPhone Simulator build | Verified | Xcode-beta `xcodebuild build`, iPhone 17 Pro, `** BUILD SUCCEEDED **`; final build output in `/private/tmp/AggieGPA-final-build3-dd-20260802` |
| Unit tests | Verified | final Xcode-beta `xcodebuild test`, `AggieGPATests`, 100 tests, 0 failures; result `/private/tmp/AggieGPA-final-unit3-results-20260802.xcresult` |
| Runnable iPhone UI tests | Verified | focused iPhone UI result, 4 tests, 0 failures; See All/detail return and no score-editor regression included; final width/demo result, 2 tests, 0 failures; result `/private/tmp/AggieGPA-final-width-demo-results-20260802.xcresult` |
| iPad Simulator UI | Verified | iPad Pro 13-inch (M5) UI result, 1 test, 0 failures; list and Template Preview columns visible |
| SwiftData migration and backup safety | Verified | migration/data-safety coverage included in 100 passing unit tests |
| Real iPhone in-place install | Verified | Existing `com.easonzhou.aggiegpa` `1.4.0 (19)` was updated in place to `1.4.1 (21)` on Eason’s iPhone; `devicectl` install and launch succeeded; no uninstall or data reset |
| Real iPad in-place install | Verified | Existing `com.easonzhou.aggiegpa` `1.4.0 (19)` was updated in place to `1.4.1 (21)` on Eason’s iPad; `devicectl` install and launch succeeded; no uninstall or data reset |
| GitHub branch and pull request | Pending final commit | remote branch and PR URL |

## Known limitations

- The four new capabilities remain local-only and do not depend on Apple Developer
  Program services, iCloud, CloudKit, Foundation Models, Siri, or TestFlight.
- Xcode-beta visibly launched the current build on iPhone 17 Pro and iPad Pro
  13-inch (M5); the signed build was also installed and launched on the connected
  iPhone and iPad in place.
- The final iPhone checks verify that the Academic Insights module has the same
  outer frame as gradebook rows and that BIS 002B, UWP 007, and PSC 001 show
  varied recorded demo scores. Those demo values are deterministic so screenshots
  and UI tests remain reproducible.
