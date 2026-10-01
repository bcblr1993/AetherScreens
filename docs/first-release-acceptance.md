# First release acceptance

Candidate: 1.0.0 (build 1), Apple silicon macOS 14+.

## Verified on 2026-10-01

- Swift unit suite: 63 tests, zero failures; live tests skip without an explicit target.
- Real macOS Screen Sharing server: RFB 3.889 banner, VNC authentication, 3840 × 2160 framebuffer, 60 seconds connected, clean intentional disconnect.
- iOS signed device build: iPhone 12 Pro.
- iPhone simulator primary UI: add computer, Tailscale settings, diagnostic logs, edit computer. Screenshots reviewed.
- macOS Developer ID signature, Apple notarization, stapled ticket, DMG volume name and contents (app plus Applications link), arm64 executable and version metadata.
- Website source build, tests and internal link verification.

## Required before publication

- macOS installed-app local network permission and real rendered-session UI acceptance, keyboard controls and disconnect. The host OS denied local network access to the signed app; protocol tests from the test runner do not replace this check.
- Physical iPhone session UI acceptance requires an unlocked paired device. Device build success and simulator UI are recorded separately.
- Recheck final candidate signature, notarization, mounted DMG and checksums after code changes.
- Push scoped code, wait for CI, publish matching release assets, sync website, verify public download and version page.

## Distribution scope

The public download is macOS only. iOS is available as source for a signed Xcode installation; there is no App Store / TestFlight release in this version. VNC password authentication is implemented; macOS account authentication is not. Lock Remote Mac sends the system shortcut and is not a curtain privacy feature.

Keep private addresses, passwords and real desktop screenshots out of published evidence. Do not mark blocked checks as passed.
