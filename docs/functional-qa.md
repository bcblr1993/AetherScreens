# Controlled remote input acceptance

## Physical Mac release-candidate UI gate (2026-10-06)

The Mac runner accepts an explicitly authorized macOS 27 host via `--host`.
The default mode retains isolated `.vmqa` identification and runs the two
English/Chinese Quick Connect cases. `--release-candidate` instead accepts only
the production AetherScreens identifier, after strict signature and Gatekeeper
validation, and tests that unmodified candidate. It does not replace Applications.

For native input acceptance, copy `scripts/qa/gesture_rfb_fixture.py` to the test
Mac and start it there with `--rfb-port 6399 --display-rfb-port 6400 --http-port 8868`.
It binds to loopback by default and serves only synthetic pixels, without an
account or password. Add `--native-input` to the runner to require three passing
tests, with no skips or runtime warnings. The third case verifies actual received
click, right-click, held drag with changed coordinates, keyboard press/release
and wheel packets from the installed native window. It retains packet attachments
and a synthetic-desktop screenshot. Real Apple-server input is a separate gate.

```sh
python3 scripts/qa/run_macos_vm_ui_qa.py \
  --host <authorized-Mac-host> \
  --developer-dir /Applications/Xcode.app/Contents/Developer \
  --app build/release/AetherScreens.app --release-candidate --native-input \
  --output build/mac-release-candidate-ui
```

Stop only the fixture process started for this run after reviewing the report.

The separate Apple-server protocol run on the authorized Mac mini passed real
Mac-account authentication with a 3840x2160 desktop, new clicks and wheel-driven
scrolls recorded by the browser, exact `中文 QA 20261006 verified` committed text,
Observe suppression and restored control. Ten click-specific decoded-marker
changes had median 235 ms and max 1396 ms. The test acknowledges the initial
marker before sending subsequent toggles; otherwise a previous pending update
can merge with the next toggle. This does not measure display presentation or
physical iPhone responsiveness. Source log:
`/tmp/aetherscreens-macmini-live-input-acknowledged.log`.

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
Native two-finger scrolling and the two physical iPhones' interaction
and perceived smoothness remain separate acceptance gates.

## Pan input cancellation and guarded UI run (2026-10-01)

A real loopback RFB session queued 300 wheel ticks, entered local Pan, then
resumed scrolling. Before repair, wheel ticks kept reaching the server during
Pan and the fresh wheel missed a 0.5-second delivery gate behind the backlog.
The client now maintains a separate pointer-input gate. Entering Pan invalidates
queued wheel work and releases held pointer buttons while leaving keys enabled;
resuming pointer input resets wheel scheduling on its next generation. Observe's
global input gate composes with the pointer gate. A received keyboard event acts
as a TCP barrier so bytes sent before cancellation are not mistaken for queued
old work. The test also verifies suppression of fresh engine/native/wheel input,
keyboard delivery, Observe-to-control transition while still in Pan, and fresh
scroll delivery after leaving Pan. These are transport liveness gates, not phone
latency benchmarks.

The final core suite passes 121 tests, five environment skips, no failures. Mac
Release and signed iOS device Release builds pass. The initial hand-selected UI
run retained only four cases even though six were requested; the report was not
accepted as six-case coverage. A fresh configuration ran the missing two cases.
`scripts/qa/run_controlled_gesture_qa.py` now copies a newly generated test plan
to a unique path and verifies the exact result case set, count, skips, failures
and runtime warnings. It preserves the generated plan and existing opt-in plans.
Its actual run `build/ios-pan-input-guarded-qa/result.xcresult` contains all six
requested English/Chinese gesture, viewport and recovery cases, no skips,
failures or runtime warnings. The script is a controlled simulator sub-gate,
not complete release or physical-device acceptance.

Repeat with the fixture running separately:

```sh
python3 scripts/qa/gesture_rfb_fixture.py
# In a second terminal:
python3 scripts/qa/run_controlled_gesture_qa.py --simulator-id <simulator-UUID>
```

Use `--derived-data <directory>` to reuse existing build products and
`--output <new-directory>` to select a new artifact directory. Existing output
directories are rejected. Stop the fixture after completion. No credentials or
real desktop content are used. The current physical phones retain the previous
installed performance candidate pending the user's hand-feel trial.

## iOS local viewport navigation (2026-10-01)

