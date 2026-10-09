# Screens alignment and full acceptance audit

## 2026-10-09 correction to the historical matrix

The October 8 matrix below is historical. Current verified checkpoints:

- Native Apple file-copy codecs, bounded workers and public upload/download
  sheets exist. Actual Mac mini coordinated directory downloads passed data,
  resource-fork, permissions, modification time, source-URL attribute and
  existing-destination preservation checks. Native upload probes also exist;
  consult `native-file-transfer-research.md` for their exact scope. These CLI
  results do not accept physical iOS picker/provider flows or drag/drop.
- The inspected native sender serializes quarantine and WhereFroms attributes
  only. Arbitrary custom-xattr fidelity is not established. The owned
  WhereFroms gate passed without skips:
  `/tmp/aetherscreens-wherefroms-native-live-20261009.log`.
- Edge-follow projections preserve newer pointer samples through delayed and
  rounded layout acknowledgements. Hardware touch cancellation no longer
  positions a held pointer. Physical arrow/FPS/hitch acceptance remains open.
- Upload preparation uses cancellable metadata-aware copying, a temporary
  volume preflight and specific insufficient-space errors. Snapshot/space
  tests passed 7/7; latest generic unsigned iOS build succeeded:
  `/tmp/aetherscreens-upload-space-error-tests-20261009.log` and
  `/tmp/aetherscreens-ios-upload-space-errors-20261009.log`.
- Completed downloads retain actual save locations for Mac Finder and UIKit
  sharing entries. Receive byte progress is gated to 0.1-second intervals;
  repeated/regressing counts are suppressed, final commit stays exact.
  Old terminal history makes room at 32 entries without evicting active work
  or deleting saved files. Targeted tests and generic iOS builds passed;
  physical presentation/access behavior remains unaccepted.
- The latest full local Release core gate including standard Tight negotiation and automatic quality: Executed 759 tests, with 28 tests skipped and 0 failures (0 unexpected) in 200.259 (200.353) seconds.
  `/tmp/aetherscreens-full-core-adaptive-quality-20261009.log`.
  This covers current core result/progress/history behavior; live opt-ins and
  physical UI/provider/fluidity requirements remain open. UIKit sharing is
  separately build-verified, not exercised by this macOS test suite.


Automatic reconnect now has bounded 1/2/4/8/16-second backoff after a successful desktop. Actual local TCP tests cover fresh frames, preserved zoom, input release, hidden/closed cancellation, five rejected retry sockets, fresh-password waiting/completion and user cancellation. These use a synthetic RFB server; real Mac mini, SSH interruptions and physical iPhone behavior remain unaccepted. Unknown SSH errors conservatively stop rather than retry.

Unclosed requirements include physical iPhone arrow/zoom/edge-follow and
sustained fluidity, real picker/provider save/selection and cancellation,
bidirectional native clipboard, actual remote Curtain, CloudKit account/device
acceptance, adaptive/scaled quality and remaining platform workflows.
Physical device availability and exclusive test windows must be revalidated;
older availability observations below are not current device status.
See `next-iteration-status.md` for dated scope and evidence. No app publication
or claim of complete Screens parity follows from these build/core results.

