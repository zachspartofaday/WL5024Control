# Contributing

Use issues for reproducible bugs and focused feature proposals, and submit changes through a pull request. For security issues, follow [SECURITY.md](SECURITY.md).

Read the [developer guide](Documentation/DEVELOPMENT.md) for setup and validation commands. Keep changes focused and include the checks you ran and any hardware or runtime limitations. Use demo mode for UI work that does not require a headset.

## Hardware changes

Protocol evidence and the acceptance criteria in [PROTOCOL.md](Documentation/PROTOCOL.md) govern live controls. Do not guess command values, enable unqualified writes, or use the normal app to experiment with firmware updates or factory reset. A successful Bluetooth delivery alone does not prove that a setting was applied.

## Before opening a pull request

- Run the relevant validation gates from the developer guide. App changes require the macOS build/test gates; package changes also require the package test and Release build gates.
- Include screenshots for visible UI changes and describe whether they show demo mode or physical hardware.
- Keep diagnostic captures and packaged builds out of Git. Redact device identifiers before sharing evidence.
- Never add signing keys, app-specific passwords, API tokens, or notarization credentials. Public CI does not need release credentials.

Contributions are provided under this repository's [MIT license](LICENSE).