### Zoomed trackpad edge-follow repair (2026-10-06)

The UIKit trackpad input layer now pans the local viewport when the pointer
moves outward within 32 points of a visible edge. Held-button trackpad drags
use the same path. Each axis clamps to the remote canvas bounds; fitted and
letterboxed axes remain fixed. Pan/Observe and direct-touch navigation do not
enable automatic following. A pointer already clamped at the remote desktop
edge can still reveal that edge on an outward finger movement.

Four geometry regression tests passed, and the full suite passed 181 tests
with five external-environment skips. Signed iOS Release build and signature
verification passed. Installed on iPhone 16 Pro Max; actual zoom/follow/drag
acceptance against the physical Mac mini remains pending because iOS refused
application launch while the phone was locked. Installation is not gesture
acceptance.

The old simulator build failed a new acceptance test because zoomed iOS
sessions offered no Pan View control. Observe also removed the native input
surface, preventing local zoom and navigation. iOS now exposes the existing
localized Pan View toggle while zoomed; Observe retains local gestures and
suppresses click/hold/wheel delivery. Pan/Observe hide the local remote cursor.
Entering Pan releases held pointer buttons. A localized Pan status identifies
why local canvas gestures do not send remote input. Viewport offsets are bounded to
visible overflow, including after a zoom or geometry change; pan samples use
the current offset rather than a captured view-render offset. Fit to Window
resets both zoom and offset. Existing macOS Pan availability is preserved.

The new English/Chinese scenarios verify zero received pointer packets during
local pan and Observe, changed touch coordinates after pan, further coordinate
changes after Observe navigation, restored remote control and the original
x=416 mapping after Fit. The six-test report
`build/ios-viewport-bilingual-regression.xcresult` passes both viewport flows plus
the existing English/Chinese native gestures and recovery, without failures,
skips or runtime warnings. Inspected packet attachments show x=244 after local
pan and x=320 after Observe navigation in both languages. Four local-navigation
screenshots were inspected. After adding the localized Pan status, the final
`build/ios-viewport-status-bilingual.xcresult` passes both viewport flows with
no failures, skips or runtime warnings; both Pan status screenshots were
inspected. The final core suite passes 120 tests with five
environment skips and no failures; Mac and signed iOS Release builds pass.
Physical viewport navigation and perceived responsiveness remain unaccepted.
This does not complete all reference gestures; native two-axis scrolling,
secondary/middle drag indicators, three-finger shortcuts, fullscreen and edge/
hot-corner gestures remain in `docs/screens-alignment-audit.md`.

## Streaming progress publication (2026-10-01)

Two regressions reproduced unnecessary loading work after the first desktop was
visible. A view-model scenario with 120 progress/frame updates published 240
progress changes. A real TCP server sent two 4 MiB raw frames in each of two
connections; the second frame still emitted two progress callbacks each time.
The client now stops progress callbacks after its first completed framebuffer
update, resets that state when connecting, and invokes progress on the network
queue like other RFB callbacks. The view model also ignores late progress after
its first frame. This avoids the extra main-queue hop and whole-view progress
publications during ongoing streaming while preserving initial loading progress.

Both regressions now pass, including progress restarting on a new connection.
The full core suite passes 120 tests, five environment skips, no failures. Mac
Release and unsigned iOS device Release builds pass. This measures callback and
publication behavior, not phone input-to-display latency or Screens-equivalent
hand feel. Physical testing remains required.

The current-source simulator report
`build/ios-stream-progress-regression.xcresult` passes all four English/Chinese
native-gesture and socket-recovery scenarios with no failures, skips or runtime
warnings.

The signed Release candidate built and passed strict codesign verification. It
was installed on both iPhone 12 Pro and iPhone 16 Pro Max; normal launch succeeded
on the 12 Pro. The 16 Pro Max reports passcodeRequired=true, so its runtime and
interaction acceptance are pending. Installation and launch do not establish
connection success or improved physical hand feel.

## Session recovery and stale callbacks (2026-10-01)

Before repair, queued frame/progress/connected callbacks restored ended-session
state and successful-connection history. Held trackpad buttons survived mode
changes and session termination. Actual loopback handshakes also showed that
cancelling a password prompt from the old VNC connection failed the replacement
connection. Session callback generations now reject queued notifications from an
ended session; input is released on mode changes, failure, reconnect and end.
VNC/ARD password replies and send completions are bound to their originating
connection. Failed writes stop handshake continuation.

