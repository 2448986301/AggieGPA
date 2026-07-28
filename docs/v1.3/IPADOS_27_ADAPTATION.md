# iPadOS 27 adaptation — Aggie GPA 1.3.0 build 17

## Scope

Aggie GPA remains one universal iOS/iPadOS target (`TARGETED_DEVICE_FAMILY = 1,2`),
with the existing bundle identifier and SwiftData store. No macOS target, AppKit,
Mac Catalyst target, second database, or duplicate calculation engine is introduced.

## Navigation

- Compact windows retain the existing iPhone `TabView`.
- Regular-width windows use `NavigationSplitView` for Today, Courses, GPA, and Settings.
- Courses adds a list-detail split that preserves the selected course UUID while the
  window changes size. A no-selection state provides clear wayfinding.
- Command-1 through Command-4 move between the four primary areas. Lists use the
  system selection, hover, pointer, keyboard-focus, and context-menu behavior.

## Layout and accessibility

- Today uses a two-column adaptive grid only when the available width is regular;
  narrow widths return to one column.
- Course Detail constrains long-form content to a readable maximum width and remains
  the shared implementation used by both platforms.
- Existing native sheets and forms remain bounded by their system presentation and
  retain cancel/save toolbar actions. Dynamic Type, reduce-transparency surfaces,
  VoiceOver labels, dark mode, and Simplified Chinese reuse the existing design system.

## Verification boundary

Build coverage confirms iPhone and iPad Simulator compilation. Visual, keyboard,
pointer, split-view, and language checks still require the Xcode-visible simulator
demonstration; no real iPad installation is part of this stage.
