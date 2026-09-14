# Releasing WL5024 Control

Release builds target Apple silicon and macOS 26 or newer. Build and notarize on a trusted Mac with the maintainer's Developer ID signing identity and a local `notarytool` Keychain profile. Keep signing keys and notarization credentials out of Git and pull-request workflows.

## Validate and package

1. Start from the intended reviewed commit, increment `CURRENT_PROJECT_VERSION` for a new build, and run all four validation gates in [DEVELOPMENT.md](DEVELOPMENT.md#validation-gates). Keep the build logs and result bundles locally in `Artifacts/`.
2. Archive the Release configuration using XcodeBuildMCP's macOS build command with `archive` and `-archivePath` in `extraArgs`. Sign with Developer ID Application, hardened runtime, a secure timestamp, and no development `get-task-allow` entitlement.
3. Copy the archive's app into an empty staging directory with `LICENSE`. Package it as a ZIP with `ditto`, then submit it with `xcrun notarytool submit --keychain-profile PROFILE --wait`. `PROFILE` names local credentials; it is not an app-specific signing profile.
4. Require an `Accepted` response, save the notarization log, and staple the ticket to the app with `xcrun stapler staple`. Rebuild the distribution ZIP after stapling.
5. Extract that final ZIP into a fresh directory and verify the extracted app with `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute`. Launch the extracted app in demo mode. Produce a SHA-256 checksum for the final ZIP.
6. Record the source commit, app version/build, toolchain, notarization submission ID, checksums, and validation results alongside the local artifacts. Publish only the final ZIP and checksum as release assets; do not publish archives, build logs, raw UI-test screenshots, or hardware captures.

The notarization tools are Apple's command-line utilities because XcodeBuildMCP does not expose a notarization command. Screenshot attachments must capture the app window, not the desktop. README screenshots use demo data and are visually checked before committing.

Public CI builds the app without signing and runs package tests and the package Release build. The full macOS UI test gate runs locally before release; CI success does not establish physical-headset qualification.

## Repository protections

- Require pull requests to `main`, resolve review conversations before merging, and enforce protection for admins. Block force pushes and branch deletion.
- Require the `Build and package tests` check. A failed or unstarted run blocks merging until CI succeeds. No second-person approval is required for a sole-maintainer repository; CODEOWNERS identifies the maintainer for contributed changes.
- Protect `v*` release tags from updates and deletion. Create a new version instead of moving an existing release tag.
- Keep the Actions token read-only and disallow workflow approval of pull requests. The checkout action uses an immutable commit and does not retain Git credentials.
- Keep signing/notarization outside public CI and require maintainer approval for all external contributors' workflow runs.
- Enable Dependabot alerts, secret scanning, push protection, and private vulnerability reporting when available.

GitHub may not offer secret scanning, private vulnerability reporting, or public-fork approval controls while this repository is private. After the owner makes it public, enable and verify these settings:

```sh
gh api --method PATCH repos/zachspartofaday/WL5024Control \
  --input - <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}}
JSON

gh api --method PUT repos/zachspartofaday/WL5024Control/private-vulnerability-reporting

gh api --method PUT repos/zachspartofaday/WL5024Control/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors

gh api repos/zachspartofaday/WL5024Control --jq .security_and_analysis
gh api repos/zachspartofaday/WL5024Control/private-vulnerability-reporting
gh api repos/zachspartofaday/WL5024Control/actions/permissions/fork-pr-contributor-approval
```

Before changing visibility, inspect the complete Git history for credentials, personal captures, and files that are not intended for publication. A pattern scan is useful evidence, but does not prove that a repository contains no secrets. See [GitHub's security settings guidance](https://docs.github.com/en/code-security/getting-started/securing-your-repository) and [Actions permissions API](https://docs.github.com/en/rest/actions/permissions).
