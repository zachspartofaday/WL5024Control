# Accessibility verification

The app uses native SwiftUI controls and intrinsic labels. Run this checklist in demo mode (`--demo`) after any change to navigation, controls, alerts, or export.

## VoiceOver

1. Start VoiceOver and launch the app in demo mode.
2. Move through the sidebar and confirm each destination is announced once: Overview, Noise Control, Calls & Microphone, Wear & Automation, Sound, Device & Gestures, and Diagnostics.
3. On Overview, confirm the icon-only refresh control is announced as “Refresh,” including its enabled state.
4. On every settings page, confirm toggles, pickers, sliders, the device-name field, and action buttons announce the visible setting name, current value, and enabled/disabled state.
5. Confirm a setting awaiting hardware validation announces its explanatory status and cannot be changed.
6. Open a recovery alert and confirm focus enters the alert, the message explains the next step, every button is named, and focus returns to the invoking surface after dismissal.
7. Open Diagnostics and confirm “Collect & Export Log…” is named and operable. Cancel the save panel and confirm focus returns to that button.

Expected outcome: no unnamed interactive element, duplicate label, raw transport error in an alert, silent disabled control, or focus loss.

## Keyboard and Voice Control

1. Enable full keyboard access and traverse the window without a pointer.
2. Activate every sidebar destination, Refresh, each Ready demo control, recovery action, and the Diagnostics export button.
3. Drag a slider with the keyboard and confirm the displayed value changes locally, then commits once when editing ends.
4. With Voice Control, invoke “Click Refresh,” one named settings control, and “Click Collect and Export Log.”

Expected outcome: focus remains visible, follows reading order, reaches every interactive control, and actions can be invoked by their visible names.

## Environment stress

Repeat the Overview, one settings page, Diagnostics, and an alert in light and dark appearance, increased contrast, reduced transparency, and the largest practical text size. Resize the window to its 720×500 minimum.

Expected outcome: content remains legible and unclipped, status is conveyed by text/symbol as well as color, controls do not overlap, and critical actions remain reachable.
