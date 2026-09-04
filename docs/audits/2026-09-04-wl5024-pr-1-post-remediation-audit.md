# WL5024Control PR #1 post-remediation interface and SwiftUI re-audit

| Field | Value |
| --- | --- |
| Date | 2026-09-04 |
| Pull request | `#1` (`codex/wl5024-hardware-controls` into `main`) |
| Audited head | `2c7301056c7e63b6df64733be2f1aecafadc3582` |
| PR merge base | `ddd6410cc075ce395e1704cd3d5d81a02ba61bae` |
| Remediation delta | `bf6d0d59eb5d38b73bf6f6f9e80866df0db61a82...2c7301056c7e63b6df64733be2f1aecafadc3582` |

Historical verdict for audited head `2c73010`: **Do not merge.** That remediation left production setting controls unnamed to assistive technology, hid required setting/status context behind optional hints, and made several automated scenarios observe a test-only accessibility tree. The same head also retained an unqualified first-write failure path that could leave a previously confirmed value visible after the hardware may have accepted the command.

Change scope: report only. No application, protocol, test, project, or asset implementation was changed. The audit reviewed the ten-file remediation delta first, then expanded through its consumers and the full PR diff. The fresh clone contained 90 tracked files, including 56 Swift files and 7 Swift test files; PR #1 changes 67 tracked paths relative to `main`.

## Remediation disposition

All three findings were resolved on PR #1 at `df468c9c43c691b0c5a8a07fc05e4f3e90006cc5`. No automated blocker from this audit remains at that head.

| Finding | Disposition | Resolution evidence |
| --- | --- | --- |
| `WL5024-POST-AUD-001` | Resolved | Production setting explanations and readiness/gating status remain in the accessibility tree; native checkbox and pop-up controls expose the visible setting name without `--ui-layout-probes`; unknown rows expose both the setting name and “Not read from headset.” Production-mode UI assertions cover Ready, read-only, and Experimental/unknown states, and direct macOS AX inspection confirmed the checkbox label and native role. |
| `WL5024-POST-AUD-002` | Resolved | The transport now distinguishes write transactions and preserves typed post-dispatch failure/cancellation state. The controller reads back ambiguous failures at the first or later write step and invalidates the affected setting or wear-detection composite when current state cannot be established. Regression fixtures start from confirmed values and cover pre-dispatch preservation, dispatched failure recovery, cancellation invalidation, and unreadable composite invalidation. |
| `WL5024-POST-AUD-003` | Resolved | Both Diagnostics export focus scenarios now synchronize on an existing, enabled export button before clicking. The two focus tests passed three iterations each (six invocations) after the repair. |

Post-remediation validation at `df468c9`: canonical macOS build passed; canonical workspace test passed 96/96 with zero skips; canonical Swift package test passed; canonical Swift package Release build passed; `git diff --check` passed. Manual VoiceOver/Voice Control walkthroughs and physical forced first-response loss remain field-verification items rather than unresolved source findings.

## Finding registry

Findings use one `HIGH` / `MEDIUM` / `LOW` ladder and are ordered by user impact. `Regression` and `Pre-existing` describe status relative to the latest remediation delta; both findings are introduced by PR #1 relative to `main`.

| ID | Severity | Domain | Status | Confidence | Summary |
| --- | --- | --- | --- | --- | --- |
| `WL5024-POST-AUD-001` | HIGH | Accessibility / SwiftUI | Pre-existing | Confirmed in source and the production AX tree | Settings rows remove the visible title, explanation, readiness, and gating copy from production accessibility, while `labelsHidden()` leaves toggles and pickers without names. Unknown-value rows become repeated, indistinguishable “Not read from headset” elements; the new test-only AX mutation masks much of the failure. |
| `WL5024-POST-AUD-002` | HIGH | Protocol state / recovery | Pre-existing | Confirmed mechanism; physical mutation outcome inferred | A failure or cancellation after dispatching the first write step bypasses read-back and invalidation, so the UI can retain a stale device-confirmed value even though the setting may have changed. |
| `WL5024-POST-AUD-003` | MEDIUM | Validation / focus UI test | Pre-existing | Confirmed; reproduced as nondeterministic | The Diagnostics result-alert focus test clicks its export button without waiting for it to exist. One canonical run failed at 90/91, while the unchanged test passed the next full run and three isolated runs. |

