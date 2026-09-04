# WL5024 protocol notes

## Sources and evidence boundary

The application model was assembled from the WL5024 macOS firmware package, exported symbols and ARM64 disassembly from `libcorelib.dylib`, Dell DDPM 2.3.0.9 for Windows, and the Airoha Bluetooth SDK embedded in Dell Audio 1.1.2 for Android (`com.dell.dellaudio`, version code 72). The analyzed XAPK SHA-256 is `421c533723ba2c0fc2680a1d7759b029c3f62ca75a4d08d66a118b5357704ede`. Static recovery establishes packet construction and parsing. A Build 9 physical capture now validates selected getter shapes; no setter acknowledgement has yet been captured.

The macOS firmware package supplied useful command names, the RACE framing implementation, and an exact automatic-power-off getter. It did not retain enough call-site semantics to bind most setting names to complete request/acknowledgement/read-back contracts. The Windows plug-in supplied the composite wear flags. The Android SDK supplied the concrete Bluetooth contracts for sidetone, Advanced Transparency, power-off, busy light, Voice Guidance, and the two noise-cancellation switches.

## Recovered Airoha RACE frame

Non-FOTA preference commands use:

```
05 5A LL LL OO OO [payload]
```

- `05`: RACE header
- `5A`: command expecting a response (`5B` identifies a response)
- `LL LL`: little-endian body length, including the two-byte opcode
- `OO OO`: little-endian opcode

The vendor host stack can expose a leading `00` transport prefix on non-GATT paths. BLE GATT carries the raw RACE packet beginning with `05`; response decoding tolerates either form so captured wrapper bytes remain inspectable.

Direct USB inspection on 2026-09-04 identified the powered-on headset as Dell `413C:A520` with one Airoha HID interface (vendor usage page `0xFF13`). Its descriptor defines 62-byte reports: output report `0x06` and input report `0x07`, each with 61 data bytes. Disassembly of Dell's August 2026 `AirohaHidCoreLib.dll` and a matching physical request/response established the short-packet wrapper:

```
request:  06 NN 00 [RACE frame beginning 05] [zero padding to 62 bytes]
response: 07 NN 00 [RACE frame beginning 05] [zero padding to 62 bytes]
```

`NN` is the number of continuation bytes after the one-byte local transport channel `00`; for an unfragmented packet, that is the complete RACE-frame length. The read-only module-`0x0031` getter was accepted as `06 08 00 05 5A 04 00 83 2C 31 00` and returned `07 0D 00 05 5B 09 00 83 2C 00 31 00 01 02 02 00 ...`. After removing the HID wrapper and channel byte, the response exactly matches the post-update Bluetooth result. This validates direct-headset USB getter transport, not the separate HR024/UD2403 receiver path. No setter, FOTA, reset, or maintenance command was sent.

The six wear-sensor controls use one read/modify/write UInt16 bitfield:

```
get: 05 5A 02 00 21 00
set: 05 5A 04 00 20 00 FF FF
```

The response to `0x0021` is status byte `0` plus the flags as UInt16 little-endian. The setter acknowledgement for `0x0020` is exactly status byte `0`. Bits are: wear detection `0`, automatic media `1`, mute on removal `2`, Quick Pause mode `4...5` (`0` off, `1` normal, `2` sensitive), and answer on wear `6`. Each setter reads the bitfield first and preserves unrelated bits.

Dell's signed macOS updater independently constructs `GetAutoPowerOffStatusCmd` as preference module `0x0001`:

```
probe:   05 5A 04 00 83 2C 01 00
```

Build 9 returned eight bytes after the status/module fields for automatic power off:

```
01 00 08 07 00 00 08 07
```

Build 10 decodes this strictly as two Boolean/seconds UInt16 pairs and shows `30 minutes` only because both captured duration fields agree at 1,800 seconds. The meaning of the two profiles and the setter layout remain unqualified, so automatic power off is read-only. The generic preference modules used by visible settings are automatic power off (`1`) and sidetone level/state (`6`/`7`). Advanced Transparency (`8`) remained silent and is hidden. Windows-only Voice Prompts (`9`) and touch controls (`0`) remain diagnostic/catalog evidence; the capture corrected module `0`'s returned scalar to one byte. Module `16` also returned byte `1` but remains unmapped.

A Build 7 physical Bluetooth capture established the generic getter response shape as:

```
05 5B LL LL 83 2C 00 MM MM [value]
```

The first payload byte is success status `0`, followed by the little-endian module and its value bytes; there is no intervening value-length field. The capture returned sidetone module `6` as `03 00`, state module `7` as `01`, and Voice Prompts module `9` as `00`. Build 10 treats sidetone state and level as separate values, supports Android's exact `0...5` level range, and does not conflate Windows-only Voice Prompts with Android's Boolean Voice Guidance command.

