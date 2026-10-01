# Controlled remote input acceptance

This fixture checks received browser events, not only successful network sends.
Run `scripts/qa/remote_fixture.py` on the test Mac and open
`http://127.0.0.1:8766/` in its browser. The server binds only to loopback.
Use an unlocked test session. No real documents or clipboard contents are needed.

Set these environment variables in your shell without storing secrets in files:

- `AETHERSCREENS_LIVE_HOST`, `AETHERSCREENS_LIVE_PASSWORD`
- `AETHERSCREENS_LIVE_USERNAME` for Mac account authentication; omit for VNC
- `AETHERSCREENS_QA_SSH_USER` for an existing SSH key-authenticated account
- `AETHERSCREENS_QA_CLICK_X`, `AETHERSCREENS_QA_CLICK_Y`: framebuffer coordinates of Click test
- `AETHERSCREENS_QA_SCROLL_X`, `AETHERSCREENS_QA_SCROLL_Y`: optional scrollbar panel position
- `AETHERSCREENS_QA_OBSERVE=1`: verify live frames, suppressed input, held-key release and restored control

Run `swift test --filter LiveFunctionalTests`.
The test asserts new remote click and scroll events. Wrong coordinates, a locked
session, missing fixture, or failed authentication must fail rather than pass.

GUI acceptance additionally checks native keyboard shortcuts, typing, context
menus, dragging, clipboard directions, reconnect, zoom, and toolbar controls.
Do not use the renderer HUD's draw rate as proof of remote video frame rate or
end-to-end latency. Record observable events and response behavior separately.

## 2026-10-01 evidence

- Mac account authentication entered the console desktop; VNC-password sessions
  can instead enter a separate login screen on the tested Mac.
- Native GUI click, context menu, dragging, ASCII typing and Command+A passed.
- Standard RFB Unicode keysyms delivered Chinese text. The GUI text drawer
  sent `GUI 中文测试 456` exactly; direct physical IME input remains unverified.
- Real remote scrolling passed after moving the Apple server cursor before
  spacing wheel press/release events.
- Actual Size, Pan View and Fit to Window were exercised in the installed GUI.
- F8 was recorded as the correct remote key after reconnecting.
- Observe Only kept receiving live frames while remote event counts stayed unchanged
  for clicks, text, wheel and clipboard attempts. The installed Mac GUI independently
  passed click, text and wheel suppression; keyboard and remote lock controls were
  disabled. Returning to control delivered `control restored` exactly. The live
  transport test also held Shift before switching modes and received lowercase
  `observe resumed` after control resumed, confirming modifier release.
- A 60-second authenticated 3840x2160 live session remained connected.
- Ten click-specific full-background changes returned successfully: debug-build
  input-to-decoded-frame median 175 ms, maximum 225 ms. This excludes display
  presentation and does not establish physical iPhone responsiveness.
- Ten small response-marker updates in a release build returned with median
  137 ms and maximum 300 ms. Full-background release updates took median
  175 ms and maximum 274 ms. These measurements exclude display presentation.
- Legacy/extended clipboard transfer did not deliver text to this Mac session.
  The installed Paste Text button delivered `Clipboard 中文验收 789` exactly
  into the focused remote field; this is not bidirectional clipboard synchronization.
- Physical iPhone signed build passed; installation/gesture acceptance still
  require an unlocked phone. Lock/password entry/desktop restoration passed in the installed account session.
  On this Mac the session can stop accepting input after the login transition;
  reconnect restores it. A Reconnect action is available in the session menu and
  lock notice, preserving the viewport and clearing held input.
  Direct physical IME and physical iPhone input acceptance remain gates.

For repeatable response measurements, add `AETHERSCREENS_QA_LATENCY=1` to the
fixture test and run a release build with `swift test -c release --filter LiveFunctionalTests`.
The click handler changes a static background pixel; unrelated animation cannot
satisfy the response check. The test prints all ten response samples.
