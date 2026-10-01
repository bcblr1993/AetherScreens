# Screens alignment and full acceptance audit

Audit date: 2026-10-01. Existing notarized candidate: `2eea898`. Reference: [Screens 5 official feature index](https://help.edovia.com/en/screens-5/features/).
This is a completion checklist, not a claim of parity. Unit tests, simulator
screenshots and signed builds do not replace physical input/gesture acceptance.
The release remains a draft until the user has reviewed the completed acceptance.

| Requirement | Current implementation and evidence | Remaining work |
| --- | --- | --- |
| Mac account / VNC connections | ARD type 30 and VNC implemented; real Mac authentication, frame and 60-second session passed. iPhone 12 Pro received the requested target Mac's desktop; user confirmed connection. | iPhone 16 Pro Max target session; sustained physical-device interaction |
| Interactive shortcut toolbar | Sticky modifiers, common shortcuts, F1-F12; Mac F8 observed remotely | Physical iPhone modifier/shortcut delivery and narrow layouts |
| Touch / trackpad gestures | Native iOS recognizers now wire immediate clicks, secondary/middle clicks, held-button dragging, two-axis scrolling and pinch zoom. Cursor movement uses remote-pixel scaling, smooth acceleration and an immediate UIKit layer. Core tests cover click release, scaling and engine drag state. English/Chinese iOS simulator flows additionally inspect packets received for single/double/right/middle click, held-button drag, direct touch, pinch coordinate changes and Observe suppression; both flows pass without runtime warnings. Actual loopback TCP tests additionally verify scrolling preserves held buttons, delayed wheels use the latest released-button state/coordinates, and Observe cancels old work without delaying resumed control behind the cancelled backlog. | Physical tap, secondary click, drag, pinch, scroll and mode changes; Apple server combined scroll/drag acceptance; perceived responsiveness; native two-axis scroll, secondary/middle drag indicators, three-finger shortcuts, two-finger fullscreen toggle and edge/hot-corner gestures |
| Hardware pointing devices | Mac native mouse, drag, context menu and wheel passed | iPad pointer and hardware keyboard acceptance |
| International keyboards / dictation | UTF-8 text drawer and Chinese keysyms passed; NSTextInputClient composition tests | Real IME; supplementary-plane characters; dictation workflow |
| Clipboard transfers | Local clipboard insertion passed; extended protocol parser tests | Actual bidirectional clipboard and rich content transfer; insertion is not parity |
| Curtain privacy mode | System lock shortcut and password restoration passed | Actual remote display blackout while remaining unlocked; lock is not parity |
| Display selection | ExtendedDesktopSize server layout decoding, stable screen IDs, selected-monitor crop and bounded input coordinates; no monitor-count inference from framebuffer aspect ratio. Actual TCP tests cover layout-only updates, rejected resize payloads and subsequent raw frames, plus framebuffer resizing. | Apple server layout negotiation and physical per-display acceptance; target Mac currently has one online LG HDR 4K display |
| Adaptive image quality | Raw, Zlib and CopyRect decoding; Metal rendering | Network-dependent quality/compression selection and measured responsiveness. Initial-frame progress is now suppressed during streaming; regression tests prove fewer UI publications, not physical responsiveness |
| Observe / control modes | Explicit Observe Only mode; real Mac frames continue while text, clicks, wheel and clipboard writes are blocked; held modifiers released and control restored. iOS retains local zoom/pan while Observe suppresses received pointer input; English/Chinese controlled viewport flows pass. Pan separately blocks pointer input, cancels queued wheels and preserves keys; actual TCP tests cover nested Observe transitions and responsive scrolling afterward | Physical iPhone toggle and input suppression acceptance |
| Reconnect / session recovery | In-session reconnect clears input and restores remote typing. English/Chinese simulator socket-interruption tests pass with a new TCP connection, fresh frame, retained zoom/touch mode and received fresh modifier/key events. Core tests reject ended-session callbacks and old VNC/ARD password replies | Physical iPhone and Apple server recovery; real phone network interruption |
| Quick connect / session selection | Temporary account/VNC requests and optional saving; installed Mac account connection and received typing passed; iPhone simulator validation, save toggle and error/disconnect flow passed | Physical iPhone quick connection; explicit active/background session choice |
| Secure connections / SSH keys | External Tailscale transport, device import client and Keychain | Real Tailnet route/import acceptance; integrated SSH tunnel/key handling |
| File transfers | No transfer implementation | Bidirectional transfer and received-file verification |
| Data / credential synchronization | Local persistence and Keychain migration | Cross-device synchronization and conflict handling |
| Toolbar customization / keyboard options | Per-computer button size, top/bottom position, visibility, ordering and multiple spacers implemented. Installed Mac position/size/menu switching, hiding, moving, adding spacers, relaunch persistence and remote arrow/delete delivery passed. iPhone 17 simulator settings flow passed; final English/Chinese flows on a 375-point iPhone 13 mini simulator passed and screenshots were inspected. English/Chinese customization flows on both physical iPhones also passed (2/2 each, no runtime warnings), using an invalid temporary destination. Temporary settings remain in memory; hiding a held modifier releases it. | Physical iPhone live toolbar/key delivery; keyboard mapping preferences and cross-device synchronization |
| On-disconnect actions | Disconnect only | Per-connection Mac hot-corner, lock and logout actions before disconnect; proof on an isolated acceptance desktop |
| URL schemes / automation | Mac/iOS bundles register aetherscreens and alternate vnc handlers. Saved identifier/name/address and temporary account/VNC links support explicit Observe selection. Core validation and iOS system URL delivery preserve a Quick Connect draft, open the queued Observe session after dismissal, disable keyboard control and avoid saving the temporary computer. | Installed Mac and physical iPhone routing/copy-link acceptance; SSH/SSH-key and guest semantics with real server/tunnel handling; applicable shortcuts/widgets |
| AirPlay / external display / Pencil | Not implemented | iOS display routing and peripheral acceptance |
| Mac multi-window sessions | Independent native windows; real Mac concurrent account sessions, minimizing/restoring, saved-session reuse, Observe isolation and closing one window while continuing remote input in the other passed. Numbered window/menu titles distinguish the same computer. | iOS active/background session selection remains in its separate requirement |
| Wake-on-LAN | Packet construction tests and send-success notice | Real wake verification on an appropriately configured sleeping Mac |
| Discovery / device library / diagnostics | Bonjour discovery visible; add/edit and diagnostics UI covered | Saved devices now use a neutral Saved badge; Tailnet status is distinguished from screen-sharing reachability. Remote API error/recovery acceptance remains. |
| UI consistency / branding | App icon assets on Mac/iOS/site, grouped account forms and readable input bar | Full narrow / empty / loading / error / modal audit on physical devices |
| English / Simplified Chinese | Implemented; core/catalog tests, Mac switch, simulator persistence/narrow layouts and both physical iPhones' language switch/persistence passed. Account prompt passed both simulator languages. | Remaining whole-flow physical-device layout audit |
| Release readiness | Latest core suite: 125 tests, 5 environment skips, no failures. Current Mac Release and signed iOS device Release builds pass; prior iOS simulator test builds pass; iOS system URL flow passes with no runtime warnings. URL integration cbfe9db, pointer transport 3178a3a and native gesture/UI integration 7b93500, session recovery d286a69 and streaming progress 951e0c3 and viewport navigation d30c4f8 and Pan pointer gate 4b6629e passed CI, as did prior input/resize commits; the earlier 73-test candidate passed notarization, mounted DMG and installed input | Current server-display-layout integration CI and physical acceptance; complete functional gates and user review; no public release yet |

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
