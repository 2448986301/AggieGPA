# Implementation Plan

> Final status (2026-07-22): Phases 0–12 are implemented and committed; Phase 13 consists of final review, clean verification, same-identity device installation, branch push, and an unmerged pull request.

1. Baseline audit and source-of-truth specifications.
2. Versioned SwiftData v1/v1.1 models, safe container bootstrap, and migration fixtures.
3. Shared Decimal grade engine and edge-case tests.
4. Course Detail vertical slice and gradebook editing.
5. Forecast scenarios and projected GPA integration.
6. PDF/image/text extraction and deterministic syllabus parser.
7. Optional Foundation Models candidate parser with validation/fallback.
8. Local reminder reconciliation and notification deep links.
9. App Intent data service, entities, read/open/draft intents, Shortcuts, and privacy gates.
10. Dashboard and Quarter integrations.
11. JSON schema v2, v1 compatibility, CSV additions, atomic import/recovery.
12. Accessibility, bilingual copy, regression/migration/UI testing.
13. Final documentation, independent review, clean verification, feature-branch push, and unmerged PR.

Each stage follows inspect → test → implement → targeted test → build → commit. Suggested commit subjects from the product request are used where they match the actual change. Device signing, installation, permission prompts, and Siri voice verification are reported as manual checkpoints and never fabricated.
