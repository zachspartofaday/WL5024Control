# WL5024Control exhaustive UI-first re-audit

Date: 2026-09-01
Audited ref: `main` at `ddd6410cc075ce395e1704cd3d5d81a02ba61bae`
Verdict: **Do not call the current ref release-ready.** A HIGH state-synchronization race can restore stale settings after a successful command, and the canonical workspace gate currently reports two failures. The interface is functional and generally native, but the settings rows need a systematic alignment/spacing pass, Sound visibly duplicates slider labels, the shipping menu-bar control is disabled without an explanation, and the app has no icon artwork.

Change scope: report only. No implementation code or production asset was changed. Temporary UI-audit tests ran only in a disposable clone. A separate ear-cup/red-LED icon concept was generated during the audit but was not installed.

> Historical note: the statement above describes the original audit pass. The remediation below was implemented later on 2026-09-01 in the primary worktree.

## Remediation disposition

All 11 findings are accepted and remediated in code or assets. Remote Bluetooth captures verified CoreBluetooth authorization, connected-peripheral recovery by the exact `Dell WL5024 Headset` name, the recovered Airoha service/characteristics, notification subscription, and request delivery. Builds 3–5 corrected the GATT framing and bounded stalled CoreBluetooth attempts. Builds 6–8 added bounded probing and established the physical generic getter shape as status/module/value. The Build 9 field log validated getters for ten experimental writes plus read-only automatic power-off and Environment Detection. Build 10 removes the silent Advanced Transparency and incoming-audio cancellation controls, gates automatic power-off and Environment Detection as read-only, and preserves exact acknowledgement plus matching read-back requirements for every remaining experimental write. Receiver writes remain disabled.

| ID | Disposition | Implementation and evidence |
| --- | --- | --- |
| `WL5024-REAUD-001` | Accepted / remediated | Added monotonic `HeadsetStateUpdate` revisions across controller commands and events; `HeadsetModel.apply(_:)` rejects older/duplicate updates. Startup, reconnect, stale/duplicate, and the former race tests pass; the focused test also passed 25/25 independent process runs, with 25 iterations inside each run. |
| `WL5024-REAUD-002` | Accepted / remediated | Added one 760-point grouped detail container and adaptive `SettingsRowLayout`, shared metrics, trailing 300-point controls, and stacked rows. UI tests cover all six visible destinations at regular/minimum sizes and assert non-overlap plus common toggle/picker trailing edges. Row inset was increased to 12 points after rendered review. |
| `WL5024-REAUD-003` | Accepted / remediated | The shared slider primitive retains a native accessible name while hiding its visual label. The unsupported Sound page is now hidden from the normal interface, so no duplicated slider label ships in the visible surface. |
| `WL5024-REAUD-004` | Accepted / remediated | The menu shows a Toggle only when writable; otherwise it exposes the current automatic-media value and a read-only explanation. The read-only UI fixture verifies the value, explanation, and Settings command. |
| `WL5024-REAUD-005` | Accepted / remediated | Generated separate sRGB large/small graphite ear-cup/red-LED masters and populated all ten 16–1024 AppIcon renditions with alpha. Set `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`; Release verification requires `AppIcon.icns`, `Assets.car`, `CFBundleIconFile`, and `CFBundleIconName`. Finder, Dock, About, app-switcher, and final 16/32-point appearance remain manual field checks. |
| `WL5024-REAUD-006` | Accepted / remediated | Corrected native Toggle queries to `checkBoxes`; replaced the vacuous cancellation test with a production encode barrier; added model, qualification, BLE/HID/coordinator, recorder, discovery-policy, framing, and experimental-contract/read tests plus seven scenario-rich UI tests. Build 10 adds regression fixtures from the first full Build 9 field log. Coverage confirms execution of the state, qualification, BLE/HID/coordinator, recorder, and discovery paths; UI execution is evidenced by the macOS UI tests and retained screenshots because source coverage instrumentation does not attribute out-of-process UI automation. |
| `WL5024-REAUD-007` | Accepted / remediated | IOHID discovery is prefiltered to Dell VID `0x413C` and the known `0x0E8D/0x0808` updater identity, then name-filtered. Interfaces are keyed by registry/fallback identity; open failures emit/record the return code. Tests cover two interfaces, duplicate matches, input from both, first/final removal, filtering, and manager-open failure. No receiver PID was invented. |
| `WL5024-REAUD-008` | Accepted / remediated | Replaced Array shifting with a fixed-capacity O(1) ring retaining 5,000 chronological entries without batching away HID evidence. Wrap/order and 50,000-append tests pass; diagnostic JSON remains version 1. |
| `WL5024-REAUD-009` | Accepted / remediated | Replaced the writable-key set with complete `WriteQualification` contracts covering provenance, preparation, encoding, matching, acknowledgement validation, read-back/decoding, and comparison. Build 10 separates read definitions from the ten remaining experimental writes, makes automatic power off and Environment Detection read-only, and removes silent getters from the visible surface. Tests prove exact encodings, composite preservation, multi-write sequencing, invalid acknowledgements, mismatched read-back, and strict Build 9 response decoding. |
| `WL5024-REAUD-010` | Accepted / remediated | All Boolean decoders now require RACE response type `0x5B`, the exact command opcode/module and shape, and a value byte of exactly `0` or `1`; fixtures reject echoed commands, `2`, `255`, wrong opcode/module, and trailing payload. Automatic media now comes from DDPM's strictly decoded composite UInt16 wear response rather than the silent module-2 hypothesis. |
| `WL5024-REAUD-011` | Accepted / remediated | Diagnostic bytes/recipes/evidence are selectable and monospaced where appropriate. Export uses collecting/location/encoding/writing phases, visible progress, stable button naming, and native first-responder restoration after save cancellation and result dismissal; focused UI tests pass both recovery paths. |

