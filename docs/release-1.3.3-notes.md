# AetherScreens 1.3.3 Release Notes

Build: 2026102104. Privacy and usability patch.

## Privacy
- Release builds no longer embed the builder's local source paths (which include the account name)
  in the app binary. Paths are rewritten with `-ffile-prefix-map` / `-file-prefix-map`.
- `scripts/check_release_privacy.sh` now runs before signing and fails the release when the bundle
  contains the builder's home path, account name, or any pattern from the uncommitted
  `scripts/privacy.local.patterns`.
- Test fixtures, live-test defaults, QA scripts and docs no longer contain real hosts, accounts or a
  default password. Live tests read targets and credentials only from environment variables.

## Usability
- When the remote side closes the connection before Screen Sharing answers (wrong port, proxy, VPN or
  firewall), the session shows an actionable explanation instead of raw byte counts.
- The library shows an "Add computer" hint when nearby Macs are listed but nothing is saved yet.
- The session toolbar's diagnostic-log button has a proper accessibility label.
- Removed a leftover debug `print` from the VNC read path.

## Verification
- Full suite: 839 tests, 30 skipped (live-host only), 0 failures.
- New `RFBConnectionFailureMessageTests` cover the handshake-close message and its localization.
- UI re-checked on macOS with an isolated QA build: add-computer form, connection failure screen,
  settings, diagnostics and the new library hint.
