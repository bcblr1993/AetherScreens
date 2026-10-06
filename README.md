# AetherScreens

A native remote desktop client for Apple silicon Mac, iPhone and iPad, using macOS Screen Sharing over your LAN or Tailscale.

## First release

- macOS 14+ on Apple silicon; iOS / iPadOS 17+.
- Mac account authentication: enter your Mac username and account password. A username selects Apple ARD authentication.
- VNC password authentication: leave Username empty and enable “VNC viewers may control screen with password” in the remote Mac’s Screen Sharing settings.
- Metal rendering with Raw, CopyRect, Zlib and ZRLE decoding.
- Native Mac keyboard / mouse input; touch and virtual trackpad input on iOS.
- Keyboard toolbar, sticky modifiers, common Mac shortcuts and insertion of local clipboard text into remote fields.
- Bonjour discovery, Tailscale device import, saved computers and Keychain passwords.
- Fit / actual-size zoom, desktop thumbnails and diagnostic logs.
- Observe Only mode keeps the live view updating while blocking remote input; switching back restores control.
- Mac connections open in independent windows. Open Sessions restores a running connection; Open in New Window starts a separate session, with numbered titles for the same computer.
- Customize the keyboard toolbar with per-computer button size, top/bottom position, visible buttons, ordering and spacers. Settings persist locally; temporary-session changes stay in memory.
- English and Simplified Chinese interfaces, with follow-system or manual selection in Settings. Language selection persists across launches.
- Quick Connect opens a temporary account or VNC session without adding a computer, password or desktop preview to storage. Select Save Computer to keep it in your library.
- The session display menu offers All Displays and individual monitors when the server reports their layout. Saved computers remember the selected server display ID; an unavailable display falls back to All Displays. Changing the endpoint or account clears that preference.

This candidate supports bidirectional text and typed Apple clipboard transfers, plus Chinese, emoji and supplementary-plane text input. Controlled transport tests and separate real Apple-server checks cover these paths; the current candidate still requires physical-device acceptance.

“Lock Remote Mac” sends the system lock shortcut. It does not hide the physical display while leaving the desktop unlocked. Display choices come from the server's layout rather than framebuffer dimensions. The user's Apple server with two monitors, physical iPhone clicks after zooming and perceived responsiveness remain under acceptance testing. See [the acceptance record](docs/first-release-acceptance.md) for current gates.

LAN VNC traffic is not encrypted by this app. For connections outside a trusted LAN, run Tailscale on both devices and use the remote Mac’s Tailscale address.

## Build and test

```sh
swift build
swift test
swift run AetherScreensApp
xcodegen generate --spec ios/project.yml --project ios
open ios/AetherScreensIOS.xcodeproj
```

Live acceptance requires a real Mac with Screen Sharing enabled. Provide `AETHERSCREENS_LIVE_HOST` and `AETHERSCREENS_LIVE_PASSWORD` in your local environment, then run:

```sh
swift test --filter TailscaleLiveHandshakeTests
```

The live suite verifies authentication, a real framebuffer, 60 seconds of continued connection and clean disconnect. Missing live configuration is reported as skipped. Never publish credentials or private desktop captures.

For Mac account acceptance also set `AETHERSCREENS_LIVE_USERNAME`. For iPhone UI acceptance, forward those variables to Xcode with the `TEST_RUNNER_` prefix and run `AetherScreensIOSUITests/testLiveRemoteSession` on an unlocked, paired iPhone. The test verifies a real frame, landscape controls, keyboard toolbar and disconnect. `testPrimaryScreensOnIPhone` covers add/edit, settings and diagnostics. The synthetic session test additionally requires a loopback RFB server on port 5999.

## Release

```sh
AETHERSCREENS_SIGNING_IDENTITY='Developer ID Application: …' \
AETHERSCREENS_NOTARY_PROFILE='your-keychain-profile' \
./scripts/package_release.sh
```

The script tests, builds arm64, signs with hardened runtime, notarizes and staples the app, then creates a DMG, ZIP and SHA-256 checksums under `build/release/`. It does not replace an installed app. Version defaults to 1.0.0 (build 1); override with `AETHERSCREENS_VERSION` and `AETHERSCREENS_BUILD_NUMBER`.

The first public downloadable package is for macOS. iOS requires a signed Xcode installation; an App Store / TestFlight release is a separate distribution step.

## Website

[Official website](https://aethernative.com/apps/aetherscreens/) · [GitHub releases](https://github.com/bcblr1993/AetherScreens/releases)

Website source is in `website_content/apps/aetherscreens/`. Run `scripts/sync_to_website.sh` to copy it to the adjacent `aethernative-site` checkout. Publishing a GitHub release triggers `.github/workflows/aethernative-sync.yml` (requires `AETHERNATIVE_SITE_TOKEN`).

Bundle IDs: `com.aethernative.aetherscreens` (Mac), `com.aethernative.aetherscreens.ios` (iOS).

MIT license; see [LICENSE](LICENSE).

Mac account authentication uses [BigInt 5.7.0](https://github.com/attaswift/BigInt/tree/v5.7.0) for server-provided DH groups. Its MIT license is bundled with the app. Authentication protects credentials; it does not encrypt the subsequent framebuffer session.
