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
- Installed Quick Connect authenticated to the Mac account and delivered
  `temporary connection passed` exactly. Disconnect left the existing three
  saved computers unchanged. Unit coverage verifies no temporary credentials,
  device records or thumbnails are persisted. Simulator coverage verifies port
  validation, account fields, optional saving and the failure/disconnect flow.
  The installed thumbnail check exposed a second save path on incoming frames.
  Both periodic and disconnect saves now exclude temporary sessions. The strengthened
  regression triggers 61 frame callbacks with a synthetic framebuffer. The corrected installed candidate
  delivered `frame cache fixed passed`; thumbnail files stayed unchanged during
  the live session and after disconnect, and the library retained its three computers.
- One deliberately rejected account password was corrected in a temporary
  session; the same session view model reconnected and received a real desktop.
  Password submission now updates the current client and restarts a failed
  connection instead of updating only the saved credential.
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

## Chinese / English localization acceptance (2026-10-01)

- Core suite: 87 tests, four external-environment skips, zero failures. Tests
  load both bundled catalogs, compare key sets and format argument types, check
  language fallback/persistence, and preserve original server error details.
- iPhone 17 simulator: primary workflow and Chinese-to-English settings switch
  passed. The same open sheet updated, Quick Connect changed language, and
  English persisted after terminating and relaunching the app. Evidence:
  `build/ios-localization.xcresult` and exported screenshots.
- Reviewed Chinese dashboard/Quick Connect and English settings screenshots.
  The existing compact iPhone navigation title truncates beside four actions;
  retain this as a UI issue to resolve before final acceptance.
- Installed standalone Mac candidate loads the package resource bundle and
  follows the Chinese system preference. Switching to English updates the open
  settings sheet and main dashboard without rebuilding session state; English
  also persisted after quitting and relaunching the Mac app.
- App-owned labels, prompts, status/errors and local-network permission text
  have English and Simplified Chinese resources. OS-owned menus/dialogs follow
  the system's application language; remote names and server diagnostics remain
  original data. Physical iPhone localization acceptance remains pending unlock.

### Localization resource build compatibility

CI for `22f5fe6` failed Chinese resource loading despite local Swift Build
acceptance. Reproduced with the native SwiftPM build: it emits `zh-hans.lproj`
while Xcode/Swift Build emits `zh-Hans.lproj`; Foundation's localized directory
lookup did not resolve the former. Resolve actual bundled resource directories
case-insensitively before loading the selected catalog. Both full suites now
pass: `swift test` and `swift test --build-system native --skip-update
--scratch-path build/native-localization` (87 tests, four external skips).
Evidence: `/tmp/aetherscreens-native-localization-before-fix.log`,
`/tmp/aetherscreens-native-localization-fixed.log`, and
`/tmp/aetherscreens-localization-build-fixed.log`. Remote CI must pass again.
