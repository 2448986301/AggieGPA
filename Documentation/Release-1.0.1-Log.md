# 1.0.1 (25) release log

## 2026-09-11 — authorization and preflight

- User authorized version 1.0.1 (25), in-place physical iPhone/iPad installation, final acceptance and GitHub publication while retaining the old release. User also requested logs and redundant-file cleanup.
- Initial preflight source: `codex/ipad-navigation-polish`, based on `36ea03c23880a41097cec2e70052e6d9eb6d12b9`, with the documented uncommitted UI refinements. Original UCD checkout remains untouched.
- Verified Xcode: `/Applications/Xcode.app`, 27.0 (27A266a). The old Xcode-beta path does not exist.
- Both paired physical devices were available. Both installed apps report `com.easonzhou.aggiegpa`, 1.0.0 (24).
- GitHub currently retains published `v1.0.0`, targeting the same base commit, with `AggieGPA-1.0.0-build24.ipa`. No release was changed.

## Blocking source-integrity check

- The prior temporary `/tmp/aggiegpa-syllabus-image-fix` directory does not exist.
- Current `SyllabusTextExtractor` accepts images, but the inspected `OpenSourceLocalProvider.analyze` uses `SyllabusAnalysisPlanner` text chunks and throws `noReadableText` when the plan is empty. No image/vision/mmproj inference implementation was found in the inspected provider/engine source.
- The original UCD provider and the working provider are identical. Copying that file from UCD would not restore the previous visual-model path.
- The September 5 full working-tree backup contains the identical provider (SHA-256 `52744a10e077dd2642262c8843189483ce9e34e1f8086bab4ddffb1f0c821574`); it cannot supply that later repair. No provider/engine changes since September 5 were found among local Git refs. Other backups have not been exhaustively searched.
- `SyllabusAnalysisPipeline.chunks` explicitly skips pages without `page.text`, confirming that an image-only document produces no text chunks on this path.
- Model artifact verification currently uses 1 MiB reads; bounded autorelease lifetime from the prior memory repair has not yet been verified.
- Installation and publication are paused to avoid replacing previously repaired functionality with an incomplete reconstruction. This is a source-level finding, not a new physical-device reproduction.

## Cleanup policy and status

- Original app copies, release packages, source backups, logs, result bundles and screenshots are preserved. The one approved failed-build cache was moved to Trash after backup; see closeout below.
- Before material cleanup: identify exact redundant targets, create and verify a local backup, present a cleanup preview for approval. Do not delete whole workspace roots or change Git history.

## Acceptance status

- Version/build update: 1.0.1 (25), verified in both physical About screens.
- Fresh device test build and simulator core regression: passed; final 244-test core run and three migration repetitions passed. Final Release archive/export passed.
- Final exported Release app: cover-install and ordinary launch passed on both physical devices; all 22 database tables match each device's pre-install snapshot.
- Physical interaction and hitch profiling: passed for the tested paths below. Absolute zero latency cannot be guaranteed.
- Final archived source: `9fefdcf8959d4795c21d9a0357cc8b48e997c8c8`; IPA SHA-256 `afcf190b7845bcb99b037f9930c187a83f5a5c2d8624b1eba80bea8762c735f6`. Tag/publication closeout follows below.
- GitHub publication: pending; old release preserved.

## Recovery implementation — subsequent work

- Reconstructed the September 7–8 image-import patches in an isolated recovery directory. Applied only the relevant service, import UI, activity and image-test changes to current source; retained current navigation/gradebook refinements. Historical reports remain outside current acceptance evidence.
- Restored pinned Qwen2-VL model/projector handling, bounded image inputs, direct visual grading-table decoding, source-page evidence, image-model readiness and stage-scoped progress. No model downloaded.
- Confirmed both physical devices retain the expected language-model and projector files. Presence/size is not a replacement for cryptographic verification at inference load.
- Restored bounded autorelease pools in visual checksum/inference work and applied per-chunk cancellation/cleanup to text-model checksums too.
- Found an additional cancellation defect during review: an actor-isolated cancel method queued behind synchronous native inference. Made the cancellation flag reachable without that actor hop, added task/native cancellation hooks and checks preventing cancelled requests from yielding successful results or retrying a fallback.
- Updated app/extension project settings to authorized 1.0.1 (25); built-product verification remains pending.
- First fresh simulator test attempt emitted an Xcode SwiftCompile infrastructure error (`exit code 0 but produced no further output`) and stopped making progress. Terminated that owned build process; no passing-test claim. Retry will use the finalized recovery/cancellation source.

