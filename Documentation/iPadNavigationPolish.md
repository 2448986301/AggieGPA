# iPad navigation and UI refinement

Status: focused changes implemented and simulator-verified on 11 September 2026. Physical-device frame profiling remains unverified. Not published.

本轮已修正 iPad 顶部白色断层：分栏页面延伸至原生标签栏后方，滚动时保留系统边缘模糊。搜索、切换状态保留、课程保存、模拟范围和大字号均已完成针对性验证。重复切换测试耗时降低约 25.5%，但首次打开延迟及真机掉帧仍未证明改善。

## Source and preservation

- Working branch: `codex/ipad-navigation-polish`, created with the user's approval from `36ea03c`.
- Persistent workspace: `/Users/easonzhou/Documents/AggieGPA-iPad-Polish`.
- The original `/Users/easonzhou/Documents/UCD` checkout and its changes remain untouched.
- The previous temporary worktree no longer exists. This is a reconstruction of the relevant UI changes, not a claim that every prior uncommitted change has been recovered.
- Before testing, the previously installed simulator app was preserved in `/Users/easonzhou/Documents/AggieGPA-iPad-Polish-Artifacts/PreviouslyInstalled-AggieGPA.app`.
- No data deletion, physical-device installation, model download, branch publication, or release is part of this work.

## Apple design references

