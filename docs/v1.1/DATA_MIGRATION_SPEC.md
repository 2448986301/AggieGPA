# Data Migration and Backup Specification

> Implementation status (2026-07-22): versioned SwiftData v1→v2 lightweight migration, verified pre-migration JSON recovery backup, schema-v2 export, schema-v1 decode compatibility, transactional import, and relationship-restoration tests are complete.

## Store migration

Define explicit v1.0 and v1.1 `VersionedSchema` types plus a `SchemaMigrationPlan` when supported by the shipping iOS 27 SDK. v1.0 includes the eight audited model types; v1.1 adds gradebook models and additive defaults while preserving original stable identifiers and relationships.

Before opening a v1.0 store for migration, locate and record the existing `AggieGPA` store URL and sidecars, create and decode-verify a recovery JSON backup where the existing schema can be opened, and never overwrite the source with an empty database. Migration failure retains the original store and backup and shows a recoverable error. The current silent in-memory recovery must not represent success.

No App Group is planned for the first architecture because in-process App Intents can use the app container. If later proven necessary, moving the store requires a separately tested copy/verify/swap transaction with target-exists, partial-copy, rollback, and real v1.0 fixtures.

## Backup schema v2

JSON schema version 2 includes policies, categories, items, grade scales, forecast scenarios, reminder settings, and Siri settings. Decoder accepts v1 and maps missing v1.1 collections/settings to safe defaults. Imports validate the whole payload, preview contents/duplicates, create a recovery point, and offer Merge, Replace, or Cancel. Replace is transactional; any failure rolls back rather than leaving a partial import.

CSV remains supported and gains a documented grade-item export without changing the meaning of the existing course export. Local snapshot metadata remains intact.
