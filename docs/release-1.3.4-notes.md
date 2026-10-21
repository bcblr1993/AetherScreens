# AetherScreens 1.3.4 Release Notes

Build: 2026102201. Reliability and interface-consistency patch.

## Fixes
- **Deleting a computer asks for confirmation.** Deletion also removes its saved password and SSH
  credentials and, with iCloud Sync on, removes it from other devices, so it is no longer one click.
- **Showing the keyboard toolbar no longer resizes or moves the session window.** Session windows
  are constrained only by their minimum size; the toolbar scrolls when it does not fit.
- **Windows shortcuts with punctuation work.** While Ctrl, Alt or Win is held, punctuation is sent as
  its key position, so Ctrl+/, Ctrl+-, Ctrl+= and similar shortcuts reach Windows. Ordinary typing
  still sends characters, so mixed keyboard layouts keep producing the right text.
- **Windows receives every typed character.** Characters outside Latin-1 (for example €, Chinese
  and emoji) were dropped; they are now delivered. Caps Lock, keypad, Menu and Print Screen keys
  are mapped, and unknown function keys are no longer sent as stray characters.

## Interface
- Section explanations in forms and Settings are left-aligned with the rows above them.
- The sidebar adds a Windows PCs category, shows every count with the same native badge and
  shortens "Nearby (Bonjour)" to "Nearby".
- The library header count follows the selected category.
- Saved computer addresses read `host:port` (IPv6 hosts in brackets).
- The session options button matches the neighbouring toolbar icons.
- Horizontal rows (nearby Macs, keyboard toolbar) show a scroller on macOS so overflow is visible.

## Verification
- Full suite: 849 tests, 30 skipped (live-host only), 0 failures.
- New `RDPKeyTranslatorTests` and `LibraryPresentationTests`.
- Interface changes checked on macOS with an isolated QA build and the loopback RFB fixture,
  including delete confirmation, keyboard toolbar window size and category filtering.
- iOS: the core library builds for the iOS 17 simulator; the iOS UI was not re-checked.
- RDP key handling is covered by unit tests; not yet checked against a physical Windows host.
