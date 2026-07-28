# Gradebook Specification

> Implementation status (2026-07-22): course detail, policy, categories, grade items, breakdown, multiple forecasts, reminders, undo, and manual-review states are implemented.

## Ownership and models

Each `CourseRecord` may own one `CourseGradingPolicy`, zero or more `GradingCategory`, `GradeItem`, `GradeScaleBoundary`, and `ForecastScenario` records. All use stable UUIDs, timestamps, explicit raw-value enums, and safe defaults.

`CourseGradingPolicy` stores grading method (`weightedCategories`, `totalPoints`, `hybrid`, `manualLetterGradeOnly`), normalization choice, explicit missing-item policy, targets, import source/status, manual-review reason, and calculation timestamps.

`GradingCategory` stores name, category type (homework, quiz, lab, discussion, participation, attendance, project, presentation, midterm, final exam, extra credit, custom), weight, calculation mode (weighted category, total points, equal items, custom), drop-lowest count, extra-credit/inclusion flags, ordering, and timestamps.

`GradeItem` stores course/category links, title, due date, optional earned points, possible points, optional percentage override, status, inclusion/extra-credit/dropped/excused flags, multiplier, notes, reminder configuration, and timestamps. Statuses are upcoming, submitted, graded, missing, excused, dropped, and not counted.

`GradeScaleBoundary` supports A+ through F with course-specific percentage thresholds. A Common Scale Template may be offered only as a clearly labeled editable template; it is not an official UC Davis scale. Scale prediction can be disabled; curve notes and manual-review state are retained.

`ForecastScenario` supports best case, expected, conservative, finals goal, and custom assumptions. It references stable item/category IDs or stores value snapshots and never mutates official grade items.

## Editing

Course Detail supports add, edit, delete with undo, duplicate, search, category filter, date sort, batch entry preview, Save and Add Another, and quick Missing/Excused/Dropped actions. Batch paste is parsed into an editable preview and only persists after confirmation.

Ungraded and submitted-but-ungraded items remain nil and are not zero. Only an explicit Missing status combined with a confirmed zero policy can contribute zero.
