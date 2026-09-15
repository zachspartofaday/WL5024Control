# Security policy

## Reporting a vulnerability

Please use GitHub's [private vulnerability reporting](https://github.com/zachspartofaday/WL5024Control/security/advisories/new) when it is available. Include the affected version, the expected and actual behavior, and minimal reproduction steps. Avoid sending signing credentials, unrelated personal information, or a complete hardware capture when a redacted excerpt is sufficient.

If private reporting is unavailable, open an issue requesting a private contact method **without disclosing the vulnerability or attaching logs**. Do not post exploit details publicly before the maintainer has had a chance to investigate.

Security fixes target the latest published release and `main`. This is a personal project; no response-time or long-term support commitment is offered.

## Diagnostic privacy

Diagnostic exports may include Bluetooth identifiers, USB serial/location information, timestamps, and raw headset protocol traffic. They are saved locally when you choose to export. Review and redact them before sharing. Never commit `*.wl5024log.json`, the `Artifacts` directory, signing keys, certificates containing private keys, or notarization credentials.

## Release integrity

Download binaries from this repository's GitHub Releases page. Release apps are signed with `Developer ID Application: Zachary Skjaveland (9T97GZT4MV)` and notarized by Apple. Release assets include a SHA-256 checksum file for checking download integrity. A checksum is useful for detecting a damaged download; the Developer ID signature identifies the publisher.

Headset writes remain experimental and require an acknowledgement and matching read-back. Firmware flashing and factory reset are outside the app's scope.
