# Accessibility verification

The app uses native SwiftUI controls and intrinsic labels. Run this checklist in demo mode (`--demo`) after any change to navigation, controls, alerts, or export.

## VoiceOver

1. Start VoiceOver and launch the app in demo mode.
2. Move through the sidebar and confirm each visible destination is announced once: Overview, Noise Control, Calls & Microphone, Wear & Automation, Device, and Diagnostics.
3. On Overview, confirm the icon-only refresh control is announced as “Refresh,” including its enabled state.
4. On every settings page, confirm toggles and pickers announce the visible setting name, current value, and enabled/disabled state.
5. Confirm a setting awaiting hardware validation announces its explanatory status and cannot be changed.
6. Open a recovery alert and confirm focus enters the alert, the message explains the next step, every button is named, and focus returns to the invoking surface after dismissal.
7. Open Diagnostics and confirm “Run Read-only Discovery” is named and operable. Start it, confirm its numeric progress and current probe are announced, cancel it, and confirm the partial-result explanation appears.
8. Confirm “Collect & Export Log…” is named and operable. Cancel the save panel and confirm focus returns to that button.

Expected outcome: no unnamed interactive element, duplicate label, raw transport error in an alert, silent disabled control, or focus loss.

## Keyboard and Voice Control

1. Enable full keyboard access and traverse the window without a pointer.
2. Activate every sidebar destination, Refresh, each Ready demo control, recovery action, and the Diagnostics export button.
3. Change a picker with the keyboard and confirm its selected value is announced once.
4. With Voice Control, invoke “Click Refresh,” one named settings control, and “Click Collect and Export Log.”

Expected outcome: focus remains visible, follows reading order, reaches every interactive control, and actions can be invoked by their visible names.

## Environment stress

Repeat the Overview, one settings page, Diagnostics, and an alert in light and dark appearance, increased contrast, reduced transparency, and the largest practical text size. Resize the window to its 720×500 minimum.

Expected outcome: content remains legible and unclipped, status is conveyed by text/symbol as well as color, controls do not overlap, and critical actions remain reachable.

## Automated scenario coverage

The UI test target covers all six visible destinations at regular and minimum window sizes, Ready, read-only, and Experimental states, light and dark appearance, increased contrast, and reduced transparency. It asserts native checkbox and pop-up-button roles, explicit experimental Set Value menus, adaptive row separation and common trailing control edges, the menu-bar read-only explanation, selectable diagnostic values, the discovery action and completion summary, visible export progress, save-panel cancellation, result dismissal, and real first-responder return to the export button. Default and minimum screenshots are retained in the test result bundle.

Automation supplements but does not replace the VoiceOver, Full Keyboard Access, Voice Control, Finder/Dock/About/app-switcher icon, and 16/32-point icon checks above. Record those as manual observations on the hardware Mac rather than inferring them from passing UI tests.