The other Android Boolean getter/setter opcode pairs are Busy Light `0x0023/0x0022`, Voice Guidance `0x0025/0x0024`, incoming-audio noise cancellation `0x0044/0x0043`, and microphone noise cancellation `0x0EFF/0x0E0D`. Build 9 confirmed exact `[status=0, value=0|1]` getter responses for Busy Light, Voice Guidance, and microphone noise cancellation. Incoming-audio noise cancellation remained silent and is not writable. A setter acknowledgement must contain exactly `[status=0]`; none has yet been captured.

Environment Detection returned the exact payload `03 03 00` to getter payload `03 02`. Build 10 strictly interprets the final byte as a Boolean value and exposes the setting read-only.

A direct 2026-09-03 CoreBluetooth capture corrected the Smart Switch getter recovered from the vendor library. Module `6` is a little-endian UInt16, not a single byte:

```
get:      05 5A 04 00 01 09 06 00
response: 05 5B 06 00 01 09 06 00 00 00
```

The response is module `0x0006`, success status `0`, and Boolean value `0`. The corrected production command answered 3/3 requests, and an independently constructed two-byte frame answered 5/5. Smart Switch is therefore visible read-only; its statically recovered setter remains unqualified.

The same read-only session validated two ANC-family getters recovered from `libcorelib.dylib`:

```
ANC status get:      05 5A 04 00 01 09 05 00
ANC status response: 05 5B 09 00 01 09 05 00 00 09 00 00 04

pass-through gain get:      05 5A 04 00 01 09 07 00
pass-through gain response: 05 5B 07 00 01 09 07 00 00 F8 F8
```

Each answered 5/5 isolated requests. Dell's parser treats `F8 F8` as a signed Int16 scaled by 100, yielding `-18.00 dB`. The ANC response contains raw mode code `9`, zero gain, and an additional byte `4`; the user-facing meaning of those mode/filter values is not yet proven, so ANC remains hidden and no ANC setter is generated.

## Firmware 4 package comparison

Dell's August 2026 Windows super-updater package (ZIP SHA-256 `c39b7f563915ead0c34fa7b02bfe9b65368f352e7984db714d0679064ff599b9`) contains headset firmware 4.1.4, build 2196, dated 2026-05-22. The extracted headset image is named `fota_mp3_pegasus_v414_2196_noROFS_20260522.bin` and has SHA-256 `557bb760a7fa891c81a3cb39d3c1ff87c8ddace2c3d1ed69e369c5584e52fea2`. It also contains separate 4 MB and 8 MB dongle 0.3.9 images. The connected headset reported firmware 2.9.9, so it is older than the downloaded headset image.

Static analysis of the bundled v4 Windows SDK shows that several newly named tasks reuse already-known wire commands: AINR `0x0EFF`, downlink noise reduction `0x0044`, Busy Light `0x0023`, Voice Guidance `0x0025`, and wear-detection microphone state `0x0021`. The SDK—not the firmware updater's user interface—exports named `GetLEAFeatureMode` and `SetLEAFeatureMode` functions. The decompiled Android app/SDK contains no equivalent named LE Audio setting. Four additional getter packets were recovered without executing Dell code:

```
mic-flip action:       05 5A 02 00 29 00
UC profile:            05 5A 02 00 41 00
UC app status:         05 5A 02 00 42 00
LE Audio feature mode: 05 5A 04 00 83 2C 31 00
```

A read-only 2026-09-04 query against headset firmware 2.9.9 returned `[status=0, value=3]` for mic-flip action and `[status=0, value=0]` for both UC getters on 3/3 requests each. LE Audio feature mode produced no notification on 0/4 requests, including one 2.5-second wait. This proves that the first three command families already exist in 2.9.9; their value semantics and setter acknowledgements remain unqualified. The silent LE Audio getter is a plausible post-update capability, but the generic SDK inventory and pre-update timeouts do not prove that firmware 4.1.4 enables it on WL5024 hardware.

After the headset and dongle were updated, the standard GATT Device Information Firmware Revision characteristic (`0x2A26`) returned the NUL-padded ASCII value `0x0414`, confirming headset firmware 4.1.4 directly. macOS `system_profiler` continued to display its cached pre-update value of 2.9.9 even after a normal disconnect/reconnect. On the updated headset, LE Audio feature mode returned `[status=0, module=0x0031, data=01 02 02 00]` on 3/3 requests; the exact same getter had timed out on 0/4 requests before the update. The Windows SDK response task verifies module `0x0031`, treats the first data byte (`01`) as a fixed selector, and publishes the following byte (`02`) as the feature mode; its parser ignores the trailing `02 00`. The corresponding setter sends module `0x0031` with payload `01 <mode>`, but the accepted mode table is not present in the updater. A broader post-update read-only run returned 17/20 responses, with three legacy or unsupported probes remaining silent. An exhaustive `0...255` preference-module sweep found value-bearing replies only for modules 0, 1, 6, 7, 9, 16, and the newly responsive 49 (`0x0031`); module 10 returned only a success status with no module or value bytes. This establishes module `0x0031` as the sole newly exposed preference family detected on this WL5024. The app now reports its decoded mode read-only; it does not generate an LE Audio setter until the accepted values and their meanings are qualified.

