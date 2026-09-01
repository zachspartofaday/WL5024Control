# WL5024 Control

A lightweight, native macOS menu-bar and SwiftUI settings app for the Dell Premier Wireless ANC Headset WL5024. It was derived from Dell's firmware bundle and Windows WL5024 plug-in; it does not implement firmware flashing or factory reset.

## Requirements and product scope

- macOS 26 or newer on Apple silicon (`arm64`)
- Xcode 26 or newer for local development
- English interface copy; localization is intentionally outside this personal-app release scope

Live Bluetooth writes are fail-closed. A capability is writable only after its request, correlated acknowledgement, and read-back sequence has been physically qualified. Until then the app can discover the headset, read the known automatic-media value, and collect diagnostics, while displaying all unqualified settings as read-only or awaiting validation. USB receiver access is discovery-only.

## Run

Open `WL5024Control.xcworkspace`, select the `WL5024Control` scheme, and run. Pass `--demo` as a launch argument to exercise every setting without a physical headset.

The app scans for the Airoha Bluetooth control service and discovers candidate HR024/UD2403 USB HID receiver interfaces. USB writes remain gated until their report IDs and framing can be captured from hardware.

## Hardware capture

On a Mac with the headset paired and its USB receiver connected, open **Diagnostics** and choose **Collect & Export Log…**. Before exporting, operate the headset buttons and wear sensor for a minute so the log includes representative HID input events. The JSON capture contains:

- USB identity, serial/location data, report sizes, and the HID report descriptor
- HID usage pages, usages, report IDs, timestamps, and observed values
- Bluetooth peripheral identity, service/characteristic properties, and negotiated write sizes
- Raw RACE requests, responses, and unsolicited notifications observed by the app
- The application capability map and its firmware/Windows-plugin evidence

Files matching `*.wl5024log.json` and the local `Artifacts` directory are ignored by Git and must not be committed. Send the exported log separately for protocol analysis.

The package also contains a command-line inspection tool:

```sh
cd WL5024ControlPackage
swift run WL5024Probe
swift run WL5024Probe --packets
```

## Implemented surface

- Listening modes, ANC, adaptive ANC, transparency, environment detection, outgoing and incoming noise reduction
- Sidetone and busy light
- Wear detection, automatic media pause/resume, removal mute, wear-to-answer, Quick Pause, and power-off timeout
- EQ presets and custom bands, adaptive EQ, maximum volume, and game/chat controls
- Voice guidance/prompts, device naming, touch/gesture controls, Smart Switch, assistant selection, and Find My Headset
- Menu-bar automatic-media toggle, device state, battery display, diagnostics, and mock/demo operation

The automatic-media RACE packets and generic preference envelope are statically recovered. Other settings have typed mappings to their firmware or Windows plug-in command families. Those marked “Ready for device validation” in Diagnostics need physical request/response traces before live writes are enabled; this prevents guessed vendor packets from being sent to the headset. Unknown values are never replaced with guessed defaults in live mode.

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