## Detailed findings

### `WL5024-POST-AUD-001` — production settings semantics are unnamed or incomplete

Evidence:

- `WL5024ControlPackage/Sources/WL5024ControlFeature/Views/HeadsetSettingsView.swift:254-322` makes the title, explanation, readiness text, and Quick Pause gating explanation accessible only when the private `--ui-layout-probes` argument is present. Production puts the explanation and state into `.accessibilityHint` on the trailing control group.
- The controls at `HeadsetSettingsView.swift:331-350` use `Toggle(key.title, ...)` and `Picker(key.title, ...)`, followed by `.labelsHidden()`, without restoring an explicit accessibility label.
- A production-mode Accessibility API inspection of the Wear & Automation page found five `AXCheckBox` elements and two `AXPopUpButton` elements with no `AXTitle`, `AXDescription`, or accessible name. Their help strings contained the explanation/readiness copy, but help/hints are optional and may be disabled.
- In the disconnected production state, the same page exposed seven separate static text elements named only “Not read from headset”; the setting titles were absent from the accessibility tree. One inspected element had the help string for Automatic Media, but its announced name did not identify that setting.
- This violates the repository's own contract in `Documentation/ACCESSIBILITY.md:10-16`: every control must announce its visible setting name, value, and enabled state; awaiting-validation settings must announce their explanatory status; no interactive element may be unnamed.
- `WL5024ControlUITests.swift:63-70` is the only production-mode single-identity assertion, and it checks only one ready checkbox. The read-only and Experimental assertions at lines 73-131 launch with `--ui-layout-probes`, changing the accessibility tree they purport to validate. Layout probes therefore mask the production semantic regression.

Impact: VoiceOver users cannot identify settings controls reliably, and Voice Control cannot target them by the visible setting name. Disconnected/unavailable rows are indistinguishable without optional hints. The failure repeats across every settings destination and contradicts a documented acceptance criterion, so it is `HIGH`.

Current shape:

```swift
Text(key.title)
    .accessibilityHidden(!exposesUITestMetadata)

Toggle(key.title, isOn: binding)
    .labelsHidden()

Group { /* value, experimental action, or unknown text */ }
    .accessibilityHint(Text(accessibilityHintText))
```

Target shape:

```swift
Toggle(key.title, isOn: binding)
    .labelsHidden()
    .accessibilityLabel(Text(key.title))

Text("Not read from headset")
    .accessibilityLabel(Text(key.title))
    .accessibilityValue("Not read from headset")
```

Apply the same explicit naming rule to pickers and other interactive controls. Keep readiness/gating information in a semantic channel that does not depend solely on optional hints, while preserving each control's native value and enabled state. Remove the launch-argument-dependent accessibility mutation: layout tests may expose dedicated geometry probes, but the app-under-test must keep production semantics. Add production-mode assertions for Ready, read-only, Experimental, and disconnected/unavailable rows, then complete the documented VoiceOver and Voice Control passes.

### `WL5024-POST-AUD-002` — the first write can fail after dispatch without invalidating state

Evidence:

- `WL5024ControlPackage/Sources/WL5024ControlFeature/Model/LiveHeadsetController.swift:186-207` performs recovery only when `index > 0`. Any first-step error is rethrown directly.
- `WL5024ControlPackage/Sources/WL5024ControlFeature/Transport/BLETransport.swift:49-70` calls `source.write` before awaiting a response. A subsequent response timeout reports whether the GATT write was acknowledged only to diagnostics; that delivery information is not returned to the controller.
- Cancellation also finishes the pending continuation after the request may have been written (`BLETransport.swift:78-81`) and follows the same no-invalidation first-step path in the controller.
- `TransportStateTests.swift:637-649` codifies that a first-step timeout performs no read-back. The fixture begins with no value, so it cannot detect the unsafe case: a previously device-confirmed value remains visible after an ambiguous first-write outcome.
- Explicit acknowledgement rejection is different: the hardware response proves the write was rejected and can safely preserve the old value. The transport currently does not give the controller enough typed outcome information to distinguish provable pre-dispatch failure from timeout/disconnect/cancellation after dispatch.