### Remediation validation

Toolchain: XcodeBuildMCP 2.7.0, Xcode 26.6 (17F113), Apple Swift 6.3.3.

| Check | Remediation result |
| --- | --- |
| Canonical macOS Debug build | Pass |
| Canonical workspace test | Pass: 61 tests, 0 failures, 0 skips; regular/minimum screenshots for all six visible destinations retained in the result bundle |
| Canonical Swift package test | Pass: 54 tests in 6 suites |
| Canonical Swift package Release build | Pass |
| macOS Release build | Pass |
| Protocol probe and `--packets` mode | Pass; raw BLE GATT frames begin `05 5A` as documented; decoder tests cover `5B` responses with and without an outer transport prefix |
| Focused state stability | Pass: 25/25 independent runs |
| Per-file coverage report | Pass as execution evidence: controller `81.7%`, qualification `83.6%`, command codec `82.5%`, BLE state machine `86.0%`, HID `41.0%`, coordinator `98.5%`, recorder `93.9%`, ring buffer/discovery/catalog/state-update `100%`; UI behavior is covered out-of-process and is not attributed to source lines |
| Developer ID distribution | Pass: `0.1.0 (9)` was archived with Developer ID and hardened runtime through Xcode 26.6, accepted and exported by Apple's notarization service with its stapled ticket, strict-code-sign valid, and Gatekeeper accepted as `Notarized Developer ID` for Team `9T97GZT4MV`; ZIP integrity verified, SHA-256 `8e7283e861a88fbbde8e99839c8ac2724dde5c5a9f078ce78d86c244299f1581` |
| Physical Bluetooth/HID behavior | Partial: Build 9 connected on its first attempt, acknowledged all 272 GATT writes, and completed the bounded 263-query discovery without a transport failure. It confirmed getter responses for the composite wear flags, automatic power off, sidetone state/level, Busy Light, Voice Guidance, microphone noise cancellation, and Environment Detection. Advanced Transparency, incoming-audio noise cancellation, and Smart Switch remained silent. No setter acknowledgement or HID behavior was captured. |
| VoiceOver, Full Keyboard Access, Voice Control, icon surfaces | Manual field verification still required; automated semantics/layout/focus/appearance scenarios pass |

## Finding registry

Findings are ordered as acts-wrong behavior, systemic UI issues, release/testing gaps, then structural drift. `Confirmed` means the mechanism or rendered result was directly observed. `Inferred` means the mechanism is present but hardware timing or event volume was unavailable.