## Current verification and remaining blocker

- Simulator `release101-ai-recovery-03.xcresult`: 33 passed, 4 skipped, zero failures. Actual local visual inference produced the synthetic 20% / 80% weights on both cold and warm runs. CPU simulator timings were approximately 107 / 104 seconds, not physical-device latency.
- The earlier simulator native crash was localized to MTLSimDevice buffer allocation during projector loading. Matching the existing text runtime's CPU-only simulator policy removed that crash in the rerun.
- Simulator `release101-core.xcresult`: 234 tests executed, 5 skipped, zero failures. Existing visual goldens and the already-completed long synthetic inference test were excluded explicitly.
- Device build 04 succeeded after selecting the existing development team and moving build products out of the File Provider-managed Documents directory. Previous signing failure was FinderInfo metadata on the generated extension. App and extension products both report 1.0.1 (25); strict signature verification passed.
- Both app-group backups completed after the iPhone was unlocked; both current database copies passed SQLite quick_check. Local source archive SHA-256: `f33d185dda3fa77eae7ab485a232fbc12f2542899b754eb0cbf6d05990c64fd8`. Git bundle verification passed. This source backup predates the final version-note/test-isolation edits and is not the final release artifact.
- Physical tests cover-installed build 25 and launched the test host with an in-memory grade database while using already-installed model files. Final ordinary-launch/user-data verification remains pending.
- Both devices correctly decoded the public MAT180 grading weights 20% / 50% / 30%: iPad 9.474 s, iPhone 11.898 s total analysis; nominal thermal state. Both native-encoding cancellation tests passed (about 0.079 / 0.052 s from cancellation request to test cleanup).
- The same three-test sequence then failed on its synthetic cold reload: iPhone correctly refused the load with 2.47 GB headroom below the unchanged 3 GB gate; iPad test host exited with signal kill. These are failures, not a completed release acceptance.
- Investigating Metal residency/resource reclamation with the same binary and an explicit diagnostic-only `GGML_METAL_NO_RESIDENCY=1` test configuration. GPU acceleration and the memory gate remain unchanged. Upstream implementation reference: https://github.com/ggml-org/llama.cpp/blob/b10375/ggml/src/ggml-metal/ggml-metal-device.m . Similar upstream report is contextual evidence only, not proof of the local root cause: https://github.com/ggml-org/llama.cpp/issues/25937 .
- Publication and cleanup remain pending. No GitHub mutation or file deletion performed.

## Resource-reclamation diagnosis

- The no-residency diagnostic did not resolve the three-test sequence; it is not promoted to production.
- Added opt-in DEBUG resource tracing. Both devices again passed cancellation and real-image extraction, then failed the synthetic cold reload (iPhone memory gate; iPad test-host termination).
- Immediately after real-image engine destruction, Metal allocation returned to about 1–5 MB, while process footprint remained about 1.04–1.11 GB. Cancellation-only teardown returned footprint to about 110 MB. This rules out a simple retained Metal-buffer explanation but does not yet establish the cause of remaining process memory.
- Investigating heap allocation versus allocator-retained memory with DEBUG-only statistics and opt-in pressure relief. Production memory threshold, GPU policy and model files remain unchanged. No passing stability claim yet.
- Heap diagnostic: after real-image teardown on iPhone, heap in use was approximately 49 MB and reserved heap approximately 146 MB, but footprint remained 1.06 GB. `malloc_zone_pressure_relief` released zero bytes. This is not evidence for a large retained ordinary heap allocation.
- Disabling model mmap did not help: teardown footprint increased to approximately 2.26 GB; retain default mmap. A tiny completed Metal blit after teardown also did not restore iPhone headroom. Neither diagnostic is a production fix.
- Removing Xcode's RPAC injection from the test descriptor yielded one complete iPad sequence (three tests, including synthetic cold/warm inference), but teardown footprint still stayed around 1.07 GB, and the iPhone still failed its unchanged headroom guard. Do not generalize that single iPad pass to final acceptance.
- iPad briefly became unavailable and then reconnected. One subsequent install failed with a provisioning-profile mismatch after generic-device building; rebuilding explicitly for the iPad. The failed install is not runtime evidence.