Impact: after a timeout or cancellation, the settings window and menu can continue presenting the old value as device-confirmed even though the headset may have applied the new value. A retry can then issue a second command from a false state. This crosses the repository's fail-closed hardware-truth boundary and is `HIGH` despite requiring hardware timing to reproduce.

Current shape:

```swift
if index > 0 {
    throw await partialWriteError(...)
}
throw error
```

Target shape: have the transport return a typed failure outcome that records whether the request was dispatched and, when known, whether GATT acknowledged it. For any ambiguous post-dispatch failure at any write index, attempt the qualified read-back when the connection permits; if it cannot establish the current value, invalidate the affected setting/composite before surfacing the recovery error. Preserve the prior value only for a provable pre-dispatch failure or explicit negative acknowledgement. Add fixtures that start from a confirmed old value and cover first-step timeout, disconnect, and cancellation for both single-step and composite settings.

### `WL5024-POST-AUD-003` — the result-alert focus test races Diagnostics rendering

Evidence:

- `WL5024ControlUITests.swift:163-167` launches the app, navigates to Diagnostics, queries `Collect & Export Log…`, and immediately calls `click()` without first waiting for that element to exist and become actionable.
- The first exact-head canonical workspace run failed at line 167 because the button query had no match. The result bundle recorded 90 passes, 1 failure, and 0 skips.
- Without changing source or test products, the same test then passed three isolated runs, each in about 22 seconds. A second full 91-test workspace run also passed.
- The product's result-alert dismissal and first-responder restoration completed in all four reruns. The established defect is therefore the test's synchronization boundary, not a deterministic focus-engine failure.

Impact: the README's canonical gate can alternate red and green on the same commit, and a timing failure before export means the test sometimes proves nothing about the focus behavior it owns. This is `MEDIUM`: it does not establish a user-facing focus defect, but it makes a required merge signal unreliable.

Target shape: wait for the export button to exist and be enabled/hittable before clicking, with an assertion that fails at that boundary. Keep the existing alert-entry, dismissal, and first-responder-return assertions. Repeat the repaired test in suite order enough times to show the gate no longer depends on Diagnostics render timing.

## Summary

Two `HIGH` findings block the current head: the settings surface fails its production accessibility contract, and the first-write recovery path can preserve unverified hardware state. One `MEDIUM` finding makes the focus-restoration UI test nondeterministic. The visual remediation otherwise holds up: shared row geometry, regular/minimum layouts, native typography and colors, and appearance variants did not produce another actionable interface or SwiftUI finding. Manual VoiceOver, Full Keyboard Access, Voice Control, largest-text, and physical first-write verification remain undone; the confirmed AX failure means those omissions do not soften the merge verdict.

## Interface coverage

### Change scope

| Axis | Audited scope |
| --- | --- |
| Target | PR #1 current head, with the ten-file `bf6d0d5...2c73010` remediation delta as the primary review surface |
| Expanded consumers | Settings/model/transport call paths, shared layout, menu bar, Diagnostics, launch fixtures, package tests, UI tests, README, protocol and accessibility authority |
| Visible surfaces | Menu bar; Overview; Noise Control; Calls & Microphone; Wear & Automation; Device; Diagnostics; recovery/export alerts and save workflow |
| Excluded | Physical-device command execution, notarization, Finder/Dock icon field checks, and code/assets not reachable from PR #1 |

### Surface and state matrix

| Surface | Ready | Read-only | Experimental / unknown | Disconnected / recovery | Pending / error |
| --- | --- | --- | --- | --- | --- |
| Settings shell and six destinations | Source, UI automation, retained renders | Source and production AX inspection | Source and UI fixture | Source and production AX inspection | Source and UI fixture |
| Menu bar | Source and UI fixture | Source and UI fixture | N/A | Source | Source |
| Diagnostics | Source, UI automation, retained renders | N/A | N/A | Source | Discovery/export automation |
| Alerts and save flow | N/A | N/A | N/A | Source | UI automation for dismissal and focus return |

### Environment and interaction evidence