| ID | Severity | Domain | Confidence | Summary |
| --- | --- | --- | --- | --- |
| `WL5024-REAUD-001` | HIGH | State / concurrency | Confirmed; reproduced | Snapshot events can overwrite a newer command result with stale state; the focused test failed 7 of 10 runs. |
| `WL5024-REAUD-002` | MEDIUM | UI layout | Confirmed in source and renders | Forms do not share a coherent trailing control edge or adaptive row metric; margins and wrapping change by control type and width. |
| `WL5024-REAUD-003` | MEDIUM | UI / accessibility | Confirmed in source and renders | Every slider repeats its setting name inside the control after the row has already displayed that name. |
| `WL5024-REAUD-004` | MEDIUM | Menu-bar UX | Confirmed | The shipping automatic-media menu item is disabled without saying why, even though all live writes are intentionally unqualified. |
| `WL5024-REAUD-005` | MEDIUM | App identity | Confirmed | The AppIcon asset catalog declares every macOS slot but contains no filenames or images. |
| `WL5024-REAUD-006` | MEDIUM | Validation / tests | Confirmed | The canonical gate is red, the UI smoke test queries the wrong macOS role, critical runtime files have 0% coverage, and a cancellation test is vacuous. |
| `WL5024-REAUD-007` | MEDIUM | USB HID / diagnostics | Confirmed mechanism; hardware impact inferred | The monitor matches all HID devices but retains only one candidate interface and ignores manager-open failure. |
| `WL5024-REAUD-008` | MEDIUM | Performance | Confirmed complexity; runtime impact inferred | High-frequency HID capture appends and shifts a 5,000-entry Array on the main actor. |
| `WL5024-REAUD-009` | MEDIUM | Protocol safety / drift | Confirmed structural gap; current writes remain safely off | Qualification is only a set of keys; most mapped writes lack a capability-specific acknowledgement signature and read-back contract. |
| `WL5024-REAUD-010` | LOW | Protocol decoding | Confirmed | Automatic-media decoding treats every nonzero byte as `true`, converting unknown wire values into device-confirmed state. |
| `WL5024-REAUD-011` | LOW | Diagnostics UX | Confirmed | Raw protocol data is not selectable, and export has no visible progress state while its button is disabled. |

## Detailed findings

### `WL5024-REAUD-001` — stale event can replace a newer command result

Evidence:

- `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/HeadsetModel.swift:42-58` starts an event consumer that assigns every streamed snapshot directly to `model.snapshot`.
- `HeadsetModel.swift:182-190` independently assigns the snapshot returned by refresh, set, and action commands.
- `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:44-79,99-117,130-144` both yields snapshots to the stream and returns snapshots from commands. There is no revision, generation, or ordering check between those two update paths.
- `WL5024ControlPackage/Tests/WL5024ControlFeatureTests/HeadsetModelTests.swift:7-20,63-80` reproduces the same dual path: `start()` yields the initial `.integer(0)` snapshot while `set()` returns `.integer(3)`.
- The canonical workspace run failed at `HeadsetModelTests.swift:18`: expected `.integer(3)`, observed `.integer(0)`.
- Ten isolated repetitions produced 3 passes and 7 failures. This is a nondeterministic race, not a deterministic assertion mistake.

Impact: a control can complete successfully and then snap back to an older value. The same mechanism can regress connection/readiness/freshness state, so it is more serious than a flaky test.

Target shape: give the model one authoritative snapshot-ingestion path. Either commands return no snapshot and the ordered event stream owns state, or external events and command results carry a monotonically increasing revision and the model rejects older revisions. Make startup deliver/await an initial state before accepting commands, then test forced interleavings rather than timing luck.

### `WL5024-REAUD-002` — settings rows lack one alignment and spacing system

Evidence:

- Overview uses explicit `spacing: 20`, `padding(24)`, a `720`-point content maximum, and `8` points of card content padding (`HeadsetSettingsView.swift:80-120,124-157`).
- Settings pages rely on grouped `Form` defaults (`HeadsetSettingsView.swift:198-217`). Each row then combines a `LabeledContent`, a trailing `VStack(spacing: 4)`, an arbitrary `maxWidth: 280`, label spacing of `3`, and vertical padding of `4` (`HeadsetSettingsView.swift:220-250`). These numbers are not shared tokens and do not define where the control edge should land.
- The default Wear render's accessibility geometry showed a 630-point form-content region. Checkboxes ended 142 points before its right edge; pop-up buttons ended about 103 points before it. The result is a narrow “control island,” not a common trailing edge.
- Default-size renders of all seven destinations confirmed that checkboxes, pop-ups, sliders, text fields, and buttons terminate at visibly different positions.
- At the minimum supported content size (`720×500`; observed outer frame `720×552`), the Overview connection sentence wraps despite unused surrounding space, and Device splits “Device name” into a detached duplicated control line. Wear and Sound remain scrollable, but their row rhythm becomes much less stable.

Impact: scan paths jump between rows, dense pages feel improvised, and the exact concerns raised in this audit—text alignment, margins, button/checkbox spacing—repeat across the product rather than belonging to one isolated view.

Target shape:

- Define shared detail inset, card inset, row vertical inset, label/control gap, and footer spacing tokens.
- Give one `SettingsRowLayout` ownership of all rows. At regular width, use a label column and a full-width trailing control column with a common right edge. At compact width, deliberately stack label and control rather than allowing each native control to improvise wrapping.
- Keep checkboxes on the card's trailing inset; give pop-ups a consistent useful width; let text field plus Apply button use an intentional wider control variant.
- Align the section footer with the card text edge and avoid adding a second status column under controls in live unavailable states.