Audit date: 2026-10-01. Existing notarized candidate: `2eea898`. Reference: [Screens 5 official feature index](https://help.edovia.com/en/screens-5/features/).
This is a completion checklist, not a claim of parity. Unit tests, simulator
screenshots and signed builds do not replace physical input/gesture acceptance.
This October 1 matrix is historical implementation evidence and the subsequent
Screens-parity backlog. Current first-release gates and publication evidence
are in `release-1.0.0-status.md`; the user later authorized publication and
selected the physical Mac mini and connected iPhone 12 Pro for acceptance.


## Current acceptance audit — 2026-10-08

The October 1 matrix below is retained as historical evidence. Current local
build/test checkpoints are in `next-iteration-status.md`. The latest actual
Mac mini full-core gate completed 490 tests, with 16 explicit environment skips
and three assertion failures in one legacy-Keychain migration case, in 150.593s.
The default Keychain remains locked and not writable; fixture saving fails
before migration. Other completed cases reported no failures. This remains a
failed full gate; targeted green tests and unavailable live gates do not prove
full parity. Evidence: `/tmp/aetherscreens-macmini-full-refresh-tests-20261008.log`
and `/tmp/aetherscreens-macmini-keychain-refresh-status-20261008.log`.

The latest native streaming timing trials passed twice over owned patterns,
but measured multi-second full-frame receive windows and roughly one-second
pattern transitions; this is not rendered FPS or physical fluidity acceptance.
Experimental SRP auth remains internal QA. Stable native updates, vendor cursor,
physical fluidity and whole-flow UI acceptance remain open. Earlier UI results
are historical evidence and do not establish complete product parity.

Rechecked the [official feature index](https://help.edovia.com/en/screens-5/features/)
and the following requirements against the current source. These are remaining
product behaviors, not polish items that can be closed by another animation test:

| Priority / requirement | Current authoritative evidence | Completion evidence required |
| --- | --- | --- |
| P0 actual mouse, zoom edge-follow and sustained fluidity | Controlled native input/viewport gates exist; no current physical FPS/hitch/latency gate. LAN TCP probes to 192.168.50.226:22 and :5900 timed out, but existing Tailscale discovery recovered the Mac mini at 100.64.0.3. SSH identity and macOS 27.0.1 verified; actual RFB handshake and 4K/60-second VNC connection tests passed 2/2 (`/tmp/aetherscreens-macmini-mesh-handshake-20261008.log`); explicit Mac-account session subsequently passed 1/1 (`/tmp/aetherscreens-macmini-mesh-ard-session-20261008.log`). `devicectl list devices` reports the paired physical iPhone 12 Pro unavailable; the connected 12 Pro is explicitly simulated. | Reachable target Mac and physical phone; continuous 30-minute session covering arrow rendering, zoom/pan, edge following, reconnect, gestures; measured presentation, hitch and input latency evidence. Simulator success cannot close this row. |
| P1 actual remote Curtain | `CurtainModeManager.swift` explicitly implements a local Lock Screen shortcut notice only. [Official Curtain behavior](https://help.edovia.com/en/screens-5/features/curtain-mode) requires remote display privacy while the client keeps seeing and controlling the desktop; Remote Management is required. | Verify target Remote Management capabilities and protocol; enable/disable on a real Mac, inspect its physical display and retained client control; login-window, headless and multi-display behavior. Do not change remote system settings without concrete authorization. |
| P1 native bidirectional file drag/drop | Historical missing implementation has been superseded by the current native file-copy workers and transfer sheets described above. Physical drag/drop and picker/provider acceptance remain open. [Official Apple-device transfers](https://help.edovia.com/en/screens-5/features/file-transfers) use drag/drop, with direction-specific server requirements: mobile download requires macOS 14+, upload macOS 10.10+. | Real server transfer negotiation and upload/download byte integrity; destination selection, progress/cancel, overwrite and interrupted/reconnected cleanup; native mobile and Mac drag/drop. SFTP alone cannot establish this behavior. |
| P1 Apple clipboard compatibility | Native receive is now integrated for exact Apple banner plus Mac-account authentication; eight TCP cases cover Unicode/empty, metadata isolation, coalescing, size/deadline and reconnect. Actual ordinary client 4K + 60-second stability passed 1/1 after integration (`/tmp/aetherscreens-apple-native-clipboard-client-live-20261008.log`). Read-only actual archive parsing passed in both standard/encrypted profiles, but current archive had unsupported flavor; text/write acceptance remains open. Read-only VNC-password native fetch also failed on this host both without ViewerInfo (45-second deadline) and with ViewerInfo (20 status messages, no archive); native VNC compatibility remains an open parity gap. Earlier actual Mac mini Unicode and ASCII/multiline gates both failed over the recovered Tailscale path; connection remained active and original board restoration passed. ASCII packet acceptance did not produce the remote pasteboard value. Verified Mac-account rerun also failed both cases; ASCII lost QA ownership and was not restored over the changed board, while Unicode restored (`/tmp/aetherscreens-macmini-mesh-ard-clipboard-20261008.log`). Logs: `/tmp/aetherscreens-macmini-mesh-unicode-clipboard-20261008.log` and `/tmp/aetherscreens-macmini-mesh-legacy-clipboard-20261008.log`. | Reachable actual Apple server and exclusive clipboard window; both directions, Unicode/multiline, reconnect and restoration of the pre-test board without retaining private contents. |
| P1 cloud library and credential synchronization | CloudKit reader/coordinator/library model sources exist, but no model integration was found in DeviceList UI. Actual configured container/account gate remains absent. [Official synchronization](https://help.edovia.com/en/screens-5/features/sync) separates connection/settings storage from encrypted Keychain credentials. | Approved actual container/entitlements and credential synchronization policy; connect list/settings to the sync model, then real account/two-device create/edit/delete/conflict/retry tests. Do not infer container IDs or expose key material in cloud journal records. |
| P1 adaptive/scaled quality and interoperability | Actual encrypted RGB565 desktop stability passed 1/1 (101.075 seconds): first genuine 4K frame at 39.9575 seconds, 60 seconds connected after it, 20 pixel-frame callbacks. Native cursor gate still failed; color appearance, physical fluidity and adaptive/scaled operation remain open. Local decoder/GPU/quality gates also exist; none proves end-to-end performance. | Actual Apple server encoding/RGB565/scaling behavior and changing-network quality adaptation, plus end-to-end measured responsiveness. |
| P2 remaining physical workflows | Pencil, external pointer/keyboard, IME/dictation, AirPlay/external displays and Siri/widget acceptance remain open in the historical matrix. | Exercise each requested platform workflow on actual hardware; existing UI controls or simulator tests are insufficient. |

No new remote configuration, credentials, device installation or release was
performed by this read-only audit. The overall goal remains active. Mac reachability was recovered through Tailscale; physical phone availability
and missing real-server feature implementation still block complete acceptance; local work must retain these requirements rather than
closing the goal around unit/Simulator results.

| Requirement | Current implementation and evidence | Remaining work |
| --- | --- | --- |
| Mac account / VNC connections | ARD type 30 and VNC implemented; real Mac authentication, frame and 60-second session passed. iPhone 12 Pro received the requested target Mac's desktop; user confirmed connection. | iPhone 16 Pro Max target session; sustained physical-device interaction |
| Interactive shortcut toolbar | Sticky modifiers, common shortcuts, F1-F12; Mac F8 observed remotely | Physical iPhone modifier/shortcut delivery and narrow layouts |
| Touch / trackpad gestures | Native iOS recognizers now wire immediate clicks, secondary/middle clicks, held-button dragging, two-axis scrolling and pinch zoom. Cursor movement uses remote-pixel scaling, smooth acceleration and an immediate UIKit layer. Core tests cover click release, scaling and engine drag state. English/Chinese iOS simulator flows additionally inspect packets received for single/double/right/middle click, held-button drag, direct touch, pinch coordinate changes and Observe suppression; both flows pass without runtime warnings. Three-finger desktop shortcuts, local two-finger fullscreen and held-button colors are now implemented; their acceptance details appear below. Actual loopback TCP tests additionally verify scrolling preserves held buttons, delayed wheels use the latest released-button state/coordinates, and Observe cancels old work without delaying resumed control behind the cancelled backlog. | Physical tap, secondary click, drag, pinch, scroll and mode changes; Apple server combined scroll/drag acceptance; perceived responsiveness; native two-axis scroll and secondary/middle drag indicators; physical three-finger shortcuts and fullscreen; edge/hot-corner gestures |
| Hardware pointing devices | Mac native mouse, drag, context menu and wheel passed | iPad pointer and hardware keyboard acceptance |
| International keyboards / dictation | UTF-8 text drawer and Chinese keysyms passed; NSTextInputClient composition tests | Real IME; supplementary-plane characters; dictation workflow |
| Clipboard transfers | Native Apple receive integrated for Mac-account connections with bounded off-worker archive parsing and socket identity; outgoing Apple UTF-8 archives now queued off the interaction thread with latest-only pending coalescing and Observe/socket-generation guards; real bidirectional acceptance still pending. Local clipboard insertion passed; traditional Latin-1 and negotiated compressed UTF-8 double-direction loopback TCP text, malformed message rejection and ended/reconnected session guards tested | Actual bidirectional clipboard and rich content transfer; insertion is not parity |
| Curtain privacy mode | System lock shortcut and password restoration passed | Actual remote display blackout while remaining unlocked; lock is not parity |
| Display selection | ExtendedDesktopSize server layout decoding, stable screen IDs, selected-monitor crop and bounded input coordinates; no monitor-count inference from framebuffer aspect ratio. Actual TCP tests cover layout-only updates, rejected resize payloads and subsequent raw frames, plus framebuffer resizing. | Apple server layout negotiation and physical per-display acceptance; target Mac currently has one online LG HDR 4K display |
| Adaptive image quality | Raw, Zlib, ZRLE and CopyRect decoding; Metal rendering; native presented-frame FPS and measured TCP RTT diagnostics | Network-dependent quality/compression selection and measured responsiveness. Initial-frame progress is now suppressed during streaming; regression tests prove fewer UI publications, not physical responsiveness |
| Observe / control modes | Explicit Observe Only mode; real Mac frames continue while text, clicks, wheel and clipboard writes are blocked; held modifiers released and control restored. iOS retains local zoom/pan while Observe suppresses received pointer input; English/Chinese controlled viewport flows pass. Pan separately blocks pointer input, cancels queued wheels and preserves keys; actual TCP tests cover nested Observe transitions and responsive scrolling afterward | Physical iPhone toggle and input suppression acceptance |
| Reconnect / session recovery | In-session reconnect clears input and restores remote typing. English/Chinese simulator socket-interruption tests pass with a new TCP connection, fresh frame, retained zoom/touch mode and received fresh modifier/key events. Core tests reject ended-session callbacks and old VNC/ARD password replies | Physical iPhone and Apple server recovery; real phone network interruption |
| Quick connect / session selection | Temporary account/VNC requests and optional saving; installed Mac account connection and received typing passed; iPhone simulator validation, save toggle and error/disconnect flow passed. In-app retained session selection now preserves sockets/viewports, gates hidden input and rejects hidden clipboard callbacks; English/Chinese received-packet UI flows pass | Physical iPhone quick connection and session switching; OS background execution remains unverified |
| Secure connections / SSH keys | External Tailscale transport, device import client and Keychain | Real Tailnet route/import acceptance; integrated SSH tunnel/key handling |
| File transfers | No transfer implementation | Bidirectional transfer and received-file verification |
| Data / credential synchronization | Local persistence and Keychain migration | Cross-device synchronization and conflict handling |
| Toolbar customization / keyboard options | Per-computer button size, top/bottom position, visibility, ordering and multiple spacers implemented. Installed Mac position/size/menu switching, hiding, moving, adding spacers, relaunch persistence and remote arrow/delete delivery passed. iPhone 17 simulator settings flow passed; final English/Chinese flows on a 375-point iPhone 13 mini simulator passed and screenshots were inspected. English/Chinese customization flows on both physical iPhones also passed (2/2 each, no runtime warnings), using an invalid temporary destination. Temporary settings remain in memory; hiding a held modifier releases it. | Physical iPhone live toolbar/key delivery; keyboard mapping preferences and cross-device synchronization |
| On-disconnect actions | Disconnect only | Per-connection Mac hot-corner, lock and logout actions before disconnect; proof on an isolated acceptance desktop |
| URL schemes / automation | Mac/iOS bundles register aetherscreens and alternate vnc handlers. Saved identifier/name/address and temporary account/VNC links support explicit Observe selection. Core validation and iOS system URL delivery preserve a Quick Connect draft, open the queued Observe session after dismissal, disable keyboard control and avoid saving the temporary computer. | Installed Mac and physical iPhone routing/copy-link acceptance; SSH/SSH-key and guest semantics with real server/tunnel handling; applicable shortcuts/widgets |
| AirPlay / external display / Pencil | Not implemented | iOS display routing and peripheral acceptance |
| Mac multi-window sessions | Independent native windows; real Mac concurrent account sessions, minimizing/restoring, saved-session reuse, Observe isolation and closing one window while continuing remote input in the other passed. Numbered window/menu titles distinguish the same computer. | iOS in-app session selection passes controlled UI; physical switching and OS background behavior remain in their separate requirement |
| Wake-on-LAN | Packet construction tests and send-success notice | Real wake verification on an appropriately configured sleeping Mac |
| Discovery / device library / diagnostics | Bonjour discovery visible; add/edit and diagnostics UI covered | Saved devices now use a neutral Saved badge; Tailnet status is distinguished from screen-sharing reachability. Remote API error/recovery acceptance remains. |
| UI consistency / branding | App icon assets on Mac/iOS/site, grouped account forms and readable input bar | Full narrow / empty / loading / error / modal audit on physical devices |
| English / Simplified Chinese | Implemented; core/catalog tests, Mac switch, simulator persistence/narrow layouts and both physical iPhones' language switch/persistence passed. Account prompt passed both simulator languages. | Remaining whole-flow physical-device layout audit |
| Release readiness | Latest core suite: 177 tests, 5 environment skips, no failures. Current Mac Release and signed iOS device Release builds pass; prior iOS simulator test builds pass; iOS system URL flow passes with no runtime warnings. URL integration cbfe9db, pointer transport 3178a3a and native gesture/UI integration 7b93500, session recovery d286a69 and streaming progress 951e0c3 and viewport navigation d30c4f8 and Pan pointer gate 4b6629e passed CI, as did prior input/resize commits; the earlier 73-test candidate passed notarization, mounted DMG and installed input | Display-layout integration 3be37e8, incremental GPU rendering 913eb8c and display-switch input eb78dcb passed CI; clipboard lifecycle/text encoding a411187 passed CI; extended-clipboard validation 5485f1b passed CI; native navigation gestures 698249b passed CI and controlled UI; physical acceptance remains required. Complete functional gates and user review; no public release yet |

Vision Pro, Windows/Linux server support and Screens Connect infrastructure are
listed by the reference product but were not in the requested iPhone/iPad and
Apple-silicon Mac platform scope. Their absence must not be described as supported.

The iOS live test now accepts the Mac username and selects the account password
field. Previously it could only exercise the VNC-password path. The updated account form
simulator test passed. Connection attempts no longer stamp successful-connection
history; a regression test verifies this boundary. Physical iPhone
initially required unlocking both devices. Parallel USB runs subsequently
completed the six UI scenarios on iPhone 12 Pro and iPhone 16 Pro Max. The 12 Pro
passed 6/6; the 16 Pro Max passed 5/6 before an interrupted menu tap was retried.
The English and Chinese toolbar scenarios then passed 2/2 on each device.
These scenarios check UI and intentionally failed destinations, not live input.

Physical connection diagnosis found that Bonjour instance display names had
been incorrectly converted to DNS host names. The fix resolves the actual SRV
host and port and repairs only old generated addresses, preserving device IDs,
accounts, Keychain associations and manually configured IP addresses. A live
LAN discovery regression verifies a display name differing from its DNS host.
The 12 Pro received a real framebuffer from its saved MacBook Pro after repair;
that machine is 192.168.50.26, not the requested 192.168.50.226 target. The
16 Pro Max's saved configuration lacked a username, so its Mac-only server
rejected VNC authentication. Interactive Mac username/password prompting is now
implemented with handshake and saved-versus-temporary persistence regressions.
The 12 Pro subsequently passed the account-session test against 192.168.50.226;
its screenshot shows the controlled QA desktop. The user confirmed connection
but reported poorer responsiveness than Screens. The 16 Pro Max target test
was interrupted before reaching Quick Connect and remains pending; its subsequent
normal launch was denied while locked. CoreDevice refused pasteboard
transfer because the current clipboard is marked transient/remote-synchronized;
no password was copied into it or written to test arguments/results.

The responsiveness repair removes single-click waiting for double-tap zoom and
the 50 ms click-release timer, connects the previously unwired iOS gestures,
scales finger points to remote pixels, moves the cursor directly in a UIKit
layer, and avoids publishing unchanged first-frame/display state for every
frame. Metal invalidation is coalesced and removes the extra main-thread hop.
The latest core suite passed 102 tests with four environment skips. Mac and iOS
Release builds passed. The optimized iOS candidate was installed on both phones;
normal launch passed on the 12 Pro and awaits unlocking on the 16 Pro Max.
Actual improved hand feel and physical gesture delivery remain unaccepted.
This is an internal test candidate, not a public release.

Reference detail checked on 2026-10-01: [Toolbar customization](https://help.edovia.com/en/screens-5/features/toolbar-customization),
[on-disconnect actions](https://help.edovia.com/en/screens-5/features/on-disconnect-actions),
and [URL schemes](https://help.edovia.com/en/screens-5/features/url-schemes).
The remaining-work cells retain these concrete behaviors; existence of a
settings sheet or parser alone is not completion of the corresponding feature.

Live toolbar/menu acceptance exposed a metrics deadlock: the network thread
published an observable bandwidth value while holding the metrics lock and
waited for SwiftUI's main thread; Metal drawing on the main thread waited for
that lock. The repair publishes on the main thread after releasing accumulator
locks. Regression tests cover observable notification reentering frame recording
and main-thread publication from a network thread. The previously stuck native
position menu and continued remote key delivery passed in the installed repair.

The iPhone keyboard-settings acceptance uses an invalid temporary destination;
it verifies UI configuration, sheet stability, visible controls and disconnect,
not live network delivery. Screenshot review caught an oversized truncated English
title; the final inline title fits both languages. Sorting/removal controls have
44-point targets, and the session menu exposes configuration without requiring
horizontal toolbar scrolling. The final mini report contains two passed tests,
zero failures and zero runtime warnings.

Gesture reference checked on 2026-10-01:
[Cursor Control and Gestures](https://help.edovia.com/en/screens-5/features/cursor-control-modes-and-other-gestures).
The reference documents two-axis scrolling, secondary/middle drag, three-finger
Mission Control/App Expose/Space shortcuts, two-finger fullscreen toggling, edge
cursor positioning and hot-corner gestures. The existing click/drag/pinch tests
do not prove all those workflows. They remain in the full gesture acceptance
scope; local viewport navigation does not substitute for them.

## Server-reported display layouts

The client previously advertised encoding -308 without consuming its payload and
inferred two displays from wide framebuffer dimensions. It now decodes
[ExtendedDesktopSize](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst),
validates unique IDs and framebuffer bounds, preserves unknown flags, and consumes
failed resize responses without applying their undefined geometry. Layout-only
updates retain existing pixels; changed framebuffer dimensions invalidate them.
Server ID zero remains distinct from the full-desktop UI choice. Monitor removal
falls back to the full desktop, and selected-monitor coordinates clamp to its
actual last pixel. Session-generation guards reject stale layout/selection work.
Unchanged geometry does not republish canvas state or reset local zoom. Metal
samples only the selected monitor's normalized texture region; the CPU fallback
crops the same bounds, and canvas sizing/input share that region. The desktop view
observes monitor-list publications directly so same-size, layout-only changes
refresh its menu even when no new pixel frame arrives. Changing region
resets local navigation and cancels active input recognizers. Layout-only replies
do not mark the initial desktop as visible or suppress its download progress.

`swift test` passed 125 tests with 5 external-environment skips and no failures
(`/tmp/aetherscreens-monitor-accepted-core.log`). Mac Release and signed iOS
Release builds pass. The earlier unsigned invocation failed because no development
team was specified. An incremental signed build later failed strict resource
verification after the localization files changed, so it was rejected. A fresh
build in `/tmp/aetherscreens-display-accepted-signed-derived` uses the existing
development team and passes deep, strict signature verification
(`/tmp/aetherscreens-monitor-final-signature.log`). The signed candidate has not been installed
on either phone during the hand-feel trial. A read-only SSH inventory of the
requested target reports one online LG HDR 4K display, logical 1920x1080 at 60Hz
and 4K physical pixels. This does not verify Apple RFB layout negotiation or
physical multi-display selection, and these remain open acceptance gates.

A concurrent verification run recorded one CopyRect timing-budget failure
(15.784 ms/frame against the unchanged 15 ms threshold; the preceding run was
1.603 ms/frame). The host's subsequently observed load average was over 300 while
other projects were compiling. This is an environment-load hypothesis, not proof
of the earlier failure's cause or physical-phone latency. The failed log
`/tmp/aetherscreens-monitor-final-core.log` is retained; the final acceptance
rerun follows completion of this task's Release builds. No threshold was relaxed.

The final controlled simulator run passed all eight requested cases with zero
skips, failures or runtime warnings (`build/ios-monitor-final-controlled-qa/`).
Both English and Chinese display-selection flows verify a right-monitor crop,
full-desktop restoration, then a live two-to-three-monitor layout change without
changing the framebuffer size or sending pixel data. The new third monitor
becomes selectable and receives the expected translated touch coordinate.
Selected-monitor/full-desktop screenshots were exported and inspected. The
existing native-input, viewport and reconnect flows also passed. These synthetic
loopback desktops do not replace Apple-server or physical multi-monitor proof.
The final complete core rerun passed 125 tests, with five environment skips and
no failures; CopyRect measured 2.172 ms/frame without changing its threshold.

## Incremental GPU uploads and queued-frame correctness

The renderer previously uploaded the complete framebuffer on every dirty draw.
A GPU readback regression reproduced five expected failures before the fix
(`/tmp/aetherscreens-incremental-upload-before.log`): unnecessary full uploads
for a one-pixel update and unchanged redraws, and missing initialization after
a resize when pixel uploading was disabled.

Framebuffer changes now use a bounded revision history shared by independent
readers. Overlapping regions merge; excessive damage or an expired history
falls back to a complete upload. CopyRect uses overlap-safe row ordering and
memmove instead of allocating a temporary array for every row. Invalid raw
updates leave pixels and revisions unchanged, and clipping retains the original
source row stride.

Pixels are copied into retained shared staging buffers, then blitted to a private
texture before rendering in the same ordered command buffer. This follows
Apple's [CPU texture-write synchronization requirement](https://developer.apple.com/documentation/metal/mtltexture/replace%28region%3Amipmaplevel%3Aslice%3Awithbytes%3Abytesperrow%3Abytesperimage%3A%29)
and [buffer-to-texture blit API](https://developer.apple.com/documentation/metal/mtlblitcommandencoder/copy%28from%3Asourceoffset%3Asourcebytesperrow%3Asourcebytesperimage%3Asourcesize%3Ato%3Adestinationslice%3Adestinationlevel%3Adestinationorigin%3A%29).
At most three presentation commands are in flight; overload defers a redraw
until a completion without blocking input on GPU work.

Actual GPU readback tests verify a 3840x2160 initial upload of 33,177,600 pixel
bytes, a one-pixel update of four pixel bytes, unchanged redraws of zero bytes,
CopyRect correctness, initialized resized textures, independent readers, and
same-size framebuffer replacement. Byte counts describe encoded pixel payload,
not measured bus traffic: staging rows are aligned to 256 bytes. A shared-event
test delays GPU execution while 24 frames are queued and verifies each frame's
individual pixels, covering staging lifetime and command ordering.

The final complete core suite passed 132 tests with five external-environment
skips and zero failures (`/tmp/aetherscreens-incremental-core-final.log`);
1080p CopyRect measured 0.760 ms/frame against the unchanged threshold. Mac and
iOS Release builds passed (`/tmp/aetherscreens-incremental-mac-release.log`,
`/tmp/aetherscreens-incremental-ios-release.log`). The fresh signed iOS candidate
in `/tmp/aetherscreens-incremental-signed-derived` passes deep, strict signature
verification. It has not yet been installed for physical-device acceptance.
These rendering checks do not measure phone input-to-display latency or establish
Screens-equivalent hand feel. Those physical gates remain open.

The final controlled simulator rerun passed all eight requested English/Chinese
display, viewport, native-input and reconnect cases, with zero skips, failures
or runtime warnings (`build/ios-incremental-render-controlled-qa/`). Exported
selected-monitor and live-layout screenshots were inspected to confirm the new
private-texture rendering path actually presents the expected crop and pixels.
This is synthetic simulator coverage, not a two-phone acceptance result.

The incremental-render commit `913eb8c` passed CI run 36836749844 on its second
attempt. The first attempt failed the existing streaming-progress reconnect
case (five-second wait, no decoded frames), while all GPU tests passed. Its log
is retained at `/tmp/aetherscreens-incremental-ci-failed.log`. The same streaming
case passed locally, then ten consecutive repetitions without changing the
source or timeout. This does not establish the first timeout's cause.

## Display selection during held input

A real loopback TCP regression reproduced an incorrect mouse release at x=4
after switching from the right monitor, where the last transmitted held position
was x=12. It also received old wheel pulses after switching
(`/tmp/aetherscreens-display-input-before.log`). Selection now closes the
transport pointer gate before scheduling UI work: it releases the mouse at the
last transmitted global position and invalidates queued wheel work. Local held
state is cleared while the gate remains closed, then pointer input is restored
according to viewport Pan state. Observe still retains its global input gate.
Geometry changes reset navigation; switching identical geometry clears input
without resetting navigation. Duplicate unchanged layout callbacks preserve
ongoing input.

The TCP regression checks the original release coordinates, cancellation of a
300-tick backlog after a keyboard receipt barrier, fresh scroll on the next
monitor within 0.5 seconds, and a duplicate layout preserving the held drag and
input generation. The earlier six-case pointer transport suite passed, including
Pan, Observe and resumed scrolling (`/tmp/aetherscreens-display-input-after.log`).
Mac Release and signed iOS Release builds pass; the iOS candidate passes deep,
strict signature verification (`/tmp/aetherscreens-display-input-signature.log`).
The initial iOS invocation omitted the existing development team and failed;
the accepted invocation supplies it without modifying project signing settings.
This synthetic two-display regression does not replace physical Apple-server
or two-iPhone acceptance.

The final complete core rerun passed 133 tests with five environment skips and
zero failures (`/tmp/aetherscreens-display-input-core-accepted.log`), including
the added duplicate-layout assertion. CopyRect measured 0.751 ms/frame against
the unchanged threshold.

Display-switch input commit `eb78dcb` passed CI run 36837835393. Its final
controlled simulator run passed all eight requested English/Chinese cases with
zero skips, failures or runtime warnings (`build/ios-display-input-controlled-qa/`).
The selected-monitor screenshot was exported and inspected.

## Clipboard lifecycle and wire text

Two regression cases reproduced stale clipboard writes after ending or
reconnecting a session (`/tmp/aetherscreens-clipboard-lifecycle-before.log`).
Clipboard delivery now captures the session callback generation before queueing
the UI task, rejects a changed generation, and requires a currently connected
client before invoking the clipboard writer. The writer is injectable so these
tests do not read or replace the user's system clipboard. Native platform writes
remain the default.

A packet regression also reproduced UTF-8 bytes in traditional ClientCutText
and carriage returns that violate its format
(`/tmp/aetherscreens-clipboard-legacy-before.log`). The
[RFB clipboard specification](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#746-clientcuttext)
requires Latin-1 and LF for traditional messages, and UTF-8, CRLF and a trailing
null for extended text. Traditional encoding now returns nil for text that
cannot be represented without loss. `sendCutText` returns a Boolean indicating
queue acceptance (not a remote acknowledgement), rejects disconnected/Observe
input and oversize normalized data, and never sends unrepresentable Unicode as
traditional Latin-1. Negotiated extended text uses CRLF on the wire; received
extended text is normalized to local LF.

Actual loopback TCP tests receive accented Latin-1 text from the server, inspect
the client's exact accent/newline bytes, reject unsupported Chinese/emoji
uploads to the legacy-only fixture, and confirm Observe blocks uploads. They
also queue old text across end/reconnect and accept fresh server text after a
new handshake. Compressed UTF-8 parser coverage includes Chinese and CRLF text.
These controlled tests do not establish Apple Screen Sharing clipboard delivery,
physical-phone clipboard routing, rich content or file transfer. Those original
acceptance requirements remain open.

The complete core suite passed 137 tests with five environment skips and zero
failures (`/tmp/aetherscreens-clipboard-core-accepted.log`); CopyRect measured
0.708 ms/frame against the unchanged threshold. Mac Release and signed iOS
Release builds passed (`/tmp/aetherscreens-clipboard-mac-release.log`,
`/tmp/aetherscreens-clipboard-ios-release.log`), and the signed iOS candidate
passes deep, strict verification (`/tmp/aetherscreens-clipboard-signature.log`).

Clipboard lifecycle/text-encoding commit `a411187` passed CI run 36838639008.

## Negotiated UTF-8 clipboard TCP coverage

The controlled TCP fixture now exercises negative-length extended clipboard
messages after a real RFB handshake. Tests observe capability replies, the
client's notify action, a server request and its compressed provide response.
Independent decompression verifies exact Chinese, emoji, CRLF multi-line and
trailing-null bytes rather than invoking the client's own decoder to check its
encoder. A server notify/request/provide exchange then reaches the session's
clipboard writer with normalized Chinese/emoji text. Observe cancels the pending
upload and blocks an explicit new upload; a delayed server request sends no
provide response, while the incoming clipboard download still succeeds.

The expanded regression reproduced three failures before the fix
(`/tmp/aetherscreens-clipboard-extended-validation-before.log`): a capability
message missing its size entry enabled Unicode uploads, RTF-only capabilities
also enabled text uploads, and a compressed text value without a terminating
null overwrote the local clipboard. Capability payload length now matches the
number of advertised format bits, UTF-8 availability requires the text format,
and losing text capability clears pending uploads. Text provides require their
terminating null. Following valid legacy messages still decode after malformed
extended messages, proving the stream remains aligned. The rules follow the
[RFB Extended Clipboard specification](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#7729-extended-clipboard-pseudo-encoding).

The complete core suite passed 140 tests with five environment skips and zero
failures (`/tmp/aetherscreens-clipboard-extended-core.log`); CopyRect measured
0.671 ms/frame without changing its threshold. Mac Release and signed iOS
Release builds passed (`/tmp/aetherscreens-clipboard-extended-mac-release.log`,
`/tmp/aetherscreens-clipboard-extended-ios-release.log`); the iOS app passes deep,
strict signature verification (`/tmp/aetherscreens-clipboard-extended-signature.log`).
The first new test compilation hit a Swift type-inference diagnostic; explicit
closure types and UInt32 length assertions fixed the fixture before reproducing
the product failures. None of these tests read or overwrite the user's system
clipboard. Apple-server, physical-phone and rich-content acceptance remain open.


## Native navigation gestures and fullscreen recovery

Following the [Screens gesture reference](https://help.edovia.com/en/screens-5/features/cursor-control-modes-and-other-gestures),
iOS now recognizes three-finger up/down/left/right swipes and sends Control-Up,
Control-Down, Control-Right and Control-Left respectively. The shortcut menu
also exposes App Windows and previous/next Space in English and Chinese.
Session dispatch releases sticky modifiers first and blocks these remote
shortcuts in Observe mode. A real loopback TCP test verifies every key packet,
including sticky Command release and the absence of remote keys in Observe.
Actual three-finger contact recognition and customized Mac shortcut mappings
still require physical acceptance.

Two-finger double-tap toggles local fullscreen in normal and Observe modes.
Toolbar/keyboard visibility returns on exit, while a failed fullscreen session
reveals recovery and disconnect controls. Reconnect preserves its fullscreen
preference. The local cursor now gives blue/red/green feedback for held
left/right/middle buttons. Physical secondary/middle dragging, edge navigation
and hot corners remain open; these changes are not complete Screens parity.

The first full ten-case UI run retained a genuine fullscreen failure in
`build/ios-navigation-fresh-controlled-qa`; the subsequent run in
`build/ios-navigation-final-controlled-qa` still failed Chinese first entry.
Temporary DEBUG-only touch diagnostics then proved the tap recognizer reached
its ended action and the model reported `full=true state=connected`, while
native view updates retained `full=false`. The input identity was published
before the fullscreen layout value, allowing a synchronous rebuild with stale
layout. Fullscreen is now changed before input identity, inside the same
animation. Both language-specific fullscreen/recovery tests passed in
`/tmp/aetherscreens-navigation-order.xcresult`. The diagnostic instrumentation
was removed; final tests add three additional enter/exit cycles per language,
each requiring one gesture and no remote pointer packets.

The controlled runner now enumerates all ten requested cases before execution
and rejects discovery omissions. An earlier incremental build executed only
eight old cases despite reporting test success; its guarded run was rejected
and preserved in `build/ios-navigation-gestures-controlled-qa`. A fresh derived
data directory restored discovery. No skipped or missing case counts as a pass.

Current core validation passed 141 tests with five environment skips and no
failures (`/tmp/aetherscreens-navigation-state-core.log`); unchanged CopyRect
threshold measured 0.677 ms/frame. Mac and signed iOS Release builds passed
(`/tmp/aetherscreens-navigation-state-mac.log`,
`/tmp/aetherscreens-navigation-state-ios.log`), and deep/strict iOS signature
verification passed (`/tmp/aetherscreens-navigation-state-signature.log`).
Final guarded acceptance passed all ten requested cases with no skips,
failures or runtime warnings (`build/ios-navigation-state-controlled-qa`).
The six exported fullscreen/restored/connection-loss screenshots in
`/tmp/aetherscreens-navigation-state-attachments` were inspected in both
languages: fullscreen hides controls, exit restores the keyboard, and failure
reveals recovery controls. At this snapshot the English connection-loss screenshot lacked the status-bar
row seen in the Chinese screenshot. The recovery-rendering follow-up below
checks settled placement and renders both rows; full physical error-layout
consistency remains in the UI acceptance gate.
Two-phone live interaction, physical smoothness and the other open acceptance
requirements above remain required before human review and release.


## Recovery rendering and physical-test preparation

Navigation gesture commit `698249b` passed CI run 36843762056. Its initial
English failure screenshot omitted the system status row. A proposed XCTest
`app.statusBars` assertion was rejected as an acceptance signal: both the
normal and recovery layouts lacked that element in the iOS 27 test hierarchy
(`/tmp/aetherscreens-statusbar-fresh.xcresult`, four assertion failures).
A reused diagnostic test-plan path also executed the previous test body rather
than the new assertions; it is not evidence for the new checks. Fresh test-plan
paths are required.

The replacement waits for recovery's Session Options button to return to the
normal layout's vertical position, then captures the screen. Both languages
passed (`/tmp/aetherscreens-recovery-geometry.xcresult`). The exported recovery
screenshots show the system clock and connectivity row in both languages.
Pixel comparison locates the toolbar at the same rows in English and Chinese.
An experimental safe-area branch refactor passed two targeted tests but did
not improve that measured placement, so it was removed. No speculative product
layout change remains. Physical error-state layout acceptance remains required.

The controlled fixture defaults to loopback and can explicitly bind a local
LAN interface. The runner now supports either a simulator or a signed USB
physical-device destination and injects the fixture host plus independently
configurable RFB, dual-display RFB and HTTP inspection ports. Separate fixture
processes/port sets keep simultaneous phone runs from sharing event resets or
socket interruption commands. Defaults remain 5999/6000/8768. A loopback address
or missing signing team is rejected for physical runs before build/execution.

The LAN-address controlled simulator suite passed all ten requested cases with
zero skips, failures and runtime warnings
(`build/ios-lan-controlled-native-qa`). This validates network routing to the
received-event service, not Apple Screen Sharing or physical hand feel.
Two simultaneous real TCP handshakes then demonstrated event isolation:
resetting/dropping the 5999/8768 lane preserved the 6999/8868 lane's existing
key record and delivery of a subsequent key
(`/tmp/aetherscreens-fixture-isolation-smoke.log`). Alternate-port UI validation
passed exactly the Chinese display-selection and English fullscreen/recovery
cases, with no skips, failures or runtime warnings
(`/tmp/aetherscreens-isolated-ports.xcresult`). Execution logs confirm entry
of ports 7000 and 6999; the inspection service ran on 8868. Python syntax,
missing physical signing/LAN arguments and out-of-range TCP ports were also
checked. These port-plumbing checks do not replace the separate physical gate.

The iPhone 12 Pro reconnected over USB and reported unlocked; developer mode
was enabled and its development disk image reported compatible/usable.
A signed physical UI test build succeeded, but preflight discovery's runner
failed to initialize with `Timed out while enabling automation mode`
(`build/ios-12-controlled-native-qa`). The guard rejected the run even though
xcodebuild printed test success. A separate one-case direct execution repeated
the same initialization timeout (`/tmp/aetherscreens-native-12-direct.xcresult`)
without executing a functional case. The human has been asked to confirm any
phone-side UI Automation/password prompt and its developer setting. No device
password is collected by the test. The 16 Pro Max remains unavailable. Neither
physical run nor the whole original goal is accepted by these controlled results.

For parallel physical QA, start one fixture per phone on separate ports and
use different derived-data/output directories. For example, lane A uses
5999/6000/8768 and lane B uses 6999/7000/8868; pass the same local LAN address
through `--listen-host` on each fixture and `--fixture-host` on each runner.
Use `--device-id`, `--development-team`, `--rfb-port`, `--display-rfb-port` and
`--http-port` explicitly. These are test fixtures containing no real desktop
content or credentials; stop each owned process when its run ends.


## Performance measurement correction (2026-10-01)

The renderer now counts successful drawable presentation callbacks, rather than
command-buffer submissions. Zero/invalid presentation times and callbacks from
an ended session are rejected. Metal's simulator SDK does not expose these
callbacks, so the simulator does not manufacture a presentation FPS value.
See [Apple drawable presentation time](https://developer.apple.com/documentation/metal/mtldrawable/presentedtime).
FPS describes presented updates during a sample interval; a static desktop or
this event-driven fixture is not a throughput benchmark.

The existing connection's transfer reports supply TCP RTT, collected at most
once per second while sending existing traffic. No probe traffic or idle timer
is added. The expanded EN/ZH badge names this value TCP RTT / TCP 往返 and its
help text excludes remote processing/display latency. It cannot measure
finger-to-screen latency or establish Screens-equivalent fluidity.
See [Apple transport RTT](https://developer.apple.com/documentation/network/nwconnection/datatransferreport/pathreport/transportsmoothedrtt).
Session start/end/failure clears metrics and rejects queued old-session
publications. The core suite passed 144 tests with five environment skips and
no failures (`/tmp/aetherscreens-presentation-rtt-core-final.log`). An actual
loopback TCP test obtained a positive kernel RTT and separately awaited the
peer's pointer receipt. An initial test incorrectly assumed the report callback
implied peer receipt; its failure log is retained and the wait was corrected.
Mac Release and signed iOS device Release builds passed, including strict
signature verification. The initial simulator build exposed the unavailable
Metal API and was corrected with an explicit simulator conditional.

An isolated native Mac QA bundle connected to a separate NoAuth loopback
fixture on 7999/8000/8968. Its visible Chinese badge reported positive
presentation FPS and TCP RTT, and the English badge reported TCP RTT and
throughput. Screenshots and accessibility evidence are saved as
`/tmp/aetherscreens-presentation-rtt-native-{zh,en}.png` and
`/tmp/aetherscreens-presentation-rtt-native-{zh,en}-ax.txt`.
No user account credentials, installed product, or saved computer library were
changed. This is native presentation/label evidence, not iPhone acceptance or
an Apple Screen Sharing speed comparison. Physical fluidity and the original
full functional acceptance remain open; no public release is authorized by
these measurement checks alone.

The corrected fresh simulator build then executed all ten requested English/
Chinese controlled cases successfully, with zero skips, failures and runtime
warnings (`build/ios-presentation-rtt-fixed-controlled-qa`). Both fullscreen,
display-selection, viewport-navigation, recovery and received-native-gesture
lanes passed. The failed initial build is retained separately at
`build/ios-presentation-rtt-controlled-qa`.
A current read-only check reached the target Mac over SSH, but CoreDevice did
not offer an available connected physical-iPhone testing tunnel. The user's
manual iPhone 12 Pro connection/basic-operation result stands; its reported
lack of Screens-level smoothness remains unresolved. Do not infer two-phone
acceptance from the successful simulator lanes.


## Negotiated ZRLE compressed display (2026-10-01)

The client now advertises implemented ZRLE before Zlib, retaining CopyRect and
Raw fallbacks. This adds a lossless encoding option; it does not implement
adaptive JPEG quality or establish that the target Apple server will choose it.
The decoder implements the tile modes and compact BGR pixels for the BGRA32
format the client requests, following
[RFC 6143 section 7.7.6](https://www.rfc-editor.org/rfc/rfc6143.html#section-7.7.6).
ZRLE maintains its own continuous zlib dictionary, separate from ordinary Zlib
rectangles, and resets it on reconnect. Variable inflation uses bounded chunks;
rectangle output is limited to 256 MiB and tile/compressed lengths are checked
before decoding. Invalid indices, reserved modes, overruns, missing data and
trailing tile data reject the entire failing rectangle before framebuffer writes.
New connection failures have matching English/Chinese resource entries.

Twelve decoder tests cover BGR/alpha conversion, edge tiles, packed palette
row padding, non-power-of-two palettes, long runs, dictionary continuation,
reset, malformed data and expansion limits. Five actual TCP tests inspect
SetEncodings and verify pixel equality through interleaved ZRLE/Zlib/Raw,
reconnect, compressed receives larger than 64 KiB, malformed-data rejection
and oversized-announcement rejection. The malformed fixture first decodes a
valid pixel before a later run fails, verifying that partially decoded pixels
never overwrite the last good framebuffer.
The first full suite passed 160 tests with five environment skips and no failures
(`/tmp/aetherscreens-zrle-core.log`); subsequent final-suite evidence follows
below, including the added reentrant-reconnect regression.
Mac Release and signed iOS Release builds, including strict signature checks,
passed. The small synthetic Full HD tile image compressed to 549 bytes from
8,294,400 Raw pixel bytes and decoded in about 3.5 ms in the debug run.
That ratio and timing describe this fixture only, not Apple desktop traffic or
physical-device responsiveness.

The controlled Python fixture has an optional `--encoding zrle` mode, creates
one compressor per connection, requires ZRLE advertisement, and records actual
encoding/payload lengths. Raw remains its default. An independent compiled
Mac QA bundle displayed the fixture's 640x360 compressed image: first payload
2,726 bytes versus 921,600 Raw pixel bytes, followed by continuous incremental
updates and received mouse events. The desktop below the toolbar shadow
matched the earlier Raw screenshot exactly, for region `(0,190,2160,1380)`;
the wider comparison correctly detects the different toolbar shadow rather
than labeling it a decoder difference. Evidence is retained at
`/tmp/aetherscreens-zrle-native.png`,
`/tmp/aetherscreens-zrle-native-events.json` and
`/tmp/aetherscreens-zrle-native-pixel-comparison.txt`.
The full-image protocol tests additionally verify complete framebuffer bytes;
this screenshot crop alone is not that assertion. The QA bundle used temporary
NoAuth loopback connections and did not replace the installed product.

Target Mac encoding selection, both physical iPhones' sustained input/scroll
feel, adaptive compression and the other original functional acceptance gates
remain open. No public release or website publication follows from these
controlled checks.

The receive-notification reconnect regression initially timed out after five
seconds, with no fresh frame and only one negotiated connection
(`/tmp/aetherscreens-zrle-reentrant-first.log`). A post-notification connection
identity guard prevents an old receive from reading the new handshake or
reporting errors against the new socket. The same real TCP scenario then passed
in about 0.09 seconds with complete pixel equality
(`/tmp/aetherscreens-zrle-reentrant-fixed.log`). Stream dictionaries now reset
on the serial connection queue's ready callback, not concurrently from the UI;
ZRLE completion also rejects pixels/errors belonging to an old connection.
This is reconnect-race evidence, not a measured fix for sustained iPhone lag.

The first incrementally rebuilt iOS package printed BUILD SUCCEEDED while
strict codesign verification rejected changed English/Chinese resource files
(`/tmp/aetherscreens-zrle-incremental-signature-check.log`). The candidate was
rebuilt in a fresh derived-data directory and subsequently rechecked. Do not
accept Xcode's build-success message alone as signature verification.

Final source passed 161 core tests with five environment skips and zero failures
(`/tmp/aetherscreens-zrle-core-verified.log`). Mac Release build passed
(`/tmp/aetherscreens-zrle-mac-verified.log`). The iOS Release build at
`/tmp/aetherscreens-zrle-queue-final-signed-derived` passed strict/deep signature
verification after the final code rebuild; its build log is
`/tmp/aetherscreens-zrle-ios-verified.log`.

Both initial and queue-reset controlled simulator runs passed all ten requested
ZRLE EN/ZH cases with zero skips, failures and runtime warnings
(`build/ios-zrle-controlled-qa`, `build/ios-zrle-final-controlled-qa`). The final
receive-notification guard is being verified separately below before acceptance.

A current device check found the 12 Pro wired/connected, booted, unlocked, with
developer mode enabled; the 16 Pro Max's network development tunnel was
still disconnected (`/tmp/aetherscreens-zrle-current-devices.json`). The 12 Pro
was retried in its own ZRLE LAN lane on 6999/7000/8868, independently of the
simulator lane. Its signed test build succeeded, but runner 14452 again timed
out enabling UI automation during test discovery. The enumeration guard
rejected all ten missing tests (`build/ios-zrle-12-controlled-qa`). No physical
functional case executed. The prior phone-side automation confirmation remains
required; no device password is entered or collected by the tools. This does
not invalidate the user's earlier manual basic-operation result, and does not
prove a new installed product revision or two-phone acceptance.

The final receive-notification guard's fresh simulator run passed all ten
requested controlled EN/ZH cases, with no skips, failures or runtime warnings
(`build/ios-zrle-reentrant-controlled-qa`). Final event evidence is saved at
`/tmp/aetherscreens-zrle-final-ui-events.json`.
A subsequent internal buffer-ownership correction uses explicitly aligned
UInt32 storage, transferring it to Data after successful decoding and freeing
it on failure. It preserves the tested pixel bytes and avoids relying on Data's
inline byte-buffer layout. All 161 core tests then passed again, with the same
five environment skips and zero failures
(`/tmp/aetherscreens-zrle-aligned-core.log`); the aligned implementation's Mac
Release and signed iOS Release builds also passed. Final strict/deep signature
verification succeeded (`/tmp/aetherscreens-zrle-final-signature.log`). The UI
run preceded this internal allocation correction; protocol tests afterwards
verify every received framebuffer byte and reconnect behavior with the new
allocation. No UI layout or gesture mapping changed in that correction.
The full original acceptance remains incomplete and awaits the separate
physical/Apple-server gates listed above.


### Exact Zlib rectangle acceptance — 2026-10-01

The subsequent Zlib audit reproduced an independent correctness defect:
`decompress(expectedBytes:)` accepted both an eight-byte output for a declared
twelve-byte rectangle and the first four bytes of an eight-byte output for a
four-byte rectangle. Both rejection assertions failed against the previous
implementation (`/tmp/aetherscreens-zlib-exact-before.log`). The separate
512-rectangle persistent-stream test passed before the fix; this audit does
not claim that valid continuous Zlib updates were previously broken.

The exact-size decoder now uses bounded, fully consumed inflation and requires
exactly the declared pixel count. The Zlib transport validates rectangle bounds
and compressed lengths before reading/allocating, checks connection identity
around reads and decoding, and fails instead of publishing a malformed frame.
The new failure messages have matching English and Chinese catalog entries.
This follows the [RFB Zlib extension definition](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#zlib-encoding):
one ordered stream per connection carrying Raw-format rectangle pixels.

Actual TCP tests verify short/oversized pixel payloads, oversized announced
length and out-of-bounds rectangles preserve the preceding valid framebuffer.
The mixed-encoding test now receives five rectangles including two ordinary
Zlib rectangles interleaved with persistent ZRLE and Raw, and repeats after
reconnect. The 512-rectangle test alternates four-byte and 65,540-byte payloads
and checks complete pixel equality on every update.

All 167 core tests completed with five environment skips and zero failures
(`/tmp/aetherscreens-zlib-bounded-core.log`). Mac Release and fresh signed iOS
Release builds passed (`/tmp/aetherscreens-zlib-bounded-mac.log`,
`/tmp/aetherscreens-zlib-bounded-ios.log`); explicit deep/strict iOS signature
verification passed (`/tmp/aetherscreens-zlib-bounded-signature.log`). The iOS
build emitted only its existing AppIntents metadata-extraction warning. This
transport-only change does not rerun or replace the prior ten-case controlled
UI evidence, nor prove physical-device fluidity. Current read-only device
inspection still finds the 12 Pro connected and the 16 Pro Max paired rather
than connected (`/tmp/aetherscreens-current-devices-oct1.json`). Full physical
acceptance and user review remain open; nothing has been publicly released.

## Retained iOS sessions and VM automation policy (2026-10-01)

Returning to the computer library keeps the connection and viewport alive. The
Open Sessions menu selects the existing session without another handshake.
Selection releases hidden buttons/modifiers, disables hidden input, and rejects
queued or newly received hidden clipboard callbacks. Observe survives selection;
closing one session leaves the other connected.

The final controlled English/Chinese iPhone 13 mini simulator suite executed
12 tests with zero failures, zero skips and no runtime warnings. Packet assertions
verify two connections, selected-session clicks, Observe suppression and closing
one connection while using the other. Core suite: 169 tests, 5 explicit live-environment
skips, no failures. Mac Release and signed iOS device Release builds and strict
signature verification pass. Screenshots reviewed in both languages confirm the
375-point library title remains readable after adding Open Sessions.
Evidence: `build/ios-mobile-sessions-layout-controlled-qa/result.xcresult` and
its `summary.json`. Earlier runs failed because numeric-keyboard clearing and
offscreen Esc automation were incorrect, and one pointer assertion included a
legitimate zero-button cursor event. Those failures were retained, the automation
was corrected, and the complete suite rerun; none were counted as acceptance.

The user requires future UI automation to execute inside the existing `macos27`
VM. The host simulator suite above had already started when that instruction
arrived and was allowed to finish. Future UI runs use the VM; physical iPhone
acceptance remains separate. The VM has macOS 27.0 and an isolated Xcode 27.0
copy; recognizing the tools is not itself UI acceptance. A dedicated Mac XCTest
project at `macos/UITests/AetherScreensMacUITests.xcodeproj` targets a separately
identified QA app via `AETHERSCREENS_MAC_QA_APP_PATH`. Its initial two-language
cases cover Quick Connect, valid/invalid port gating and cancellation. This is
initial VM coverage, not full Screens parity or release approval.

The initial VM `build-for-testing` completed successfully. Actual
`test-without-building` launched the runner, then showed the system
“XCTest / Enable UI Automation” authentication dialog. The runner subsequently exited 65 after
`Timed out while enabling automation mode`; no functional test ran. Human
authentication is pending; no Mac VM functional case is counted as passed yet. The existing VM
and other projects were not reset. Passwords are neither scripted nor recorded.

## 4K compact-pixel decoding and repeatable VM runner

A 3840x2160 high-entropy raw-tile ZRLE fixture verifies every decoded pixel over
three frames using the persistent zlib dictionary. Before optimization, Release
samples were 21.9/22.1/23.8 ms; after checking each compact-pixel tile in one
bounded read instead of three throwing byte reads per pixel, samples were
17.5/17.1/16.5 ms. The full-core run measured 17.7/18.0/18.0 ms and passed
171 tests with 5 live-environment skips. Truncation of any of the last three
compact-pixel bytes in a final 1x1 edge tile is explicitly rejected. These are
host CPU/fixture samples, not a claim about physical-iPhone latency, network
adaptation or Screens smoothness. Logs are under `/tmp/aetherscreens-zrle-4k-*`
and `/tmp/aetherscreens-zrle-tile-bounds-core.log`.

`scripts/qa/run_macos_vm_ui_qa.py` supplies a repeatable VM UI entry point. It
resolves an existing Tart VM, requires macOS 27 and `kern.hv_vmm_present=1`,
requires a separately identified `.vmqa` app, copies into a fresh guest directory,
builds XCTest in the guest, configures the QA app path and retrieves the actual
result bundle. The acceptance gate requires exactly two passing initial Mac UI
cases and no failures, skips or runtime warnings. It does not restart a VM,
retry a timed-out test or enter a password. Syntax/help and refusal of a
non-isolated app were verified; end-to-end VM execution awaits human automation
authentication as recorded above.

Example (use the current isolated Xcode and freshly built QA app):

```sh
python3 scripts/qa/run_macos_vm_ui_qa.py \
  --vm macos27 --user chenxu \
  --developer-dir /Users/chenxu/aetherscreens-ui-tools.ec1zbU/Xcode.app/Contents/Developer \
  --app /tmp/AetherScreens-macOS27-VM-QA.app \
  --output build/macos27-ui-qa-new-run
```

The example QA app must be regenerated from the current Release binary before
acceptance; an older bundle or an already-used output path is not current proof.

Current decoder-change verification also passed the iOS Release device build and
strict deep signature check. Mac Release compilation is included in the Release
core-test build. No new host UI automation was started; the VM auth gate and
physical-device/full Screens requirements remain open.

## Reentrant failure teardown regression

The earlier CI run `36858535958` failed in
`testReconnectFromReceiveNotificationCannotConsumeOldPayloadOnNewConnection`
with an EOF notification; its following run `36858571568` passed. The exact
interleaving of that intermittent EOF is not proven by the CI text. Inspection
found cancellation preceded invalidating the connection reference, and failure
notifications preceded all teardown. A new deterministic TCP test reconnects
synchronously from the failure notification after a malformed ZRLE rectangle.
Before repair it timed out and never negotiated the second connection (four
assertion failures); after repair all ten ZRLE transport cases pass. Both teardown
paths now invalidate the old connection before cancelling it; the failure path
finishes old teardown before publishing the failure. The new test proves the
replacement completes its handshake, publishes the expected full image and
remains connected. It does not ignore any failure or weaken the EOF assertion.
Evidence: `/tmp/aetherscreens-reentrant-failure-before.log` and
`/tmp/aetherscreens-reentrant-failure-after.log`.

After repair, all ten TCP transport cases passed 20 consecutive executions
(200 actual cases, no failures). The complete Release core suite passed
172 tests with 5 explicit live-environment skips. Mac Release compilation,
iOS Release device build and strict deep iOS signature verification passed.
The preceding pixel-decoder/VM-runner commit `5e61aa1` passed CI run
`36859071018`; the teardown repair needs its own exact-commit CI evidence.
The VM's required human UI automation authentication is still outstanding.

## Handshake state notification replacement guards

The connected-state observer can synchronously disconnect/reconnect just like a
failure observer. A new actual-TCP regression reproduced the original bug:
after the callback, the old session issued update/read work on the replacement
socket, which remained in version negotiation and never produced the expected
frame (five assertion failures). Handshake state changes now retain the publishing
connection identity and return when the observer replaces it. The initial
connecting notification similarly returns if its attempt was cancelled or a
nested connect already created the replacement.

Five regressions cover connecting, version negotiation, authentication,
initialization and connected notifications. They verify exactly one replacement
frame, complete expected pixels, the final connected state, accepted socket
counts and the replacement's encoding negotiation. The fixture counts accepted
sockets separately from SetEncodings packets: cancellation need not flush the
old socket's pending message. No unexpected connection failure is ignored.
The initial 15-case TCP suite passes. Evidence:
`/tmp/aetherscreens-state-reconnect-before.log` (reproduced failure) and
`/tmp/aetherscreens-state-reconnect-verified.log` (15 passing TCP cases).
The VM automation authentication and all physical/full Screens acceptance gaps
remain open.

The 15 TCP cases then passed 20 consecutive Debug executions (300 actual
cases). Complete current Release core regression: 177 tests, 5 explicit
live-environment skips, no failures. Mac Release compilation, iOS Release device
build and strict deep signature verification passed. No new host UI automation
was started. Previous teardown commit `506b248` passed all steps in CI run
`36859492030`; this state-notification repair requires its own current-commit CI
result. Logs: `/tmp/aetherscreens-state-reconnect-repeat.log`,
`/tmp/aetherscreens-state-reconnect-core-release.log`,
`/tmp/aetherscreens-state-reconnect-ios.log` and its signature log.

### Standard rich-cursor presentation checkpoint (2026-10-08)

Non-Apple RFB connections now negotiate Cursor (-239). Shape pixels and mask
expand off the transport queue, then source-checked publication updates cached
UIKit/AppKit native cursor images. Explicit hide, hotspot placement, fallback
arrow, external-display shape delivery and session resets are implemented.
Seven targeted codec/native-view/TCP cases passed; held-worker transport testing
confirms pointer sending and reconnect proceed without waiting for conversion.
The full core run passed 412 tests with 9 explicit environment skips.

Apple 003.889 cursor negotiation remains gated: the actual Mac-account session
with Cursor offered authenticated but failed to return its first frame. Its
previous encoding combination is retained while fallback acceptance is checked.
This result does not establish the failure's cause, or implement Apple's separate
0x450 cache protocol. Physical cursor rendering, edge-follow and measured
sustained fluidity remain P0 acceptance work.

Final Apple-banner fallback regression passed 1/1 (78.607 seconds), actual 4K
frames and a continuously connected 60-second session. Twenty targeted
cursor/clipboard cases passed after the guard. Two owned-simulator native
viewport/edge-follow scenarios passed with zero skips/failures/runtime warnings;
exported screenshots verify the green fixture RichCursor and shifting viewport.
Cursor body clipping at the display edge remains visible; no physical FPS/hitch
or Apple cursor interoperability claim follows from these gates.


### Initial pixel request correction (2026-10-08)

The next request now remains non-incremental after cursor/layout-only responses
until actual pixels arrive. A TCP regression asserts full/full/incremental request
ordering. Full core regression passed 413 tests, 9 explicit environment skips,
zero failures (108.926 seconds); both builds passed. Standard Cursor is again
advertised on Apple banners. Actual Mac-account regression passed 1/1 (80.610
seconds), 44 4K frame callbacks and 60 seconds connected, but emitted zero Cursor
shape callbacks. This restores the broader standard negotiation after the
previous temporary guard without claiming Apple shape interoperability or a
proven cause for the earlier first-frame failure. Apple's 0x450 cache remains
future protocol work; all physical and clipboard acceptance gaps stay open.


### Experimental Apple cursor codec (2026-10-08)

Bounded 0x450 STORE/SELECT receive, session-local LRU shape cache and native
callback delivery are implemented behind unadvertised default behavior.
Compressed payloads cap at 2 MiB, dimensions at 512, retained pixmaps at 8 MiB
and 64 entries. Eleven new codec/TCP/negotiation cases passed; full core 424
tests passed with 9 explicit environment skips and zero failures. Both builds
passed. Fractional-alpha conversion assumes straight RGB and requires actual
packet/appearance validation before acceptance.

An isolated explicit-opt-in Mac-account probe received desktop pixels but no
vendor cursor shape within its 15-second acceptance window: 1/1 failed, 35.015
seconds. Startup server-driven control, layout rearming and encrypted-profile
framing remain unvalidated. This is an implementation and negative gate
checkpoint, not an enabled or completed Apple cursor feature. Production does
not advertise 0x450. Physical smoothness and clipboard gates remain open.


### Experimental cursor startup message (2026-10-08)

The isolated cursor probe now sends bounded 16-byte AutoFrameBufferUpdate (0x09)
with full backing geometry before its initial full-image request. Exact wire
and opt-in/Apple-banner gating pass in three control/TCP cases. Full core 426
tests passed with 9 explicit environment skips and zero failures; both builds
passed. Production does not send this experimental startup message.

Actual Mac-account probe still failed the vendor cursor gate (1/1, 36.274
seconds): desktop pixels arrived but no 0x450 shape arrived in the subsequent
15 seconds. Viewer capability/modern-bootstrap prerequisites, server-driven
operation and transition rearming need actual wire acceptance. No successful
Apple cursor rendering or physical fluidity claim follows from this result.


### Cursor image reuse and modern-bootstrap evidence (2026-10-08)

Immutable cursor CGImages are constructed once with decoded models and reused
by native presentation and cache SELECT. Value equality remains geometry/pixel
based. Fifteen targeted tests passed; full core: 430 tests, 9 explicit environment
skips, zero failures (110.731 seconds). One owned-simulator zoomed edge-follow
case passed without skips/failures/runtime warnings; three screenshots reviewed.
Hotspots reach both edges; cursor bodies are still clipped. Physical smoothness
and measured FPS/hitch improvements remain unaccepted. BGRA cache accounting
excludes CGImage/provider and native renderer overhead.

Shared ViewerInfo bytes are regression-tested against independent wire data.
An isolated modern version/ClientInit profile remains internal and opt-in.
Unknown framebuffer encodings now fail before opaque bodies can be misparsed
as subsequent rectangles; TCP regression preserves already decoded pixels.
Actual corrected modern and Apple-only cursor probes returned desktop pixels
but failed the vendor shape gate (36.730 and 37.017 seconds respectively).
The earlier first-image timeout is not a proven stable failure. Independent
actual encrypted bootstrap passed 1/1 (15.111 seconds), including rekey and
verified control records, but full RFBClient encrypted-session integration and
cursor/layout interoperability remain open. Production cursor profile is unchanged.

Final macOS and generic iOS builds passed; git diff --check passed. The owned
fixture was stopped and its three ports closed; the already booted owned
simulator was preserved. No physical acceptance, commit, push or release.

## Encrypted record stream checkpoint (2026-10-08)

AppleRFBRecordStream now reassembles fragmented headers/bodies and coalesced
records while retaining at most one outer record (65,522 bytes). Delivery is
synchronous, avoiding an unbounded decoded-body queue. Invalid lengths,
integrity failure, truncated EOF and delivery-triggered disconnect close the
stream before further delivery. Eleven codec/stream tests passed, zero skips
or failures, 0.014 seconds; all split boundaries of independent OpenSSL vectors
are covered. `/tmp/aetherscreens-record-stream-final-targeted-20261008.log`.
The earlier 430-test full suite precedes these three new stream tests; no new
full-suite count is claimed.

The actual probe now uses this stream for separated header/body delivery. Its
first run authenticated and verified the first record but the remote socket
closed after encrypted Observe (1 failure, 16.686 seconds). Inspection found
the outgoing encryption transition was previously sent only by the clipboard
variant. Every native probe now sends cleartext Observe and SetEncryption 2
before encrypted writes. Repeat passed 1/1, zero skips/failures, 28.027 seconds:
rekey, first record and three continuous verified status records (receive
sequence 4). This is evidence for the corrected path, not proof the omitted
transition alone caused the earlier close. Logs:
`/tmp/aetherscreens-record-stream-live-20261008.log` and
`/tmp/aetherscreens-record-stream-transition-live-20261008.log`.

macOS and generic iOS builds passed; git diff --check passed. Logs:
`/tmp/aetherscreens-record-stream-mac-build-20261008.log` and
`/tmp/aetherscreens-record-stream-ios-build-20261008.log`. Default RFBClient
still does not use native record encryption; the stream is exercised by the
actual opt-in bootstrap probe. Native desktop/metadata/cursor integration,
physical smoothness and the isolated bidirectional clipboard gate remain open.
No commit, push or release.

## Reusable native encryption prelude (2026-10-08)

AppleEncryptionControl centralizes the verified receive-encryption request,
cleartext Observe and outgoing-encryption transition. It also validates the
exact initial single-rekey framebuffer/rectangle envelope before any key
payload is consumed. Two independent-wire tests cover the packets and every
modified envelope byte, plus truncated/extra rectangle framing. Together with
the stream/codec tests, 13 cases passed, zero skips/failures (0.014 seconds);
`/tmp/aetherscreens-encryption-control-targeted-20261008.log`.

The actual probe uses the shared controls and envelope validation. Mac-account
rekey/control regression passed 1/1, zero skips/failures (26.604 seconds), with
four verified receive records and one encrypted Observe write;
`/tmp/aetherscreens-encryption-control-live-20261008.log`. macOS and generic
iOS builds passed; git diff --check passed. Build logs:
`/tmp/aetherscreens-encryption-control-mac-build-20261008.log` and
`/tmp/aetherscreens-encryption-control-ios-build-20261008.log`. This extracts the verified prelude for subsequent
client integration; no production encryption, desktop metadata or cursor
interoperability claim follows. The default RFB client remains unchanged.

## Internal encrypted desktop client integration (2026-10-08)

RFBClient now has a separate internal experimentalAppleEncryption opt-in,
requiring the Apple cursor profile and Apple server banner for native startup.
It retains the ARD exchange wrap key only for this experiment, validates the
initial rekey envelope, installs the record codec and sends the verified
cleartext Observe/outgoing-encryption transition before session configuration.
Subsequent writes are bounded encrypted records; reads verify record integrity
before feeding decoded bytes to the existing desktop parser. Final disconnect
chords also use encryption. Teardown clears keys/decoded pending bytes while
holding the input lock. A diagnostic callback exposes only verified fragment first byte/length;
its callback cannot publish an old session body after disconnect/reconnect.
Public construction and default connection behavior remain unchanged.

Final targeted codec/control/standard transport regression: 43 tests, zero
skips/failures, 10.617 seconds;
`/tmp/aetherscreens-native-encryption-client-final-targeted-20261008.log`.
The first actual integrated probe reached connected after rekey but failed the
20-second first-pixel gate (1 failure, zero unexpected, 28.599 seconds);
`/tmp/aetherscreens-native-encryption-client-live-20261008.log`. This is not
accepted encrypted desktop/cursor interoperability. Diagnostic repeat failed 1/1 (29.290 seconds), receiving 81 integrity-verified
records: an initial 161-byte archive record and subsequent 32,768-byte stream
fragments. Their first bytes are not all message types. Data is arriving but
no complete desktop frame passed the first-pixel gate. Log:
`/tmp/aetherscreens-native-encryption-client-records-live-20261008.log`. Generic iOS build passed;
`/tmp/aetherscreens-native-encryption-client-final-ios-build-20261008.log`.
The earlier 430-test full suite predates these integration changes; this phase
claims only its targeted regression and actual negative gate. Native display
configuration/metadata/startup sequencing still needs wire evidence. No release.

Final macOS build and git diff --check passed;
`/tmp/aetherscreens-native-encryption-client-final-mac-build-20261008.log`.

## Native encrypted first-frame diagnosis (2026-10-08)

Internal callbacks expose verified fragment first byte/length, rectangle geometry
and encoding, and validated ZRLE compressed payload length. They expose no pixels,
clipboard text or credentials; source-identity guards prevent callbacks from
continuing a replaced session. Default/public behavior remains unchanged.

The rectangle probe failed 1/1 (35.945 seconds), identifying a 3840x2160 ZRLE
rectangle (encoding 16), not Raw. The payload probe failed 1/1 (26.726 seconds):
validated compressed length 5,001,652 bytes and 64 verified records arrived before
the 20-second first-pixel timeout. Thus receiving data is proven; a complete frame
is not. Logs: `/tmp/aetherscreens-native-encryption-rectangle-live-20261008.log`
and `/tmp/aetherscreens-native-encryption-payload-live-20261008.log`. Actual
throughput, startup sequencing, progress reporting and the bounded first-frame
deadline need further investigation; no encrypted desktop/cursor acceptance.

A new 128-record synthetic test verifies 4,194,304 bytes with equality/integrity,
zero retained framing bytes after each record, and clean EOF. Receive processing
measured 0.008329 seconds in this Debug run, excluding sockets, decompression and
rendering. This does not establish actual session FPS or explain network/server
throughput. Combined codec/control/standard transport checks: 44 tests, zero
skips/failures (10.479 seconds);
`/tmp/aetherscreens-native-encryption-throughput-targeted-20261008.log`.
That run preceded only the additional payload-length diagnostic hook. Final macOS and generic iOS builds passed; git diff --check passed. Logs:
`/tmp/aetherscreens-native-encryption-payload-mac-build-20261008.log` and
`/tmp/aetherscreens-native-encryption-payload-ios-build-20261008.log`. Full parity remains in progress.

## Native first-frame progress and bounded wait (2026-10-08)

Experimental encrypted desktop reads now publish initial payload progress in
MiB at the first fragment, MiB boundaries and completion, avoiding per-record UI
updates. Only explicit ZRLE/Zlib/Raw pixel payload reads qualify; clipboard,
cursor and metadata traffic cannot renew the desktop deadline or masquerade as
its loading progress. Notifications retain codec/session identity guards.

Native first-frame waiting is now bounded by 20 seconds without pixel-payload
progress and 60 seconds total after connected. Standard sessions keep their
existing 20-second deadline. Deterministic tests cover no progress, mid-transfer
stalls and continuous progress reaching the hard cap. Combined initial targeted
suite: 44 tests, zero skips/failures (10.397 seconds), excluding the later explicit
pixel-payload classification refinement;
`/tmp/aetherscreens-native-first-frame-targeted-20261008.log`.
Actual bounded-transfer result and final targeted/build results are being collected.
No first-frame/cursor, UI rendering, physical smoothness or parity acceptance
is inferred from a longer bounded wait.

Final targeted regression passed 44 tests, zero skips/failures (10.918 seconds),
including the explicit pixel-only progress classification;
`/tmp/aetherscreens-native-first-frame-final-targeted-20261008.log`.
Final macOS and generic iOS builds passed; git diff --check passed. Build logs:
`/tmp/aetherscreens-native-first-frame-final-mac-build-20261008.log` and
`/tmp/aetherscreens-native-first-frame-final-ios-build-20261008.log`.

Actual bounded-wait probe failed 1/1 (77.808 seconds): first ZRLE payload length
5,017,846 bytes, 89 verified records, no complete first frame before the bound.
`/tmp/aetherscreens-native-first-frame-live-20261008.log`. This run preceded only
the explicit pixel-only classification; no default/public profile was enabled.
A contemporaneous read-only tailscale ping reports DERP(baizhiedu), 862 ms, for
the target. The relayed high-latency path is confirmed, but is not alone proof
of the throughput cause. Next work must inspect transfer/path and server profile;
further timeout extension is not accepted as a performance fix. No physical
smoothness, cursor parity, commit, push or release acceptance.

## Actual route comparison and loopback SSH QA (2026-10-08)

Read-only SSH on the trusted Mac mini reports en0 192.168.50.79 and en1
192.168.50.226; TCP 22/5900 on both addresses timed out from this host.
The mesh addresses remain reachable. A bounded, compression-disabled SSH probe
read/discarded 262,144 generated random bytes in 14.776 seconds including SSH
startup, exit 0. No remote file was created or user content transferred. This
shows a slow combined path/startup, not an isolated transport throughput result.

QA now supports a saved-credential host alias only for 127.0.0.1 destinations,
so an owned SSH forward to the already trusted target can exercise the native
client without copying a password into files/arguments or changing saved devices.
The alias is ignored for arbitrary remote destinations. Public app behavior and
network configuration are unchanged. An owned compression-disabled SSH forward
on 127.0.0.1:15941 targets the same Mac's loopback 5900. Actual native client
first-frame/cursor result is being collected; no accepted frame claim yet.

Final loopback SSH actual probe failed 1/1, zero unexpected failures (66.959
seconds). Authentication, native rekey and connected completed; first rectangle
3840x2160 ZRLE, compressed payload 5,017,675 bytes, 37 verified records; no complete
first frame before the bounded deadline. Log:
`/tmp/aetherscreens-native-ssh-forward-live-20261008.log`. This does not establish
that forwarding fixes throughput or native desktop/cursor interoperability.
The owned SSH process (PID 18834) was terminated after the probe; its tool session
completed and port 15941 has no listener. No remote/network configuration changed.
The QA alias compiled in the actual run; git diff --check passed. Existing app
builds/44-case targeted results precede only this test-only credential alias.
Native startup/display configuration and path-limited first-frame behavior remain
open, alongside physical fluidity and all other full-parity gates.

## Fixed native display preface (2026-10-08)

Independently encoded the static 0x1d display configuration from the experimental
protocol field description (no implementation source copied):
https://raw.githubusercontent.com/renegadelink/iShareScreen/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md
The 196-byte packet contains one fixed mode, a 192-byte post-prefix length and
184-byte descriptor. Source/logical dimensions match ServerInit; dynamic flags,
virtual-display type, HDR, rotation and unnamed/physical-size fields are zero.
60 Hz is the proposed mode; actual host acceptance remains a separate gate.
No dynamic resize or high-performance claim is made.

Only the internal encrypted experiment sends display configuration followed by
SetEncodings as its first two records; SetPixelFormat follows. Default sessions
keep their original sequence. Two independent fixed-wire/bounds tests and the
codec/control/standard TCP regressions passed: 46 tests, zero skips/failures,
10.258 seconds; `/tmp/aetherscreens-native-display-preface-targeted-20261008.log`.
Actual server and final build results are being collected. Real metadata/layout,
cursor, startup throughput and physical fluidity still require acceptance.

Actual display-preface probe failed 1/1, zero unexpected failures (79.749 seconds).
It reached connected and received 51 integrity-verified records; first rectangle
3840x2160 ZRLE, payload 5,001,497 bytes, no complete first frame within the bound.
`/tmp/aetherscreens-native-display-preface-live-20261008.log`. Continued records
are not a semantic acknowledgement of every display field, nor evidence that
this preface solves throughput/cursor interoperability. Keep the profile internal.
Final macOS and generic iOS builds passed; git diff --check passed. Logs:
`/tmp/aetherscreens-native-display-preface-mac-build-20261008.log` and
`/tmp/aetherscreens-native-display-preface-ios-build-20261008.log`.
Next native work includes authoritative metadata/layout and actual adaptive
quality behavior; network-path-limited acceptance and physical smoothness remain
open. No commit, push, tag or release.

## Bounded native layout wire diagnosis (2026-10-08)

The experimental protocol document explicitly notes geometry-offset version skew:
https://raw.githubusercontent.com/renegadelink/iShareScreen/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md
Added a bounded 0x451 length-prefix receiver and internal payload callback. The
UInt16 body length must include at least a version word; callbacks are guarded by
connection identity. Until actual geometry is validated, reception fails clearly
instead of resizing by guessed offsets or parsing later pixels against stale
geometry. This is diagnostic framing, not supported display-layout action.

A separate internal experimentalAppleLayoutDiagnostic opt-in plus active native
record encryption is required to advertise 0x451. Default and existing cursor
experiments do not advertise it. QA logs only payload length and the first ten
numeric leader words, no screenshots/clipboard/credentials or display strings.
A TCP regression verifies unvalidated layout and invalid short length preserve
existing desktop pixels and do not manufacture a frame. Initial targeted tests:
47 cases, zero skips/failures (10.312 seconds), before the additional diagnostic
opt-in and explicit non-advertisement assertion. Actual diagnostic/final tests
and builds are being collected. Full geometry application, transition rearming,
cursor continuity and actual multi-display acceptance remain open.

Actual layout diagnostic probe failed 1/1, zero unexpected failures (22.278
seconds), but its failure classification revealed a first-frame false positive:
a 16-byte encrypted framebuffer message containing DesktopSize (-223) triggered
onFrameUpdated before pixels arrived. No 0x451 payload was received. The subsequent
5,001,487-byte ZRLE body was still incomplete when the probe entered its cursor
wait. Therefore this run does NOT prove a completed desktop image. Log:
`/tmp/aetherscreens-native-layout-framing-live-20261008.log`.

Fixed DesktopSize to mark layout-only updates and preserve pixels on same-size
announcements. Initial empty updates also cannot count as the first desktop;
after real pixels have arrived, existing empty-update refresh behavior remains.
A TCP regression verifies no frame callback, unchanged seeded pixels and a full
(non-incremental) retry after the size-only update. Initial expanded targeted
suite passed 48 cases, zero skips/failures (10.378 seconds), preceding only an
extra completion expectation/full-retry assertion in that test. A final full
suite/build is collecting that assertion and all changes. The earlier actual
negative evidence is retained; a corrected live gate remains to be rerun.

Final full core regression passed 442 tests, 9 explicit environment skips, zero
failures (108.668 seconds), covering diagnostic opt-in, non-advertisement and
size-only full-retry assertions;
`/tmp/aetherscreens-native-layout-frame-full-core-20261008.log`.
Final macOS and generic iOS builds passed; git diff --check passed. Logs:
`/tmp/aetherscreens-native-layout-frame-final-mac-build-20261008.log` and
`/tmp/aetherscreens-native-layout-frame-final-ios-build-20261008.log`.
No corrected actual first-pixel/0x451 geometry result is claimed in this phase.
Layout application/rearming, native cursor, throughput and physical smoothness
remain open. No commit, push, tag or release.

## Actual reduced-color profile gate (2026-10-08)

The saved-target live QA harness now accepts explicit fullColor/rgb565 wire
profiles through AETHERSCREENS_LIVE_COLOR_DEPTH; absent configuration keeps
fullColor. Unsupported profile values skip before creating expectations or
connecting. The selected existing RFBColorDepth is passed to the actual client,
without changing default saved devices or production quality policy. No secret
is copied/logged. This enables the previously missing actual Apple RGB565 gate,
not automatic adaptation or scaled-desktop support. An encrypted Mac-account
RGB565 first-frame/cursor probe is being collected. No image/quality acceptance
is claimed until the actual result and frame semantics are inspected.

Actual encrypted RGB565 first-frame/cursor probe completed with one expected
cursor-gate failure, zero unexpected failures (47.225 seconds). It delivered
nine genuine 3840x2160 frame callbacks after the first-pixel correction; first
ZRLE compressed body 1,385,316 bytes, followed by smaller actual updates. No
native cursor shape arrived within 15 seconds. This proves reduced-color decode
and ongoing desktop updates in this session, not visual color accuracy, sustained
fluidity or complete Apple cursor parity. The earlier fullColor samples were
collected at different times/content, so their approximately 5 MB bodies are
not a controlled compression A/B benchmark. Log:
`/tmp/aetherscreens-native-rgb565-live-20261008.log`.

Added a separately explicit-opt-in testLiveAppleRGB565DesktopStability gate using
the same encrypted client and forced RGB565 profile. It measures elapsed frame
arrival and requires 60 seconds connected after the first genuine frame. Cursor
shape acceptance remains mandatory in the existing cursor gate and remains open;
this independent desktop gate cannot close it. Actual stability result is being
collected. Production app code/builds are unchanged in this phase; the previous
442-test full regression predates only QA profile support and this additional
live test. No release.

Final independent RGB565 desktop gate passed 1/1, zero skips/failures (101.075
seconds). First genuine 3840x2160 frame arrived at 39.9575 seconds after connect
invocation, followed by 60 seconds continuously connected and 20 total genuine
frame callbacks. First ZRLE payload 1,385,202 bytes. Log:
`/tmp/aetherscreens-native-rgb565-stability-live-20261008.log`.
This verifies actual encrypted reduced-color decoding and bounded desktop
stability on the current path. It does not prove visual color fidelity, FPS,
hitches, input latency, adaptive/scaled quality, physical smoothness or native
cursor shapes. Approximately 40-second startup remains unacceptable for the
requested polished experience; neither timeout changes nor this passing
stability gate close that requirement. Earlier raw callback totals can include
size-only/empty messages and must not be treated as pixel-frame/FPS counts.

Only QA source changed in this phase; the shared session helper keeps the
existing cursor gate and adds independent reduced-color stability acceptance.
Invalid-profile guard check completed: 1 explicit skip, zero failures or
unexpected expectation failures (0.026 seconds), without opening a session;
`/tmp/aetherscreens-native-quality-invalid-profile-20261008.log`. The session-start
log was subsequently moved after profile validation to match that behavior. Prior full
core 442/build results precede this QA-only additional live case. Full goal
remains active; no user device/quality state, commit, push or release changed.

## Native push scheduling (2026-10-08)

Only the internally encrypted profile now sends its initial full-image request
before AutoFrameBufferUpdate, and does not send a request after every decoded
frame. Standard/plaintext sessions retain their existing polling behavior.
Validated DesktopSize notifications re-arm and request a full image on the native
profile; callback connection identity prevents an old resize continuation from
reading a replacement session. Unvalidated 0x451 still fails diagnostically;
its geometry/rearming is not implemented or accepted. An internal request hook
allows actual QA to count request scheduling without retaining content.

48 control/deadline/codec/standard TCP cases passed, zero skips/failures,
10.672 seconds; `/tmp/aetherscreens-native-streaming-targeted-20261008.log`.
Actual encrypted RGB565 cursor gate failed 1/1, zero unexpected failures,
50.774 seconds: one full request, one genuine 4K frame at 34.9786 seconds after
connect invocation, first compressed body 1,368,972 bytes, but no cursor shape
in the subsequent 15 seconds. Log:
`/tmp/aetherscreens-native-streaming-cursor-live-20261008.log`.
The lack of further frames during this uncontrolled desktop interval cannot
prove stopped updates or FPS; next streaming acceptance needs controlled remote
visual changes. This run does not close native push continuity/cursor or startup
latency requirements. Final macOS and generic iOS builds passed; git diff --check passed. Logs:
`/tmp/aetherscreens-native-streaming-mac-build-20261008.log` and
`/tmp/aetherscreens-native-streaming-ios-build-20261008.log`. The actual probe
uses Observe mode and sends no pointer/keyboard input; controlling-mode shape
changes remain unexercised. No commit, push or release.

## Owned remote visual-change fixture (2026-10-08)

Added scripts/qa/native_display_pattern.swift: one accessory/floating test window
with a small moving color patch and tick label, updating once per second. It
does not request activation/key focus, send input, capture screens, access clipboard,
or write settings. Lifetime is explicitly bounded to 5...180 seconds; a timer
closes its window and terminates the process. Compile passed with warnings as
errors and main-actor AppKit execution;
`/tmp/aetherscreens-native-display-pattern-final-build-20261008.log`.
Invalid lifetime 0 exited 2 before NSApplication creation (no host GUI launch).

Trusted Mac mini checks report UID 501, an existing gui/501 domain and Dock
process, while physical console ownership reports root; these alone are not
proof of the shared surface. Final five-second remote smoke exited 0 and logged
1920x1080 logical geometry/backing scale 2, plus owned draw passes at tick 0 and
tick 1. Log: `/tmp/aetherscreens-native-display-pattern-final-remote-smoke-20261008.log`.
This proves helper execution/drawing/automatic exit, not RFB delivery or visible
presentation on the sharing surface. Next gate must match this known pattern
in actual received pixels while server push remains armed; other desktop changes
must not substitute for that evidence. Remote owned binary removal and temp-directory cleanup completed, exit 0;
remote absence verification also completed, exit 0. App source and prior test/build results are unchanged;
full Screens parity and physical smoothness remain open. No release.

## Received owned-pattern continuity gate (2026-10-08)

Added a separately opt-in RGB565/native pattern test. The matcher reads only the
expected fixture sample points in a 3840x2160 framebuffer, requiring opaque black
border samples plus the known moving teal/orange patch. It stores abstract
pattern signatures/timestamps, never image pixels or screenshots. Local tests
reject transparent/empty/solid/unrelated colors and repeated-state inflation.
Final local matcher test passed 1/1, zero skips/failures (see final matcher log).
The live harness initially compiled with four explicit environment skips; these
are not actual acceptance. Logs:
`/tmp/aetherscreens-native-pattern-matcher-final-tests-20261008.log` and
`/tmp/aetherscreens-native-pattern-qa-build-20261008.log`.

Actual controlled probe failed 1/1, zero unexpected failures (94.841 seconds):
one genuine 4K frame at 33.1388 seconds, one full request, zero matched states
through the 60-second connected observation. The producer ran for its bounded
170 seconds and exited 0, logging owned draws at tick 0/1 and logical 1920x1080,
backing scale 2. This does not distinguish geometry/surface mismatch from missing
push updates. No continuous-update, FPS or fluidity claim is justified. Logs:
`/tmp/aetherscreens-native-pattern-push-live-20261008.log` and
`/tmp/aetherscreens-native-pattern-producer-20261008.log`.

After this negative run, tightened future acceptance: at least three distinct
states, changes spanning at least 30 seconds, and last change less than 20 seconds
old at the end. Deterministic tests prove repeated frozen frames cannot renew
freshness; this refinement has not had a further actual run.

Read-only scutil confirms console user UID 501, on-console and login complete.
Thus /dev/console root ownership alone is insufficient to infer a locked/login
surface. Additional lock-state query timed out; filtered extraction was
unavailable, so lock state is unverified. No login/unlock settings changed.
The owned binary/directory were removed and remote absence verified (exit 0);
no producer remains after its completed session. App code/builds are unchanged
in this QA-only phase; latest full core/build numbers predate these added QA
cases. Actual pattern surface/geometry, native push/cursor and all physical/full
Screens requirements remain open. No commit, push or release.
# Ordinary-profile pattern comparison, 2026-10-08

Capture timeline/byte1 trial (2026-10-08): monitor requested capture until
disconnect; handler flag0 cannot identify successful0x09 subscription. Byte1=1
did not change log flag0 or restore push: states2/span3.650s/age42.124s,
61.012s failed3 assertions,zero skips:
`/tmp/aetherscreens-srp-autoupdate-flag-pattern-live-20261008.log`.
Reserved0 packet restored; no unsupported enable interpretation retained.
Producer80ticks/84draws exited0; owned files removed. Next distinguish handlers
with direct subscription evidence. No parity/fluidity/release claim.

Physical+logical transition (2026-10-08): actual60.672s failed sustained gate,
states2/span3.726s/age41.889s. Producer logged transient3840x2160 scale1 /
window120,1120 then1920x1080 scale2/window120,40. Mapping changes confirmed;
unmatched samples alone cannot prove capture freeze. Actual gate still fails.
Log `/tmp/aetherscreens-srp-physical-hidpi-pattern-live-20261008.log`.
Producer80ticks/83draws exited0, owned files removed. Static server formats show
capture stop/inactive and reconfigure events; causality still unverified.
Next correlate capture restart/subscription. No release or fluidity claim.

Positive physical dimensions (2026-10-08): bounded finite millimeter fields,
explicit nominal96-DPI fallback and measured QA override. Five tests passed,
iOS build succeeded. Actual61.506s gate failed3 assertions: states0/span0/ageInf,
`/tmp/aetherscreens-srp-physical-pattern-live-20261008.log`.
Same-interval server query no longer showed prior physical-size/create errors,
but agent-port/factory/zero-value errors remained. No sustained push claim.
Two4K ZRLE plus one DesktopSize arrived; owned surface still unmatched.
Producer80ticks/82draws exited0, owned files removed/absence verified. Full465 predates
this source correction; current validation targeted+iOS only. No release.

Server-side evidence (2026-10-08): static-format unified logs at HiDPI/combined
trial times report Invalid size in millimeters and unable to create display
configuration. Encoder's physical floats are zero. Actual remote CGDisplay
physical size598.380359111388 x340.770181217549mm. No private/interpolated log
values or capture retained. Omission trial still froze without those size errors,
so size is a compatibility issue, not proven sole cause. Agent-port/zero-value
errors remain unexplained; AutoFrameBufferUpdateMessage2 logs support handler
receipt only. Next bounded physical-size correction and independent agent query.
No app source change, push/fluidity claim or release in this diagnostic phase.

Server-display omission trial (2026-10-08): actual61.103s gate failed all three
assertions, states1/span0/age46.609s. Log:
`/tmp/aetherscreens-srp-server-display-pattern-live-20261008.log`.
Trial flag/branch removed; no omission solution promoted. Producer85draws
exited0, owned files removed/absence verified. New test-thread assertion gate
actually exercised; next gather server/startup evidence. No push/fluidity claim.

Full core regression (2026-10-08):465tests/16 explicit environment skips/zero
failures,148.722s (`/tmp/aetherscreens-srp-display-full-core-tests-20261008.log`).
Selection iOS build completed BUILD SUCCEEDED/exit0. Subsequent QA-only fix
moves pattern assertions to test thread and cancels observation work on cleanup;
five pattern/display tests passed0.041s. Actual gate rerun after lifecycle change
still pending. Neither skips nor earlier first-frame evidence prove full parity.
Native push/cursor/physical UI fluidity remain open; no release.

Combined-display comparison (2026-10-08): independent8-byte selection encoder,
four display tests passed. Actual61.062s aggregate run failed sustained pattern:
states1/span0/age47.477s (`/tmp/aetherscreens-srp-combined-pattern-live-20261008.log`).
Producer80draws exited0; owned files removed. OnConsole/LoginDone true, no lock
key supplied: unlocked state not proven. Full regression session42922 launched,
no terminal claim (`/tmp/aetherscreens-srp-display-full-core-tests-20261008.log`).
Native push/cursor/physical UI parity remain open; no release.

HiDPI descriptor comparison (2026-10-08): backing3840x2160/logical1920x1080
paired bounded encoder passed3/3 tests, iOS build succeeded. Actual61.461s
run still failed sustained pattern: states1/span0/age48.242s, log
`/tmp/aetherscreens-srp-hidpi-pattern-live-20261008.log`.
Owned producer80draws exited0; files removed/absence verified. No push/fluidity
acceptance; next investigate display selection. No release.

SRP normal-control comparison (2026-10-08): QA mode1 still received only one
3840x2160 ZRLE rectangle/23 status4; states0/span0/ageInfinity. Actual60.575s
test failed three assertions, zero skips:
`/tmp/aetherscreens-srp-control-pattern-live-20261008.log`.
Producer85ticks/draws exited0; owned files removed/absence verified. No input
events sent. Mode change did not restore push; no surface/cursor/fluidity claim.
Next inspect display configuration/shared surface. No release.

Native status gate fix (2026-10-08): active encrypted record sessions now parse
0x14 independently of clipboard capability; no type33 clipboard enabled. Actual
61.061s run avoided previous encoding failure but failed sustained pattern:
states1/span0/last change48.778s. Status command4 remains uninterpreted. Log:
`/tmp/aetherscreens-srp-status-separated-pattern-live-20261008.log`.
Producer85s/85draws exited0 and owned files removed. Clipboard transport
regression exit0 (`/tmp/aetherscreens-srp-status-regression-tests-20261008.log`).
Subscription/push and physical fluidity remain open; no release.

Type33 controlled pattern (2026-10-08): producer100s/100draws auto-exit0,
owned fixture removed. Two actual clients failed before sustained gate; final
failure Unsupported framebuffer encoding16778260 (17.789s), log
`/tmp/aetherscreens-srp-controlled-pattern-diagnostic-live-20261008.log`.
No continuous-push acceptance; unknown encoding versus offset not established.
Internal SRP iOS build did complete successfully:
`/tmp/aetherscreens-srp-client-ios-build-20261008.log`.
Native push/cursor/physical smoothness remain open; no release.

Internal RFBClient type33 first-pixel gate (2026-10-08): native profile now accepts
QA-supplied fixed-target RSA SPKI, worker-computes padded SRP, verifies M2 then
SecurityResult and uses existing encrypted record/pixel decoder. Public init
and default type30 unchanged; key trust absent. Final actual frame test passed
1/1, zero skips/failures,12.137s:
`/tmp/aetherscreens-srp-client-owned-first-pixel-live-20261008.log`.
Nine relevant SRP tests also passed15.258s. First pixel is not sustained native
push/cursor/rendering/physical fluidity acceptance. iOS rebuild session57695
launched, no terminal result yet. No release.

Type33 ServerInit acceptance (2026-10-08): actual M2/zero SecurityResult followed
by shared ClientInit0xc1 returned parsed3840x2160,32bpp/depth24 ServerInit.
Test passed1/1, zero skips/failures,8.896s:
`/tmp/aetherscreens-srp-serverinit-live-20261008.log`.
Padded SRP iOS build also completed successfully, terminal exit0:
`/tmp/aetherscreens-srp-padded-ios-build-20261008.log`.
No framebuffer stream/rekey configured; no native-push/rendering acceptance.
Production type33 integration, key trust and physical fluidity remain open.

Padded SRP vector regression (2026-10-08): independent Python padded M1/M2,
wrap key and 64 mutation refusals matched Swift. Nine relevant tests passed,
zero failures (15.629s), `/tmp/aetherscreens-srp-padded-vector-tests-20261008.log`.
Actual stage2 fixture rerun2/2 passed (0.003s),
`/tmp/aetherscreens-srp-actual-stage-fixture-tests-20261008.log`.
iOS rebuild session50045 still live at last poll; no completed-build claim.
Production/native push/physical smoothness still open; no release.

Type33 mutual proof verified (2026-10-08): QA group-width generator hash padding
produced actual body98/stage2. Strict M2 matched; subsequent SecurityResult zero.
Actual test passed1/1, zero skips/failures:
`/tmp/aetherscreens-srp-actual-mutual-verified-live-20261008.log`.
Minimal packet2 accepted on this host; no ClientInit/desktop entered. Key trust,
independent padded vectors, iOS rebuild, production integration, native continuous
push and physical fluidity remain open. Type30 production unchanged; no release.

Type33 continuation evidence (2026-10-08): after short body u32=2/u16=0,
server returned one more u32=1, no verified M2. Test failed 1/1, zero skips,
13.630s (`/tmp/aetherscreens-srp-after-short-live-20261008.log`). Placement is
unverified; this is not accepted SecurityResult/authentication. No key released,
ClientInit or desktop session entered. Next check primary Apple SRP behavior;
do not blame credentials or claim native-push cause. No production change/release.

Type33 actual proof attempt (2026-10-08): fixed QA app-suite device/credential
store mismatch; saved bound credentials resolved. Two real minimal packet-2
attempts failed the expected M2 gate (one failure each, zero skips). Server body6
contains u32=2/u16=0, semantics unverified, not expected body98. No verified M2,
SecurityResult, released wrap key or entered desktop session. Logs:
`/tmp/aetherscreens-srp-mutual-store-live-20261008.log`,
`/tmp/aetherscreens-srp-mutual-short-response-live-20261008.log`.
Earlier credential skips are inconclusive after this lookup correction. Actual
framing/proof compatibility remains open; no native-push causal claim/release.

Type33 QA wiring (2026-10-08): packet-helper iOS build succeeded, terminal exit0
(`/tmp/aetherscreens-srp-packets-ios-build-20261008.log`). Explicit mutual-auth
QA now requires exact saved target/account credentials, verifies M2 then zero
SecurityResult, and closes without ClientInit. Both authorized LAN/mesh binding
attempts skipped before connection for missing exact saved credentials; no real
proof sent and no authentication success. Logs: `/tmp/aetherscreens-srp-mutual-live-20261008.log`,
`/tmp/aetherscreens-srp-mutual-mesh-live-20261008.log`. Native push/physical
fluidity remain open; production selection unchanged.

Type33 final parser prototype (2026-10-08): exact 102-byte bounded profile,
explicit expected stage, rejection of all truncated prefixes and header/reserved
mutations. Combined SRP math/challenge/packet/final tests passed 8/8, zero failures
(7.815s), `/tmp/aetherscreens-srp-server-proof-tests-20261008.log`.
Final envelope and stage remain remotely unverified; no real proof attempted,
no authentication acceptance or production integration claimed.

Type33 packet-2 encoder (2026-10-08): minimal bounded RSA1 proof packet now
has independently checked exact byte offsets/lengths and malformed-field tests,
2/2 passed, zero failures (0.003s). macOS test build passed (8.39s), log:
`/tmp/aetherscreens-srp-proof-packet-tests-20261008.log`.
Research-derived framing remains live-unverified; no real proof sent, no
production integration, server-final-proof acceptance or iOS build claim yet.

Type33 proof prototype (2026-10-08): independently generated synthetic Python
vectors now match Swift client public value, M1 and M2-gated wrap key. Every
single-byte server-proof mutation is rejected. Actual Mac mini challenge group
and options match the restricted profile. Eight targeted tests passed with zero
skips/failures (9.221s); macOS build (1.58s) and generic iOS Simulator build passed.
Logs: `/tmp/aetherscreens-srp-proof-profile-final-tests-20261008.log`,
`/tmp/aetherscreens-srp-proof-mac-build-20261008.log`,
`/tmp/aetherscreens-srp-proof-ios-build-20261008.log`.
No real password or M1 was loaded/sent. Prototype remains unwired; variable-time
BigUInt math is not hardened authentication. Actual mutual proofs, key trust,
native continuous push and physical smoothness remain open. Earlier full448
predates these helpers; production type30 unchanged. No release.

Historical type33 challenge progress: encrypted target identity on a fresh auth connection
successfully receives a bounded SRP challenge. Actual outer layout differs from
the reference memo: u32 stage2/u16 nested length/u32 payload. Decoder corrected
against real bytes; modulus512, generator1, salt32, public512 bytes, account
iterations131578/options80 bytes. No password/proof/session was attempted.
Six boundary/identity/envelope/actual challenge tests passed, zero skips/failures,
1.100s (`/tmp/aetherscreens-srp-challenge-final-source-tests-20261008.log`).
Group trust/algorithm policy/SRP math/mutual proofs and native push remain open;
production type30 unchanged. This is challenge parsing, not authenticated type33
or physical fluidity acceptance. Full448 evidence predates the new helpers.

RSA1 continuation: actual Mac mini public SPKI now passes independent bounded
DER/RSA-2048 validation and Security.framework import. Local identity packet
encryption passes independent private-key decryption/UTF8/boundary checks using
a temporary nonpersistent key. Final targeted3/3 passed, zero skips/failures,
0.807s (`/tmp/aetherscreens-rsa1-identity-live-final-20261008.log`). No identity
or password was sent remotely, no server-key trust or SRP mutual-authentication
acceptance is claimed. Production type30 selection is unchanged; SRP challenges,
proofs and full native stream/physical fluidity still remain open. Earlier
448 full-suite result predates these new helpers.

Authentication prerequisite audit: current Mac-account/native experiment always
uses type30; type33 RSA-SRP is missing. Actual server offers33, and credential-free
key discovery succeeds (301-byte response/294-byte DER). Independent bounded
RSA1 envelope helper plus actual Swift TCP gate passed2/2, zero skips/failures,
3.164 seconds (`/tmp/aetherscreens-rsa1-prelude-live-tests-20261008.log`).
This is discovery/envelope acceptance only, not key trust, identity encryption,
mutual SRP authentication or proof of the native push failure's cause. Type30
defaults unchanged. Full native authentication/stream/physical gates remain open.

One-time post-first-pixel native arming experiment was rejected: actual1 case,
3 strict pattern assertions failed, zero unexpected failures,67.769s. First4K
image6.328s, one owned state, no subsequent pixels over60s despite a queued
post-frame arm. No periodic polling was introduced. The speculative flag/hook/
arming branch were removed; remote owned fixture stopped/removed, absence
verified. Log: `/tmp/aetherscreens-post-frame-arm-live-20261008.log`.
This does not prove the server's missing prerequisite; native streaming and
hardware fluidity remain unaccepted.

Actual region-aware comparison: ordinary RGB565 passed1/1, zero skips/failures,
67.741 seconds; first4K pixel image6.658 seconds, seven owned states,11 updates
covering the owned window, strict span/freshness passed. Owned-region intervals
median5.523s/max9.188s still do not demonstrate fluidity. Network was DERP132ms,
different from earlier conditions; no controlled performance A/B claim.
Native Observe received one owned state/image at6.606s then no new pixels over60s:
1 case/3 assertions failed, zero unexpected failures,68.009s. Actual command
diagnostics likewise showed only28 commands4 (unknown), no session-change11 or
heartbeat12. A separately opt-in normal-control wire mode also produced only one
image/state at6.590s and failed1 case/3 assertions (68.261s). No input was sent;
public defaults are unchanged. These now-valid coordinates strengthen the native
streaming failure evidence; they do not prove its cause.
Logs: `/tmp/aetherscreens-pattern-regions-live-20261008.log`,
`/tmp/aetherscreens-pattern-regions-native-live-actual-20261008.log`,
`/tmp/aetherscreens-native-status-pattern-live-20261008.log`,
`/tmp/aetherscreens-native-control-pattern-live-20261008.log`.
Targeted wire/status/reconnect/matcher17/17 passed; iOS Simulator build succeeded.
All owned remote fixtures were removed/absence verified. Final regression passed
448 cases,12 explicit environment skips,zero failures,130.229s:
`/tmp/aetherscreens-native-control-mode-full-core-20261008.log`.
Skipped hardware/live gates remain unaccepted. Native push/cursor/input, layout and physical fluidity remain
unaccepted; no release.

Controlled pattern follow-up found the earlier sampler's geometry invalid:
AppKit content x=118 with a side Dock, while samples assumed x=40. The fixture
now explicitly uses (120,40), confirmed by an actual geometry smoke, and
sampling positions follow that verified origin. QA also separates initialization
and pixel waiting, and returns immediately on a failed waiter.
The positioned ordinary probe received three owned-pattern states over at least
30 seconds, first genuine4K frame at12.531 seconds, but failed freshness:
last changed signature age21.488 seconds, threshold<20. Actual result1 case,
1 assertion failure, zero unexpected failures,74.303 seconds;48 callbacks are
not48 distinct images/FPS. Producer completed170 seconds with170 ticks/170 draws
and exit0. Logs: `/tmp/aetherscreens-positioned-standard-pattern-live-20261008.log`,
`/tmp/aetherscreens-positioned-pattern-producer-20261008.log`,
`/tmp/aetherscreens-positioned-pattern-geometry-smoke-20261008.log`.
Older zero-match probes cannot distinguish native push from wrong coordinates.
QA-only revision/owned-region diagnostics were added for future diagnosis;
compiled/local matcher passed1/1, but no actual diagnostic run yet. All owned
remote fixture files removed, absence verified. Production defaults unchanged;
continuous freshness, native cursor/push and hardware fluidity remain open.

Subsequent diagnosis/repair: ordinary pixel-body progress now renews the bounded
20-second stall deadline, capped at 60 seconds after connected. Metadata cannot
renew it; header-prefetched pixel bytes count once. Final targeted TCP/deadline
tests passed 6/6, zero skips/failures (42.117 seconds), including a genuine image
completed after 22 seconds. Actual ordinary RGB565 run passed 1/1, zero skips/
failures (89.399 seconds), first genuine 4K image at 28.3379 seconds and a further
60-second connected observation. 23 callbacks are not necessarily distinct
images/FPS; this run did not apply the owned-pattern matcher. Logs:
`/tmp/aetherscreens-standard-progress-deadline-tests-final-20261008.log` and
`/tmp/aetherscreens-standard-progress-live-final-20261008.log`.
Startup speed, native cursor/push, pattern continuity and physical fluidity are
still open. No release.

Final source regression: 447 tests, 12 explicit environment skips, zero failures,
150.185 seconds (`/tmp/aetherscreens-standard-progress-full-core-20261008.log`).
Generic iOS Simulator build succeeded, terminal exit 0
(`/tmp/aetherscreens-standard-progress-ios-build-20261008.log`). Skipped live and
hardware gates do not count as passed acceptance.

The explicit ordinary RGB565 controlled-pattern probe authenticated and connected
but received no desktop image before the existing first-frame deadline. Actual
result: 1 failure, zero unexpected failures, 29.883 seconds; pattern freshness
checks were not reached. Local matcher: 1/1 passed, zero skips/failures, 0.046
seconds. Logs: `/tmp/aetherscreens-standard-pattern-live-20261008.log` and
`/tmp/aetherscreens-standard-pattern-matcher-tests-20261008.log`.
This comparison does not isolate native encryption/push as the cause. Sharing
surface identity, geometry and transport latency remain unresolved, and full
Screens parity/physical smoothness remain unaccepted. Production defaults and
timeout gates are unchanged; no release.


## Target-binary evidence: auto-update flag means screen selection (2026-10-08)

Read-only inspection of the authorized Mac mini's actual screensharingd arm64e
image resolves the previously ambiguous diagnostic. Binary SHA256:
d533d282442b6e5c8c8e1f1cced931738ed9c8e1195aadf75b68b839c1479af0.
Local inspection only; no Apple implementation copied into the app.
At image addresses 0x100038da0..0x100038e80 the handler reads exactly16 bytes,
byte-swaps the screen ID at offset4 and rectangle at offsets8/10/12/14.
It stores selected_screen != 0xffffffff into the viewer field at offset0x2c
(0x100038e3c..0x100038e44). The diagnostic
HandleAutoFrameBufferUpdateMessage2 flag reads this same field at
0x10003c990 and0x10003c9cc. Thus flag0 is expected for our all/main sentinel;
it is not a rejected/disabled automatic subscription and not evidence of
the0x03 non-incremental handler. The earlier ambiguous log interpretation
is superseded by this target-version evidence.
The same path calls screen-change monitoring with argument1 at0x10003c8b8.
Static code proves the request path and field meaning, not successful RPC,
active capture delivery, sustained pixel changes, or UI fluidity. No live
configuration change was made during inspection. Comment clarified in
AppleFramebufferControl; wire bytes remain unchanged.
Next isolate monitor RPC results and display-transition capture callbacks;
do not repeat byte1 trials based on flag0. Native sustained update, cursor,
and complete physical Screens parity remain unaccepted. No release.


## Current full-core regression after physical-size and QA lifecycle fixes (2026-10-08)

Current swift test completed naturally with exit0:466 tests,16 explicit
environment-dependent skips,0 failures,146.167s (146.229s overall).
Log: /tmp/aetherscreens-current-full-core-20261008.log. Covers present physical
descriptor correction, test lifecycle, SRP parsing/proofs, transport, storage,
and input regressions. Does not exercise skipped real-device cases or prove
sustained native updates/UI rendering/physical smoothness. Scoped diff check
passed. Bounded12-minute remote log query found0 exact numeric monitor-RPC
result matches; absence does not imply RPC success or failure.
No protocol experiment retained, no commit/push/release; full goal active.


## Reusable read-only capture timeline QA (2026-10-08)

Added scripts/qa/inspect_native_capture_logs.py with trusted SSH to the
authorized Mac mini only,1..30 minute window,40s timeout,8MiB inspection limit,
exact static-format allowlist and validated timestamps. Emits only event names,
time and explicitly parsed numeric flag/RPC result; raw messages/stderr are
withheld, no credentials/pixels/clipboard/settings changes.
Actual20-minute query exited0 and emitted33 allowlisted events:
/tmp/aetherscreens-sanitized-capture-timeline-20261008.jsonl.
This confirms monitor-request logs at19:21:13.655446/19:21:14.323529 and
screen-selection flag0 at13.655754/14.326981, capture stop at19:22:03.796305.
No explicit monitor RPC result was observed; missing logs are inconclusive.
Python compile passed; adversarial synthetic privacy smoke verified unknown
formats, invalid timestamps and private text in known messages never appear,
while allowlisted numeric0/-5 are retained. No app wire behavior changed.
Still need actual capture-delivery and native sustained-update acceptance.
No commit/push/release; full goal remains active.


## Native sustained update gate passed with explicit first-screen subscription (2026-10-08)

Single-variable real test changed0x09 selected_screen from0xffffffff to0,
keeping reserved0/version1/measured mm/1920x1080 logical/3840x2160 backing.
Actual SRP owned-pattern gate PASSED1/1,0 skips/failures,60.654s:
/tmp/aetherscreens-first-screen-pattern-live-20261008.log.
Received8 known states spanning44.3898356667s; final change age0.4563157917s.
Server diagnostic flag1 corroborates explicit screen selection at
19:32:17.670489,18.341715,22.539836; monitor-request events precede each.
Log: /tmp/aetherscreens-first-screen-capture-timeline-20261008.jsonl.
This provides actual sustained pixel delivery evidence for this single-screen
experimental native profile; previous all/main-sentinel trials failed the
same acceptance gate. It does not prove universal server behavior/causation
for other versions,60FPS, input latency, cursor transitions or physical UI.
Retained fix: AppleFramebufferControl defaults to selected_screen0 for this
single-display configuration; optional explicit UInt32 remains representable
with network byte order. Public auth type30 selection stays unchanged; this
does not enable SRP by default. No periodic polling fallback added.
Producer85ticks/91draw passes, natural exit0:
/tmp/aetherscreens-first-screen-producer-20261008.log. Owned remote binary
and directory removed and absence verified, exit0. No clipboard/input changes.
Next repeat sustained gate with final helper, test cursor and frame cadence,
and complete current iOS/full-core validation. Full Screens/physical UI goal
remains active, no commit/push/release.


Final first-screen helper regression completed naturally exit0:21 tests,
0 skips/failures,57.597s. Includes AppleFramebufferControlTests (first-screen,
explicit UInt32/network order and invalid geometry), StreamingProgressTests
and AppleClipboardTransportTests. Log:
/tmp/aetherscreens-first-screen-regression-20261008.log. Earlier466 full-core
regression predates screen-selection correction; next current full regression
and iOS build remain required.


## Current first-screen app gates completed (2026-10-08)

After retaining explicit first-screen subscription, full swift test exited0:
467 tests,16 explicit environment-dependent skips,0 failures,150.015s
(150.069s overall). Log:
/tmp/aetherscreens-first-screen-full-core-20261008.log.
Fresh derived-data generic iOS build with CODE_SIGNING_ALLOWED=NO naturally
exited0/BUILD SUCCEEDED:
/tmp/aetherscreens-first-screen-ios-build-20261008.log.
Actual build retained warnings in RFBClient.swift about implicit strong versus
weak capture and KeyboardToolbarSettingsView.swift unreachable code; do not
claim zero warnings, signed device installation or hardware/UI acceptance.
Scoped diff check passed. This replaces the earlier466-test baseline for
current single-screen wire correction. Real sustained delivery proved in
one controlled60s trial; repeat/cursor/frame cadence/end-to-end latency and
physical iPhone fluidity still require acceptance. No commit/push/release.
Full Screens parity remains active and incomplete.


## First-screen repeat failed sustained gate; cadence instrumentation (2026-10-08)

Current helper unchanged (screen0), same measured physical/logical profile.
Repeat live gate exited1,1 assertion failure/0 skips,65.449s:
/tmp/aetherscreens-repeat-cadence-live-20261008.log.
Known states8,span7.072920875s,final age0.733663375s,15 transitions,
mean inter-change arrival0.471528058s,max2.297315125s. Span<30s fails existing
gate; did not relax it. All eight states arriving late is not sustained/real-time
proof. The earlier44s pass remains one trial only; stability is unaccepted.
Possible late/buffered delivery needs timestamp evidence, not assumed cause.
Concurrent read-only bounded capture-log query timed out/unavailable exit1;
no server reset/restart or fresh producer was started in response.
Producer85ticks/90draws auto-exited0; remote owned binary/directory removed
and absence verified exit0:
/tmp/aetherscreens-repeat-cadence-producer-20261008.log.
Added test-only constant-space transition count/mean/max arrival gaps;
unchanged images never count as transitions. Rejects nonfinite/regressing
timestamps. Initial matcher+arm checks4/4 pass0.042s:
/tmp/aetherscreens-native-cadence-tests-20261008.log.
Added first-known-pattern arrival since client.connect to next live diagnostics
(no actual measurement yet); final matcher test1/1 pass0.043s:
/tmp/aetherscreens-native-cadence-final-tests-20261008.log.
These metrics are received known-pattern cadence, not rendered FPS/input lag.
App source unchanged since prior467-test full regression and iOS build; only
QA instrumentation changed. Next isolate initial delivery from steady-state
update cadence; native stable push/cursor/full physical fluidity remain open.
No commit/push/release; full goal active.


## Initial known-pattern delay measured without concurrent log query (2026-10-08)

Same current single-screen profile, measured mm/logical1920/backing3840; no
concurrent remote log query during session. Live test exited1,2 failures/0
skips,65.059s:
/tmp/aetherscreens-arrival-timing-live-20261008.log.
First known-pattern arrival after client.connect58.563294792s; states1,
span0,age1.494775042s,0 transitions. This proves late first recognized owned
pattern in this trial, not raw first-pixel time or which stage consumed time.
Do not infer authentication versus transfer versus decode delay without stage
timestamps, nor label this solely an auto-subscription freeze.
Observed73 native plaintext record bodies totaling2287780 bytes; no timestamped
network-throughput claim. Earlier passing trial196 bodies/5388637 bytes/54
pixel rectangles(two4K); earlier failing repeat93 bodies/2601126 bytes/21
pixel rectangles(one4K). These totals alone do not prove cause.
Pre-session tailscale ping returned DERP(baizhiedu)651ms; direct establishment
failed(exit1). LAN5900 nc probe ultimately exited1. No route/daemon/settings
changed. Owned producer85ticks/89draws natural exit0:
/tmp/aetherscreens-arrival-timing-producer-20261008.log. Remote owned binary
and directory removed/absence verified exit0. App/QA source unchanged this
trial, prior current full467/iOS build still apply.
Next add connected/first-pixel/record-duration timing to separate handshake,
initial receive/decode and steady-state cadence; stable native/cursor/full
physical UI parity remain open. No commit/push/release; goal remains active.


## Session versus pixel stage timing exposes incomplete initial frame (2026-10-08)

Added test-only thread-safe stage timestamps connected/first record/first pixel
rectangle/first frame. Finite nonnegative first arrival retained; repeated
events cannot overwrite startup measurement. Synthetic stage test1/1 pass
0.001s, exit0: /tmp/aetherscreens-srp-stage-timing-tests-20261008.log.
This is callback timing, not isolated CPU decode profiling.
Actual controlled60s gate exited1/3 assertions/0 skips,63.194s:
/tmp/aetherscreens-stage-timing-live-20261008.log. Elapsed from client setup:
connected16.147912s,first native record19.475381s,first pixel rectangle
header25.149447s; no first-frame callback by deadline. No known pattern
was received (states0/span0/ageInfinity). This falsifies authentication as the
only delay in this trial; actual rectangle header is not a completed desktop.
Next inspect declared compressed rectangle size versus actual payload arrival
and decode dispatch; do not claim networking/decoder cause from indirect logs.
Producer85ticks/90draws natural exit0:
/tmp/aetherscreens-stage-timing-producer-20261008.log. Remote owned binary
and directory removed/absence verified exit0. No clipboard/input/settings
changes, no concurrent remote unified-log traffic during this trial.
Updated stale document checkpoints from442/369 counts and no-native-pixels
claims to current app-source467-test/iOS evidence and explicitly unstable
native sustained gate. App source unchanged; new instrumentation/test has
targeted verification, prior full suite predates this test-only addition.
No commit/push/release. Full Screens/physical-fluidity goal remains active.


## Native payload completion/decode diagnostics reveal tiny first frame (2026-10-08)

Added internal numeric-only native ZRLE hooks for compressed payload readiness
and decode worker elapsed duration. Bound to captured connection; reentrant
disconnect/reconnect is rechecked before decode scheduling and framebuffer
commit. No timestamp cost for ordinary decoding when hooks are unset.
ZRLE transport + stage tests33/33 pass,0 skips/failures,10.543s/exit0:
/tmp/aetherscreens-native-payload-progress-tests-20261008.log.
Actual60s pattern gate exited1 with1 assertion failure/0 skips,64.759s:
/tmp/aetherscreens-payload-progress-live-20261008.log. Eight known states
span6.337899s,final age1.524661s;12 transitions,mean0.528158s/max1.071455s.
Connected14.891592s,first native record17.690505s,first2x2 rectangle/payload
18.830466/18.830471s,payload ready18.830475s,decode complete/first frame
18.830560/18.830579s. Thus first-frame callback can mean a tiny pixel update,
not an entire usable desktop; no new completion claim from this callback.
Later4K ZRLE rectangle declared and received2285924 bytes; its debug decode
worker elapsed1.075819s. First known owned pattern52.174810s after connect.
Log label originally said CPU elapsed; this is systemUptime wall time including
preemption, not pure CPU profiling. Corrected source label to worker elapsed.
Need per-full-frame receive time and optimized-build profiling before attribution
or implementing tile optimizations. No desktop payload persisted.
Producer85ticks/89draws auto-exit0, owned remote binary/directory removed and
absence verified exit0: /tmp/aetherscreens-payload-progress-producer-20261008.log.
Earlier467 full regression/iOS build predates these internal core hooks; targeted
33-test check is current, full-core/iOS gates need refreshing. No protocol byte
change, no commit/push/release. Stable native/cursor/physical UI goal open.


## RGB565 decode lookup optimization verified (2026-10-08)

Added independent4K RGB565 raw-tile fixture covering all65536 wire colors,
partial final tile rows and three persistent-zlib frames. Expected BGRA comes
from advertised channel maxima, never the decoder or its lookup. Every output
byte compared. Before-change release test1/1 passed1.755s/exit0:
/tmp/aetherscreens-rgb565-baseline-release-20261008.log. Decode milliseconds
[62.166375,64.214375,61.200500], median62.166375.
Retained lazy immutable256KiB RGB565 color lookup in ZRLE raw/palette/plain-RLE
pixel conversion, preserving endian/color output. Full-color path does not
initialize the table. Release decoder suite16/16 passed3.811s/exit0:
/tmp/aetherscreens-rgb565-lookup-release-20261008.log. Same fixture durations
[51.650000,51.701208,54.014250], median51.701208 (about16.8% reduction in this
synthetic benchmark, not end-to-end FPS or proof of real-desktop cause).
Release ZRLE transport regression32/32,0 skips/failures,3.351s/exit0:
/tmp/aetherscreens-rgb565-lookup-transport-release-20261008.log. Covers parser,
malformed inputs, reconnect and RGB565 transport behavior.
Current generic unsigned iOS build BUILD SUCCEEDED/exit0:
/tmp/aetherscreens-rgb565-lookup-ios-build-20261008.log. Existing compiler
warnings retained, no zero-warning or signed-device acceptance claim.
Scoped diff check passed. Full core suite predates internal numeric hooks and
this optimization/new fixture; refresh remains required. Native real-stream
startup, stable cadence/cursor and physical30-minute fluidity remain open.
No desktop capture, network/settings mutation, commit/push/release. Goal active.

## Optimized native full-desktop timing (2026-10-08)

Two timing regression cases passed in release configuration. Actual SRP/native
owned-pattern trial passed1/1 with zero skips/failures in60.561s. Connected1.095s,
first record2.711s, first complete4K ZRLE payload declaration5.125s, receive
completion10.048s, decode completion10.083s, first frame10.087s. Receive took
4.923s while worker decode took0.035s; these are wall durations, not CPU time.
Eight known states and49 transitions spanned49.204s, mean gap1.004s, maximum
gap3.622s, last age0.721s. This improves the diagnostic evidence relative to
earlier failed runs but does not prove repeatability, rendered FPS, cursor or
physical UI fluidity. No protocol default, server settings or acceptance gates
were changed. Evidence: `/tmp/aetherscreens-fulltiming-live-20261008.log`.
Remote producer exited0 at tick85/draw89; exact owned binary and directory
removed, absence and no running pattern verified via trusted SSH exit0.

## Fragmented encrypted receive regression (2026-10-08)

Added a4MiB record integrity case using receive fragments1,2,113,8192,65536 bytes
so records cross fragment boundaries and a receive can contain several records.
All128 bodies are checked byte-for-byte and retained record bytes remain bounded
by65522. Release record suite13/13 passed, zero failures/skips,0.026s. Fragmented
reassembly285 fragments took3.382ms; existing complete-record case3.823ms.
These synthetic durations exclude socket, downstream RFBClient buffering and
presentation and cannot prove a live transport bottleneck. They do indicate
record decryption/reassembly alone did not reproduce the observed4.923s receive
interval. No transport settings/defaults changed. Evidence:
`/tmp/aetherscreens-fragmented-record-release-20261008.log`.

## Full-desktop socket arrival window instrumentation (2026-10-08)

Internal SRP test now attaches the existing onBytesReceived callback and stores
only numeric byte/event counts and maximum arrival gap while the first full
desktop ZRLE payload is pending. Initial wait and tail wait count toward the gap.
Previously prefetched bytes are excluded, so it is not exact payload throughput.
Invalid, regressing or post-completion events do not renew the window. Debug
timing regressions3/3 passed without skips/failures,0.001s. No production source
or network settings changed. The new window has no real-stream data yet; the
earlier60-second pass remains earlier evidence, not validation of these hooks.
Evidence: `/tmp/aetherscreens-receive-window-timing-tests-20261008.log`.

## Actual full-desktop arrival window (2026-10-08)

Release timing preflight3/3 passed. Second optimized owned-pattern60-second
trial passed1/1, no failures/skips,60.562s. Connected0.643s;2x2 patch first
frame2.958s;full4K payload declared3.164s/received6.707s/decoded6.738s and first
known pattern6.741s. Receive window3.543s captured402 arrivals/2302566 wire bytes
and maximum gap1.178s; bytes exclude earlier prefetch and include encrypted
framing, so this is not exact payload throughput. Worker decode31ms. Eight
states/55 transitions spanned52.455s,mean0.954s/max3.901s,last age0.809s.
Two consecutive optimized trials support continuity but cannot establish
consistent fluidity or distinguish network from server-side delays. Evidence:
`/tmp/aetherscreens-arrival-live-20261008.log`.
Producer exited0,tick85/draw90; exact owned remote binary/directory removed,
absence and no active pattern process verified via trusted SSH exit0.

## Post-run route/capture correlation (2026-10-08)

Read-only allowlisted Mac mini capture log inspection exited0. Latest run
monitoring requested20:20:42.425/42.958, capture_stop20:21:40.055 near test end.
No intervening stop is logged; this does not prove absence of server stalls or
correct RPC results. Post-run tailscale ping returned DERP(baizhiedu)427/22/72ms
and exited1 because direct was not established; successful pongs prove mesh
reachability, not direct reachability. Known LAN target192.168.50.226 ports22 and
5900 both failed3-second connect probes. Thus no LAN-vs-mesh causal comparison
is available presently. No service/network/security settings changed. Evidence:
`/tmp/aetherscreens-arrival-capture-events-20261008.jsonl`,
`/tmp/aetherscreens-current-mesh-ping-20261008.log`,
`/tmp/aetherscreens-lan-reachability-20261008.json`.

## Scroll cap overflow correction (2026-10-08)

NativeScrollAccumulator previously capped emitted ticks at64 but retained all
excess whole ticks; a subsequent zero-delta event could emit another64 or delay
an opposite-direction scroll. It now retains only fractional remainder after
each event, bounds before integer conversion, and rejects nonfinite deltas.
Existing precise-wheel accumulation/direction and new cap/reverse/zero/invalid
regressions2/2 passed, no failures/skips. These target pure accumulator functions
only and are not native GUI/hardware smoothness acceptance. Evidence:
`/tmp/aetherscreens-scroll-overflow-tests-20261008.log`.

## Bounded two-finger wheel callbacks (2026-10-08)

Extracted ScrollWheelAccumulator as shared pure calculation. iOS two-finger
scroll now keeps its8-point step and fractional remainder but caps each axis to
64 wheel pulses per callback rather than an unbounded loop. Invalid divisor or
nonfinite deltas produce no pulses. Existing gesture-began reset, drag guard and
local navigation branch remain. Three pure scroll regressions passed, no skips
or failures. Initial iOS compile correctly caught the macOS-only declaration;
moving the helper to shared source fixed this and final generic unsigned iOS
build passed. No host GUI automation or physical iPhone acceptance performed.
Evidence: `/tmp/aetherscreens-touch-scroll-bounds-tests-20261008.log` and
`/tmp/aetherscreens-touch-scroll-bounds-ios-build-20261008.log`.

## Left-drag to local-pan handoff (2026-10-08)

MacNativeInputView previously returned from mouseUp while isPanning, even if
the preceding mouseDown had sent a remote left-button press. It now remembers
the last down/drag remote coordinate and emits a release when entering local
pan, then clears the pan anchor. Normal mouseUp clears the remembered drag.
No release is sent for a mode change when no remote left drag was tracked.
macOS swift build passed, diff check passed. No native host GUI tests were run;
actual remote/UI mode-switch acceptance remains pending. Evidence:
`/tmp/aetherscreens-pan-drag-release-build-20261008.log`.

## macOS input focus cleanup (2026-10-08)

MacNativeInputView now releases remembered keySyms/modifiers and left drag on
resignFirstResponder, window didResignKey, window movement and SwiftUI teardown.
Key releases are deduplicated; state clears before callbacks to tolerate
reentrant focus changes. Pan anchor, wheel remainder and marked text clear.
Window publisher uses weak view capture. macOS build passed and existing wire
focus-release case1/1 passed; this transport case does not cover the newly added
AppKit lifecycle hooks. Native remote UI/window-switch acceptance is pending;
no host GUI automation was run. Evidence:
`/tmp/aetherscreens-mac-focus-release-build-20261008.log` and
`/tmp/aetherscreens-focus-release-wire-tests-20261008.log`.

## Thumbnail refresh duplicate work removal (2026-10-08)

DeviceCardView previously assigned a newly cached image on each notification
and incremented thumbnailRevision, immediately launching another async lookup
and animated assignment of that same image. Cache hits now use one identity-
guarded update; only cache misses revise the load task. Task completion uses
the same guard and existing cancellation/visibility/fresh-cache checks remain.
Reduce Motion still suppresses animation. macOS and generic unsigned iOS builds
passed; async thumbnail storage regressions5/5 passed, zero skips/failures.
These checks do not prove native card animation/large-library performance.
Evidence: `/tmp/aetherscreens-thumbnail-refresh-build-20261008.log`,
`/tmp/aetherscreens-thumbnail-refresh-storage-tests-20261008.log`,
`/tmp/aetherscreens-thumbnail-refresh-ios-build-20261008.log`.

## Actual Mac mini AppKit input regression (2026-10-08)

Built the XCTest bundle without running native view tests on the host and
transferred the owned bundle to the authorized Mac mini temporary directory.
Its installed xcrun/xctest ran exactly MacNativeInputTests:8/8 passed, no
failures/skips,0.011s. New view cases exercise mouseDown -> entering pan ->
release at matching coordinates exactly once; flags/keyDown -> cleanup ->
keyUp releases each key once and clears composition. Existing Unicode/key
release/scaled-coordinate/wheel cases passed. No real window focus switching
or long-duration hardware smoothness is proved by these synthetic event cases.
Evidence: `/tmp/aetherscreens-macmini-input-lifecycle-tests-20261008.log`.
Owned remote test bundle/directory removed after terminal test success; exact
path absence verified by remote Python exit0. No host native view test ran.

## Mac mini window callback regression (2026-10-08)

Added an undisplayed AppKit window case to test the actual registered Combine
window publisher and viewDidMoveToWindow detachment. A posted didResignKey
notification releases a recorded Escape key; removing the input view releases
a newly pressed Escape; repeat cleanup is idempotent. This uses synthetic
notification/events, not a real system focus switch. Host built tests only;
authorized Mac mini xcrun/xctest ran MacNativeInputTests9/9 passed, no failures
or skips,0.075s. Evidence:
`/tmp/aetherscreens-macmini-window-lifecycle-tests-20261008.log`.
Owned remote test bundle and directory removed; exact path absence checked
by trusted SSH/Python exit0 after terminal test success.

## iOS canvas focus drag release (2026-10-08)

RemoteTouchView now calls releaseDrag in addition to releaseHardwareKeys after
successful resignFirstResponder. This addresses dragging left behind when
focus transfers away from the canvas. Existing dismantle/window-detach and
local navigation cleanup remain. Generic unsigned iOS build passed; underlying
TrackpadEngineTests9/9 passed, zero failures/skips. These pure engine cases do
not prove the UIKit callback or hardware/IME transition; phone acceptance remains
pending. Evidence: `/tmp/aetherscreens-ios-focus-drag-release-build-20261008.log`
and `/tmp/aetherscreens-ios-focus-drag-engine-tests-20261008.log`.

## Actual Mac mini full-core regression and credential gate (2026-10-08)

Current owned XCTest bundle full run completed477 tests,16 explicit environment
skips,3 assertion failures in149.782s. All three belong to
DeviceStoreTests.testMigratesLegacyKeychainPasswordOnRead, beginning with failed
save of its legacy synthetic fixture before migration. Standalone retry likewise
failed1 case/3 assertions. Read-only Security default-Keychain status returned
success with unlocked=false/readable=true/writable=false. This is consistent
with the failed persistence setup; migration remains unverified here and the
full run is not green. No Keychain unlock, credential disclosure or system
settings change was attempted. Remaining completed cases have no failures;
this still does not imply physical UI/long-session/Screens parity acceptance.
Evidence: `/tmp/aetherscreens-macmini-full-core-regression-20261008.log`,
`/tmp/aetherscreens-macmini-keychain-migration-recheck-20261008.log`,
`/tmp/aetherscreens-macmini-keychain-status-20261008.log`.
Owned remote test bundle/archive/directory removed and exact path absence
verified via trusted SSH/Python exit0 after both processes completed.

## Non-destructive credential replacement (2026-10-08)

KeychainStore.writeItem previously deleted before SecItemAdd; an add failure
could lose the previous persistent value. It now updates the exact service/
account in place, adds only on errSecItemNotFound, and retries update when a
concurrent add reports duplicate. Lock/access failures stop without delete.
Four injected-status branch tests passed, no skips/failures, and generic
unsigned iOS build passed. This does not validate real Keychain migration or
save-failure UI; the existing memory fallback remains unchanged. Official
API grounding: https://developer.apple.com/documentation/security/updating-and-deleting-keychain-items
Evidence: `/tmp/aetherscreens-keychain-upsert-tests-20261008.log` and
`/tmp/aetherscreens-keychain-upsert-ios-build-20261008.log`.

## Credential-save failure feedback (2026-10-08)

DeviceStore add/update configuration and updatePassword now return durable
credential write status; process-local fallback remains available. Device list
add/discovered add/editor show existing warning banner when config is saved
but password persistence fails. Session VNC and Mac-account remember paths
publish a dismissible English/Chinese top warning and keep current entered
credentials flowing through authentication. Password update logs success only
when Security persistence succeeds. Injected-denial/store/session tests6/6
passed and unsigned generic iOS build passed. These are logic/build evidence,
not native warning rendering or actual writable-Keychain migration acceptance.
Evidence: `/tmp/aetherscreens-session-save-notice-tests-20261008.log`,
`/tmp/aetherscreens-session-save-notice-ios-build-20261008.log`; prior store/UI
checkpoint `/tmp/aetherscreens-credential-save-report-tests-20261008.log`.