| Check | Result |
| --- | --- |
| Regular and minimum window layouts | Reviewed retained captures for all six destinations; no new clipping, overlap, or alignment finding |
| Light and dark appearance | Reviewed retained launch-smoke captures; no new legibility finding |
| Increased contrast and reduced transparency | Reviewed retained launch-smoke captures; no new legibility finding |
| Production accessibility tree | Failed: unnamed controls and indistinguishable unknown rows reproduced through macOS Accessibility APIs |
| Keyboard focus restoration | Product behavior passed four reruns; its result-alert UI test is timing-sensitive as described in `WL5024-POST-AUD-003` |
| VoiceOver, Full Keyboard Access, Voice Control | Not completed manually; production AX failure already blocks acceptance |
| Largest practical text size | Not completed manually; minimum-width captures do not substitute for Dynamic Type verification |
| Right-to-left localization | Not in current product scope; README documents an intentional English-only release |

## Validation

Toolchain: XcodeBuildMCP 2.7.0, Xcode 26.6 (17F113), Apple Swift 6.3.3.

| Check | Result |
| --- | --- |
| Fresh-clone inventory and clean-tree check | Pass before report creation: 90 tracked files, 56 Swift files, 7 Swift test files; no pre-existing local changes |
| Diff hygiene | Pass: `git diff --check` clean |
| Canonical macOS Debug build | Pass in 11.5 seconds |
| Canonical workspace test | Unstable: first run 90/91 with `testDiagnosticResultAlertDismissalRestoresFocus` failing before the export-button click; unchanged second run 91/91 |
| Focused result-alert focus test | Pass 3/3 isolated reruns; confirms the canonical failure is nondeterministic and does not establish broken product focus restoration |
| Canonical Swift package test | Pass: 82 tests in 6 suites |
| Canonical Swift package Release build | Pass in 9.6 seconds |
| Production AX inspection | Fail as described in `WL5024-POST-AUD-001` |
| Physical first-write ambiguity | Not executed; mechanism confirmed in source, physical mutation outcome remains inferred |

## SwiftUI and interface findings not carried forward

- The remediated settings layout uses one shared adaptive row layout and stable control metrics. Regular/minimum captures did not reproduce the prior overlap or trailing-edge inconsistency.
- Text concatenation in the Experimental menu was replaced with localized interpolation; current source no longer uses the deprecated `Text + Text` form.
- The settings bindings capture the current rendered value, but controls are disabled while commands are pending and state updates rerender the row. No stale-binding failure was established.
- `ForEach(Array(settings.enumerated()))` creates a small transient array, but the setting lists are bounded and no measurable impact was found; this is not a performance finding.
- Diagnostics discovery progress invalidates a larger view subtree, but the bounded row count and retained UI runs showed no concrete responsiveness failure.
- Native buttons and sidebar rows remain keyboard-focusable. Focus restoration around export cancellation/result dismissal is explicitly implemented, and four reruns passed; no product focus-engine defect was found beyond the timing-sensitive test in `WL5024-POST-AUD-003`.
- System semantic colors, materials, and native controls remain coherent across the reviewed appearance captures. No unsupported contrast ratio or color-only-state claim is made.

## Remediation roadmap

1. **Restore production semantics and make the gate representative.** Explicitly name every settings control/unknown value, expose required readiness context outside optional hints, remove accessibility-tree mutation from `--ui-layout-probes`, and add production-mode AX assertions for all readiness families.
2. **Close the first-write ambiguity.** Preserve transport delivery state, read back or invalidate after every ambiguous post-dispatch failure, and add stale-prior-value recovery fixtures.
3. **Stabilize the focus test.** Synchronize on an actionable Diagnostics export button before clicking and prove the repaired test in repeated suite-order runs.
4. **Field-verify the repaired invariants.** Run the documented VoiceOver, Full Keyboard Access, and Voice Control checklist, then use a physical headset to force or simulate a lost first response and confirm that the UI never retains an unverified value.

## Merge criteria

- `WL5024-POST-AUD-001`, `WL5024-POST-AUD-002`, and `WL5024-POST-AUD-003` are fixed with regression tests.
- All four canonical README gates pass at the resulting exact head with zero warnings and zero failures.
- Production-mode accessibility inspection shows a unique setting name, current/unknown value, enabled state, and required readiness context for Ready, read-only, Experimental, and disconnected states.
- Ambiguous post-dispatch first-write failures can no longer leave a stale device-confirmed value visible.