- [Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields): a clear search scope and a native placement.
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): stable top-level destinations.
- [Enhancing content with tab navigation](https://developer.apple.com/documentation/swiftui/enhancing-your-app-content-with-tab-navigation): a system-owned adaptable tab/sidebar hierarchy.
- [SwiftUI navigation](https://developer.apple.com/documentation/swiftui/navigation): adaptive split views and stateful navigation.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): keep navigation in a distinct functional layer, audit custom backgrounds and safe areas.

The Apple Design review focuses on stable navigation, immediate input, typography, and appropriate native controls. It does not replace the existing app, data model, icon, or Liquid Glass identity.

## Findings and changes

| Area | Finding | Change |
| --- | --- | --- |
| iPad navigation | Switching Courses replaced the complete two-column root with a different three-column root. Resizing could replace it again with the phone hierarchy. | One native sidebar-adaptable TabView throughout iPad resizing; per-destination navigation state. |
| Search | A sidebar action switched to Courses and competed with its automatic search placement; the request observer could miss the first newly mounted request. | Dedicated native search-role tab, a single course-scoped search field, preserved search text and separate selection. |
| Touch handling | A window-wide tap recognizer used the default delayed end delivery and participated in native control gestures. | No touch delays/cancellation; ignore controls and allow simultaneous recognition. |
| Course list | A fixed 168-point grade column crowded the course identity; repeated computed properties resolved the same grades multiple times per row. | Stacked iPad list rows; one planning and grade snapshot evaluation per row update. |
| Course summary | Percentages could split across lines within the three-column summary. | Keep each numeric value indivisible so the existing adaptive layout can choose a taller arrangement. |
| Full simulation | Restore recent compact controls and scope/target recomputation. | A-first grade choices, 76-point default target capsule, adaptive large-text layout, rounded summary; excluded courses stay selectable. |
| Save feedback | The older source dismissed course editing before a delayed save and silently ignored several editor errors. | Save before dismissing; preserve drafts and show a localized failure alert. Template creation gets a visible completion message. |
| Top white strip | The nested course split view stopped at the enclosing tab safe area, exposing a contrasting outer background and clipping the scrolling canvas. | Extend the split container through the top container safe area and provide its semantic grouped canvas. Native column navigation bars continue managing foreground insets; scrolling content now passes behind the top tab bar with the system scroll-edge effect. Do not mirror the entire navigation hierarchy: that also reflects toolbar text and bottom-edge content. |

## Evidence boundaries

UI tests use isolated in-memory demo data. XCTest wall times include event synthesis, accessibility queries, and idle waits; they are not input-to-photon measurements or frame-rate measurements. Simulator behavior is not a claim of physical iPad performance.

The initial baseline and intermediate results are retained outside the repository under `/Users/easonzhou/Documents/AggieGPA-iPad-Polish-Artifacts`.

## Measured verification (10–11 September 2026)

- Xcode 27.0 (27A266a), `/Applications/Xcode.app`; iPad Pro 11-inch (M5) and iPhone 17 Pro simulators. The previous `Xcode-beta.app` path is not present.
- Final source build-for-testing: `verified-source-build-02.log`, succeeded (only explanatory comments were added afterward).
- Core suite: `final-core-tests.xcresult`, 215 executed, 2 skipped, 0 failures (213 passed). Includes migration/data safety, calculations and both keyboard-recognizer tests. Existing visual-golden tests were excluded, not silently re-recorded. The later canvas-only change was built and checked through focused UI tests.
- iPhone functional regression: `final-iphone-functional.xcresult`, 5 passed. Course save, preserved draft/failure/retry, target/scope editing, search to canonical detail, Settings.
- iPad functional suite: `final-ipad-functional.xcresult`, 8 passed and one test assertion failed. The failure was a test assuming text inserted at the end after tapping the middle of the field; the test now checks the actual edited draft. Its focused rerun is recorded separately below. Passing cases include native search/query preservation, Chinese labels, portrait/landscape tab interaction, Quick Add, template navigation, full-simulation navigation/grade recovery and target/scope editing.
- iPhone maximum accessibility text size: `phone-accessibility.xcresult`, 1 passed. The simulator's actual text-size setting was changed, rendered control dimensions were asserted, and the setting was restored to `large` afterward.
- iPad maximum accessibility text size: `ipad-accessibility.xcresult`, 1 passed. Visual review found an untranslated reachability warning; its Chinese catalog entry was subsequently added.
- Final localized iPad maximum-text check: `ipad-accessibility-localized-02.xcresult`, 1 passed, including an assertion for the Chinese reachability warning. Both simulators were confirmed restored to `large` text size.
- `glass-final-ui.xcresult`: 3 passed, including the corrected course-save assertion, light/dark scrolling and landscape Quick Add.
- `glass-layout-final.xcresult`: 2 passed after the final top-safe-area adjustment, covering light/dark scrolling, retained search, tab interactions and portrait/landscape adaptation. The screenshots show content behind the tabs rather than a full-width opaque strip.
- `glass-layout-compile-check.xcresult`: 2 keyboard-recognizer tests passed after the safe-area adjustment.
- Actual simulated iPad window resizing was performed with the system resize handle. Selected CHE 002A remained open as the course column collapsed; the native bar accommodated the smaller window. Full-screen size was restored and the course selection persisted. This is real window-resizing evidence, separate from orientation tests; it does not assert coverage of every possible window size.

### Navigation timing

The same XCTest repeated Courses → GPA → Today cycle (three repetitions) changed from **7.295 s** baseline to **5.433 s** after navigation/row changes, approximately **25.5% lower**. Measured CPU time changed from **0.256 s** to **0.179 s**, approximately **30% lower**. Bundles: `baseline-timing.xcresult` and `native-navigation-03.xcresult`. This is a test-harness cycle metric, not the duration of a single tap or an FPS claim.

Cold first Courses navigation did **not** demonstrate an improvement: baseline 2.014 s versus later 2.30–2.42 s, including XCTest idle and accessibility waits. Do not describe first-frame latency as solved from these figures. Quick Add used a different native menu route after the redesign, so its old/new timings are not directly comparable.

An Animation Hitches recording was attempted against only the simulated app. Instruments returned **“Hitches is not supported on this platform.”** The saved trace is a failed recording, not frame-time or zero-hitch evidence. Physical-device frame profiling remains a separate acceptance step.

## Follow-up: Today computation during tab switching

Time Profiler identified repeated target solving inside the reminder-sort comparator. `InsightPriorityEngine.rank` now builds one scoring context per referenced course and computes each reminder score once before sorting. Contexts are invocation-local, not persistent caches: edits, forecast changes and the current date remain inputs on every call. Priority weights, tie-breaking, reminder content and official grades are unchanged.

- `ranking-performance-02.xcresult`: 6 focused tests passed, including score/content/tie preservation, refresh after edits/time changes, explicit priority weights and deterministic insight rules. The same 24-reminder fixture averaged 278.6 ms using the old comparator algorithm and 2.63 ms using precomputed contexts (five iterations each). This is only a sorting microbenchmark.
- Matched manual-input simulator recordings: `navigation-before-timeprofiler.trace` and `navigation-after-timeprofiler.trace`, 20 seconds each, fresh app launch with the same demo/course-detail arguments and four Today → Courses → GPA cycles (12 native mouse taps). The final screenshot confirms GPA was reached. Courses was the initial destination, so this comparison does not establish cold first-Courses latency.
- Inclusive main-thread sampled weights: reminder ranking **705 → 27 ms**, Today body **836 → 199 ms**, all main-thread samples **2691 → 2118 ms**. These are aggregate CPU sample weights over each recording, not wall-clock response times; inclusive rows overlap and must not be added. One recording per version is directional evidence, not a statistical frame-latency benchmark.
- Instruments reported one unknown-input-table warning for each recording; the symbolic Time Profiler tables exported successfully. No animation-hitch or input-to-photon claim is made.
- `ranking-navigation-final.xcresult`: all 3 iPad UI tests passed (readable insight width, Today priority sections/timeline navigation, repeated tab switching). The repeated warm-cycle metric was 5.428 s with 0.183 s CPU time, effectively unchanged from the earlier 5.433 s / 0.179 s result. The new fix reduces the profiled Today computation; this warm-cycle test does not demonstrate a further end-to-end speedup.

## Follow-up: course summary calculations

The cold-Courses trace showed repeated `planningState` evaluation inside the grade hero's adaptive layout candidates and accessibility values. The summary now evaluates planning state and grade result once per summary refresh and passes them to all candidates. This is not a persistent cache; calculation rules and saved records are untouched. The Apple Design response principle informed this change without removing adaptive layout or accessibility feedback.

- `summary-build.log`: build-for-testing succeeded.
- `summary-ui.xcresult`: 4 iPad UI tests passed: current/projected/target and opportunity action, Chinese lifecycle labels and 44-point targets, projected grade edits refreshing GPA, and final grade replacing projected grade.
- `course-cold-before.trace` / `course-cold-after.trace`: 15-second Time Profiler recordings, fresh demo launch initially on Today with course-detail selection prepared, followed by the same four Today → Courses → GPA cycles. Inclusive main-thread sample weights for course body were **149 → 59 ms**, summary **98 → 11 ms**, planning state **89 → 6 ms**. These overlapping weights are not additive or per-click wall times. The before build predates both the reminder-ranking fix and this summary fix; the course-specific stacks support the local improvement, but this is not an isolated whole-app A/B experiment. Both traces have the previously noted unknown-input-table warning; symbolic export succeeded.
- The final native-input screenshot confirms arrival at GPA. Cold input-to-first-frame latency and physical-device hitches remain unverified; no claim of eliminating all tab delay is made.

## Follow-up: fresh-process course readiness

**Invalidated as course-detail acceptance:** `cold-course-readiness.xcresult` passed three process launches, but visual review found PSC 001 in the final screenshot after the test requested CHE 002A. The test checked generic grade controls without verifying the destination's course identity. The figures below are retained as diagnostic history, not proof that the requested course opened. An identity assertion is now being added and the mismatch investigated. All data is isolated demo data; no physical devices were used.

| Trial | Courses row ready | Course detail controls ready |
| --- | --- | --- |
| 1 | 2.682 s | 1.225 s |
| 2 | 2.464 s | 1.246 s |
| 3 | 2.356 s | 1.281 s |
| Median | 2.464 s | 1.246 s |

These are XCTest tap-to-accessibility-readiness totals, not screen first-frame times. For Courses, tap return alone took 1.985–2.287 s and the readiness queries another 0.371–0.395 s. The test's response timeout applies after `tap()` returns, not as a total latency budget. Fresh process does not mean OS caches are cold. Earlier checks used a weaker element-existence condition, so these figures do not establish a comparable speedup. Course-detail identity was not verified; the detail result is invalid.

## Correction: course row taps were intercepted

- `cold-course-identity.xcresult` reproduced the defect after adding a course-title assertion: tapping the correctly labelled CHE 002A row (frame x16/y550.5/w288/h133.5) left PSC 001 selected. The attached screenshot confirms the mismatch; this was not merely a missing accessibility element.
- Removing the row's additional `simultaneousGesture(TapGesture())` and reacting to native selection changes made the same identity-aware test pass all three launches (`cold-course-native-selection.xcresult`). This isolates the row gesture as the interfering change in the observed configuration. Native NavigationLink remains responsible for navigation; no replacement tap recognizer or timing delay was added.
- Opening templates now clears the course selection, because templates occupy the detail destination. Selecting the same course again produces a native selection change and returns from templates. Selection changes to nil do not close templates.
- `course-selection-final.xcresult`: 2 tests passed, covering three identity-verified first visits plus CHE 002A → templates → CHE 002A. The first-visit test checks both actual course title and operable projected/target controls, then opens the grade menu. Final source timing excludes diagnostic screenshot work: Courses totals 3.111/2.580/2.521 s; CHE detail totals 2.461/2.080/1.337 s. These remain harness/accessibility metrics, not a speedup comparison with the invalid earlier check.
- The shared iPad `openDemoCourse` test helper now asserts the requested course identity. Earlier generic-element checks should not be treated as course-specific proof without that verification. Existing computation profiles with explicit screenshot course selection remain separate evidence.
- `course-identity-grade-regression.xcresult`: both final-grade replacement and projected-grade-to-GPA synchronization passed again using the strengthened course-identity helper. This is the verified replacement for relying on their earlier generic-destination checks.
- `independent-course-selection.xcresult`: one additional scenario passed, checking CHE 002A → BIS 002B → PSC 001 → CHE 002A with an explicit detail-title assertion after every tap. Search then selects BIS 002B; returning to Courses retains CHE 002A, returning to Search retains both the BIS query and BIS 002B detail, and landscape rotation preserves these separate selections. The [landscape screenshot](Screenshots/ipad-native-2026-09-11/independent-selection-landscape.png) was visually reviewed and confirms the selected CHE 002A row matches the detail. This follow-up changed tests/documentation only, not application logic. It is selection/state evidence, not a latency benchmark or a narrow-window test.
- [Verified selected row and matching CHE 002A detail](Screenshots/ipad-native-2026-09-11/course-selection-verified.png). The Apple Design principle applied here is to preserve native gesture ownership and react to navigation state, rather than layering another tap recognizer over it.

## Reviewed screenshots

### Course-row grouping requested in screenshot review

The user noted that the separate, relatively heavy Current line looked like another course. Compact iPad rows now place the current/final grade beside the course code in smaller secondary text on the same baseline. Course title, units, projected grade/graded progress and final-report status stay in the same logical, selectable row. The native NavigationLink and combined accessibility identity are unchanged; iPhone's existing row layout is retained. This follows the Apple Design grouping and typography principles rather than adding another card or badge.

`ViewThatFits` uses a tightly spaced vertical heading/grade group when horizontal space is insufficient. A maximum Chinese accessibility-size screenshot initially revealed list-label truncation; explicit unlimited line wrapping and vertical sizing fixed the grade and final-status ellipses. The simulator was restored to `large` afterward. Grade calculation and official records are unchanged.

- `integrated-course-row.xcresult`: independent course/search identity and search empty/recovery tests passed, including landscape selection.
- `integrated-course-row-accessibility-build.log`: final wrapping adjustment built successfully; maximum accessibility-size Chinese rendering was visually reviewed.
- `integrated-course-row-final.xcresult`: search empty/clear/reselection passed on the final wrapping build; its default-size screenshot was visually reviewed and replaces the earlier row image below.
- [Default row grouping](Screenshots/ipad-native-2026-09-11/integrated-course-row.png)
- [Maximum text size, Chinese](Screenshots/ipad-native-2026-09-11/integrated-course-row-accessibility-zh.png)

Course-row closeout checks:

- `course-row-closeout-ipad.xcresult`: 2 tests passed, verifying final B+ replaces current/projected/pending labels in the same sidebar row and Chinese current-grade text retains the expected 88.14% / B+ value. Final-grade screenshot was visually reviewed.
- `course-row-closeout-iphone.xcresult`: the iPhone course-list regression passed; current 88.14%, projected 87.43% and final-pending labels remain present. The [iPhone screenshot](Screenshots/ipad-native-2026-09-11/iphone-course-row-regression.png) confirms the existing layout and gold projected text are retained. The existing narrow Major label wraps; this is not a claim of a full iPhone layout audit.
- Visual review exposed gold projected text disappearing against the gold selected-row background on iPad. Compact rows now use semantic secondary text for projected grades, following Apple Design's native selection and text hierarchy principles; the iPhone style is unchanged.
- `course-row-selected-contrast.xcresult`: the Chinese row test passed again after that style adjustment. The [final selected-row screenshot](Screenshots/ipad-native-2026-09-11/integrated-course-row-selected-zh.png) was visually reviewed: projected text is now visible and selected CHE 002A matches the detail. This is a visual correction, not a measured WCAG contrast certification. The earlier iPhone and final-grade tests preceded this iPad-only color change.

Search empty-state follow-up: `search-empty-localized.xcresult` passed both the English no-results/clear/reselect flow and the Chinese empty-state test. No matches remove the old grade hero and editing controls; clearing search restores selectable courses, while Courses and Search keep separate selections. Visual review found that the native query-in-title variant truncated in the sidebar, so the native ContentUnavailableView now uses an explicit short localized title (No Results / 无搜索结果) with localized guidance. The query stays in the search field. The parameterless `.search` variant also failed the short-title assertion and is not the final implementation.

Original, unedited simulator PNGs:

- [Search, light](Screenshots/ipad-native-2026-09-11/search-light.png)
- [Search, light, scrolled beneath tabs](Screenshots/ipad-native-2026-09-11/search-light-scrolled.png)
- [Search, dark, scrolled](Screenshots/ipad-native-2026-09-11/search-dark-scrolled.png)
- [Full simulation, compact default controls](Screenshots/ipad-native-2026-09-11/full-simulation.png)
- [Resized iPad window, selected course retained](Screenshots/ipad-native-2026-09-11/resized-window.png)

## Remaining acceptance boundaries

- Physical-device first-frame latency and animation-hitch profiling have not been verified in this simulator-only pass.
- This is the focused navigation, course/save and simulation UI refinement, not a claim that every screen in the app has been redesigned or all former temporary AI work recovered.
- No publication, release artifact, physical-device installation or model download was performed.
