# First release acceptance

Published version: 1.0.0 (build 2026100602), Apple silicon macOS 14+.
Current gate evidence is tracked in `release-1.0.0-status.md`; historical results
below do not establish acceptance of a newly packaged candidate.

## Verified on 2026-10-01

- Swift unit suite: 73 tests, zero failures; live tests skip without an explicit target.
- Real macOS Screen Sharing server: RFB 3.889 banner, VNC authentication, 3840 × 2160 framebuffer, 60 seconds connected, clean intentional disconnect.
- iOS signed device build: iPhone 12 Pro.
- iPhone simulator primary UI: add computer, Tailscale settings, diagnostic logs, edit computer. Screenshots reviewed.
- macOS Developer ID signature, Apple notarization, stapled ticket, DMG volume name and contents (app plus Applications link), arm64 executable and version metadata.
- Website source build, tests and internal link verification.

## Required before publication

- Recheck the final installed candidate after signing changes. Earlier installed GUI account sessions, native clicking, typing, dragging, zoom and wheel delivery passed; protocol tests do not replace the final installed-app check.
- Physical iPhone session UI acceptance requires an unlocked paired device. Device build success and simulator UI are recorded separately.
- Recheck final candidate signature, notarization, mounted DMG and checksums after code changes.
- Push scoped code, wait for CI, publish matching release assets, sync website, verify public download and version page.

## Distribution scope

The public download is macOS only. iOS is available as source for a signed Xcode installation; there is no App Store / TestFlight release in this version. VNC password and Mac account (Apple ARD type 30) authentication are implemented. Username selects Mac account authentication; an empty username selects VNC. Lock Remote Mac sends the system shortcut and is not a curtain privacy feature.

Keep private addresses, passwords and real desktop screenshots out of published evidence. Do not mark blocked checks as passed.

## Additional functional gate (2026-10-01)

See `functional-qa.md` for the controlled remote event fixture. Account authentication plus real click and wheel event delivery passed after fixing Apple cursor-position handling. GUI Chinese text drawer delivery passed. GUI Paste Text insertion passed with Chinese clipboard text. Lock/password input/desktop restoration passed in the installed GUI. Direct physical IME and physical iPhone acceptance are still being verified; the draft release must not be published based only on handshake success.
