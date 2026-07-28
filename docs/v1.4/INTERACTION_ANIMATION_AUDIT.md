# Aggie GPA 1.4 Interaction & Animation Audit

**Audit date:** 2026-07-28  
**Baseline:** `feature/v1.4-grade-momentum-polish` at `dbe8988` (1.3.1, build 18)  
**Targets inspected:** iPhone 17 Pro and iPad Pro 13-inch (M5), iOS/iPadOS 27 Simulator  
**Scope:** Existing universal iOS/iPadOS app only. No data model, official-grade, bundle-identifier, or calculation-engine changes are proposed in this audit.

## Evidence and limits

The baseline app was built, installed, and launched on both simulators. The initial Today composition was visually inspected in both form factors:

- iPhone: one-column Today with Upcoming, My Courses, GPA Summary, floating Add, and tab bar.
- iPad: two-column Today with Upcoming/GPA at left and courses/attention state at right.

The present execution environment can boot, install, launch, and capture the simulators, but does not expose the Simulator or Xcode window to the UI automation accessibility bridge. Therefore, the audit distinguishes static/launch evidence and source-backed findings from gesture-specific observations. The latter must be replayed manually in the visible Demo 1 before they can be marked verified.

## Findings

| Priority | Page / operation | Finding | Apple Design principle | Proposed change | Reduce Motion behavior |
| --- | --- | --- | --- | --- | --- |
| P0 | App-wide state changes | Motion is currently scattered between literal durations and two generic springs (`spring` has bounce); a semantic contract is absent. | Purpose, craft, behavior over animation | Add a small `AggieMotion` token set: Immediate, Quick, Standard, Emphasized, Interactive, Reduced. Migrate only state-changing UI to the matching token. | Tokens resolve to no displacement or an opacity-only transition. |
| P0 | Course Detail / record score | The current score-save banner is text-only and does not show the changed course grade, forecast, or GPA; it also has no undo action. | Feedback, safety, spatial consistency | Introduce a safe-area score-impact summary populated from before/after engine snapshots, with detail and undo. Never show unchanged metrics. | Opacity-only banner; retain the semantic announcement and undo. |
| P0 | What-If | Existing What-If edits whole course letter grades and includes a path that can write simulated values to official records. It is not an assignment/category playground. | Agency, responsibility, safety | Replace the record-writing action in this flow with assignment/category simulation that remains scenario-only; add explicit save confirmation for a scenario, comparison, presets, and reset. Reuse the calculation engine. | Retain numeric value updates; remove movement and threshold scale effects. |
| P1 | Today / initial composition | On iPhone the three large stacked reading surfaces are clear, but the GPA card and course list share equal emphasis with the next actionable item. On iPad, the attention card can visually compete with course context. | Simplicity, hierarchy | Add a restrained Focus Next section only when a deterministic recommendation exists; make it subordinate to the next task and preserve the current two-column iPad composition. | Content appears immediately or fades; no cascade. |
| P1 | Courses / grade changes | Grade labels are plain text in several list contexts; a grade update can read as a jump. | Understanding, continuous feedback | Use `contentTransition(.numericText())` for grade and GPA values, scoped to the changed value rather than the row or list. | Keep numeric transition where supported; otherwise change instantaneously without a row move. |
| P1 | Course Detail / section change | The segmented section switch replaces a substantial content region without an explicit transaction or transition contract. | Spatial consistency, interruptibility | Apply a transaction with Standard or Reduced semantic animation only to the section content; avoid matched geometry for whole pages. | Cross-fade the replacement content, no lateral movement. |
| P1 | Add/edit sheets and DisclosureGroup | Sheets use platform presentation, but form expansion, validation, keyboard focus, and detent changes lack a shared transition review. | Response, familiarity | Retain system sheets; use Quick for disclosure/inline validation only, preserve focus, and never animate form-wide layout on validation. | Immediate validation and opacity-only disclosure content. |
| P1 | Delete and undo | Assignment deletion has a safe-area undo banner, but its appearance has no named motion token and timeout/restore behavior needs a single contract. | Agency, forgiveness, feedback | Use Standard entry/exit with a single undo duration and a status announcement; animate only the affected row. | Opacity-only banner and immediate list update. |
| P1 | iPad navigation and selection | `NavigationSplitView` keeps the correct compact/regular structure, but selection changes do not have an explicit stable-selection transaction. | Flexibility, spatial consistency | Preserve selection across tab/sidebar changes, make the detail replacement use native navigation behavior, and test pointer/keyboard focus manually. | No custom positional animation; native selection state only. |
| P2 | Grade Breakdown / What Do I Need | These calculation-heavy regions lack a dedicated explanation view and a consistently scoped numeric transition. | Understanding, responsibility | Add Why This Grade from the existing course engine output; distinguish current, forecast, incomplete weight, and ungraded work. | Values update without movement; VoiceOver receives only settled values. |
| P2 | GPA / forecast | Existing hero GPA uses `numericText` plus a generic spring. Forecast/current distinctions need consistently named styles across dashboard and planner. | Craft, clarity | Use the motion tokens and semantic labels; do not add chart animation until data changes are known and meaningful. | Numeric transition or immediate replacement only. |
| P2 | Semester workload | There is no native Semester Map view. | Wayfinding, understanding | Build a scroll-native, filterable timeline with selection state; do not add date dragging until confirmation and notification update paths are complete. | Native scrolling; selected state fades/changes color without movement. |
| P2 | Loading, empty, and error states | ContentUnavailableView coverage exists, but loading/error transitions and accessibility announcements are not consistently codified. | Feedback, accessibility | Use a stable content container, inline retry/error, and a single accessibility announcement after settled state. | Cross-fade or immediate replacement. |
| P2 | Localization and Dynamic Type | New 1.4 labels do not yet exist in the string catalog; long localized labels need iPad sidebar, sheet, and Dynamic Type checks. | Flexibility, craft | Localize through `Localizable.xcstrings`; favor `ViewThatFits`, multiline labels, and accessibility labels over truncation. | Unchanged; motion is independent of language length. |

