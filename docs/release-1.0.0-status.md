# 1.0.0 release preparation — 2026-10-06

Candidate build: 2026100601. Public distribution scope: Apple silicon macOS 14+.
The user selected original logo concept C and authorized the first public release.
iOS/iPadOS distribution remains a separate step.

## Current evidence

- Current base `5368e3c` matches `origin/master`; its CI run `36859988746` passed.
- Release core suite: 177 tests, 5 explicit live-environment skips, 0 failures.
  Local log: `/tmp/aetherscreens-first-release-core.log`.
- iOS Release device compilation with signing disabled passed. This verifies
  compilation and icon catalog processing, not installation or physical input.
  Local log: `/tmp/aetherscreens-first-release-ios-build.log`.
- Website final full build passed: 165 tests, 326 pages and 8732 valid internal
  links. These checks validate the prepared source, not a live deployment.
- Mac release packaging passed its 177-test Debug suite (5 live skips), arm64
  Release build, strict signature verification, Apple notarization (Accepted),
  stapling and Gatekeeper assessment. The mounted volume `AetherScreens 1.0.0`
  contains exactly `AetherScreens.app` and the `Applications` link; the mounted
  app reports build 2026100601 and arm64. DMG and ZIP checksums both verify.
  Local log: `/tmp/aetherscreens-first-release-package.log`.
- The existing GitHub release is a draft on old commit `2eea898`, not a public
  release of this candidate. Its assets must not be relabeled as current proof.

## Required remaining gates

- Installed-candidate acceptance of the newly signed Mac package.
- Current `macos27` VM UI acceptance. `tart list --format json` returned an empty
  list on this host; no replacement host UI test was run.
- Real Mac Screen Sharing authentication, framebuffer, input and sustained
  connection. No live test variables are configured on this host.
- Physical iPhone acceptance remains separate. The 12 Pro is unavailable and
  the 16 Pro Max is paired; neither status proves interaction acceptance.
- Scoped commit/push, current-commit CI, matching GitHub release assets, website
  deployment and public download/version verification.

The required environments have been requested from the user. Do not mark their
absence as a passed test or publish solely from compile/unit-test evidence.
