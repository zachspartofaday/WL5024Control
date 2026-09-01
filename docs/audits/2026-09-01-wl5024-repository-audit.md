# WL5024Control repository audit

Date: 2026-09-01
Verdict: **Block hardware-backed use and release readiness until the five HIGH findings are resolved.**
Change scope: report only; no implementation code was changed.

## Findings

Findings are ordered as acts-wrong behavior, structural gaps, then drift risk. `Confirmed` means the behavior follows directly from source or command evidence. `Inferred` means the mechanism is present but its user-visible impact depends on runtime volume or hardware timing.

| ID | Severity | Domain | Evidence and confidence | Finding | Fix direction |
| --- | --- | --- | --- | --- | --- |
| `WL5024-AUD-001` | HIGH | Protocol / concurrency | `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/BLETransport.swift:266-289`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:74-77`; `README.md:13-14`. **Confirmed.** | A pending transaction accepts the first notification on the notify characteristic, with no opcode/module/request correlation. The repository explicitly expects unsolicited notifications. A coincident button or wear event can therefore complete a request; setters then publish the requested value as successful without validating the acknowledgement or reading it back. | Store an expected response matcher with each pending request, route non-matching frames to an unsolicited-event path, validate set acknowledgements, and read back before publishing state. Keep live writes disabled where a matcher is not physically qualified. |
| `WL5024-AUD-002` | HIGH | Transport state | `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/HIDMonitor.swift:87-92`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/TransportCoordinator.swift:48-52`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:99-101`. **Confirmed.** | Removing a read-only USB receiver emits the same generic `.disconnected` update as losing Bluetooth. The coordinator forwards it even when Bluetooth is the active transport, and the controller clears the connected state. Unplugging the receiver can therefore disable a still-live Bluetooth session. | Make updates transport-specific (`receiverRemoved`, `bluetoothDisconnected`) or carry a source on every update. Only clear the active connection when the active transport disconnects. Add a state-machine test for “Bluetooth connected + receiver removed.” |
| `WL5024-AUD-003` | HIGH | Capability model / UI | `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:6-10,67-71,114-135`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:150-162,186`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetMenuBarView.swift:17-22`; `README.md:41-43`. Commands report 32 exposed settings but only 7 live setter cases. **Confirmed.** | All 32 controls are presented from defaults and disabled only while that same key is pending. Twenty-five settings/actions have no live command, and every control is also enabled while disconnected or still awaiting qualification. The footer says changes are written even though most interactions deterministically fail. This conflicts with the README promise that unvalidated writes remain disabled. | Add explicit availability/readiness to each capability (`unavailable`, `readOnly`, `validationPending`, `ready`), represent unread values as unknown rather than defaults, and derive enabled state and explanatory copy from connection plus qualification. Apply the same gate to the menu-bar toggle and refresh action. |
| `WL5024-AUD-004` | HIGH | Accessibility | `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:103-109,189-227`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetMenuBarView.swift:17-22`. **Confirmed at source; runtime AX walk unavailable.** | The refresh button is image-only with no intrinsic text label, and the toggle, picker, and slider are created with empty labels. A neighboring `LabeledContent` does not give the interactive child a reliable accessible name for VoiceOver, Voice Control, or keyboard inspection. This is a systemic unnamed-control escalation trigger. | Give each native control `key.title` as its real label, then hide that label visually where needed. Build refresh as `Button("Refresh", systemImage: ...)` with an icon-only label style. Verify names, values, and activation in VoiceOver and keyboard navigation. |
| `WL5024-AUD-005` | HIGH | Interface writing / recovery | `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:35-45`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/DiagnosticsView.swift:56-66,87-90`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Core/HeadsetError.swift:14-25`. **Confirmed.** | Command and export failures lead to alerts whose only path is `OK`; several messages expose raw transport text or state the failure without a recovery step. An error with no way to recover is a HIGH interface trigger. | Model typed recovery (`Retry`, `Reconnect`, `Open Bluetooth Settings`, `Choose Another Location`, or an explicit “requires hardware validation” disabled state). Keep technical detail in Diagnostics and make the alert answer “what can I do next?” |
| `WL5024-AUD-006` | MEDIUM | Model correctness | `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:42-57`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/HeadsetModel.swift:89-100`. **Confirmed.** | `refresh()` catches transport/decoding errors, emits an event, stamps `lastUpdated`, and returns a successful snapshot with the previous/default value. The diagnostic caller's catch block cannot observe those failures. The UI can label stale data as freshly updated, and the exported report misses the intended capture-failure entry. | Throw refresh failures to the caller or return an explicit freshness/result state. Only advance `lastUpdated` after a validated response; separately record `lastAttemptedAt` if useful. Test timeout, malformed frame, and cancellation paths. |
| `WL5024-AUD-007` | MEDIUM | Concurrency / controls | `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/HeadsetModel.swift:45-79`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/BLETransport.swift:53-55`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:212-227`. **Confirmed mechanism; hardware timing not exercised.** | The model serializes only repeated writes to the same key, while the transport permits one global transaction. Fast edits to different controls produce `busy`. A slider starts a write on every value callback, but the first pending write causes later drag values to be discarded, so the persisted value can be an early intermediate position. | Add one model-level command serializer/queue and cancellation policy. Keep slider state local while dragging and commit once at edit end, or debounce to the latest value. Expose a global in-flight state where concurrent operations are unsupported. |
| `WL5024-AUD-008` | MEDIUM | Bluetooth lifecycle | `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/BLETransport.swift:109-145,233-264`. **Confirmed mechanism.** | The transport declares itself ready immediately after requesting notification subscription, before `didUpdateNotificationStateFor` confirms success. Service, characteristic, and incomplete-characteristic failures emit `.failed` but do not cancel/clear the retained peripheral or resume scanning, so discovery can remain stranded after a setup error. | Become ready only after notification state succeeds. Route every setup failure through one cleanup path that clears characteristics/peripheral, cancels the connection when needed, and restarts scanning. Add a retry/backoff policy and injectable lifecycle tests. |
| `WL5024-AUD-009` | MEDIUM | Testing / regression safety | `WL5024Control/WL5024Control.xctestplan:18-25`; `WL5024ControlUITests/WL5024ControlUITests.swift:18-26`; coverage command evidence below. **Confirmed.** | Seven tests pass, but feature-source line coverage is 18.68%; `HeadsetModel`, `LiveHeadsetController`, all transport files, and all views are at 0%. The workspace test plan excludes the UI-test target, whose only test launches the app and asserts `true`. The green gate does not exercise the state machine that owns hardware safety. | Inject a raw transport and transport-event source, then test response matching, timeouts/cancellation, disconnect source identity, readiness, stale refresh, command serialization, and qualification gates. Add the UI target to a demo-mode test plan with non-vacuous navigation/control-name assertions. |
| `WL5024-AUD-010` | MEDIUM | Build configuration | `Config/Shared.xcconfig:18-23`; `WL5024Control.xcodeproj/project.pbxproj:255-290`; effective build settings report `SWIFT_VERSION = 5.0` and `EFFECTIVE_SWIFT_VERSION = 5`. **Confirmed.** | The shared configuration declares Swift 6 with complete strict concurrency, but target-level settings override both app and UI-test targets back to Swift 5. The package uses Swift tools 6.2, leaving neighboring modules under different language enforcement without documenting that choice. | Remove the target-level Swift 5 overrides or document an intentional split. Rebuild app, package, and tests in the selected Swift mode and ratchet warnings to zero. |
| `WL5024-AUD-011` | MEDIUM | Performance / diagnostics | `WL5024ControlPackage/Sources/WL5024ControlFeature/Diagnostics/DiagnosticRecorder.swift:51-68,71-108`; `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/DiagnosticsView.swift:73-90`. **Inferred.** | Up to 5,000 entries, including hex strings derived from payloads capped at 8,192 bytes, are assembled and JSON-encoded on `@MainActor`; the encoded data is then atomically written from a main-actor task. A large hardware capture can freeze the settings window during export. | Snapshot the Sendable report payload on the main actor, encode and write it in explicitly offloaded work, then return only progress/result state to the UI. Add a large-report performance fixture and cancellation behavior. |
| `WL5024-AUD-012` | LOW | Localization / drift | `WL5024ControlPackage/Sources/WL5024ControlFeature/Resources/Localizable.xcstrings` has 0 entries; no localization resource is present in the built app; examples include `WL5024ControlPackage/Sources/WL5024ControlFeature/Core/CapabilityDefinition.swift:8-13` and `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:119-129`. **Confirmed; no non-English requirement was found.** | Localization is only partially modeled. Some package model strings use `LocalizedStringResource(..., bundle: #bundle)`, while many visible strings are plain `String` values or package `Text` literals, and the catalog is empty. English renders, but extraction/translation has no effective ratchet. | Decide and document localization scope. If localization is intended, populate and validate the package catalog, keep user-facing model text as `LocalizedStringResource`, and use the package bundle for package-owned literals. Add an extraction/catalog check. |

## Scope and authority

| Field | Resolved value |
| --- | --- |
| Repository | `zachspartofaday/WL5024Control` (private) |
| Ref audited | `main` at `92eae9ffd082a57f13c93d60fc12bb70b271822f` |
| Checkout | Clean ephemeral clone of the remote; the operator's checkout was not used for builds or source inspection |
| Active issue / PR | None: GitHub returned no issues or pull requests |
| Repository instructions | No `AGENTS.md`, `CONTRIBUTING.md`, plan, status document, or workflow configuration was present |
| Product authority | Operator audit request, `README.md`, and `Documentation/PROTOCOL.md` |
| Method | Tracked-file inventory, targeted specialist review, effective build-setting inspection, clean Debug/Release builds, package/workspace tests, coverage, built-entitlement inspection, and a bounded demo-mode render |
| Evidence threshold | Tracked source with stable lines, reproducible commands, or observed demo-mode render. Hardware-dependent claims are explicitly marked as unverified or inferred. |

The audit covers engineering correctness, SwiftUI and macOS interface quality, Swift concurrency, Swift Testing, and the requested UIKit modernization inventory. It excludes the Dell firmware/updater artifacts outside the repository, firmware flashing and factory reset, physical Bluetooth/USB writes, sleep/wake and call-state hardware scenarios, release signing/notarization, and claims that require Dell hardware traces.

## Inventory

| Surface | Inventory |
| --- | --- |
| Tracked content | 52 files; 34 Swift files; 3 test Swift files; 2 Markdown documents |
| Xcode | One workspace, one project, app target `WL5024Control`, UI-test target `WL5024ControlUITests` |
| Swift package | Library `WL5024ControlFeature`, executable `WL5024Probe`, test target `WL5024ControlFeatureTests` |
| Schemes | `WL5024Control`, `WL5024ControlFeature`, `WL5024Probe` |
| Product areas | Core model, RACE protocol, CoreBluetooth transport, read-only IOKit HID monitor, diagnostics, settings/menu-bar views, probe CLI |
| Capability surface | 32 settings/actions; 7 live setter mappings; receiver writes intentionally disabled |
| Platform | macOS 26.0 minimum; arm64 only; package tools version 6.2 |
| Local gates | README run/probe commands, Swift package tests, workspace test plan; no configured formatter, linter, CI workflow, or merge-gate document |

## Apple interface coverage

Resolved UI scope: the macOS Overview, six settings/diagnostics destinations, menu-bar menu and label, command/export alerts, and the connection/qualification/error states at the audited commit.

| Domain | Owner | Coverage |
| --- | --- | --- |
| Accessibility | `apple-accessibility-pro` | Findings in `WL5024-AUD-004`; source reviewed. VoiceOver/Voice Control manual walk not verified because the semantic Computer Use pipe failed to start. |
| Focus | `swift-focusengine-pro` | Clear at source for custom focus anti-patterns: the app uses native SwiftUI controls and no custom `NSView`, key-view loop, `FocusState`, or focus-ring overrides. Keyboard walk not verified. |
| Layout | `apple-interface-pro` | Demo Overview rendered in dark appearance at the default 880×620 size without visible clipping. Minimum-size, longest-copy, other pages, and RTL scenarios not verified because UI navigation tooling was unavailable. |
| Writing | `apple-interface-pro` | Recovery finding `WL5024-AUD-005` and localization drift `WL5024-AUD-012`. No terminology authority exists beyond the repository copy. |
| Typography | `apple-interface-pro` | Semantic text styles are used except for a 34-point headset symbol, which is not text. Default Overview render was clear; accessibility sizes and long translations not verified. |
| Color and tokens | `apple-interface-pro` | Clear at source and in the dark Overview capture: views use semantic/system styles, and connected state also has text and icon cues. Light, increased-contrast, and reduced-transparency environments not verified. |
| Polish and motion | `apple-interface-pro` | Clear at source: no custom animation or motion-only state was found. Interactive runtime feel not verified. |

### Surface and state matrix

| Surface | Populated demo | Searching / disconnected | Qualification pending | Error / disabled / pending | Environment stress |
| --- | --- | --- | --- | --- | --- |
| Overview | Rendered, dark, 880×620 | Source reviewed | Source reviewed | Source reviewed; findings `003-005` | Not verified beyond default dark |
| Noise, calls, wear, sound, device pages | Source reviewed | Source reviewed | Source reviewed | Source reviewed; findings `003`, `004`, `007` | Not verified: no working UI navigation pipe |
| Diagnostics | Source reviewed | Source reviewed | Source reviewed | Source reviewed; findings `005`, `011` | Not verified |
| Menu bar | Source reviewed | Source reviewed | N/A | Source reviewed; findings `003`, `004` | Not verified |
| Alerts / save panel | Source reviewed | N/A | N/A | Source reviewed; finding `005` | Manual focus/VoiceOver return not verified |

## UIKit modernization result

The requested `uikit-app-modernization` pass inventoried all four task families and found zero occurrences:

- no `UIScreen.main` / shared-screen access;
- no legacy interface-orientation access;
- no UIKit application-to-scene lifecycle APIs or shared key-window lookup;
- no UIKit safe-area/global-screen sizing assumptions.

The product is a native macOS SwiftUI app with small AppKit seams (`NSApp`, `NSSavePanel`), so no UIKit modernization issue or Apple UIKit task reference applies.

## Validation performed

Toolchain: XcodeBuildMCP 2.7.0, Xcode 26.6 (17F113), Apple Swift 6.3.3, macOS SDK 26.5.

| Check | Result |
| --- | --- |
| Fresh clone and exact ref | Pass: clean `main` at `92eae9f` |
| Xcode project/workspace and scheme discovery | Pass: one project, one workspace, three schemes |
| Effective app build settings | Pass for discovery; exposed `SWIFT_VERSION = 5.0`, strict concurrency complete, macOS 26, arm64 |
| `xcodebuildmcp macos build`, Debug | Pass; 0 warnings, 0 errors |
| `xcodebuildmcp macos build`, Release | Pass; 0 warnings, 0 errors |
| `xcodebuildmcp swift-package build`, Release | Pass; 0 warnings, 0 errors |
| `xcodebuildmcp swift-package test` | Pass; 7 tests, 0 failures |
| `xcodebuildmcp macos test` through workspace plan | Pass; 7 tests, 0 failures; UI target not included |
| `swift run WL5024Probe --packets` | Pass; emitted the documented get/disable/enable frames |
| SwiftPM coverage | Pass using native `swift test --enable-code-coverage`; feature source 404/2,163 lines (18.68%) |
| Built app entitlements / Info.plist | Pass: app sandbox, Bluetooth, USB and user-selected read/write entitlements are embedded; Bluetooth purpose text and version metadata are present |
| Demo launch | Pass with `--demo`; Overview rendered in dark appearance at 880×620; app stopped cleanly afterward |
| Lint / formatting / hosted CI | Skipped: no repository configuration or authority exists |
| Physical hardware and permission scenarios | Skipped by scope and protocol safety boundary |
| VoiceOver, keyboard-only, minimum-window and environment matrix | Not verified: semantic Computer Use startup failed and no repository preview/UI fixture exists |

XcodeBuildMCP's `--show-codecov` wrapper was also tried, but version 2.7.0 translated it to the unsupported `swift test --show-code-coverage` flag. The repository's tests did not fail; native SwiftPM coverage was used instead.

## Overturned suspicions

- Effective build settings show `ENABLE_APP_SANDBOX = NO` and resource-access toggles as `NO`, but the built signed app contains the required sandbox, Bluetooth, USB and user-selected file entitlements. This is not an entitlement defect.
- `MainActor.assumeIsolated` around CoreBluetooth/IOHID callbacks looked risky initially, but CoreBluetooth is explicitly created on `.main` and the HID manager is scheduled on the main run loop. No off-actor call site was found.
- The connection icon uses green, but status is also conveyed by symbol and text; state is not carried by color alone.
- The 34-point `.font(.system(size:))` use applies to the decorative headset symbol, not user text, so it is not a Dynamic Type violation.
- XCTest in `WL5024ControlUITests` is correct because Swift Testing does not support UI tests. The issue is exclusion and vacuous assertions, not framework choice.
- No legacy UIKit modernization occurrence was found; absence is recorded above rather than converted into speculative work.

## Open questions and assumptions

1. The audit assumes this repository is intended to progress from a protocol-research prototype to a safe hardware controller because the README advertises implemented settings. If it is intentionally diagnostics-only, live controls should still be gated and labeled as non-operational.
2. Is macOS 26+ and arm64-only an intentional product constraint? Both are enforced but not documented in the README.
3. Is English-only an intentional release constraint? No localization policy exists.
4. Exact response/acknowledgement matching cannot be finalized without the physical traces already required by `Documentation/PROTOCOL.md`. Until then, disabling the affected writes is the safe target shape.
5. There is no operator disposition yet. Accepted, deferred, and rejected outcomes should be appended after review.

## Target shape

- Transport updates carry their source, and removing a secondary/discovery transport cannot invalidate the active one.
- Every transaction has one expected response signature, unmatched notifications remain unsolicited events, cancellation/timeout completes exactly once, and write state is published only after validated acknowledgement/readback.
- One serializer owns all headset commands; controls display local edit state and commit predictably.
- Capability definitions are the single source of truth for readiness, current-value confidence, access and UI enabled state. Unknown values never masquerade as headset defaults.
- Errors preserve stale/fresh state and offer a concrete recovery action while technical details remain in Diagnostics.
- Native controls have intrinsic names and values, and the demo harness exercises keyboard and accessibility behavior.
- The clean gate covers transport/model state transitions, malformed and unsolicited protocol frames, demo UI smoke behavior, and one documented Swift language mode.

## Phased fix list

Treat accepted multi-phase remediation as a small program in this repository.

### Phase 0 — Contain unsafe and misleading behavior

1. **PR: capability readiness and UI containment** (`WL5024-AUD-003`, part of `005`)
   Add explicit readiness/value-confidence state; disable every unqualified write and disconnected action; correct footer/menu-bar behavior. This can ship without hardware traces.
2. **PR: transport-source state identity** (`WL5024-AUD-002`)
   Split receiver removal from Bluetooth disconnect and add deterministic state-machine tests.
3. **PR: accessible names and recovery surface** (`WL5024-AUD-004`, `WL5024-AUD-005`)
   Name controls intrinsically, supply recovery actions/copy, and add demo-mode UI assertions plus a manual VoiceOver/keyboard checklist.

### Phase 1 — Make transactions trustworthy

4. **Issue/PR series: injectable transport and transaction matcher** (`WL5024-AUD-001`, `WL5024-AUD-006`, `WL5024-AUD-008`, `WL5024-AUD-009`)
   First introduce a fakeable raw transport/event source; then add opcode/module matchers, unsolicited routing, setup cleanup/retry, refresh freshness semantics, negative protocol cases and coverage. Keep writes disabled until each matcher is backed by a captured trace.
5. **PR: command serialization and edit semantics** (`WL5024-AUD-007`)
   Serialize commands globally, commit sliders at edit end/latest value, and test cancellation and rapid cross-control edits.

### Phase 2 — Ratchet build and product quality

6. **PR: validation gate and Swift-mode alignment** (`WL5024-AUD-009`, `WL5024-AUD-010`)
   Select Swift 6 or document the split, include the demo UI target in the test plan, replace the vacuous test, and document canonical local gates. Add hosted CI only if repository policy and billing allow it.
7. **PR: bounded background diagnostic export** (`WL5024-AUD-011`)
   Move encoding/write work off the main actor and verify a maximum-size fixture.
8. **Issue/PR: localization policy and catalog ratchet** (`WL5024-AUD-012`)
   Either document English-only scope or wire package strings into a populated catalog and test extraction.

### Phase 3 — Physical qualification

9. Execute the existing protocol checklist for Bluetooth and receiver framing, reconnect, sleep/wake, low battery, active call and Dell Peripheral Manager coexistence. Attach sanitized request/response facts to the owning issues, enable one capability at a time, and re-run the accessibility and minimum-window matrices after implementation.

## Summary

The repository is compact, builds cleanly in Debug and Release, embeds the intended entitlements, and has a useful demo/probe foundation. Its main risk is not compilation: live transport state and request/response semantics are under-specified while the interface presents the full catalog as operational. The first remediation slice should contain unqualified controls and make transport events source-aware; the next should build a testable, correlated transaction layer before any additional physical write is enabled.

## Remediation disposition

Disposition date: 2026-09-01

All repository findings are accepted and remediated in source. Physical-device qualification remains a separate, explicit product gate: the live controller enables no writes until captured hardware evidence qualifies each capability. Firmware flashing and factory reset remain intentionally out of scope.

| ID | Disposition | Remediation evidence |
| --- | --- | --- |
| `WL5024-AUD-001` | Remediated, fail-closed pending hardware qualification | `TransportTransaction` gives each request an opcode/module matcher; `TransactionResponseRouter` keeps non-matches unsolicited; the qualified automatic-media path requires acknowledgement plus read-back before publishing. The production qualification set is empty, so no unverified write can execute. |
| `WL5024-AUD-002` | Remediated | Transport updates are source-specific and `TransportStateReducer` preserves an active Bluetooth connection when the USB receiver is removed. State-transition regression tests cover receiver removal and Bluetooth fallback. |
| `WL5024-AUD-003` | Remediated | Each capability carries `unavailable`, `readOnly`, `validationPending`, or `ready` state plus explicit value confidence. Live values begin unknown; UI and menu-bar writes derive their enabled state from readiness and connection state. |
| `WL5024-AUD-004` | Remediated in source | Refresh, toggle, picker, slider, text, action, and menu-bar controls have intrinsic names. The demo UI test asserts representative names and navigation; `Documentation/ACCESSIBILITY.md` defines the manual VoiceOver, keyboard, Voice Control, and environment matrix. |
| `WL5024-AUD-005` | Remediated | Typed failures offer Retry, Reconnect, Open Bluetooth Settings, Choose Another Location, or explicit dismissal for a validation gate. Technical transport detail is recorded in Diagnostics instead of shown as the primary alert message. |
| `WL5024-AUD-006` | Remediated | Refresh errors throw, `lastAttemptedAt` is distinct from `lastUpdated`, and freshness advances only after a matched decoded response. Timeout, malformed-response, and cancellation tests verify stale data is not marked fresh. |
| `WL5024-AUD-007` | Remediated | One model queue serializes every command and coalesces queued writes to the latest value per setting. Sliders keep local draft state and commit once when editing ends. Cross-setting serialization and rapid-write tests cover both policies. |
| `WL5024-AUD-008` | Remediated | Bluetooth reaches ready only after notification subscription succeeds. Setup failures share cleanup, pending-command completion, peripheral cancellation, and bounded retry behavior; an injectable lifecycle policy is unit tested. |
| `WL5024-AUD-009` | Remediated | Transport/controller injection now covers response matching, unsolicited traffic, source-aware disconnects, readiness, freshness, command serialization, read-back mismatch, cancellation, and diagnostic export. The shared test plan includes a non-vacuous demo UI target and enables coverage collection. |
| `WL5024-AUD-010` | Remediated | Target-level Swift 5 overrides were removed. App, UI-test, and package targets use Swift 6 with complete strict concurrency checking. |
| `WL5024-AUD-011` | Remediated | Diagnostics snapshot on the main actor, then use `@concurrent` encoding and atomic writing off that actor with cancellation checks. Tests exercise a 5,000-entry capture larger than 1 MB and pre-encoding cancellation. |
| `WL5024-AUD-012` | Remediated by policy | The README now declares English-only as the intentional scope for this personal app. Localization is not a release requirement; package-owned localized resources remain structured for a future expansion. |

The remaining physical checklist in `Documentation/PROTOCOL.md` is not an accepted code defect or permission to enable writes. It is the evidence gate for moving an individual capability from `validationPending` to `ready` after a real WL5024 trace is supplied.

### Post-remediation validation

| Check | Result |
| --- | --- |
| Swift package tests | Pass: 22 tests in 5 suites; 0 failures |
| Workspace package-test gate | Pass: the same 22 tests discovered and passed through the shared test plan |
| Coverage | 34.3% overall (1,105/3,218 lines), up from 18.68%; `HeadsetModel` 60.0%, `LiveHeadsetController` 70.4%, transport reducer 43.6%, matcher/router and lifecycle policy 64.3–100% |
| macOS Debug build | Pass under Swift 6 complete concurrency checking |
| macOS Release build | Pass under Swift 6 complete concurrency checking |
| Swift package Release build | Pass |
| Probe packets | Pass: documented get/disable/enable automatic-media frames unchanged |
| Demo launch | Pass: built Debug app launched with `--demo` and stopped cleanly |
| UI smoke source/build | Pass: target is in the test plan and the named navigation/accessibility test builds under Swift 6 |
| UI smoke execution on this host | Toolchain blocked before app startup: Xcode 26.6 and Xcode 27 beta both report `IDELaunchParametersSnapshot: no debugger version`; direct launch of the same built app passes. This is recorded as host test infrastructure, not converted into a product pass. |

Xcode 26.6 also emits an App Intents metadata-processor notice because these targets do not link AppIntents; no Swift compiler warnings or errors were emitted. Manual VoiceOver/keyboard and physical-headset matrices remain explicit operator checks rather than inferred passes.
