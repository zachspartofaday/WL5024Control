# WL5024 Control

A lightweight, native macOS menu-bar and SwiftUI settings app for the Dell Premier Wireless ANC Headset WL5024. It was derived from Dell's firmware bundle and Windows WL5024 plug-in; it does not implement firmware flashing or factory reset.

## Requirements and product scope

- macOS 26 or newer on Apple silicon (`arm64`)
- Xcode 26 or newer for local development
- English interface copy; localization is intentionally outside this personal-app release scope

Build 10 incorporates direct physical-headset captures. It exposes ten explicitly experimental Bluetooth writes whose getters answered on the physical WL5024: the six composite wear-sensor behaviors, sidetone, busy light, Voice Guidance, and microphone noise cancellation. Automatic power off, Environment Detection, Smart Switch, microphone-boom action, UC profile, UC app status, and firmware 4.1.4's LE Audio feature mode are visible read-only because their getters answered but their write contracts or value tables remain unqualified. Advanced Transparency and incoming-audio noise cancellation are hidden because their getters remained silent at both discovery and refresh timeouts. A write is sent only after the user chooses a value, and success requires the exact acknowledgement followed by an exact matching read-back. The standalone probe can issue bounded getters to a directly connected `413C:A520` headset over its validated USB HID wrapper; the shipping app and separate receiver path remain discovery-only.

## Run

Open `WL5024Control.xcworkspace`, select the `WL5024Control` scheme, and run. Pass `--demo` as a launch argument to exercise every setting without a physical headset.

The app first queries already-connected BLE peripherals for the recovered Airoha control service. If macOS's audio connection does not expose that route, it falls back to an unfiltered BLE scan but accepts only the recovered service UUID or a normalized `WL5024` device name before performing read-only service validation. A CoreBluetooth connection attempt that remains pending for 12 seconds is cancelled and retried through the same gated discovery path. The app also discovers candidate headset/HR024/UD2403 USB HID interfaces. USB writes remain disabled in the shipping app; the direct-headset command-line path constructs only the recovered generic preference getter.

## Hardware capture

On a Mac with the headset paired and its USB receiver connected, open **Diagnostics**, choose **Run Read-only Discovery**, and then choose **Collect & Export Log…**. Before exporting, operate the headset buttons and wear sensor for a minute so the log includes representative HID input events. The JSON capture contains:

- USB identity, serial/location data, report sizes, and the HID report descriptor
- HID usage pages, usages, report IDs, timestamps, and observed values
- Bluetooth peripheral identity, service/characteristic properties, and negotiated write sizes
- Raw RACE requests, responses, and unsolicited notifications observed by the app
- Every read-only discovery request, response, timeout, decoded setting, and run summary
- The application capability map and its firmware/Windows-plugin evidence

Files matching `*.wl5024log.json` and the local `Artifacts` directory are ignored by Git and must not be committed. Send the exported log separately for protocol analysis.

For a Bluetooth-only capture, keep **Dell WL5024 Headset** connected in macOS Settings before launching the app and approve Bluetooth access when prompted. Once the app says Bluetooth is connected, choose **Refresh** to read the current state for every visible setting. Refresh deduplicates both successful and failed shared transactions; it sends at most thirteen distinct reads and can take at most roughly 39 seconds if each family is silent. For broader inventory, run the bounded 266-query Diagnostics discovery and leave the app open until it completes (up to roughly four minutes when most modules are silent). Change only values you intend to test, then export even if a command reports a timeout—the connection state, exact requests, GATT delivery acknowledgements, acknowledgements, read-backs, and unsolicited notifications are the evidence needed to validate the hardware path.

The package also contains a command-line inspection tool:

```sh
cd WL5024ControlPackage
swift run WL5024Probe
swift run WL5024Probe --packets
swift run WL5024Probe --live --only=smart-switch --repeat=3 --timeout-ms=2000 --listen-seconds=0
swift run WL5024Probe --live --only=firmware-v4.mic-flip-action --only=firmware-v4.uc-profile --only=firmware-v4.uc-app-status --only=firmware-v4.le-audio-feature-mode
swift run WL5024Probe --usb --module=49
```

The `--live` path connects straight to the recovered CoreBluetooth service and prints each request, GATT acknowledgement, notification, match, and timeout. It is restricted to an explicit read-only getter list. The `--usb` path matches only the direct headset's Dell `413C:A520` vendor interface and sends one generic preference getter using the physically validated `06`/`07` HID wrapper. The `firmware-v4.*` probes are packet contracts recovered from Dell's August 2026 Windows SDK; the four physically validated values also appear read-only in the normal app surface.

## Visible setting surface

- Microphone noise cancellation, plus read-only Environment Detection
- Sidetone levels 0–5/off and busy light
- Wear detection, automatic media pause/resume, removal mute, wear-to-answer, and Quick Pause/sensitivity, plus read-only power-off timeout
- Voice Guidance, plus read-only Smart Switch, microphone-boom action, UC profile/status, and LE Audio feature mode
- Menu-bar automatic-media control, device state, battery display, diagnostics, and mock/demo operation

The broader internal capability catalog still records firmware symbols and Windows vocabulary for future research, but incomplete controls—including ANC mode/level, Advanced Transparency, incoming-audio noise cancellation, EQ, device naming, touch/gesture controls, Windows-only Voice Prompts, assistant selection, and game/chat controls—do not appear in the normal UI. Experimental controls with an unknown current value show an explicit Set Value menu. Unknown wire values are never replaced with guessed defaults in live mode.

## Architecture

- `Core`: settings and device state model
- `Protocol`: RACE framing, command encoding, and the complete capability catalog
- `Transport`: CoreBluetooth plus read-only HID receiver discovery
- `Model`: live and mock controllers with a SwiftUI observation model
- `Views`: settings window, menu-bar commands, and diagnostics
- `WL5024Probe`: terminal-readable capability and packet inspection

See [PROTOCOL.md](Documentation/PROTOCOL.md) for the recovered wire format and validation checklist.

## Validation gates

Run repository validation through XcodeBuildMCP so local results use the same build/test workflow as the audit:

```sh
xcodebuildmcp macos build --workspace-path WL5024Control.xcworkspace --scheme WL5024Control
xcodebuildmcp macos test --workspace-path WL5024Control.xcworkspace --scheme WL5024Control
xcodebuildmcp swift-package test --package-path WL5024ControlPackage
xcodebuildmcp swift-package build --package-path WL5024ControlPackage --configuration release
```

The shared `WL5024Control` test plan contains both the Swift package tests and a demo-mode macOS UI smoke test with real navigation and accessible-name assertions. Swift 6 complete concurrency checking is enabled across the app, UI tests, and package. The expected clean gate is zero build warnings and zero test failures.

Manual accessibility scenarios and their expected outcomes are in [ACCESSIBILITY.md](Documentation/ACCESSIBILITY.md). Physical command qualification remains governed by [PROTOCOL.md](Documentation/PROTOCOL.md).