### `WL5024-REAUD-003` — slider names are visibly duplicated

Evidence:

- The outer row already displays `Text(key.title)` at `HeadsetSettingsView.swift:241-248`.
- `LevelSettingControl` supplies the same title as the Slider's visible label at `HeadsetSettingsView.swift:348-364`; unlike Toggle and Picker, the Slider is not given `.labelsHidden()`.
- Sound renders `Bass … Bass 0`, `Mid … Mid 0`, and `Treble … Treble 0`. Longer names such as Maximum volume and Game and chat balance wrap inside the already-constrained control column at default and minimum width.
- `Documentation/ACCESSIBILITY.md:15` explicitly expects no duplicate label.

Impact: Sound is the least polished destination and the duplicate visible names compete with the value, slider track, and outer explanation. At minimum width, they cause avoidable multi-line controls.

Target shape: hide the Slider's visual label while retaining the native accessible name, keep one concise numeric value at the trailing edge, and define one stable slider-track width. Verify VoiceOver announces name/value once.

### `WL5024-REAUD-004` — menu-bar write is silently disabled

Evidence:

- Production initializes `qualifiedWrites = []` (`LiveHeadsetController.swift:17-20`), so no live write is currently ready.
- `HeadsetMenuBarView.swift:17-25` shows an automatic-media Toggle whenever a value exists, then disables it from readiness without any status or explanation.
- The settings window does display readiness status for non-ready controls (`HeadsetSettingsView.swift:225-239`), so the two primary surfaces explain the same state differently.

Impact: the app's quickest control appears broken in the shipping configuration. A user opening only the menu cannot distinguish disconnected, read-only, awaiting validation, or command-in-flight states.

Target shape: show a concise adjacent status such as “Read-only — validation pending,” or replace the disabled Toggle with a value row until it becomes writable. Preserve the current value and offer “Open Settings…” for the explanation.

### `WL5024-REAUD-005` — app icon artwork is absent

Evidence: `WL5024Control/Assets.xcassets/AppIcon.appiconset/Contents.json:2-51` declares all ten macOS renditions but has no `filename` field and no image files. Debug and Release builds still succeed, so compilation does not protect this release-quality gap.

Impact: the product has no deliberate Finder, Dock, app-switcher, or About identity. This is especially noticeable for a small menu-bar utility whose icon is one of its few persistent brand surfaces.

Target shape for the requested concept:

- Use one simple side-profile ear-cup/hinge silhouette in matte black/graphite, not a full headset illustration.
- Add one small saturated red LED as the only bright accent. Do not use text or a Dell logo.
- Keep the cup large, asymmetric, and inside an 18–20% optical safe area so the idea survives at 16 and 32 points.
- Produce a clean 1024 master, then hand-tune the 16/32-point renditions instead of relying only on downsampling.
- Fill the existing 16, 32, 128, 256, and 512 point 1×/2× catalog slots and verify Finder, Dock, app switcher, Spotlight, About, and both desktop appearances.

A concept preview matching this direction was generated during the audit. It remains a design input, not a committed production asset.

### `WL5024-REAUD-006` — the validation gate is red and misses its riskiest seams

Evidence:

- `README.md:61-72` defines the workspace/package commands and expects zero warnings and zero failures.
- The canonical workspace test executed 23 tests and returned 21 passed, 2 failed: the real race in finding `001` and `WL5024ControlUITests.swift:21-22`.
- The UI test queries `app.switches[...]`, while macOS exposes the native SwiftUI Toggle as an accessible `CheckBox`. The failure hierarchy showed a named, enabled `CheckBox`; changing only the query to `app.checkBoxes[...]` in the disposable audit clone made the smoke test pass.
- A temporary audit-only UI test then navigated and captured Overview, Noise Control, Calls & Microphone, Wear & Automation, Sound, Device, and Diagnostics at default size, plus representative pages at the minimum size. Those tests passed and confirmed that the original UI failure was a query defect, not an unreachable control.
- Coverage from the failed canonical `.xcresult` was 34.3% overall (1,105/3,218 lines). `BLETransport`, `HIDMonitor`, `TransportCoordinator`, `HeadsetSettingsView`, `DiagnosticsView`, and the app/UI-test sources each reported 0%.
- `DiagnosticExporterTests.swift:30-40` calls `Task.checkCancellation()` in the test closure before entering `DiagnosticExporter.encode`, so the passing test does not prove the production cancellation check ran.

Impact: the repository's documented quality signal is currently unusable as a merge/release ratchet, and transport/UI regressions can remain invisible even after it turns green.

