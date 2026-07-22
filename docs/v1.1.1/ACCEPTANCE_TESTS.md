# Acceptance tests

## Verified P0 coverage

- Add a course and select a breakdown template.
- Add assignments or exams without entering a score.
- Record earned and possible points in the dedicated score form.
- Verify category averages and current course grade refresh after a score edit.
- Verify an ungraded item is excluded and a confirmed missing item is the only zero-counted case.
- Verify final recorded grades remain separate from projected GPA input.

`AggieGPAUITests.testStudentCoreFlowRecordsAnUpcomingScore` covers the student-facing score path: it opens a demo course, records a score for an upcoming assignment, saves it, and verifies that the item becomes graded. `CourseGradeCalculationEngineTests` separately covers category weighting, immediate recalculation, ungraded exclusion, and the explicit missing-as-zero confirmation rule.

## Remaining release checks

- Full English and zh-Hans visual audit of every active catalog string.
- Dynamic Type and light/dark visual audit for Today, course detail, grade breakdown, GPA, Settings, empty states, and errors.
- Visible iPhone 17 Pro Simulator walkthrough of the complete student path; physical-device walkthrough remains required before release.
