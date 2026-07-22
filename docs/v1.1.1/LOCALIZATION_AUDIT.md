# Localization audit

The baseline uses hard-coded English copy and an `AppCopy` helper. `Localizable.xcstrings` now covers the active student-first shell, Today, global Add, course-detail labels, and GPA summary. The remaining settings, import, advanced calculation, and legacy planner copy still need catalog migration before v1.1.1 completion.

The simulator check must verify English and zh-Hans Today, Add, course detail, breakdown, GPA, Settings, empty states, errors, and Dynamic Type. Dates and numbers must continue using the environment locale.