Target shape: fix the macOS role query; make the model race deterministic and then fix it; replace the cancellation test with a production-boundary test; add injectable BLE/HID/coordinator behavior tests and UI assertions for all destinations, minimum size, unavailable/disabled copy, and one recovery path. Treat coverage as a risk map, not an arbitrary percentage target.

### `WL5024-REAUD-007` — HID interface ownership is lossy

Evidence:

- `HIDMonitor.swift:17` asks the manager to match all HID devices, then filters candidates in callbacks.
- The monitor owns one `matchedDevice` (`HIDMonitor.swift:7`) and overwrites it for every candidate (`HIDMonitor.swift:71-84`).
- Removal only counts if it is that one last device (`HIDMonitor.swift:87-92`), and input from every other candidate interface is discarded (`HIDMonitor.swift:94-112`).
- `IOHIDManagerOpen`'s return code is ignored (`HIDMonitor.swift:57`), so an open failure produces neither state nor diagnostic evidence.
- The repository's own physical checklist asks for the receiver's interface inventory and report IDs (`Documentation/PROTOCOL.md:37-44`), implying multi-interface capture is a required scenario. Actual WL5024 interface count was not verified in this audit.

Impact: if the receiver exposes multiple matching interfaces, captures omit all but the last. Removing the last-matched interface can report “receiver removed” while another candidate remains; removing an earlier one is ignored. A manager-open failure looks like an indefinitely absent receiver.

Target shape: track candidate interfaces in a dictionary keyed by stable IORegistry/location/interface identity, record input for every candidate, and emit receiver removal only when the candidate set becomes empty. Check and report the manager-open result. Once hardware IDs are known, move as much filtering as possible into the manager match dictionaries.

### `WL5024-REAUD-008` — the HID capture hot path shifts an Array on the main actor

Evidence:

- `DiagnosticRecorder` is `@MainActor` and stores `[DiagnosticEntry]` (`DiagnosticRecorder.swift:71-76`).
- Every record appends and, after 5,000 entries, calls `removeFirst` (`DiagnosticRecorder.swift:80-88`), an O(n) shift for an Array.
- HID input invokes that path for every value callback (`HIDMonitor.swift:94-112`).

Impact: after the buffer fills, sustained hardware input can repeatedly move thousands of entries on the UI actor. The exact jank depends on real receiver event rate and was not benchmarked.

Target shape: use a bounded ring/deque with O(1) eviction, batch high-frequency HID events where fidelity permits, and measure capture while resizing/navigating the settings window. The existing off-main `@concurrent` JSON encode/write path is a strength and should remain.

### `WL5024-REAUD-009` — write qualification is a key set, not an executable safety contract

Evidence:

- Repository authority requires a captured acknowledgement signature plus confirmed read-back before enabling each write (`README.md:11`; `Documentation/PROTOCOL.md:31-35`).
- `RaceResponseMatcher` validates only opcode and optional module (`TransportTransaction.swift:3-20`). It has no capability-specific payload/status predicate.
- `LiveHeadsetController.set` performs a read-back only for `.automaticMedia`; other mapped setters publish the requested value after a matching transaction (`LiveHeadsetController.swift:82-117,165-186`).
- Qualification is represented only as `Set<HeadsetSettingKey>`. Adding a future key to that set can therefore enable a path whose acknowledgement/read-back policy is absent.
- Production's set is empty, so **there is no currently enabled unsafe live write**.

Impact: the present release is fail-closed, but the type system does not preserve the documented evidence gate when capabilities are enabled later. Safety depends on reviewers remembering extra steps outside the qualification representation.

Target shape: replace the bare key set with a per-capability qualification object containing the exact request encoder, acknowledgement matcher/status validator, read-back transaction/decoder, comparison rule, provenance, and tests. A capability should be impossible to mark writable without a complete contract.

### `WL5024-REAUD-010` — unknown boolean values become confirmed `true`

Evidence: `WL5024Command.swift:52-65` validates the frame and module, then returns `bytes[2] != 0`. Values such as `0x02` or `0xFF` are accepted as `true`; `LiveHeadsetController.swift:72-76` then marks the value `.deviceConfirmed`.

Impact: a protocol change or status byte can masquerade as a valid setting, contrary to the repo's fail-closed posture.

Target shape: accept only the physically observed domain (`0` and `1` unless traces establish another encoding), throw `malformedResponse`/`invalidValue` otherwise, and add negative fixtures.

### `WL5024-REAUD-011` — Diagnostics is readable but not optimized for diagnostic work

Evidence:

