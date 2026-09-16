# Accessibility verification

The app uses native SwiftUI controls and intrinsic labels. Run this checklist in demo mode (`--demo`) after any change to navigation, controls, alerts, or export.

## VoiceOver

1. Start VoiceOver and launch the app in demo mode.
2. Move through the single settings window and confirm Headset, This Mac, Noise Control, Calls & Microphone, Device, and Wear & Automation are announced in reading order without a sidebar.
3. Confirm the toolbar controls are announced as “Refresh” and “Diagnostics,” including their enabled state.
4. Confirm each writable toggle and picker announces the visible setting name, current value, and enabled/disabled state.
5. Confirm an unavailable, gated, saving, or hardware-validation-pending setting announces its exceptional status and cannot be changed.
6. Expand Headset Information, confirm all seven values are announced as static text rather than editable controls, then collapse it again.
7. Open a recovery alert and confirm focus enters the alert, the message explains the next step, every button is named, and focus returns to the invoking surface after dismissal.
8. Open the separate Diagnostics window and confirm “Run Read-only Discovery” is named and operable. Start it, confirm its numeric progress and current probe are announced, cancel it, and confirm the partial-result explanation appears.
9. Confirm “Collect & Export Log…” is named and operable. Cancel the save panel and confirm focus returns to that button.

Expected outcome: no unnamed interactive element, duplicate label, raw transport error in an alert, silent disabled control, or focus loss.

## Keyboard and Voice Control

1. Enable full keyboard access and traverse the window without a pointer.
2. Activate Refresh, Diagnostics, each demo control, the Headset Information disclosure, Launch at Login, each recovery action, and the Diagnostics export button.
3. Change a picker with the keyboard and confirm its selected value is announced once.
4. With Voice Control, invoke “Click Refresh,” one named settings control, and “Click Collect and Export Log.”

Expected outcome: focus remains visible, follows reading order, reaches every interactive control, and actions can be invoked by their visible names.

## Environment stress

Repeat Settings, Diagnostics, and an alert in light and dark appearance, increased contrast, reduced transparency, and the largest practical text size. Resize the window to its 640×520 minimum.

Expected outcome: content remains legible and unclipped, status is conveyed by text/symbol as well as color, controls do not overlap, and critical actions remain reachable.

## Automated scenario coverage

The UI test target covers the single two-column settings surface at regular and minimum window sizes, the collapsed read-only disclosure, writable, read-only, Experimental, unavailable, and Quick Pause-gated states, the separate Diagnostics window, the status-only menu, menu-only login launches, and persistence of the menu-bar item after the last window closes. Appearance profiles are launch-smoke coverage only and retain screenshots in the test result bundle.

Automation supplements but does not replace the VoiceOver, Full Keyboard Access, Voice Control, Finder/Dock/About/app-switcher icon, and 16/32-point icon checks above. Record those as manual observations on the hardware Mac rather than inferring them from passing UI tests.