The final core suite passed 118 tests, with five environment skips and no
failures. Mac Release and unsigned iOS device Release builds passed. The final
report `build/ios-controlled-recovery-bilingual-final.xcresult` contains four
passed tests, no skips/failures/runtime warnings: English/Chinese recovery and
the existing English/Chinese native gesture scenarios. The first recovery run
failed because the test looked for `Esc` instead of the actual `esc` control;
the corrected driver passes without renaming the product control.

The loopback fixture's `/drop` shuts down the active TCP socket. Each recovery
test receives a fresh frame on a different connection, preserves zoom/touch mode
(the same touch still reaches x=384), and verifies fresh Shift down/up around
Escape down/up. Retained JSON shows Chinese connection IDs 7 to 8 and English
9 to 10. Both failure and recovered-state screenshots were inspected. Repeat
with the gesture fixture/environment above and select
`testControlledConnectionRecovery` and `testChineseControlledConnectionRecovery`.
This proves simulator UIKit-to-TCP recovery, not Apple server recovery, physical
phone network interruption or improved hand feel. These gates remain open.

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

- `AETHERSCREENS_LIVE_HOST`; supply `AETHERSCREENS_LIVE_PASSWORD` or use a matching saved Keychain account
- `AETHERSCREENS_LIVE_USERNAME` for Mac account authentication; omit for VNC
- `AETHERSCREENS_QA_SSH_USER` for an existing SSH key-authenticated account
- `AETHERSCREENS_QA_CLICK_X`, `AETHERSCREENS_QA_CLICK_Y`: framebuffer coordinates of Click test
- `AETHERSCREENS_QA_SCROLL_X`, `AETHERSCREENS_QA_SCROLL_Y`: optional scrollbar panel position
- `AETHERSCREENS_QA_OBSERVE=1`: verify live frames, suppressed input, held-key release and restored control

Run `swift test --filter LiveFunctionalTests`.
The test asserts new remote click and scroll events. Wrong coordinates, a locked
session, missing fixture, or failed authentication must fail rather than pass.
Restored click and scroll checks poll receiver events for at most five seconds,
instead of assuming delivery after a fixed delay. Wheel records retain the DOM
target and coordinates to distinguish delivery to the wrong region from actual
scrolling. This delivery timeout is not a responsiveness benchmark.

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

### iPhone 12 Pro USB fixture inspection — 2026-10-07

The connected iPhone 12 Pro executed `testPhysicalZoomedTrackpadEdgeFollow`
in `build/iphone12pro-physical-20261007/usb-edge2.xcresult`: one pass, zero
failures/skips. The test pinches to 2×, moves left/right in Trackpad mode,
then measures the viewport independently by touching the same visible center.
It also verifies held-button drag movement and release from received RFB
packets. Screenshots and packets are retained as private XCTest attachments.

The test runner's LAN inspection requests returned `-1009` without a visible
permission prompt. This alone does not prove the user rejected permission.
Physical fixture inspection now exchanges UUID-correlated files in the test
runner's own Documents directory over USB; the Mac reads the synthetic fixture.
The application still makes its normal VNC connection. Simulator inspection
continues to use HTTP. No product permission or network behavior is changed.

The canonical runner selects the twelve bilingual controlled scenarios plus
this edge-follow case for physical devices. It rejects missing cases, skips,
failures and runtime warnings. Use a new output directory for each run:

```sh
python3 scripts/qa/run_controlled_gesture_qa.py \
  --device-id <connected-device-UDID> --development-team <signing-team> \
  --fixture-host <Mac-LAN-IPv4> --rfb-port 6499 \
  --display-rfb-port 6500 --http-port 8968
```

The first full USB suite encountered an English fullscreen double-tap failure;
its result is not acceptance. The persisted runner subsequently executed all thirteen requested cases: thirteen
passed, zero failed/skipped, and no runtime warnings. Evidence is in
`build/iphone12pro-physical-20261007/canonical-suite1/summary.json`,
`tests.json`, `enumeration.json`, and `result.xcresult`. The first fullscreen
failure did not recur; its cause is not claimed to be identified. These controlled tests do not establish physical IME, real
Apple-server behavior or App Store availability.