- Raw frame values and capability recipes are ordinary `Text`/`LabeledContent` without text selection (`DiagnosticsView.swift:33-56`).
- Export changes `isExporting` and disables the button, but the label never changes and there is no `ProgressView` or status text (`DiagnosticsView.swift:7-8,21-30,85-111`).

Impact: users cannot directly copy the most technical values, and longer refresh/encode/write work presents as a silently disabled button.

Target shape: enable selection for raw protocol/capability text, use monospaced digits/bytes consistently, and replace or accompany the button with a named progress/status state. Preserve focus when the save panel and result alert close.

## Scope and authority

| Field | Resolved value |
| --- | --- |
| Repository | `https://github.com/zachspartofaday/WL5024Control.git` |
| Ref | Clean remote `main` at `ddd6410cc075ce395e1704cd3d5d81a02ba61bae` |
| Checkout method | Fresh clone in `/tmp`; the user's worktree was preserved and used only to add this report |
| Active issue / PR | None returned by GitHub |
| Repository instructions | No `AGENTS.md` or `CONTRIBUTING.md`; README and documentation are authority |
| Product authority | User's UI/UX-priority audit request, `README.md`, `Documentation/PROTOCOL.md`, and `Documentation/ACCESSIBILITY.md` |
| Prior state | The earlier `2026-09-01-wl5024-repository-audit.md` and its remediation disposition were reviewed, then current HEAD was revalidated rather than assumed clean |
| Excluded | Parent-folder Dell firmware/updater artifacts, firmware flashing/factory reset, physical command qualification, release notarization/distribution |

## Inventory

| Surface | Inventory |
| --- | --- |
| Tracked content | 64 files; 44 Swift files; 3,467 Swift lines; 4 Markdown files |
| Xcode | One macOS app target and one XCTest UI-test target in one workspace/project |
| Swift package | `WL5024ControlFeature` library, `WL5024Probe` executable, one Swift Testing target |
| Tests | Five Swift Testing source files plus one XCTest UI-test file; 22 package tests and one checked-in UI test discovered by the workspace gate |
| UI | Settings window; seven sidebar destinations; menu-bar menu/label; recovery/export alerts; save panel |
| Product model | 32 settings/actions across noise, calls, wear, sound, and device pages |
| Hardware seams | CoreBluetooth RACE transport; read-only IOHID receiver discovery/capture |
| Platform | macOS 26+, Apple silicon, Swift 6 complete concurrency |
| Dependencies | Apple frameworks only; no third-party package dependencies |

No SwiftData, Core Data, Keychain/CryptoKit/LocalAuthentication, C/Objective-C bounds-safety surface, UIKit, custom AppKit view hierarchy, custom focus APIs, or custom animation system was found. Those specialists were not expanded into speculative findings.

## UI/UX coverage

### Rendered surface matrix

| Surface | Default demo | Minimum content size | Disabled/error/live states | Result |
| --- | --- | --- | --- | --- |
| Overview | Rendered | Rendered at `720×500` content minimum | Source reviewed | No overlap; connection copy wraps awkwardly; finding `002` |
| Noise Control | Rendered | Shared layout reviewed via representative pages | Source reviewed | Control gutter/alignment issue; finding `002` |
| Calls & Microphone | Rendered | Shared layout reviewed via representative pages | Source reviewed | Sparse but functional; same control gutter |
| Wear & Automation | Rendered | Rendered; lower rows reachable by scrolling | Source reviewed | Checkbox/pop-up column and variable wrapping; finding `002` |
| Sound | Rendered | Rendered; lower rows reachable by scrolling | Source reviewed | Duplicate slider names and wrapped controls; findings `002-003` |
| Device | Rendered | Rendered | Source reviewed | Device-name control detaches/wraps; finding `002` |
| Diagnostics | Rendered | Rendered; list scrolls | Source reviewed | Legible; copy/progress gap in `011` |
| Menu bar | AX/source inventoried | N/A | Source reviewed | Silent disabled toggle; finding `004` |
| Alerts/save panel | Source reviewed | N/A | Source reviewed | Typed recovery exists; manual focus return not executed |

### Apple interface axes