## Confirmed reclamation timing and focused correction

- iPhone timeline observation: after teardown, available memory remained around 2.53 GB initially, recovered to 3.33 GB around 2 seconds, and to 3.48 GB by approximately 3–4 seconds. The outstanding allocation was transient, not evidence of a persistent app-owned leak. The precise allocator/driver implementation cause remains unproven.
- Corrected the app lifecycle mismatch: engine retirement now records pre-load headroom and asynchronously waits for reclamation (128 MiB tolerance, 5-second maximum). A replacement cold load must await retirement; the visual model's 3 GB floor is unchanged. Warm reuse and Today/Courses/GPA navigation do not wait. Model-switch cleanup now precedes the cold-load check.
- Removed the ineffective allocator-relief attempt and all trial mmap/blit/timeline controls. Retained only opt-in DEBUG resource logging. No runtime library or model file was replaced.
- `release101-iphone-retirement-fix.xcresult`: all 3 physical tests passed, including cancellation and real grading table, then synthetic cold and warm inference. Synthetic analysis approximately 13.61 / 13.48 seconds; cold model load 1.08 seconds, warm load effectively zero.
- iPad with standard RPAC injection still had a signal-kill during warm inference. The same build with RPAC removed (`release101-ipad-retirement-without-rpac.xcresult`) passed all 3 tests: synthetic approximately 10.06 / 19.49 seconds, cold model load 1.05 seconds. Preserve this configuration caveat; do not label the injected run passing or claim a proven RPAC root cause from correlation alone.
- Final core simulator regression: 236 executed, 5 conditional skips, zero failures, including two new retirement-policy/no-engine tests. Visual goldens and previously verified long synthetic inference were explicitly excluded.
- Added Apple's `XCTHitchMetric(application:)` to the physical tab-switch performance test so frame hitches are measured separately from automated tap-cycle duration. Official API: https://developer.apple.com/documentation/xctest/xcthitchmetric . Results pending.

## Physical UI acceptance and cleanup closeout

- iPhone: 5/5 focused UI tests passed (About/version history, edit/save, canonical search, launch, tab switching). iPad: 6/6 passed (About/version history, edit/save, Chinese row summary, independent course/search identity through rotation, launch, tab switching).
- Both devices recorded 0 hitches, 0 hitch duration and 0 ms/s hitch ratio in all 3 measured Today/Courses/GPA switching iterations. Automated tap-cycle clock time is not touch-to-first-frame latency.
- iPad measured app launches: 0.552 / 0.538 / 0.606 s. iPhone: 0.604 / 2.947 / 1.134 s; high variance means these samples do not establish consistently subsecond launch. These are development-build/XCTest measurements, not an absolute no-latency guarantee.
- Visually inspected all 7 retained physical screenshots. About screens show 1.0.1 (25); course/search identity and saved titles match. iPhone metadata exposed a split "Major" label: fixed intrinsic label sizing and explicitly retained icon-plus-title styling. The focused post-change edit/save test passed and its screenshot verifies an unbroken visible "Major" label with compact row height (`release101-iphone-metadata-layout-02.xcresult`).
- Three iPad demo screenshots are under `Documentation/Screenshots/release101-physical/`. iPhone originals stay local because system live activities are visible; they are not included in GitHub content.
- With explicit approval of the exact target, moved only the 373 MB `Release101-Device.KDG2HE` failed-build cache to `/Users/easonzhou/.Trash/AggieGPA-Failed-Device-Build-20260911`. Recoverable from Trash or the verified backup; no other files deleted.
- Pre-cleanup backup: `/Users/easonzhou/Documents/UCD-backups/Release101-Precleanup.SViyVC`; complete Git bundle verified. Working-tree archive SHA-256 `db1eaca66472331ebb21910602dca8bd0b7687320984e21eba9c1f563ed458fc`; failed-cache archive SHA-256 `68fd51859340d5ea358986c6795c1ae1f21350afeab06669134da7518ac09144`. This backup predates the final small metadata layout correction.

## Final archive and data-preservation gate

