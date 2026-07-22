# Calculation Specification

## One engine

`CourseGradeCalculationEngine` is the sole source for SwiftUI, Dashboard, Planner, Siri, Spotlight, and Shortcuts. Inputs and outputs are Sendable value snapshots rather than SwiftData objects. Calculations use `Decimal`, do not round internally, and format only at presentation boundaries.

## Methods

- Weighted categories: calculate each included category average first, then apply category weight. Category internals may use total points, equal items, or an explicitly supported custom rule.
- Total points: included earned points divided by included possible points, with extra credit handled separately and visibly.
- Hybrid: combine documented weighted-category and direct-point/special contributions and expose a calculation breakdown.
- Manual letter only: no synthetic percentage is produced.

## Inclusion rules

Exclude ungraded, submitted-but-ungraded, excused, dropped, not-counted, and disabled records. Apply explicit missing policy only to Missing items. Respect drop-lowest after exclusions, percentage override, multiplier, extra credit, scores above maximum, zero possible points, zero weights, unassigned categories, and incomplete/overweight category totals. Invalid or ambiguous inputs return issues and may require manual review.

## Outputs and terminology

- Official Course Grade: user-entered final letter; only this enters official GPA.
- Graded Work Average: normalized average of completed graded work.
- Earned Course Credit: contribution already earned toward the full course total.
- Calculated Current Grade: descriptive current result, never official.
- Projected Course Grade: scenario-derived final result.
- What-If Grade: transient simulation.
- Planner Selected Grade: explicit GPA-forecast input.

The engine returns current percentage/letter, graded and remaining weight, earned credit, projected final, best/worst possible result, remaining average needed, final-exam-needed only when the final is the sole remaining item, target feasibility, calculation breakdown, and validation issues.

Required-average handling includes already achieved (<0%), exact feasible values, impossible targets (>100% absent explicit extra-credit capacity), multiple remaining items, incomplete weights, drops, replacement rules, and curves. Replacement rules and curves require a confirmed deterministic representation; otherwise the result is Manual Review Required.

Projected GPA never changes official GPA. Planner computes clearly labeled projected quarter and cumulative GPA only after the user enables `Use Projected Grade in GPA Forecast` for a course.
