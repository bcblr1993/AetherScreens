# AetherScreens 1.1.0 candidate release notes

Build: 2026100901. Not yet published; installed-candidate acceptance is pending.

## Changes

- Restore arrow cursor fallback and improve zoomed desktop edge tracking and pointer handling.
- Add standard RFB Tight decoding and optional automatic compression, with quality hints updated on the existing connection. Servers may ignore compression hints; native Apple sessions use separate display settings.
- Improve reconnect recovery, session lifecycle and stale-callback handling.
- Add SSH connection configuration and host-key verification, and improve file-transfer preparation, progress and receive validation.
- Improve session controls, saved-computer management and localized interface text.
- Include pinned dependency license notices in the macOS installation package.

## Validation and limits

Core Release regression: 759 tests, 28 explicit environment-dependent skips, zero failures. A read-only authenticated Mac mini session received 3840×2160 frames for 60 seconds. Actual TCP tests verify compression downgrade, recovery and same-socket updates.

Final installed macOS UI acceptance and iPhone 12 Pro acceptance remain pending. These checks do not establish complete Screens parity, native adaptive display support, measured frame rate or energy performance. iOS compilation does not constitute a TestFlight or App Store release.
