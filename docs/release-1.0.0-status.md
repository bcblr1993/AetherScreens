# 1.0.0 release preparation — 2026-10-07

Candidate: 1.0.0 (2026100602), Apple silicon macOS 14+, original C icon.
Production source commit: `a4c8418e97279b58a75b5dd1293b58041594c235`.
Public distribution is macOS only. iOS remains a signed Xcode source install;
there is no App Store or TestFlight release.

## Verified candidate gates

- Exact source commit passed GitHub CI `37463183249`.
- Core suite: 181 tests, five explicit external-environment skips, zero failures.
- Developer ID signing, Apple notarization acceptance
  `95a51042-079e-4bb7-9a32-8dcccd1c36f0`, stapling and mounted DMG checks passed.
  Volume `AetherScreens 1.0.0` contains the app and Applications link; version,
  architecture, icon and binary match the packaged candidate.
- The authorized physical Mac mini accepted the candidate with Gatekeeper
  enabled (`Notarized Developer ID`). Final signed native UI: three tests,
  zero failures/skips, including English/Chinese Quick Connect and received
  native click, right-click, held drag, keyboard and wheel packets.
- Final signed Paste Text UI: one test, zero failures/skips; exact Chinese/Latin
  text received as Unicode key down/up pairs. Evidence is retained privately in
  `build/macmini-final-signed-2026100602/`. These controlled UI checks do not
  prove bidirectional clipboard or direct physical IME input.
- Real Mac account authentication, 3840×2160 frame, committed Chinese text,
  click, scrolling, Observe suppression and restored control passed against a
  controlled page on the Apple Screen Sharing server. Median/max of ten
  click-to-decoded-marker samples were 235/1396 ms; these are not presented-frame
  latency or proof of equivalence to Screens.
- Draft release `400587239` retains the matching candidate; downloaded draft
  assets were checked against local hashes. It is still unpublished.
- Physical iPhone 12 Pro edge-follow test passed: left/right viewport movement
  after 2× zoom and held-button dragging verified from received packets and
  same-location direct-touch coordinates. Result:
  `build/iphone12pro-physical-20261007/usb-edge2.xcresult`.
- Prepared website passed 165 tests, 332 pages and 8882 internal links on
  2026-10-07. This does not establish deployed public availability.

## Candidate checksums

- DMG: `98ff67cc194364db928b2510236adc43577e5ebf6e754d804dc84562bc659341`
- ZIP: `233927091b459ae5c6436659ea63acd709361d04a5378b6d65788fb1c3feba77`
- App executable: `d20007ea3da08305b479a763d2e90fcd6b2d1bc938824448892fa1e447bae82d`

## Remaining gates

- Complete physical iPhone controlled gestures and verify the persisted USB
  inspection runner. A full-suite English two-finger fullscreen test failed;
  retain that failure and investigate before claiming acceptance.
- Commit/push scoped QA changes and verify their CI. The existing binary was
  built from the production source commit above; any production code change
  requires a newly signed/notarized package and matching asset verification.
- Publish the matching first release, synchronize/deploy the website, and check
  public download, version and checksums. No public release is claimed yet.

The user replaced the removed Tart `macos27` environment with the physical
Mac mini. Private addresses, credentials and real desktop screenshots remain
outside published evidence. Lock Remote Mac is not curtain privacy; clipboard,
files, Shortcuts, server-side scaling and Screens edge-swipe/Hot Corner parity
remain separate subsequent work described in `next-version-plan.md`.
