# Acceptance tests

## Verified P0 coverage

- Add a course and select a breakdown template.
- Add assignments or exams without entering a score.
- Record earned and possible points in the dedicated score form.
- Verify category averages and current course grade refresh after a score edit.
- Verify an ungraded item is excluded and a confirmed missing item is the only zero-counted case.
- Verify final recorded grades remain separate from projected GPA input.

`AggieGPAUITests.testStudentCoreFlowRecordsAnUpcomingScore` covers the student-facing score path: it opens a demo course, records a score for an upcoming assignment, saves it, and verifies that the item becomes graded. `CourseGradeCalculationEngineTests` separately covers category weighting, immediate recalculation, ungraded exclusion, and the explicit missing-as-zero confirmation rule.

`AggieGPAUITests.testClearDemoDataKeepsDashboardUsable` verifies that clearing demo data returns to a usable empty Today dashboard. `DataSafetyTests` verifies that the same operation preserves personal courses while removing the demo course's grading policy, categories, items, scale, and forecast; its replace-import coverage verifies the same dependent-first cleanup order.

## Remaining release checks

- The iPhone 17 Pro Simulator smoke check covers English and zh-Hans Today and Settings, including the persisted picker values for grading basis and appearance. Complete the visual matrix for grade breakdown, GPA, empty and error states whenever those screens change.
- Dynamic Type and light/dark visual audit remain required for Today, course detail, grade breakdown, GPA, Settings, empty states, and errors.
- The same bundle identity was installed over v1.1.0 on a connected iPhone 17 Pro and launched successfully as v1.1.1 (build 3). The latest debug update is installed, but iOS currently requires the device owner to re-trust the development profile before a new physical walkthrough can run. A manual on-device walkthrough remains the final visual release check.