The included installation guide requires Windows, the USB dongle, and a powered-on headset connected through that dongle. It updates the headset and dongle together, then instructs the user to remove the old Bluetooth pairing and pair the updated headset again. No firmware image or setter was sent during this analysis.

## Bounded read-only discovery

Diagnostics can send 266 serialized queries: all module identifiers `0...255` through the recovered preference getter `0x2C83`, then the wear bitfield, four typed Android status getters, environment detection, Smart Switch, and three additional firmware-v4 status getters. Each query has a 750-millisecond response timeout, so a mostly silent run can take roughly four minutes. Every request, response, timeout, raw payload, recognized decode, cancellation, and final count is retained in the version-1 diagnostic log.

The discovery plan is deliberately not an arbitrary RACE scanner. It generates no setter opcodes, unknown opcodes, firmware/FOTA operations, maintenance commands, reset, pairing, or device-name writes. Tests decode every generated frame and assert that it belongs to the recovered getter allowlist.

## Experimental write boundary

Every Bluetooth request carries an expected RACE opcode and, for preference traffic, a module identifier. Only a matching notification completes the request; other notifications are retained as unsolicited diagnostic events. Shipping setting decoders require exact status-prefixed shapes. Refresh caches successful identical read transactions, so the six wear controls use one coherent bitfield response rather than six redundant requests.

Build 10 enables ten visibly Experimental Bluetooth controls: the six composite wear controls, sidetone, Busy Light, Voice Guidance, and microphone noise cancellation. Their getters are physically validated by the Build 9 capture, but their setters remain experimental until exact device acknowledgements and matching read-backs are captured. Every enabled write uses a complete `WriteQualification`: preparation/read-modify-write transactions where needed, request encoder, opcode/module matcher, success-status validator, read-back transactions and strict decoder, and comparison rule. The controller publishes only the value read back from the headset after it exactly matches the requested value.

Automatic power off and Environment Detection have independent read definitions and cannot reach a setter. Advanced Transparency and incoming-audio noise cancellation are absent from both the visible surface and write registry. All other capabilities remain absent from the write registry. Receiver writes remain disabled even for qualified Bluetooth settings.

Boolean reads accept only exact RACE response (`5B`) shapes and values `0` or `1`. Unknown values, echoed commands, wrong opcodes/modules, and malformed/trailing payloads fail closed instead of being treated as true.

CoreBluetooth and IOHID framework delegates terminate in thin event sources. Their normalized events feed separately testable BLE and HID state machines; the coordinator chooses the active transport and correlates Bluetooth disconnects by peripheral identity. HID interfaces are retained independently by IORegistry identity (with location/usage/session fallback), and receiver removal is published only when the final candidate disappears.

Bluetooth discovery queries `retrieveConnectedPeripherals(withServices:)` first because a headset already connected for audio may no longer advertise its control service. If that query is empty, discovery scans broadly but selects only a peripheral advertising the recovered control UUID or whose punctuation-insensitive name contains `WL5024`; every other BLE device is ignored and not logged. A name match never makes the transport ready by itself—the recovered service, characteristics, and notification subscription must still validate.

CoreBluetooth can leave `connect(_:)` pending indefinitely. The adapter therefore bounds each attempt to 12 seconds, cancels only the still-selected peripheral, rejects late callbacks by peripheral identity, and retries discovery after a short delay. Diagnostics record the attempt number, timeout, advertised connectability, and eventual framework callback.

## Physical validation checklist

1. Capture the separate HR024/UD2403 receiver IOHID interface inventory and input/output report IDs; direct-headset `413C:A520` reports `06`/`07` are now confirmed.
2. Confirm whether the separate receiver uses the same report-ID, channel-byte, and fragmentation wrapper now validated on the direct headset.
3. Validate the exact automatic-media read and write on Bluetooth and receiver paths.
4. Record request/response pairs for every capability marked `hardwareValidationPending`.
5. Add read-back verification and rollback behavior for composite wear, EQ, ANC, gesture, and game/chat transactions.
6. Verify reconnect, sleep/wake, low-battery, active-call, and simultaneous Dell Peripheral Manager behavior.

For a Bluetooth-only field capture, pair the headset in macOS Settings, launch the signed app, and grant Bluetooth access. Refresh sends at most thirteen distinct reads and can take up to 39 seconds if every command family is silent. Exercise only the desired experimental controls, then export Diagnostics even if a write times out. Treat write behavior as unverified until the exported acknowledgement/read-back evidence is reviewed.

Firmware flashing and factory reset are intentionally outside the app's scope.
