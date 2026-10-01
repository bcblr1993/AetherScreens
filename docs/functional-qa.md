# Controlled remote input acceptance

## Native iOS gesture delivery (2026-10-01)

The English and Chinese simulator flows both passed (two tests, no skips,
failures or runtime warnings): `build/ios-native-gesture-bilingual-final.xcresult`.
The application connected to a credential-free loopback RFB fixture,
decoded a 640x360 fixture frame, then sent native UIKit gestures over TCP. Each
language report retains seven received-packet JSON attachments and an inspected
screenshot. They prove one click, two clicks for a double tap, right click for
two fingers, middle click for three fingers, coordinate changes while the left
button remains held during drag, direct touch, pinch-modified coordinates, and
Observe blocking subsequent pointer input and disabling the keyboard button.
For the same 65%-width touch, received x changed from 416 before pinch to 384
after pinch. Right and middle button masks are 4 and 2 respectively.

Earlier failures were fixture-driver issues: the inherited canvas identifier
caused overlapping accessibility targets, window-wide multi-touch gestures
landed on screen-edge controls, and the test initially reversed right/middle
button bits. The final assertions retain the protocol masks and inspect received
events. The input canvas now has a localized accessibility label and its visible
canvas frame; the parent is a distinct accessibility group. Input Mode also has
a localized accessibility label. This does not establish complete VoiceOver
support or physical-device responsiveness.

To repeat, run `python3 scripts/qa/gesture_rfb_fixture.py` (TCP 5999 / HTTP 8768,
both loopback-only). Build for testing and set `AETHERSCREENS_GESTURE_QA=1` in
the UI test target's xctestrun EnvironmentVariables. Run sequentially with
`-parallel-testing-enabled NO` and select
`testReceivedNativeGesturesOnControlledDesktop` and
`testReceivedChineseNativeGesturesOnControlledDesktop`. Stop the fixture after
the reports finish. No real credentials or desktop data are used.
Native two-finger scrolling, recovery and the two physical iPhones' interaction
and perceived smoothness remain separate acceptance gates.

## Pointer transport regression (2026-10-01)

A loopback RFB server captures actual TCP pointer messages after the handshake.
Before the repair, two scenarios failed: wheel positioning/release cleared a
held left button, and a delayed wheel re-pressed that button at the old position
after a newer release/move. The repair retains the current physical button mask
and reads current coordinates when delayed wheel work executes. Wheel press and
release share the input lock; disabling input invalidates queued work even if
control resumes immediately. Disconnect also invalidates old work. A further
regression queued 300 wheel events, entered Observe, then resumed control:
the fresh wheel failed its one-second delivery gate before repair because the
cancelled backlog still reserved timing slots. A changed input generation now
resets those slots; the resumed wheel passes the same gate.

`swift test --filter PointerTransportTests` covers held-button preservation,
release/move before delayed wheel delivery, Observe cancellation and responsive
delivery after cancelling a backlog. The full core suite passed 113 tests with
five environment skips and no failures.
This proves transport behavior on a real local TCP stream, not Apple server
scroll/drag behavior or physical iPhone gesture responsiveness. Those acceptance
gates remain open.

## Connection link routing acceptance (2026-10-01)

The core suite passed 109 tests with five environment skips and no failures.
Connection-link regressions cover saved selectors, ambiguous names, temporary
credentials, account isolation, exactly-once percent decoding and invalid or
unsupported options. Copied saved links contain only the local computer UUID.

The iPhone 17 simulator system-routing test passed (one test, no runtime warnings):
`build/ios-url-routing-draft-retry.xcresult`. It received
`aetherscreens://connect?host=link-qa.invalid&name=Link%20QA&observe=true`
through `simctl openurl` while Quick Connect contained a draft. After explicitly
accepting the system Open confirmation, the draft remained intact; cancelling
the form opened an Observe session with keyboard control disabled. Disconnect
returned to the library without saving Link QA. Both screenshots were inspected.
The first run was cancelled by XCTest's default system-alert handler; the test
now explicitly accepts only the AetherScreens Open confirmation.

To repeat, build for testing, set `AETHERSCREENS_URL_ROUTING_QA=1` in the UI
test target's xctestrun EnvironmentVariables, and select
`testConnectionLinkPreservesQuickConnectDraft`. Deliver the URL above using
`xcrun simctl openurl <simulator-UUID> <URL>` after the log marker
`AETHERSCREENS_URL_QA_READY`, within the 15-second delivery window.
The invalid host deliberately avoids real credentials and network acceptance.
Installed Mac/physical iPhone routing and saved-link copying remain acceptance
gates, along with unsupported SSH/SSH-key, guest and shortcut/widget workflows.

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
  The compact navigation title initially truncated beside four actions;
  diagnostics and sync now live in More Actions, keeping Quick Connect and Add
  directly available. Reviewed the corrected iPhone 17 screenshot: full title.
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

### Compact dashboard and Chinese error recovery

After the resource fix, the Chinese/English switch and persistence workflow,
primary add/edit/settings/diagnostics workflow, and Chinese temporary connection
error/retry/disconnect workflow all passed on iPhone 17 simulator. The latter
confirms account-specific Chinese password labels and no saved device after a
temporary failure. Evidence: `build/ios-localization-fixed.xcresult`; earlier
error screenshot: `build/ios-chinese-error-screenshots`.

Both language menus expose diagnostics and Tailscale sync under More Actions.
The sync action disables while running to prevent duplicate requests. CI
`36812376187` passed for resource fix `32dbfd1`. Signed physical iPhone and
iPhone mini layout tests are running; these are not yet acceptance results.

### Narrow toolbar acceptance and physical test status

The first compact menu still truncated the product name on iPhone 12 mini.
Settings, diagnostics and sync now share the leading menu; Quick Connect and
Add remain direct trailing actions. The mini Chinese/English switch/persistence
and full add/edit/settings/diagnostic workflow both passed in
`build/ios-mini-toolbar-verified.xcresult`; the full title was visually checked.
The fresh-library test exposed an old fixture helper entering `59995900` because
deleting at the beginning left the default port intact. It now selects all,
asserts `5999` and enabled Save before submitting. Core suite remains 87 tests,
four external skips, zero failures.

iPhone 16 Pro Max was unlocked with Developer Mode enabled over Wi-Fi. The
signed app installed and launched. XCTest failed before executing cases: its
runner exited 74 after the IDE peer refused
`dtxproxy:XCTestDriverInterface:XCTestManager_IDEInterface`. Evidence:
`build/ios-physical-localization.xcresult` and its exported runner diagnostics.
This is not physical functional acceptance. The user connected USB; the current
USB test is waiting for the device to unlock after automatic locking.