- Exact archived source: `b39f1b68a70a43080e0ed3f8db6eef535ecad957`; app and widget version 1.0.1 (25). Fresh Release archive and development export succeeded; exported app passed strict deep signature verification. IPA SHA-256: `f47e7ce2af7d46a487c9ff61212c21296d39c8922bee82ccd16f801c33810d64`.
- The app extracted from that IPA was cover-installed and ordinarily launched on both physical devices, without uninstalling or clearing data. This is a development-signed sideload artifact, not an App Store export.
- Read-only pre-test versus final database comparison: both integrity checks pass. iPad application records match apart from the preferences optimistic-lock counter. iPhone terms, courses, official grades, gradebook items/categories, forecasts, templates and all preference/privacy values match.
- Publication is paused: the iPhone saved planning scenario has two changed assumed-grade values (same eight entries, no additions/removals), plus scenario sort/update metadata. Siri update metadata also changed, but its permission values did not. The recorded planning update occurred at 13:21 China time, before the final Release installation. Available snapshots do not establish whether this was an intentional user edit or test-related. Preserve both backups and current data; do not restore or overwrite the scenario without clarification.
- A subsequent installed-app recheck could not run because `/Applications/Xcode-beta.app/Contents/Developer` is no longer available. Earlier successful install/launch records remain evidence, but this failed recheck supplies no new device-state evidence.
- No release publication or tag push has been performed in this release-preparation sequence. This documentation-only closeout is later than the archived source and does not change the IPA provenance.
- Follow-up: the user explicitly reports no manual assumed-grade changes. Both unexpected transitions are A to A-minus. Treat this as an unresolved data-preservation incident, not an accepted user edit. No repair has been applied to device data.
- The retained 13:19:48-13:20:04 iPhone diagnostic run selects only three image-inference tests; its preserved descriptor supplies `--uitest-in-memory`. Those test bodies have no planning-store writes. Current planning mutation call sites are grade-selection buttons / explicit save, while the Siri settings screen updates its timestamp on disappearance. These observations do not identify who or what triggered the writes; no automatic startup rewrite has been established.
- Test-isolation risk: the regenerated default test descriptor does not retain the manually inserted in-memory argument. This is a real workflow weakness, but not proof that it caused these changes. Further testing must explicitly verify isolation before launch; do not run mutation tests against the user's durable store.
- Toolchain correction: the available installation is `/Applications/Xcode.app`, which was also used by the retained successful build logs. A fresh read-only iPad installed-app query using it confirms 1.0.1 (25). The earlier missing beta-path recheck was a path-selection mistake, not evidence that Xcode was removed.

## Authorized two-value recovery

- The user explicitly approved restoring only the two unexpected assumed-grade values. A fresh pre-repair database/WAL/SHM backup was retained locally under `/Users/easonzhou/Documents/UCD-backups/TwoGradeRepair.gl6Exo/`; the expected metadata matched the prior incident snapshot before execution.
- At 14:15:37 China time, a one-time, explicitly authorized test performed an on-device SQLite transaction with an exact expected-value predicate. It changed one metadata cell containing exactly the two approved A-minus to A corrections. No whole-database replacement, uninstall, scenario timestamp/order adjustment or official-grade write was performed. The one selected recovery test passed.
- Compared all 22 SQLite tables and the schema against the fresh pre-repair snapshot: only the approved metadata cell changed, and its bytes exactly matched the two-value replacement. Every other stored value, including optimistic-lock counters, matched; integrity checks passed.
- Removed the one-time recovery method and import from source, disabled its test authorization environment variable, and consumed its device-side payload. Private recovery evidence remains in the local backup only, not in the app or Git history.
- Reinstalled the exact previously exported Release app from the verified IPA and ordinarily launched it. A second complete 22-table comparison again found exactly the two authorized grade corrections and no other changed values. Production source remains identical to archived commit `b39f1b68a70a43080e0ed3f8db6eef535ecad957`; only this documentation has subsequent changes.
- Recovery is complete. Publication remains paused because the original unexpected write source is unresolved; successful recovery is not root-cause verification.

## Follow-up investigation and data-safety corrections

