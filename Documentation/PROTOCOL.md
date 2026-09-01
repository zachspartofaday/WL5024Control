# WL5024 protocol notes

## Sources

The application model was assembled from the WL5024 firmware package in the parent folder, exported symbols and ARM64 disassembly from `libcorelib.dylib`, and the feature vocabulary in Dell's Windows WL5024 plug-in. The capability catalog records the evidence used for each setting.

## Recovered Airoha RACE frame

Non-FOTA preference commands use:

```
00 05 5A LL LL OO OO [payload]
```

- `00`: transport prefix
- `05`: command type
- `5A`: RACE channel
- `LL LL`: little-endian body length, including the two-byte opcode
- `OO OO`: little-endian opcode

Automatic media control uses preference module `0x0002`:

```
get:     00 05 5A 04 00 83 2C 02 00
disable: 00 05 5A 05 00 82 2C 02 00 00
enable:  00 05 5A 05 00 82 2C 02 00 01
```

Additional statically recovered generic preference modules include auto power-off (`1`), sidetone level/state (`6`/`7`), advanced passthrough (`8`), voice prompts (`9`), and touch controls (`0`). Environment detection and Smart Switch use distinct command families represented in `WL5024Command`.

## Physical validation checklist

1. Capture the HR024/UD2403 IOHID interface inventory and input/output report IDs.
2. Confirm whether the receiver wraps RACE frames with a report-ID or fragment header.
3. Validate the exact automatic-media read and write on Bluetooth and receiver paths.
4. Record request/response pairs for every capability marked `hardwareValidationPending`.
5. Add read-back verification and rollback behavior for composite wear, EQ, ANC, gesture, and game/chat transactions.
6. Verify reconnect, sleep/wake, low-battery, active-call, and simultaneous Dell Peripheral Manager behavior.

Firmware flashing and factory reset are intentionally outside the app's scope.
