# Notifications Specification

> Implementation status (2026-07-22): stable per-item identifiers, schedule/update/cancel behavior, permission handling, course deep links, and automated scheduler tests are implemented. Authorization presentation remains a real-device manual check.

Use `UNUserNotificationCenter` local notifications only. Grade items may choose off, one day, three days, one week, or a custom date/time. Assignments and exams may have different defaults.

Authorization is requested only in response to user intent. A deterministic identifier derived from the GradeItem stable ID prevents duplicates. Create/update reconciles requests; due-date edits reschedule; delete cancels; app launch performs a bounded reconciliation. Denial never blocks gradebook use.

Notification content respects privacy settings. Tapping a notification opens the exact Grade Item or Exam through the shared deep-link router. Tests use an injectable notification client and verify create, update, cancel, deduplication, denial, and routing.
