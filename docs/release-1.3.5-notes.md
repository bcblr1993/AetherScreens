# AetherScreens 1.3.5 Release Notes

Build: 2026102202. macOS session-window usability update.

## Interface
- **The session top bar no longer covers the remote screen.** On macOS the floating bar (disconnect,
  computer name, FPS/latency, logs, session options) hides about 1.5 seconds after the first remote
  frame arrives, so the remote desktop's own top edge — browser tabs, address bars, menu bars — can
  be clicked again.
- **Rest the pointer at the top edge to bring it back.** Holding the pointer within 6 pt of the top
  of the session (or pushing it into the title bar) for about 0.3 seconds reveals the bar. Passing
  through briefly does not, so clicks near the top still reach the remote computer. The bar stays
  while the pointer is over it and hides 1.5 seconds after it leaves.
- The bar stays visible while connecting, reconnecting or after a failure, in Observe mode, while a
  session sheet (logs, file transfer, display quality, keyboard customization), password or SSH
  prompt is open, and whenever VoiceOver is running.
- Edge detection uses a tracking area only and never takes clicks; ordinary pointer motion does not
  re-render the session view. iPhone and iPad behaviour is unchanged.

## Verification
- Full suite: 862 tests, 30 skipped (live-host only), 0 failures, including the new
  `SessionTopBarAutoHideTests`.
- iOS Simulator build succeeds.
- Not yet checked in a live session window: the top-edge reveal was covered by state tests only.