## Pages requiring visible interaction replay

The following are deliberately not declared “visually verified” until Demo 1’s foreground iPhone and iPad run: Course Detail, Assignment List/Detail, Add Assignment, Add Exam, Record Score, deletion/undo, Grade Breakdown, What Do I Need, GPA, GPA Forecast, Syllabus Import, Settings, What's New, Version History, sheets, alerts, menus, navigation return, keyboard focus, and Reduce Motion / VoiceOver behavior.

## Native SwiftUI API palette to validate by compilation

| Semantic use | Native API |
| --- | --- |
| Immediate state | `Transaction(animation: nil)` / no animation |
| Quick controls and lightweight feedback | `withAnimation`, `Animation.easeOut`, `transaction` |
| Standard list/content changes | `withAnimation`, native `transition`, `Transaction` |
| Emphasized numeric change | `contentTransition(.numericText())`, limited `symbolEffect`, `sensoryFeedback` |
| Interactive native controls | `Slider`, `Stepper`, native scroll and sheet interactions; no custom physics engine |
| Navigation and layout | `NavigationStack`, `NavigationSplitView`, system `sheet`, `safeAreaInset`, `ViewThatFits` |
| Accessibility fallback | `@Environment(\\.accessibilityReduceMotion)`, `@Environment(\\.accessibilityReduceTransparency)`, `accessibilityAnnouncement` only after a settled value |

All APIs will be compile-validated against the installed iOS/iPadOS 27 SDK before use. `matchedGeometryEffect`, `phaseAnimator`, `keyframeAnimator`, and `navigationTransition` are intentionally not defaults: they will be used only where a concrete spatial continuity problem remains after native navigation and transactions are insufficient.

## Proposed implementation order after approval

1. Add the compact motion and feedback contract, then polish existing Today, Courses, Course Detail, add/edit, record-score, delete, and undo flows.
2. Build and run the first visible iPhone/iPad Demo; pause for approval.
3. Continue only after the requested `继续` confirmation with What-If Playground and Score Impact.

## Implementation progress

- Completed semantic motion and feedback tokens, What-If Playground, Score Impact, Focus Next, and Why This Grade.
- Completed Semester Map with calendar-safe week grouping, current-week context, course and assessment filters, compact iPhone browsing, and an expanded iPad layout.
- Semester Map deliberately does not support dragging due dates; editing continues through the existing assignment editor so reminder updates and user confirmation remain reliable.