| Axis | Result |
| --- | --- |
| Layout and spacing | All destinations rendered in demo mode at the default launch size; Overview, Wear, Sound, Device, and Diagnostics rendered at the minimum. Findings `002-003`. |
| Typography | Native semantic text styles; no fixed-size user text. Long English copy wraps without overlap, but control-label duplication causes crowding. |
| Color | System/semantic colors; connected state is also conveyed by text and symbol. Current dark appearance rendered clearly. |
| Accessibility semantics | Failure hierarchy confirmed named Refresh button, named checkboxes, named pop-ups, labeled sidebar, and named menu-bar status item. The UI-test role was wrong, not the control label. |
| Focus and keyboard | Source uses native controls and no focus overrides. Full Keyboard Access, VoiceOver, Voice Control, alert focus return, and save-panel focus return were not manually executed. |
| Motion | No custom animation, transition, or motion-only information path found. |
| Appearance stress | A command-line attempt to override the app to light appearance did not change the rendered appearance. Light, increased contrast, reduced transparency, and largest practical text remain manual gates. |
| Localization / RTL | English-only is explicitly documented in `README.md:9`; no localization defect was opened. RTL was not treated as a release requirement. |

The semantic Computer Use workflow could not run because its installed server and client versions differ. Per that workflow's rules, ad-hoc GUI automation was not substituted. Runtime evidence instead came from Xcode's native UI test recording, accessibility hierarchy, and a disposable XCTest screenshot harness. The captured whole-desktop screenshots were not committed to the repository.

## Validation performed

Toolchain: XcodeBuildMCP 2.7.0, Xcode 26.6 (17F113), Apple Swift 6.3.3.

| Check | Result |
| --- | --- |
| Fresh clone / ref | Pass: exact clean remote `main` at `ddd6410c` before audit-harness edits |
| macOS Debug build | Pass; one App Intents metadata “skipped” toolchain notice, no Swift compile error |
| macOS Release build | Pass |
| Swift package Release build | Pass |
| Swift package tests | Pass: 22 tests in 5 suites |
| Canonical workspace tests | **Fail:** 21 passed, 2 failed of 23; findings `001` and `006` |
| Focused model repetition | **Fail intermittently:** 3 passed, 7 failed of 10 |
| Coverage | 34.3% overall (1,105/3,218); critical runtime/UI files at 0%; finding `006` |
| Checked-in UI smoke | **Fail:** wrong `Switch` role query |
| UI smoke with query corrected in disposable clone | Pass: 2 tests, 0 failures |
| Audit-only all-page capture | Pass: every destination navigated and captured |
| Audit-only minimum-size capture | Pass: outer frame `720×552`, corresponding to the declared `720×500` content minimum; representative pages navigated and captured |
| Light appearance override attempt | Inconclusive: launch succeeded but appearance remained dark |
| Physical Bluetooth/USB, permissions, sleep/wake, call state | Skipped: no supplied hardware trace; physical qualification remains fail-closed |
| VoiceOver, Full Keyboard Access, Voice Control | Skipped: semantic Mac-control bridge version mismatch |
| Lint / format / hosted CI | Skipped: no repository authority or configuration exists |

The eight “not stripping binary because it is signed” messages during UI tests originate from signed XCTest frameworks. They were treated as Xcode/toolchain noise, not repository defects. XcodeBuildMCP's `--show-codecov` wrapper was also incompatible with its underlying Swift command; coverage was successfully read from the workspace `.xcresult` instead.

## Overturned suspicions and confirmed strengths

- The automatic-media control is present, enabled in demo mode, and intrinsically labeled. The checked-in UI test fails because it asks XCTest for a `Switch`; macOS reports a `CheckBox`.
- Minimum-size Wear, Sound, Device, and Diagnostics content remains in scroll containers. Partially visible bottom rows are scroll affordance, not confirmed unreachable content.
- Representative interactive controls have native accessible labels; the current problem is duplication/spacing, not a systemic unnamed-control failure.
- The interface uses system colors and native controls, with no custom focus-ring suppression or motion-only state.
- Recovery alerts provide typed actions, refresh freshness is separated from attempted time, notification setup waits for success, and transport disconnects are source-specific—the prior remediation materially improved these areas.
- Shipping live writes remain disabled because `qualifiedWrites` is empty. Finding `009` is a future-enablement guardrail, not a claim that current hardware writes are unsafe.
- English-only, macOS 26+, and arm64-only are documented product choices, so they were not reopened as defects.
- Strict Swift concurrency and clean compilation do not disprove finding `001`; it is a semantic ordering race within valid actor isolation.

## Target product shape

- One ordered/revisioned state path owns every snapshot and cannot regress after a completed command.
- One adaptive settings-row component owns horizontal insets, label/control columns, row heights, trailing alignment, disabled-status placement, and compact stacking.
- A setting name appears once visually and once semantically; values remain close to their controls.
- Menu-bar and window surfaces explain read-only/validation states consistently.
- The app carries a simple, recognizable graphite ear-cup icon with a single red LED accent at every macOS size.
- HID discovery records every candidate interface without letting one interface overwrite receiver ownership.
- Enabling a live write requires a typed, tested acknowledgement-and-read-back qualification object—not a bare key insertion.
- The canonical workspace command is green, deterministic, and exercises the highest-risk model/transport/UI paths.

