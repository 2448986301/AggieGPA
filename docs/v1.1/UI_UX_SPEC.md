# UI and UX Specification

> Implementation status (2026-07-22): the existing Liquid Glass hierarchy and tab navigation are preserved; grade state is communicated with text and symbols, key views expose VoiceOver semantics, and the gradebook remains reachable at Accessibility XXXL.

Preserve the existing iOS 27 Liquid Glass language: current tabs/navigation/icon, deep navy and warm gold palette, large titles, generous corners, and restrained glass surfaces. Grade-item rows prioritize readable density and do not become heavy glass cards.

## Course Detail

A restrained hero shows course identity plus official grade, graded-work average/current letter, projected percentage/letter, graded/remaining weight, target, and projected GPA impact with explicit labels. Segments are Gradebook, Breakdown, and Forecast.

Gradebook lists title, category, due date, score/percentage, status, inclusion, drop, and extra-credit state. Breakdown shows category weight, average, contribution, graded/remaining/missing/dropped counts with simple progress visuals. Forecast edits scenarios only and shows expected/best/conservative/custom, required remaining average or final score, and feasibility.

Course and Quarter plus menus expose the specified add/import actions; Quarter-level assignment/exam creation selects a course first. Destructive item deletion provides undo.

## Dashboard and Quarter

Dashboard adds compact Upcoming, Courses at a Glance, and conditional Attention Needed sections. Quarter summaries choose only the most relevant two-to-four signals rather than placing every metric on one line.

## Accessibility

Support light/dark appearance, Reduce Transparency, Reduce Motion, Dynamic Type, VoiceOver, non-color status labels, long course names, and small iPhones. Gold is an emphasis color, contrast remains sufficient, and critical controls do not truncate.
