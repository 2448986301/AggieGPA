# Aggie GPA version-history audit

Audit date: 2026-07-28

## Method and limits

This audit uses repository refs and commits, the version settings at those commits,
existing release documentation, `CHANGELOG.md`, `README.md`, and test records. The
repository has **no Git tags**, so commit IDs—not tags—are the durable references.
“Released” below means the repository contains a documented completed version; it
does not assert App Store distribution or a public release date. Dates are omitted
where the repository does not establish one.

| Version | Build | Primary commit / ref | Status | Evidence | Uncertainty |
| --- | ---: | --- | --- | --- | --- |
| 1.3.0 | 17 | Current branch `feature/v1.3-ai-syllabus-import` | Unreleased development version | Current project settings, syllabus-import and native iPad workspace source, changelog, and 1.3 documentation | Real-device Foundation Models and PCC availability remain unverified. |
| 1.0 (semantic 1.0.0) | 1 | `6a80167` on `main` | Documented baseline | `docs/v1.1/BASELINE_AUDIT.md`; project settings at commit; existing changelog | No Git tag; no separately recorded public release date. |
| 1.1.0 | 2 | `0b3418f` (`feature/v1.1-gradebook-siri`) | Documented completed development version | Project settings at ref; `CHANGELOG.md`; v1.1 product, acceptance, and test documents | The existing changelog date is retained as historical documentation; no tag proves a release artifact. |
| 1.1.1 | 3 | `704f243` (`feature/v1.1.1-student-first-ux`) | Documented student-flow checkpoint | Project settings at ref; v1.1.1 acceptance and verification documents | Existing changelog calls it “In progress”; it must not be presented as a confirmed public release. |
| 1.1.2 | 14 | `756ef1d` (`feature/v1.1.2-direct-siri-ai`, `$AppleDesign`) | Documented development version | Project settings at ref; Siri guides, limitations, and device-results record | Physical-device evidence validates one exact assignment App Shortcut route and Spotlight indexing only. It does not validate all Siri flows or Chinese Siri. |
| 1.2.0 | 15 | Current branch `feature/apple-design-unification` | Unreleased development version | Current project settings now show `MARKETING_VERSION = 1.2.0`, `CURRENT_PROJECT_VERSION = 15`; Apple Design commits follow `756ef1d` | Full regression matrix, visible review, push, and PR are still pending. |

## Version-by-version evidence

### 1.3.0, build 17

- **User-visible scope:** reviewable on-device syllabus understanding, page evidence,
  confidence and confirmation controls, removal of the prior OCR path, and a native
  iPad sidebar/list-detail workspace.
- **Do not claim:** a completed real-device Apple Intelligence run or PCC access.

### 1.0 (semantic 1.0.0), build 1

- **User-visible scope:** offline iPhone GPA tracking; term and course management;
  GPA/planning tools; import/export and local backups; privacy lock; English and
  Simplified Chinese; light/dark appearance and accessibility fallbacks.
- **Technical scope:** SwiftUI and SwiftData foundation, GPA calculation engine,
  tests, and the original app icon/privacy-lock fixes.
- **Evidence:** chronological commits `094ad57` through `6a80167`; project settings
  at `6a80167` show `MARKETING_VERSION = 1.0` and `CURRENT_PROJECT_VERSION = 1`;
  the baseline audit records the unchanged bundle identifier and signing team.
- **Do not claim:** an App Store release or a Git tag; neither is present.

### 1.1.0, build 2

- **User-visible scope:** per-course gradebook categories and grade items; current
  grade, forecasts, target/required-score tools, syllabus-assisted setup, local
  reminders, forecasts, and safer backup/import behavior.
- **Technical scope:** versioned SwiftData schemas, migration backup, backup schema
  v2, deterministic syllabus parsing with optional on-device refinement, and
  privacy-gated App Intents/Shortcuts.
- **Evidence:** commits `270bc88` through `0b3418f`; project settings at `0b3418f`
  show `MARKETING_VERSION = 1.1.0` and `CURRENT_PROJECT_VERSION = 2`; the existing
  changelog, product specification, acceptance criteria, and test plan describe
  the completed scope.