- The user requested continuation and publication after completion. The historical two assumed-grade writes have no retained action-level audit sufficient to assign a unique cause. Do not claim that the issues below prove their origin.
- Confirmed a test-isolation weakness: regenerated test descriptors can omit manually inserted in-memory arguments. Added a launch-time isolation policy covering explicit UI/preview flags, XCTest environment markers and the loaded test runtime. Main-app startup, data factories and Siri factory calls honor it. Root preview guards use the same decision.
- Six isolation tests passed on each physical device using a regenerated descriptor with empty custom arguments. iPhone pre/post-test comparison of all 22 SQLite tables was identical. The first iPad post-test copy timed out and is not accepted as a data-preservation result; final installation comparison remains required.
- Separately reproduced a destructive backup preparation defect in a disposable Simulator copy without the migration marker: `createVerifiedV1RecoveryBackupIfNeeded` opened a current database using the V1 model. The inferred downgrade removed standalone template/Siri entities. A synthetic current-schema regression reproduced the loss before the fix; this was not a newly observed physical-device loss.
- Fixed backup preparation by opening the source SQLite connection read-only, creating and checking a complete online-backup snapshot, and migrating only a disposable copy to the current schema for JSON export. Export includes gradebook data, Siri settings, templates and reminder defaults. The original database is never opened with the old model; failed verification cannot write the completion marker. Existing verified backups remain intact. API reference: https://www.sqlite.org/c3ref/backup_finish.html .
- Regression coverage checks every live table and schema before/after backup, preservation of official/assumed grades and standalone entities, complete exported fields, marker idempotence, invalid-store failure safety, V1 migration and current-schema backup restoration. A raw-file-byte assertion was replaced with a transactional row/schema comparison because asynchronous WAL checkpointing may change physical bytes without changing data; the comparison waits for SQLite locks and fails on incomplete reads.
- Final core regression (`release101-final-data-safety-core-03.xcresult`): 244 executed, 5 conditional skips, zero failures. Earlier regression failures and the initial fixture-test compilation error are retained locally, not counted as passing.
- Re-provisioned only the disposable Simulator copy and reran ordinary launch plus three rounds of GPA / Full Simulation scrolling / Siri navigation (`release101-preservation-navigation-fixed.xcresult`). Navigation passed. All academic, official-grade, assumed-grade, scenario, template and preference/privacy values matched the restored source. Only expected Siri visit timestamps, optimistic-lock counters and framework transaction-history metadata changed; no historical records were truncated. This is data-preservation evidence, not a proof of the historical write actor.
- New runtime changes require a fresh source commit, Release archive, IPA checksum and final physical cover-install verification. The earlier `b39f1b6` artifact remains preserved as a historical pre-hardening artifact and will not be substituted for the final package.

## Final package acceptance

- Final runtime source is committed at `9fefdcf8959d4795c21d9a0357cc8b48e997c8c8`; the checkout was clean throughout the fresh Release archive. Later log-only commits do not change the archived app.
- Fresh archive `AggieGPA-1.0.1-build25-final.xcarchive` and development export succeeded. Final IPA: `Release101-FinalExport/AggieGPA-1.0.1-build25.ipa`, 6,732,454 bytes; SHA-256 `afcf190b7845bcb99b037f9930c187a83f5a5c2d8624b1eba80bea8762c735f6`. App and embedded widget both report 1.0.1 (25); strict deep signature verification passed and the profile includes both acceptance devices.
- Installed the app extracted from that exact IPA on iPhone and iPad, then ordinarily launched both without test/demo arguments. Both operations succeeded on each device. Fresh installed-app queries confirm 1.0.1 (25).
- Both post-test and final post-install database comparisons pass: 22 tables per device, matching schema, successful integrity checks, and every stored value identical to that device's fresh pre-test snapshot. The already-authorized two-grade repair remains intact; no additional changes were made to personal data.
- Final core: 244 executed, 5 conditional skips, zero failures. All five migration/backup tests passed three consecutive repetitions. Physical UI/hitch and AI measurements above remain evidence for unchanged UI/AI paths; the new changes are data isolation and backup preparation, not a new visual redesign.
- Retained limitations: no unique historical actor/source for the two repaired writes; iPad RPAC-injected AI termination is not labeled passing; larger unverified models remain restricted. The normal-launch/navigation data-preservation regression and explicit test isolation checks passed. The final package is approved for the requested GitHub release with those limitations documented.
