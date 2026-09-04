# WL5024Control PR #1 repository audit

**Date:** 2026-09-04  
**Audited head:** `8ecb1702becc6e2aecb8c64d6319d996f7e85e70` (`codex/wl5024-hardware-controls`)  
**Base:** `main` at merge base `ddd6410cc075ce395e1704cd3d5d81a02ba61bae`  
**Pull request:** [#1 — Implement hardware-validated WL5024 controls](https://github.com/zachspartofaday/WL5024Control/pull/1)  
**Verdict:** **Changes requested**. The branch builds and all automated tests pass, but two high-severity state/queue defects and eight medium-severity correctness or accessibility defects should be resolved before merge.

## Findings

| ID | Severity | Confidence | Finding |
| --- | --- | --- | --- |
| WL5024-PR1-AUD-001 | High | High | Device-confirmed settings survive a Bluetooth session change and become writable before a fresh read |
| WL5024-PR1-AUD-002 | High | High | Cancelling discovery silently discards setting changes queued behind it |
| WL5024-PR1-AUD-003 | Medium | High | Changing Quick Pause sensitivity while Quick Pause is off enables it without updating the toggle |
| WL5024-PR1-AUD-004 | Medium | High | A partial refresh presents failed keys as freshly device-confirmed |
| WL5024-PR1-AUD-005 | Medium | High | A terminal pre-ready Bluetooth setup failure leaves the UI stuck in “searching” |
| WL5024-PR1-AUD-006 | Medium | High | A later queued success can leave a visible retry alert with no command to retry |
| WL5024-PR1-AUD-007 | Medium | Medium | A failed multi-step sidetone write can leave unreported partial device state |
| WL5024-PR1-AUD-008 | Medium | High | Status-only preference responses are either lost or can be attributed to the wrong discovery module |
| WL5024-PR1-AUD-009 | Medium | High | The probe exits successfully after setup and runtime errors |
| WL5024-PR1-AUD-010 | Medium | High | Setting rows expose duplicate accessible names and status announcements |
| WL5024-PR1-AUD-011 | Low | High | Demo discovery cannot render progress or exercise cancellation as documented |
| WL5024-PR1-AUD-012 | Low | High | Appearance/accessibility automation claims exceed what the test asserts |

### WL5024-PR1-AUD-001 — Device-confirmed settings survive a Bluetooth session change

**Severity:** High  
**Confidence:** High

`TransportStateReducer` changes only connection and transport fields on Bluetooth disconnect; it does not invalidate `values` or `valueConfidence` (`WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/TransportStateReducer.swift:29-35`). `HeadsetSnapshot.DeviceInfo` has no Bluetooth peripheral or session identity to which those values could be bound (`WL5024ControlPackage/Sources/WL5024ControlFeature/Core/HeadsetSnapshot.swift:3-39`). On the next Bluetooth connection, `updateReadiness()` marks every qualified write `.experimental` regardless of whether that setting has been read in the new session (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:387-404`). A retained value therefore renders as a normal enabled control (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:265-277`).

An audit-only regression test set Busy Light to `true`, disconnected the active UUID, and connected a different UUID. The new snapshot still contained `.boolean(true)` with `.deviceConfirmed` confidence, and the control was write-enabled. The audit test was removed after execution.

This crosses the branch's hardware safety boundary: the UI can claim that a value was confirmed by the currently connected headset when it came from an earlier transport session or a different peripheral.

**Required fix:** Bind live values and confidence to a transport session/peripheral identity. On disconnect or identity change, invalidate device-confirmed values and timestamps. Require a successful current-session read before presenting the normal control; the existing explicit experimental “Set Value…” path is an appropriate fallback when the value is unknown. Add same-device reconnect and different-device reconnect tests.

### WL5024-PR1-AUD-002 — Cancelling discovery silently discards queued changes

**Severity:** High  
**Confidence:** High

Bounded discovery can take roughly four minutes (`Documentation/PROTOCOL.md:108-112`). While it is the active command, settings remain enqueueable: regular controls are disabled only for the same pending key, and experimental menus follow the same per-key rule (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:265-277`). The menu-bar automatic-media toggle also remains enabled while any command is in flight (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetMenuBarView.swift:17-22`), although Refresh is globally disabled (`HeadsetMenuBarView.swift:42-43`). All operations share one queue (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/HeadsetModel.swift:160-176`).

When the user cancels active discovery, `cancelReadOnlyDiscovery()` calls `queuedCommands.removeAll()` before cancelling the shared task (`HeadsetModel.swift:136-145`). That deletes unrelated setting changes and refreshes without executing them or telling the user. If discovery is not cancelled, those hardware writes may instead execute minutes after the user initiated them.

An audit-only deterministic test blocked discovery, queued a bass-setting write, cancelled discovery, and confirmed that the write never reached the controller and no setting failure was presented. The audit test was removed after execution. The completed Codex PR review independently reported the same defect.

**Required fix:** Make discovery an exclusive operation. Either disable/reject every setting and refresh action while it runs with a visible explanation, or separate discovery cancellation from the command queue and explicitly preserve or disposition unrelated commands. Do not permit silently dropped or surprisingly delayed writes. Cover settings-window and menu-bar entry points.

### WL5024-PR1-AUD-003 — Quick Pause sensitivity can silently enable Quick Pause

**Severity:** Medium  
**Confidence:** High

Quick Pause and its sensitivity share bits 4–5 in one wear-detection word. Mode `0` is off; modes `1` and `2` are on with normal or sensitive behavior (`WL5024ControlPackage/Sources/WL5024ControlFeature/Protocol/WearDetectionFlags.swift:11-25,70-75`). Updating `.quickPauseSensitivity` always replaces mode `0` with `1` or `2` (`WearDetectionFlags.swift:53-63`). The existing unit test explicitly demonstrates the transition from disabled raw value `0xA547` to enabled raw value `0xA557` (`WL5024ControlPackage/Tests/WL5024ControlFeatureTests/RaceFrameTests.swift:227-232`).

The write contract decodes and publishes only the key that initiated the write (`WL5024ControlPackage/Sources/WL5024ControlFeature/Protocol/WriteQualification.swift:102-125`; `LiveHeadsetController.swift:162-169`). As a result, the hardware can have Quick Pause on while the toggle remains off in the snapshot/UI.

**Required fix:** Treat the two fields as one composite state. Disable or reject sensitivity changes while Quick Pause is off, or decode the post-write bitfield into both logical values and publish both atomically. Add a controller-level test that asserts snapshot and device state cannot diverge.

### WL5024-PR1-AUD-004 — Partial refresh keeps failed keys falsely fresh

**Severity:** Medium  
**Confidence:** High

Each successful getter overwrites its value and confidence, but a failed getter only records a diagnostic (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:76-115`). If any other key succeeds, the controller advances the single global `lastUpdated` timestamp and publishes success (`LiveHeadsetController.swift:118-122`). It does not clear or downgrade the failed key's old value, `.deviceConfirmed` confidence, or readiness.

After an earlier successful refresh, a later wear-bitfield timeout can therefore leave all six wear controls showing old, writable state while an unrelated successful getter makes the overall snapshot look newly refreshed. This is a current-session variant of WL5024-PR1-AUD-001 and remains harmful even after session identity is added.

**Required fix:** Track freshness per key or per shared transaction. On a failed read, invalidate/downgrade every key derived from that transaction and expose a partial-refresh result. Advance global freshness only when its meaning is unambiguous. Add a successful-refresh-then-partial-failure regression test.

### WL5024-PR1-AUD-005 — Terminal setup failure leaves a false searching state

**Severity:** Medium  
**Confidence:** High

Name-gated fallback can connect to a device that lacks the recovered control service. That path calls `failSetup(..., willRetry: false)` (`WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/BluetoothEventSource.swift:427-435`). `failSetup` emits `.failed` and deliberately schedules no retry (`BluetoothEventSource.swift:286-312`).

Before the control service becomes ready, `snapshot.device.transport` is still `nil`. The reducer changes state to `.failed` only when the failure source equals that transport; a non-retrying failure from an unselected source matches neither branch (`WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/TransportStateReducer.swift:44-50`). The persistent state remains `.searching` after the transient alert is dismissed even though the Bluetooth source has stopped searching.

**Required fix:** Represent terminal pre-connection source failure explicitly. A non-retrying failure for the only viable source must transition the UI out of searching, while preserving receiver fallback when one exists. Add reducer and controller integration tests for unsupported name-gated candidates.

### WL5024-PR1-AUD-006 — A queued success can produce a dead retry alert

**Severity:** Medium  
**Confidence:** High

The queue continues after a non-discovery command fails, setting both `retryCommand` and a visible failure (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/HeadsetModel.swift:179-213`). Every later successful command unconditionally clears `retryCommand` at line 189, but it does not clear or replace the earlier alert. The alert still offers “Try Again” (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:31-50`), while `retryLastAction()` silently returns when the command is nil (`HeadsetModel.swift:115-119`).

An audit-only test queued a failing bass write followed by a successful treble write. The failure alert remained retryable, but invoking retry sent no additional write and did not dismiss the alert. The audit test was removed after execution.

**Required fix:** Associate failures and retries with a command identity. Stop the queue when user recovery is required, or clear retry state only when the corresponding retry succeeds. Never render a retry action without a retained retry command. Add failure-then-success and repeated-retry tests.

### WL5024-PR1-AUD-007 — Sidetone can be left in unreported partial state

**Severity:** Medium  
**Confidence:** Medium for the device outcome; high for the code path

Setting an enabled sidetone level emits two writes in order: enable module 7, then set module 6's level (`WL5024ControlPackage/Sources/WL5024ControlFeature/Protocol/WriteQualification.swift:129-157`). The live controller executes writes sequentially and aborts immediately if any write or acknowledgement fails; read-back begins only after every write succeeds (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:148-169`).

If the enable acknowledgement succeeds and the level write times out or is rejected, the headset may be enabled at its previous level. The app reports only a generic failure, performs no qualified read-back, and has no partial-success or rollback state. The exact setter acknowledgements are still awaiting field validation (`Documentation/PROTOCOL.md:114-120`), so the safest behavior is to assume an acknowledged first write may have taken effect.

**Required fix:** Design the operation as an explicit multi-step transaction. Prefer setting the level before enabling if hardware evidence proves that ordering safe. Otherwise capture pre-state and, after any intermediate failure, perform qualified read-back and report the observed partial outcome; roll back only if that write is independently proven safe. Add failure-at-each-step tests before further field qualification.

### WL5024-PR1-AUD-008 — Status-only responses are mishandled during discovery

**Severity:** Medium  
**Confidence:** High

Physical evidence records that preference module 10 returns success status with no module or value bytes (`Documentation/PROTOCOL.md:102-104`). The shipping `RaceResponseMatcher` requires the requested module to appear in the payload for preference transactions (`WL5024ControlPackage/Sources/WL5024ControlFeature/Protocol/TransportTransaction.swift:12-26`). The app will therefore classify that real response as unsolicited and record a timeout rather than a response.

The direct BLE probe works around this by accepting any one-byte payload with the pending opcode as a match (`WL5024ControlPackage/Sources/WL5024Probe/DirectBLEProbe.swift:341-361`). During the serialized `0...255` scan, a late status-only response after one timeout is indistinguishable from the status-only response for the next module and can be credited to the wrong request. An audit-only matcher test confirmed that the module-10 transaction rejects the documented status-only response; the test was removed afterward.

**Required fix:** Introduce an explicit response disposition such as exact, ambiguous-status-only, or unrelated. Count and log status-only responses as ambiguous without attributing them to a module, and ensure late ambiguous notifications cannot complete the next request. Align app and CLI summaries around the same semantics.

### WL5024-PR1-AUD-009 — Probe errors return exit status zero

**Severity:** Medium  
**Confidence:** High

`WL5024Probe.main()` calls either probe runner and returns normally (`WL5024ControlPackage/Sources/WL5024Probe/WL5024Probe.swift:4-18`). Direct BLE setup failures return `false` after logging, while runtime failures stop the run loop after logging (`WL5024ControlPackage/Sources/WL5024Probe/DirectBLEProbe.swift:193-201,394-410`). Neither path propagates an outcome to `main`. The USB runner uses the same fire-and-return shape (`WL5024ControlPackage/Sources/WL5024Probe/DirectUSBProbe.swift:11-21`).

The audit ran the built executable with `--live --only=does-not-exist`. It printed `ERROR No getter matched the supplied --only identifier.` and exited with status `0`. Automation can therefore store failed hardware evidence as a successful run.

**Required fix:** Make each runner return a typed outcome and have `main` terminate nonzero for invalid arguments, setup failure, timeout, I/O failure, and malformed responses. Reserve zero for a completed command whose declared success criteria were met. Add process-level exit-code tests.

### WL5024-PR1-AUD-010 — Setting rows duplicate accessible names and status

**Severity:** Medium  
**Confidence:** High from the accessibility tree/source; manual assistive-technology verification was not run

Each interactive row exposes a standalone `Text(key.title)` and a native Toggle or Picker that also uses `key.title` as its label (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:248-285,289-312`). The UI test confirms that both a static text node and a checkbox named “Wear detection” exist (`WL5024ControlUITests/WL5024ControlUITests.swift:24-35`). Non-ready rows likewise expose readiness as visible text and repeat it as the control's accessibility hint. `ExperimentalSettingMenu` repeats the row title as its accessible label while its visible action is “Set Value…” (`WL5024ControlPackage/Sources/WL5024ControlFeature/Views/ExperimentalSettingMenu.swift:7-29`).

This violates the repository's documented expectation of no duplicate label (`Documentation/ACCESSIBILITY.md:5-16`) and can produce repeated VoiceOver announcements or ambiguous Voice Control names.

**Required fix:** Give each interactive row one semantic control name. Hide the redundant visual title/status from accessibility when the native control carries them, combine title/value for read-only rows, and give the experimental menu a visible and accessible action name that remains unambiguous. Update accessibility-tree tests, then manually verify VoiceOver, Voice Control, and Full Keyboard Access.

### WL5024-PR1-AUD-011 — Demo discovery cannot exercise cancellation

**Severity:** Low  
**Confidence:** High

The mock controller iterates through all 266 probes synchronously on the main actor with no suspension point (`WL5024ControlPackage/Sources/WL5024ControlFeature/Model/MockHeadsetController.swift:62-84`). SwiftUI cannot render intermediate progress or deliver the Cancel action until the operation is already complete. That makes the documented demo-mode scenario—hear numeric progress, cancel, and inspect the partial-result explanation—unexercisable (`Documentation/ACCESSIBILITY.md:3,13`).

**Required fix:** Add deterministic yielding or a short injectable delay to mock discovery so progress and cancellation are observable without making tests slow. Add an integration/UI test that cancels after known progress and verifies the partial result.

### WL5024-PR1-AUD-012 — Appearance automation claims exceed its assertions

**Severity:** Low  
**Confidence:** High

`Documentation/ACCESSIBILITY.md:33-35` says the UI target covers light/dark appearance, increased contrast, and reduced transparency. `testAppearanceAndAccessibilityLaunchProfiles` launches each argument profile, navigates to one page, and asserts only that the Sidetone pop-up exists (`WL5024ControlUITests/WL5024ControlUITests.swift:153-169`). It takes no screenshot and makes no assertion about effective appearance, contrast, transparency, clipping, overlap, or legibility.

**Required fix:** Rename/narrow the test and documentation to “launch smoke” coverage, or add deterministic screenshot attachments and assertions that prove the intended scenario. Keep the manual environment-stress checklist as the authority for visual quality that automation cannot establish.

## Audit summary

The branch substantially improves the protocol boundary, transport decomposition, diagnostics, UI coverage, and hardware evidence relative to `main`. Exact acknowledgement plus read-back gating, strict decoders, getter allowlisting, receiver-write exclusion, and removal of unqualified controls are strong choices. The remaining release risk is concentrated in state provenance and command orchestration: values are not tied to the current headset/session, partial reads retain authoritative-looking state, and one long-running diagnostic operation can silently consume user writes.

No Critical findings were identified. Findings WL5024-PR1-AUD-001 and -002 should block merge. Findings -003 through -010 should be resolved in the same remediation program because they affect the truthfulness of hardware/UI state, recoverability, diagnostic evidence, or assistive-technology operation. Findings -011 and -012 can follow once their disposition is recorded, but the documentation must not continue to claim behavior that the demo/test path cannot demonstrate.

## Scope and authority

The audit used a fresh clone and did not modify or build in the operator's existing worktree. The checkout was pinned to the PR's exact head before evidence collection.

| Area | Authority used |
| --- | --- |
| Current change | PR #1 body and diff, 65 files, `+6,123/-935` versus `main` |
| Product/platform scope | `README.md` — personal English-only app, macOS 26+, Apple silicon |
| Hardware safety | PR #1 “Safety boundary”; `README.md:5-11`; `Documentation/PROTOCOL.md` |
| Accessibility contract | `Documentation/ACCESSIBILITY.md` |
| Validation contract | `README.md:68-81` |
| Historical disposition | `docs/audits/2026-09-01-wl5024-repository-audit.md` and `docs/audits/2026-09-01-wl5024-exhaustive-ui-re-audit.md` |
| Live project state | Open PR #1; no open GitHub issues; no operator-authored issue/PR comments; completed Codex review at the audited head |

No `AGENTS.md`, `CONTRIBUTING.md`, CI workflow, or repository linter configuration exists. The README is therefore the executable validation authority. Firmware flashing, factory reset, pairing/maintenance commands, unqualified writes, receiver writes, localization, older OS/Intel compatibility, and a general redesign were excluded by explicit repository scope.

## Repository inventory

| Surface | Inventory |
| --- | --- |
| Tracked files | 90 at the audited head |
| Swift source/test files | 56 |
| Automated test files | 6 Swift package test files plus 1 macOS UI-test file |
| Build graph | One Xcode workspace/project, app target, UI-test target, Swift package library, probe executable, package test target |
| Primary layers | Core, Protocol, Transport, Model, Views, Diagnostics, CLI probe |
| Change shape | Hardware-validated reads/writes, bounded discovery, direct probes, transport/lifecycle refactor, UI/accessibility and documentation updates |

Inventory preceded specialist routing. Because the changed surface includes SwiftUI, strict Swift concurrency, Swift Testing, explicit accessibility/focus contracts, and XcodeBuildMCP validation, the audit applied the installed `swiftui-pro`, `swift-concurrency-pro`, `swift-testing-pro`, `apple-accessibility-pro`, `swift-focusengine-pro`, and `xcodebuildmcp-cli` review standards. No Core Data, SwiftData, UIKit modernization, cryptography/Keychain, or Xcode security-settings evidence was present, so those specialist scopes were not invoked.

## Validation and spot verification

| Check | Result |
| --- | --- |
| `xcodebuildmcp macos build --workspace-path WL5024Control.xcworkspace --scheme WL5024Control` | Passed |
| `xcodebuildmcp macos test --workspace-path WL5024Control.xcworkspace --scheme WL5024Control` | Passed, 66/66 tests |
| `xcodebuildmcp swift-package test --package-path WL5024ControlPackage` | Passed, raw log confirms 59 tests in 6 suites; the tool summary incorrectly displayed zero |
| `xcodebuildmcp swift-package build --package-path WL5024ControlPackage --configuration release` | Passed |
| Workspace line coverage | 50.2% (`3,393/6,759`); protocol/transaction code is generally strong, while lifecycle/reducer paths are materially lower |
| `git diff --check origin/main...HEAD` | Passed |
| Tracked plist/JSON syntax | Passed (`plutil`/`jq`) |
| Built app entitlements inspection | App sandbox plus expected Bluetooth/USB/user-selected file entitlements present; debug-under-test product also contained Xcode test allowances |
| Probe invalid-selector smoke test | Reproduced error text with process exit status 0 |
| Audit-only behavioral tests | Reproduced stale cross-session values, discovery queue loss, dead retry, and status-only matcher rejection; all temporary tests removed |

The workspace test emitted eight “not stripping binary because it is signed” warnings for signed Xcode test-support frameworks. These are toolchain/test-host noise rather than warnings from repository code. The app and UI-test source files show zero in-process coverage because the UI target drives the application out of process; this is not evidence that the UI tests did not run.

No physical Bluetooth/USB writes, firmware operation, pairing change, or device reset was performed. The PR's recorded physical read-only evidence was reviewed but not repeated. VoiceOver, Voice Control, Full Keyboard Access, appearance stress, release signing/notarization, and real-hardware runtime behavior remain manual/unverified in this audit.

## Overturned suspicions and strengths retained

- **Strict shipping response correlation is present.** The app transport requires opcode/module matches, and malformed or wrong-family responses fail closed. WL5024-PR1-AUD-008 is specifically about the documented status-only exception and the probe workaround, not a general relaxation request.
- **Write success is not optimistic.** Qualified writes validate acknowledgements and exact read-back before publishing. WL5024-PR1-AUD-007 concerns partial multi-write failure before that read-back phase.
- **Shared wear reads are coherent within one refresh.** The response cache prevents six independent reads of the composite word. The remaining issue is invalidation when that shared transaction fails after an older success.
- **Bluetooth notification setup waits for readiness.** A suspected pre-subscription request race was not found.
- **Receiver interface removal is reference-counted.** The current HID monitor waits for the final matching interface rather than treating one interface removal as full receiver loss.
- **HID callback isolation is documented and internally consistent.** Main-run-loop scheduling supports the audited `@unchecked Sendable` boundary; no concrete race was identified.
- **Diagnostic buffering/export is bounded and avoids repeated front-removal.** No reportable complexity or main-actor export issue remained.
- **Swift 6 complete concurrency checks pass.** No concrete task-isolation, continuation, or cancellation misuse beyond the command-orchestration findings above was established.
- **English-only, macOS 26+, and arm64-only choices are explicit scope decisions.** They are not audit defects.
- **No CI workflow is present, but no repository authority requires one.** This is a future governance option, not a finding.

## Questions, assumptions, and residual risk

- The audit assumes a reconnect is a new freshness boundary even when CoreBluetooth supplies the same UUID. A different UUID makes WL5024-PR1-AUD-001 more visible but is not required for stale state to matter.
- No authority states that delayed writes behind discovery are intended. If they are, the UI needs explicit queued-state and cancellation semantics rather than the current implicit behavior.
- The safest sidetone write order and any rollback sequence require controlled hardware evidence. The report does not infer that an unqualified rollback is safe.
- A status-only packet cannot identify its module from its bytes. Any implementation that labels it with the pending module would remain an inference and should be described as such.
- Per-key freshness may also be needed for derived device metadata, not only settings. The remediation design should inventory every value carried across reconnect/partial refresh.
- Passing automation does not establish the manual accessibility or physical-device outcomes listed above.

## Target shape

The target architecture should make five invariants explicit:

1. Every live value carries a current transport-session identity and per-key freshness; disconnect, identity change, and read failure have deterministic invalidation rules.
2. Long-running discovery is exclusive or isolated from user commands. Cancellation affects only the operation the user cancelled, and every queued/discarded command has visible disposition.
3. Composite settings are decoded and published atomically. A write to one projection cannot silently change another projection without updating the snapshot.
4. Multi-step hardware operations and diagnostic responses have typed outcomes: complete, partial, ambiguous, timed out, or failed. CLI exit status reflects that outcome.
5. Each setting row has one accessible semantic identity, and automated documentation distinguishes structural/launch checks from manual visual and assistive-technology verification.

## Phased remediation roadmap

This is multi-phase work. After operator disposition of the findings, accepted work should become a tracked remediation program rather than an unbounded audit-fix PR.

### Phase 0 — State truth and command safety

- Resolve WL5024-PR1-AUD-001 with session-bound values and fresh-read gating.
- Resolve WL5024-PR1-AUD-002 with exclusive discovery and explicit queue/cancellation behavior.
- Resolve WL5024-PR1-AUD-004 with per-key/shared-transaction freshness.
- Resolve WL5024-PR1-AUD-006 with command-scoped failure/retry state.
- Add deterministic model/controller tests for reconnect, partial refresh, queued cancellation, and retry ordering.

### Phase 1 — Composite writes and transport outcomes

- Resolve WL5024-PR1-AUD-003 by atomically modeling Quick Pause mode.
- Resolve WL5024-PR1-AUD-005 with explicit terminal pre-ready source state.
- Resolve WL5024-PR1-AUD-007 with typed multi-step outcomes and hardware-approved recovery.
- Resolve WL5024-PR1-AUD-008 and -009 with shared response dispositions and truthful process exit codes.
- Repeat bounded read-only hardware checks; perform write tests only under the repository's explicit qualification protocol.

### Phase 2 — Accessibility and verification truthfulness

- Resolve WL5024-PR1-AUD-010 with one semantic identity per setting row.
- Resolve WL5024-PR1-AUD-011 so demo progress/cancellation can actually be observed.
- Resolve WL5024-PR1-AUD-012 by narrowing claims or strengthening scenario evidence.
- Run and record the manual VoiceOver, Voice Control, Full Keyboard Access, appearance, minimum-window, icon, and focus-restoration checklist.

## Disposition

Pending operator review. Record each stable finding ID as **accepted**, **deferred** (with owner/reason/target), or **rejected** (with evidence) before implementation planning. Do not mix fixes into this audit-only change.