## Phased remediation roadmap

### Phase 0 — Restore trustworthy state and a green gate

1. **PR: ordered snapshot ownership** (`WL5024-REAUD-001`)
   Choose one authoritative update path or add revisions; add deterministic initial-event/command-result interleaving tests.
2. **PR: repair the canonical smoke gate** (part of `WL5024-REAUD-006`)
   Query `checkBoxes`, keep the accessible-name assertions, replace the vacuous cancellation test, and require repeated model stability.

### Phase 1 — UI/UX polish, the requested priority

3. **PR: settings-row layout system** (`WL5024-REAUD-002`)
   Introduce shared metrics and regular/compact row variants; align checkbox, picker, slider, text, action, and readiness states across every page.
4. **PR: Sound and Device control cleanup** (`WL5024-REAUD-003`)
   Remove visible slider-label duplication, stabilize track/value widths, and give device naming an intentional adaptive layout.
5. **PR: menu and Diagnostics feedback** (`WL5024-REAUD-004`, `WL5024-REAUD-011`)
   Explain read-only state, add selectable diagnostic text, progress, and focus-return verification.
6. **PR: production app icon** (`WL5024-REAUD-005`)
   Refine the generated ear-cup/red-LED concept, hand-check small sizes, populate all ten AppIcon slots, and add a release checklist screenshot.

### Phase 2 — Capture and qualification robustness

7. **PR: multi-interface HID ownership and bounded capture** (`WL5024-REAUD-007`, `WL5024-REAUD-008`)
   Track all candidate interfaces, report manager-open failures, adopt an O(1) bounded buffer, and add a synthetic high-rate capture test.
8. **PR: executable capability qualification** (`WL5024-REAUD-009`, `WL5024-REAUD-010`)
   Model acknowledgement, read-back, comparison, strict decoding, and provenance together; keep the production qualification collection empty until traces fill each contract.

### Phase 3 — Release ratchet and physical evidence

9. Add fake BLE/HID/coordinator tests and all-page demo UI coverage; re-run default/minimum, light/dark, contrast, transparency, large text, VoiceOver, keyboard, Voice Control, alert, save-panel, and menu-bar scenarios.
10. Execute `Documentation/PROTOCOL.md` with physical WL5024 hardware one capability at a time. Attach sanitized interface inventories and request/ack/read-back evidence before enabling any key.

## Acceptance checks for the UI phase

- At regular width, every interactive control shares one trailing edge inside its card.
- At the `720×500` content minimum, no label/control collision occurs; intentional stacked rows have a consistent gap and controls remain reachable by scrolling.
- Sound displays each setting name once, a stable slider track, and one nearby numeric value.
- Device naming has one visible label, a field with useful width, and an Apply button with standard button insets.
- Disabled controls expose a visible reason in both the settings window and menu bar.
- VoiceOver announces label, value, enabled state, and validation reason once; keyboard traversal reaches every action with visible focus.
- Light/dark, increased contrast, reduced transparency, and large text remain legible without relying on color alone.
- App icon remains recognizable at 16 points and the red LED does not disappear or bloom into the cup silhouette.

## Assumptions, skips, and residual risk

1. The requested visual direction is interpreted as “reminiscent of the side ear cup” rather than a photorealistic product rendering or use of Dell's logo/trade dress.
2. Hardware-specific impact in findings `007-009` remains inferred until a WL5024 and receiver are supplied. Current production writes stay off.
3. Dark appearance and demo/populated states received the strongest runtime coverage. Live unavailable, Bluetooth permission, transport failure, pending command, save-panel, alert, light/contrast/transparency, and assistive-technology scenarios still require manual execution.
4. The audit did not authorize issue creation, implementation PRs, release signing/notarization, or changes to external systems.
5. The refined icon preview is not yet a production-ready asset set; small-size vector/raster cleanup and trademark review remain implementation tasks.

## Summary

The repository is compact, compiles in Debug and Release, uses a strong fail-closed hardware posture, and now has meaningful typed state/recovery scaffolding. Its release blocker is the nondeterministic dual-snapshot update path. Its main UI debt is equally clear from source and renders: margins and row spacing are locally chosen, controls do not share a coherent trailing edge, Sound duplicates labels, compact Device layout is awkward, and the menu bar does not explain its disabled control. The simplest useful sequence is to fix snapshot ownership and the red gate, then land one shared row-layout pass and the ear-cup/red-LED icon before expanding hardware qualification.