- **Do not claim:** end-to-end Siri speech verification; v1.1 documentation lists
  it as a device-only manual check.

### 1.1.1, build 3

- **User-visible scope:** student-first course grade flow, reachable first-term
  setup, clearer Today and global add entry points, simplified course detail and
  GPA language, and broader English/Simplified Chinese visible-copy coverage.
- **Technical scope:** gradebook-flow regression coverage, stale-relationship
  hardening, and data-safe course deletion behavior.
- **Evidence:** commits `fd5d870` through `704f243`; project settings at `704f243`
  show `MARKETING_VERSION = 1.1.1` and `CURRENT_PROJECT_VERSION = 3`; v1.1.1
  acceptance tests and verification documentation.
- **Status caveat:** the root changelog says “In progress.” Treat it as a documented
  development checkpoint, not a confirmed public release.

### 1.1.2, build 14

- **User-visible scope supported by evidence:** optional, privacy-gated Siri access
  and draft confirmation controls; one verified exact App Shortcut phrase for
  assignment summaries; Spotlight course indexing; expanded bilingual Siri
  guidance and explicit limitations.
- **Technical scope:** App Group shared snapshot, App Intent entities and metadata,
  persistent-store hardening, and Apple Design-branch baseline.
- **Evidence:** commit `756ef1d`; project settings at that commit show
  `MARKETING_VERSION = 1.1.2` and `CURRENT_PROJECT_VERSION = 14`; device-results
  and limitation documents under `docs/v1.1.2`.
- **Do not claim:** arbitrary natural-language Siri, native in-app search/open,
  Chinese Siri, grade/GPA/draft flows, or complete Siri AI verification. The
  documented evidence explicitly leaves those unverified.

### 1.2.0, build 15

- **Planned user-visible scope, pending approval and version bump:** the current
  branch’s unified Apple Design work across Today, Courses, grade entry, GPA,
  Settings, global status feedback, bilingual layout, and accessibility polish.
- **Evidence for branch work:** Apple Design commits `8bbeeb5` through `06d3426`.
- **Status:** versioned and release-noted in the current branch, but not yet fully
  regression-tested, pushed, or proposed for merge. It remains **Unreleased**.

## Proposed user-facing release-note entries for approval

These are intentionally concise and omit unverified Siri claims.

### 1.2.0 — Unreleased

- Unified Apple-inspired design system across the iPhone app.
- Clearer Today, Courses, Course Detail, grade-entry, and GPA experiences.
- More restrained Liquid Glass, with clearer hierarchy and fewer layered surfaces.
- Refined Settings, syllabus import, feedback states, English, Simplified Chinese,
  Dynamic Type, and VoiceOver support.

### 1.1.1 — Development checkpoint

- Made first-term setup and the student course-grade flow easier to reach.
- Improved Today, global add, course detail, grade guidance, and visible bilingual
  copy.
- Kept ungraded work excluded from current-grade calculations.

### 1.1.0 — Documented completed development version

- Added course gradebooks, weighted categories, assignments/exams, and score entry.
- Added current-grade forecasts, targets, required-score calculations, syllabus
  import, reminders, and safer backup migration.
- Added privacy-gated App Intents and Shortcuts with confirmation before writes.

### 1.0 — Documented baseline

- Added offline term, course, GPA, and planning tools with local import/export and
  privacy lock.
- Added English and Simplified Chinese, light/dark appearance, and accessibility
  foundations.

## Source inventory

- Git refs and chronological history: `main`, `feature/v1.1-gradebook-siri`,
  `feature/v1.1.1-student-first-ux`, `feature/v1.1.2-direct-siri-ai`, and
  `feature/apple-design-unification`.
- Build settings: `AggieGPA.xcodeproj/project.pbxproj` at commits `6a80167`,
  `0b3418f`, `704f243`, `756ef1d`, and the current branch.
- Product and verification documents: `CHANGELOG.md`, `README.md`, `TESTING.md`,
  `docs/v1.1/*`, `docs/v1.1.1/*`, and `docs/v1.1.2/*`.
