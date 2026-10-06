# 1.0.0 release preparation — 2026-10-06

Public distribution scope: Apple silicon macOS 14+. The user selected original
logo concept C and authorized the first public release. iOS/iPadOS distribution
remains separate. The removed Tart environment was explicitly replaced by the
authorized physical Mac mini.

## Verified evidence

- Pushed base commit `4f2e43f` passed GitHub CI run `37430653075`.
- Current core suite: 181 tests, five explicit external-environment skips,
  zero failures (`/tmp/aetherscreens-final-core-tests.log`).
- iOS arrow pointer and zoomed trackpad edge-follow compile in a signed Release
  build. Strict signature verification and installation on iPhone 16 Pro Max
  passed. The phone is locked; launch and actual gesture acceptance remain open.
- Physical Mac mini runs macOS 27.0.1 arm64. English and Chinese Quick Connect
  validation passed: two tests, zero failures/skips. Result:
  `aetherscreens-ui-qa.zztyp2/retest.xcresult` in the test account's home directory.
  The first attempt found macOS 27 grouped Forms' unlabeled editable fields;
  tests now select the host and port fields within the sheet. A duplicate QA
  registration blocked the second attempt; reuse of the original path passed.
- The expanded Mac suite passed three tests, including received native click,
  right-click, drag, keyboard press/release and wheel packets on a synthetic
  loopback desktop. Latest source result: `aetherscreens-ui-qa.zztyp2/native-final.xcresult`
  on the physical Mac. A separate application launch-confirmation dialog blocked
  the first expanded run; cancelling that pending launch allowed the tests to
  run. The signed production candidate must still pass the same suite.
- Real Mac account authentication, 3840x2160 framebuffer, a sustained 60-second
  connection and clean disconnect passed with the saved Keychain account
  (`/tmp/aetherscreens-resume-saved-live.log`). This does not prove input.
- A separate live input run passed click delivery, exact Chinese committed text,
  scrolling, Observe suppression and restored control against the controlled
  browser page. Ten click-to-decoded-marker samples had median 235 ms and max
  1396 ms (`/tmp/aetherscreens-macmini-live-input-acknowledged.log`). The test
  waits for the initial marker before further toggles to avoid coalescing two
  pending changes. It does not establish presented-frame latency, installed-app
  native input acceptance or equivalence to Screens.
- Previous build 2026100601 passed signing, notarization, stapling, Gatekeeper,
  mounted-DMG contents and asset checksums. Changes after `4f2e43f` require a
  newly packaged candidate; do not publish the previous package as current.
- Prepared website source passed 165 tests, 326 pages and 8720
  internal links. The AetherScreens updates have not yet been deployed.
- GitHub release remains a draft; no first public release is claimed.

## Remaining gates

- Installed final signed candidate native input verification and Paste Text
  acceptance. Bidirectional Mac clipboard is not included in this release.
- Physical iPhone input acceptance, including zoom, edge-follow and drag.
- Scoped commit/push, exact-commit CI, final signed/notarized package and
  matching GitHub assets.
- Public release, website deployment, download/version/checksum verification.
