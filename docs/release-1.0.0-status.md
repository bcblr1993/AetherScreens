# 1.0.0 first public release — 2026-10-07

Release: 1.0.0 (2026100602), Apple silicon macOS 14+, original C icon.
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
- Public release `400587239`, tag `v1.0.0`, targets the exact production source
  commit above. Anonymous public downloads of both DMG and ZIP pass the
  published SHA-256 checksum file. Public URL:
  https://github.com/bcblr1993/AetherScreens/releases/tag/v1.0.0
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

## Physical acceptance and publication status

- Canonical USB runner passed all thirteen physical iPhone 12 Pro cases, with
  zero failures/skips/runtime warnings and exact test discovery/membership.
  Result: `build/iphone12pro-physical-20261007/canonical-suite1/result.xcresult`.
  It covers bilingual gestures, fullscreen/keyboard transitions, recovery,
  display selection, retained sessions, viewport navigation and edge-follow.
- The first twelve-case run had one English fullscreen synthetic-gesture
  failure. The canonical suite did not reproduce it; retain the historical
  failure and do not claim its cause was identified.
- Test/documentation commit `4b707da` passed CI `37588947942`. Production source,
  package inputs and app icons are unchanged from `a4c8418`; the v1.0.0 tag
  points to the commit actually used for the signed/notarized package.
- Website source includes matching release metadata and the approved C icon.
  Final build: 165 tests, 336 pages, 8990 internal links. Website commit
  `8ccc6e7` passed Cloudflare Pages deployment. Both language home/version pages
  expose 1.0.0, build 2026100602, the matching public DMG and SHA-256. The live
  optimized icon matches the built C asset; English release notes are intact.
  Mac is available and iOS remains in development. Browser screenshots and
  independent public verification are retained in
  `build/release-public-v1-20261007/verified.json` and `website-zh.jpg` /
  `website-en.jpg`. No first-release publication gate remains open.

The user replaced the removed Tart `macos27` environment with the physical
Mac mini. Private addresses, credentials and real desktop screenshots remain
outside published evidence. Lock Remote Mac is not curtain privacy; clipboard,
files, Shortcuts, server-side scaling and Screens edge-swipe/Hot Corner parity
remain separate subsequent work described in `next-version-plan.md`.
