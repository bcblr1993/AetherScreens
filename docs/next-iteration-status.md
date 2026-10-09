# Next iteration implementation status

The agreed sequence remains interaction stability, connection diagnostics,
bidirectional plain-text clipboard, actual bandwidth/quality behavior, and
mobile acceptance/distribution preparation. No new public release is authorized
by this implementation work alone.

## Implementation checkpoints (chronological, 2026-10-08)

Overall Screens parity remains in progress. This is a chronological record;
newer entries at the end supersede earlier implementation gaps and scoped test
counts. A codec/build/fixture pass never establishes actual-server or physical
UI acceptance. Full-suite failures remain open until an explicit newer full
run proves otherwise.

- Read-only authorized Mac mini static inspection located native file-copy
  handler/helper entry points and receiver session/version/item-message names.
  No helpers launched or packets sent; byte grammar remains unknown. Detailed
  evidence and required interoperability gates are in native-file-transfer-research.md.
  This narrows protocol investigation but does not establish transfer capability.

- Native file manifest path groundwork rejects absolute paths, dot traversal,
  empty segments and NUL; limits depth/length while preserving Unicode, literal
  percent sequences and valid Apple backslash filenames. FileTransferRelativePath
  tests3/3 passed, no failures/skips. URL construction provides lexical containment
  only: filesystem writer still needs symlink-safe creation; no transfer writer
  or native wire format is implemented. Source review confirms existing Apple
  control/clipboard handlers do not implement file messages. Public experimental
  Apple high-performance specification reviewed; no verified file-copy frame
  grammar was obtained. Evidence:
  `/tmp/aetherscreens-file-transfer-path-tests-20261008.log`.

- Native file-transfer groundwork: FileTransferJob models acknowledged byte
  progress, conflict confirmation, cancellation, transport pause/resume with
  confirmed offsets, and destination finalization. Per-attempt tokens reject
  callbacks from replaced/cancelled transports. Four regressions passed with
  no failures/skips, including empty/UInt64-sized metadata. This module is not
  integrated with a native wire transport or drag/drop UI: no actual file
  upload/download capability is claimed. SSH direct-TCP forwarding is not a
  substitute for native Screens file drag/drop. Reference rechecked:
  https://help.edovia.com/en/screens-5/features/file-transfers
  Evidence: `/tmp/aetherscreens-file-transfer-job-tests-20261008.log`.

- Saved-device thumbnail capture now uses session-local5-second time cadence
  instead of every60 frame callbacks. First frame captures immediately; each
  start/reconnect resets cadence, while explicit end snapshots keep their
  existing scheduler path. This avoids frame-rate-dependent snapshot requests
  and missed initial thumbnails on static desktops. Scheduler/cadence suite4/4
  passed with zero failures/skips; generic unsigned iOS build passed. Actual
  image conversion cost, CPU and large-library smoothness remain unmeasured.
  Evidence: `/tmp/aetherscreens-thumbnail-cadence-tests-20261008.log`,
  `/tmp/aetherscreens-thumbnail-cadence-ios-build-20261008.log`.

- Performance metric publication now skips unchanged FPS/bandwidth/latency/
  optimal values. Latency samples have revision guards so an older queued
  publication cannot replace a newer main-thread sample. PerformanceMetrics
  regression13/13 passed, no failures/skips, including100 identical latency
  samples with zero additional UI notifications. This measures notification
  behavior, not end-to-end frame rate, CPU reduction or animation smoothness.
  Evidence: `/tmp/aetherscreens-metrics-publication-tests-20261008.log`.

- Cursor presentation now distinguishes explicit zero-dimension hiding from
  nonhidden shapes without renderable images. macOS restores its native arrow;
  iOS restores its existing arrow fallback for image failures. Explicit hiding
  and valid cached bitmaps remain unchanged. Mac mini cursor suite6/6 passed,
  no failures/skips, and remote fixtures were cleaned. Build and generic
  unsigned iOS build passed. Vendor/live cursor and physical presentation remain
  unaccepted. Evidence: `/tmp/aetherscreens-cursor-fallback-build-20261008.log`,
  `/tmp/aetherscreens-cursor-fallback-native-tests-20261008.log`,
  `/tmp/aetherscreens-cursor-fallback-ios-build-20261008.log`.

- Added isolated legacy-Keychain migration regressions using internal read/write/
  delete hooks: denied destination writes retain the source and keep its value
  available in the process cache; successful migration writes the destination
  before source deletion. KeychainWriteTests8/8 passed, zero failures/skips.
  Normal Security API paths are unchanged; these regressions do not replace
  actual migration on a writable Keychain or clear the failed full gate.
  Evidence: `/tmp/aetherscreens-legacy-migration-denial-tests-20261008.log`.

- Latest refreshed actual Mac mini full-core gate:490 tests,16 explicit
  environment skips,3 assertions failed in the single legacy-Keychain migration
  case,150.593s. Other completed cases reported no failures. Read-only status
  again reports default Keychain locked/not writable; fixture save fails before
  migration. Full gate remains failed, with physical/live gates still open.
  Remote test bundle/archive/owned directory were removed and absence verified.
  Build passed. Evidence:
  `/tmp/aetherscreens-core-regression-refresh-build-20261008.log`,
  `/tmp/aetherscreens-macmini-full-refresh-tests-20261008.log`,
  `/tmp/aetherscreens-macmini-keychain-refresh-status-20261008.log`.

- Connection recovery content now scrolls within available height, reserving
  top-control space. Retry/password actions fall back to vertical arrangement
  when their intrinsic horizontal width does not fit. Status/name/host/error
  copy uses scalable semantic fonts. macOS and generic unsigned iOS builds
  passed; phone landscape, long error copy and accessibility text-size visual
  acceptance remain pending. Evidence:
  `/tmp/aetherscreens-recovery-responsive-build-20261008.log`,
  `/tmp/aetherscreens-recovery-responsive-ios-build-20261008.log`.

- Terminal session states now share local input cleanup: ordinary disconnect
  also clears sticky modifiers and all engine mouse buttons, and both failure
  and disconnect replace native input view identity. Synthetic state callback
  regression1/1 passed for both terminal states; existing keyboard/focus-release
  wire regression1/1 passed. Generic unsigned iOS build passed. Real disconnect
  lifecycle and remote held-input acceptance remain pending. Evidence:
  `/tmp/aetherscreens-session-input-recovery-tests-20261008.log`,
  `/tmp/aetherscreens-session-recovery-wire-tests-20261008.log`,
  `/tmp/aetherscreens-session-input-recovery-ios-build-20261008.log`.

- Connection recovery UI is now presented over retained remote frames during
  failure/disconnection and active reconnect phases. A stale image no longer
  suppresses error details and retry/password/log actions. Disconnected state
  no longer shows a waiting spinner; initialization keeps its existing first
  frame HUD without an additional connecting overlay. macOS and generic
  unsigned iOS builds passed. Native failure/reconnect visual and interaction
  acceptance remain pending. Evidence:
  `/tmp/aetherscreens-connection-recovery-overlay-build-20261008.log`,
  `/tmp/aetherscreens-connection-recovery-overlay-ios-build-20261008.log`.

- macOS edge-follow now accounts for pending pan requests between viewport
  layout updates. Consecutive samples clamp against the projected viewport;
  click/release/wheel map through pending pan without initiating another pan.
  Incoming viewport updates reset projection. Mac mini native view suite12/12
  passed, zero failures/skips, including consecutive edge samples and layout
  catch-up without double mapping; build passed and remote fixtures cleaned.
  Rendered continuous-pointer acceptance remains pending. Evidence:
  `/tmp/aetherscreens-mac-edge-burst-build-20261008.log`,
  `/tmp/aetherscreens-mac-edge-burst-native-tests-20261008.log`.

- macOS native pointer motion/drag now receives the actual viewport in canvas
  coordinates and applies bounded edge-follow. Window-coordinate movement
  avoids treating canvas movement as physical input; mapped coordinates account
  for the requested pan. Click/release/wheel do not initiate following; local
  pan mode bypasses it and focus cleanup resets the previous pointer sample.
  Mac mini view-unit suite11/11 passed with zero failures/skips and scoped
  fixtures cleaned. Build passed. Actual rendered edge-follow latency and
  continuous hardware input still require acceptance. Evidence:
  `/tmp/aetherscreens-mac-edge-follow-build-20261008.log`,
  `/tmp/aetherscreens-mac-edge-follow-native-tests-20261008.log`.

- iOS hardware pointer movement now uses the same bounded edge-follow geometry
  as finger trackpad movement. Canvas origin updates before absolute pointer
  mapping to retain pointer alignment. Stationary/first samples do not pan;
  hover departure and drag cleanup reset previous position. Geometry suite5/5
  and generic unsigned iOS build passed. Physical edge-follow smoothness remains
  pending; this is not macOS hardware edge-follow acceptance. Evidence:
  `/tmp/aetherscreens-hardware-edge-follow-geometry-tests-20261008.log`,
  `/tmp/aetherscreens-hardware-edge-follow-ios-build-20261008.log`.

- TrackpadEngine wire coordinates now clamp to the last pixel (dimension - 1)
  and UInt16 capacity for motion, clicks and wheel pulses. Nonfinite geometry
  produces safe zero coordinates rather than a conversion trap. Logical
  viewport cursor geometry remains unchanged. Engine regression11/11 passed
  with zero failures/skips, covering edge events and oversized/invalid geometry.
  This does not establish visual edge-follow or physical-device acceptance.
  Evidence: `/tmp/aetherscreens-pointer-wire-bounds-tests-20261008.log`.

- iOS drag cleanup now clears local hardware/touch ownership before outgoing
  callbacks and releases the complete engine button chord once. Engine
  regression10/10 passed, including recursive cleanup without duplicate
  release; generic unsigned iOS build passed. These tests do not validate
  UIKit focus callbacks or physical pointer behavior. Evidence:
  `/tmp/aetherscreens-ios-chord-release-tests-20261008.log`,
  `/tmp/aetherscreens-ios-chord-release-build-20261008.log`.

- macOS mouse input now tracks combined left/right/middle button masks.
  Releasing one preserves other held buttons; right/middle dragging updates
  coordinates, wheel pulses preserve held buttons, and focus loss/panning
  release the complete held mask. Additional mouse buttons are ignored instead
  of being misreported as middle. Mac mini native input regression10/10 passed
  with zero failures/skips; synthetic view events do not replace hardware
  acceptance. Test fixtures were removed from the remote machine. Evidence:
  `/tmp/aetherscreens-all-buttons-build-20261008.log`,
  `/tmp/aetherscreens-all-buttons-macmini-tests-20261008.log`.

- Password-save warning dismissal now has a 44-point minimum hit target and
  localized accessibility hint. Generic unsigned iOS build passed; native
  touch/VoiceOver acceptance remains pending. Evidence:
  `/tmp/aetherscreens-notice-dismiss-ios-build-20261008.log`.

- Session remember-password failure now has a dismissible localized warning,
  covering VNC and Mac-account prompt paths without discarding entered values.
  DeviceStore.updatePassword returns persistence status and logs success only
  on actual success. Current synthetic deny-write/session suite6/6 passed;
  unsigned iOS build passed. Native warning presentation and actual writable
  Keychain migration are still pending. Evidence:
  `/tmp/aetherscreens-session-save-notice-tests-20261008.log`,
  `/tmp/aetherscreens-session-save-notice-ios-build-20261008.log`.
- DeviceStore add/update now return credential persistence success separately
  from saving computer configuration. Library add/discovered-add/editor report
  failure via existing warning banner with English/Chinese copy; process-local
  fallback remains available. Injected denied-write regression confirms config
  persistence and false result. Keychain write tests5/5 and unsigned iOS build
  passed. Session password prompt feedback is recorded above; native visual acceptance remains pending.
  Evidence: `/tmp/aetherscreens-credential-save-report-tests-20261008.log`,
  `/tmp/aetherscreens-credential-save-report-ios-build-20261008.log`.
- Keychain writes no longer delete an existing credential before replacement.
  SecItemUpdate handles existing values; only errSecItemNotFound permits add,
  and duplicate-item races retry update. Access/lock errors remain errors.
  Deterministic write-branch regressions4/4 passed; unsigned iOS build passed.
  These injected-status tests do not replace actual locked-Keychain migration
  acceptance. Existing in-memory fallback and save-failure UI still need review.
  Evidence: `/tmp/aetherscreens-keychain-upsert-tests-20261008.log`,
  `/tmp/aetherscreens-keychain-upsert-ios-build-20261008.log`.
- Latest actual Mac mini full-core run:477 tests,16 explicit environment skips,
  three assertion failures in one legacy-Keychain migration case,149.782s.
  Standalone retry reproduces1 case/3 failures. Failure starts when the legacy
  fixture cannot save. Read-only default-Keychain status reports unlocked=false,
  writable=false, readable=true. No unlock/settings change was attempted.
  This is a failed full gate, not a pass; credential migration needs a writable
  Keychain run. Other completed test cases reported no failures. Evidence:
  `/tmp/aetherscreens-macmini-full-core-regression-20261008.log`,
  `/tmp/aetherscreens-macmini-keychain-migration-recheck-20261008.log`,
  `/tmp/aetherscreens-macmini-keychain-status-20261008.log`.
- iOS canvas resignFirstResponder now releases both touch/hardware dragging
  and hardware keys, instead of hardware keys alone. Generic unsigned iOS
  build passed; trackpad engine regression9/9 passed, zero failures/skips.
  These engine tests do not validate UIKit focus callbacks; physical focus
  transfer acceptance remains pending. Evidence:
  `/tmp/aetherscreens-ios-focus-drag-release-build-20261008.log`,
  `/tmp/aetherscreens-ios-focus-drag-engine-tests-20261008.log`.
- Extended authorized Mac mini AppKit regression9/9 passed, zero failures/skips,
  0.075s. Added undisplayed NSWindow case: posted didResignKey notification
  reaches the registered publisher, detaching the input view triggers cleanup,
  and repeat cleanup sends no duplicate release. No system-generated actual
  focus switch or rendered fluidity is proved. Evidence:
  `/tmp/aetherscreens-macmini-window-lifecycle-tests-20261008.log`.
- Actual authorized Mac mini XCTest run: MacNativeInputTests8/8 passed,
  zero failures/skips,0.011s. New AppKit view cases confirm drag-to-pan release
  uses the last remote coordinate once, and focus-cleanup clears normal keys,
  modifiers and marked text without duplicate releases. Existing coordinate,
  Unicode and wheel cases also passed. This is actual remote view-unit evidence,
  not complete window-focus UI/hardware acceptance. Evidence:
  `/tmp/aetherscreens-macmini-input-lifecycle-tests-20261008.log`.
- Device card thumbnail cache hits no longer restart async thumbnail work;
  image identity guard skips redundant state writes/animations. Cache misses
  still revise the request, and Reduce Motion remains respected. macOS and
  generic unsigned iOS builds passed; async thumbnail regression5/5 passed.
  Storage tests do not prove card animation or large-library smoothness; native
  visual acceptance remains pending. Evidence:
  `/tmp/aetherscreens-thumbnail-refresh-build-20261008.log`,
  `/tmp/aetherscreens-thumbnail-refresh-storage-tests-20261008.log`,
  `/tmp/aetherscreens-thumbnail-refresh-ios-build-20261008.log`.
- macOS input view now clears recorded keys/modifiers/left drag when it resigns
  first responder, its window resigns key, or its view is detached/dismantled.
  State is cleared before callbacks; fractional scroll and marked text reset.
  macOS build and existing keyboard/focus-release wire regression1/1 passed.
  That wire test verifies transport, not new AppKit lifecycle callbacks; native
  remote focus-change acceptance remains pending. Evidence:
  `/tmp/aetherscreens-mac-focus-release-build-20261008.log`,
  `/tmp/aetherscreens-focus-release-wire-tests-20261008.log`.
- macOS entering local panning during a left drag now releases the remote
  button at the last sent remote position and clears the local pan anchor.
  Previously mouseUp in panning returned without releasing that drag. macOS
  build passed; native remote UI transition acceptance is still pending.
  Evidence: `/tmp/aetherscreens-pan-drag-release-build-20261008.log`.
- iOS two-finger wheel callbacks now reuse a shared ScrollWheelAccumulator,
  preserving8-point steps and fractional motion while bounding each axis to64
  events per callback and dropping whole overflow. Existing local panning and
  drag guards remain. Pure scroll regressions3/3 passed with no skips/failures;
  generic unsigned iOS build passed. Evidence:
  `/tmp/aetherscreens-touch-scroll-bounds-tests-20261008.log`,
  `/tmp/aetherscreens-touch-scroll-bounds-ios-build-20261008.log`.
  Physical iPhone gesture acceptance remains pending.
- macOS scroll accumulator now drops capped whole-tick overflow rather than
  replaying it on later zero-delta events; sub-tick precision remains. Finite
  bounds are checked before integer conversion. Pure accumulator regressions
  2/2 passed, zero failures/skips; no host GUI automation ran. Evidence:
  `/tmp/aetherscreens-scroll-overflow-tests-20261008.log`.
- Post-run route/log diagnostic: mesh ping stayed DERP(baizhiedu),427/22/72ms,
  no direct connection. LAN192.168.50.226 ports22/5900 both timed out after3s.
  Allowlisted server events show monitoring requested20:20:42 and capture stop
  20:21:40 near test end, with no intervening stop logged. Absence of a log is
  not proof of absence of server stalls. A direct-LAN comparison is unavailable
  on the current route; no network/security configuration was modified.
  Evidence: `/tmp/aetherscreens-current-mesh-ping-20261008.log`,
  `/tmp/aetherscreens-arrival-capture-events-20261008.jsonl`,
  `/tmp/aetherscreens-lan-reachability-20261008.json`.
- Second optimized native owned-pattern run passed1/1, zero failures/skips,
  60.562s. Full desktop received6.707s/decoded6.738s/known pattern6.741s after
  connect. Full payload window3.543s,402 socket arrivals,2302566 observed wire
  bytes, maximum arrival gap1.178s. Eight states/55 transitions spanned52.455s,
  mean gap0.954s,max3.901s,last age0.809s. Consecutive optimized trials now pass
  continuity, but four-second stalls and physical UI acceptance remain open.
  Evidence: `/tmp/aetherscreens-arrival-live-20261008.log`.
- Internal SRP QA now measures socket byte arrivals only during the first full
  desktop payload window: observed wire bytes, event count and maximum arrival
  gap, including the initial/final wait. This excludes previously prefetched
  bytes and must not be presented as exact payload throughput. Three timing
  regression cases passed, no failures/skips. Actual receive-window measurement
  is recorded in the checkpoint above. Evidence: `/tmp/aetherscreens-receive-window-timing-tests-20261008.log`.
- Encrypted record fragmentation regression: release13/13 passed, no skips or
  failures.4MiB/285 fragments reassembled with every delivered byte verified in
  3.382ms (synthetic; excludes socket, RFBClient downstream buffer and UI).
  This narrows the investigation but cannot attribute live stalls to network
  versus server scheduling. Evidence:
  `/tmp/aetherscreens-fragmented-record-release-20261008.log`.
- Latest optimized-build native owned-pattern trial passed 1/1 (60.561s),
  zero skips/failures: eight states, 49 transitions spanning49.204s; mean gap
  1.004s, maximum gap3.622s, final age0.721s. First full desktop arrived10.087s
  after connect; declared payload5.125s, received10.048s, decode completed10.083s
  (receive4.923s, worker decode0.035s). One passed trial does not establish
  repeatability or rendered UI fluidity. Evidence:
  `/tmp/aetherscreens-fulltiming-live-20261008.log`.
- Internal SRP QA now distinguishes the first tiny pixel patch from a full
  desktop rectangle, recording full payload declaration, receive completion
  and decode completion separately. This is diagnostic instrumentation only;
  actual full-desktop timing still requires a new owned-pattern run.
  Two timing regression tests passed with no skips or failures.
- Refreshed core regression before the new timing helper: 469 tests, 16 explicit
  environment skips, zero failures, 154.718 seconds. Evidence:
  `/tmp/aetherscreens-core-refresh-20261008.log`. The subsequent test-only timing
  helper compiled and passed separately: `/tmp/aetherscreens-full-desktop-timing-tests-20261008.log`.
- Latest targeted RGB565 optimization: lazy256KiB lookup preserves all65536
  colors/every4K output byte; release decoder16/16 and transport32/32 passed.
  Same synthetic benchmark median62.17 ->51.70ms (about16.8% reduction).
  Current unsigned iOS build passed: `/tmp/aetherscreens-rgb565-lookup-ios-build-20261008.log`.
  No real-stream/FPS improvement claimed yet; core refresh is recorded above.
- Latest app-source full core regression after explicit first-screen subscription:
  467 tests, 16 explicit environment skips, zero failures, 150.015 seconds;
  `/tmp/aetherscreens-first-screen-full-core-20261008.log`. Generic unsigned
  iOS build passed: `/tmp/aetherscreens-first-screen-ios-build-20261008.log`.
  Later cadence/stage instrumentation and internal payload/decode hooks have
  targeted checks; they are not covered by that earlier full-suite/iOS run.
- Experimental SRP mutual authentication and first desktop pixels have actual
  evidence. One explicit screen-0 owned-pattern trial passed the 60-second gate
  (eight states spanning 44.39 seconds). Repeats failed: only 7.07 seconds of
  changes, then one known state first arriving after 58.56 seconds. Native
  sustained stability, vendor cursor and physical UI fluidity remain unaccepted.
  No periodic polling fallback was added, and SRP remains internal QA only.
- Final macOS and generic iOS builds passed (code signing disabled for iOS).
  Logs: `/tmp/aetherscreens-cursor-image-cache-mac-build-20261008.log` and
  `/tmp/aetherscreens-cursor-image-cache-ios-build-20261008.log`.
  Immutable cursor images are now created once on the decode worker and reused.
  Fifteen targeted cases passed, zero skips/failures, 0.116 seconds.
- Owned-simulator zoomed trackpad edge-follow gate passed 1/1 with no skips,
  failures or runtime warnings. Three right/left/held-drag screenshots reviewed;
  hotspots reach the edges while cursor bodies remain clipped there.
  `/tmp/aetherscreens-cursor-image-cache-ui-20261008/result.xcresult`.
- Actual modern ViewerInfo/arm/Apple-only cursor offer failed 1/1, 37.017 seconds:
  desktop pixels arrived but no vendor shape within the subsequent 15 seconds.
  Production cursor negotiation remains unchanged. Native shape interoperability,
  encrypted-session integration and layout rearming remain unaccepted.
- Earlier standard Cursor desktop regression passed 1/1, 80.610 seconds,
  44 actual 4K frame callbacks and 60 seconds continuously connected; zero
  standard Cursor callbacks were observed. Initial-fetch retry and native
  fallback presentation remain implemented, not Apple shape interoperability.
- Earlier native presentation gates passed: 20 targeted cursor/clipboard cases
  after the temporary Apple guard, and two owned-simulator viewport/edge-follow
  cases with no skips/failures/runtime warnings; five screenshots were reviewed.
  The guard was subsequently removed after the initial-fetch correction and
  successful actual desktop regression. Physical smoothness, Apple shape and
  bidirectional clipboard acceptance remain open.
- Earlier macOS/iOS builds passed with native Apple Unicode sending, bounded
  latest-pending coalescing and Observe/reconnect send guards;
  `/tmp/aetherscreens-apple-native-clipboard-send-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-native-clipboard-send-ios-build-20261008.log`.
  Twenty-five native clipboard codec/control/transport cases passed in the
  final full suite. Actual bidirectional text and physical acceptance await
  an isolated clipboard window.
- Earlier macOS/iOS builds passed with native Apple clipboard receive enabled
  for Mac-account desktop connections;
  `/tmp/aetherscreens-apple-native-clipboard-client-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-native-clipboard-client-ios-build-20261008.log`. Eight
  TCP cases and actual 4K/60-second desktop regression passed. Outgoing native
  Unicode and actual bidirectional text acceptance remain open.
- Earlier macOS/iOS builds passed with native Apple clipboard request framing
  and promise-only protection;
  `/tmp/aetherscreens-apple-clipboard-control-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-clipboard-control-ios-build-20261008.log`. Eleven
  targeted tests and both actual read-only profiles passed. Normal RFBClient
  integration and text acceptance remain open.
- Earlier macOS/iOS builds passed with bounded Apple clipboard archive decoding
  and record-fragment assembly;
  `/tmp/aetherscreens-apple-clipboard-archive-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-clipboard-archive-ios-build-20261008.log`. Eight
  targeted archive tests passed. Native clipboard integration remains open.
- Earlier macOS/iOS builds passed after exposing the in-memory ARD wrap-key
  result: `/tmp/aetherscreens-apple-auth-bridge-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-auth-bridge-ios-build-20261008.log`. Actual standard
  Mac-account/4K/60-second regression passed 1/1;
  `/tmp/aetherscreens-apple-auth-bridge-live-20261008.log`.
- Earlier macOS and generic iOS builds passed with the experimental Apple record
  codec compiled; `/tmp/aetherscreens-apple-record-mac-build-20261008.log` and
  `/tmp/aetherscreens-apple-record-ios-build-20261008.log`. Eight codec tests and
  nine independent OpenSSL vectors passed. The codec is not wired into normal
  RFB yet. Opt-in actual Apple bootstrap now verifies rekey and the first
  encrypted control record; clipboard interoperability remains open.
- Earlier macOS/iOS builds passed with bounded desktop snapshot scheduling;
  `/tmp/aetherscreens-thumbnail-coalescing-mac-build.log` and
  `/tmp/aetherscreens-thumbnail-coalescing-ios-build.log`. Controlled native
  preview save/disconnect/relaunch gate passed 1/1 with screenshots reviewed;
  `build/thumbnail-coalescing-native-ui-20261008/`.
- Earlier macOS and generic iOS Simulator builds passed with keyboard overlay
  transitions: `/tmp/aetherscreens-overlay-transitions-mac-build.log` and
  `/tmp/aetherscreens-overlay-transitions-ios-build.log`. Normal floating/carousel
  native cases passed 2/2; actual system Reduce Motion rerun passed 1/1 with
  original OFF setting restored. See the overlay phase below.
- Earlier macOS and generic iOS Simulator builds passed with accelerated
  full-color ZRLE raw-tile expansion: `/tmp/aetherscreens-zrle-vimage-mac-build.log`
  and `/tmp/aetherscreens-zrle-vimage-ios-build.log`. Local macOS Release 4K
  fixture median fell from 15.20 to 7.85 ms across nine samples per version;
  `build/zrle-vimage-benchmark-20261008/summary.json`. This excludes network/GPU
  presentation and does not establish physical-device FPS or UI hitch behavior.
- Actual Mac-account authentication over recovered Tailscale target passed
  1/1 with 4K frames and 60-second stability;
  `/tmp/aetherscreens-macmini-mesh-ard-session-20261008.log`. Account-mode
  clipboard rerun still failed both cases; ownership loss in ASCII prevented
  restoration, while Unicode restored. See the account clipboard phase below.
- Actual ZRLE fixture native viewport/quality/reconnect gate 2/2 passed with
  screenshots reviewed; `build/zrle-vimage-native-ui-20261008/`. Previous real
  GPU upload-pool tests and display/edge-follow gate remain valid historical
  evidence: `build/metal-upload-pool-navigation-ui-20261008/`.
- Encrypted ECDSA PKCS#8 import: native phone Simulator draft/library
  English/Chinese 4/4 passed; wrong phrase, cancel/retry, fingerprints and
  persisted library lifecycle verified; screenshots reviewed. Four owned
  source files and generated identities cleaned. Actual decrypted-key SSH
  authentication/4096-byte forwarding passed. Artifacts:
  `build/ssh-encrypted-pkcs8-native-final-ui-20261008/`.
- Latest SSH UI follow-up: settled native draft-file import 2/2 and full
  repeated edit/save/reload/disable settings 2/2 passed in both languages;
  screenshots reviewed. Earlier English label clipping was a transitional
  capture; the Chinese long-press failure was resolved with visible-frame
  coordinates. Artifacts: `build/ssh-draft-file-interactive-ui-20261008/`
  and `build/ssh-settings-repeat-edit-ui-20261008/`.
- Latest SSH export gate: owned phone Simulator English/Chinese native
  save/re-import 2/2 passed, exact bytes/fingerprints matched, owned files
  cleaned; `build/ssh-export-save-roundtrip-settled-ui-20261008/`. Current
  macOS/iOS builds passed after the per-key accessibility identity change:
  `/tmp/aetherscreens-ssh-export-roundtrip-mac-build.log` and
  `/tmp/aetherscreens-ssh-export-roundtrip-ios-build.log`.
- Latest lock-notice layout UI gates: default English/Chinese and Reduce Motion
  3/3; 375-point maximum accessibility text English/Chinese 2/2. Screenshots
  reviewed; system motion/text settings restored. See
  `build/adaptive-lock-notice-final-motion-ui-20261008/` and
  `build/adaptive-notice-actions-se-large-ui-20261008/`.
- Idle metrics now settle completed windows without another frame/packet, and
  reject older queued window results. The HUD motion setting is respected;
  this is not physical FPS or Mac-window visual acceptance.
- Mac mini LAN ports still time out, but current Tailscale peer discovery found
  `100.64.0.3` online. SSH confirms the Mac mini identity and macOS 27.0.1;
  actual RFB handshake and 3840x2160 desktop/60-second connection passed 2/2,
  `/tmp/aetherscreens-macmini-mesh-handshake-20261008.log`. Physical iPhone
  acceptance remains deferred; paired physical 12 Pro currently unavailable.
- True Curtain, native file drag/drop, real cloud container/login/list wiring,
  Apple clipboard compatibility, progressive/scaled quality and measured
  device responsiveness remain incomplete. No commit, push or release is
  implied by these implementation/verification steps.

## Connection diagnostics

Implemented stage-specific bilingual timeout guidance for network connection,
RFB negotiation, authentication and desktop initialization. A separate 20-second
first-pixel deadline begins after initialization; an empty update or a display
layout acknowledgement cannot satisfy it. The deadline belongs to its original
socket so a disconnected/replaced session cannot fail the replacement.

Transport refusal now points to Screen Sharing, port and firewall checks;
unreachable POSIX network errors point to LAN/Tailscale and address checks.
This identifies the observed failure, not a proven remote configuration cause.

Regression coverage uses real loopback TCP: an initialized server sends only
layout data, and a closed listener exercises an actual connection refusal.
Normal large-frame delivery and reconnect progress remain covered.

Final local core run: 183 tests, 5 explicit environment skips, zero failures
(`/tmp/aetherscreens-next-all-tests-3.log`). Earlier regression attempts exposed
an incomplete listener fixture and then the waiting/refused transport branch;
both were corrected before this final run. Localization plist validation, Python
compilation and diff whitespace checks pass. Final transport changes still need
a fresh iOS build and physical acceptance.

## Physical interaction validation

UITest assertion failures now retain a screen image and UI hierarchy, including
fullscreen failures that previously had no visual evidence. The cause of the
historic fullscreen failure remains unresolved.

The 2026-10-07 next-iteration physical build succeeded, but the attempted suite
was interrupted after detecting concurrent AetherRoute xcodebuild tests targeting
the same iPhone 12 Pro and operating Chrome. Its result is incomplete and must
not be used as acceptance. Evidence: ignored local
`build/iphone12pro-next-20261007/diagnostics-gestures-1/`.

The physical runner now checks for live competing xcodebuild test processes
before building and again after building. It rejects a busy device and reports
only process IDs; it never stops another task. This is an observed preflight
check, not a cross-project device lock.

Latest default core run: 185 tests, 6 explicit opt-in/environment skips, zero
failures (`/tmp/aetherscreens-next-all-tests-4.log`). The real-Mac clipboard
opt-in run is separate and fails; the default suite skip is not acceptance.

## Clipboard negotiation and actual-server acceptance

An opt-in real-Mac regression now uses RFB for clipboard delivery and SSH only
for inspecting the remote pasteboard. Original representations stay in remote
RAM and are restored only if QA still owns the board. No original clipboard
content or account password is printed or stored in artifacts.

The initial Mac mini Unicode/multiline run failed in both directions; the
restoration assertion passed. Evidence: `/tmp/aetherscreens-real-clipboard-probe.log`.
This is a real compatibility gap, not acceptance.

Investigation found that the client implemented extended clipboard messages
but omitted the required `0xc0a1e5ce` SetEncodings advertisement. The advertisement
is now included. A real-TCP server that replies with capabilities only when the
extension is requested passes the new negotiation regression. The first
filtered command selected the wrong test class and ran zero tests; only
`/tmp/aetherscreens-clipboard-advertisement-test-2.log` is pass evidence.
Actual Mac mini retest still fails in both Unicode directions after the
advertisement fix (`/tmp/aetherscreens-real-clipboard-probe-2.log`); restoration
again passed. Generic extension negotiation alone does not resolve this server
compatibility gap. Apple-specific clipboard support needs separate live
negotiation evidence before implementation can be accepted.

Protocol reference: [Extended Clipboard](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#extended-clipboard-pseudo-encoding).
This does not establish support for Apple's separate clipboard extensions.

## First-frame UI regression

The controlled fixture can withhold all pixels for its next connection only.
English and Chinese UI cases check the exact first-frame timeout guidance and
then retry to a new socket that delivers a real frame. USB inspection permits
only the new named QA endpoint in addition to the existing allowlist.
These cases still require execution. The default complete runner now selects
15 physical cases (14 simulator cases); `--case` explicitly selects focused
cases and still verifies every requested case/count/warning. Earlier 13-case
plans already built before this change remain 13-case evidence only.

## Device scheduling and development archive

The second 13-case physical attempt was also contaminated: AetherRoute testing
started after preflight and activated its app during the edge-follow test. That
case failed to receive expected pointer packets and retained a failure screen
and hierarchy. The run was interrupted and is not product acceptance. The user
then explicitly chose to continue code work and schedule physical acceptance
later. Do not restart physical UI tests until an exclusive window is arranged.

The runner now checks competing real xcodebuild processes during execution,
ignores its own PID, records `device-interference.json`, interrupts only its own
test, and rejects a contaminated result regardless of xcodebuild's final exit.
A short isolated compiled process fixture verified mid-run conflict detection,
owned-process interruption and rejection (exit 125) without using a real device.

A Release development-signed archive succeeded. Inspection exposed hardcoded
Info.plist version `1.0` / build `1`; both Info.plist and its XcodeGen source now
use MARKETING_VERSION and CURRENT_PROJECT_VERSION. Re-archive and strict
codesign verification show `1.0.0` / `2026100601`. The existing configuration
values were preserved; no new release/version was published. Evidence:
`build/ios-next-20261007/archive-metadata-fixed-verification.json`.
The local signing keychain contains no valid Apple Distribution/iPhone
Distribution identity. Distribution export, account access and final unique
release build approval remain pending; this archive is not TestFlight-ready.

An ASCII real-Mac clipboard probe retained the connection and accepted the
outgoing packet, but did not confirm either transfer direction and did not
confirm restoration. The remote guard preserves another writer's clipboard
rather than overwriting it. This probe is inconclusive for server compatibility;
repeat in an exclusive clipboard window. QA now compares canonical newline
representations and reports only safe ownership/match markers on failure.

## Explicit local clipboard transfer

The existing Paste Text action still inserts key events. Its context menu now
has a separate Send to Remote Clipboard action, with localized feedback for
inactive control, no plain text, rejected text and an unacknowledged request.
It never claims that acceptance of a packet confirms the remote pasteboard.
The reader is injected for regression tests so no local user clipboard is
modified during the controlled suite. The actual TCP Unicode round-trip now
calls this session action; Observe prevents even reading the local clipboard.
Apple-server Unicode compatibility remains unresolved.

Latest code verification: 186 core tests, 7 explicit opt-in/environment skips,
zero failures (`/tmp/aetherscreens-next-all-tests-6.log`), localization plist
validation and Python compilation pass. Generic iOS build-for-testing succeeds
with the new UI, timeout cases and failure capture (`/tmp/aetherscreens-next-ui-build-4.log`).
This build does not execute physical acceptance or establish rendered UI quality.

The contaminated second physical report finished at 13 executed, 12 passed,
1 failed, zero skips/runtime warnings; no overall acceptance is claimed. Its
edge failure attachments were exported by test ID and the screen was inspected:
the AetherRoute return indicator and logs confirm the app handoff. Attachments
added via XCTestCase.add were retained but not associated with the issue, so
`--only-failures` exported nothing. Failure capture now puts attachments directly
on the XCTIssue. The first mutableCopy attempt did not compile through the Swift
overlay; the corrected XCTIssue initializer passes the generic iOS test build.
Association still needs runtime verification in a scheduled UI test window.

Latest clipboard UI Release archive also succeeds with strict signature and
configured version/build verification; source hash evidence is retained in
`build/ios-next-20261007/archive-clipboard-ui-verification.json`. This remains
a development-signed local candidate, with no upload or distribution export.

## Input responsiveness during compressed-frame decoding

A real TCP regression exposed a transport-queue stall: after receiving a full
2048×2048 ZRLE rectangle, a scheduled wheel packet reached the server only after
the frame callback. Baseline evidence:
`/tmp/aetherscreens-decode-input-baseline.log` (one ordering assertion failure).

ZRLE and Zlib decoding now run on a separate serial worker. Protocol parsing,
framebuffer commits and continuation of the rectangle stream stay on the
transport queue. Each connection gets fresh dictionary objects; disconnect and
failure cancel its context, pending cancelled work is skipped, and result commits
check the original socket identity. This preserves stream ordering and prevents
old decoding from overwriting a reconnected session.

The same actual-TCP ordering regression now passes while checking every decoded
pixel. A second regression reconnects while a large decode is pending, receives
a replacement raw frame, and rejects any stale frame publication. Mixed ZRLE,
Zlib/Raw dictionary and malformed-payload regressions remain in the complete run.

Latest complete core run: 188 tests, 7 explicit opt-in/environment skips, zero
failures (`/tmp/aetherscreens-next-all-tests-7.log`). Current generic iOS
test build passes (`/tmp/aetherscreens-next-decode-ui-build.log`). The tests prove
that wheel transport no longer waits for compression decoding; they do not
measure actual Apple-server scroll results, presented-frame latency or perceived
hand feel. Physical acceptance remains deferred at the user's request.
The updated Release development archive also passes strict signature and metadata
verification; source hashes are retained in
`build/ios-next-20261007/archive-decode-worker-verification.json`. No distribution
export or upload was performed.

## RGB565 wire precision (physical acceptance deferred)

Added an opt-in core RGB565 pixel format, while retaining full-color defaults.
Raw and Zlib pixels expand to BGRA32 on the decode worker; ZRLE handles compact
16-bit pixels for raw tiles, palettes and run-length encodings. Desktop dimensions
and pointer coordinates remain unchanged. No quality selector is exposed yet.

Controlled TCP tests verify the actual SetPixelFormat negotiation, all returned
pixels, pointer coordinates and interleaved ZRLE/Zlib/Raw frames across reconnects.
The same 4x2 Raw frame uses 32 pixel bytes in full color and 16 in RGB565; complete
received streams are 92 and 76 bytes including handshake and rectangle headers.
This does not imply that compressed traffic or Apple-server traffic halves.
The initial byte-count assertion incorrectly included a compressed-length field
for Raw; it was corrected to the actual Raw protocol header size.

Full core regression passes: 191 tests, 7 explicit opt-in skips, zero failures
(`/tmp/aetherscreens-next-rgb565-full-tests.log`). iOS build-for-testing passes
(`/tmp/aetherscreens-next-rgb565-ios-build.log`).
Apple-server compatibility and physical input/visual acceptance remain pending,
as requested by the user. The previous archive predates these color-depth changes.

## iPad hardware pointer input

Inspection found no hardware hover or wheel recognizers in the iOS canvas. Added
an indirect-pointer hover recognizer, raw indirect-pointer button transitions and
a scroll-only pan recognizer. Finger recognizers now exclude indirect pointers,
so hardware clicks do not require the finger long-press delay. Hardware movement
maps canvas coordinates absolutely in both finger modes, retaining held buttons.
Cancellation, view removal and local-navigation transitions release held buttons.
The indirect-input capability is explicit in Info.plist and XcodeGen source.

Nine input-engine tests pass, including a new check for absolute coordinates in
both finger modes, held right-button movement/release and empty-canvas rejection.
Full core regression passes: 192 tests, 7 opt-in skips, zero failures
(`/tmp/aetherscreens-hardware-pointer-full-tests.log`). The final iOS
build-for-testing also passes (`/tmp/aetherscreens-hardware-pointer-ios-build-final.log`).
These tests do not instantiate UIKit events or prove real-device delivery.
Hardware keyboard passthrough, actual iPad landscape/rotation and external-device
acceptance remain open; physical testing is deferred per the user's instruction.

## Hardware keyboard passthrough

Added a canvas first responder selected by clicking/tapping the remote canvas.
USB usages map arrows, navigation/function keys and left/right modifiers to RFB
keysyms; printable values use UIKit charactersIgnoringModifiers. Modifiers precede
other keys within a press batch. Key-up uses the original down keysym by usage,
so changing Shift/layout while a key is held cannot strand the original key.
Focus loss, view removal and observe transitions release the keyboard state.
Unknown keys continue through the UIKit responder chain.

Three mapping/state tests pass. A separate actual TCP test verifies Command-C,
key repeat, focus-release packet ordering, held-key release on Observe, blocked
Observe key-down and resumed Return packets. iOS build-for-testing passes
(`/tmp/aetherscreens-hardware-keyboard-ios-build.log`). These tests do not create
physical UIKit keyboard events, test system-reserved shortcuts, or establish
physical Chinese IME compatibility. Canvas capture requires a canvas click;
local text entry fields keep their own responder behavior.

## Combined input/quality candidate verification

Full core regression passes: 196 tests, 7 explicit environment/opt-in skips,
zero failures (`/tmp/aetherscreens-hardware-keyboard-full-tests.log`).
The combined Release development archive succeeds and passes strict signature,
actual signing-team/identity, version/build, indirect-input flag and unchanged
source-hash verification. The hash list includes the new HardwareKeyboard.swift
and RFBColorDepth.swift. Evidence:
`build/ios-next-20261007/archive-input-quality-verification.json`.
The archive is local, remains development signed, and has not been exported for
distribution or uploaded. Physical iPhone/iPad and actual Apple-server acceptance,
account/distribution prerequisites and unique release build approval remain open.

## iPad rotation coverage

Added English/Chinese controlled rotation cases to the standard runner. They
check portrait, landscape-left and landscape-right in fitted and zoomed states,
including center RFB coordinates, fitted off-center coordinates, clickable session
and keyboard controls, and retained screenshots/received pointer packets.
The first run uses an isolated self-created iPad mini iOS 27 simulator and a ZRLE
loopback fixture; it does not occupy the physical iPhone or establish Apple-server
or real external-device acceptance. Production viewport code is unchanged until
runtime evidence demonstrates a defect.

Run 1 (`build/ipad-rotation-20261007/run-1`) compiles successfully. The Chinese
case passes all six rotation/zoom combinations in 47.111 seconds. The English
case also passes; the final report contains two passes, zero failures/skips and
an empty runtimeWarnings list. The text execution log nevertheless records five
60-second waits for SpringBoard animation-complete notifications; this remains
unresolved. All 12 screenshots were inspected. Landscape app screenshots show
cropping/black areas and missing toolbar content, despite successful hit testing
of right-side controls. PNG files contain landscape pixel dimensions plus EXIF
orientation. Metadata-only review copies preserve IDAT pixel chunks and originals;
this inspection does not establish the source of the cropping. Visual acceptance
is not passed. Run 2 adds full-device screenshots, UI hierarchies and a left-side
Disconnect hit test to distinguish capture trouble from a rendered-layout defect.

## Rotation capture/environment investigation

Run 2 repeats the 60-second SpringBoard animation wait before launching the app
and again before Quick Connect. A read-only simulator screenshot shows the library
while the test is waiting. The owned xcodebuild test PID 7934 was interrupted for
simulator recovery; Xcode reported an internal error during interruption and did
not finalize a readable result bundle. This run is not accepted. Its logs,
read-only screenshot and `interruption.json` are retained. Only the self-created
simulator ABED9232-7AC7-4E53-9C3F-AC33813A3B3F was shut down and restarted.
Run 3 repeats the existing English case with full-device screenshots, hierarchy
attachments and left-side Disconnect hit testing. No production layout patch is
justified yet; coordinate acceptance and visual acceptance remain separate.

## Rotation capture finding

After the isolated simulator restart, Run 3's English case passes all six
orientation/zoom combinations, including left-side Disconnect hit testing, with
zero skips/failures/runtime warnings and no animation-complete wait lines.
All six full-device screenshots were inspected: both toolbar ends and the canvas
are visible in the expected orientation; fitted letterboxing and zoom cropping
are correct. In the same test moments, app-only screenshots are incorrectly
cropped. The retained landscape hierarchy has a 1133x744 window, a 1133x692 input
area and Disconnect at (24,52), matching the full-device render.

The common QA screenshot helper now uses XCUIScreen.main rather than the cropped
app screenshot. Production layout code remains unchanged. Run 4 passes the
Chinese case using this helper with zero failures/skips/runtime warnings. All six
Chinese full-device screenshots were inspected and correct, completing the 12
English/Chinese orientation/zoom views across Runs 3 and 4. Physical rotation/external input acceptance is
still outstanding. The simulator restart cleared the observed animation delay,
but its original cause is not established as repaired product behavior.

## Remaining acceptance

- Re-run the complete physical suite while the iPhone is available exclusively.
- Diagnose fullscreen failures from retained evidence; do not count a rerun as
  proof of a root-cause repair.
- Real Mac-server scrolling, dragging, physical Chinese IME, reconnection and
  30-minute active use, with the same-device Screens comparison.
- Real bidirectional Chinese/multiline clipboard and reconnect verification.
  Existing local text insertion sends key events and is not clipboard sync.
- Verify negotiated server scaling/quality with actual transferred bytes and
  accurate pointer coordinates before adding quality controls.
- iPad landscape/external input acceptance and a concrete TestFlight candidate;
  distribution still requires the applicable account and release authorization.

## Expanded Screens parity and interaction polish

User now requests comprehensive Screens parity, polished animations and smooth
interaction, with physical acceptance still deferred. Compare against the official
feature catalog: https://help.edovia.com/en/screens-5/features/ . Track gestures,
customizable toolbars, international/hardware keyboards, clipboard, display
selection, adaptive quality, SSH, file transfer and device synchronization as
separate evidence-backed capabilities; do not claim parity from visual resemblance.

First motion change scopes keyboard visibility animation to the controls subtree,
adds combined fade/slide transitions with a damped spring and honors Reduce Motion.
The keyboard toggle no longer wraps the whole state mutation in withAnimation,
keeping live canvas/pointer updates outside that explicit animation transaction.
macOS swift build and the iOS simulator build-for-testing both pass. Visual motion
and physical responsiveness remain open. The English/Chinese first-frame timeout
recovery cases are running in the isolated iPad simulator at
`build/ipad-motion-20261007`; this does not establish animation smoothness.

## First-frame recovery and control feedback

`build/ipad-motion-20261007` completes both English/Chinese first-frame timeout
recovery cases: two passes, no skips/failures/runtime warnings. All four retained
full-screen captures were inspected: actionable timeout guidance is readable, and
Retry connects a new fixture session and restores the desktop without stale error.
This proves controlled recovery, not Apple-server stability or animation frame rate.

Toolbar text/F-key expansion now uses consistent damped transitions scoped to
controls and respects Reduce Motion. Toolbar buttons, sticky modifiers, top-bar
buttons and computer cards receive short local press feedback; events still fire
through normal Button actions. A localized text-close label replaces an unnamed
icon. Two opt-in UI cases now cover repeated keyboard visibility, unchanged canvas
bounds/center coordinates, function and text rows, actual received F1/QA key packets,
row collapse and disconnect. The default controlled suite is now 18 simulator /
19 physical cases; both additions pass at `build/ipad-controls-20261007` with zero failures/skips/runtime
warnings. All six screenshots and the 107-second recorded sequence storyboard
were inspected. A 20 Hz extraction around toolbar expansion shows staged fade/slide
into its final position; this sampling is visual evidence, not an actual frame-rate
or input-latency benchmark. The video uses variable frame timing and includes idle
intervals and system screens; its average frame rate cannot prove UI jank or smoothness.

## Screens parity audit (expanded request, 2026-10-07)

Reference catalog: https://help.edovia.com/en/screens-5/features/ . Toolbar behavior
reference: https://help.edovia.com/en/screens-5/features/ios-toolbar and customization
reference: https://help.edovia.com/en/screens-5/features/toolbar-customization .
This table records gaps, not a completion claim. A fixture pass proves the scoped
client/wire behavior only; Apple-server and physical-device evidence remain separate.

| Capability | Current implementation/evidence | Remaining requirement |
| --- | --- | --- |
| Pointer/gestures and edge follow | TrackpadEngine/native UIKit input; controlled gestures/coordinates, arrow cursor | Exclusive iPhone + actual Mac scrolling/drag/zoom/edge-follow and same-device Screens comparison |
| Docked/interactive toolbar | Per-computer order/visibility/size; horizontal portrait/iPad and iPhone landscape side dock; animated F/text rows; controlled rotation/state preservation | iPad floating drag/collapse/quick-menu now has controlled two-language acceptance; carousel now has initial two-language iPhone/iPad controlled acceptance; remaining menus, hardware and physical acceptance pending |
| Modifier interactions | Once/locked states and key-release guards | Click/drag release gap now reproduced and patched; controlled TCP regression passes, wheel Once consumption now has controlled TCP/lifecycle acceptance; physical acceptance remains open |
| Navigation keys and repeat | Arrow/Tab/Return keys; hardware key-repeat wire test | Home/End/Page Up/Page Down default-hidden controls have controlled two-language customization/wire acceptance; configurable toolbar hold-repeat now has scheduler/TCP and two-language iPhone/iPad controlled acceptance; physical acceptance remains open |
| Hardware input | HID mapping and direct mouse buttons/wheel paths; core and TCP tests | Real external keyboard/mouse, focus changes and reserved system shortcuts |
| International keyboards | Unicode key events/text entry | Actual physical Chinese IME and multiple layout acceptance |
| Clipboard | Legacy/extended clipboard protocol + explicit transfer action | Apple server bidirectional Chinese/multiline/reconnect blocked by compatibility evidence |
| Display selection/arrangement | ExtendedDesktopSize layout/cropping/global-coordinate mapping | Actual multi-monitor Apple server acceptance; remote arrangement editing absent |
| Quality/compression | Worker decode Raw/Zlib/ZRLE; RGB565 TCP tests; per-computer full/16-bit quality UI accepted on controlled iPhone/iPad | Actual Apple RGB565, server scaling and measured adaptive quality |
| Quick connect/URLs | Temporary sessions, saved connection links and routing | Physical deep-link/no-duplicate-session regression with current candidate |
| Observe/control and reconnect | Input boundary guards, controlled recovery, separate active session selection | Actual 30-minute session/network interruption acceptance |
| Curtain/disconnect actions | Local lock shortcut notice; per-computer explicit disconnect actions, platform filtering, final-packet drain; core TCP tests and English/Chinese iPhone/iPad controlled lock acceptance | Genuine Curtain mode absent; actual remote OS actions/hot corners and stalled-send acceptance remain open |
| SSH/SSH keys | Password and Ed25519/ECDSA authentication, bounded OpenSSH/PEM import, fail-closed sessions, native prompts, final-chord drain and saved/add/quick settings; real SSH/RFB, system ssh-keygen and isolated Keychain checks | Password settings, native file-picker open/cancel and saved-key reuse passed on owned phone/iPad in both languages. Standalone library import/reuse/delete model has real Keychain coverage; phone/iPad bilingual library/delete/empty UI and screenshots passed. Native draft paste and standalone library paste/import/name/relaunch/delete passed on owned phone/iPad in both languages. Actual library file selection/import/name/relaunch/delete passed on owned phone/iPad in both languages. Phone-simulator bilingual native key export/cancel/save/re-import passed with exact original-byte and selected-fingerprint checks. Phone-simulator temporary draft actual file selection/import passed in both languages; Mac/iPad draft-file acceptance remains open. Encrypted ECDSA PKCS#8 native draft/library import passed 4/4 on the owned phone Simulator in both languages, including wrong phrase/cancel/retry and persisted-library lifecycle; real decrypted-key SSH authentication/forwarding passed. Encrypted OpenSSH/bcrypt, RSA, Mac/iPad/physical key-import/export acceptance, host-sheet visuals and actual server/device acceptance remain open |
| File transfer | No app file-transfer transport/UI implementation | Actual iPhone/iPad/Mac bidirectional transfer, progress, cancel, overwrite and reconnect behavior |
| Data/credential sync | Configuration-only journal, durable account-scoped checkpoints, DeviceStore/coordinator integration, conditional CloudKit read/save code, bounded conflict merge and generation-safe UI model tested locally | CloudKit container/entitlements, login and existing UI wiring, actual multi-device conflict/deletion, notifications/retry and credential policy remain open |
| Pencil/Dictation | Pencil direct touch plus double-tap/squeeze callbacks for Carousel; editable local text field | Physical Pencil callbacks, customization and dedicated dictation behavior |
| External display/AirPlay | Independent active-session Metal presentation surface; external scene delegate/config and iOS 27 accessory registration compiled | Actual external scene delivery, rendered external screen, attach/detach/AirPlay and device input mapping remain unaccepted |
| Widgets/Siri/Shortcuts | Saved-computer App Intent; actual system action discovery, connection, repeated-session reuse and Chinese localization accepted on owned simulator | Spoken Siri, widgets and physical acceptance |
| Vision Pro | No visionOS target in current project | Platform-specific build/input/toolbar/acceptance if extending the product to that platform |
| Smooth UI | Local scoped transitions/press feedback; Metal renders only on incoming frames | Review captured motion; measure input-to-present latency and dropped-frame behavior on actual devices |

Keep the complete request open. Prioritize operation correctness and polished controls
first, then actual server quality/clipboard compatibility, then missing transport and
platform integrations. Do not relabel any absent feature as supported.

## One-use pointer modifier fix

A new actual-TCP regression reproduces missing Shift/Option releases after both
gesture and native mouse clicks before the patch (`/tmp/aetherscreens-modifier-pointer-before-2.log`).
Both pointer sources now use the same main-actor forwarding path without adding a
queue hop. Hover preserves a pending modifier, a multi-button drag retains it until
all buttons are released, and one-use modifier key-ups follow the final pointer-up
in the received TCP event sequence. Locked modifiers remain held. A focused run
passes at `/tmp/aetherscreens-modifier-pointer-after.log`; follow-up coverage resets
tracking at Pan/input-generation/connection boundaries so a cancelled old click
cannot consume a newly selected modifier. Full core regression passes: 197 tests, seven environment-dependent skips, zero
failures at `/tmp/aetherscreens-controls-modifiers-full-tests.log`. The iOS simulator
rebuild and extended English/Chinese toolbar cases also pass at
`build/ipad-controls-modifiers-20261007` (two passes, zero failures/skips/runtime
warnings). The UI cases confirm once/locked accessibility values and real Shift
key/pointer delivery. All four new modifier-state screenshots were inspected;
inactive and locked styling correctly follows the remote click. Both localization
property lists validate, and the five localization tests pass after the new labels.
A complete 18-case simulator regression is now running at
`build/ipad-parity-regression-20261007`; its outcome is still pending.
Wheel ticks remain queued independently and are not treated as click completion;
that behavior needs its own ordering solution before claiming complete parity.
The earlier local archive predates these production motion/modifier changes and
must be refreshed before treating it as the current candidate.

## Optional toolbar navigation keys

Screens documents Home, End, Page Up and Page Down in its shared toolbar controls
(https://help.edovia.com/en/screens-5/features/ios-toolbar). All four are now available
in our toolbar customization and emit the existing standard keysyms. They default
to hidden to preserve the compact visible layout. Older stored settings gain the
new hidden controls without changing existing IDs, order, size, position or visibility.
A migration/persistence regression covers an encoded older configuration and
subsequent opt-in/reordering. The existing English/Chinese controlled toolbar cases
now enable all four through the real settings sheet and require each key's down/up
packet to arrive at the fixture, with retained settings/toolbar screenshots.
Core migration/build and new UI acceptance outcomes pending.

The live complete 18-case run at `build/ipad-parity-regression-20261007` uses the
compiled motion/modifier candidate from before these optional navigation additions.
Keep that evidence scoped to its compiled candidate; it cannot prove the new buttons.
No shared fixture, simulator or running test process has been restarted for these edits.

## Navigation acceptance environment and input failure

Navigation configuration migration tests pass (four toolbar tests), both localization
catalogs lint, and five localization tests pass. A separate self-created iPhone 12 Pro
simulator `B2A70B86-CF9F-4B79-B813-C97E81273130` uses isolated build products
`build/navigation-derived-20261007` and its own loopback fixture on 6031/6032/8791.
Its iOS build-for-testing succeeds. The two cases at `build/iphone-navigation-20261007`
fail before connecting: the trailing-coordinate port tap does not obtain keyboard
focus in landscape. The navigation buttons have not been accepted by this run.
The runner/xcodebuild remains alive collecting results after the failed cases;
do not restart it merely because the result bundle is not yet readable. A read-only
live screen capture shows an app-launch transition and does not establish a rendered
port-field defect. An owned xcodebuild stack sample is retained for the result wait.

The QA port-entry helper now scrolls a keyboard-occluded field within the exposed
form area, then uses the semantic field tap before positioning the trailing caret.
It retains the exact entered-port assertion. This public XCTest interaction change
still needs a terminal prior run and a new acceptance run; no production connection
UI workaround or relaxed omission/failure gate has been added.

## Verified terminal results and navigation QA correction

The iPad parity run has now finalized successfully: 18 requested tests passed,
zero failures/skips and no runtime warnings (822 seconds). Its compiled candidate
predates the optional navigation keys, so those keys still require their own gate.
The first iPhone run finalized after stopping only its owned, identified simctl
 diagnostic-collection child; the original two keyboard-focus failures remain
recorded. The second run finalized naturally and successfully entered the port
and connected, resolving the QA focus path.

Run 2's actual failure screenshots/hierarchies expose two additional QA positioning
problems: the Chinese Shift button spans x=-27.7…34 despite a toolbar starting at
x=0, and English settings remain at the top after application-root swipes. The
helper now requires the whole toolbar button within the viewport and scrolls the
settings CollectionView itself. These changes preserve state assertions and the
required received key-down/key-up packets. Run 3 is evaluating both languages;
navigation acceptance remains pending. All four custom failure screenshot/hierarchy
attachments in run 2 have isAssociatedWithFailure=true in the exported manifest.

The current full core suite is terminal: 198 tests, seven environment-dependent
skips, zero failures (73.3 seconds). Navigation run 3 finalized naturally, still
failing both cases at the Home visibility check. Its exported screenshots show
the settings form at the bottom (Page Up/Page Down), and hierarchies put End
under the navigation bar: full swipe gestures overshoot Home. This is distinct
from run 2's unscrolled form. The next helper uses short, bounded drags and reverses
when an existing row is under the navigation bar; run 4 is pending. No diagnostic
child was stopped in run 3: process validation found no still-matching child.

Navigation run 4 is now terminal and accepted for its controlled simulator scope:
both requested Chinese/English cases passed with zero failures/skips/runtime
warnings. The cases enable all four default-hidden controls and require received
key-down/key-up events for Home=65360, End=65367, Page Up=65365, Page Down=65366.
All four exported navigation customization/enabled screenshots were visually
reviewed. Files and manifest are retained under
`build/iphone-navigation-20261007-run-4/attachments`; terminal summary/tests/logs
and result bundle remain alongside them. No physical-device acceptance, frame-rate
measurement or production Mac clipboard compatibility is inferred from this run.
The comprehensive Screens feature/interaction goal remains open.

## iPhone landscape side dock

The current toolbar layout now selects a left, vertically scrolling dock for iPhone
landscape, while iPad/macOS and phone portrait retain configured horizontal placement.
The canvas remains a sibling overlay and keeps its original geometry; controls do
not inset or animate the framebuffer. Text/function expansion stays accessible above
the dock. Side docking reuses the same configured buttons, modifier state and sizing.
macOS `swift build` passes; the isolated iPhone build-for-testing also passes.
`build/iphone-side-dock-20261007` is evaluating the existing two-language wire/control
cases with additional side geometry assertions and axis-aware button reveal. Results
and screenshot review remain pending; portrait rotation needs explicit verification.

The first side-dock candidate passed both language interaction cases with zero
failures/skips/runtime warnings. Its four expanded/navigation screenshots were
reviewed and expose excess sidebar width and inadequate auxiliary-panel contrast.
The dedicated new rotation case then reproduced expansion loss when rotating from
landscape to portrait (`iphone-toolbar-rotation-red-20261007`, assertion at line 473).
Only its verified, owned optional simctl diagnostic child was stopped after the test
ended, preserving the failed result bundle.

The revised controls use one toolbar view identity through orientation changes,
a 104-point side dock, compact modifier/action representations with named accessibility
labels, and material backgrounds on text/function rows. The canvas remains a separate
unchanged overlay. macOS builds successfully. The final iPhone run evaluates rotation
and both interaction languages; acceptance is pending. The rotation case is included
in the runner's default set, now 19 simulator / 20 physical cases (including edge follow).

Additional official platform constraints checked against the current Screens catalog:
- File transfers https://help.edovia.com/en/screens-5/features/file-transfers supports
  iPhone/iPad uploads to macOS 10.10+, but downloads require macOS 14+; this is an Apple
  file transfer path, not generic clipboard text/image transfer.
- Curtain https://help.edovia.com/en/screens-5/features/curtain-mode requires Remote
  Management on the destination Mac and is unavailable with Screen Sharing alone.
  Sending Lock Screen cannot establish this capability; do not change remote host
  management settings merely to make a fixture pass.
- SSH https://help.edovia.com/en/screens-5/features/ssh-keys includes password/private
  key authentication, file/clipboard key import and Keychain storage, not a tunnel
  toggle without a functioning transport and trust lifecycle.
These constraints refine evidence requirements without dropping the comprehensive goal.

## Interrupted final acceptance and recovery

The prior final iPhone/iPad runs stopped during interaction checks after the turn
was interrupted. Their runner/xcodebuild and both fixtures were confirmed absent
from the process table; neither log contains a complete terminal result. Keep these
bundles as interrupted evidence, not accepted tests. Independent fixture services
were restarted only after verifying their absence. New output directories preserve
prior evidence: `iphone-toolbar-rotation-green-20261007` first checks the reproduced
rotation defect; `ipad-toolbar-continuity-20261007-resume` evaluates all three toolbar
cases. Results are pending. The full goal remains active.

The resumed dedicated rotation run finalized PASS: one requested case, zero
failures/skips/runtime warnings (41.8 seconds). It proves Fn expansion survives
portrait/landscape, receives F1 down/up, restores input bounds and maps a center
click to (320,180). Both exported rotation screenshots were reviewed: the current
material function row is readable and the side dock is visibly narrower. This
closes the reproduced rotation-state defect for the controlled iPhone simulator;
it does not prove physical smoothness or all expanded input/focus scenarios.
`iphone-side-dock-final-20261007-resume` is now evaluating the two language cases
against the same production candidate; iPad's three-case run remains active.

Resumed iPad toolbar acceptance is terminal PASS: all three requested rotation and
Chinese/English interaction cases ran, with zero failures/skips/runtime warnings.
Four expanded/rotation screenshots were exported and reviewed; the iPad retains
horizontal toolbar layout with readable auxiliary rows. The current candidate is
still not a physical-device or Apple-server acceptance claim.


Final resumed iPhone side-dock interaction acceptance is terminal PASS: both language
cases ran with zero failures/skips/runtime warnings. Four expanded/navigation images
were exported and visually reviewed; controls remain reachable by vertical scrolling,
material panels are readable, and all navigation key down/up events were required.
Together with the separate current rotation pass and current iPad three-case pass,
this closes the controlled toolbar/rotation gate for the current production candidate.
No physical device was used, no release was made, and the broader feature parity,
Apple clipboard compatibility, hardware-device and measured smoothness gates remain
open. All interrupted runs stay unaccepted and preserved alongside these final results.

## iPad floating toolbar implementation

A new Floating position is exposed only in the iPad settings picker; existing
Top/Bottom JSON preferences and navigation visibility migrate unchanged. Five
configuration tests pass, including floating mode persistence isolated by computer.
Five localization tests and both strings lint checks pass. macOS builds and iOS
build-for-testing succeed.

The floating overlay reuses configured controls, expands/collapses with scoped,
Reduce Motion-aware animation, keeps Fn/text rows mounted while collapsed, and
clamps its position to the viewport. Expanded movement is vertical via the handle;
the collapsed chevron can move in both axes and exposes esc/tab/paste through a
long-press quick menu. It does not resize the remote canvas. Dedicated Chinese and
English controlled cases require local dragging to produce no remote pointers,
quick-menu Escape down/up on the wire, retained Fn expansion and unchanged center
mapping. `build/ipad-floating-toolbar-20261007` is running these cases; UI acceptance
and screenshot review remain pending. Text-field focus during collapse, physical
interaction and long-session smoothness are not proven. The default runner now
includes both floating cases (21 simulator / 22 physical cases), with phone cases
checking that the iPad-only option is unavailable rather than skipping.

The first floating UI run finalized with two genuine failures: dragging the collapsed
chevron also fires its button action, re-expanding controls instead of leaving the
compact toolbar moved. Both exported failure screenshots were reviewed and show
that expanded state. The diagnostic collector had already exited when revalidated;
no child was stopped. The drag now takes priority over the button's tap recognizer,
keeping taps and drags distinct; run 2 is evaluating the fix. The iPhone platform
boundary cases passed in both languages with zero failures/skips/runtime warnings.
Those iPhone cases build the prior candidate but prove the new iPad-only setting is
not offered on phone; they do not prove floating interaction or the drag fix.

Run 2 finalized with both test cases passing but the strict runner rejected it:
summary.json contains two `_UIGravityWellEffectAnchorView` runtime warnings. The
owned optional diagnostic collector was stopped only after both cases ended, and
the terminal bundle was still checked; test passes do not override the warning gate.
No accepted UI result is claimed for run 2. The long-press menu now uses a SwiftUI
popover instead of contextMenu; run 3 checks the same interaction/wire requirements
and must still finish with zero runtime warnings before acceptance.


Run 3 removed the runtime warnings but failed both final expansion checks. Its
quick-menu screenshots show an expanded toolbar rather than the popup; the action
log targets the ordinary keyboard-action-esc button. The warning-free bundle was
therefore rejected and not treated as successful quick-menu acceptance. Its owned
optional diagnostic collector was stopped after both failed cases had ended.

Run 4 makes long press take priority over the button tap, preserves drag priority,
and uses 44-point quick-action touch targets. Both language cases now finish with
zero failures/skips/runtime warnings. The logs target the actual popup esc button,
and six expanded/collapsed/quick-menu screenshots were reviewed. They prove the
menu really appears, collapse/drag does not accidentally expand, Fn survives
collapse, the quick action receives Escape down/up, local dragging sends no pointer
packets, and the desktop's center mapping/bounds stay unchanged. Final macOS build
and diff checks pass. This closes the controlled floating toolbar gate; focused
text-field collapse, rotate/resize edge behavior, physical input and smoothness
measurements remain open. No public release or upload was made.

## Floating draft focus and rotation regression

An extended floating case types an unsent QA draft, collapses/re-expands, rotates
portrait/landscape, closes the editor and requires original desktop bounds/center
mapping. The first controlled English run reproduced a real failure: the editor
was removed but the software keyboard remained visible, reducing input bounds to
504.9×284 instead of 1133×637.3. Its actual failure screenshot/hierarchy was reviewed.
The owned optional diagnostic child was stopped only after the failed test ended.
The collapse keyboard-dismiss check itself passed, so this is not reported as a
failure of that earlier step.

The text field now uses explicit FocusState, clears focus on collapse and close,
and keeps the unsent buffer/expanded rows. Expanding the draft does not implicitly
reopen the keyboard. New cases also wait for actual keyboard disappearance before
asserting original canvas bounds, preserving the geometry requirement. Both iPad
languages are running at `ipad-floating-focus-green-20261007`; one normal iPhone
toolbar case at `iphone-toolbar-focus-regression-20261007` exercises the shared
editor path. These outcomes are pending; physical IME and performance remain open.

The first FocusState candidate finalized with both floating cases failing: re-expansion
still reopened the software keyboard. The stricter no-implicit-keyboard assertion
was retained. The next candidate keeps draft/expansion state in the toolbar/model
but removes the native TextField subtree while collapsed, preventing first-responder
restoration from a merely hidden editor. Both languages are running again under
`ipad-floating-focus-green-20261007-run-2`. The standalone iPhone normal toolbar
case has finalized PASS with zero failures/skips/runtime warnings for the preceding
shared FocusState candidate (its isCollapsed stays false); it does not prove the new
floating editor lifecycle or physical input.

The latest floating draft candidate finalized PASS in both languages: zero failures,
skips and runtime warnings. Four collapsed/focused-draft/portrait images were exported
and reviewed. The tests now prove retained QA draft, no implicit software keyboard
on re-expansion, an on-screen collapse control after rotation, original canvas bounds
and center pointer mapping after closing the editor, while keeping the earlier drag,
quick-menu and Fn-state checks. Final macOS build and diff checks pass. No physical
Chinese IME, iPad multitasking resize or latency/frame-drop measurement is inferred.
The broader Screens parity goal remains active, and no release was made.

After the final floating focus change, the complete macOS core suite was rerun:
199 tests, 7 environment-dependent skips, zero failures, exit 0 in 67.126 seconds.
The log is `/tmp/aetherscreens-floating-focus-full-tests.log`. This supersedes the
older 198-test core snapshot; it does not substitute for physical acceptance or
prove end-to-end animation frame rate. Final diff whitespace checks also pass.

## Toolbar hold repeat and per-computer speed

The next Screens-alignment phase adds hold repeat for arrows, Home/End/Page Up/
Page Down, Tab, Space and Delete. Return, Escape, shortcuts and menu controls keep
single activation. Button retains tap/scroll recognition; after the configured
hold delay, repeated key-downs form one held-key operation and end with one key-up.
Once modifiers stay active throughout the hold and release after its key-up.
Locked modifiers remain locked. Input generation changes, hiding the toolbar,
foreground-session changes, collapse, disappearance and inactive scene cancel the
hold. Disconnect/failure also clears the model's held-key tracking.

Key Repeat offers Off/Slow/Normal/Fast, stored per computer. The new Codable field
is optional on read: legacy records retain item IDs/order, visibility, sizing and
position. Defaults are Normal (450ms delay, 65ms repeat); Slow is 600/120ms and Fast
300/45ms. Off retains one ordinary button activation on release. This is local
repeat timing, not a measured remote response latency.

Two scheduler regressions and one actual-TCP hold/modifier/lifecycle test pass.
The TCP test proves repeated downs followed by one up and then Once Shift up,
no extra packet on duplicate release, and held-key cleanup before locked Cmd is
released when leaving the foreground session. Its initial expected command keysym
was corrected to MacKeyMap.commandLeft; the observed wire used the existing keymap.
The intermediate full core suite passes 202 tests with seven environment skips.
Final settings/legacy/localization/scheduler selection passes 13 tests; string
plists and whitespace checks pass. Final full-suite and UI gates are still pending.

The first iPhone/iPad two-language toolbar interaction runs already passed their
Chinese hold/tap checks and continue through the existing navigation/UI scenarios.
They compiled before the final scene/connection cancellation and repeat-speed UI.
New dedicated two-language repeat cases cover Off/Fast, retained Once Shift,
wire ordering, no packets after release and unchanged canvas bounds. They are now
part of the default controlled gate (23 simulator cases, 24 physical including USB
acceptance). They must pass on the final source before the speed UI is accepted.
Physical input/IME and end-to-end frame/input latency are still deferred.


The final repeat-speed candidate passes both languages on both owned simulators:
`build/ipad-repeat-settings-20261007` and
`build/iphone-repeat-settings-20261007`, each two passes, zero failures/skips and
zero runtime warnings. Four final Fast setting screenshots (phone/pad × both
languages) were reviewed. Exported wire attachments from all four cases show one
Shift down, 12 Right downs, one Right up, then one Shift up; no further key packet
arrives after release. Off sends exactly one down/up pair, and canvas bounds stay
unchanged. The earlier two full toolbar interaction cases on each simulator also
finalized with zero failures/skips/runtime warnings, but predate final settings.

The final full core suite passes 203 tests with seven environment-dependent skips
and zero failures (73.127s), log
`/tmp/aetherscreens-repeat-settings-full-tests.log`. Final macOS build, localized
string validation and diff checks pass. Tests prove the controlled hold/speed
interaction and core cancellation paths, not a physical keyboard/IME gate,
VoiceOver device acceptance or measured end-to-end smoothness. Carousel, wheel
Once modifiers and actual Apple clipboard/display/quality behavior remain open.
No commit, push, tag, release or physical-device takeover occurred.

## Once modifiers and delayed wheel completion

A new actual-TCP regression reproduced a real missing release: the wheel's
press/release reached the server, but Once Shift remained active and no Shift-up
followed. The red bundle/log was retained at
`/tmp/aetherscreens-wheel-once-red.log`; the initial corrected test passes at
`/tmp/aetherscreens-wheel-once-green.log`.

RFBClient's optional onWheelSent callback now fires outside its input lock, after
both delayed pulse packets are queued. Cancelled pulses do not invoke completion.
SessionViewModel tracks pending modified wheels and captures each Once modifier's
selection generation. A completed pulse releases matching Once states only when
no modified wheel remains pending and no drag button remains held. Mouse-up/key-up
cannot release those states ahead of queued wheel pulses; locked states and newer
modifier selections remain intact. Input cancellation resets the pending counter
and callback epoch so an old/cancelled callback cannot affect resumed control.
Pan cancels wheel state without resetting held keyboard input.

The complete PointerTransportTests selection passes 13 tests (34.269s). Its new
lifecycle case verifies delayed wheel after drag-up, a newly reselected Once,
Pan cancellation without a stuck pending count, locked modifiers and immediate
Observe/resume. The first full core run passes 205 tests with seven environment
skips, zero failures (78.708s). One iPhone repeat-settings regression and one iPad
viewport-navigation regression pass with zero failures/skips/runtime warnings;
these compile before the final viewport identity cancellation below.

Review also found that fullscreen input identity changes must invalidate pending
transport wheels, not only local counters. Added cancelPendingWheelEvents, which
advances the transport input generation while preserving held keyboard keys and
current pointer state. Session input generation changes invoke it. The final TCP
lifecycle case now also verifies no old wheel arrives after fullscreen changes
and subsequent Once click consumption remains usable; that case passes (4.870s).
Final full-core and final iPad viewport gate are running again for this candidate.
The new wheel acceptance is controlled TCP evidence; physical two-finger gestures,
external mouse/trackpad and actual Apple server acceptance remain deferred.


The final input-generation candidate passes the complete core suite: 205 tests,
seven environment-dependent skips, zero failures (79.762s), log
`/tmp/aetherscreens-wheel-generation-final-tests.log`. The final iPad viewport
navigation gate `build/ipad-wheel-lifecycle-regression-20261007-run-2` passes its
exact requested case with zero failures/skips/runtime warnings. Its Observe/Pan
screenshots were exported and reviewed. The previous iPhone toolbar case also
passes, but predates the final transport identity-cancellation method. Both iOS
builds succeed, and final macOS build and diff checks pass. This closes the
controlled wheel Once release/lifecycle gap; carousel, Apple server compatibility
and the deferred physical/performance gates remain open. No release was made.


## Initial Carousel toolbar and touch interaction

Screens' current official toolbar page and its Carousel reference image were
reviewed. The circular option is now available on iPhone/iPad, stored per computer
without new JSON fields beyond the existing position enum. macOS keeps its current
position options. The ring uses native material and eight 44-point controls,
localized accessibility labels, press feedback and Reduce Motion-aware collapse.
It supports modifiers, navigation, function keys, editing, shortcuts, quick text,
local Paste Text and session actions. Editing chords send key-up before Command-up
and preserve an already locked Command; an actual-TCP regression covers that path
and Observe rejection. Navigation reuses the existing configurable hold repeat.

The native ring has a center hole and hit-tests only the circular footprint.
Its buttons/pan filter finger/Pencil touch types; indirect pointer touches return
false from hit-testing/tracking. Physical mouse/trackpad pass-through is not yet
accepted. Remote touch activity minimizes the ring to a 56-point expansion button.
Its view-local position is clamped and survives ordinary portrait/landscape
rotation without resizing the desktop. Pencil double-tap/squeeze, advanced resize,
hardware-key/scroll minimization and all menu branches remain open.

First iOS build exposed a UIView.mask name collision; the private shape layer was
renamed ringMask. No UI cases executed in that build. The next iPad cases failed
because their expected Once accessibility value did not match existing localized
Next action/下一次操作; expectations were corrected to current source labels.
Only the owned optional iPad diagnostic child (PID 98236, parent 97611, exact
simulator/result path validated) was stopped after both failed cases ended. The
failed bundles remain preserved.

The first iPhone run reproduced a real menu accessibility bug: the container's
identifier replaced the Done button identifier. The menu now has an explicit
accessibility container, retaining independently addressable controls. No fallback
selector, skipped test or runtime-warning exemption was introduced.

Final initial Carousel gates pass:
- `build/ipad-carousel-toolbar-20261007-run-3`: two language cases, zero failures,
  skips and runtime warnings.
- `build/iphone-carousel-toolbar-20261007-run-2`: two language cases, zero failures,
  skips and runtime warnings.

The cases prove local ring drag emits no remote pointer packets, the center hole
passes a remote click, touch interaction minimizes the ring, expansion is local,
rotation keeps it on-screen, menu modifiers expose Once/Locked/Inactive, Page Down
arrives as down/up, Copy arrives as a complete Command-C chord, and closing/reopening
quick text preserves QA draft without leaving the keyboard visible. Text Send
arrives as Q/A down/up. Canvas bounds remain unchanged once the text popup closes.
Moved, portrait, minimized and navigation-menu screenshots were exported; selected
phone/iPad screenshots were reviewed. This is not acceptance of unexercised function/
shortcut/session action menus, physical Pencil/IME, indirect input or performance.

Final core suite: 207 tests, seven environment-dependent skips, zero failures
(83.633s), `/tmp/aetherscreens-carousel-final-core-tests.log`. Both iOS builds,
macOS build, localization plists and diff checks pass. Default controlled QA now
contains 25 simulator cases (26 physical with USB input acceptance). No full new
25-case run or release is inferred from the selected Carousel passes. The full
Screens parity goal remains active; no commit/push/tag/release was made.


## Carousel connection and menu follow-up (2026-10-07)

Command groups now disable when the session is disconnected, inactive or Observe-only;
the actions group remains available for recovery. Function/shortcut menus close when
remote commands become unavailable. Hardware hover, scroll and native key activity
now notify the ring to minimize; physical peripheral acceptance is still pending.

A real TCP regression reproduced keyboard bytes corrupting the RFB version handshake
(`/tmp/aetherscreens-handshake-input-red.log`). `sendKeyEvent` now requires connected
state, and the same test passes (`/tmp/aetherscreens-handshake-input-green.log`).
The fixture validates the exact negotiated protocol version.

The first expanded UI run failed because resetting fixture events removed the ready
event used to identify the old socket. The test now captures that identity before
resetting, preserving the reconnect assertion. Both failed bundles remain retained.
An earlier full core run had a reconnect clipboard timeout; the final full run passes
208 tests, seven environment skips, zero failures (85.583s), recorded in
`/tmp/aetherscreens-carousel-connection-final-core.log`. macOS build and diff checks pass.

Accepted expanded controlled UI bundles:
- `build/iphone-carousel-menus-20261007-run-2`
- `build/ipad-carousel-menus-20261007-run-2`

Each executes both languages with zero failures, skips and runtime warnings. In
addition to the previous Carousel checks, these verify F12 down/up, Spotlight
Command-Space ordering, Fit retaining canvas bounds, disabled command groups after
fixture disconnect, and F1 delivery on the newly established socket after reconnect.
Attachments are exported; phone reconnected function menu and iPad disconnected
controls were visually reviewed. Clipboard actions and physical peripherals remain
unaccepted.

The complete 25-case simulator suites are now running, not yet accepted:
- `build/iphone-screens-parity-full-20261007`, runner log
  `/tmp/aetherscreens-parity-full-phone-runner.log`
- `build/ipad-screens-parity-full-20261007`, runner log
  `/tmp/aetherscreens-parity-full-ipad-runner.log`

Do not infer complete Screens parity, end-to-end smoothness, a physical device pass
or release readiness from these selected checks. No commit, push, tag or release.


## Native Pencil Carousel interaction (2026-10-07)

The remote UIKit input view now installs `UIPencilInteraction`. Double tap toggles
the mounted Carousel; on iOS 17.5+ a squeeze toggles only at its ended phase. Both
respect the system Ignore preference. When expanding and hover pose exists, the
ring moves toward the Pencil location and clamps to the available canvas. Without
hover pose, it retains the previous position. Menus close before toggling; callbacks
are local UI events and do not generate remote key or pointer commands. Only a
visible Carousel outside fullscreen handles the action.

Source references checked against Apple's official UIPencilInteraction/delegate
documentation and the installed SDK headers:
https://developer.apple.com/documentation/uikit/uipencilinteraction
https://developer.apple.com/documentation/uikit/uipencilinteractiondelegate

First iOS build caught an out-of-scope local `carouselDock` reference; fixed by
checking the view model's toolbar position directly. Final iOS test build succeeds
(`/tmp/aetherscreens-pencil-build-2.log`, isolated `build/pencil-derived-20261007`);
macOS build succeeds (`/tmp/aetherscreens-pencil-mac-build.log`); diff check passes.
No physical Pencil device was used. No double-tap/squeeze/hover behavior acceptance
is inferred from compilation.

The two full simulator suites launched in the previous phase remain live. Their
built candidate predates this Pencil change, so their results will prove only that
previous candidate. Do not label those suites as regression acceptance of this
latest input-view change. At this observation Carousel, connection recovery, display
selection, first-frame recovery and floating toolbar cases have passed; the suites
are not terminal. Preserve their current runners/handles and inspect completion
instead of restarting solely because an observation timed out.


## Carousel edge movement follow-up (2026-10-07)

Native pan now consumes incremental translation rather than accumulating movement
beyond the clamped edge. This avoids needing to reverse the whole overshoot before
the ring can move inward. The ring's horizontal/vertical margins are bounded by
half the available dimension; when a window is smaller than the ring plus margins,
the center remains in the available area. Geometry changes normalize the stored
offset to the clamped location rather than preserving an unreachable old offset.

Latest isolated iOS test build succeeds (`/tmp/aetherscreens-carousel-edge-build.log`,
`build/pencil-derived-20261007`), diff check passes. This is build evidence only;
edge reversal and multitasking resize still require actual interaction acceptance.
The latest candidate combines this change with the native Pencil callbacks and has
not yet replaced the candidate running in the full suites.

Both original full-suite runner handles were polled and are live: phone 44977,
iPad 10803. Both have passed eight cases so far (Chinese Carousel/recovery/display/
first-frame/floating/fullscreen/session-selection/rotation). No suite completion
or latest-candidate regression is claimed. Next: inspect those terminal results,
then run the latest candidate's Carousel plus input gesture/rotation regression
without interrupting the existing sessions. No release or remote Git mutation.


## Explicit zoomed edge-follow coverage (2026-10-07)

Auditing the running viewport-navigation case confirms it checks local Pan, Observe
navigation and Fit restoration, not trackpad edge follow. An earlier commentary
that included edge follow among those passes was corrected. Do not use that case
as edge-follow proof.

Added controlled English/Chinese edge-follow cases reusing the physical test's
shared verifier. It moves the trackpad cursor toward both edges, requires hover-only
pointer masks, then measures viewport movement independently by switching to Touch
and comparing a fixed visible center's received remote coordinate. A separate held
drag verifies pressed pointer packets, release, and actual displayed viewport shift.
The physical test still calls the same verifier; simulator results cannot substitute
for physical-device acceptance. Attachments now use neutral Controlled labels.

Default runner now enumerates 27 simulator cases (28 physical). The existing full
runs captured their original 25-case list before this edit and remain live; their
manifest must be evaluated against that captured scope, not the new default.
Latest test build succeeds (`/tmp/aetherscreens-edge-qa-build.log`, isolated
`build/pencil-derived-20261007`); runner Python AST and diff checks pass. New cases
are not executed yet. At last poll phone full suite has 14 passes/zero failures,
iPad has 13 passes/zero failures; neither is accepted as terminal. Next run the
latest Carousel, new edge-follow and native-input/rotation cases after the existing
simulator suites release their devices. No physical tests, Git push or release.


## Complete prior-candidate simulator gate (2026-10-07)

Both full 25-case controlled simulator runners are terminal and accepted:
`build/iphone-screens-parity-full-20261007` and
`build/ipad-screens-parity-full-20261007`. Each executed all requested cases with
zero skips, failures and runtime warnings. The candidate predates native Pencil
callbacks, Carousel incremental edge drag/clamping and the two new edge-follow
cases; this does not prove those later changes or any physical-device acceptance.

Latest candidate's eight-case regression now runs on the same owned simulators:
`build/iphone-latest-input-regression-20261007` and
`build/ipad-latest-input-regression-20261007`. It includes both languages of Carousel,
zoomed trackpad edge follow/held drag, rotation mapping and received native gestures.
Logs: `/tmp/aetherscreens-latest-input-phone-runner.log` and
`/tmp/aetherscreens-latest-input-ipad-runner.log`. No latest-run acceptance yet.


## Latest edge-follow evidence (2026-10-07)

Latest eight-case runners remain live (phone handle 73992, iPad 31065). Both
`testChineseControlledZoomedTrackpadEdgeFollow` cases passed: phone 76.500s,
iPad 80.565s. The verifier confirms left/right cursor movement without pressed
buttons, independent fixed-screen center coordinate shift in the expected direction,
and a held drag with pressed packets, final release and displayed viewport shift.
Both latest Chinese Carousel and rotation mapping cases also passed. The remaining
five cases are not accepted yet; these are controlled simulator results only.

Prior full iPad bundle attachments exported and portrait zoomed rotation plus Observe
navigation screenshots reviewed (`18B240F9-CDA4-4473-9DC7-DC3C013339DD.png`,
`7C959517-0F84-4464-B6A6-781397F2A446.png`). Primary controls remain inside the visible
window. Screenshots do not prove frame rate or animation performance. Full parity
and physical input/Apple-server acceptance remain open.


## Latest input regression accepted (2026-10-07)

Both latest candidate runners are terminal and accepted:
- `build/iphone-latest-input-regression-20261007`: eight cases, 441.070s.
- `build/ipad-latest-input-regression-20261007`: eight cases, 467.280s.

Both ran all requested cases with no skips, failures or runtime warnings. Both
languages of Carousel, rotation, left/right zoomed trackpad edge-follow/held drag
and received native gestures pass. Attachments exported under each bundle; latest
phone held-drag viewport screenshot `2B880D3A-F0E1-42B4-9B77-8D7B5391D4A6.png`
reviewed. This confirms selected input/UI regression of the latest code, not
physical Pencil callback execution, hardware mouse behavior, multitasking resize,
edge-overshoot reversal within one continuous drag, or end-to-end performance.

The complete previous-candidate 25-case suites also passed; no complete latest
27-case run is inferred. Full parity table remains open, including Apple clipboard/
display/quality acceptance, SSH/file transfer/synchronization/integrations and actual
smoothness measurements. No physical device was taken over; no commit/push/release.


## Display quality preference foundation (2026-10-07)

Added DisplayQualityStore for per-computer wire color precision, with full color
as the default and fallback for unknown stored values. RFBColorDepth now has
stable raw values/Codable/CaseIterable for preference persistence. No session or UI
selection is connected yet; this does not change live connection behavior.
Two isolated UserDefaults tests prove per-computer separation, recreation persistence,
reset to full color and unknown-value fallback. Both pass (zero failures),
`/tmp/aetherscreens-display-quality-store-tests.log`; diff check passes.
Next connect the preference to session construction and an explicit quality/reconnect
flow, with TCP-format and UI acceptance. This does not implement adaptive quality
or verify actual Apple-server RGB565 compatibility. No new dependency or release.


## Display quality session/UI integration (2026-10-07)

Saved sessions load their per-computer DisplayQualityStore preference; temporary
sessions default to full color and do not save changes. Session options expose a
Display Quality sheet with Full Color/Reduced Colors and an explanation of reduced
precision and reconnection. Switching releases toolbar keys, modifiers and pointer
buttons, cancels the password continuation, invalidates input identity, disconnects
and negotiates the selected format on a new socket. Inactive sessions reject changes.
RFBClient rejects color-depth changes on active sockets, preserving decoder format.
Explicit reconnect now disconnects before starting a fresh connection even when
the prior state was connected. No adaptive quality behavior is claimed.

Core suite passes 210 tests, seven environment skips, zero failures (85.307s),
`/tmp/aetherscreens-quality-session-core.log`. Later targeted tests pass four cases
(`/tmp/aetherscreens-quality-targeted-tests.log`), including saved vs temporary
session construction, inactive-session guard and real TCP negotiated pixel formats/
unchanged framebuffer size and pointer coordinates. New targeted case was added
after the full run; no final 211-case full-suite claim. iOS test build succeeds
(`/tmp/aetherscreens-quality-ui-build.log`); strings and diff checks pass.

Quality sheet has not yet been rendered or exercised by UI tests. The controlled
gesture fixture currently ignores SetPixelFormat and sends 32-bit data, so extend
it honestly to negotiate 16-bit frames before testing this workflow. Do not use
that fixture unchanged to claim reduced-color rendering. Apple-server RGB565 and
physical visual acceptance remain open; no commit/push/release.


## Display quality controlled UI acceptance (2026-10-07)

Gesture fixture now validates exact full-color/RGB565 SetPixelFormat and sends
genuine 16-bit little-endian RGB565 Raw or ZRLE compact pixels when negotiated.
Frames log their bitsPerPixel and rawPixelBytes; unsupported formats are rejected
as protocol errors. Restarted only the two previously owned idle fixture PIDs
after exact command validation. Current fixture handles: phone 46223, iPad 7509.

Accepted bundles `build/iphone-display-quality-20261007` and
`build/ipad-display-quality-20261007`: two language cases each, zero skips/failures/
runtime warnings. Each switches full->reduced->full through the actual sheet,
requires new socket identities and full-frame delivery at 16/32 bits respectively,
checks expected raw pixel byte counts, restores the desktop, and verifies unchanged
input bounds plus center click (320,180). Default QA grows to 29 simulator cases
(30 physical); no complete new 29-case run is inferred. Phone attachments exported
and reduced-color Chinese sheet screenshot reviewed:
`1F8CB3F4-FC15-4688-A830-079384FCE74C.png`.

This confirms controlled ZRLE UI switching, not real Apple-server color-depth
compatibility, adaptive quality, saved-device lifecycle UI or physical acceptance.
Core latest added test totals remain as described above. Full Screens parity remains
open. No physical device takeover, remote Git mutation or release.


## Quality lifecycle cleanup (2026-10-07)

Deleting a saved computer now removes only its display-quality preference from the
same UserDefaults domain. DisplayQualityStore is an immutable, Sendable wrapper
over thread-safe UserDefaults, allowing DeviceStore deletion without a detached
main-actor cleanup. A test with two isolated saved computers proves deleted-device
fallback and retention of the other device's reduced-color choice. Quality-triggered
reconnection clears the previous local lock-shortcut notice, matching explicit
reconnect behavior; this is not genuine remote Curtain mode.

Final full core suite passes 212 tests, seven environment skips, zero failures
(84.213s), `/tmp/aetherscreens-quality-lifecycle-core.log`. Latest iOS test build
succeeds (`/tmp/aetherscreens-quality-lifecycle-build.log`), diff check passes.
Selected quality UI results precede this lifecycle cleanup; do not silently relabel
them as complete latest-candidate UI coverage. Broader parity table remains open.
No physical test, Git mutation or release.


## Queued lock shortcut cancellation (2026-10-07)

A real TCP regression reproduced a cancelled local Lock Screen action still
sending Ctrl-Cmd-Q from its queued Task (`/tmp/aetherscreens-lock-callback-red.log`).
The callback now requires the captured connection generation, foreground generation
and latest lock-action identity to match, with the local notice still active.
Generation advance returns its new identity atomically. Rapid true/false/true
toggles send only the final intentional six-event chord. Cancelled true/false sends
no keys. Green TCP test: `/tmp/aetherscreens-lock-callback-green.log`. Connection/
foreground invalidation guards are implemented but not independently exercised
by this cancellation case.

CurtainModeManager documentation now accurately describes a local Lock Screen
shortcut notice, not actual privacy/remote Curtain implementation. Full core suite
passes 213 tests, seven environment skips, zero failures (84.673s),
`/tmp/aetherscreens-lock-callback-core.log`. iOS test build succeeds
(`/tmp/aetherscreens-lock-callback-build.log`); diff check passes. Previous selected
UI passes are not relabeled latest-candidate UI acceptance. Full parity remains open.
No physical-device action, commit, push or release.


## Foreground callback and responsive session title (2026-10-07)

Extended the real TCP lock regression to queue an active lock action, switch away
and back before its Task runs, then require no received keys with the same connected
socket retained. It passes (`/tmp/aetherscreens-lock-foreground-tests.log`). Latest
213-case full-suite result predates this assertion-only extension; connection-
generation invalidation still has no independent case here.

The previously reviewed iPad Observe screenshot exposed the fixed 90-point title
cap truncating even a short host with a status prefix. Toolbar title cap now follows
available width (up to 260 on iOS), reserves room for controls, and supplies the full
accessibility label. macOS preserves a bounded title with small-window allowance.
macOS build succeeds (`/tmp/aetherscreens-responsive-title-mac-build.log`).

Accepted `build/iphone-responsive-session-title-20261007` and
`build/ipad-responsive-session-title-20261007`: rotation mapping and viewport
navigation both pass, zero skips/failures/runtime warnings. Attachments exported;
iPad Observe screenshot `A522C5E8-BC21-44E4-A3F9-8B3D0DEEF13B.png` reviewed and full
Observe/loopback host is visible with primary controls retained. Diff check passes.
No broad performance, complete latest 29-case gate or physical acceptance inferred.
No commit, push or release; full parity table remains open.


## Saved computer App Intent foundation (2026-10-07)

Added ConnectSavedComputerIntent with saved-computer AppEntity selection and a
foreground-only request handoff. Requests buffer in SavedComputerIntentInbox until
DeviceListView mounts, then use the existing UUID saved-link resolver/credential
lookup. The inbox coalesces duplicate pending IDs and drains once. Entity queries
reload stored devices and distinguish duplicate names by ID and host; perform
rejects missing/deleted IDs. No password is included in the handoff or entity.

Apple documentation checked: OpenURLIntent requires universal links and cannot
be used as a custom-scheme opening workaround, so the foreground in-app handoff
is used instead. AppIntentsPackage is registered by iOS and macOS consumers.
https://developer.apple.com/documentation/appintents/openurlintent
https://developer.apple.com/documentation/appintents/appintentspackage

First compile required explicit EntityQuery.init(); fixed. First test compile
required awaiting suggestions outside XCTest autoclosure; fixed. Two isolated
query/inbox tests pass (`/tmp/aetherscreens-intents-tests-2.log`). macOS build
succeeds (`/tmp/aetherscreens-intents-build-2.log`); iOS test build succeeds
(`/tmp/aetherscreens-intents-ios-build-2.log`) with extracted App Intents metadata.
Diff check passes. No full new core suite, real Shortcuts invocation, Siri phrase,
active-session reuse, localized system metadata or widget acceptance is inferred.
These remain next-phase requirements; full parity is open. No release or Git push.


## Saved intent/session reuse boundary (2026-10-07)

A red registry test proved an explicit independent session could be reused by a
normal saved connection (`/tmp/aetherscreens-intent-reuse-red.log`). Registry entries
now carry their saved-reuse eligibility; reusableEntry ignores independent entries.
Saved registrations reuse only eligible sessions. On iOS a received saved link for
the already-presented eligible session returns immediately instead of queuing a
reopening after disconnect. Explicit Observe/credential overrides retain their
independent behavior. The active-session route short-circuit itself still requires
external link/intent UI delivery acceptance.

Full core suite passes 216 tests, seven environment skips, zero failures (87.081s),
`/tmp/aetherscreens-intent-reuse-core.log`; iOS test build succeeds
(`/tmp/aetherscreens-intent-reuse-build.log`), diff check passes.
Both languages of controlled mobile session selection are now running on the latest
candidate: `build/iphone-intent-session-reuse-20261007` and
`build/ipad-intent-session-reuse-20261007`; runner logs
`/tmp/aetherscreens-intent-session-phone-runner.log` and
`/tmp/aetherscreens-intent-session-ipad-runner.log`. They are not accepted yet and
cannot substitute for system Shortcuts invocation/Siri/widget acceptance.
No physical device action, commit, push or release. Full parity remains open.


## Shortcut provider metadata and session UI regression (2026-10-07)

Accepted latest session-selection bundles `build/iphone-intent-session-reuse-20261007`
and `build/ipad-intent-session-reuse-20261007`: both languages pass, no skips,
failures or runtime warnings. This is session-selection acceptance, not actual
external App Intent delivery or active-link short-circuit UI acceptance.

Added action parameter summary and localized missing-computer error description.
App Shortcuts declaration initially compiled in the shared module but actual app
metadata had an empty autoShortcuts list. Moved providers into each app consumer.
Final iOS metadata now contains one autoShortcut targeting ConnectSavedComputerIntent
and both parameterized/unparameterized applicationName phrase templates. Do not
infer Siri recognition or Shortcuts execution from generated metadata.

Final iOS build `/tmp/aetherscreens-shortcuts-provider-build-2.log` and macOS build
`/tmp/aetherscreens-shortcuts-provider-mac-build-2.log` pass. Query/inbox/session
targeted suite passes seven cases (`/tmp/aetherscreens-shortcuts-provider-tests.log`).
Diff check passes. System action/phrase localization, Siri, Shortcuts runtime and
widgets remain open. No physical device takeover, commit, push or release.
Reference: https://developer.apple.com/documentation/appintents/appshortcutsprovider

## System Shortcuts discovery evidence (2026-10-07)

Latest full core suite: 216 tests, seven environment-dependent skips, zero failures
in 89.039 seconds (`/tmp/aetherscreens-current-core-20261007.log`).
Isolated iPhone simulator system Shortcuts search finds the actual
`Connect to Computer` action: accepted one diagnostic case, no skips/failures/runtime
warnings, `build/iphone-shortcuts-action-search-20261007`. Exported hierarchy contains
an action Cell and StaticText, distinct from the search field value. Earlier catalog
and editor bundles prove only system launch/editor access. This diagnostic remains
explicit-only in the runner, outside the 29-case default functional gate.
Actual parameter selection, execution, foreground connection, Siri and widget
acceptance remain open. No physical device takeover, commit, push or release.

## System Shortcuts connection accepted (2026-10-07)

`build/iphone-shortcuts-connection-20261007` passes the explicit isolated iPhone
simulator case: actual system action search, add action, saved entity picker,
execution, foreground app, rendered remote canvas, and received pointer
sequence (mask 0/1/0 at 320,180). Exported connected-session screenshot visually
reviewed: named QA Shortcut Fixture, green connection state and arrow cursor.
This is actual system runtime acceptance on the controlled RFB fixture, not Siri
recognition or physical Apple-server acceptance. Repeated invocation/reuse is
being tested separately; widget and system localization remain open.

## Repeated system Shortcut session reuse accepted (2026-10-07)

`build/iphone-shortcuts-session-reuse-20261007`: actual system action selected and
executed twice, passes one test with zero skips/failures/runtime warnings. Second
execution returns to the existing remote canvas, receives another click on the
same fixture connection, and leaves exactly one `ready` handshake since the reset
before first execution. This covers cold app delivery and repeat active-session
routing through the system action, not just SessionRegistry unit tests.
The test is simulator-only and remains explicit-only; default functional suite
still has 29 cases. Isolated QA saved computer/shortcuts live only in the owned
simulator. Physical compatibility, Siri, widget, system localization and whole
latest default gate remain open. No commit, push or release.

## Chinese system action accepted on fresh install (2026-10-07)

Added main app en/zh-Hans Localizable.strings for title/entity/parameter summary
and AppShortcuts.strings for both applicationName phrases. Both iOS project
resource membership and macOS packaging already include assets/localization.
Built iOS app tables inspected with plutil: all Chinese entries present.
First existing-install action search failed (retained iphone-shortcuts-chinese-20261007).
An attempted module-bundle resource reference was rejected by Xcode AppIntents
metadata export, which explicitly requires the main bundle; source reverted to
main-bundle literals. swift build passed; final runner build also passed.
Only optional simctl diagnostic child PID 34059 was stopped after test failure,
with exact parent/path/owned UDID validation and owned-diagnostic-stop.json.

Reinstalled only the owned isolated simulator app; test recreated its QA computer.
`build/iphone-shortcuts-chinese-fresh-20261007` passes actual Chinese system search,
parameter selection, first execution and repeated live-connection reuse; zero
skips/failures/runtime warnings. Exported hierarchy confirms navigation title
连接电脑, summary 连接到 and parameter 电脑 with QA Shortcut Fixture value.
Chinese phrase resource packaging is verified; spoken Siri recognition is not.
Explicit case requires the simulator's Chinese system UI. Main default 29-case
functional gate remains separate. No physical device action, commit or release.
Sources: https://developer.apple.com/documentation/foundation/localizedstringresource
and https://developer.apple.com/videos/play/wwdc2022/10170/

## Latest complete controlled gate started (2026-10-07)

Current candidate full default functional suite dispatched on independent owned
simulators and distinct fixture ports: 29 requested cases per device.
Phone: build/iphone-current-full-20261007, runner handle 37325,
/tmp/aetherscreens-iphone-current-full-runner.log.
iPad: build/ipad-current-full-20261007, runner handle 28826,
/tmp/aetherscreens-ipad-current-full-runner.log.
Both xcodebuild test-without-building processes verified live, no competing
xcodebuild on either owned UDID. Fixtures PID 20249/20253 verified live on
6031/6032/8791 and 6021/6022/8781 respectively. Do not accept before terminal
summary confirms all 29 cases, no skips/failures/runtime warnings. Do not restart
these runs on an observation timeout. System Shortcuts explicit acceptance remains
separate. Physical devices remain deferred.

Official feature list refreshed: https://edovia.com/en/screens and
https://help.edovia.com/en/screens-5/features/ still confirm SSH, file transfers,
Curtain Mode, sync, adaptive quality and platform integration in the broad parity
scope. Current core/controlled evidence does not prove those absent capabilities.

## Latest complete controlled gate accepted (2026-10-07)

Both current-candidate default suites terminal exit zero and authoritative
summary.json results inspected:
- build/iphone-current-full-20261007: 29/29 pass, zero failures/skips,
  empty runtimeWarnings/testFailures, 1629.405 seconds.
- build/ipad-current-full-20261007: 29/29 pass, zero failures/skips,
  empty runtimeWarnings/testFailures, 1600.848 seconds.
Neither bundle has a device-interference.json. Both runner logs explicitly confirm
all requested cases executed. Same candidate held unchanged during these runs.
Covers both language variants of current toolbars, session selection, display
quality/selection, timeout/reconnect, viewport navigation, explicit zoomed edge
follow and received native gestures, plus toolbar rotation. System Shortcuts
Chinese/English runtime evidence remains in separate explicitly selected bundles.

Attachments exported for visual review in each bundle's attachments directory.
This is controlled simulator/RFB fixture acceptance; no physical Apple server,
hardware/Pencil callbacks, real IME, frame-rate/input-to-present performance or
remaining missing parity capabilities inferred. Full goal remains open. No
commit, push, release, or physical device takeover.

## On-disconnect action preference foundation (2026-10-07)

Official behavior checked at
https://help.edovia.com/en/screens-5/features/on-disconnect-actions : user-selected
action runs immediately before disconnect; lock/log out/Ctrl-Alt-Del/hot corners.
Added DisconnectAction enumeration and isolated per-computer defaults store.
Default/missing/unknown values are none; platform-incompatible preferences are
ignored. Mac actions limited to Mac; Ctrl-Alt-Delete to Windows/Linux. Deleting
a computer removes only its preference in DeviceStore's same defaults domain.
Targeted persistence/platform/deletion suite passes three tests, zero failures:
/tmp/aetherscreens-disconnect-action-lifecycle-tests.log. Diff check passes.

Not connected to session shutdown or UI yet. RFBClient.disconnect immediately
cancels NWConnection; firing key events then canceling can lose buffered actions.
Need completion-based outgoing action drain tied to the current connection,
explicit-user-close versus network loss/rotation distinctions, Observe guards,
all configured actions and actual-TCP pre-EOF acceptance before calling supported.
Earlier 29/29 simulator gate predates this new foundation. No real remote action,
physical-device use, commit/push/release. Full goal remains open.

## Final key sequence transport foundation (2026-10-07)

Added RFBClient.disconnect(afterSendingKeySequence:): releases tracked input,
blocks new input, sends one final complete packet with outgoing isComplete,
closes on contentProcessed, with two-second fallback. Completion/fallback check
captured NWConnection identity before closing. Repeat request while draining
returns without canceling or sending duplicate actions.
Real TCP test sends the complete Ctrl-Cmd-Q lock sequence and asserts server's
exact six received key events including releases after two immediate requests.
PointerTransportTests passes all 17 cases with no failures in 39.337 seconds:
/tmp/aetherscreens-disconnect-pointer-regression.log. Diff check passes.
This primitive is not integrated into session/UI; does not yet implement corner
packets, all disconnect actions, explicit-close versus onDisappear rules or
replacement-socket/timeout regression. No remote lock on a real Mac; controlled
TCP receipt is not remote OS lock acceptance. Full goal remains open.

## Graceful disconnect replacement/Observe boundaries (2026-10-07)

Actual TCP targeted suite passes three cases, zero failures in 2.519 seconds:
/tmp/aetherscreens-disconnect-boundary-tests.log. Covers complete final lock chord
with duplicate request; close first socket then establish replacement, wait beyond
old two-second fallback and send/receive Escape on replacement; Observe input
blocked before disconnect yields no remote keys and disconnected client state.
No forced stalled-send timeout-path acceptance or old completion race separately
verified. Session/UI integration, hot corners, logout and Ctrl-Alt-Delete actions
remain incomplete. Existing simulator gate predates this transport foundation;
no physical remote action, commit/push/release. Full goal remains open.

## All disconnect action packet foundation (2026-10-07)

Shared final-packet drain now accepts either key sequences or configured
DisconnectAction through RFBClient.disconnect(performing:deviceType:). Actions
encode lock, immediate Mac logout (Option-Shift-Cmd-Q), Windows/Linux Ctrl-Alt-Del,
and four Mac hot corners. Corners move first to desktop center then selected
outer pixel with zero button mask; invalid dimensions/platform yield no action.
Apple logout reference: https://support.apple.com/en-gb/102650 .

Persistence/packet unit suite four cases passes zero failures:
/tmp/aetherscreens-disconnect-action-packet-tests.log. Shared drain TCP boundary
plus persistence subset five cases passed before added packet unit cases:
/tmp/aetherscreens-disconnect-packets-tests.log. Diff check passes.
No settings/explicit-close integration yet; not a supported end-to-end product
feature. Actual remote logout, hot corners, OS handling and multi-display desktop
corner compatibility remain unaccepted. No physical remote actions or release.

## Explicit disconnect and edit settings integration (2026-10-07)

EditDeviceSheet adds localized platform-filtered per-computer action Picker,
loads on edit, persists on Save only; switching platform resets incompatible
selection. Logout selection explains immediate logout/save work. Added English
and Chinese action labels/footer. Explicit registry close and desktop/Carousel
Disconnect call requestDisconnect; onDisappear retains normal cleanup.

Integration test initially reproduced endSession -> cancelPasswordPrompt ->
immediate socket close, losing configured chord (retained failure log
/tmp/aetherscreens-disconnect-explicit-close-test.log). Extracted prompt clearing
from cancel/disconnect; explicit close marks the VM and clears without immediate
cancel, then sends configured final packet. Subsequent disappearance cannot cancel
that drain, duplicate requests ignored, startSession resets marker. Transport stays
retained through send completion/two-second fallback after UI releases ownership.

Actual TCP test proves lifecycle close sends nothing; reconnect, explicit close,
immediate endSession and repeated close sends exactly six lock chord events.
Final combined suite 29 tests/zero failures in 42.830 seconds:
/tmp/aetherscreens-disconnect-integrated-final-tests.log. Final iOS simulator build
passes /tmp/aetherscreens-disconnect-settings-ios-final-build.log. Diff check passes.
New settings UI not yet visually/automatically accepted; full 29-per-device UI gate
predates this integration. Real remote OS effects and remaining parity stay open.
No physical actions, commit/push/release.

## iPhone disconnect settings/action UI accepted (2026-10-07)

Explicit testControlledDisconnectAction added outside default CASES while under
acceptance: edit saved controlled computer, choose Lock Screen, Save, reopen and
verify selection, connect fixture, click Disconnect, assert exact received keys
65507/65515/113/113/65515/65507 and down 1/1/1/0/0/0, restore No Action.
First bundle iphone-disconnect-action-20261007 failed because native menu Picker
AX value was empty; exported hierarchy already showed selected Lock Screen in
label (persistence worked). Added explicit localized accessibilityValue to Picker.
Retained failure bundle. Optional owned diagnostic stop script found process
already terminal and did not stop any process.

build/iphone-disconnect-action-20261007-run-2 passes one case, zero skips/failures/
runtime warnings. Exported A82ACCE9-9454-4810-A81D-1BF33D5201BB.png visually reviewed:
selection and primary controls fit; port numeric keyboard visible beneath form.
English iPhone fixture acceptance only; Chinese/iPad/settings cancel/platform
filter and other actions remain to cover. Actual Mac OS lock not implied.
No physical-device action, commit/push/release. Full goal remains open.

## Disconnect action language/device follow-up (2026-10-07)

Refactored explicit disconnect UI case into same verifier for English/Chinese;
localized loopback saved-computer helper. iPhone bundle
build/iphone-disconnect-action-languages-20261007 accepts both cases, zero skips/
failures/runtime warnings, including exact configured lock wire sequence and
restore No Action. iPad first bundle retains two failures: snapshot after Save
before saved card exists; legacy Command-A port replacement produced 59995900.
Updated helper to existing replacePort and explicit card wait before scrolling.
No product rollback or masked failure. New iPad owned run remains live:
build/ipad-disconnect-action-languages-20261007-run-2, handle 54023,
/tmp/aetherscreens-ipad-disconnect-languages-runner-2.log. Re-poll same handle;
do not accept before authoritative terminal output. Default 29-case UI suite
unchanged; disconnect cases still explicit-only. No physical use or release.

## iPad numeric caret follow-up (2026-10-07)

Run-2 also failed port replacement in both languages, retaining result. Viewed
DBA04A18-AB66-444C-A7FA-0EE805C14FAB.png: native floating number pad overlaps trailing
port text field area. Added keyboard-navigation caret placement instead of tapping
trailing coordinate. Run-3 still failed; command log proves conditional keyboard
frame-overlap branch was not entered, so it still tapped [0.98,0.50]. Changed
condition to iPad idiom to avoid inaccurate reported floating-keyboard bounds.
Run-4 live handle 30504 at build/ipad-disconnect-action-languages-20261007-run-4,
/tmp/aetherscreens-ipad-disconnect-languages-runner-4.log; not accepted yet.
Owned optional diagnostic PIDs 53353/53983 stopped only after each test terminal
failure with exact parent/path/UDID verification recorded in each bundle.
No changes to product behavior in this step; test input helper only. iPhone
language acceptance stays valid; iPad and full new-candidate gate remain open.

## Latest disconnect candidate core gate (2026-10-07)

Full swift test completed with 224 tests, 7 explicit environment skips, zero
failures in 87.434 seconds; terminal handle 76040 exit 0. Evidence:
/tmp/aetherscreens-current-core-disconnect-20261007.log. This covers latest
product disconnect changes; previous 29-case/device UI gate predates them.

iPad runs 4 and 5 retained two input-setup failures each (59995900); hardware
Command-Right and double-tap did not select/remove the existing number. Run 5
optional owned diagnostic PID 57390 was validated against parent xcodebuild 57291,
exact bundle path and UDID, then stopped after terminal test failure; JSON retained.
Updated iPad helper to native edit-menu Select All with explicit existence assertion.
Run 6 remains live, handle 99211, build/ipad-disconnect-action-languages-20261007-run-6,
/tmp/aetherscreens-ipad-disconnect-languages-runner-6.log. No iPad acceptance yet.
Capability table updated to reflect current Shortcuts execution/localization and
scoped disconnect implementation; broad parity and physical gates remain open.

## Explicit-close restart regression (2026-10-07)

Extended real-TCP explicit-close case to restart the same SessionViewModel and
require actual Escape down/up delivery. It reproduced a product bug: final-packet
drain disables input, but startSession did not restore the foreground/Observe
policy. Before-fix /tmp/aetherscreens-explicit-disconnect-restart-before.log fails
with missing restarted input. startSession now restores input only for foreground
control sessions. After-fix /tmp/aetherscreens-explicit-disconnect-restart-after.log
accepts all 20 PointerTransportTests, zero skips/failures, terminal handle 79402
exit 0, 42.847 seconds. Full 224-test gate above predates this last one-line fix;
new targeted suite validates the change.

iPad run 6 native Select All menu was not available; retained two failures.
Owned diagnostic 58144/parent 57638 stopped after terminal tests, proof retained.
Run 7 changes caret placement to trailing coordinate before opening numeric pad
(no preceding center tap on iPad), live handle 96900,
build/ipad-disconnect-action-languages-20261007-run-7. No acceptance claimed yet.

## Numeric keyboard usability follow-up (2026-10-08)

iPad run 7 successfully replaced the port but native Save hit testing returned
{-1,-1} with floating numeric keyboard open; both cases failed before saved-card
creation, result retained. Optional diagnostic 58555 ended independently before
validated stop script could inspect it; no signal was sent. Runner 96900 exit 1.
Added port focus and native keyboard Done accessory to Add/Edit sheets (UIKit
only); test helper explicitly dismisses it after validating numeric text. This is
a real numeric-entry usability change, not seeded QA data or hidden test bypass.
Owned runs live: iPad run 8 handle 30090, iPhone keyboard-done handle 43833,
with existing isolated fixtures/derived directories; no acceptance yet.
macOS build handle 13884 also live. No physical device, commit or release.

## Keyboard warning and iPad hit-testing follow-up (2026-10-08)

iPad run 8 reaches saved-computer editing but cannot open disconnect action menu;
retained two failures and two Invalid frame dimension runtime warnings. Exported
attachments/video frame confirm keyboard remains focused after the accessory tap.
iPhone keyboard-done first run executes both cases successfully but same two
runtime warnings prevent runner acceptance (43833 exit 1). Optional diagnostic
59253/parent 58907 validated/stopped after both tests terminal pass; proof retained.

Made keyboard accessory content stable rather than empty while focus changes,
and Done resigns the current responder as well as resetting port focus. This also
allows Done to dismiss other form keyboards. Test uses element-relative coordinate
for Done/picker to avoid the observed iPad automatic hit-test mismatch.
New owned candidate: iPad run 9 handle 53846, iPhone run 2 handle 24051. Both
bundles retain strict zero-warning acceptance checks. Final macOS build 10268 live.
No new test bundle accepted in this follow-up yet; prior passing gates retained
as historical scoped evidence, full parity and physical performance remain open.

## Native numeric-entry candidate (2026-10-08)

Stable SwiftUI keyboard toolbar did not remove frame warnings: iPhone run 2
executed both cases but remains unaccepted due two warnings, runner 24051 exit 1.
iPad run 9 failed action-menu selection with warnings, runner 53846 exit 1.
Owned diagnostic 61311/60382 and 60788/60095 stopped after exact ownership and
terminal test validation; JSON retained. This does not prove old simulator state
was the cause; new iPad A9F8BF45-23CE-4458-9C22-8ED898729570 created only for
this task and remains live test handle 48028 at build/ipad-disconnect-fresh-20261008.
That run built the previous SwiftUI accessory candidate.

New PortTextField uses UIKit UITextField/UIToolbar Done accessory on iOS, keeping
SwiftUI TextField on macOS; avoids transient SwiftUI keyboard toolbar layout and
resigns the exact field. Add/Edit use the shared component. Native candidate
macOS build passes, handle 23545 exit 0, /tmp/aetherscreens-native-port-macos-build.log.
iPhone native candidate run live 38352 at build/iphone-disconnect-native-port-20261008.
No candidate UI acceptance claimed before terminal summary/warning checks.

## Native numeric-entry first acceptance (2026-10-08)

Fresh iPad with previous SwiftUI accessory completed both action cases but retains
two frame warnings; runner 48028 exit 1, no acceptance. This confirms old simulator
state affected earlier hit testing, while warning remains reproducible separately.

Native PortTextField iPhone candidate accepts both English/Chinese cases: 2 passed,
zero failures/skips/runtime warnings, handle 38352 exit 0,
build/iphone-disconnect-native-port-20261008/summary.json. This includes actual TCP
lock sequence, preference reopen and reset to No Action, plus keyboard Done.
Native candidate macOS final build passes, handle 49237 exit 0; kept 44-point
port touch height UIKit-only so macOS field remains compact.
Native iPad same code run live 93114 at build/ipad-disconnect-native-port-20261008
on task-owned fresh A9F8BF45-23CE-4458-9C22-8ED898729570. Physical/whole parity
still open; latest full 29-case/device gate predates these form changes.

## Native numeric-entry and disconnect gate accepted (2026-10-08)

Final owned iPad native-port run completed, handle 93114 exit 0:
build/ipad-disconnect-native-port-20261008, 2 passed, zero failures/skips/runtime
warnings. Same English/Chinese full action verifier as accepted iPhone native
bundle (38352 exit 0): port entry and Done, settings save/reopen, actual framebuffer
connection and exact six-key lock chord, reset No Action. Native field preserves
localization and removes earlier reproducible keyboard frame warnings in both
controlled environments. iPhone and iPad Chinese settings screenshots reviewed; keyboard dismissed,
Save visible, localized selection/footer correctly displayed. Latest native macOS build 49237 exit 0;
diff whitespace and QA Python compilation pass.

This gate is scoped to new forms/disconnect flow; historical 29-case/device full
UI gate is not relabeled as latest native candidate full acceptance. Full parity
goal remains active: true Curtain, SSH, file transfer, sync, adaptive/Apple quality,
clipboard compatibility and platform extensions remain separate work; physical
IME/peripherals/latency/drop frames remain deferred by human. No commit/push/release.

## SSH security foundation (2026-10-08)

Previous goal turn classified as progress: native numeric-entry and disconnect
flow acceptance changed authoritative code/test state. Current turn advances
the broad SSH gap with security foundations, not a secure-session completion claim.

New SSHServerAddress/SSHConnectionSettings validate host/port/account/remote target
on construction and decoding; config stores a private-key UUID reference, no key
material or password. SSHHostKey fingerprints validated public-key blobs using
SHA256; independent system ssh-keygen public-only fixture matches exactly.
SSHHostTrustStore persists per canonical host/port (DNS case/trailing dot, IPv6
representation), recognizes known/unknown/changed keys, requires exact previous
key for change approval, and rejects stale concurrent approvals/deletions.
Damaged data raises an error; it is not silently replaced or treated as first use.

SSHCredentialStore uses a separate Keychain service, kind/reference namespaces,
ThisDeviceOnly accessibility and no synchronization/cache fallback. Updates use
SecItemUpdate rather than deleting an old credential first. Denied save/read/add/
delete stay errors; rejected replacement preserves existing data. Real Keychain QA
used only a unique test service and dummy values; all owned items deleted.

Final /tmp/aetherscreens-ssh-security-foundation-tests-final.log: 11 tests, zero
skips/failures, 0.180 seconds, handle 40881 exit 0. Includes actual system Keychain
round trips and simultaneous first-use decisions across two trust-store instances.
Earlier first run retained a bracketed-DNS validation failure; fixed by allowing
brackets only for valid IPv6 (also rejects host control characters).
iOS simulator build /tmp/aetherscreens-ssh-foundation-ios-build.log succeeded,
56696 exit 0. Sources not wired into app settings or direct RFB routing yet; no
secure toggle falsely claims encrypted transport. No production dependency added.

Official Apple SwiftNIO SSH 0.15.0 fetched into ignored owned build reference
for next forwarding implementation. Verified package minimum Swift tools 6.1,
iOS 13/macOS 10.15, current compiler Swift 6.4; password/public-key auth and direct
TCP forwarding API inspected. Its accept-all-host-keys example is intentionally
not adopted. Ed25519/ECDSA supported; RSA/import compatibility remains a separate
requirement before claiming Screens key parity.

References: https://help.edovia.com/en/screens-5/features/ssh-keys
https://github.com/apple/swift-nio-ssh/tree/0.15.0
https://www.rfc-editor.org/rfc/rfc4253.html
https://man.openbsd.org/ssh-keygen

Next: real authenticated forwarding, cancellation/lifecycle and blocked/changed
host prompts, then settings/key import and actual server UI proof. Physical
acceptance still deferred by human; no commit, push or release. Full goal active.

SSH foundation final macOS app build also succeeds: handle 93717 exit 0,
/tmp/aetherscreens-ssh-security-foundation-macos-build-final.log. Diff check passes.

## Authenticated SSH forwarding and RFB core transport (2026-10-08)

Previous goal turn was progress (host trust, strict credential persistence and
verified builds). This turn adds Apple SwiftNIO SSH 0.15.0 and NIO 2.81.0 exact
dependencies; root resolved graph keeps Collections 1.2.1 (5.10 tools), avoiding
the initial 1.7.2 resolution's 6.4 requirement. SSH/crypto/system/ASN1 currently
require Swift tools 6.1; local accepted compiler is 6.4, deployment targets remain
iOS 17/macOS 14. No CI success claim or CI/release configuration change.

SSHForwardingTunnel authenticates password over verified SSH, binds only
127.0.0.1 with an ephemeral port and opens direct-TCP channels to the configured
remote target. Pending/local/SSH child channels belong to one captured attempt;
stop, timeout, task cancellation or replacement close only that attempt.
One-shot completion guards avoid promise races. Network timeout pauses while
awaiting human host identity confirmation; resumed timeout and cancellation
cannot revive an old connection or persist a late approval. Event-loop-confined
handlers stay in NIOLoopBound rather than crossing the actor as Sendable objects.
Wrong password/declined key fail without a published listener. Private-key auth
is explicitly unsupported in this candidate, never silently downgraded.

Glue with read backpressure/half-close behavior is adapted from Apple's Apache-2
example with original attribution and bundled license. Transitive dependency
licenses/notices also bundled in Resources/ThirdPartyNotices. Codec and fixture
use real SSH channel bytes, not a simulated encryption switch or plaintext proxy.

RFBClient can configure a loopback forwarding socket only while disconnected or
failed; logical remote host/port and RFB credentials stay intact. It never reports
local proxy RTT as remote latency. No saved computer/settings currently enables
this core adapter yet; app session setup, teardown/drain, prompts and UI remain
open, so there is no app secure-connection completion claim.

Accepted /tmp/aetherscreens-ssh-forwarding-rfb-tests.log: 7 tests, zero failures/
skips, 3.819 seconds, handle 69368 exit 0. Actual SSH server accepts credentials
and direct-TCP target; 2 MiB exact echo, trusted reuse, wrong password, identity
rejection before any credential request, same-address server-key change, paused
human confirmation timeout, cancellation/late approval and replacement checked.
RFB integration uses an unresolvable logical host to detect accidental direct
fallback: real 16x16 green pixels and the entire six-event final lock chord arrive
through SSH. RTT inverse assertion crosses the reporting deadline.
Earlier first test build failed due async XCTest autoclosure/throwing getter use;
fixed by awaiting before assertion and preserving the build failure log.

Full current core /tmp/aetherscreens-ssh-forwarding-full-core.log: 242 tests,
7 explicit environment skips, zero failures, 91.507 seconds, handle 19798 exit 0.
Keychain QA explicitly enabled using isolated dummy credentials. iOS current
code build /tmp/aetherscreens-ssh-forwarding-ios-build-final.log succeeded,
97222 exit 0. Final license-resource rebuild 41142 remains live; re-poll same
handle and inspect actual bundled notices. Diff whitespace check passes.

Next integration must keep these boundaries: SSH-enabled sessions cannot call
direct client.connect on failed/awaiting tunnel; password/host prompts need
session-generation cancellation; each restart needs its own tunnel so late
cleanup cannot close its replacement. Explicit disconnect must retain/drain the
tunnel for the final chord before closing parent SSH; ordinary disappearance
closes without remote actions. Then native settings/key import and UI/wire gates.
Real Mac/iPhone SSH interoperability and performance remain deferred/unproven.
No physical device use, commit, push, tag or release. Full parity goal active.

Primary implementation reference: https://github.com/apple/swift-nio-ssh/tree/0.15.0

License-resource iOS rebuild 41142 completed exit 0. Actual app bundle contains
SwiftNIO-SSH-LICENSE.txt, swift-nio-NOTICE.txt and swift-crypto-NOTICE.txt
(and remaining dependency licenses). Final diff check passes; no live gate pending
for this core-transport phase. App integration and full parity remain open.

### Required SSH forwarding policy (2026-10-08)

RFBClient now accepts an immutable requiresLoopbackForwarding policy. A secure
client without an assigned loopback port fails before creating any TCP socket;
clearing a previously assigned port cannot turn this policy into a direct
connection. Existing direct clients retain their default behavior. The real
SSH framebuffer/final-chord test now exercises this required policy as well.

Accepted /tmp/aetherscreens-ssh-required-forwarding-tests.log: eight SSH tests,
zero failures/skips, 3.848 seconds, handle 73378 exit 0. New regression covers
missing forwarding and clearing configured forwarding with a listening direct
target. App settings/prompts/session lifetime integration remains open; this
does not claim a usable saved SSH connection UI. No physical acceptance or release.

iOS Simulator build /tmp/aetherscreens-ssh-required-forwarding-ios-build.log
completed successfully, handle 87383 exit 0. Diff whitespace check passes.

### SSH session integration and native confirmation (2026-10-08)

RemoteDevice now serializes optional validated SSH settings, preserving legacy
devices as direct connections. SessionViewModel creates a separate tunnel per
attempt and enforces required forwarding on its RFBClient. SSH vault reads fail
closed; missing passwords prompt separately from VNC authentication. Temporary
sessions cannot persist SSH passwords. Denied saves keep the prompt and show an
error. Password and host-confirmation continuations are cancelled on local end,
restart or explicit cancel. Prompt identities reject stale dismissal/approval.

Native SessionSSHSheet shows the SSH server/account, secure password input and
Keychain preference. Host identity displays selectable SHA256 fingerprints;
changed keys include the previous fingerprint and a verification warning. English
and Simplified Chinese strings included. Private-key authentication still fails
explicitly; import/authentication remains open. No settings form yet exposes SSH.

Explicit disconnect detaches and retains its tunnel through forwarded-stream
drain (three-second upper bound), so subsequent local disappearance cannot close
the SSH parent early. Late old-tunnel cleanup cannot stop a replacement. Actual
SessionViewModel tests cover password/host prompts, cancellation before credentials,
trusted restart, framebuffer delivery, complete final lock chord, immediate local
end, repeated close, denied vault reads/writes and legacy device decoding.

Initial full regression /tmp/aetherscreens-ssh-session-full-core.log found an
intermittent lost final chord despite the isolated lifecycle suite passing.
Forwarding glue now flushes and awaits pending write promises before requested
full/half close, instead of discarding queued SSH writes. The failure log is kept.
Final iOS build /tmp/aetherscreens-ssh-session-ios-build-drain-fix.log succeeded,
handle 21057 exit 0. Native sheet visual/device acceptance remains open, alongside
saved/add/quick settings, SSH key management and full Screens parity. No commit,
push, physical-device use or release.

Accepted full core /tmp/aetherscreens-ssh-session-full-core-drain-fix.log:
247 tests, seven explicit environment skips, zero failures, 91.878 seconds,
handle 80736 exit 0; isolated real OS Keychain QA enabled. All twelve SSH tests
passed in the full regression. Diff whitespace check passes.

Immediate explicit disconnect/local end/reconnect repeated twenty times using the
built test binary: /tmp/aetherscreens-ssh-session-drain-repeat.log, handle 79877
exit 0, twenty successful runs, no failed expectations. This additional run is
scoped to the previously observed intermittent drain failure.

### SSH configuration and credential lifecycle (2026-10-08, scoped UI gates accepted)

SSHConnectionDraft validates form data without serializing passwords. Native
SSHConnectionFields is shared by add, saved edit and temporary/saved quick connect.
It separates the SSH account/server from the desktop account and forwarding target.
Numeric ports have distinct accessibility labels and select their existing value
after native focus; SSH text/password fields dismiss their keyboard on Done.
Existing key references round-trip without being silently changed to password auth;
key authentication/import is still explicitly unavailable.

ConnectionRequest carries an optional SSH password only in memory. Saved requests
keep the exact device ID when associating vault credentials. Temporary requests
pass their password to the session without reading/writing the vault or device
defaults, verified through actual SSH/RFB framebuffer delivery. Saved changes write
the vault before persisting the computer; denied writes retain the prior device.
Changing server identity/account/authentication clears stale passwords; canonical
host spelling or a forwarding target change preserves the same login. Device
deletion fails visibly and keeps its configuration when SSH-password deletion is
denied, and never deletes shared private-key references. Vault failures report OS
status only in diagnostics and a system error description in the configuration UI.

Accepted /tmp/aetherscreens-ssh-settings-full-core-final.log: 254 tests, seven
environment skips, zero failures, 93.946 seconds, handle 12647 exit 0; real OS
Keychain opt-in enabled. After localized vault-error reporting was added, targeted
/tmp/aetherscreens-ssh-settings-vault-error-tests.log passed all 23 credential,
configuration and SSH transport/session tests, zero skips/failures, 4.414 seconds,
handle 38583 exit 0. Diff whitespace check passes.

UI failures are retained in build/*-ssh-settings-* artifacts: initial orientation
API compilation error; centered switch hit, lazy/offscreen form queries and port
replacement; missing simulator Keychain access; host ad-hoc restricted-entitlement
launch refusal (AMFI -424); global entitlements affecting static Swift-package
objects; test-plan filename discovery. These are not accepted UI evidence. Current
runner scopes isolated QA entitlements only to the app target in a disposable
sibling Xcode project, leaves production project/signing untouched and verifies
fresh generated test plans. Temporary project paths are recorded per run and
cleaned at normal runner exit. Saved fixture SSH state and sheet scroll positions
are reconditioned through native UI for the controlled direct-RFB cases.

The target-plan runs (47108/90975) are terminal failures, retained as evidence.
The subsequent autofill runs (69010/73477) are also terminal exit 1, each 3/4:
phone Chinese SSH settings and both disconnect cases passed; iPad English SSH
settings and both disconnect cases passed. Actual dummy-password Keychain saves,
reload and clearing are exercised in the passing settings cases. The OS password
manager's save offer is declined so QA credentials stay out of that separate store.
Rendered passing phone Chinese/iPad English forms have been inspected.

Failures were inspected through screenshots and accessibility hierarchies:
iPad's initial global downward swipe dismissed the edit sheet; phone's switch
was marked hittable while almost entirely below the viewport. The SSH-settings
helpers now drag the Form collection view, require the entire control frame to
be visible and tap the nested native switch when available.
Owned post-test simctl diagnostic collectors were terminated only after terminal
suite results; scoped evidence is retained in each run's diagnose-cleanup.json.

Replacement SSH settings gates are accepted, both terminal exit 0:
phone handle 58757, build/iphone-ssh-settings-form-scroll-20261008;
iPad handle 99942, build/ipad-ssh-settings-form-scroll-20261008.
Each executed exactly the two requested English/Chinese cases, with zero skips,
failures or result-summary runtime warnings. Test builds succeeded on both.
All twelve saved/reloaded/temporary configuration screenshots were exported and
visually inspected; native forms have no horizontal layout overflow. Secure text
is redacted by XCTest captures. Scoped SSH settings gates and the four prior
passing disconnect cases do not replace the entire UI release suite.

Physical iPhone/Mac SSH acceptance, host-confirmation sheet visual acceptance,
private-key import/authentication, file transfer, sync, real privacy Curtain and
full parity remain open. Continuous real-device performance, IME and peripherals
also remain unaccepted. No commit, push, tag, release or physical-device use.
The full goal remains active; this is one accepted implementation phase.

Primary entitlement reference:
https://developer.apple.com/documentation/security/errsecmissingentitlement

### SSH private-key import and authentication (2026-10-08, native importer gate pending)

SSHPrivateKey decodes bounded (64 KB) unencrypted OpenSSH Ed25519 and ECDSA
nistp256/384/521 keys and ECDSA PEM through CryptoKit. It validates check integers,
lengths, curves, scalar bounds, derived public keys, outer public-key blobs and
padding, reports generic localized errors, and never logs imported material.
System ssh-keygen is an independent oracle for all four key types and SHA256
fingerprints; generated QA files are isolated and removed by test teardown.
An initial parser failure showed OpenSSH can omit padding for aligned content;
this was verified against openssh-portable/sshkey.c and corrected, retaining the
failed log /tmp/aetherscreens-private-key-targeted-final-fixed.log.

Native shared configuration now selects Password/Private Key and imports or
replaces a key through the system file picker. Imported bytes and fingerprints
remain in draft memory until Save; invalid replacements preserve the selection.
Saved keys are written to the independent SSH vault using a new UUID reference,
never serialized into device defaults or used to overwrite existing shared keys.
Temporary keys pass in memory directly to the session without vault access.
Transport offers only the selected authentication method; wrong-key tests prove
no forwarding listener is published. Temporary key-auth sessions receive a real
RFB framebuffer through SSH, with vault reads/writes denied.

Accepted /tmp/aetherscreens-private-key-targeted-padding-fixed.log: 30 tests,
zero skips/failures, 5.385 seconds, handle 78697 exit 0, real Keychain QA enabled.
Full /tmp/aetherscreens-private-key-full-core.log: 261 tests, seven environment
skips, zero failures, 94.137 seconds, handle 10433 exit 0.
Final generic iOS build /tmp/aetherscreens-private-key-ios-build-final.log: handle
9482 exit 0. Owned phone/iPad password-settings regression each passed both
languages, handles 8532/11124 exit 0, artifacts build/*-private-key-settings-20261008.
These cases do not exercise importing a file or key-authentication UI.

Encrypted-key/passphrase decoding, RSA, key-library deletion/reuse/export, actual
file-choice-to-connection device acceptance, host-sheet visuals and the full
Screens parity goal remain open. No commit, push, tag, release or physical-device
use. New importer selection/cancel gates are dispatched separately; re-poll the
exact recorded handles before retrying.

Current native importer handles: phone 71388, iPad 45387; artifacts
build/iphone-private-key-import-picker-20261008 and
build/ipad-private-key-import-picker-20261008, owned UDIDs
B2A70B86-CF9F-4B79-B813-C97E81273130 and A9F8BF45-23CE-4458-9C22-8ED898729570.
Each requests both importer-selection cases only. Builds succeeded; runtime
results remain pending. These scenarios verify choosing key authentication,
disabling Connect until a key is selected, opening/cancelling the native picker,
and returning to password authentication. They do not choose a real file.

Importer first attempts are terminal exit 1, phone 71388/iPad 45387; each failed
both cases at the immediate post-Cancel hittability check. Exported iPad picker
attachment 164E4EDE-6C65-42A9-B5E1-7631E7420EF7.png still showed Quick Connect
before the document picker covered it; the test therefore clicked the underlying
Cancel while presentation was pending. Failure screenshots/hierarchies and the
scoped phone diagnostic-collector cleanup are retained. These are not accepted
importer evidence. Helpers now wait for the draft to become covered before
locating a foreground Cancel and wait for draft hittability to return afterward.

Replacement handles: phone 20954, iPad 96594; artifacts
build/iphone-private-key-import-wait-20261008 and
build/ipad-private-key-import-wait-20261008. Both requested the two English/Chinese
importer-selection cases. Re-poll these exact live handles before retrying; no
complete native importer or full parity acceptance is claimed.

OpenSSH format references: https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.key
and https://github.com/openssh/openssh-portable/blob/master/sshkey.c (padding loop).

### Saved SSH key identity and native-picker audit (2026-10-08)

The edit sheet now retrieves the saved key's public fingerprint through the
injected vault and restores only that fingerprint/reference into the form.
It does not stage private bytes as a replacement or rewrite a shared key on Save.
Missing/denied key reads report a localized error rather than a false saved-key
identity. SSHSettingsTests covers missing keys, strict read denial, matching
fingerprint, unchanged UUID/settings and absence of private material in the draft.
Native importer cancellation errors are ignored, preserving the current selection.

Accepted /tmp/aetherscreens-private-key-editor-tests.log: 27 settings/key/transport
tests, zero failures, 5.212 seconds, handle 5437 exit 0, real Keychain QA enabled.
After cancellation handling, /tmp/aetherscreens-private-key-editor-localization-tests.log
passed all 13 settings/localization tests, 0.184 seconds, handle 71743 exit 0.
Generic iOS build /tmp/aetherscreens-private-key-editor-ios-build.log passed with
handle 29303 exit 0; latest cancellation-inclusive build /tmp/aetherscreens-private-key-editor-ios-build-final.log
passed with handle 58654 exit 0.

Picker-wait runs 20954/96594 are terminal exit 1: both cases on each device timed
out locating a foreground Cancel after correctly waiting for the draft to be
covered. Scoped iPad diagnostic collector cleanup is retained. The owned simulator
document-service log /tmp/aetherscreens-owned-picker-provider.log records a
running separate DocumentManager service; its actual installed CFBundleIdentifier
was read from the runtime plist as com.apple.DocumentManagerUICore.Service.
Test helpers now query that extension alongside the host app and capture the
whole XCUIScreen rather than only the host application's screenshot.

Replacement service-query runs are live: phone handle 27326, iPad handle 33008;
artifacts build/iphone-private-key-import-service-20261008 and
build/ipad-private-key-import-service-20261008. Both builds succeeded; each
requests the two English/Chinese importer-selection/cancel cases. Re-poll exact
handles before retrying. These test builds predate the small Cocoa cancellation
guard; latest generic build and settings/localization tests cover that source.
No native import/cancel acceptance claim yet. Full parity remains active.

Service-query runs 27326/33008 are now terminal exit 1, each 1/2. English
importer selection, real system picker opening/cancelling, preserved disabled
Connect and returning to password auth passed on both phone/iPad. Chinese flows
also passed picker cancellation/return, then correctly failed because the product
menu still said Password. This was an actual missing localization, now fixed in
both resource catalogs; the test continues to require 密码. LocalizationTests
passed all five tests in 0.016 seconds, handle 29948 exit 0, log
/tmp/aetherscreens-password-localization-tests.log. Scoped iPad diagnostic
collector cleanup is retained; the phone collector had already ended, so no
process was signalled there. English/Chinese phone system-picker screenshots
were inspected and show the native empty Recents browser.

Latest Chinese-only native gates are live: phone handle 9021, iPad handle 7385,
artifacts build/iphone-private-key-import-localized-20261008 and
build/ipad-private-key-import-localized-20261008. Both use the unchanged full
settings/import/cancel/switch flow, including the product localization fix and
Cocoa cancellation guard. These scenarios still do not select an actual key file.
The latest full-core regression is also dispatched separately; record/re-poll its
returned handle before considering the phase accepted. Full parity remains open.

Latest full-core handle 34734 remains pending in
/tmp/aetherscreens-private-key-editor-full-core-final.log; real Keychain QA is
enabled. Re-poll that exact handle alongside native 9021/7385 before retrying.
Both iPad service-run picker screenshots were also visually inspected: actual
native Recents/Search/Locations UI, no application-layout substitution.

### Latest scoped SSH configuration acceptance (2026-10-08)

Latest full core is accepted: /tmp/aetherscreens-private-key-editor-full-core-final.log,
handle 34734 exit 0: 262 tests, seven explicit environment skips, zero failures,
97.781 seconds, real Keychain QA enabled.
Chinese native importer runs are accepted, handles 9021/7385 both exit 0, artifacts
build/iphone-private-key-import-localized-20261008 and
build/ipad-private-key-import-localized-20261008. Each executed its exact one
requested case with zero skips/failures/result-summary runtime warnings. Both
private-key configuration screenshots were exported and visually inspected.
Together with the previous passing English cases, this proves choosing private
key mode, disabled Connect without a key, real native-picker opening/cancelling,
preserved draft and returning to password auth on both owned device sizes/languages.
It does not prove selecting a real key file or real-device SSH compatibility.
All previously recorded handles are now terminal; no tests are still running.
Full key management, encrypted keys/RSA, file transfer, sync, privacy Curtain,
host-sheet visual acceptance and physical-device/performance acceptance remain
open. No commit, push, tag or release. The full parity goal stays active.

### SSH field identity during editing (2026-10-08, native layout gate pending)

SSH server, account and desktop-target fields now keep a visible caption above
the editable value; entered values no longer erase the meaning of each row.
Captions are excluded from VoiceOver separately because the native text fields
already expose the same localized label. Focus, submit handling and accessibility
identifiers stay attached to the native field.
Accepted /tmp/aetherscreens-ssh-field-label-tests.log: 13 settings/localization
tests, zero failures, 0.177 seconds, handle 74011 exit 0.
Generic iOS build /tmp/aetherscreens-ssh-field-label-ios-build.log passed,
handle 63510 exit 0. Phone native settings regression
handle 17501 remains live, build/iphone-ssh-field-labels-20261008, requests exactly
both English/Chinese SSHSettings cases on owned B2A70B86-CF9F-4B79-B813-C97E81273130.
Re-poll exact handles before retrying. New caption layout is not visually accepted
yet; iPad layout also needs verification. No release or full-parity claim.

Paired iPad caption-layout regression is dispatched, handle 53102, artifacts
build/ipad-ssh-field-labels-20261008, same two English/Chinese settings cases on
owned A9F8BF45-23CE-4458-9C22-8ED898729570. Re-poll 17501/53102 before retrying.

Phone caption-layout gate 17501 is accepted, exit 0, both requested languages
executed without skips/failures/result-summary runtime warnings. Both SSH
configuration screenshots were exported and visually inspected; captions stay
visible above entered server/account/target values without horizontal overflow.
iPad 53102 remains live; Chinese case passed, English case still running.
Re-poll the same handle before retrying. Full parity remains active.

### 2026-10-08 SSH captions accepted and saved-key reuse increment

Owned iPad runner 53102 completed with exit 0: both requested Chinese/English
SSH settings cases executed, no skips, failures or runtime warnings. Result:
`build/ipad-ssh-field-labels-20261008/result.xcresult`. Both saved-settings
attachments were visually reviewed: persistent field captions and entered values
are readable with no horizontal clipping. Phone caption gate 17501 was already
accepted. Secure-field pixels are redacted by XCTest.

Add/Edit/Quick Connect now offer a native saved-key menu when saved computers
reference keys. References are deduplicated without reading secrets while listing.
Selection validates Keychain contents and exposes the derived public fingerprint;
no private bytes are staged for rewriting, and target server/account stay intact.
Read denial or missing keys preserve the previous selection. This does not yet
provide a standalone key library, orphan deletion, export or encrypted-key support.

Targeted SSH settings/localization run 99906 completed with exit 0: 14 tests,
zero failures. Regression covers deduplication, denied/missing reads, imported-key
replacement, unchanged target account and no additional vault writes. Initial
compile failure used an incorrect test-only DeviceStore method; corrected to the
existing addDevice API. Logs retained in `/tmp/aetherscreens-key-reuse-tests.log`
and `/tmp/aetherscreens-key-reuse-tests-fixed.log`. Whitespace check passed.
Generic iOS build 35703 is still pending; saved-key menu native UI acceptance
remains open. Broad Screens parity and physical-device acceptance remain active.

Generic iOS saved-key-reuse build 35703 completed with exit 0 and
`BUILD SUCCEEDED` (`/tmp/aetherscreens-key-reuse-ios-build.log`).
Current candidate full regression started: core handle 18371 with isolated real
Keychain QA enabled; controlled native 29-case phone handle 38633 and iPad handle
70949, each on its previously owned simulator and dedicated live fixture.
Artifacts: `build/iphone-key-reuse-full-gestures-20261008` and
`build/ipad-key-reuse-full-gestures-20261008`. These are pending results, not
acceptance, and do not cover actual saved-key-menu selection or physical devices.

### Saved-key commit-time validation and full core result

Full core handle 18371 completed with exit 0: 263 tests, 7 explicit environment
skips, zero failures, 94.855 seconds. Real isolated SSH Keychain QA was enabled.
Log: `/tmp/aetherscreens-key-reuse-full-core.log`. This binary predates the
following narrow save-validation change.

Saving a new/replaced reference without imported bytes now revalidates its
Keychain identity before any configuration mutation. This closes the gap between
menu selection and save if a reused key has disappeared. Renaming an existing
computer with the same reference retains prior behavior. Targeted handle 67012
completed with exit 0 after the change; its regression proves saved-key reuse does
not rewrite the secret and a missing reused identity leaves the device count
unchanged. Log: `/tmp/aetherscreens-key-reuse-save-validation.log`.

Incremental generic iOS build 91100 is pending. Controlled UI runs 38633 and
70949 remain live with the pre-save-validation binary; no restart or acceptance
claim. Neither run exercises the new saved-key menu.

Incremental iOS build 91100 completed with exit 0 and BUILD SUCCEEDED.
Latest 14 targeted tests completed with zero failures in 0.179 seconds.

### Loading transition accessibility consistency

RemoteDesktopView loading notice now uses opacity alone when Reduce Motion is
enabled, matching the toolbar and button feedback policy; its ordinary transition
retains the existing opacity/0.95 scale. No transport or frame rendering changes.
Whitespace check passed; generic iOS build handle 34465 is pending.
The two full native regression handles remain live: current logs prove Chinese
Carousel passed on both devices and Chinese connection recovery passed on iPad.
No full-suite or current-loading-motion acceptance is claimed.

Loading reduced-motion generic iOS build 34465 completed with exit 0 and BUILD SUCCEEDED. Native full-suite handles 38633/70949 remain live; Chinese recovery now passed on both simulators, and Chinese display-quality passed on iPad.

### Owned simulator motion evidence

Recorder handle 56817 completed with exit 0. `motion-sample.mov` in the phone
full-gesture artifact directory is verified by ffprobe: duration 29.813333 seconds,
1170x2532, 694 recorded frames, 10,158,368 bytes. The recording overlapped the
first-frame timeout/recovery scenario, not a complete toolbar/zoom motion audit.
A timestamp-15s preview was extracted for inspection. Variable-rate screen
recording metadata is not an app FPS or physical input-to-display latency metric.
UI suite handles 38633/70949 remain pending; no recording-based pass claim.

### Current native regression failure retained

Owned iPad full-suite log reports Chinese floating-toolbar failure at the
collapsed horizontal-drag assertion: actual midX 647.75 vs required >763.84375.
Phone case passed. The test read the button frame immediately after the collapse
label changed, while the spring moves the expanded right-side button to center.
The test now waits for its hittable frame to remain stable for at least 0.35s
before recording drag origin and after the drag. Original >40 horizontal and
>20 vertical movement assertions remain intact. This is a synchronization
hypothesis, not a product-fix or acceptance claim; targeted native rerun must
follow the still-live full suites without interrupting them.

### Expanded floating toolbar horizontal movement

Current product implementation discarded horizontal drag while expanded, despite
the iPad floating layout having available space in landscape. Both expanded and
collapsed modes now retain horizontal translation and clamp the final position
using the current toolbar width. Pointer events remain local to the drag handle;
no gesture-to-remote changes. The existing native floating case now additionally
requires expanded horizontal displacement >30 points for its 60-point drag.
The current full-suite binaries predate this change. Targeted native verification
and the stable-collapse-origin correction remain pending until owned devices are
free. The previous test-only build logged TEST BUILD SUCCEEDED; its parent
handle is polled separately before treating it as terminal.

Expanded two-axis floating-toolbar build-for-testing handle 19416 completed with
exit 0 and TEST BUILD SUCCEEDED. Log:
`/tmp/aetherscreens-floating-two-axis-build.log`. No test execution was performed
by this compile gate. The existing full native suites continue on their original
binaries: phone currently 9 passes/0 failures, iPad 8 passes/1 retained Chinese
floating failure, both in toolbar-interaction cases. Follow-up native floating
English/Chinese verification is still required; no passing count inferred from
compilation or source changes.

### Full iPad regression terminal result and targeted follow-up

Owned iPad runner 70949 exited 1 after all 29 requested tests executed:
28 passed, one retained Chinese floating-toolbar horizontal displacement failure,
1669.575 seconds. Its parent terminated naturally; no collector was signaled.
Both-language edge follow and both native gesture cases passed. Original result
remains `build/ipad-key-reuse-full-gestures-20261008/result.xcresult`. This failed
full run is not acceptance of the latest floating implementation.

After confirming the iPad was no longer running its xcodebuild, started the
English/Chinese two-case follow-up with current two-axis floating product code
and stable-frame drag origin at `build/ipad-floating-two-axis-20261008`. Phone
full-suite handle 38633 remains live, in English zoomed edge-follow.

### Full phone regression accepted

Owned phone runner 38633 completed with exit 0: all 29 requested cases executed,
no skips, failures or result-summary runtime warnings. Result:
`build/iphone-key-reuse-full-gestures-20261008/result.xcresult`. This run used the
pre-two-axis/pre-stable-frame binary; do not use it as acceptance of those iPad
changes or saved-key-menu selection. Phone both-language edge follow, full-screen
gestures, rotation, toolbar/repeat/recovery and native gesture cases passed.

Owned iPad failed-run attachments export handle 68228 completed with exit 0.
Failure screenshot and hierarchy were inspected: the collapsed control is in
its final moved location; the original horizontal threshold came from the moving
collapse layout. Stable-origin synchronization remains a hypothesis until the
current English/Chinese follow-up 4299 (confirmed live, Chinese case started)
completes. No extra simulator was created and no other project was interrupted.

### Two-axis floating native acceptance

Owned iPad targeted runner 4299 completed with exit 0: both requested English/
Chinese cases executed, no skips/failures/runtime warnings. Chinese 72.363s,
English 71.322s. Existing pointer-isolation, >40 vertical expanded movement,
>40 horizontal and >20 vertical collapsed movement assertions were preserved;
new expanded horizontal >30 assertion also passed.
Result: `build/ipad-floating-two-axis-20261008/result.xcresult`. Exported current
expanded Chinese and collapsed English screenshots were visually inspected: the
floating surface stays within the viewport and the handle/control remain visible.
The original failed 29-case iPad run is retained. Started a fresh complete
29-case run of the current candidate at `build/ipad-floating-current-full-20261008`
(handle 18148), pending. Neither targeted acceptance nor prior phone acceptance
proves physical-device smoothness, full Screens parity or saved-key-menu use.

### Native saved-key reuse gate implementation

Added explicit English/Chinese SSHKeyReuse cases. The runner creates generated
app source only inside the disposable simulator project and appends a QA-only
fixture from `scripts/qa/ssh_key_ui_fixture.swift`; the production app/project
are unchanged. UUID-scoped P256 keys are generated in the isolated QA Keychain,
a UUID-named source computer is seeded, and cleanup removes only this generated
identity/source and clears this reference from affected QA computers.

The native cases choose the saved key in Quick Connect, verify Connect enables,
then choose/save/relaunch the editor and require the public fingerprint to survive.
No network SSH compatibility claim comes from this menu/settings test.
Phone runner 55772 started at `build/iphone-saved-key-reuse-20261008`, pending.
Runner help and whitespace checks passed; native test compilation/execution
is not accepted yet. macOS app build 5119 completed with exit 0 in 4.52s.
Owned iPad full current suite 18148 remains active.

### Saved-key UI failure diagnosis and cleanup repair

Initial phone reuse runner 55772 exited 1: Chinese menu option not found; English
card placement failed. Its Selected suite was terminal but owned diagnostic PID
44595 remained collecting; validated exact parent/result/UDID and stopped only
that collector, retaining `diagnose-cleanup.json`. Attachment export completed.
Failure video preview shows no menu presentation; modern AX treats the Menu as
a popup. Selection now targets its actual coordinate and waits for a stable
UUID-tagged option. Card scrolling drags inside the list instead of global swipes.

XCTest abort bypassed Swift defer and left two generated source computers. Both
known QA identities were cleaned using the installed generated app, without
editing the simulator Keychain database. Immediate plist verification raced
preference flushing and failed; a subsequent authoritative plist read confirmed
both sources absent. New fixture journals generated UUIDs in its own Caches file.
Runner post-test cleanup launches the generated app only after xcodebuild is
terminal, checks journal completion, and records a cleanup receipt. App cleanup
strictly removes/reads the generated private key before removing its journal entry.

Fixed phone runner 1700 is live at `build/iphone-saved-key-reuse-fixed-20261008`;
results remain pending. Runner help and whitespace checks passed. iPad full
current handle 18148 remains live. No successful key-reuse UI claim yet.

### Saved-key native selector implementation change

Fixed phone runner 1700 terminated with exit 1: the menu still did not expose
its option even through an actual coordinate and explicit wait. English card
geometry additionally rejected minY108 against a fixed120 threshold. Its
post-test cleanup receipt verifies zero remaining generated identities; no
collector intervention was required.

Replaced the non-presenting Form Menu with a native confirmationDialog opened
by a normal Button, retaining public identities, strict vault selection and error
behavior. Native case selects its actual source label in the dialog. Card safe
top now derives from the rendered header control instead of a fixed120; the
whole-card visibility check is retained. Started phone dialog runner at
`build/iphone-saved-key-dialog-20261008`, pending; no selector pass claim.

### Native key dialog presentation confirmed; option query repair

Phone dialog-run Chinese case reached a real native Popover/Sheet titled
使用已保存的私钥. It failed at selection because UIKit exposes nested Buttons
with the same source label and option UUID identifier; the unqualified query
required a single element. Current test resolves the UUID option via firstMatch.
This proves presentation, not successful selection/persistence. Original
failure hierarchy is retained in the run log. English case and runner 47559
are still live; do not restart while they own the phone.

Dialog macOS build 51269 completed with exit 0 in 11.18s. Current iPad
full-suite handle18148 remains live with no reported test failures so far.

Phone dialog runner47559 completed with exit1: both languages showed the native
dialog but failed on duplicated nested option buttons. Cleanup receipt confirms
2 generated identities processed and remaining[]. No collector signal required.
Started fresh phone run `build/iphone-saved-key-dialog-option-20261008` with
UUID firstMatch selection. This runner is pending; old failed results retained.
Current iPad full suite has passed English toolbar interaction, repeat and
rotation, and remains live without test failures so far.

### Official Screens baseline reverified 2026-10-08

Current official product page https://www.edovia.com/en/screens/ lists file
transfer, iCloud, adaptive quality, SSH keys, shortcuts toolbar, disconnect
actions and Vision Pro. File transfer is an actual parity gap, not an assumed
SFTP feature: https://blog.edovia.com/en/screens-56 (2025-06-04) specifies drag
and drop between the local Apple device and a remote Mac. Transport must be
verified before selecting SFTP as the implementation.

Official SSH guide https://help.edovia.com/en-GB/screens-5/features/ssh-keys
confirms a separate settings Keys area, file and clipboard import, selection
per connection and Keychain storage. Current per-computer file import plus
shared-reference selection does not close standalone key-library or clipboard
import gaps. The guide's future-5.5.3 Nearby note appears older than the 5.6
release and is not current evidence of a Nearby limitation.

Official 5.6 announcement also explicitly describes Unicode/legacy/keystroke
input modes, adjustable tracking speed, Pencil direct touch and reconnect.
Retain complete parity scope and actual-device smoothness acceptance; do not
relabel merely compiled callbacks or generic SSH/SFTP as these verified UXs.

### Clipboard private-key import increment

SSH fields now expose a system PasteButton for String payloads, with localized
Paste Private Key row. Only explicit system paste delivers text to the handler.
It checks UTF8 length before allocating Data, then uses the same bounded
SSHPrivateKey decoder as file import. Invalid/oversized paste preserves the
previous selected identity and shows the existing localized error; no secret
logging or automatic clipboard reads. macOS app build19958 exited0 in4.72s;
generic iOS build65929 pending. Native paste-specific acceptance remains open.

Current iPad full runner18148 exited0. Inspect final verifier/count before
claiming complete acceptance; this binary predates new clipboard selector row.
Phone key-dialog option runner85438 remains live.

### Current iPad full regression accepted

Owned runner18148 completed exit0: all29 requested cases executed with zero
skips/failures/runtime warnings; selected suite 1750.923s. Result:
`build/ipad-floating-current-full-20261008/result.xcresult`. Both-language
floating, edge follow and native gesture cases now passed in this full run.
It predates the key confirmationDialog and paste row; these SSH UI increments
need independent acceptance and do not invalidate its transport/toolbar scope.

Started owned iPad English/Chinese saved-key dialog selection gate at
`build/ipad-saved-key-dialog-option-20261008`. Phone85438 remains live;
iOS paste build65929 remains pending. No physical acceptance or full parity claim.

### Keychain identity-index foundation

SSHCredentialStore now enumerates UUID references for a requested credential
kind using only attributes from its exact service, nonsynchronizable generic
items. It does not request private bytes for indexing. Not-found is empty; denied
access, malformed private-key UUIDs or malformed successful responses remain
errors. Results are deduplicated and deterministic. Existing test adapters
without enumeration explicitly return unimplemented, never pretend to be empty.

Targeted real-Keychain-enabled credential/settings handle3867 completed exit0:
14 tests, zero failures in0.528s. Actual isolated system vault was checked before
save, after save/update and after delete; fake regression covers kind filtering,
no value-data query, denial and corrupt identities. Log:
`/tmp/aetherscreens-key-index-tests.log`. Standalone key-library UI remains open.

Phone saved-key dialog option run Chinese case passed235.177s, including saved
identity reloaded fingerprint. English and its parent85438 remain pending; iPad
18395 remains live. Paste localization handle40562 previously exited0:5 tests,
0fail in0.024s; generic paste iOS build65929 exited0 and BUILD SUCCEEDED.

### Key library model operations and native saved-key status

Added standalone key enumeration/import/remove model APIs. Listing preserves
malformed entries with a localized problem while denied Keychain access remains
an error; import creates a validated new vault reference without device/defaults
mutation. Removal refuses any saved computer or open SessionRegistry reference
and propagates vault deletion denial. The standalone settings UI is still open.
Targeted handle34904 exited0:16 tests,1 explicit real-Keychain opt-in skip,
0fail in0.260s. Previous identity-index run had enabled and passed real vault QA.

Phone runner85438 exited0, all2 language cases executed/no skips/failures/runtime
warnings. Chinese235.177s and English231.735s, including temporary selection,
save/relaunch and fingerprint recovery. Its cleanup receipt confirms no remaining
generated identities. Result: `build/iphone-saved-key-dialog-option-20261008`.

Current iPad18395 remains live. Chinese failed only at final SSH-switch reveal
after the fingerprint recovery screenshot; lazy Form removed the upper row from
AX and the generic lookup scrolled farther down. Added two content-only upward
returns before this final reveal, preserving assertions and setting cleanup.
English and parent remain active; wait for terminal before rerunning.


### 2026-10-08 — Native standalone SSH key library (in progress)

Settings now has a native SSH Keys destination with bounded file import,
explicit system PasteButton, public fingerprints, computer usage, retry/error,
and confirmation before deleting unused keys. The model refuses deletion when
any saved computer or registered session references a key. No secret is placed
in preferences, labels or logs. Library imports become selectable without
creating a synthetic computer; private-key fields refresh choices on entry to
key authentication and selection revalidates the vault.

macOS builds passed for the native library view and completed choice integration.
The real isolated Keychain/model regression passed 16 tests, zero skipped or
failed, including choosing an unreferenced library key without staging secret
bytes. iOS simulator build is still running. Native library/paste interaction
and visual acceptance remain pending; these changes do not establish full
Screens parity or physical-device smoothness.

Previous iPad key reuse run `ipad-saved-key-dialog-option-20261008` ended with
two UI scroll lookup failures. Its fixture cleanup verified zero remaining
owned identities. The generic form reveal now searches both directions when a
lazy accessibility row is absent, retaining visibility checks. Replacement
`ipad-saved-key-dialog-scroll-20261008` is still running. Phone bilingual key
reuse previously passed. No production device, commit, push or release used.


The completed iOS generic simulator build ended with BUILD SUCCEEDED (both
simulator architectures, isolated derived data). English/Chinese strings pass
plutil syntax validation; git diff --check passes. All four prior successful
phone key reuse screenshots were visually inspected (temporary/reloaded,
English/Chinese); fingerprint wrapping and native sheet controls are readable.
Those screenshots predate the PasteButton/library UI and cannot accept it.

A separate pair of native library tests is now running on the owned phone:
`iphone-key-library-native-20261008`. Its disposable app seeds only a generated
unreferenced key, checks navigation/fingerprint/import/paste visibility and
actual confirmed deletion/empty state, then verifies scoped vault cleanup.
This does not test clipboard content delivery or a selected file import yet.
The test runner's isolated fixture mechanism now explicitly supports these
library cases; no production startup hook or signing configuration changed.


Latest full core gate: `/tmp/aetherscreens-key-library-full-core.log`, terminal
exit 0, 266 tests, seven explicit live-environment skips, zero failures,
118.814 seconds. The isolated real Keychain tests ran rather than skipped.
Skipped LAN/real-Mac clipboard/authentication/input gates remain unaccepted.
Synthetic benchmark output is not an iPhone UI or remote-Mac latency result.


Phone native library gate ended terminal exit 0: Chinese 29.310s, English
27.039s, no skips/failures/runtime warnings. Both confirmed deletion and empty
state passed; all four library/empty screenshots were exported and visually
inspected. The native system paste button follows the simulator OS language;
its surrounding labels correctly follow the selected app language. Fixture
cleanup receipt has generatedIdentityCount 0 and remaining [], because the
successful Swift defer removed both identities before the fallback audit.
Actual paste content delivery and file selection remain pending.

Replacement iPad bilingual reuse ended terminal exit 0, both requested cases
executed, no skips/failures/runtime warnings; cleanup also remaining []. The
bidirectional Form search fixes the observed lazy-row scroll lookup failure.
New iPad native library run `ipad-key-library-native-20261008` is now active
only after that prior runner and its cleanup completed.


### Native key library phase verification completed

The iPad native library runner ended exit 0, both requested tests executed with
no skips/failures/runtime warnings, and its fixture cleanup has remaining [].
All four iPad library/empty-state screenshots were inspected: the centered
native sheet has readable controls and fingerprints in both app languages.
Phone and iPad therefore accept navigation, key display, explicit deletion and
empty state. This remains distinct from actual paste data/file delivery.

The new model default-argument reference to main-actor SessionRegistry.shared
produced a Swift 6 isolation warning. It now resolves the optional injected
registry inside the main-actor method instead. The affected real-vault/model
16-test gate passed again (0 skips/failures), and iOS rebuild passed. The broad
266-test gate precedes this semantically equivalent default-argument fix.

Screenshot review also found the dashboard count displayed `1 computers`.
The English single-device count now uses `%d computer`, with a matching Chinese
catalog entry; localization regression and final simulator rebuild are running.
No commit/push/release or physical-device acceptance performed. The full parity
matrix remains open, including file transfer, sync, genuine curtain mode,
encrypted/RSA keys, adaptive quality, peripheral support and measured motion.


Final polish checks ended terminal exit 0: localization 5/5 passed, iOS generic
simulator build BUILD SUCCEEDED, git diff --check clean. No owned QA runner is
left active from this phase. Overall goal remains active; no all-feature or
physical smoothness completion is claimed.


### 2026-10-08 — SSH key names and persistent identification

Managed keys can now be renamed from a native alert. Labels are stored as a
UUID-to-string preference dictionary, separate from secret Keychain bytes;
trimmed empty input restores the default label and input is bounded to 120
characters. Named keys use their label in the connection selector, including
keys referenced by a saved computer. Deleting a key removes its label only
after successful vault deletion. Rename performs all fallible vault reads
before writing metadata; denied/missing keys cannot acquire a new label.

Model/localization regression passed 22 tests with the isolated real Keychain
enabled. A first new test mistakenly reset an optional mock read override to
success-with-nil, which correctly failed strict vault decoding. Resetting that
mock to its actual-data path corrected the test; production fail-closed checks
were retained. The follow-up read-before-metadata refinement is under test.

Native bilingual phone/iPad library cases now include rename, app relaunch,
restored label/fingerprint, deletion and empty state. Both owned runners are
active with independent derived data. No physical device, real account,
production signing, commit, push or release was used. Overall parity remains
open with the full capability matrix above.


Rename refinement gate passed 22 tests, 0 skips/failures; the simulator build
also passed. The first native phone/iPad naming runs ended with two failures
per device. Exported failure screenshot contradicts the initial input-locator
hypothesis: tapping Rename displayed Delete Private Key. Multiple automatic
buttons inside a Form row invoked overlapping actions. The key row now applies
borderless button style so rename/delete actions remain distinct. The tests
require the exact rename alert and one input before typing; they still require
relaunch persistence and confirmed deletion.

Both failed suites had finished before their hanging owned simctl diagnose
collectors were stopped. PID/parent/device/result guards were checked and
recorded in each diagnose-cleanup.json; the xcodebuild test processes were not
signalled. Both runner handles ended exit 1, then scoped generated-key cleanup
verified generatedIdentityCount 2 and remaining []. The read-only simulator
screenshot after test termination showed SpringBoard and provides no alert
evidence; the actual exported failure screenshot is the diagnosis source.
Fresh runs `iphone-key-names-actions-20261008` and
`ipad-key-names-actions-20261008` are now live after cleanup. Native naming is
not accepted until these complete and exported screenshots are inspected.


### Key naming native gates accepted

Both replacement runners ended terminal exit 0 with all two requested cases
executed and no skips/failures/runtime warnings. Phone Chinese/English:
50.577s/48.418s; iPad Chinese/English: 52.862s/49.233s. These gates actually tap
Rename, require the correct one-field native alert, save the label, relaunch the
app without reseeding, verify restored label/fingerprint, confirm deletion and
verify empty state. Generated key cleanup remaining [] on both devices.
All four named-key screenshots were exported and visually inspected: labels
appear above the fingerprint and Rename/Delete remain separate. The English
iPad screenshot also confirms the dashboard now displays `1 computer`.
The read-before-metadata model/localization regression passed 22 tests, zero
skips/failures; macOS build passed in 5.51s and simulator builds passed.
No owned test runner remains live from this naming phase.

### File transfer baseline rechecked before transport changes

Primary product reference rechecked:
https://help.edovia.com/en/screens-5/features/file-transfers-iphone
It specifies dropping local files on the remote desktop for upload and dragging
remote files into a cursor-side download target; downloads go to Files Downloads.
Uploads cover macOS 10.10+, downloads require macOS 14+. Its notes treat SSH as
optional session encryption, not a mandatory SFTP account. A separate SFTP file
browser alone therefore cannot prove the requested Screens-equivalent behavior.

The current client implements standard RFB clipboard/SSH directTCP forwarding,
not Apple file-transfer negotiation or remote drag metadata. SwiftNIO SSH's
primary README documents subsystem channels but does not prove Apple's file
transfer protocol: https://github.com/apple/swift-nio-ssh . No SFTP substitute
or vendor opcodes were enabled in production.

A possible investigation pointer is the author's experimental reverse-engineered
specification https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md .
It explicitly disclaims Apple/IETF endorsement and describes a 003.889 encrypted
record layer with vendor pasteboard/control messages. This is a research lead,
not a verified file-transfer specification or evidence our existing 003.008
sessions can consume those messages. Native capture/protocol validation must
precede advertising capability. Full goal remains active; physical acceptance,
file transfer, iCloud, curtain mode and other matrix gaps remain open.


### 2026-10-08 — Actual system private-key paste acceptance (running)

Added four explicit bilingual native cases per owned simulator: valid key paste
and invalid paste while retaining an already selected saved key. Valid paste
starts with Connect disabled and requires a decoded SHA256 fingerprint and
Connect enabled. Invalid paste requires the translated parser error, unchanged
fingerprint and Connect still enabled. Drafts are cancelled, so imported private
bytes are not written to a computer/defaults or a second vault identity.

Only the disposable QA app creates a P256 key and puts it in that simulator's
clipboard, with localOnly true and a five-minute expiration. Invalid text has an
owned UUID marker. Its cleanup clears clipboard content only on exact match to
the generated seed/marker, then removes the existing journalled vault identity
and owned source computer. No real private key is passed into the test runner,
printed, persisted in source or shared by Universal Clipboard.

Current live runners: `iphone-key-paste-native-20261008` and
`ipad-key-paste-native-20261008`. Production PasteButton/draft decoding code is
unchanged; these tests establish actual content delivery, rather than treating
button visibility as acceptance. Native library-paste persistence and actual
file selection are still separate pending gates.


First actual-paste phone/iPad runners ended exit 1: all four cases failed on
each device, cleanup receipts remaining []. The phone runner completed naturally
before an attempted collector cleanup found anything to signal; no collector
was stopped for this run. iPad also ended naturally. A read-only mid-run iPad
screenshot caught app launch (blank window) and does not diagnose paste.

The exported phone valid-paste failure screenshot and hierarchy identify the
issue: `ssh-paste-key` was exposed as a Button spanning the entire LabeledContent
row (x32,y702,width326,height34.3), while the visible blue paste control sits at
the trailing edge. The test tapped the row center, not the actual paste control.
Apple's primary PasteButton documentation confirms String Transferable delivery
and automatic iOS validation:
https://developer.apple.com/documentation/swiftui/pastebutton
https://developer.apple.com/documentation/swiftui/pastebutton/init(payloadtype:onpaste:)
Its UIPasteboard representation reference includes UTF8PlainText:
https://developer.apple.com/documentation/uikit/pasteboard-data-type-representations
The fixture's UTF-8 item type is therefore not being replaced speculatively.

Both production paste rows now use contained accessibility children and an
intrinsic fixed-size PasteButton, preserving explicit system paste access.
macOS build passed. A targeted actual valid-paste phone case is running in
`iphone-key-paste-contain-20261008`; full bilingual valid/invalid gates remain
pending. No parser or credential failure check was weakened.


Containment alone did not solve LabeledContent's merged activation frame: the
targeted phone run ended exit 1 and its exported hierarchy still reports a
326-point wide paste button. Cleanup remaining []. Replacing LabeledContent
with an explicit HStack (title, spacer, fixed-size native PasteButton) exposes
the actual control separately, with a localized action accessibility label.
Both connection/library rows use this structure. The targeted actual valid-paste
phone case `iphone-key-paste-hstack-20261008` ended exit 0, no skips/failures/
runtime warnings; its screenshot shows the SHA256 fingerprint and enabled
Connect after native content delivery. Cleanup remaining [], macOS build passed.

Full bilingual valid/invalid runs are now live in
`iphone-key-paste-current-20261008` and `ipad-key-paste-current-20261008`.
Their imports remain temporary drafts. Library persistent paste and actual file
selection still require their own verification. No completion/physical smoothness
claim or release action is made.


Current phone full paste gate ended terminal exit 0: all four bilingual valid/
invalid cases passed without skips/failures/runtime warnings. iPad current gate
ended exit 1 with three passes and one Chinese invalid-paste failure (expected
error absent). Exported failure screenshot/hierarchy confirms a correctly sized
78.5-point paste control, selected fingerprint and enabled Connect, but no error.
Its failed temporary draft was cancelled by the runner's owned cleanup; remaining
[] (one owned seed). Phone cleanup also completed. No collectors were signalled
for either current run.

Both runners had written/cleared clipboard data in parallel. Apple's Simulator
help documents host-device clipboard synchronization, independently of the
UIKit localOnly Universal Clipboard option:
https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/simulator_help_topics/Chapter/Chapter.html
Cross-run interference is an inference to investigate, not a confirmed product
or simulator bug; compared public fingerprints do not establish that one test
consumed the other test's key. The unchanged four-case iPad gate is now rerunning
alone in `ipad-key-paste-serial-20261008`, after both prior runners and cleanup
were terminal. No user host/device clipboard setting was modified. Production
macOS build and original-app generic simulator build passed with the final
HStack layout. Full acceptance remains pending the serial iPad outcome.


The unchanged serial iPad runner ended terminal exit 1: Chinese invalid paste
failed again, both valid cases and English invalid paste passed. This contradicts
parallel clipboard interference as the sole explanation. Owned cleanup remaining
[]; no test or diagnostic process was signalled. Further source audit found
Picker.onAppear calls refreshKeys(), whose success cleared keyError. Form lazy
row reappearance during scrolling can therefore erase an import error.

Key-list refresh failures now use a separate savedKeysError with explicit Retry.
A successful list refresh preserves import/selection errors; the initial list
read is guarded to avoid repeated Keychain work on every scroll. Explicit mode
changes and Retry still refresh, and key selection continues strict vault checks.
macOS build passed; original-app iOS build and targeted unchanged Chinese invalid
paste gate (`ipad-key-paste-error-state-20261008`) are running.

The QA runner also has a nonblocking cross-worktree clipboard lock for Paste/
Clipboard cases, held through owned fixture cleanup. A cross-process kernel-lock
probe confirms contention is rejected, release permits the next run, and other
cases are unchanged. This prevents our own future concurrent clipboard runners
without altering host pasteboard preferences. It does not prove the prior failure
was caused by synchronization and does not serialize unrelated third-party apps.


Targeted unchanged Chinese invalid-paste gate with separate error state ended
terminal exit 0, no skips/failures/runtime warnings, and cleanup remaining [].
The actual error plus preserved fingerprint/Connect assertions now pass. This
provides native evidence for the error-state fix; the earlier synchronization
hypothesis did not resolve the serial failure. Original-app iOS build passed.
Final four-case iPad then four-case phone runs are queued sequentially in one
owned orchestration process; each runner must finish and release its clipboard
lock/cleanup before the next starts. Output folders are
`ipad-key-paste-final-20261008` and `iphone-key-paste-final-20261008`.


Final native draft-paste gate completed sequentially, terminal exit 0. iPad: four bilingual valid/invalid cases, zero failures in 204.453 seconds (ipad-key-paste-final-20261008). iPhone: four cases, zero failures, durations 54.998 / 35.211 / 53.912 / 35.290 seconds (iphone-key-paste-final-20261008). Both cleanup receipts remaining [], generatedIdentityCount 0: deferred cleanup already removed owned seed identities. All eight screenshots exported and visually reviewed: native controls, fingerprints, enabled Connect; invalid input retains selection and displays localized error. No diagnostic collector signalled. git diff --check passed. This accepts temporary Quick Connect draft paste only. Persistent library paste, actual file import, server/device authentication and physical smoothness remain open with broader Screens gaps. Full goal remains active; no commit/push/release.

Standalone library native paste acceptance (2026-10-08):
- iphone-key-library-paste-20261008: two bilingual cases, zero failures, 98.581s.
- ipad-key-library-paste-20261008: two bilingual cases, zero failures, 100.892s.
Both runners terminal exit 0, cleanup remaining []. Eight screenshots exported
and visually reviewed. Each case taps the real system PasteButton, discovers
the new UUID via its native delete action, names that identity, relaunches,
checks label restoration, deletes it and verifies the original seed remains.
Existing core real-Keychain checks support model persistence/deletion; these
UI cases do not authenticate the imported key against a remote SSH server.
Fixture-only seed-library-paste uses generated bytes; cleanup matches those
bytes only in the disposable QA group to recover an interrupted imported copy.
No product startup hooks or user keys are changed. Screenshot attachment name
'Empty SSH Key Library' is inherited from the no-paste case: for paste cases
it represents the remaining original key, not an empty vault.
Python compile and diff check passed. No physical testing, commit or release.
Full Screens alignment remains active with the matrix gaps above.

Key-library state transition polish (2026-10-08):
DeviceListView SSHKeyLibraryView now preserves its last successfully read list
on vault refresh failure instead of publishing an empty list. Retry/error stays
visible. Vault reads finish before list/error UI publication; subsequent updates
use a scoped 0.18s ease-out animation. First load and Reduce Motion bypass it.
macOS swift build passed (4.03s). Native bilingual paste/name/relaunch/delete
regression passed on iPhone (2 cases, 100.447s) and iPad (2 cases, 101.009s),
both terminal exit 0, cleanup remaining []. iPhone exported screenshots reviewed;
the named row may be outside a given viewport based on UUID ordering, so the
English image alone does not prove visible name restoration. XCTest's exact-name
assertion covers restoration. Static screenshots and functional tests do not
prove frame pacing or physical smoothness. Refresh-failure visual injection and
Reduce Motion runtime visual acceptance remain pending. Existing unrelated iOS
deprecation/unreachable-code warnings remain; no new library compiler error.
No commit/push/release; full alignment goal remains active.

Native library file-selection acceptance (2026-10-08):
Fixture-only seed-library-file writes a runtime-generated P256 PEM to its owned
Documents filename. Disposable QA Info.plist exposes that container to Files;
production Info.plist/source configuration remains unchanged. Cleanup removes
the exact owned file and generated/imported keys by owned generated content.
No key bytes are emitted in process arguments/logs. Actual selection uses the
system picker and real importer, then independent UUID/name/relaunch/delete checks.
Initial phone case failed because it assumed the picker started at location
selection; observed hierarchy showed My iPhone already open. One owned simctl
diagnostic collector (PID86836/parent86759) was stopped only after Selected tests
failed; guard receipt retained. Runner terminal exit1, owned cleanup remaining [].
Corrected phone bilingual gate iphone-key-library-file-container-20261008 passed
2/2 in 125.505s, runner exit0, cleanup remaining [].
Initial iPad gate failed 2/2 because sidebar layout has no Browse tab; terminal
exit1, remaining [] (two owned seeds), no collector signalled. Actual failure
screenshot/hierarchy shows My iPad sidebar item. Corrected current sidebar-aware
gate ipad-key-library-file-sidebar-20261008 passed 2/2 in 129.681s, exit0, remaining
[]. Phone passed before final optional Browse-button adjustment; compact branch
is unchanged semantically, but was not rerun after that QA-only adjustment.
Both bilingual named-library result screenshots visually inspected on each device.
This accepts library file import, not draft file import or remote authentication.
Python compile/diff checks passed; no physical testing/commit/release.
The full Screens alignment goal remains active.

Bounded frame-update UI work (2026-10-08):
New FrameUpdateGate coalesces pending MainActor notifications within a session
generation. The framebuffer retains latest pixels; every callback still notifies
Metal. Atomic generation advancement resets the gate, and old tasks/old enqueue
attempts cannot consume new-generation notifications. One task can process while
at most one more task is pending for the current generation. Batched update counts
preserve first-five/sixty-frame thumbnail threshold crossings instead of silently
counting batches as frames. No measured latency gain is claimed.
Final core gate/streaming suite passed 6/6 (20.121s), including 1000 concurrent
producers, pending-task bound and reconnect generation isolation. An intermediate
compile failed because the generation helper also serves foreground/shortcut
guards; optional frameGate parameter corrected those callers without resetting
frame state for unrelated generations. Final compile/tests passed.
Owned iPhone connection recovery and zoomed trackpad edge-follow gate passed 2/2,
118.442s, runner terminal exit0, iOS test build passed. Wire event/result artifacts
exported; reconnect screenshot inspected. No physical/latency/frame-pacing
acceptance; fallback CGImage copying still executes on MainActor and is open.
git diff --check passed. Full alignment remains active; no commit/release.

Non-Metal fallback frame work (2026-10-08):
FallbackFramePipeline now creates CGImages on a serial user-initiated worker,
with one replaceable pending request and one latest pending main-thread
publication. Session generation changes clear pending work/results and reject
old requests; an old in-flight image cannot publish into the reconnected VM.
SessionViewModel currentImage publication remains on MainActor. Metal behavior
is unchanged. Existing thumbnails already use a background queue.
Eight targeted pipeline/gate/streaming tests passed in 20.186s. Deterministic
blocked-copy cases verify intermediate pending frames are not copied, actual
Framebuffer CGImage creation runs off-main, publication runs on-main, and
reconnection discards the old result. Final full core ran with explicit owned
system-Keychain QA: 272 tests, seven environment skips, zero failures, 99.938s.
Original production iOS project generic simulator build and macOS build passed.
git diff --check passed. Pipeline tests do not constitute a rendered physical
fallback session, input-to-present latency measurement or whole-UI motion review.
The full Screens alignment goal remains active; no commit/push/release.

External-display implementation started (2026-10-08):
Core ExternalDesktopPresentationView follows active SessionRegistry selection and
selected monitor crop with a separate Metal renderer/metrics and shared framebuffer.
Frame notifications use a non-Published Combine subject, preserving frame-update
coalescing without invalidating the full control UI for every new frame.
External surface owns no connection/input lifecycle. Delegate releases its window
on external scene disconnect. App Info.plist/project.yml declare external scene
configuration; iOS27 view-controller scene accessory is explicitly enabled and
retained. Older systems use the declared external-display scene configuration.
English/Chinese waiting copy added in core and app resources.
Apple primary reference:
https://developer.apple.com/documentation/uikit/presenting-content-on-a-connected-display
Local SDK UISceneAccessory / UISceneAccessoryRegistration / UIViewController
headers confirm iOS27 registration API/availability. No third-party inference
is treated as runtime acceptance.
macOS build passed (5.30s); original iOS generic build passed. Current app test
build passed with explicit registration enabled. Owned phone native display
selection passed 1/1, 66.244s; runner terminal exit0 after result finalization.
It proves primary-display control remains functional, not external scene delivery.
Owned simulator enumeration exposes TVOut screen2 but no IOSurface for that port.
One read-only screen2 capture failed to return after >60s; only exact owned simctl
capture PID94978 (parent94842) was SIGTERM'd, receipt retained; capture return -15.
No xcodebuild/test/other app was signalled. A read-only finalization sample was
collected while the original runner remained live; it then completed naturally.
No external pixel image was obtained. Do not claim AirPlay/external display works
yet. Need actual scene/pixel acceptance and physical attach/detach/input validation.
Plist lint/diff check passed. Full goal stays active; no commit/push/release.

External presentation state and pointer polish (2026-10-08):
ExternalSessionCanvas now shows live pixels only when session state is connected
and first frame is received; failed/disconnected sessions show generic localized
status instead of continuing to present old pixels as an online desktop.
The external pointer is a native CAShapeLayer, fed by the actual translated
coordinates from sendNativePointer, with selected-monitor origin and aspect-fit
letterboxing applied. Updates do not publish the entire SwiftUI hierarchy.
PointerArrowShape is shared with the existing iOS input cursor, preserving its
tip/hotspot/path. Outside-crop or invalid geometry hides the external arrow.
Language changes refresh external waiting copy.
23 pointer-transport/frame-gate tests passed (42.596s); three geometry cases passed,
including right-monitor global origin, vertical letterboxing and invalid bounds.
Native owned-phone display selection and connection recovery passed 2/2, runner
terminal exit0. This binary predates the final pure geometry extraction (same
mapping behavior); final original iOS generic build with extracted geometry passed.
No external scene pixel image was obtained; do not treat these tests as actual
external-screen runtime acceptance. Physical attach/detach/AirPlay remains open.
git diff --check passed. Full Screens goal remains active; no commit/release.

Computer sync merge foundation (2026-10-08):
New ComputerSyncJournal explicitly whitelists saved-computer metadata; excludes
runtime online/last-connected state and thumbnail/credential bytes. SSH metadata
retains endpoint/account/auth method and opaque local key reference; it does not
silently remove SSH for a recipient missing that key. Cloud credential scope was
asked via async preference question; no answer yet and no cloud configuration,
entitlements, account, upload or secret synchronization changed in this phase.
Logical counter plus peer tie-break gives deterministic whole-record edit wins,
not lossless per-field merging. Remove-wins tombstones cannot be overwritten by
an unaware offline peer's higher-clock edit. Re-add uses a new computer UUID.
A local tombstoned identity rejects upsert. No unsafe tombstone garbage collection.
Version forks/duplicate or mismatched records/unsupported schemas reject the
entire incoming snapshot. Persisted peer and logical clock are restored together.
Document limits 512KiB / 1000 records and clock overflow fail before mutation;
these are local codec bounds, not a claim about a cloud provider quota.
Seven tests passed (0.008s), including high-clock offline edit vs delete, merge
order/repeated merge convergence, relaunch/no-op, malformed/schema/version fork,
excluded runtime fields, retained SSH settings, size and overflow atomicity.
macOS build passed; original iOS generic build running. This is a merge/codec
foundation only, not wired into DeviceStore or cloud transport. Multi-device
synchronization is still unimplemented end-to-end. Full alignment goal remains
active; no commit/push/release.

Final sync foundation checks: eight tests passed (0.008s). Added semantic merge
result (local records changed / clock advanced / remote records need update).
It compares record sets instead of peer-bearing serialized payloads, preventing
different local peer headers from requiring endless rewrite loops. A stale
remote snapshot still requests update when local tombstones supersede it.
Final original iOS generic build passed; macOS compilation through final tests
passed. No cloud transport, DeviceStore wiring or credential sync is enabled.
Async credential-scope preference remains unanswered. Goal remains active.

### 2026-10-08：同步配置存储适配

- DeviceStore.applySyncJournal 显式应用已合并的日志，不自动启用云端同步。
- 同 ID 的配置更新保留本机 isOnline / lastConnected；新远端电脑默认离线。未出现在日志中的本机电脑保留。
- 删除标记移除列表配置，保留本机凭据和现有会话；凭据清理及跨设备凭据策略仍待确定。
- 完整日志校验、候选列表编码完成后才更新偏好设置和内存列表。UserDefaults 原有持久化语义不变，不宣称跨文件事务或同步落盘。
- ComputerSyncStoreTests 两项验证配置更新、未参与同步条目、运行状态、新条目、重启持久化、重复应用和删除不复活；连同日志测试共 10 项通过，git diff --check 通过。
- 尚未接入云端传输、账户隔离、自动捕获本地编辑或列表实时通知；全面 Screens 对齐和真机体验验收仍未完成。

### 2026-10-08：同步结果的列表发布边界

- DeviceListViewModel.applySyncJournal 在存储成功后一次发布完整列表，重复相同结果不触发列表重绘。
- 远端删除只改变电脑库，保持 activeSessionDevice；不会因同步列表更新中断当前会话。
- 新增发布次数及活动选择回归验证；11 项同步日志/存储/列表测试全部通过。云端传输、本地编辑捕获、账户隔离仍未接入，不宣称同步功能完整。
- 原始 iOS 工程 generic iOS Simulator 构建通过：/tmp/aetherscreens-sync-list-ios-build.log；未进行真机验收。

### 2026-10-08：同步端点更新与旧密码关联修正

- 审计发现凭据仍以电脑 UUID 为索引，直接应用远端 host / port / authMethod / username / SSH 配置改变可能把旧凭据带到替换后的服务器。
- 修正前述“远端配置更新已接入”的范围：当前允许名称等不改变认证目标的配置；认证目标变化抛出 SyncApplicationFailure.credentialRebindingRequired，整批不写入、不发布，避免半更新。
- 此处是临时失败关闭边界，完整目标仍要求实现凭据与端点/账号绑定及重新输入流程；不把拒绝配置变化视为同步完成。
- 新测试验证带其他记录的端点变更批次全部拒绝、内存列表及持久化原始字节不变。12 项同步测试通过，git diff --check 通过。

### 2026-10-08：密码与连接目标绑定，替代临时同步拒绝

- 移除上一阶段 credentialRebindingRequired 临时拒绝，远端地址、端口、账号及 SSH 配置现在可应用；旧密码只对其原绑定目标可读。下次连接新目标时走既有 VNC / SSH 交互提示，输入并保存后重新绑定。
- 独立 vnc / ssh 绑定元数据使用 host、port、authMethod、username、SSH 配置白名单，不含凭据字节。名称、在线状态、连接时间不进入身份。保守比较可能让等价地址字符串变化也重新提示。
- 存储旧目标绑定先于列表更新；此处不是 UserDefaults 跨键原子事务，进程在两次写入之间退出最多保留旧列表及绑定。新增远端条目显式 unbound，防止继承同 UUID 的孤立旧密码。
- 本机显式保存 VNC 密码及严格 SSH vault 写入成功后分别更新绑定。SSH 密码读取统一走 DeviceStore，目标不符时不读取 vault。共享私钥引用仍保持原策略，未新增秘密同步。
- 既有账户提示测试改为验证新账号可取密码、旧账号配置不可读取；旧版密码迁移测试使用真实已保存电脑。既有迁移机制保留。
- 云端传输、账户隔离、本地编辑自动捕获、物理设备提示交互验收仍未完成。
- 同步/存储/账户提示回归共 32 项通过；原始 generic iOS Simulator 构建通过。日志：/tmp/aetherscreens-credential-binding-final-tests.log、/tmp/aetherscreens-credential-binding-ios-build.log。git diff --check 通过。

### 2026-10-08：SSH 交互保存与完整回归

- 审计补齐 SessionViewModel.submitSSHPassword 的“记住密码”绑定，严格 vault 写入成功后才更新目标绑定；失败仍保持原提示框。
- 首轮完整回归发现新的 SSH 密码读取路径错误绕过会话注入的 vault，导致两项拒绝读取/显式断开重连失败。已修复 getSSHPassword 支持会话仓库，并保留无绑定临时 SSH 会话的原读取行为；同步新增条目的 unbound 标记优先阻止继承旧密码。
- 新增真实 SSH/RFB 用例：同步账号变化触发密码提示，保存与主机身份确认后连接成功，第二次连接无需密码或主机提示，服务端完成两次认证。
- 原始 iOS generic Simulator 构建通过：/tmp/aetherscreens-binding-reconnect-ios-build.log。完整修正版回归仍在运行，不将首轮失败日志计为通过证据。
- 修正版完整核心回归自然退出 0：290 项，7 项环境条件跳过，0 失败，92.829 秒；启用 AETHERSCREENS_SSH_KEYCHAIN_QA=1，日志 /tmp/aetherscreens-binding-reconnect-full-core.log。新增同步账号变化→记住密码→真实 SSH/RFB 重连测试通过。此结果不代替实际 Macmini / iPhone / 外接显示器验收。

### 2026-10-08：本地配置变更捕获与日志持久化

- ComputerSyncJournal.captureLocalComputers 接受完整电脑库快照；新增及配置编辑产生版本，已知条目缺失产生保留的删除标记。禁止传入过滤搜索结果，不把列表顺序、isOnline 或 lastConnected 当成配置修改。
- 批量捕获先建立候选日志、完整校验再发布，一批仅进行一次完整编码，避免逐条编码整个文档。重复 ID、无效配置、容量/时钟失败不部分更新。被删除身份不能复活，重新添加须用新 UUID。
- DeviceStore.captureLocalSyncJournal 显式捕获并将 peer、counter、records 保存为一个文档；重启保留身份和逻辑时钟。损坏文档抛错，原字节不覆盖、不重新创建身份。重复无变化不重写文档。
- 17 项同步测试通过，覆盖本地新增编辑删除、运行状态不增版本、重复/无效批次原子拒绝、重启持久化及损坏数据保留。
- 此捕获接口仍未自动挂到 UI 编辑事件或云端协调器；云端传输与账户隔离未完成。前述完成范围是捕获及本地持久化基础，不是可用的多设备同步。
- 同时把旧凭据目标捕获改为一次批量写入，不再逐台电脑读取并写入整份绑定字典；已有绑定无变化不写入。最终 17 项同步测试通过，git diff --check 通过。
- 最终原始 iOS generic Simulator 构建通过：/tmp/aetherscreens-local-sync-capture-final-ios-build.log。未启用云端上传、修改签名配置或发布版本。

### 2026-10-08：本地捕获→远端合并→列表发布与待应用恢复

- DeviceStore.mergeSyncSnapshot 在同一 store 锁内先捕获完整本地库、再合并并验证远端；无效远端不保存捕获候选，不部分改变列表或已保存日志。
- 合并结果保留本地身份、逻辑时钟和删除标记；DeviceListViewModel.mergeSyncSnapshot 仅在列表内容变化时发布一次。
- 设置待应用日志后更新列表、保存正式日志、清除待应用记录。loadDevices / captureLocalSyncJournal 在捕获前恢复现存待应用记录，防止把尚未应用的远端新增误当成本地删除。
- 这是 UserDefaults 下现存待应用状态的恢复机制，不是 fsync 事务或断电一致性保证；多键异步持久化顺序仍需在实际云端启用前升级验证。未声称进程崩溃或断电的所有写入排列都安全。
- 38 项同步/存储/账户提示测试通过：本地条目与远端条目合并、重启保存、空列表待应用恢复不误删除、损坏远端/待应用数据保留及原有凭据绑定回归。
- 仍无云端传输、账户隔离、自动 UI 编辑触发；本轮接入不能等同于可用多设备同步。
- 最终补齐 ViewModel 合并列表发布/回声无重复刷新测试，共 39 项通过。原始 iOS generic Simulator 构建通过：/tmp/aetherscreens-sync-merge-recovery-ios-build.log；测试日志 /tmp/aetherscreens-sync-merge-recovery-final-tests.log。git diff --check 通过。

### 2026-10-08：电脑卡片缩略图冷加载与淡入

- 发现 DeviceCardView.body 调用同步 getThumbnail，缓存未命中时在视图求值中 Data(contentsOf:) 与图片解码；改为内存-only 初始值及 .task 异步后台加载，取消的卡片任务不发布结果。
- ThumbnailStore 使用 utility 串行队列读取磁盘，ImageIO 立即解码并限制最长边 480；兼容旧 PNG。NSCache 设置 64 张 / 16 MiB 建议上限，按解码字节成本计费。
- 新缩略图通过 publisher 通知已显示卡片；通知路径只读取内存，不读磁盘。磁盘加载完成时若已经存在更新的实时预览，保留更新预览，不以旧磁盘图片覆盖。
- 冷预览淡入 0.18 秒，Reduce Motion 关闭动画。缓存命中在卡片初始状态直接显示，避免重新出现时闪占位。
- 5 项缩略图测试通过，覆盖真实 JPEG 落盘→冷实例异步读取、旧高竖屏 PNG 下采样、缺失/损坏文件占位和既有保存缩放。新增测试仅清理自己创建的临时目录。
- 手机尺寸模拟器连接恢复回归在运行；该用例不量化列表滚动帧率，不代替真实卡片冷启动视频或物理设备性能验收。
- 最终 5 项缩略图测试通过（/tmp/aetherscreens-async-thumbnail-final-tests.log）；原始 iOS generic Simulator 构建通过（/tmp/aetherscreens-async-thumbnail-final-ios-build.log）。
- iPhone 12 Pro 尺寸的自有模拟器连接恢复用例 1/1 通过，runner 自然退出 0，44.227 秒；build/iphone-async-thumbnail-20261008/result.xcresult。已查看重连截图及导出清单，确认桌面/工具栏恢复。该截图不是电脑卡片动画验收证据。
- 既有 ThumbnailStoreTests 同样改为自有临时目录，避免继续往共享应用缓存写测试预览；未扫描或删除旧共享缓存。

### 2026-10-08：电脑卡片真实会话预览的中英文冷加载验收

- 新增 testControlledComputerPreview / testChineseControlledComputerPreview，通过实际添加自有 UUID 名称电脑→连接受控 RFB→断开→查看热预览→重启→查看冷预览的完整产品路径，不使用预置图替代真实会话快照。
- 测试 defer 仅通过 UI 删除自己创建的准确名称条目，不改用户已有电脑。加入受控 QA 套件。
- 同时补 ThumbnailStore.removeThumbnail：本机删除电脑清除 JPG / PNG 与内存预览，运行期保留 removed ID 防止旧会话迟到快照重新写回；读盘途中完成的旧图片也不能重新进入缓存。该操作针对本机显式删除，不改变远端同步删除保留现有会话的策略。
- 文件保存与删除使用同一 store 锁序列化；图片加载仍在后台，视图只读 NSCache。缓存删除为 best effort，未宣称系统文件 I/O 错误下严格安全清除。
- 24 项缩略图/存储回归通过，包括删除后迟到保存不重建文件；中英文 UI 验收正在运行。
- 首轮中英文预览测试 2/2 通过（104.247 秒），但截图复核发现新创建卡片的 Warm Computer Preview 仍为占位；Cold Computer Preview 为真实彩色 RFB 网格。纠正：首轮只能证明冷恢复与操作流程，不证明热预览实时显示正确。
- 正在修复卡片重新出现时内存刷新以及异步空结果不覆盖新内存图片；新增 VoiceOver 预览可用状态，中英文验收明确等待真实预览状态后截图，不以卡片存在替代预览加载完成。修正版验收仍在运行。
- 加强断言的第二轮中英文验收均在 Warm 预览可用状态等待时失败；Cold 状态可用。没有把这轮算通过。
- 进一步把异步加载身份包含最近连接时间和预览修订号：全屏会话关闭后 reload 更新 lastConnected 会重新触发加载；卡片出现/保存通知提升修订号并取消旧请求。读取结果发布时优先采用更新内存图片，避免旧空结果盖掉新快照。
- 修订后的 24 项缩略图/存储核心测试通过；第三轮中英文实际 UI 验收正在运行，尚无成功结论。
- 第三轮修订版中英文 UI 验收 2/2 通过、0 失败，109.458 秒，runner 自然退出 0：build/iphone-computer-preview-refresh-20261008/result.xcresult。已查看四张 Warm / Cold 中英文截图，新生成的准确 UUID 名称卡片均显示真实彩色 RFB 网格，无占位图。测试通过 UI 删除自己创建的条目。
- 最终 24 项核心回归通过：/tmp/aetherscreens-preview-refresh-core.log；原始 iOS generic Simulator 构建通过：/tmp/aetherscreens-computer-preview-refresh-ios-build.log。git diff --check 通过。
- 这证明受控模拟器的返回列表预览刷新和冷加载，不证明实际设备滚动帧率、动画掉帧、30 分钟会话或 Screens 全面功能对齐。

### 2026-10-08：离屏预览引用释放与队列取消

- DeviceCardView.onDisappear 清空持有的 CGImage，隐藏卡片不响应快照通知重新持有图片；重新出现用现有修订号/连接时间加载策略恢复，避免长列表逐个浏览后仅依靠 NSCache 上限却由 View State 持有大量已解码图片。
- ThumbnailStore.loadThumbnail 支持 Task 取消：已取消任务不取缓存；未开始的排队读盘跳过，正在执行的读盘/解码允许完成但取消结果不向卡片发布。当前 worker 队列仍串行，不引入额外并发图片解码。
- 新增挂起自有队列、启动请求、取消、恢复队列、验证无缓存、随后正常读取的真实 JPEG 回归。内部队列注入仅用于确定性测试，正式初始化继续使用独立 utility 队列。
- 7 项缩略图测试通过；中英文真实会话生成→热预览→重启冷预览 UI 回归运行中。尚未记录大量卡片滚动的实际内存峰值或帧率，不用结构性改进代替性能测量。
- 最终中英文 UI 回归 2/2 通过，runner 自然退出 0：build/iphone-computer-preview-lifecycle-20261008/result.xcresult。已查看四张 Warm / Cold 截图，确认离屏释放后返回列表、重启均恢复真实 RFB 预览；自有 QA 条目通过 UI 清理。
- 最终原始 iOS generic Simulator 构建通过：/tmp/aetherscreens-thumbnail-lifecycle-ios-build.log；7 项缩略图核心测试通过：/tmp/aetherscreens-thumbnail-cancellation-tests.log。git diff --check 通过。

### 2026-10-08：受控电脑列表滚动性能测量

- 根据本机 SDK 27 XCTMetric / XCTMetric+UIAutomation 头文件及 Apple 文档确认使用 scrollingAndDecelerationMetric，不新增已废弃 scrollDraggingMetric / scrollDecelerationMetric。
- 新增显式 testControlledComputerPreviewScrollingPerformance：真实保存电脑并生成预览、重启确认冷预览后，使用 scrollingAndDecelerationMetric + XCTMemoryMetric(application:)；iOS 26+ 同时记录 XCTHitchMetric(application:)。
- 3 次测量，滚动前回到顶部、每轮 stopMeasuring 后在测量区间外复位。测量用例通过 --case 显式运行，不无条件给所有功能验收增加性能循环。
- 当前受控应用里其他既有 QA 电脑保留；这是小列表基线，不是固定大规模数据集、改动前后性能比较或真实设备门槛。暂不设置无证据的性能阈值。
- 官方依据：https://developer.apple.com/documentation/xctest/xctossignpostmetric ；运行中，结果需从 xcresult 指标读出后再判断支持范围。
- 实际受控测量自然退出 0，1/1 通过；原始数据 build/iphone-computer-preview-metrics-20261008/metrics.json。滚动与减速区间 3 样本为 0.968073458 / 0.967806167 / 0.967922209 秒。
- 进程物理内存峰值 40995.312 / 41011.696 / 41011.696 kB，约 41 MB（十进制）；这是该小列表测量区间的进程物理内存指标，不包含对全部 GPU/系统内存的证明。
- iOS 27 模拟器虽然可初始化 XCTHitchMetric，但结果包没有任何 hitch 指标样本；不能报告“零卡顿”或推断实际 FPS。滚动区间时长也不是帧率。
- QA runner 新增性能用例的自动 metrics.json / metrics-summary.json 导出，检查三次正数秒制滚动样本、保留原指标名称/单位、标明模拟器或真机环境，并明确 hitch 样本是否实际存在。已对本次实际 xcresult 执行导出 helper 验证；Python 编译和 git diff --check 通过。
- 尚无固定大量卡片数据集、改动前后对照或物理设备性能门槛；这些保留为全面流畅度验收未完成项。

### 2026-10-08：固定 64 电脑列表夹具与滚动基线

- 新增 scripts/qa/large_library_ui_fixture.swift，仅附加到临时 QA app 源文件；原始生产 App / 工程 / 签名配置不变。
- 64 个随机 UUID、自有名称前缀、480×300 生成网格预览，无真实账号/秘密。创建前原子记录 owned journal，重启 display 不重新生成图片，使进程缓存真正从冷状态开始。
- 新增 testControlledLargeLibraryScrollingPerformance：筛选唯一运行前缀，仅测这 64 条；3 轮、每轮 6 次快扫，复位不计入测量。结束后另行遍历至第 64 条，验证预览可用并截图；完整遍历不在性能测量区间内，不能把测量内存峰值当成完整遍历的峰值。
- 测试 defer 与 runner 终态备用清理均只处理 journal 记录的自有 UUID，核对准确名称，并验证对应 JPG/PNG 不存在。清理失败保留 journal 并报错，不删除未知条目或旧配置。
- 该显式夹具用例限定自有模拟器，当前 physical-device 路径没有临时夹具安装流程，不用缺少夹具的真机运行制造通过结论。
- 运行中，尚无性能/正确性/清理成功结论；图片为生成测试数据，不能替代真实远程画面或物理设备性能证明。
- 固定 64 条用例自然退出 0，1/1 通过，218.012 秒：build/iphone-large-library-metrics-20261008/result.xcresult。自动指标导出完成；清理回执 large-library-cleanup.json 为 remaining={}，自有 64 条配置与预览已清理。
- 三轮滚动指标样本 2.584666625 / 2.566870959 / 2.5686155 秒；这些是 XCTest 记录的滚动/减速区间，不是整段测试墙钟时间或 FPS。
- 测量区间进程物理内存峰值 53217.824 / 53135.904 / 53021.216 kB，约 53 MB；无 hitch 样本。不能把 41 MB 小列表和本次 53 MB 数据直接解释成优化前后变化，数据集和操作不同。
- 已查看首尾两张截图：筛选结果显示 64 computers、键盘已关闭；首条和末条预览为生成网格，最后一条在屏幕内正常显示。应用原有 Bonjour 发现区仍存在，未移除用户配置或伪装为完全隔离网络环境。
- 本轮仅新增 QA 夹具、测量用例和导出/清理流程；生成 QA app 编译及实际测试通过，生产源/签名未修改。Python 编译与 git diff --check 通过。物理 iPhone、掉帧指标、真实远程会话压力及完整 Screens 对齐仍未完成。
### 2026-10-08：电脑列表重复发布抑制

- DeviceListViewModel.reload 仍从存储读取完整电脑列表，但只有数组值实际变化才发布 devices，避免无变化的重复刷新触发列表求值。连接时间参与 RemoteDevice 相等比较，返回会话后预览重新加载所依赖的真实变化仍发布。
- 新增真实临时 UserDefaults / Combine 订阅回归：连续无变化 reload 不发布；重命名、lastConnected 更新和删除分别发布一次。未改变发现服务、排序或活动会话。
- ComputerSyncStoreTests 12 项全部通过，日志 /tmp/aetherscreens-reload-publication-tests.log；git diff --check 通过。此项验证发布次数，不宣称已改善实际 FPS；物理设备流畅度和完整 Screens 对齐仍待完成。
### 2026-10-08：浮动工具栏边缘反向拖动

- FloatingKeyboardToolbar 改为按事件消费位移并限制当前位置，避免越界累计位移造成反向拖动死区。手势结束/取消重置前次位移；折叠内容仍保持挂载，原有弹簧与 Reduce Motion 策略不变。
- 提取 FloatingToolbarGeometry 并验证四个边缘越界后 10pt 反向立即生效，以及工具栏大于视口时居中；2 项核心测试通过，日志 /tmp/aetherscreens-floating-edge-tests.log。
- 自有 iPad 模拟器中英文 testControlledFloatingToolbar / testChineseControlledFloatingToolbar 回归正在运行：build/ipad-floating-edge-20261008/result.xcresult，runner 日志 /tmp/aetherscreens-floating-edge-ui.log。此次尚未有 UI 成功结论；需等待现有运行自然结束，不能从观察等待时间推断失败或重启。
- 最终上述现有运行自然退出 0，2/2 通过、0 失败，139.539 秒。用例验证展开/折叠拖动、拖动不发送远程 pointer、快速菜单真实 Escape 按下释放、草稿保留/键盘关闭及旋转后控件留在屏幕内。已导出 10 张附件并查看中文竖屏 QA 草稿、英文横屏展开移动截图，布局正常。
- 边缘越界后反向连续手势目前由几何回归覆盖，现有 UI 用例只验证普通拖动及状态保持；没有把静态截图宣称为连续跟手动画/FPS 或真机证明。git diff --check 通过；当前没有该次未收尾测试进程。
### 2026-10-08：失败重试统一重连输入清理

- RemoteDesktopView 的 Retry Connection 从直接 startSession 改为 reconnectSession，与菜单重新连接一致：先释放工具栏按键、修饰键和触控板按钮、取消旧认证提示并更换输入代次，再断开并重连。
- 中英文受控连接恢复测试改为实际点击 Retry Connection；仍验证新 TCP 连接、缩放/触控模式保留、新连接 Shift 按下/释放和成功断开。运行中：build/iphone-retry-input-reset-20261008/result.xcresult，日志 /tmp/aetherscreens-retry-input-reset-ui.log。
- PointerTransportTests 核心回归也在运行，日志 /tmp/aetherscreens-retry-input-core.log；尚未宣称该候选 UI/核心测试通过。继续等待现有进程，不重启或终止运行。
- 最终核心 PointerTransportTests 20/20 通过，42.511 秒；中英文 UI 2/2 通过、0 跳过/失败，runner 自然退出 0，summary 无运行时警告。结果 build/iphone-retry-input-reset-20261008/result.xcresult。
- 已查看中文断线错误页与英文重连截图，重试控件可见、桌面恢复；核对两份实际收包附件，新连接首次鼠标点击前没有任何 key-down，之后显式 Shift 恰好 [down, up]。用例同时确认新 TCP 会话和缩放/触控模式保留。git diff --check 通过；真机重连与完整 Screens 对齐仍未完成。
### 2026-10-08：累计改动完整核心回归

- 以 AETHERSCREENS_SSH_KEYCHAIN_QA=1 运行完整 swift test，进程自然退出 0；305 项、7 项环境依赖跳过、0 失败，92.386 秒。日志 /tmp/aetherscreens-alignment-full-core-20261008.log。不是把 7 项跳过算通过，也不替代 iPhone / Mac 真机验收。
- 覆盖当前累计预览、列表发布、同步存储、工具栏几何、RFB/SSH、按键和指针等核心改动；git diff --check 通过。
- Debug 构建性能输出的 4K raw-tile ZRLE 三样本约 1026/1022/1031 ms；需先核对 Release 优化构建同一夹具，再判断产品解码瓶颈。该 fixture 不能代表所有真实桌面编码/延迟，也不能凭功能测试通过宣称丝滑。完整 Screens 功能与实机验收仍未完成。
### 2026-10-08：4K 解码 Release 基线复核

- 对相同 3840×2160、连续三帧 raw-tile ZRLE 夹具运行 swift test -c release，进程自然退出 0，1/1 通过；每帧所有输出字节均与期望 BGRA 比较。
- 解码区间三样本 13.556 / 13.451 / 13.362 ms，首包 24892842 bytes；日志 /tmp/aetherscreens-zrle-release-baseline-20261008.log。此前 Debug 约 1 秒不能作为正式性能瓶颈结论，未据此盲目更换解码算法。
- 该计时只包含本机解压/瓦片扩展，不包含网络、主线程调度、纹理上传、显示或输入往返；不宣称 4K 60 FPS、手机相同速度或低端设备门槛。
- 正在补跑 Release ZRLEDecoderTests / ZRLETransportTests 整组，日志 /tmp/aetherscreens-zrle-release-regression-20261008.log；尚未有整组通过结论。
- 整组自然退出 1：34 项、3 个断言失败，集中于 pending decode 重连和输入抢先测试。解码像素类测试通过。重连测试明确在收齐数据后延迟 20ms 才重连，但 Release 4K 解码约 13ms（本例 2048² 更小），将合法重连前帧也计为“旧解码发布”；输入测试同样以耗时替代 worker 被阻塞的确定证据。需用可控 decode worker 排队建立真实 pending 状态再验证，不能删断言或把这次失败算通过。
### 2026-10-08：解码等待并发回归确定化

- RFBClient 保持 public 初始化参数与自有串行 decode worker；新增 internal 指定队列初始化供测试控制。未改解码算法或正式连接/代次防护。
- 两项真实 TCP 回归用自有队列上的 semaphore 阻塞任务确定 worker 等待状态，终态 defer 放行，不再假设 20ms 或大图一定解得慢。输入测试先收滚轮再放行帧；重连测试先确认第二条连接及 0 帧，再放行队列，保留旧帧 inverted 断言和替换像素完整校验。
- Release 整组 34/34 通过、0 失败，4.666 秒，进程自然退出 0：/tmp/aetherscreens-zrle-release-deterministic-20261008.log。4K 像素完整校验三样本约 14.1/15.0/14.2ms。
- Debug 同组正在运行，日志 /tmp/aetherscreens-zrle-debug-deterministic-20261008.log；不把 pending worker 证明扩大成“正在运行的单个解码函数可中断”或物理 iPhone FPS。
- 最终 Debug 同组 34/34 通过，18.798 秒，进程自然退出 0。Release 和 Debug 都保留真正阻塞 worker 的滚轮可达及重连旧帧不发布断言；git diff --check 通过。没有发布或改用固定延迟绕过失败。
### 2026-10-08：完整 Release 核心回归及同步接入缺口核对

- 当前候选 AETHERSCREENS_SSH_KEYCHAIN_QA=1 swift test -c release 自然退出 0：305 项、7 项实机环境依赖跳过、0 失败，76.463 秒。日志 /tmp/aetherscreens-alignment-full-release-20261008.log；git diff --check 通过。正式优化下的完整核心回归覆盖新增 internal decode queue 初始化及其调用方。
- 本次整组负载下 4K 解码约 15.8/16.4/15.6ms；不是和孤立运行 13–15ms 做严格改动前后性能对照。测试计时没有网络/显示/真机 FPS 证明。
- 当前源码核对：captureLocalSyncJournal / mergeSyncSnapshot 仍是显式接口；没有 CloudKit/ubiquity 传输、账户隔离或自动捕获本地 UI 编辑。多键 UserDefaults pending/journal/list/credential bindings 仍非同步落盘事务。下一阶段需先建立可靠的整体同步提交边界，再接本地编辑捕获、云端与账户隔离，不以现有合并单测宣称多设备同步可用。
- 本轮没有改生产 entitlement、账户或发布配置；真机、远程文件拖放、Curtain 及完整对齐目标仍保留。
### 2026-10-08：本地同步整体检查点文件基础

- 新增 ComputerSyncCheckpoint（local-only envelope）：日志、完整电脑列表、本机凭据目标绑定字符串一起编码；验证 schema、日志、唯一/有效电脑、日志记录与配置一致、绑定键/大小及 8MiB 总量。不上传运行状态或本机绑定；调用方只允许现有目标元数据，不含凭据字节。
- ComputerSyncCheckpointFile 写自有 UUID 临时文件（0600、O_EXCL/O_NOFOLLOW），完整写入和 fsync 后同目录 rename，再 fsync 父目录；rename 前失败保留原目标，rename 后目录同步失败显式 durabilityUncertain。只清理本次临时文件；目录由调用方准备。读取最多 8MiB+1，损坏文件报告错误不重建。
- 3 项真实自有临时目录测试通过：整体替换/重启读取/权限/记录配置不一致拒绝、损坏文件不改写、rename 到已有目录失败保留目录内容且清理临时文件。日志 /tmp/aetherscreens-sync-checkpoint-tests.log，git diff --check 通过。
- 尚未接入 DeviceStore、迁移或云端；既有 UserDefaults 同步路径未改变。测试不是断电/故障注入证明，fsync 不宣称设备硬件级绝对持久。下一步需将候选合并列表和绑定构造整合进该提交边界，再发布内存与兼容偏好镜像。
### 2026-10-08：检查点绑定白名单及无副作用候选构造

- 抽取 ComputerCredentialTarget，与 DeviceStore 现有目标 token 共用固定 Codable 字段。检查点只接受 unbound 或可解码且与排序字段重新编码逐字节一致的目标 JSON；未知字段（含额外 password）、损坏 token 和非法地址拒绝，不把任意 base64 内容作为绑定持久化。
- 新增合法绑定/额外秘密字段/损坏字符串回归，使用生成测试值；检查点、同步存储、设备存储共 34 项通过，日志 /tmp/aetherscreens-sync-checkpoint-bindings-tests.log。
- DeviceStore 同步应用先构造完整 ComputerSyncCheckpoint 候选：保留本机运行状态、在候选字典捕获旧目标绑定、为新远端 UUID 标记 unbound。候选生成和校验不写任何偏好键；应用阶段再发布原有兼容存储和内存列表。
- 候选重构后同组 34 项通过，日志 /tmp/aetherscreens-sync-checkpoint-candidate-tests.log；git diff --check 通过。文件提交仍未接到实际 Store，现有多键 UserDefaults 非事务限制保留；下一步接提交/恢复和本地编辑一致性，尚非可用云同步。
### 2026-10-08：同步合并提交前完整校验

- mergeSyncSnapshot 在写 pending 日志之前构造并校验完整检查点及预编码电脑列表，提交阶段使用已验证候选发布；applySyncJournal 共用发布方法。避免绑定校验失败却留下本次不可恢复 pending 日志。
- 新增自有 UserDefaults 失败回归：有效远端改动配合无效本机绑定时，拒绝合并、内存配置/持久列表/正式日志/原绑定均不变、pending 不存在，重启原配置仍保留。不是只检查抛错。
- 检查点/同步存储/设备存储 35 项全部通过，1.811 秒：/tmp/aetherscreens-sync-preflight-tests.log。git diff --check 通过。
- 原始 iOS generic Simulator 构建正在运行，日志 /tmp/aetherscreens-sync-checkpoint-ios-build.log；文件检查点正式提交/恢复、本地编辑一致性及云端账户接入仍未完成，现有 UserDefaults 仍非同步落盘事务。
### 2026-10-08：DeviceStore 显式文件提交与完整恢复

- 上一阶段原始 iOS generic Simulator 构建自然退出 0（/tmp/aetherscreens-sync-checkpoint-ios-build.log），证明此前检查点/白名单/预检候选在 iOS 编译。不是本轮新增 Store 接口的单独 iOS 构建结论。
- 新增 internal mergeSyncSnapshot(_:checkpointURL:)：生成完整候选与编码后先保存/fsync/rename 检查点，再发布兼容偏好和内存列表；原 public 默认接口不自动启用文件或云同步。新增 recoverSyncCheckpoint(at:) 验证文件后完整重放绑定、列表、正式日志并清除旧 pending，保留文件供重试。
- 37 项检查点/同步存储/设备存储回归通过，1.852 秒：/tmp/aetherscreens-sync-durable-store-tests.log。新增验证文件写失败→所有偏好与内存不变；成功提交后模拟偏好副本丢失/坏日志→新 Store 显式恢复完整配置、日志、unbound 标记，重复恢复/后续捕获不制造删除。git diff --check 通过。
- 自动启动恢复尚未接入。未来协调器必须在允许本地编辑前恢复指定账户检查点，并同步持久化后续本地编辑；不能随时重放旧检查点覆盖新编辑。本轮没有生产路径自动调用、账户上传或密钥同步，也不是物理断电证明。完整 Screens 目标仍保留。
### 2026-10-08：本地编辑显式检查点捕获

- 新增 internal captureLocalSyncJournal(checkpointURL:)，完整本机列表捕获元数据/删除标记后，先保存含配置与绑定的文件检查点，再更新兼容绑定与日志。默认 public 接口不自动启用文件或云端。
- 本地运行状态也保存到 local-only 检查点，但 lastConnected 变化不提升同步逻辑时钟，不进入可上传的 journal。检查点持续保留，供显式恢复。
- 38 项检查点/同步存储/设备存储测试通过，1.808 秒：/tmp/aetherscreens-sync-local-checkpoint-tests.log。新增真实文件回归：初始捕获→重命名/删除→重新捕获→仅连接时间更新捕获→故意恢复旧偏好副本→新 Store 显式恢复最新编辑、保留 tombstone 与 peer，不复活删除条目；文件写失败保留原文件和日志。git diff --check 通过。
- 这是编辑完成后显式捕获，不是 UI 编辑与文件保存的单一事务；编辑后尚未捕获时重启仍可能回到旧检查点。必须继续将本地编辑纳入正式提交、启动恢复和账户协调器后才能自动使用；当前不宣称已完成云同步。
### 2026-10-08：本地配置完整提交接口

- 新增 internal commitLocalSyncConfiguration(_:checkpointURL:)：输入完整未筛选候选列表，先登记旧完整列表再捕获候选，确保从未建立日志时的首次删除也生成 tombstone；检查点文件提交成功后才发布偏好副本与内存配置。
- 旧目标绑定保持原有身份，新 UUID 显式 unbound；密码/私钥写入或删除不在这个配置接口内，现有 Keychain 策略未改变。重用旧 tombstone UUID / 重复 UUID / 校验及文件写失败均在发布前拒绝。
- 检查点/同步存储/设备存储 39 项通过，1.807 秒：/tmp/aetherscreens-sync-local-transaction-tests.log。新增写失败所有偏好和内存不变、首删 tombstone、成功文件完整恢复、新身份不继承旧密码、重复 UUID 不覆盖已提交文件回归；git diff --check 通过。
- 这是未来账户协调器的显式配置事务，不是已接入 UI 的完整凭据/配置联合事务；启动恢复、账户目录隔离、界面保存错误反馈、凭据操作顺序及云端仍需完成。默认生产路径不自动调用或覆盖用户文件。
### 2026-10-08：检查点账户作用域核对

- 新增 ComputerSyncAccountScope，由 provider 稳定不透明账户 ID 的 SHA-256 摘要确定，不使用邮件/显示名；检查点仅记录摘要，属于标识隔离而非加密或身份认证。
- 文件 load 核对期望作用域；save 在覆盖前验证已有文件归属并拒绝不同账户/有作用域文件被无作用域调用读取，损坏旧文件也不自动覆盖。无作用域旧文件向账户文件迁移须显式实现，当前不静默认领。
- Store 的显式捕获、合并、本地配置提交和恢复接口传递可选作用域；默认生产流程/无作用域旧测试保持原路径。
- 回归包含稳定摘要、不同账号读/写拒绝且文件原样保留、不存原账户 ID、错误作用域 Store 恢复不改内存与任何偏好。检查点/同步存储/设备存储测试日志 /tmp/aetherscreens-sync-account-scope-tests.log。
- 最终同组 41 项全部通过，1.911 秒，进程自然退出 0；git diff --check 通过。
- 尚无 provider 登录、账户切换协调器、每账户偏好/Keychain 命名空间或跨 Store/进程写者锁；文件归属预检不能代替并发写者串行化。账户隔离端到端仍未完成，不启用云上传。
### 2026-10-08：检查点写者锁与非阻塞冲突

- 文件 save 采用同目录、按目标文件名摘要固定的 0600/O_NOFOLLOW lock 文件与 POSIX flock(LOCK_EX|LOCK_NB)。持锁覆盖已有文件账户核对、临时写入/fsync、rename 和目录 fsync；不同进程/Store 使用相同接口时也针对同一 inode 竞争。锁忙立即抛 busy，不阻塞等待。
- 锁文件不在每次写后删除，避免换 inode 使第二写者绕过正在持有的锁；只清理本次 UUID 临时提交文件。测试仅清理自己的整个临时目录，文件清单区分保留锁与泄漏临时文件。
- 首次编译遇 Darwin 命名空间 flock 结构体/函数冲突，改为显式函数类型选择未限定的已导入 POSIX flock；本机 Swift 编译/实际锁回归确认，不使用私有符号桥接。
- 检查点/同步存储/设备存储 42 项全部通过、1.877 秒：/tmp/aetherscreens-sync-writer-lock-tests.log。真实另一个 FD 持锁时保存报 busy、文件逐字节不变；释放后保存成功。git diff --check 通过。
- 这是合作写者互斥，不是绕过锁的外部进程防护，也未解决同一账户旧候选覆盖新提交的版本冲突；下一步需提交版本核对和账户协调器。云端/启动/UI 自动接入未完成。
### 2026-10-08：检查点旧提交冲突防护

- 新增文件 save(_:replacing:)：写者锁内核对完整期望旧检查点，与当前读取不相等时抛 conflict，文件不变；比较配置/运行状态/绑定/账户和日志，而非仅 counter。
- Store 显式合并、捕获和配置事务在构造候选前读取文件基线，验证兼容日志与文件日志一致，再以该完整基线提交。偏好日志落后于文件时要求先显式恢复，拒绝用旧日志覆盖新提交。
- 新增文件级同日志但 lastConnected 已更新的 stale candidate 拒绝回归；新增两个自有 UserDefaults Store 共享文件测试，A 写新配置后 B 旧日志提交拒绝、B 内存/偏好/文件均不变，显式恢复读到 A 新配置。
- 默认文件保存便利接口只保证从该次读取到提交期间的比较；持有旧候选的调用方必须显式携带准备时基线。Store 已使用显式接口。尚非云端乐观锁、UI 协调器或全账户状态隔离，完整 Screens 目标仍保留。
- 最终检查点/同步存储/设备存储 44 项全部通过，1.891 秒，自然退出 0：/tmp/aetherscreens-sync-checkpoint-conflict-tests.log；git diff --check 通过。
### 2026-10-08：账户本地生命周期协调器

- 新增 internal actor ComputerSyncCoordinator 串行化一个账户的激活、完整配置事务、远端日志合并及导出；以账户摘要独立目录，先恢复已有检查点，否则首次捕获，成功后才允许列表访问/编辑/导出。
- 存储异常将协调器退回未激活状态，要求显式重新激活恢复；坏文件不静默新建 peer 或继续使用偏好副本。目录创建请求 0700、提交文件 0600。
- 导出仅 ComputerSyncJournal 白名单元数据，不上传 local-only 检查点中的 lastConnected / 绑定 / scope 字段。actor 不启用登录或网络。
- 测试覆盖未激活访问拒绝、首次激活→编辑→导出→模拟偏好丢失后新协调器恢复→删除 tombstone；两个独立 Store/偏好账户目录不串列表；坏文件阻止激活但保留原文件和 Store 配置。日志 /tmp/aetherscreens-sync-coordinator-tests.log。
- 调用方仍需提供独立账户 Store/偏好，且将所有配置变更路由到协调器；目前 UI/Keychain 命名空间/登录/切换/云端未接入，不能把内部 actor 测试视为产品端到端同步。保留完整 Screens 目标。
- 最终协调器/检查点/同步存储/设备存储 47 项全部通过，1.871 秒，自然退出 0；git diff --check 通过。
### 2026-10-08：编辑快照版本防止覆盖同步更新

- 协调器提供 Sendable LibrarySnapshot（完整电脑列表和 UUID revision）；saveConfiguration 必须携带读取/开始编辑时的 revision。版本不同抛 libraryChanged，保留当前激活状态与配置，供 UI 重新读取，不自动替用户覆盖。
- 成功改变列表的本地提交/远端合并更新 revision，激活/恢复生成新 revision；相同列表提交及同步回声保持 revision，避免无变化同步打断编辑。
- 新增实际协调器/文件回归：读取编辑快照→合并远端重命名→旧快照保存拒绝→最新列表正确→导出回声合并不改变 revision→当前版本保存成功。协调器/检查点/同步存储/设备存储 48 项全部通过，1.872 秒：/tmp/aetherscreens-sync-editor-revision-tests.log。git diff --check 通过。
- 原始 iOS generic Simulator 构建正在运行，日志 /tmp/aetherscreens-sync-coordinator-ios-build.log。UI 尚未读取/提交协调器快照，冲突提示与草稿保留交互待接入；云端、登录与完整 Screens 目标未完成。
### 2026-10-08：异步账户选择的界面发布边界

- 原始 iOS generic Simulator 构建自然退出 0：/tmp/aetherscreens-sync-coordinator-ios-build.log，覆盖此前账户摘要、文件锁、协调器与版本快照。不是本轮新增 UI model 的单独 iOS 验收结论。
- 新增 internal MainActor ComputerSyncLibraryModel / Sendable session 协议，桥接协调器激活与保存。账户选择生成代次并清空旧快照，退出立即失效；旧激活/保存任务完成时只有当前代次能发布列表、错误、loading/saving 或成功结果。
- 编辑冲突返回 false 和 libraryChanged，保留当前快照；表单草稿由调用方持有，只有 true 才可关闭编辑页。模型不改共享 Store 或启用登录/云端。
- 确定性延迟 actor 回归：旧激活挂起→新账户完成→旧激活放行不覆盖新列表；退出→旧完成不重新显示；冲突保存不更新快照、清 saving 并返回失败。日志 /tmp/aetherscreens-sync-library-generation-tests.log。
- 这是未来账户/编辑 UI 的模型边界，尚未接到现有 DeviceListView 或表单，也没有渲染/真机证明。登录、账户切换凭据生命周期、云端以及完整 Screens 目标仍待完成。
- 最终该模型及存储相关 51 项测试全部通过，1.921 秒，自然退出 0；git diff --check 通过。
### 2026-10-08：CloudKit 私有快照只读接入代码

- 检查 ios/project.yml / 源码，目前没有 CloudKit 容器配置；未改生产 entitlement、容器或账户。新增 internal CloudKitComputerSyncReader，构造不请求，只有显式 fetch 才查询账户/私有数据库。
- fetch 读取前确认 accountStatus.available，取得 provider userRecordID，读取固定 computer-library-v1 后再次核对 userRecordID；变化时拒绝将返回内容交给旧账户。unknownItem 是空快照，其他错误保留，不制造空成功。
- 只接受固定 record type/ID、schema=1、字段恰好 schema/journal、≤512KiB、通过 ComputerSyncJournal 完整校验的数据，返回重新编码的白名单日志及 changeTag；本机检查点和额外秘密字段拒绝。
- 53 项 reader/界面模型/协调器/存储测试通过，1.920 秒：/tmp/aetherscreens-cloudkit-reader-tests.log，git diff --check 通过。reader 用实际 CKRecord 进行本地验证测试，未实例化真实容器或发云请求；不宣称云端读写成功。
- 官方 API 依据：developer.apple.com/documentation/cloudkit/ckdatabase/record(for:) 与 ckcontainer/userrecordid()；后续写者需采用 ifServerRecordUnchanged（官方 modifyRecords / RecordSavePolicy 文档）并处理账户变化，不能把只读核对直接扩展成上传账户绑定保证。
- 写端、容器登录/配置、真实多设备读写、UI 接入、订阅/重试仍未完成，完整 Screens 目标保留。
### 2026-10-08：CloudKit 替换记录与保存策略准备

- replacementRecord 仅从校验日志生成规范数据；已有 base 必须通过字段/ID/类型白名单，使用 CKRecord.copy 而非新建 ID 来准备更新，不修改 base。额外字段拒绝，不能把未知旧字段带入新快照。
- modification 构造但不 enqueue CKModifyRecordsOperation：仅一个完整日志记录，无 recordIDsToDelete，savePolicy.ifServerRecordUnchanged；base 更新要求非空且匹配 expectedChangeTag，新建请求要求无 expected tag。默认私有 zone 不请求跨记录 atomic batch，单记录版本检查仍保留。
- 实际 CKRecord/CKModifyRecordsOperation 本地回归验证独立副本、旧 payload 不变、规范日志、未知字段拒绝、保存策略/单记录/不删除、无版本 base 或错误新建版本拒绝。没有实际非空 server changeTag 的保存或 CloudKit 请求，不能将 nil tag 副本比较宣称为云端更新证明。
- 写者的账户变化/取消 gate、CloudKit completion/result 处理、真实冲突合并/重试、容器/UI/登录仍待接入。官方保存策略依据 developer.apple.com/documentation/cloudkit/ckmodifyrecordsoperation/recordsavepolicy 。完整 Screens 目标仍保留。
- 最终 CloudKit 记录及模型/存储相关 55 项测试通过，1.858 秒，自然退出 0：/tmp/aetherscreens-cloudkit-record-preparation-tests.log；git diff --check 通过。
### 2026-10-08：CloudKit 账户变化请求代次

- 新增 CloudKitAccountOperationGate，直接观察本机 SDK CKAccountChangedNotification；同步更新 UUID 代次并取消登记的 CKOperation，cancel 在锁外执行，避免 completion 回调重入。旧代次 register/finish 拒绝，完成操作移除，deinit 取消未完成操作并清理 observer。
- reader 在账户/数据库 await 之前捕获代次，结果核对 userRecordID 与代次，覆盖 A→B→A 通知情况下身份字符串再次相同的旧请求。开头/返回前检查 Task cancellation；未将无操作句柄的 record(for:) 请求宣称为已可立即网络取消。
- 自有 NotificationCenter + 实际未 enqueue CKModifyRecordsOperation 回归验证变化通知取消、旧注册取消、旧完成拒绝、新代次注册/完成、完成操作不再保留。未触碰真实 iCloud 账户或执行云端请求。
- 操作取消为 best effort，不能撤回服务器已接受写入；写者尚未执行/接入，真实账户切换与云端冲突验收保留。完整 Screens 目标仍未完成。
- 最终 CloudKit gate/记录及模型/存储相关 56 项测试全部通过，1.918 秒，自然退出 0：/tmp/aetherscreens-cloudkit-account-gate-tests.log；git diff --check 通过。
### 2026-10-08：CloudKit modify 操作异步桥接

- 新增 CloudKitModifyOperationRunner.run：安装账户 gate 与 modifyRecordsResultBlock 后才调用注入 enqueue，CheckedContinuation 一次终态桥接 CloudKit Result<Void,Error>。relay 处理取消先于 continuation 安装，以及迟到/重复 callback。
- gate 登记可选 invalidation 回调，账户通知即刻完成等待并 cancel，无需 SDK 再回调；任务取消先决定 CancellationError 再取消操作，避免同步取消回调抢终态。操作回调 weak operation，避免对象自持有循环；cancel/continuation resume 均在锁外执行。
- 受控回调测试使用实际 CKModifyRecordsOperation，但 enqueue 不发送网络：成功、serverRecordChanged 原样返回、预取消不 enqueue、排队取消后迟到成功不重复 resume、账户变化且 SDK 不回调也结束等待。
- 这是执行桥接，不包含保存结果逐记录/服务器 tag 校验、请求超时或真实 CloudKit writer 接入；取消不撤回服务端已接受数据。未改容器/权限或调用真实账户。完整 Screens 目标保留。
- 最终 runner/gate/记录及模型/存储相关 61 项测试全部通过，1.922 秒，自然退出 0：/tmp/aetherscreens-cloudkit-operation-runner-tests.log；git diff --check 通过。

### 2026-10-08：保存结果校验与显式上传入口

- runSaving 校验单记录条件保存请求，分别检查 perRecordSaveBlock 与整体结果；逐记录错误原样返回，缺失结果、未知记录、内容不匹配或缺少非空服务器 changeTag 均拒绝作为上传成功。
- 新增 save(journal:accountIdentifier:expectedChangeTag:)：显式调用才请求 CloudKit；读取当前账户与服务器 base，核对调用方账户/版本后交给账户 gate 和 runner enqueue，保存后再核对账户与取消状态。版本冲突不自动覆盖，需调用方合并后重试。取消不能撤回服务器已接受写入。
- 本地受控回归新增整体成功但缺少逐记录结果、逐记录冲突、返回记录无服务器版本三条失败路径。最终相关 64 项测试通过，1.766 秒，自然退出 0：/tmp/aetherscreens-cloudkit-writer-tests.log；git diff --check 通过。
- 测试不发送 CloudKit 网络请求，尚无真实非空 changeTag 保存成功、多设备冲突或账户切换验收；容器 entitlement、登录、UI、重试/订阅仍未接入。完整 Screens 对齐与真机流畅度目标未完成。
- iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-cloudkit-result-ios-build.log。仅编译验证，不是手机手感或真实云端验收。

### 2026-10-08：协调器条件同步与冲突合并

- ComputerSyncTransport 协议由 CloudKit reader/save 实现；协调器新增显式 synchronize，账户不匹配在合并前拒绝，先持久合并再导出上传。每次版本冲突重新 fetch/merge，最多三次；网络错误不伪装成功、不清空本地记录。并行同步请求拒绝，上传期间的本地编辑通过上传后重新导出比较发现并进入下一次尝试。
- 生成数据受控 transport 测试：第一次新建冲突后取得远端独立设备，再次上传包含双方设备且使用新版本；错误账户不合并、不上传且本地日志不变。相关 66 项测试通过，1.802 秒，自然退出 0：/tmp/aetherscreens-sync-conflict-loop-regression.log；git diff --check 通过。
- 这是核心流程，不是已接到应用 UI 的可用云同步；尚未验收真实 CloudKit 服务器、三次连续冲突、上传中编辑/账户切换或订阅。没有改 entitlement、启用登录或发布。
- iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-sync-conflict-loop-ios-build.log。全面 Screens 对齐及真机流畅度目标继续保留。

### 2026-10-08：上传等待期间编辑与连续冲突验证

- 新增受控 transport 的连续冲突回归，验证三次条件保存后 retryLimit，本地完整设备配置仍保留。
- 上传回调等待时通过真实协调器保存改名，验证第一次提交旧名称、第二次提交新名称，未将第一次成功当成全部本地配置已同步。该等待期间再发同步请求必须 synchronizationInProgress，避免相互穿插。
- 无网络、真实账户或秘密数据参与；此前 iOS 构建已确认通过。最终相关 68 项测试全部通过，1.823 秒，自然退出 0：/tmp/aetherscreens-sync-upload-edit-regression.log；git diff --check 通过。真实云端、同步 UI 接入与设备操作手感仍未完成验收。

### 2026-10-08：同步结果到列表模型的刷新

- ComputerSyncLibrarySession 增加显式 synchronize，模型增加 isSynchronizing / syncFailed 状态；同步成功读取协调器当前列表，上传失败也尝试读取已经持久合并的列表，避免仍显示旧配置。无自动云端激活。
- 切换/退出账户清同步状态；同步刷新、错误和结束状态受账户代次约束。旧同步失败晚于新账户加载时不能覆盖列表或错误。重叠模型同步请求直接返回 false。
- 受控 session 回归覆盖成功刷新、失败后持久更新刷新、旧账户挂起同步→新账户完成→旧同步失败、不重复启动。相关 21 项测试全部通过，0.090 秒，自然退出 0：/tmp/aetherscreens-sync-model-refresh-tests.log；git diff --check 通过。
- 此模型仍未接到现有 DeviceListView 或可操作同步设置页；不是已渲染 UI、真实云端或真机验收。该阶段 iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-sync-model-refresh-ios-build.log。

### 2026-10-08：同账户编辑与同步刷新乱序修复

- 同一账户的 save/synchronize 可以交错，账户代次不能区分两个快照请求。模型新增独立 refreshGeneration：较早请求捕获的快照挂起时，较新请求已发布后，旧请求返回不会覆盖新快照。保存/同步仍各自结束状态，不阻止合法的上传期间编辑。
- 确定性 actor 回归按同步旧快照捕获→编辑保存并显示新配置→释放旧快照的顺序验证，最终保持新配置且两个 busy 状态结束。相关 22 项测试全部通过，0.081 秒，自然退出 0：/tmp/aetherscreens-sync-model-publication-tests.log；git diff --check 通过。
- 新改动 iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-sync-model-publication-ios-build.log。完整对齐、现有列表/同步设置页接入、真实云端和真机流畅度仍待完成。

### 2026-10-08：设置页范围与云端配置检查

- 现有设置页包含语言、Tailscale、SSH 密钥与 Mac 连接说明，标题改为通用 Settings / 设置；更新已有中英文语言切换和主要页面 UI 断言，不改变功能或旧偏好。git diff --check 通过。
- 当前 ios/project.yml 没有 CloudKit entitlement/container。已请求用户提供 Apple Developer 中实际创建的容器 ID；未推测或创建生产容器。未将底层同步代码视为已可用的云同步界面。
- 设置标题 iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-settings-title-ios-build.log。
- 已核对专用模拟器 B2A70B86-CF9F-4B79-B813-C97E81273130 仍存在且原为 Shutdown，boot 自然退出 0；已有 testChineseEnglishSwitchAndPersistence 与 testPrimaryScreensOnIPhone 全部通过（38.167 秒 / 34.963 秒），xcodebuild 自然退出 0，TEST SUCCEEDED。独立 derived data / xcresult：build/settings-title-ui-derived-20261008、build/settings-title-ui-20261008.xcresult，日志 /tmp/aetherscreens-settings-title-ui-tests.log。
- xcresulttool 导出 8 张附件到 build/settings-title-ui-20261008-attachments；实际查看 English Settings After Switch 与 Add Computer：设置标题正确、语言切换后保持页、添加字段与条件密码显示正常。仅此次模拟器导航/显示回归，未触碰物理 iPhone，不作为真机流畅度或完整 Screens 对齐证据。git diff --check 通过。

### 2026-10-08：Tailscale 设置输入行为

- 核对新增/编辑电脑以及 SSH 地址/用户名已有 autocorrectionDisabled 与 iOS never capitalization。补齐 Tailscale token/tailnet 字段：关闭纠错/自动大写，token 使用 ASCII 键盘，tailnet 使用网址键盘，避免输入值被系统自动改写。不改变偏好存储或验证行为。
- git diff --check 通过。iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-settings-input-ios-build.log；尚无真机软件键盘输入验收，不用构建结果代替该结论。

### 2026-10-08：同步与界面模型后的完整核心回归

- 当前工作树 swift test 自然退出 0：346 项，8 项环境跳过，0 失败，91.506 秒。日志 /tmp/aetherscreens-full-core-sync-integration-20261008.log；git diff --check 通过。覆盖新增同步/CloudKit 受控操作/列表模型以及原连接、输入、解码、存储回归。
- 跳过项目为 LAN Bonjour 1、真实 Mac 剪贴板 2、真实登录失败重试/指针 2、系统 Keychain 1、Tailscale 真实握手 2。没有将跳过计作验收；不代表实际 iCloud、多设备、真机动画/帧率或完整 Screens 对齐通过。
- 本轮没有发布、推送或触碰物理设备；真实云同步容器 ID、UI 接入、剩余功能差距和真机验收仍待完成。

### 2026-10-08：隐私模式差距与锁屏提示观察

- 最新官方依据 https://help.edovia.com/en-GB/screens-5/features/curtain-mode ：Curtain 隐藏远端物理显示但客户端继续控制，需要 Remote Management，普通 Screen Sharing 不支持。当前源码仅 RFB 003.008 与锁屏快捷键，没有确认 Curtain 协议或服务器状态，不宣称对齐。
- RemoteDesktopView 此前通过 SessionViewModel 读取嵌套 CurtainModeManager，却没有直接观察通知，提示可依赖其他会话/帧更新才重绘。新增独立 ObservedObject lockNotice，横幅/菜单均读取它，显示与关闭随通知更新。仍是快捷键提示，不是远端隐私状态。
- 既有 notice/指针实际传输相关 23 项测试通过，42.034 秒，自然退出 0：/tmp/aetherscreens-lock-notice-core-tests.log。iOS generic Simulator 构建自然退出 0，BUILD SUCCEEDED：/tmp/aetherscreens-lock-notice-ios-build.log；git diff --check 通过。尚未做静止画面下提示重绘 UI 验收，也未验收实际 Remote Management Curtain。

### 2026-10-08：静止画面锁屏提示的受控 UI 场景

- 新增 testControlledStaticLockNotice / testChineseControlledStaticLockNotice，并加入受控 QA runner。临时连接生成数据服务，第一帧后打开锁屏提示→关闭提示，校验提示消失、收到完整 Ctrl+Command+Q 键序列、期间 frame 数量不增加，避免依赖新画面通过。
- 旧 8791 服务未响应，确认 6041/6042/8801 无监听后启动新的自有 gesture_rfb_fixture；仅 loopback 模拟服务，不连接真实 Mac。使用现有专用模拟器与既有 derived data，新输出 build/static-lock-notice-ui-20261008，runner 日志 /tmp/aetherscreens-static-lock-notice-ui.log。
- runner 自然退出 0：两项均执行、无跳过/失败/runtime warning；中文 26.796 秒、英文 27.535 秒，日志 /tmp/aetherscreens-static-lock-notice-ui.log。断言验证完整快捷键与 frame 数不增加，提示显示和关闭不依赖后续画面。
- 导出 4 张附件到 build/static-lock-notice-ui-20261008/attachments；实际查看中文提示和英文关闭后截图，提示出现/消失、静态网格与箭头指针正常。git diff --check 通过；这是受控 UI 证据，完整 Curtain、真实云同步和真机流畅度目标仍保留。

### 2026-10-08：锁屏提示触控与过渡

- 提示内关闭/重连按钮扩展至至少 44 点宽高，文字允许垂直扩展以适应较窄页面。提示采用 0.18 秒 opacity 过渡，Reduce Motion 时无动画；状态变化仅用于提示交互，不改远端输入或画面处理。
- git diff --check 通过；同一受控静止画面中英文场景均通过，无跳过/失败/runtime warnings，runner 自然退出 0。中文 26.346 秒、英文 25.144 秒，输出 build/lock-notice-touch-ui-20261008，日志 /tmp/aetherscreens-lock-notice-touch-ui.log。
- 导出 4 张截图并实际查看中英文提示，新按钮完整显示、未遮挡顶栏，静态画面下显示/关闭与快捷键断言继续通过。未单独跑 Reduce Motion 设置、窄屏/大字体矩阵或真实帧率测试，不作为真机动画或完整目标验收证据。

### 2026-10-08：指定真实 Mac mini 可达性

- 对用户指定 192.168.50.226 的 TCP 5900 / 22 进行独立 nc -vz -G 3 检查，两者均 Operation timed out，自然退出 1；route get 显示需要网关路径。没有发认证、操作远端桌面或修改远端设置。
- 真实 Apple 服务器验收当前受网络可达性阻塞，已询问当前局域网/Tailscale 地址。不是代码或受控 fixture 失败，也不能将此前受控通过作为真实服务器通过。完整目标保持，真实设备与云端配置等待用户提供。

### 2026-10-08：CloudKit 保存操作的 SDK 超时配置

- 条件保存工厂设置 CKOperation.Configuration 请求 20 秒、资源 60 秒，使用现行 API，不改变账户 gate、保存策略或冲突重试。官方依据 https://developer.apple.com/documentation/cloudkit/ckoperation/configuration-swift.class/timeoutintervalforresource 与 timeoutintervalforrequest，且已核对本机 SDK 声明。
- 相关 16 项现有记录/runner/冲突回归通过，0.041 秒，自然退出 0：/tmp/aetherscreens-cloudkit-timeout-policy-tests.log；git diff --check 通过。没有真实网络超时测试，不宣称整个同步流程 60 秒终止；accountStatus/userRecordID/record(for:) 与每次重试仍是独立等待。
- 同步对齐总表更新为目前已实现的本地持久化、协调器、CloudKit 条件读写代码和 UI 模型，继续明确容器/登录/UI 实际接入、真实多设备与凭据策略缺口。完整目标未完成。

### 2026-10-08：系统 Reduce Motion 受控验证尝试

- 新增显式 simulator-only testControlledReducedMotionLockNotice：在系统设置记录 Reduce Motion 原值，开启后运行静态提示场景，defer 恢复原值。runner 将其置于可显式选择项目，不加入物理默认矩阵，并拒绝物理设备选择。
- 首次运行失败于 Settings 的 Accessibility Cell 定位，尚未找到/切换 Reduce Motion，不作为动画或系统设置验证通过。测试日志 build/lock-notice-reduced-motion-ui-20261008/tests.log，runner 日志 /tmp/aetherscreens-lock-notice-reduced-motion-ui.log。测试本体已失败，但 runner/xcodebuild 收尾仍运行，后续继续核对同一进程与附件，不重复启动。
- 下一步需取得实际系统设置页面/层级证据，修正入口查询后重跑；此前普通中英文提示回归保持通过，但不覆盖此新场景。git diff --check 通过。
- 后续 simctl io 对专用模拟器截屏 /tmp/aetherscreens-reduce-motion-current.png，实际查看确认系统设置为中文，解释只查询英文 Accessibility 的失败。已将 Accessibility/Motion/Reduce Motion 定位改为中英文标签匹配，增加入口截图；失败发生在开关操作前，无系统开关变更。原 xcodebuild 仍在收尾，修正尚未重跑，等待同一 handle 终态后再执行。
- 对仍存活 xcodebuild PID 27095 进行 1 秒 sample，/tmp/aetherscreens-reduce-motion-xcode-sample.txt 显示 XCTHRunDestinationAllocator.collectSimulatorDiagnostics / simCtlDiagnose 等待，确认长收尾在诊断收集，不把观测超时当停止。QA runner ast.parse 通过。新场景设置 continueAfterFailure=false，定位断言失败时避免再尝试点击不存在入口；待原任务自然终止后重跑。
- 原 xcodebuild 与 runner 最终自然终止，runner 退出 1、明确 Controlled QA incomplete，失败证据保留。诊断只读子进程仍在后台，但原测试不再操作模拟器；已用新的 build/lock-notice-reduced-motion-ui-20261008-2 与 /tmp/aetherscreens-lock-notice-reduced-motion-ui-2.log 启动修正后的显式单项测试，结果待确认。
- 第二次测试本体再次失败于 Accessibility 定位（26.058 秒），仍未操作开关；simctl 当前截图 /tmp/aetherscreens-reduce-motion-retry-current.png 显示中文设置页。将查询从 StaticText 扩展为任意元素的中英文标签匹配，并增加 Settings debugDescription 持久附件；尚未获得层级或验证此修正。当前 runner 34978 仍在收尾，不重启测试或宣称通过。

### 2026-10-08：当前同步与界面代码的 Release 完整核心回归

- swift test -c release 自然退出 0：346 项，8 项环境跳过，0 失败，75.764 秒，日志 /tmp/aetherscreens-full-release-sync-integration-20261008.log。此次覆盖新同步/CloudKit/模型及原连接、输入、解码、存储，非旧版本结果。
- 跳过的真实环境项目保持未验收；现有 deprecation、测试 Sendable 捕获及未修改变量警告仍在，不把编译或绿色核心结果视为真实云端、系统 Reduce Motion UI、真机帧率或完整 Screens 对齐证据。git diff --check 通过。

### 2026-10-08：系统设置元素只读检查场景

- 第二次失败的诊断收尾仍存活（xcodebuild 39702、diagnose 42350）。准备显式 simulator-only testControlledSystemSettingsInventory，保存设置页顶部及后续两页的 debugDescription/截图，再依真实元素标签、类型修正入口；不操作任何系统开关，不加入默认验收矩阵。
- QA runner 可显式选择此检查，并拒绝物理设备选择；检查成功仅代表取证成功，不能代替 Reduce Motion 或产品验收。当前尚未执行/编译此新场景，等待原测试收尾后运行。git diff --check 通过。
- 第二次原 xcodebuild/runner 最终自然退出，runner 退出 1、Controlled QA incomplete；诊断只读子进程仍在后台。已启动独立取证，输出 build/system-settings-inventory-ui-20261008，日志 /tmp/aetherscreens-system-settings-inventory-ui.log，终态与层级待确认；不改变开关。
- 首次只读取证自然退出 0、单项执行无跳过/失败/runtime warning，18.432 秒。导出三组截图/层级；实际查看顶部截图与 14CB591A-9983-4F43-96F9-115DCBA941BD.txt，系统入口为 Button、label 无障碍、identifier com.apple.settings.accessibility（此前辅助功能标签过时）。按实测标识修正入口。
- 继续启动只读第二层取证，build/system-settings-inventory-ui-20261008-2、/tmp/aetherscreens-system-settings-inventory-ui-2.log；导航到已确认入口并保存下一层，仍不操作开关。当前待终态，不把取证通过当 Reduce Motion 验收。
- 第二层取证自然退出 0，25.949 秒，无跳过/失败/runtime warning。导出层级 DE7B9127-41F2-4EF6-89A1-C9F32D01ECFF.txt 确认动态效果 Cell/Button identifier MOTION_TITLE；测试改用实测标识，并允许设置 App 已停留在无障碍页面时直接进入动态效果。
- 启动第三层只读取证，build/system-settings-inventory-ui-20261008-3、/tmp/aetherscreens-system-settings-inventory-ui-3.log，确认实际 Reduce Motion 开关标识后再操作。当前终态待确认，仍无开关变更或产品验收结论。

### 2026-10-08：Reduce Motion 实际系统开关回归通过

- 第三层只读取证自然退出 0，确认实际 Switch identifier REDUCE_MOTION；实际查看动态效果截图。按已取证标识修正显式测试，整理导航缩进。
- build/lock-notice-reduced-motion-ui-20261008-3 自然退出 0：单项执行、无跳过/失败/runtime warnings，51.900 秒，日志 /tmp/aetherscreens-lock-notice-reduced-motion-ui-3.log。系统开关开启后运行静态锁屏提示显示/关闭与完整快捷键断言，最后恢复原值并断言恢复成功。
- 导出五个附件，实际查看系统开关已开启与产品提示截图，按钮完整显示且箭头可见。这验证开启系统选项时行为正确，不证明动画帧率或真实 Curtain、真机流畅度；完整目标保留。
- 继续启动六项中英文缩放边缘跟随、轮播工具栏、旋转和连续按键回归，输出 build/interaction-motion-regression-20261008，日志 /tmp/aetherscreens-interaction-motion-regression.log，结果待确认；没有启动物理设备或真实 Mac 连接。

### 2026-10-08：锁屏提示字号与宽度自适应（验证中）

- 固定 11/12 点字号改为语义 caption/caption2，跟随系统动态字体。ViewThatFits 优先横向布局，空间不足时采用文字和操作分行布局；保留 44 点最小按钮与 Reduce Motion 分支，外侧留出 12 点边距，背景改为可容纳多行的圆角矩形。
- 现有静态提示受控测试增加提示/两按钮的可点击性及水平窗口边界断言；未新增生产依赖。swift build 自然退出 0，日志 /tmp/aetherscreens-adaptive-lock-notice-build.log；git diff --check 通过。
- 此改动在此前六项 test-without-building 已启动后实施，六项结果属于已编译的前一版交互。新布局尚未取得 iOS、大字体或系统 Reduce Motion UI 证明，待当前运行结束后独立编译验证。
- 六项交互回归自然退出 0，419.069 秒，6/6 执行、0 失败/跳过/runtime warning：中英文轮播工具栏、中英文缩放边缘跟随、旋转、连续按键。导出附件并实际查看横屏工具栏及左右边缘画面；右边缘箭头大部分在窗口外，仅余边缘可见，不能由此宣称边界箭头完整显示；不改视觉热点以伪造远端位置。
- 启动新布局独立三项默认中英文/系统 Reduce Motion 回归，build/adaptive-lock-notice-ui-20261008，日志 /tmp/aetherscreens-adaptive-lock-notice-ui.log，结果待确认。
- 新布局原设备三项测试：普通中文 27.495 秒/英文 25.790 秒通过；Reduce Motion 产品显示/关闭/按键与按钮边界检查执行后，恢复系统原值断言失败（读到 1 而非原始 0，48.130 秒）。不宣称三项全绿。xcodebuild 9665 正在 simctl diagnose 600 秒只读收尾，保持原进程、不取消。
- simctl spawn defaults read com.apple.Accessibility ReduceMotionEnabled 确认持久值 1；仅对自有 QA 模拟器写回已记录原值 false，再读为 0。此持久值读取不代替下一次框架/UI 状态核对。恢复函数改为等待 value 到达目标 5 秒、最多两次已确认值不同的点击，并保留恢复后截图。
- 为覆盖 375 点窄屏且不与旧测试的诊断收尾争用设备，创建新的自有 iPhone SE 第三代模拟器 C3F6C4B6-6643-4379-AC36-D03E541446F2（iOS 27），CLI boot，不打开宿主 Simulator GUI。独立 derived build/accessibility-se-ui-derived-20261008，三项默认字体/Reduce Motion 验证输出 build/adaptive-lock-notice-se-ui-20261008，日志 /tmp/aetherscreens-adaptive-lock-notice-se-ui.log，待结果；不重建已删除 Tart VM。
- 原设备三项 runner 最终自然退出 1，失败证据和截图完整保留；实际查看失败系统开关与普通中文新布局截图。小屏独立三项自然退出 0，110.010 秒：中文 29.162、Reduce Motion 55.476、英文 25.372，0 跳过/失败/runtime warning；恢复原值断言成功，导出附件并实际查看恢复后的系统开关与中文提示。
- 启动小屏最大辅助字号 accessibility-extra-extra-extra-large 中英文验证，build/adaptive-lock-notice-se-large-ui-20261008，日志 /tmp/aetherscreens-adaptive-lock-notice-se-large-ui.log；外围 finally 恢复已读取原字号并核对，当前结果待确认。原设备单独只读 Settings 层级检查确认之前 CLI 恢复值，build/reduced-motion-restoration-inventory-20261008，不发送远端输入，不与小屏共享操作目标。
- 根据本机 xcodebuild -help 支持的 -collect-test-diagnostics on-failure|never，仅受控 simulator 的后续运行设置 never，避免失败后长 sysdiagnose 收尾；仍保留 xcresult、失败/截图/日志与严格结果核对，真实设备继续默认诊断。runner ast.parse 和 git diff --check 通过；新参数实际运行待确认。
- 原设备只读检查自然退出 0，27.406 秒，无失败/跳过/runtime warning；附件 D985C07B-3301-4450-8FB8-62EDA181BDA7.txt 的 REDUCE_MOTION Switch value 0，确认界面层恢复已生效。新 -collect-test-diagnostics never 参数实际运行成功。
- 最大辅助字号首轮两项均失败，finally 已恢复 large，不作为通过：中文菜单锁屏项未滚入可见列表；英语端口区域被主机键盘遮挡，无法取得键盘焦点。没有执行到提示边界断言。失败后 runner 迅速自然退出 1，没有 sysdiagnose 长收尾；保留视频、层级、Issue Description、UI Snapshot（此轮没有独立 PNG failure screenshot，不混同自动截图格式）。
- 实际从受控失败视频提取并查看末帧：中文系统菜单呈大字号滚动列表；英语表单的主机仍聚焦、端口数值在键盘下。新增/编辑表单主机输入配置 FocusState + Done submit，提交明确清除主机焦点；测试使用真实返回键确认收起主机键盘，菜单按可见滚动路径找到锁屏项，先保留菜单截图。未缩小系统菜单字号或跳过功能。
- 重跑最大辅助字号中英文，build/adaptive-lock-notice-se-large-ui-20261008-2，日志 /tmp/aetherscreens-adaptive-lock-notice-se-large-ui-2.log；保持外围字号恢复/核对，当前待结果。swift build /tmp/aetherscreens-host-submit-build.log 当前待终态，git diff --check 通过。
- 主机 Done 提交改动 swift build 自然退出 0，7.30 秒，/tmp/aetherscreens-host-submit-build.log。最大辅助字号修正轮自然退出 0：中文 35.013 秒、英文 33.615 秒，总计 68.628 秒，两项实际执行、无失败/跳过/runtime warning。finally 恢复字号 large 并读回核对；导出六张附件，实际查看中英文大字体提示，文字/两个按钮完整位于 375 点窗口，分行布局生效。
- 新主机 Done 提交/菜单滚动后，启动最后默认字号中英文 + 系统 Reduce Motion 回归，build/adaptive-lock-notice-se-final-ui-20261008，日志 /tmp/aetherscreens-adaptive-lock-notice-se-final-ui.log，结果待确认。这不是重新重复旧版本全套，而是核对本轮最后表单/测试路径改动的默认字号与无动画分支。
- 大字体断言绿后实际截图仍显示英语按钮单词被拆行（Dismiss / Reconnect），因此继续视觉修正，不将前一版截图的边界通过混同为满意的排版。操作区域增加自身 ViewThatFits：优先自然宽度横排，放不下时按钮纵排，按钮文字保持完整单行；装饰图标固定 18 点并隐藏重复无障碍图标信息，为提示文字保留宽度。swift build 自然退出 0，4.20 秒，/tmp/aetherscreens-adaptive-notice-actions-build.log。
- 当前 SE 默认三项已编译前一版操作布局，保留其验证主机 Done 流程的价值，等待自然收尾。为验证最新按钮布局，确认 6043/6044/8802 可绑定后启动第二个自有 loopback fixture（/tmp/aetherscreens-accessibility-final-fixture.log），原设备独立默认中英文/Reduce Motion 三项输出 build/adaptive-lock-notice-final-motion-ui-20261008，日志 /tmp/aetherscreens-adaptive-lock-notice-final-motion-ui.log。
- 两套 fixture、设备、derived data 和结果路径独立；避免两组真实输入/帧计数污染。最新布局的小屏最大字号验证待 SE 当前运行终态后开始，没有声明整体 Screens 功能或真机流畅度验收完成。
- 最终操作布局原设备默认字号中英文 + Reduce Motion 3/3 自然退出 0，129.311 秒，无失败/跳过/runtime warning，日志 /tmp/aetherscreens-adaptive-lock-notice-final-motion-ui.log；导出并实际查看恢复后系统开关为关闭。
- 最终操作布局 375 点小屏最大辅助字号中英文 2/2 自然退出 0，日志 /tmp/aetherscreens-adaptive-notice-actions-se-large-ui.log；finally 恢复字号 large 并核对。导出并实际查看两个提示截图：装饰图标不挤占阅读空间，Dismiss / Reconnect 以及中文操作均完整单行纵排，无前一版单词拆行；提示文字完整，窗口边界和点击断言通过。
- git diff --check 通过；本轮没有提交/推送/发布或操作物理 iPhone。仅停止本轮新建的第二个 loopback fixture，关闭本轮创建的 SE 模拟器，保留测试结果/模拟器数据以便复验；原 fixture 与原模拟器保留用于持续目标。
- 完整目标仍未完成：真实 Curtain、文件拖放、云容器/登录/现有列表的同步接入、真实 Apple 剪贴板兼容及真机延迟/FPS 等缺口保持；不能以此 UI 场景通过宣称全面 Screens 对齐。

### 2026-10-08：静止画面下的性能指标窗口

- 上一目标轮是实际进展：新提示布局、主机 Done 输入及受控 UI 验证已落地。本轮保持全量 Screens 目标，检查尚未完成的画质与流畅度能力。
- 新核对官方 https://help.edovia.com/en/screens-5/features/images-quality/：Screens 的 Mac Adaptive Quality 为渐进细化，Compression 请求服务端 50% 尺寸；现有颜色深度开关不等价于这两者。没有添加虚假的自适应/缩放开关，也未将本文作为协议实现证明。
- PerformanceMetrics 原先仅在下一次帧/字节到来时结算，短暂传输结束后会保留旧速率。新增 sampleRates 完成满一秒窗口，即使没有新数据也结算；HUD 使用显示期间的每秒 TimelineView 驱动。静止画面合法为零，不把它当网络变差。相同值不重复发布；计数锁在 observable 发布前释放，保留重入安全。
- 初始 10 项指标测试通过，但新的同会话发布顺序测试采用 DispatchQueue.sync 时未真正产生待发布后台结果，第一次探针通过不作为此并发路径证明。改为 async 工作队列 + 有界 semaphore 完成核对，再等待主队列排空；复现过期结果将零改回 FPS 1、吞吐 8（/tmp/aetherscreens-idle-metrics-order-probe-2.log，自然退出 1）。
- 帧率/接收流量分别增加窗口版本，过期同会话发布被拒绝，保持各自窗口独立；会话 generation/reset 保护仍保留。相关旧的 queued-publication/reset 测试也改为实际 async 后台队列，不依赖 sync 的调用线程执行优化。
- 最新 PerformanceMetricsTests 11 项全部通过、0.003 秒，自然退出 0，/tmp/aetherscreens-idle-metrics-final-tests.log。最新 iOS generic Simulator 构建自然退出 0、BUILD SUCCEEDED，/tmp/aetherscreens-idle-metrics-final-ios-build.log；git diff --check 通过。HUD 展开采用 0.28 秒阻尼 spring，Reduce Motion 时不动画。
- 当前完整核心 swift test 日志 /tmp/aetherscreens-idle-metrics-full-core-tests.log，尚待自然终态。HUD 当前仅在 macOS 会话顶栏显示，本轮未做真实 Mac/原生窗口渲染验收；没有真机 FPS、端到端输入延迟或网络自适应/服务端缩放通过证据。

- 本轮完整 Debug 核心回归自然退出 0：350 项、8 项明确环境跳过、0 失败，92.565 秒，/tmp/aetherscreens-idle-metrics-full-core-tests.log。HUD 日程使用稳定 State Date 起点，避免普通视图刷新重建起始时间；最终 macOS swift build 自然退出 0、4.17 秒，/tmp/aetherscreens-idle-hud-final-build.log；最终 iOS generic Simulator BUILD SUCCEEDED，自然退出 0，/tmp/aetherscreens-idle-hud-final-ios-build.log。
- 最新独立 nc -vz -G 3 对指定 Mac mini 5900/22 均 Operation timed out、自然退出 1，没有发认证或改远端设置；真实服务器/窗口/物理流畅度仍未验收。顶部新增当前 checkpoint，明确下文旧计数和待确认条目为历史证据。git diff --check 通过；完整目标继续保持。

## SSH private-key export (2026-10-08)

Added explicit bilingual confirmation and native FileDocument export from the
key library. The selected vault entry is read only after confirmation and its
fingerprint is checked again. Completion/cancellation releases the export
document state; this is not a memory-zeroization guarantee. Exported bytes are
the original unencrypted key, with local FileWrapper permissions set to 0600.
Cloud/file-provider permission semantics are not assumed.

Four new model/document regressions verify unchanged original data and
persistence, changed/missing/denied keys, invalid material, size limits and local
file permissions. SSHSettingsTests: 16/16 passed. Full core: 354 tests, 8
environment skips, zero failures. macOS and generic iOS builds succeeded:
`/tmp/aetherscreens-ssh-export-final-mac-build.log`,
`/tmp/aetherscreens-ssh-export-final-ios-build.log`.

First native UI run failed because iOS 27 confirmation popovers omit the Cancel
button and expose PopoverDismissRegion instead. The screenshot and accessibility
hierarchy confirmed this; the test now uses the observed dismiss region when
Cancel is absent. A second run confirmed the native document picker opens, but iOS 27 exposes
its Cancel control as accessibility type Other, not Button. The test now uses
the observed control type. The third run showed this system Cancel element is
hidden/non-hittable, and the subsequent rename did not open (so an existence
check alone was insufficient). The test now drags the visible native sheet edge
to dismiss when Cancel is non-hittable. Final English/Chinese rerun passed
2/2, zero failures (150.453 s):
`build/ssh-export-sheet-dismiss-ui-20261008/`. Confirmation screenshots reviewed. The final English picker attachment was
captured during its blank loading transition, so it does not establish settled
picker visual quality. Earlier failure screenshots show the settled system
picker; a settled screenshot gate is still required with save/re-import. The flow verifies dismissal, subsequent rename, persistence across
relaunch and removal of only the generated QA key; existing keys are retained. At that checkpoint actual native save/re-import and physical acceptance
remained required. The subsequent phone-Simulator round-trip gate below now
verifies save/re-import; full cross-platform/physical export parity is still open.

## Native SSH export save/re-import gate (2026-10-08, verified phone Simulator)

Added two controlled QA-only English/Chinese cases that save a uniquely named
generated key via the system document picker, relaunch with an internal exact
byte comparison against the generated vault entry, then re-import via Files and
compare the exact selected fingerprint. Fingerprint labels now expose stable
per-key accessibility identities. No secret is printed or transferred to the
test process. Disposable QA-only file-sharing configuration enables Files
access; production entitlements/Info.plist are unchanged.

Cleanup uses the owned seed file if the original generated key was already
deleted by the test, allowing matching generated re-imports to be removed.
Only token-specific QA export files are removed. Existing keys are retained.

The initial Chinese save and internal byte verification succeeded; the test
failed in subsequent Files navigation because the picker retained Documents
instead of starting at Locations. The test now checks the exact exported file
in the current directory before using the Locations fallback. The initial
English case subsequently failed at the same navigation step; the final
round-trip result below supersedes this intermediate checkpoint.
macOS and generic iOS builds after the accessibility identity change succeeded:
`/tmp/aetherscreens-ssh-export-roundtrip-mac-build.log`,
`/tmp/aetherscreens-ssh-export-roundtrip-ios-build.log`.

Round-trip UI follow-up: both languages saved and passed internal byte
verification. Files can initially show Recents, then retain the saved directory
after Browse; both transitions are handled. The second run selected the correct
exported file but queried the library during the dismissal animation (failure
screenshot confirmed the partial sheet). Added a condition-based wait for one
new identity before comparing fingerprints. Final settled rerun passed 2/2, zero failures (200.194 s):
`build/ssh-export-save-roundtrip-settled-ui-20261008/`. Save/re-import
screenshots reviewed; exact bytes and selected fingerprints matched. Both
owned seed/export-file sets are absent and the cleanup journal is empty; see
`ssh-export-file-cleanup.json` and `ssh-key-cleanup.json`. The file cleanup
check is also integrated into the runner for subsequent export-save cases.
Native file-provider behavior on actual devices, Mac/iPad export UI and physical
iPhone acceptance remain unverified. Latest three-second Mac mini port 5900
and 22 probes both timed out again; no authentication/configuration changes.

## SSH remaining capability audit and draft file gate (2026-10-08)

Authoritative Package.resolved pins apple/swift-nio-ssh 0.15.0 at
3ec281496f28a3b6581afd946b759e2642f5cd8d. Its NIOSSHPrivateKey public
initializers/backing enum support Ed25519 and NIST ECDSA; there is no RSA
private-key API. Fresh upstream API check confirms RSA PR 219 is open and
unmerged: https://github.com/apple/swift-nio-ssh/pull/219 . Parsing an RSA key
alone therefore cannot deliver RSA authentication with this backend. RSA
remains required; no production dependency/fork substitution was made.

Added controlled English/Chinese actual file selection/import gates in the
temporary Quick Connect SSH draft, complementing earlier picker-open/cancel
coverage. The QA fixture owns the generated seed, Files document and cleanup.
Checks require fingerprint display, enabled Connect and continued authentication
method switching. This does not claim real server authentication or physical
acceptance. The initial run and follow-up evidence are recorded below:
`build/ssh-draft-file-import-ui-20261008/`.

Initial draft-file run: English actual selection/import passed (138.944 s),
with fingerprint, enabled Connect and authentication-method switching;
its screenshot was reviewed. Chinese failed before import, on a repeated
computer-card long press in the existing full settings workflow (51.992 s).
XCTest reported Button/PopUpButton AX type mismatch and a {-1,-1} hit point;
root cause is not established. This is retained regression debt, not a passed
editor gate. The new file-specific cases now go directly to Quick Connect;
existing full settings cases retain their edit/save/reload checks. Final
direct bilingual run passed 2/2, zero failures (122.262 s):
`build/ssh-draft-file-import-direct-ui-20261008/`. Fingerprints appear, Connect
is enabled, and switching authentication still works. Cleanup journal is empty;
manual token-specific file check confirms two generated source files absent
(`ssh-key-file-cleanup.json`). Screenshots reviewed: Chinese is readable;
English shows partially clipped label prefixes during capture and does not
prove settled visual quality. A modal-dismissal/hittability capture gate and
repeat-editor locator audit remain required. No physical/server authentication
or full editor/visual acceptance is claimed.

## Draft import settled capture and repeated editing follow-up (2026-10-08)

Added condition-based waits for the import button and fingerprint to become
hittable after native file-picker dismissal. Both languages passed 2/2 with
zero failures (111.204 s), `build/ssh-draft-file-interactive-ui-20261008/`.
The new English screenshot has complete label prefixes, establishing that
the earlier clipped capture was an intermediate transition frame. No
production-layout workaround was introduced.

The full settings regression now long-presses the observed, fully visible card
center using its containing window, avoiding XCTest's inconsistent legacy
Button/modern PopUpButton hit-point resolution. The menu must appear before
Edit is tapped. Actual edit/save/reload/disable checks remain intact.
Bilingual full settings regression passed 2/2, zero failures (206.138 s):
`build/ssh-settings-repeat-edit-ui-20261008/`. Both languages actually
edit/save/reopen, recover the username/port/SSH enabled state, disable and
reopen with fields absent, then retain temporary Quick Connect behavior.
Reloaded settings screenshots reviewed. This resolves the observed owned-phone
XCTest locator failure; it is not a product layout patch or physical acceptance.

Owned native draft-file source cleanup verified after the settled capture gate:
two generated seed files absent and the key journal empty, recorded in
`build/ssh-draft-file-interactive-ui-20261008/ssh-key-file-cleanup.json`.
No production dependency, commit, push or release was introduced.

## Bounded CloudKit account callback waits (2026-10-08)

Current inspection confirms ComputerSyncLibraryModel is not wired into the
settings or DeviceListView, and no CloudKit container entitlement is configured.
The full cloud feature remains incomplete; no container/account/secret policy
was inferred or enabled.

Added CloudKitAccountRequestRunner and integrated both container account status
and user-record-ID checks in the real reader. Each callback wait has a 20-second
default deadline, consistent with the existing request timeout policy.
Cancellation resumes the caller without waiting for the SDK reply. A locked
first-terminal relay accepts synchronous completion, ignores duplicate/late
callbacks and supports cancellation before continuation installation. The SDK
container convenience callbacks expose no cancellation handle: this bounds
caller waiting, not termination of the underlying SDK request. Record fetches,
modify operations and conflict retries remain distinct phases, so there is no
claimed total synchronization deadline.

Primary API references (also verified in the installed SDK's CKContainer.h):
https://developer.apple.com/documentation/cloudkit/ckcontainer/accountstatus(completionhandler:)
https://developer.apple.com/documentation/cloudkit/ckcontainer/fetchuserrecordid(completionhandler:)

Six initial new request-relay tests passed (0.058 s); the existing plus new
CloudKit-targeted set passed 19/19 (0.064 s). A seventh case now checks unchanged
provider authentication-error propagation; final full core regression is running:
`/tmp/aetherscreens-cloud-account-timeout-full-core.log`. macOS/iOS builds
succeeded: `/tmp/aetherscreens-cloud-account-timeout-build.log`,
`/tmp/aetherscreens-cloud-account-timeout-ios-build.log`. No real CloudKit
account/network timeout or native cloud-settings acceptance was performed.

Final callback-wait verification: all seven new cases passed within the full
core run. Full core: 361 tests, 8 environment skips, zero failures;
`/tmp/aetherscreens-cloud-account-timeout-full-core.log`. The macOS build and
iOS generic Simulator build are terminal success. `git diff --check` passed.
No native cloud UI, real container/account, provider network timeout, account
login or secret-policy acceptance is claimed. Full Screens alignment remains
active; no commit/push/release.


## 2026-10-08: bounded encrypted ECDSA PKCS#8 import and native gates

Added a system-CommonCrypto PBES2/PBKDF2 + AES-CBC envelope decoder without a
new production package. Supports P-256/P-384/P-521, AES-128/192/256-CBC and HMAC
SHA-1/256/384/512. Strict DER/size/KDF bounds reject malformed/truncated/trailing
input and profiles above 2,000,000 iterations. This is encrypted ECDSA PKCS#8
support, not encrypted OpenSSH/bcrypt, PBES1/scrypt or RSA support.

The per-import native SecureField sheet serves draft and standalone library
imports. A detached derivation keeps CPU work off the UI executor; cancellation
checks and sheet lifetime guard reject late results. CommonCrypto's synchronous
call itself is not interruptible. The passphrase is not saved. Successfully
unlocked validated PEM enters the existing local Keychain/session path; later
export is explicitly unencrypted normalized material, not the original encrypted
source envelope. Owned work arrays are cleared; Swift String/Data copies are not
claimed to be guaranteed zeroized.

Validation:
- OpenSSL 3 independently generated 36 curve/cipher/PRF combinations; all
  decoded to the expected public key, wrong passphrases rejected. Truncation,
  trailing data, oversized files and over-budget derivation were rejected.
- A decrypted OpenSSL PKCS#8 P-384 key passed actual NIOSSH authentication and
  forwarded 4096 bytes to the owned loopback echo server.
- Complete core suite: 364 tests, 8 explicit environment skips, zero failures,
  95.652 seconds; `/tmp/aetherscreens-pkcs8-full-core.log`.
- macOS build and generic iOS Simulator build passed;
  `/tmp/aetherscreens-pkcs8-final-mac-build.log` and
  `/tmp/aetherscreens-pkcs8-ios-build.log`.
- First native bilingual draft run exposed a competing modal lifetime: the
  passphrase sheet appeared and vanished when the file picker closed. Moved
  its presenter to the import control and added interactive-field waits.
  The subsequent run reached the error prompt, exposing an ambiguous nested
  Cancel locator and retained Files directory state. Added a specific cancel
  identifier and retained-directory-aware document selection.
  Initial failure evidence: `build/ssh-encrypted-pkcs8-draft-ui-20261008/` and
  `build/ssh-encrypted-pkcs8-child-sheet-ui-20261008/`.
- Final native phone Simulator gate: four requested English/Chinese draft and
  library cases passed, zero failures/skips/runtime warnings, 303.884 seconds;
  `build/ssh-encrypted-pkcs8-native-final-ui-20261008/`. Draft checks include
  wrong-phrase rejection, cancel with no staged key, reimport/retry and successful
  unlock. Library checks include matching seed/import fingerprints, rename,
  relaunch/read and deletion. Successful draft/library screenshots reviewed:
  complete labels/fingerprints, normal native controls and wrapped footer text.
  The native PasteButton label follows the simulator's system language.
- Cleanup evidence: four generated source files absent and ownership journal
  empty; `ssh-encrypted-file-cleanup.json` in the final gate directory. No actual
  user's key/passphrase was used. Native cancellation is covered after a failed
  phrase; interruption during a long-running CommonCrypto derivation has not
  received native UI acceptance.

No physical-device, Mac/iPad UI, encrypted OpenSSH/RSA or overall Screens-parity
acceptance is claimed. No commit, push, tag or release performed.


## 2026-10-08: reuse completed Metal upload buffers with bounded idle memory

Source inspection found a fresh shared MTLBuffer allocation for each dirty
upload region. Added a lock-protected best-fit pool, capped at 32 MiB and 32 idle
buffers per renderer. GPU-owned outstanding leases are outside this idle cache
limit; this is not a total renderer/process memory limit. Normal draw submission
still limits outstanding GPU frames to three. Preparation failures return only
unencoded buffers immediately; encoded buffers return solely from the command
buffer's completion handler. Shader, row alignment, pixel copies, dirty revision
tracking and render metrics remain on their existing paths.

Disconnect/failure callbacks and explicit endSession disable caching and drop
idle buffers; completion callbacks while disabled cannot replenish the cache.
A new connected state enables caching again. No package dependency was added.

Validation:
- Targeted real-Metal renderer/pool/session tests: 13/13, zero failures;
  `/tmp/aetherscreens-upload-pool-final-targeted.log`.
- Real GPU blocked by a shared event, with 24 distinct queued pixel versions:
  idle cache remained empty while blocked; each resulting snapshot retained its
  own expected pixel after execution; completed uploads populated the pool.
- Pool tests prove exclusive simultaneous leases, byte/count bounds, oversize
  rejection from the cache, cache disabling/late return/re-enable behavior and
  reuse of one actual 4K-sized allocation over 120 lease cycles. The latter is
  allocation reuse, not 120 presented frames or a measured FPS improvement.
- Full debug core: 367 tests, 8 explicit environment skips, zero failures,
  96.964 seconds; `/tmp/aetherscreens-upload-pool-full-core.log`.
- macOS build and generic iOS Simulator build passed;
  `/tmp/aetherscreens-upload-pool-mac-build.log` and
  `/tmp/aetherscreens-upload-pool-ios-build.log`.
- Owned phone Simulator native Chinese display selection/live layout changes
  and English zoomed left/right edge follow/held drag/disabled auto-pan passed
  2/2, no skips/failures/runtime warnings; screenshots reviewed;
  `build/metal-upload-pool-navigation-ui-20261008/`. Right-edge arrow body
  clipping is still visible; hotspot/viewport mapping passes and no fake clamp
  was introduced. This does not close full-pointer-visibility acceptance.

This removes repeated upload allocations on cache hits. It does not prove a
specific UI hitch/FPS/latency improvement. Physical iPhone/Macmini measurement,
remaining animation/peripheral flows and overall Screens parity remain open.
No commit, push, tag or public release performed.


## 2026-10-08: accelerate full-color ZRLE raw-tile expansion

Compared the existing implementation in macOS Release before editing. Nine
4K decoder samples from three independent processes had a 15.2004 ms median
(range 14.0449–16.5626 ms); Debug's approximately one-second timings were not a
valid estimate of shipping decoder throughput.

Replaced only the full-color raw-tile per-pixel BGR->BGRA loop with system
Accelerate/vImage RGB888->RGBA8888. Keeping the source byte order yields BGRA
from BGR input, with constant opaque alpha and no premultiplication. Each already
bounded 64x64 or partial tile uses kvImageDoNotTile to avoid nested internal
parallel tiling. Destination row stride remains the full framebuffer width.
RGB565, palette/RLE decoding, size/truncation checks and zlib dictionary ownership
retain their prior paths. No production package dependency was added.

Validation:
- Installed SDK Conversion.h confirms the BGR888->BGRA8888 macro maps to this
  function and supports nil alpha source plus constant alpha; API is available
  well below this project's platform minimums.
- All 15 ZRLE decoder tests passed in Release, including byte-for-byte repeated
  4K output, non-multiple-of-64 edges, tiny rectangles, palette/RLE variants,
  truncation and invalid profiles; `/tmp/aetherscreens-zrle-release-after.log`.
- Same fixture, compiler mode, three processes x three frames: candidate median
  7.8477 ms (range 7.5994–9.3032 ms), 48.37% less decoder time than baseline.
  Every measured frame was compared against every expected pixel. Includes
  zlib inflate plus expansion; excludes network, UI and GPU presentation.
  Raw packet size 24,892,842 bytes. This worst-case raw-tile fixture is not a
  measurement of an actual Apple desktop or a general end-to-end speedup.
  Logs/statistics: `build/zrle-vimage-benchmark-20261008/`.
- Complete debug core: 367 tests, 8 explicit environment skips, zero failures,
  91.783 seconds; `/tmp/aetherscreens-zrle-vimage-full-core.log`.
- macOS and generic iOS Simulator builds passed;
  `/tmp/aetherscreens-zrle-vimage-mac-build.log` and
  `/tmp/aetherscreens-zrle-vimage-ios-build.log`.
- Owned phone Simulator Chinese viewport/observe/local-pan and English
  16-/32-bit display quality/reconnect/coordinate gate passed 2/2, zero
  skips/failures/runtime warnings, against a separately owned fixture forced
  to ZRLE. Restored canvas/navigation screenshots reviewed; no channel swap
  or visible corrupt pixels in the controlled pattern. Captured final fixture
  events confirm ZRLE and contain no protocol-error event. Artifact:
  `build/zrle-vimage-native-ui-20261008/`. Resets clear earlier events; the saved
  final event snapshot is not a complete trace of every tested reconnect.
- Closed only this phase's fixture PID 89645 after verifying its exact command
  and ports 6061/6062/8861; terminal exit 143. Original fixture left running.

Physical iPhone/Macmini FPS/hitch/latency acceptance, remaining animation flows,
Apple RGB565 interoperability and complete Screens parity are still open.
No commit, push, tag or release performed.


## Keyboard overlay transitions and system Reduce Motion (2026-10-08)

Floating and carousel keyboard overlays now animate insertion/removal with a
0.28-second spring and subtle 0.96 scale plus opacity. A controls-only ZStack
owns the animation; the remote canvas and pointer remain outside its scope.
System Reduce Motion disables that spring/scale. Existing toolbar movement,
collapse, text entry and reconnect semantics are retained.

Validation:
- macOS and generic iOS Simulator builds passed; current logs listed above.
  The preceding full core gate remains 367 tests / 8 environment skips / zero
  failures; it was not rerun for this view-only and native-QA-helper phase.
- Initial native run: Chinese carousel and English floating toolbar passed
  separately (2/2). Its third, combined Reduce Motion case completed both UI
  flows but failed restoring the setting after Settings restarted. Preserved
  artifact: `build/keyboard-overlay-transitions-ipad-ui-20261008/`.
- Fixed the QA helper to reopen Accessibility/Motion after Settings activation,
  capture the original switch value, and restore that exact value. A separately
  selected simulator-only recovery case restored this phase's original OFF
  value; `build/keyboard-overlay-motion-restored-ui-20261008/` (1/1 passed).
- Final actual-system Reduce Motion floating/carousel rerun passed 1/1, zero
  skips/failures/runtime warnings. Original-value attachment is 0, restored
  screenshot shows OFF. Floating and carousel moved-state screenshots reviewed.
  Artifact: `build/keyboard-overlay-reduced-motion-final-ui-20261008/`.
- Animation Hitches recording targeted only the owned Simulator app, but
  Instruments returned "Hitches is not supported on this platform." Failed
  recording log: `/tmp/aetherscreens-overlay-animation-trace.log`. No hitch/FPS
  acceptance is claimed from screenshots or native functional test success.
- Returned the owned iPad Simulator to its initial Shutdown state after final
  setting restoration. Existing RFB fixture and other devices left unchanged.

Complete Screens parity, remaining animation flows and physical iPhone/Macmini
30-minute FPS/hitch/latency acceptance remain open. No commit/push/tag/release.


## Bound periodic desktop snapshot work (2026-10-08)

SessionViewModel previously submitted a new full-frame snapshot to the global
utility queue every 60 updates and again at session teardown. Slow conversion
or JPEG writes could allow those requests to accumulate. A per-session
ThumbnailSnapshotScheduler now permits one running closure and one latest
pending closure. Replaced pending work is released; an active snapshot finishes
before the latest request runs. Disconnect uses the same scheduler so its final
preview is retained. Image creation, scaling and persistence remain off the main
actor; frame upload and input transport are unchanged. No new dependencies.

Validation:
- Two deterministic scheduler tests: 100 queued requests run only the newest;
  a blocked active snapshot finishes, 99 waiting periodic requests coalesce into
  the final disconnect snapshot, and work resumes after the worker is idle.
  Final targeted 2/2: `/tmp/aetherscreens-thumbnail-coalescing-final-targeted.log`.
- Complete core: 369 tests, 8 explicit environment skips, zero failures,
  94.650 seconds; `/tmp/aetherscreens-thumbnail-coalescing-full-core.log`.
  The idle-resume test synchronization was tightened afterwards and its final
  targeted rerun passed; production code was unchanged after the full suite.
- macOS and generic iOS Simulator builds passed, logs at current checkpoint.
- Owned iPhone Simulator actual controlled RFB preview save/disconnect/relaunch
  gate passed 1/1, no skips/failures/runtime warnings (54.882 seconds). Warm and
  cold card screenshots reviewed; both show the fixture image. The test deleted
  its own saved computer. `build/thumbnail-coalescing-native-ui-20261008/`.
- Existing fixture and device boot states retained; no real-device interaction.

This proves bounded snapshot requests and functional persistence, not measured
FPS or hitch improvement. Full Screens parity and physical long-session fluidity
acceptance remain open. No commit, push, tag or release performed.


## Recover actual Mac mini through existing Tailscale peer (2026-10-08)

Read-only existing Tailscale status identified the online Mac mini at 100.64.0.3
and fd7a:115c:a1e0::3. Both addresses accepted SSH and RFB connections; Apple
server banner RFB 003.889 and offered security types [30,33,36,31,32,2,35].
Existing trusted SSH key/host verification confirmed ComputerName and macOS
27.0.1. No network policy, remote system configuration or saved device changed.

Existing TailscaleLiveHandshakeTests passed 2/2 without skips/failures: actual
saved-Keychain session received 3840x2160 frames, remained connected for 60
seconds, intentionally disconnected without failure, then the separate version/
VNC-challenge negotiation passed. 70.757 seconds total. Log:
`/tmp/aetherscreens-macmini-mesh-handshake-20261008.log`. This is real server
connectivity evidence, not physical phone interaction, measured FPS/hitches or
Apple clipboard/Curtain/file-transfer acceptance.

An exploratory explicit username/account-frame probe could not find the selected
saved account and skipped, so no ARD account-frame success is claimed. Its
unvalidated additional test was removed; pre-existing tests retained. No secrets
were copied into logs or temporary files. Paired physical iPhone 12 Pro remains
unavailable; owned Simulator is not counted as physical-device acceptance.


## Real Apple clipboard gate over recovered mesh address (2026-10-08)

Extended the opt-in LiveClipboardTests fixture to explicitly select VNC with
AETHERSCREENS_LIVE_AUTH=vnc (Mac-account mode remains the default), and look up
an exact host/auth-method credential in the shared Store or app defaults. SSH
inspection still uses its separate account; actual clipboard delivery still
travels through RFB. No password is copied into test arguments or logs. Printed
outcomes contain only the fixed restoration/match markers, never board contents.

Actual macOS 27.0.1 Mac mini, 100.64.0.3, saved VNC Keychain authentication:
- Unicode/multiline gate failed in 64.699 seconds: remote-to-client expectation
  timed out; the client rejected text not representable by the negotiated legacy
  clipboard; remote board did not match. Connection-state assertion and original
  board restoration assertion passed. Log:
  `/tmp/aetherscreens-macmini-mesh-unicode-clipboard-20261008.log`.
- ASCII/multiline gate failed in 60.963 seconds: no remote-to-client delivery;
  local sendCutText accepted the queued packet but remote board did not match.
  Connection-state assertion passed. Explicit markers `RESTORED, NO_MATCH` prove
  cleanup succeeded while end-to-end delivery failed. Log:
  `/tmp/aetherscreens-macmini-mesh-legacy-clipboard-20261008.log`.
- Only fixture code changed; it compiled in both actual runs. No production
  protocol change, clipboard-content logging or saved-device change was made.
  Earlier 369-test core pass remains historical, not a fresh pass for this phase.

Research lead: [iShareScreen Apple protocol research](https://github.com/renegadelink/iShareScreen/blob/main/docs/apple_vnc_rfc.md)
is explicitly an experimental reverse-engineered implementation specification,
not Apple documentation. It describes vendor clipboard-change/fetch/archive
messages and an authenticated Apple encrypted control channel. This is a lead
for independently validated interoperability work, not proof this client speaks
that protocol, nor a reason to inject isolated vendor opcodes into a standard
3.8 session. Actual direction-specific wire negotiation must precede integration.
Full Apple clipboard, Curtain, file transfers and physical fluidity remain open.


## Verify Apple extension negotiation before integration (2026-10-08)

Added `scripts/qa/probe_apple_rfb.py`, an explicit-host, bounded read-only
negotiation probe. It compares standard 3.8 and Apple 3.889 banners, consumes
advertised security types, selects type 30 and reads only its public DH challenge.
It never submits an authentication response or reads a desktop/pasteboard. The
report retains only public version/type/generator/length metadata, not modulus,
server key, failure text or credentials. A total per-connection deadline bounds
fragmented/slow input; challenge length is bounded before reading its body.

Actual Mac mini 100.64.0.3 final probe passed both negotiations. Server banner
003.889, types [30,33,36,31,32,2,35], generator 5 and key-length field 512 bytes
in both profiles. Evidence:
`/tmp/aetherscreens-apple-version-negotiation-final-20261008.json`.
This contradicts the experimental research document's fixed generator-2/128-byte
type-30 description for this actual server. Do not hardcode that group or change
our validated ECB credential path to a proposed CBC variant based solely on it.
Current ARDAuthCrypto/RFBClient accept a challenge up to 512 bytes; no production
authentication or profile negotiation was changed in this phase.

Six controlled probe smoke checks passed: fragmented challenge, invalid generator,
oversized length, truncated body, malformed banner and total deadline. Log:
`/tmp/aetherscreens-apple-negotiation-probe-smoke-20261008.log`.
Python compile and git diff --check passed. No fresh Swift/UI build claimed for
this QA-only phase. Account configuration is requested through the application's
protected fields rather than plaintext chat; currently usable saved credential
proves only the VNC session. Actual authenticated Apple bootstrap, rekey/record
channel, clipboard archive exchange and end-to-end clipboard remain unverified.
Full Screens parity and physical fluidity still open; no publication.


## Actual Mac-account authentication and clipboard isolation (2026-10-08)

The saved password for this exact Mac mini also authenticated the previously
user-authorized username chenxu through security type 30. Existing live session
QA selects the username explicitly and retrieves the password from the same
host's Keychain record in memory; no credentials are copied into logs, arguments
or files. No new saved account is necessary for this probe; the earlier request
for another application credential entry is superseded by this actual result.

`TailscaleLiveHandshakeTests/testLiveTailscaleFullSessionWithSavedPassword`
passed 1/1, zero skips/failures, in 75.803 seconds: authenticated, initialized,
received 3840x2160 frames, remained connected for 60 seconds and disconnected
normally. `/tmp/aetherscreens-macmini-mesh-ard-session-20261008.log`.
Added deferred teardown and a fail-fast check so a failed authentication cannot
continue into a meaningless stability wait. No production auth changes.

Clipboard QA can now explicitly select the same host's saved VNC credential as
its secret source while independently selecting verified Mac-account auth; no
cross-host credential fallback or configuration mutation. The actual account
rerun compiled and executed both existing cases, with both failing:
- ASCII: no remote-to-client delivery or remote board match. Marker
  CHANGED_BY_OTHER_WRITER means the board was no longer recognized as QA-owned;
  the helper correctly did not restore over that value. This marker alone does
  not identify the writer or distinguish user/system/protocol side effects.
- Unicode: no remote-to-client delivery; legacy transport rejected outbound
  unrepresentable text; board did not match. Original board restoration passed
  and marker was RESTORED.
- Connection-state assertions passed in both. Two cases / six assertions failed,
  114.416 seconds; `/tmp/aetherscreens-macmini-mesh-ard-clipboard-20261008.log`.
  Do not claim either bidirectional delivery or that both original boards were
  restored. Further mutating clipboard probes need an isolated board window.

The remaining problem is not unavailable account credentials. Authenticated
Apple extension bootstrap/record/archive exchange remains unimplemented and
unverified. No production protocol modification or public release. The prior
369-test core gate is not a new full-suite pass for these QA-only changes.


## Experimental Apple control-record codec (2026-10-08)

Added internal AppleRFBRecordLayer as a necessary stage for Apple extension
integration. The standard RFB client does not instantiate it. No protocol banner,
authentication, remote settings, clipboard or current session transport changed.

The codec consumes the 36-byte rekey payload, independently ECB-unwraps its key/
IV blocks, rotates the wrap key, and installs separate CBC chains for send and
receive. Subsequent rekeys preserve independent sequence counters. Records use
bounded 16-bit ciphertext/body lengths, minimal filler and the protocol SHA-1
sequence/plaintext trailer. Filler contents are not interpreted. Receive failures
close the codec and reject all further records/rekeys; transport integration must
also close the socket. Local oversized outbound bodies are rejected without
consuming a sequence. Input size is checked before copying untrusted Data.

This implements the experimental research profile, not modern AEAD or a claim of
Apple interoperability. That project's multirekey behavior remains unverified by
its own capture; tests establish only our implementation of the proposed model.
Releasing Swift key arrays is not a guaranteed memory-wipe mechanism. No keys,
plaintext or real clipboard data are logged or persisted by the codec.

Validation:
- Eight meaningful codec tests passed: independent directional streams, chained
  CBC, empty/max body, second rekey with retained sequence, tamper/replay closure,
  malformed/trailing bounds, nonzero filler, valid integrity with invalid inner
  lengths, initialization/rekey guards. Final targeted log:
  `/tmp/aetherscreens-apple-record-final-targeted-20261008.log`.
- Nine synthetic fixtures independently generated with OpenSSL AES and Python
  SHA-1 matched the checked-in test vectors. Reproducible generator and JSON:
  `build/apple-record-vectors-20261008/`. No new production dependency.
- The interrupted initial full-suite process was gone and its log lacked the
  final summary. It was not counted as passing. A fresh complete suite then
  passed 377 tests, 8 explicit environment skips, zero failures, 92.671 seconds;
  `/tmp/aetherscreens-apple-record-full-core-final-20261008.log`.
- macOS and generic iOS Simulator builds passed; logs at current checkpoint.
- git diff --check passed. No native UI or actual Apple encrypted-wire success
  is claimed from an unused codec's unit/build gates.

Next required integration is authenticated Apple bootstrap and actual rekey/
record exchange, followed by clipboard-change/fetch/archive handling and real
bidirectional text acceptance in an isolated board window. Complete Screens
parity, native file transfers/Curtain/cloud and physical fluidity remain open.
No commit, push, tag or release performed.


## Connect ARD derivation to experimental record codec (2026-10-08)

ARDAuthCrypto.exchange now returns the credential packet and the already-derived
MD5 shared-secret wrap key as internal in-memory data. The existing response API
still returns only the same encrypted credential/public-key packet; normal
RFBClient does not keep or log the new wrap-key result. ECB, DH bounds, random
padding and public API behavior remain unchanged. No new dependencies or stored
credentials. Releasing Swift Data does not guarantee key material zeroization.

A new independent-peer test derives the shared secret from the generated client
public key using the peer's own exponent, checks the wrap key, wraps a known
content key/IV with that peer-derived key, and verifies our record codec opens
the independent OpenSSL control fixture. This bridges the two local components;
it does not prove actual Apple post-authentication bootstrap or rekey exchange.

Validation:
- Three ARD crypto tests + eight record tests passed 11/11, zero failures;
  `/tmp/aetherscreens-apple-auth-record-bridge-targeted-20261008.log`.
- Actual known Mac mini/chenxu account using same-target Keychain secret passed
  standard RFB regression 1/1, zero skips/failures, 72.254 seconds: authentication,
  real 3840x2160 frames, 60-second stability and intentional teardown;
  `/tmp/aetherscreens-apple-auth-bridge-live-20261008.log`. No clipboard mutation.
- Complete core passed 378 tests, 8 explicit environment skips, zero failures,
  92.671 seconds; `/tmp/aetherscreens-apple-auth-bridge-full-core-20261008.log`.
- macOS and generic iOS Simulator builds passed; logs at current checkpoint.
- git diff --check passed. No new native UI/physical fluidity acceptance claimed.

Research inspection pinned revision 9ab40d3a3151524f954cff9d6239d891197c1705 of
[iShareScreen's RFB implementation](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/src/isharescreen/proxy/protocol/rfb.py).
Its ViewerInfo wire format uses a 32-bit app ID plus two three-u32 version tuples
and a 32-byte command mask; the experimental document describes app ID as u16.
That discrepancy needs actual-wire validation before integration. No external
implementation was imported or copied into this repository. Actual Apple
initialization/control-channel success, clipboard compatibility and complete
Screens parity remain open. No commit, push, tag or release.


## Actual Apple 3.889 bootstrap probe (2026-10-08)

Added an explicit opt-in, 45-second-bounded POSIX QA probe using only the
approved Mac mini and its same-target Keychain credential. Normal RFBClient
behavior is unchanged. The probe does not save desktop/clipboard contents or
send input, clipboard or display-configuration commands. Its socket and record
codec close on completion/error.

Actual receiver-only probe passed 1/1, zero skips/failures, 6.547 seconds:
`/tmp/aetherscreens-apple-bootstrap-first-live-20261008.log`. This verifies
3.889 type-30 authentication with our ECB credential branch, ClientInit C1,
62-byte ViewerInfo using a u32 app ID, the encryption prelude, actual 0x44f
rekey installation and authenticated opening of the first 8-byte type-0x14
control record. This supersedes the earlier lack of actual bootstrap evidence.

The extension sends an encrypted Observe command for this probe session only.
Two initial runs failed the test's expectation of status command 12, while
eight consecutive authenticated records actually contained command 4 and
advanced the receive sequence. Diagnostic log:
`/tmp/aetherscreens-apple-bootstrap-status-live-20261008.log`. The test now
checks three consecutive bounded status records (4 or 12) after the write.
Final actual probe passed 1/1, zero skips/failures, 12.853 seconds:
`/tmp/aetherscreens-apple-bootstrap-final-live-20261008.log`.
This checks connection retention and continuous receive chaining; it is NOT
an explicit acknowledgement that the server accepted the Observe payload or
proof of send-side semantic compatibility. Command 4's meaning remains unknown.

Native Apple clipboard handling, production bootstrap integration and complete
Screens parity remain open. No clipboard mutation, host GUI automation, commit,
push, tag or release was performed in this phase.

Final default full core regression passed 379 tests, 9 explicit environment
skips, zero failures, 92.491 seconds; new actual-target test skips by default:
`/tmp/aetherscreens-apple-bootstrap-full-core-20261008.log`. git diff --check
passed. This phase changes QA and status documentation only; prior macOS/iOS
application builds remain the latest application-build evidence.


## Bounded Apple clipboard archive decoding (2026-10-08)

Added independent internal AppleClipboardArchive decoding and a session-local
AppleClipboardAssembler. These components are not wired into normal RFBClient
yet, and no real clipboard interoperability is claimed. The assembler accepts
record-fragment boundaries independently of archive boundaries, rejects extra
bytes and clears partial state on error/reset/completion. Its future transport
caller must supply only the current message's bytes and enforce a deadline.

The experimental ClipboardSend envelope and archive layout were researched from
[iShareScreen's experimental protocol memo](https://raw.githubusercontent.com/renegadelink/iShareScreen/main/docs/apple_vnc_rfc.md),
not an Apple-endorsed specification. No external implementation was copied.
Parsing caps compressed/plain data at 8 MiB, flavors at 64, aliases per flavor
at 32, UTI at 1024 bytes and alias blobs at 4096 bytes. Inflation allocates
only declared size plus one byte, checks actual size and complete input
consumption, and requires stream end or a sync-flush terminator. UTF-8 is
preferred over strict UTF-16-BE fallback. Empty archive, empty text and unknown
flavor remain distinct so an unsupported archive cannot clear the clipboard.
No pasteboard data is logged or saved; no new production dependencies.

Eight targeted tests passed, zero failures/skips:
`/tmp/aetherscreens-apple-clipboard-archive-final-targeted-20261008.log`.
Coverage includes an independently Python/zlib-generated Chinese/emoji fixture,
UTF-16 fallback and preference, empty sync-flush archive, every envelope
truncation, malformed Unicode, under/over-reported output sizes, every split
boundary and one-byte fragments, completion reuse and reset/error isolation.

Remaining: actual control-channel fetch framing and send acknowledgement,
production session/state integration, real bidirectional text acceptance with
pasteboard ownership restoration, full Screens parity and physical fluidity.
No commit, push, tag or release performed.

Final complete default core regression passed 387 tests, 9 explicit environment
skips, zero failures, 92.202 seconds:
`/tmp/aetherscreens-apple-clipboard-archive-full-core-20261008.log`.
Generic iOS Simulator BUILD SUCCEEDED, terminal exit 0:
`/tmp/aetherscreens-apple-clipboard-archive-ios-build-20261008.log`.
macOS swift build passed, terminal exit 0, 1.49 seconds:
`/tmp/aetherscreens-apple-clipboard-archive-mac-build-20261008.log`.
git diff --check passed. No UI/physical-device acceptance claimed from these
parser/build gates.


## Actual native Apple clipboard fetch, both profiles (2026-10-08)

Added internal AppleClipboardControl eight-byte full-data/promise requests and
eight-byte monitoring start/stop. Request length is an important wire invariant:
the pinned experimental reference's leading comment says 9 bytes, while its
actual builder and corrective comment use exactly 8. Source pinned to
[9ab40d3a3151524f954cff9d6239d891197c1705](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/src/isharescreen/proxy/protocol/clipboard.py).
Only wire facts were used; no implementation/dependency was imported.

The explicit opt-in live bootstrap probe now supports two read-only variants:
- Apple 3.889: after rekey, send cleartext Observe and SetEncryption(command 2),
  then encrypted monitoring/full-data request. Passed 1/1, zero skips/failures,
  6.567 seconds; `/tmp/aetherscreens-apple-clipboard-readonly-live-20261008.log`.
  Server returned type 0x1f, length 161; actual archive decoded successfully
  with unsupported flavor. This proves a semantically effective request and
  valid send/receive record exchange for this transition profile. The earlier
  encrypted-Observe-only probe did NOT prove that.
- Standard 3.008/ClientInit 1: no ViewerInfo/rekey/encrypted records. Account
  authentication + native monitoring/full-data request also decoded the actual
  161-byte archive, 1/1, zero skips/failures, 3.663 seconds;
  `/tmp/aetherscreens-apple-standard-clipboard-readonly-live-20261008.log`.
  This opens integration with existing desktop transport without depending
  on Apple high-performance framebuffer codecs. VNC-password mode is not
  verified by this Mac-account-only proof.

Both paths send best-effort stop-monitoring on scope exit and close their own
socket. No remote pasteboard contents were changed, echoed or saved. Only
message sizes/content categories are logged. The current real archive did not
contain a supported text flavor, so actual Unicode/empty clipboard delivery
and bidirectional writes are NOT accepted by this result. No clipboard
mutation was performed to manufacture a passing text result.

Archive decoding now distinguishes promise-only responses from text/empty/
unsupported results and rejects unknown promise values; metadata-only replies
can never overwrite a local clipboard. Nine archive tests plus two control
framing tests passed 11/11, zero failures/skips;
`/tmp/aetherscreens-apple-clipboard-control-targeted-20261008.log`.

Next: integrate native clipboard messages into ordinary Mac-account RFB
connections with bounded reads, socket-identity callbacks and foreground
clipboard ownership, add real transport fixtures, then verify bidirectional
Unicode in an isolated pasteboard window. Whole Screens parity and physical
fluidity remain open. No commit, push, tag or release performed.

Final same-source actual probes both passed, zero skips/failures:
- Standard profile 1/1, 3.502 seconds;
  `/tmp/aetherscreens-apple-standard-clipboard-final-live-20261008.log`.
- Apple encrypted profile 1/1, 6.564 seconds;
  `/tmp/aetherscreens-apple-clipboard-final-readonly-live-20261008.log`.
Both received the unsupported-flavor archive, not text acceptance.

Final complete core regression passed 390 tests, 9 explicit environment skips,
zero failures, 92.146 seconds:
`/tmp/aetherscreens-apple-clipboard-control-full-core-20261008.log`.
macOS swift build (1.41 seconds) and generic iOS Simulator BUILD SUCCEEDED,
both terminal exit 0:
`/tmp/aetherscreens-apple-clipboard-control-mac-build-20261008.log` and
`/tmp/aetherscreens-apple-clipboard-control-ios-build-20261008.log`.
git diff --check passed. No new UI/physical fluidity acceptance is claimed.


## Native Apple clipboard receive in ordinary desktop client (2026-10-08)

RFBClient now enables native pasteboard monitoring and an initial full-data
fetch only after exact Apple 3.889 server banner and successful Mac-account
type-30 authentication. It still replies 3.008 and uses ClientInit 1, ordinary
framebuffer encodings and the existing transport. No claim of Apple
high-performance rendering or record encryption applies to this integration.
VNC-password and ordinary server branches remain on their existing clipboard
paths; the former has not been verified for native Apple messages yet.

Added status 0x14 and archive 0x1f dispatch: clipboard-change notifications
coalesce while a fetch is pending, retaining one follow-up fetch; unknown status
commands are consumed without changing the clipboard. Archive sizes are
validated before payload reads, and complete status/archive wire reads have a
15-second total deadline scoped to captured socket and read ID. Inflation and
archive decoding run on the existing serial decode worker. Results return to
the connection queue and reject replaced sockets; the clipboard callback may
itself reconnect without starting an old message loop on the replacement.

Text and explicit empty archives reach the existing onClipboardReceived path;
metadata-only/unsupported archives do not write anything. Existing foreground
and ended/reconnected session guards in SessionViewModel remain authoritative
for native platform pasteboard writes. No local pasteboard reader/writer was
called by these transport tests. Outgoing native Unicode archive encoding is
not integrated yet; actual bidirectional clipboard remains unaccepted.

Eight loopback TCP cases passed, zero skips/failures, 15.136 seconds before the
final status-deadline helper extraction:
`/tmp/aetherscreens-apple-clipboard-transport-final-targeted-20261008.log`.
They cover independent Unicode fixture + status/frame interleave, every receive
segment needed by split header/payload, explicit clear, promise/unsupported
non-delivery, oversized announced header, incomplete-body deadline, repeated
change notification coalescing, clipboard-callback reconnect and ordinary
banner isolation. The synthetic server consumes a credential response; actual
credential validity is covered by the independent crypto and actual Mac gates.
An initial test compile failed comparing different pixel collection types and
was corrected to elementsEqual; it was not counted as passing.

Full Screens parity, actual text reception/writes and physical fluidity remain
open. No commit, push, tag or release performed.

Final-source actual ordinary Mac-account regression passed 1/1, zero
skips/failures, 75.263 seconds: actual 3840x2160 frames, 60-second retained
connection and intentional teardown after native receive activation.
`/tmp/aetherscreens-apple-native-clipboard-client-live-20261008.log`.
The test has no platform pasteboard writer; no clipboard mutation was performed.
This is desktop coexistence evidence, not actual supported-text reception.
Generic iOS Simulator BUILD SUCCEEDED, terminal exit 0:
`/tmp/aetherscreens-apple-native-clipboard-client-ios-build-20261008.log`.

Final complete core regression after status-deadline helper extraction passed
398 tests, 9 explicit environment skips, zero failures, 107.640 seconds:
`/tmp/aetherscreens-apple-native-clipboard-client-full-core-20261008.log`.
The eight TCP cases, including the real 15-second deadline, passed within this
final-source suite. macOS swift build passed, terminal exit 0, 1.43 seconds:
`/tmp/aetherscreens-apple-native-clipboard-client-mac-build-20261008.log`.
git diff --check passed. No UI/physical-fluidity acceptance claimed from these
transport/build gates.


## Native Apple Unicode clipboard sending (2026-10-08)

Mac-account/Apple-banner connections now queue native type-0x1f UTF-8 text
archives instead of the legacy Latin-1 ClientCutText path. The independently
implemented encoder emits one public.utf8-plain-text flavor with zero aliases,
reserved fields zero, bounded sizes and Z_SYNC_FLUSH compression. Normal send
acceptance keeps its 1,048,000-byte UTF-8 limit; newline normalization stays LF.
Acceptance means queued work, not remote pasteboard acknowledgement. VNC and
ordinary server paths remain unchanged.

Compression runs outside inputLock on the existing decode worker. At most one
encoding operation and one latest pending text are retained; repeated sends
coalesce before encoding. Each encoding yields to queued frame/clipboard
decoding before another starts. Socket identity and an independent clipboard
input generation gate the final send on the connection queue under inputLock.
Observe, disconnect and failure clear/invalidate pending work; an already
encoded packet queued behind a connection callback is also rejected after
Observe/control toggling or replacement connection. Local pointer suppression
and viewport wheel cancellation do not cancel a clipboard upload. No data is
logged/saved and no production dependency was added.

Validation so far:
- Prior targeted run: 23 tests, zero skips/failures, 15.302 seconds;
  `/tmp/aetherscreens-apple-native-clipboard-send-targeted-20261008.log`.
  Includes independently Python-generated raw archive comparison via generic
  zlib inflater, sync-flush marker/UTF-8/empty/oversize, actual TCP independent
  one-flavor peer parser, 100-to-latest coalescing, pan preservation and pending
  Observe cancellation. The peer does not use AppleClipboardArchive.decode for
  uploads. Existing native receive gates remain covered.
- Two additional final-source deterministic tests passed 2/2, zero
  skips/failures, 0.037 seconds;
  `/tmp/aetherscreens-apple-native-clipboard-send-invalidation-20261008.log`.
  They hold an actual connection callback, drain the worker to ensure encoding
  and send enqueue, then switch Observe or reconnect before releasing it. Only
  the fresh upload reaches the TCP peer.

Real bidirectional Mac pasteboard acceptance remains required. An availability
question requests a two-minute window without concurrent copying because the
previous real board test lost ownership; lack of an answer does not permit
mutating the board. Independent core/build work continues. Full Screens parity
and physical fluidity remain open. No commit, push, tag or release performed.

Final full default core passed 404 tests, 9 explicit environment skips, zero
failures, 108.637 seconds, including all 25 native clipboard cases:
`/tmp/aetherscreens-apple-native-clipboard-send-full-core-20261008.log`.
macOS swift build (3.19 seconds) and generic iOS Simulator BUILD SUCCEEDED,
both terminal exit 0:
`/tmp/aetherscreens-apple-native-clipboard-send-mac-build-20261008.log` and
`/tmp/aetherscreens-apple-native-clipboard-send-ios-build-20261008.log`.
git diff --check passed. Only a source comment changed after the functional
full suite; no UI/physical fluidity or real pasteboard exchange claimed.
The availability question remains unanswered, so no live mutating clipboard
test was started.


## Verify VNC branch and large native upload (2026-10-08)

Added explicit VNC-password selection to the opt-in read-only Apple probe. It
allows type 2 only with the standard 3.008 profile; no ARD-derived wrap key or
encrypted-session capability is inferred from VNC authentication. Existing
same-target Keychain secret is used in memory and never logged. An optional
standard-profile ViewerInfo variant reuses the already-verified 62-byte layout.
No production activation policy was broadened by these experiments.

Actual Mac mini VNC authentication passed, but native ClipboardSend did not:
- Without ViewerInfo: authentication/ServerInit succeeded, then total probe
  deadline expired. 1 failed case, 45.609 seconds;
  `/tmp/aetherscreens-apple-vnc-clipboard-readonly-live-20261008.log`.
- With ViewerInfo: authentication/ServerInit succeeded and 20 type-0x14 status
  messages were consumed, but no 0x1f archive arrived. The bounded-loop assertion
  failed, 40.573 seconds;
  `/tmp/aetherscreens-apple-vnc-viewer-clipboard-readonly-live-20261008.log`.
These are failed native fetch gates, not passes. They establish only this host's
observed behavior under these two requests, not universal VNC impossibility.
The production native clipboard path therefore still requires successful
Mac-account authentication and the exact Apple banner.

Final-source actual Mac-account standard-profile probe retained the positive
control: 1/1, zero skips/failures, 8.100 seconds, actual 161-byte unsupported
archive decoded; `/tmp/aetherscreens-apple-account-clipboard-probe-regression-20261008.log`.
No actual text or bidirectional write acceptance is claimed. All these probes
are read-only with best-effort monitor-stop and explicit socket close.

Added a real loopback TCP large-upload case: 828,890 bytes of synthetic Chinese/
emoji/newline text. Independent peer inflater and one-flavor parser recovered
the entire exact text, with compressed payload verified greater than 65,536
bytes, one upload and retained connection. Passed 1/1, zero skips/failures,
0.052 seconds; `/tmp/aetherscreens-apple-native-clipboard-large-upload-20261008.log`.
This verifies TCP receive-chunk boundaries, not Apple encrypted-record
fragmentation (the integrated client uses standard transport).

This phase changes QA only; production app source and activation policy remain
as in the preceding Unicode send phase. The exclusive clipboard-window
question is still unanswered; no mutating live clipboard test was started.
Full Screens parity and physical fluidity remain open. No commit, push, tag or
release performed.

Final-source actual Apple encrypted-profile positive control passed 1/1, zero
skips/failures, 6.594 seconds, after extracting shared ViewerInfo generation:
`/tmp/aetherscreens-apple-encrypted-clipboard-probe-regression-20261008.log`.
Actual 0x1f unsupported archive decoded; supported text remains unaccepted.
Final default core regression passed 405 tests, 9 explicit environment skips,
zero failures, 108.117 seconds:
`/tmp/aetherscreens-apple-clipboard-vnc-large-full-core-20261008.log`.
git diff --check passed. Application sources were unchanged in this phase;
preceding macOS/iOS build logs remain the latest application-build evidence.

Next independent alignment gap located in current source: cursor pseudo-
encoding is consumed without publishing a shape, and iOS/external overlays
render PointerArrowShape. Native remote I-beam/resize/cursor visibility needs
protocol, session lifecycle and render integration plus actual acceptance.
This is a located gap, not an implemented or verified new cursor capability.


## Standard RFB rich cursor decoding and transport publication (2026-10-08)

Current cursor pseudo-encoding handling discarded its body and always used
four wire bytes per pixel. Added RFBRemoteCursor with bounded rich-pixel/mask
decoding and a socket-scoped onCursorReceived callback. Shape sizes are capped
at 512 per nonzero dimension before any body read/allocation; zero dimensions
consume no bytes and explicitly hide the cursor. Nonempty hotspots must be
within shape bounds. Alpha comes from MSB-first, byte-padded transparency rows,
not the unused fourth wire byte. Transparent pixels zero all BGRA components
for valid premultiplied images; visible pixels use alpha 255. RGB565 consumes
two wire bytes per pixel and expands colors through the existing pixel codec.
CGImage construction preserves BGRA byte order and disables interpolation.

Protocol source: [RFB Cursor Pseudo-encoding](https://github.com/rfbproto/rfbproto/blob/master/rfbproto.rst#cursor-pseudo-encoding).
Cursor-only updates now publish shape independently and do not announce a
new framebuffer frame or finish first-desktop loading. Pixel-containing
updates retain normal frame publication. Socket identity is checked after
a cursor callback that may disconnect/reconnect before reading later rects.
Invalid geometry/data fails explicitly rather than stalling or trusting a
large allocation. No new dependencies.

Five targeted codec/TCP tests passed, zero skips/failures, 0.025 seconds:
`/tmp/aetherscreens-rich-cursor-final-targeted-20261008.log`. Coverage includes
9-pixel row padding/MSB ordering, mask vs unused alpha, transparent RGB
zeroing, BGRA/RGB565 colors and exact lengths, hotspots and allocation caps,
CGImage creation, explicit hide, subsequent frame alignment and one actual
pixel frame count, cursor-callback reconnect. Final zero-dimension bounds
refinement is validated in the final full suite.

Important integration boundary: Cursor is still NOT advertised in SetEncodings
and onCursorReceived is not wired to the native overlays yet. These gates
verify decoding/publication of fixture-supplied messages, not advertised
interoperability, visible remote cursor shape or real Mac/phone acceptance.
The next stage must wire generation-safe session shape lifecycle and cached
UIKit/AppKit/external-display rendering before enabling negotiation and
checking actual server behavior. Apple 0x450 cursor-cache/SELECT remains a
separate unresolved protocol path. Full Screens parity/physical fluidity and
real bidirectional clipboard remain open. No commit, push, tag or release.

Final complete core after zero-dimension refinement passed 410 tests, 9 explicit
environment skips, zero failures, 107.730 seconds:
`/tmp/aetherscreens-rich-cursor-full-core-20261008.log`.
macOS swift build (1.56 seconds) and generic iOS Simulator BUILD SUCCEEDED,
both terminal exit 0:
`/tmp/aetherscreens-rich-cursor-mac-build-20261008.log` and
`/tmp/aetherscreens-rich-cursor-ios-build-20261008.log`.
git diff --check passed. No visible native shape or real-device fluidity claim
is made from these decoder/transport/build gates. Pixel/mask conversion is
currently bounded on the transport queue; move it to the decode worker with
stale-result rejection before enabling shape negotiation and native rendering.

## Standard RichCursor native presentation (2026-10-08)

- Cursor pixel/mask conversion now runs on the existing serial decode worker.
  Negotiated depth is captured with the source connection, cancelled workers
  skip old work, and publication checks socket identity before callbacks and
  before continuing the rectangle stream. Explicit zero-size hide remains an
  allocation-free transport fast path.
- Session shape updates use a retained CurrentValueSubject, reset at session
  start/end/failure/disconnect and checked against callback generation before
  asynchronous delivery. UIKit pointer samples still update layers directly;
  cached bitmaps preserve the server hotspot and explicit hide differs from
  the fallback arrow. External-display overlays receive the same shape state.
- macOS uses cached NSCursor shapes and local cursor rectangles; explicit hide
  uses a transparent cursor, without changing global cursor hide counts.
  Viewport panning uses the native open-hand cursor.
- Standard Cursor (-239) is now negotiated for non-Apple banners. XCursor and Apple's separate 0x450
  cache protocol remain unimplemented. Seven targeted codec/native-view/TCP
  cases passed with zero failures/skips, including transport pointer delivery
  while the decode worker is held and stale shape rejection after reconnect.
  `/tmp/aetherscreens-cursor-native-final-targeted-20261008.log`.
- iOS generic build passed after fixing a fallback-layer color assignment;
  `/tmp/aetherscreens-cursor-native-ios-fixed-20261008.log`. Full core tests,
  owned-simulator visual edge-follow and actual Mac-account desktop regression
  are running. No physical smoothness or real cursor-shape acceptance claimed.

- Actual Apple Mac-account connection with RichCursor advertised completed
  authentication but timed out without a first desktop image (1/1 failed,
  24.482 seconds); `/tmp/aetherscreens-cursor-native-client-live-20261008.log`.
  No causal certainty is claimed from this single failure. The Apple-banner
  negotiation guard retains its previously accepted encoding set while a
  direct fallback regression runs. Standard non-Apple fixture gates remain
  enabled; this failure must not be reported as Apple cursor acceptance.

- Apple-banner fallback desktop acceptance passed 1/1 with zero skips/failures,
  78.607 seconds, actual 3840x2160 frames and 60 seconds continuously connected;
  `/tmp/aetherscreens-cursor-apple-fallback-client-live-20261008.log`.
  The earlier advertised-Cursor failure remains retained, and Apple cursor
  interoperability is not considered accepted by this desktop fallback gate.
- Owned-simulator local viewport navigation passed 1/1 with zero skips,
  failures or runtime warnings; Pan/Observe screenshots were exported and
  reviewed. `/tmp/aetherscreens-cursor-native-ui-20261008/summary.json`.

- Final Apple-guard targeted regression passed 20/20 with zero skips/failures,
  15.629 seconds; `/tmp/aetherscreens-cursor-apple-guard-targeted-20261008.log`.
  Final macOS build passed, 0.84 seconds;
  `/tmp/aetherscreens-cursor-apple-guard-mac-build-20261008.log`.
- Owned-simulator trackpad edge-follow passed 1/1 with zero skips/failures or
  runtime warnings; `/tmp/aetherscreens-cursor-native-edge-ui-20261008/summary.json`.
  Exported right/left/held-drag screenshots show the fixture's green RichCursor
  at the correct hotspot while the actual viewport shifts; packet assertions
  verify pointer button release and held-button dragging. Body clipping at the
  display edge remains visible and is not claimed fixed. The earlier Pan/Observe
  gate also passed, for 2/2 native cases in this phase. No FPS/hitch inference.
  Only the newly created 6051/6052/8811 fixture is stopped after verification;
  no other fixture or simulator lifecycle was changed by this phase. The old
  recorded fixture PID 19741 was absent at final inspection; it was not stopped
  or restarted by this phase.


## Initial desktop fetch after cursor-only updates (2026-10-08)

- Cursor/layout-only responses previously caused the next request to become
  incremental before any desktop pixels had arrived. A static server can answer
  a cursor-only update and then have no changed desktop region to send. The
  client now keeps requesting a full image until hasReceivedPixelUpdate is true;
  subsequent requests return to incremental operation.
- The new TCP case asserts request order full/full/incremental around an initial
  Cursor-only reply and the first Raw pixels. Passed 1/1, zero failures/skips,
  0.012 seconds; `/tmp/aetherscreens-cursor-initial-full-targeted-20261008.log`.
- Standard Cursor is negotiated for Apple banners again after this correction.
  Actual Mac-account desktop regression passed 1/1 with zero skips/failures,
  80.610 seconds, 3840x2160 pixels and 60 seconds continuously connected;
  `/tmp/aetherscreens-cursor-initial-full-apple-live-20261008.log`.
  No standard Cursor callback was observed. The earlier failure and fallback
  results remain evidence, but this pass does not prove their cause or Apple
  shape interoperability. The Apple-banner guard recorded above is historical.
- iOS generic build passed;
  `/tmp/aetherscreens-cursor-initial-full-ios-build-20261008.log`.
  Final full core regression is running; no new native visual or physical
  fluidity acceptance is inferred from this network correction.
- Protocol research for the next Apple shape step: the pinned experimental
  [project protocol memo](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md#83-cursorimage-0x450)
  describes 0x450 as a session-local STORE/SELECT cache, separate BGRA/alpha
  payload and local pointer position. These are research leads rather than
  current device proof; earlier errors in that memo require independent wire
  validation before enabling the Apple cache protocol. No implementation source
  or dependency is copied from that project.

Final verification for the initial-fetch correction: full core 413 tests,
9 explicit environment skips, zero failures, 108.926 seconds; latest macOS
build passed in 1.07 seconds. iOS generic build passed. git diff --check passed.
No UI/device lifecycle was changed in this phase; no commit/push/release was
performed. The full Screens-alignment goal remains active.

## Experimental Apple cursor receive/cache (2026-10-08)

- Independently implemented the experimental 0x450 STORE/SELECT wire framing
  described by the pinned [protocol memo](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md#83-cursorimage-0x450).
  Opaque identifiers map to cached hotspot/shape data; unknown SELECT retains
  the current presentation rather than blanking it. A reconnect creates new
  decode contexts, so its cache cannot select a previous session's shape.
- Header lengths and geometry are validated before reading a compressed body.
  Inflation is bounded to width*height*5+1 and requires exact output/input
  consumption. Dimensions cap at 512, compressed bodies at 2 MiB, retention
  at 8 MiB/64 entries with LRU eviction. The budget covers retained pixmaps,
  not transient decoding or native renderer allocations.
- The separated alpha plane overrides the unused wire pixel-alpha byte. RGB
  is currently treated as straight color and converted to premultiplied BGRA;
  this assumption requires independent actual-packet/appearance validation.
  It must not be described as proven Apple cursor visual interoperability.
- STORE/SELECT decoding runs on the serial decode worker and socket-checked
  publication uses the existing native cursor callback. These updates neither
  publish fake desktop frames nor satisfy the first-image gate. Malformed
  replacements preserve cache entries; invalid wire bodies fail the session
  without overwriting existing desktop pixels.
- Eleven targeted codec/TCP/negotiation cases passed, zero skips/failures,
  0.050 seconds; `/tmp/aetherscreens-apple-cursor-final-targeted-20261008.log`.
  Coverage includes fractional alpha, ID reuse, unknown selection, retention
  limits, corruption, stream endings, callback reconnect, cache isolation and
  explicit-opt-in plus Apple-banner negotiation gating.
- Production does not advertise 0x450. An internal test-only constructor flag
  permits an isolated live probe, with a separate vendor callback so ordinary
  Cursor messages cannot satisfy the Apple shape acceptance expectation.
- Actual explicit-opt-in Mac-account probe failed 1/1, 35.015 seconds: desktop
  pixels arrived, but no Apple cursor shape arrived within the subsequent
  15-second gate. `/tmp/aetherscreens-apple-cursor-experimental-live-20261008.log`.
  No clipboard or remote input was written. This is a failed cursor gate, not
  evidence that the feature is enabled or interoperable.
- iOS generic build passed;
  `/tmp/aetherscreens-apple-cursor-receive-ios-build-20261008.log`.
  Full core regression is running. Server-driven update startup and subsequent
  layout/session rearming still need wire validation; no 0x09 control is sent
  by this implementation. The native encrypted profile remains separate work.

Final experimental-cache verification: 424 core tests, 9 explicit environment
skips, zero failures (108.669 seconds). macOS build passed in 1.48 seconds;
iOS generic build and git diff --check passed. No commit/push/release occurred.
The failed actual cursor probe remains an open gate, and production negotiation
is unchanged for the vendor format. Full Screens parity remains in progress.

## Experimental cursor startup control (2026-10-08)

- Added independently encoded 16-byte AutoFrameBufferUpdate (0x09), version 1,
  all/main-screen selector and full backing geometry, following the pinned
  [experimental wire memo](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md#811-autoframebufferupdate-0x09).
  Zero/negative/oversized dimensions cannot produce a packet.
- Startup sends this only with the explicit internal experimental cursor flag
  and Apple banner, immediately before the initial full-image request. The
  production public constructor keeps that flag false. Polling behavior remains
  unchanged pending actual server-driven acceptance; layout rearming and native
  encrypted-profile cursor startup are not implemented by this step.
- Three control/negotiation cases passed with zero failures/skips, 0.024 seconds;
  `/tmp/aetherscreens-apple-cursor-arm-targeted-20261008.log`. The TCP fixture
  verifies the exact startup packet is received only under the two required
  conditions and the ordinary desktop still arrives.
- Actual Mac-account arm probe failed 1/1, 36.274 seconds: desktop pixels arrived
  but no 0x450 shape reached the vendor-only callback within the subsequent
  15-second gate. `/tmp/aetherscreens-apple-cursor-arm-live-20261008.log`.
  This is negative interoperability evidence for the current 3.008/plaintext
  profile, not proof of working server-driven cursor updates. No remote input
  or clipboard write occurred. Production cursor negotiation remains unchanged.
- iOS generic build passed;
  `/tmp/aetherscreens-apple-cursor-arm-ios-build-20261008.log`.
  Full core regression is running. Next protocol work must validate the viewer
  capability/modern-bootstrap prerequisites rather than assume more polling or
  an unverified flag proves cursor acceptance.

Final startup-control verification: 426 core tests, 9 explicit environment skips,
zero failures (108.763 seconds). macOS build passed in 1.32 seconds; iOS generic
build and git diff --check passed. The actual cursor probe failure is retained;
this control is not enabled for production sessions. No commit/push/release or
UI/device lifecycle changes occurred. Full Screens parity remains in progress.

## ViewerInfo and modern cursor bootstrap prerequisites (2026-10-08)

- Extracted the independently verified ViewerInfo encoder into a shared helper.
  It preserves the 62-byte body/66-byte packet, UInt32 application identifier,
  actual OS version and the existing MSB-first bitmap. Both cursor and bootstrap
  probes use it; no additional capability bits or public feature claims are added.
- ViewerInfo is sent before pixel/encoding setup only in the explicit internal
  Apple cursor experiment. Four packet/control/TCP cases passed, zero skips or
  failures, 0.025 seconds;
  `/tmp/aetherscreens-apple-cursor-viewer-targeted-20261008.log`.
- Actual 3.008 ViewerInfo+arm experiment failed 1/1 in 37.724 seconds: desktop
  pixels arrived but no vendor cursor shape followed within the 15-second gate.
  `/tmp/aetherscreens-apple-cursor-viewer-live-20261008.log`.
- Added a separate modern-bootstrap experiment: only both internal opt-ins plus
  Apple banner select the 3.889 version reply and shared ClientInit 0xC1. All
  other combinations retain 3.008/ClientInit 1. TCP cases verify these exact
  bytes across four combinations; no public constructor can enable the profile.
- Unknown rectangle bodies have no universal length. The previous default
  skipped just their header and could parse opaque payload as later rectangles;
  it now fails explicitly without overwriting desktop pixels. A TCP regression
  covers this behavior. Three final targeted cases passed, 0.034 seconds;
  `/tmp/aetherscreens-apple-cursor-modern-final-targeted-20261008.log`.
- Actual 3.889/C1 plaintext experiment authenticated but timed out without a
  first image. The first run recorded an additional test-harness unwaited
  cursor expectation, not an extra application failure: 1 test, 2 failures
  including 1 unexpected, 36.579 seconds;
  `/tmp/aetherscreens-apple-cursor-modern-live-20261008.log`.
  The probe now owns an unregistered optional XCTestExpectation so early-image
  failure does not leave a registered expectation behind, and its failure copy
  reports the image/connection state rather than incorrectly implying auth failed.
- Independent modern encrypted-bootstrap regression passed 1/1, no skips or
  failures, 15.111 seconds: accepted type-30 auth, rekey, first verified type-20
  record and three subsequent verified control records after encrypted Observe.
  `/tmp/aetherscreens-apple-viewer-bootstrap-regression-20261008.log`.
  This verifies the shared helper and existing cipher bootstrap, not integrated
  native desktop, cursor, privacy or encrypted bidirectional clipboard support.
- Full core passed 429 tests, 9 explicit environment skips, zero failures,
  108.004 seconds; `/tmp/aetherscreens-apple-cursor-modern-full-core-20261008.log`.
  This full run preceded only the live-harness expectation/failure-copy fix.
  iOS generic build passed;
  `/tmp/aetherscreens-apple-cursor-modern-ios-build-20261008.log`.
  The corrected modern live harness is being checked separately. Production
  defaults remain unchanged; full encrypted-session integration is still required.

## Final cursor allocation and bootstrap checkpoint (2026-10-08)

The corrected modern live harness failed exactly once, with zero unexpected
failures, 36.730 seconds. Desktop pixels arrived in this repeat; the earlier
first-image timeout is not a proven stable bootstrap failure. The subsequent
Apple-only shape negotiation also delivered pixels but failed the cursor gate,
37.017 seconds. Removing the simultaneous standard Cursor offer did not close
that gate. Four exclusive-negotiation targeted cases passed, 0.052 seconds.
Logs: `/tmp/aetherscreens-apple-cursor-modern-harness-live-20261008.log` and
`/tmp/aetherscreens-apple-cursor-exclusive-live-20261008.log`.

RFBRemoteCursor now owns one immutable CGImage, constructed with the decoded
model on the serial worker. Repeated native presentation/cache selection reuses
that image; value equality still compares geometry and pixels. Hidden/invalid
raster has no image. Fifteen codec/cache cases passed in 0.116 seconds, followed
by the 430-test full suite and the owned-simulator edge-follow regression above.
The Apple cache budget accounts for retained BGRA Data only; CGImage/provider
and native renderer allocations are outside it. No measured FPS or hitch
improvement, actual Apple alpha/rendering acceptance, or physical fluidity is
claimed. Full Screens parity remains in progress; no commit/push/release.

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

## Capture timeline and byte1 hypothesis rejected (2026-10-08)

Bounded sanitized timeline extraction shows capture_monitor want_changes=1 /
capture_screen=1 / capture_current=1 after reconfiguration, then want_changes=0
at test disconnect. Thus no log evidence that capture was disabled during the
whole frozen observation. HandleAutoFrameBufferUpdateMessage2 recorded flag0
at initial/rearm times; this alone does not identify the0x09 arm, and could be
related to0x03 non-incremental requests. Prior handler-receipt claims must not
be treated as verified auto-subscription acceptance.
Tested only byte1 of0x09 from0 to1 against same measured physical+logical setup.
Actual61.012s failed3 assertions/zero skips: states2/span3.650s/age42.124s,
`/tmp/aetherscreens-srp-autoupdate-flag-pattern-live-20261008.log`.
Server still recorded flag0 at19:21:13.655 and19:21:14.326. Byte1-enable
hypothesis unsupported; restored original reserved0 packet and expected vector,
no probe branch/flag retained. Producer80ticks/84draws exited0, owned files
removed/absence verified:
`/tmp/aetherscreens-srp-autoupdate-flag-producer-20261008.log`.
Final arm tests rerun after restoration; log
`/tmp/aetherscreens-autoupdate-restored-tests-20261008.log`.
Next distinguish request handler versus actual auto subscription with direct
startup evidence. No sustained push/cursor/full UI/hardware acceptance/release.

## Measured physical plus logical-size transition evidence (2026-10-08)

Added owned fixture screen-parameter notification logging (geometry only),
compiled helper successfully, and tested measured physical size plus1920x1080
logical/3840x2160 backing. Actual gate failed3 assertions/zero skips,60.672s:
states2/span3.726s/last change age41.889s.
`/tmp/aetherscreens-srp-physical-hidpi-pattern-live-20261008.log`.
Producer notification evidence shows remote transiently3840x2160 logical/scale1
with contentrect120,1120,360,160, then1920x1080/scale2 with content120,40,360,160.
Thus configuration changes fixture coordinate mapping; do not treat unmatched
samples during that phase alone as proof of frozen captured pixels. Two known
states do not satisfy sustained gate. Producer80ticks/83draws auto-exit0; owned
binary/directory removed and absence verified:
`/tmp/aetherscreens-srp-physical-hidpi-producer-20261008.log`.
Bounded static-format server logs additionally show stop screen capture / screen
capture is not active / display reconfigure / AutoFrameBufferUpdateMessage2.
No interpolated/private log values printed. Next correlate transition times and
capture callback/subscription restart; this is evidence, not proven cause.
No app source change this phase except owned diagnostic fixture. Current full
core/iOS baseline unchanged; native continuous push/cursor/full physical UI
parity remain open. No release.

## Positive physical-size compatibility correction (2026-10-08)

Fixed descriptor now emits finite positive float millimeter dimensions; accepts
measured width/height and rejects zero/negative/NaN/Infinity/>100000. When no
measurement supplied, nominal96-DPI logical geometry is used explicitly as
synthetic descriptor size, not hardware measurement. Public standard profile
unchanged. Internal QA supplied actual598.380359111388 x340.770181217549mm.
Five independent byte/boundary/display tests passed0.003s:
`/tmp/aetherscreens-physical-size-tests-20261008.log`.
iOS build completed BUILD SUCCEEDED/exit0:
`/tmp/aetherscreens-physical-size-ios-build-20261008.log`.
Actual controlled gate failed three assertions/zero skips,61.506s,states0/span0/
ageInfinity (`/tmp/aetherscreens-srp-physical-pattern-live-20261008.log`).
Post-run three-minute static-format server-log query no longer showed the prior
Invalid size in millimeters / Unable to create display configuration errors for
the19:14:25 interval. It still reported invalid agent port, factory registration,
zero value, and two AutoFrameBufferUpdateMessage2 records. This supports size
compatibility improvement, not sole causation or sustained push success.
Actual transport received two4K ZRLE rectangles and one4K DesktopSize(-223),
20 status4 and one status12. Resize re-arm occurred, but owned surface unmatched.
Producer80ticks/82draws auto-exit0; owned files removed/absence verified:
`/tmp/aetherscreens-srp-physical-pattern-producer-20261008.log`.
Full465 regression predates this physical-size source correction; targeted
checks/iOS build are current. Next inspect returned geometry/surface and agent
port separately. Native push/cursor/full physical UI parity remain open.
No commit/push/release.

## Server-side static-format diagnostics and physical size (2026-10-08)

Read bounded remote unified logs for screensharingd/ScreensharingAgent. Raw
messages/interpolated/private values were never printed or saved. Extracted
binary static format strings and timestamps only. At18:51:45.845 and18:55:08.724
(HiDPI/combined trials), server logged `%s: Invalid size in millimeters` followed
by `Unable to create display configuration for display %d. Error: %s`.
Current fixed descriptor emits zero physical-width/height floats, a concrete
compatibility issue requiring correction. Do not call it the sole stall cause:
19:05:58 omission trial lacked these size/create errors but still froze.
All three trial intervals also reported `invalid agent port %d`, `zero value?`,
and `HandleAutoFrameBufferUpdateMessage2 flag %d`; dynamic flag/port/error
values not logged, meanings unresolved. Auto-update handler log supports server
receipt of arming in those intervals, not successful pixel delivery.
Read-only CGDisplayScreenSize(CGMainDisplayID()) on authorized remote returned
598.380359111388 x340.770181217549 millimeters. No capture/settings/input change.
Next add bounded positive physical dimensions and test with this measured size;
also investigate agent-port error independently. This phase only gathers live
evidence; code/test/build baseline unchanged. Native push/cursor/full physical
UI parity remain open. No release.

## Server-display omission trial rejected (2026-10-08)

Temporarily omitted encrypted0x1d descriptor while retaining ServerInit geometry,
record encryption, encodings, pixel format and one initial request/push arm.
Actual owned pattern still froze: states1/span0/last change age46.609s. New
test-thread gate reported all three failures,61.103s,zero skips:
`/tmp/aetherscreens-srp-server-display-pattern-live-20261008.log`.
This does not show display configuration causes the stall. Removed the trial
flag/initializer field/environment handling/branch, restoring previous setup.
No omission option retained or promoted as a solution.
Producer85ticks/85draws auto-exit0; owned binary/directory removed and absence
verified (`/tmp/aetherscreens-srp-server-display-producer-20261008.log`).
Final local pattern/display test rebuild passed5/5,zero failures,0.041s,
session76555 terminal0, log
`/tmp/aetherscreens-server-display-trial-final-tests-20261008.log`.
Full465 regression and selection iOS build remain prior verified baseline;
only QA observation lifecycle changed since that full run. Next gather bounded
server-side diagnostics/startup evidence rather than retrying identical flags.
Native push/cursor/full physical/UI parity remain open. No release.

## Full core regression and pattern-gate lifecycle (2026-10-08)

Full current core regression completed exit0:465tests,16 explicit environment
skips,zero failures,148.722s:
`/tmp/aetherscreens-srp-display-full-core-tests-20261008.log` (session42922).
Skipped external gates do not prove hardware/native-push acceptance. This run
covers the new SRP/display/status source but predates the following QA-only
observation lifecycle correction. Latest selection iOS build completed
BUILD SUCCEEDED/exit0:
`/tmp/aetherscreens-display-selection-ios-build-20261008.log` (session84368).

Moved the three sustained-pattern assertions to the XCTest thread after waiting;
timer now only closes/fulfills. Lock-protected QA client owner holds/cancels the
DispatchWorkItem on cleanup; timer refuses disconnected clients. This avoids
late observation callbacks after early transport failure and worker-thread
assertion attribution. Pattern/display tests rerun5/5,zero failures,0.041s:
`/tmp/aetherscreens-srp-pattern-gate-tests-20261008.log`.
No new actual remote attempt in this QA lifecycle phase; current actual gate
after this correction still needs rerun. Earlier frozen-pattern measurements
remain evidence, not a new passing result. Native push/full physical/UI parity
remain open. No commit/push/release.

## Combined-display selection comparison (2026-10-08)

Independently encoded bounded8-byte SetDisplay0x0d aggregate/explicit-ID packet
from research memo section7.4. Internal opt-in sends aggregate after encodings;
public default unchanged. Four display-configuration/selection tests passed,
zero failures,0.003s: `/tmp/aetherscreens-display-selection-tests-20261008.log`.
Actual controlled aggregate run failed,61.062s,zero skips:
`/tmp/aetherscreens-srp-combined-pattern-live-20261008.log`.
Matched states1/span0/last change age47.477s; no sustained acceptance or surface
causal claim. Producer80ticks/80draws auto-exit0; owned files removed/absence
verified (`/tmp/aetherscreens-srp-combined-pattern-producer-20261008.log`).
Read-only CGSession dictionary confirms OnConsole/LoginDone true but contains
no screen-lock key; fallback false must not be taken as unlocked proof:
`/tmp/aetherscreens-remote-session-flags-20261008.log`.
Full core regression launched session42922, still live at launch; log
`/tmp/aetherscreens-srp-display-full-core-tests-20261008.log`. Resume handle,
do not claim passed before terminal count/skip/failure audit. Latest selection
iOS build not run yet. Native push/cursor/full physical/UI parity remain open.
No commit/push/release.

## Fixed HiDPI descriptor comparison (2026-10-08)

Fixed display encoder now accepts an optional paired logical size separate from
backing size; rejects missing partner/nonpositive/logical dimensions exceeding
backing. Default existing packets unchanged. Internal QA client can supply
1920x1080 logical for3840x2160 backing, matching remote NSScreen metadata.
Independent byte-offset tests passed3/3, zero failures,0.003s:
`/tmp/aetherscreens-hidpi-display-tests-20261008.log`.
Generic iOS build completed BUILD SUCCEEDED/exit0:
`/tmp/aetherscreens-hidpi-client-ios-build-20261008.log` (session26818 completed).
Actual observe-profile controlled run still failed all three sustained gates,
61.461s,zero skips: states1/span0/last change age48.242s.
`/tmp/aetherscreens-srp-hidpi-pattern-live-20261008.log`.
Descriptor scaling did not restore push; no root-cause or smoothness claim.
Owned producer80ticks/80draws exited0 and owned files removed/absence verified:
`/tmp/aetherscreens-srp-hidpi-pattern-producer-20261008.log`.
Source framing reviewed from experimental memo section7.2; no third-party code
copied. Next investigate display selection. Public type30/default profile,
physical acceptance/full parity and release status unchanged.

## SRP normal-control comparison (2026-10-08)

Reviewed experimental memo startup/AutoFrameBufferUpdate fields; existing arm
matches version1/all-main-screen/full backing region. Source:
https://raw.githubusercontent.com/renegadelink/iShareScreen/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md
Added QA-only selection of existing normal-control mode1 to the SRP client.
No keyboard/pointer events sent, no production setting changed. Actual85-second
owned producer completed85ticks/85draws, exit0; owned binary/directory removed
and absence verified (`/tmp/aetherscreens-srp-control-pattern-producer-20261008.log`).
Actual client completed60.575s, one test/three assertions failed/zero skips:
`/tmp/aetherscreens-srp-control-pattern-live-20261008.log`.
Received one3840x2160 ZRLE rectangle,23 status-command4 messages. Matched states0,
span0,ageInfinity; initial frame does not establish owned-surface presentation.
Mode1 did not restore sustained updates. Observe-mode prior run also had one
4K rectangle/23 status4, but matched one state; no mode-causation claim follows.
Next inspect static display configuration versus actual sharing surface.
No native push/cursor/fluidity acceptance, no commit/push/release.

## Native status recognition separated from clipboard (2026-10-08)

Found native0x14 status was gated solely on appleClipboard, which is not enabled
for type33. Its bytes then fell through the unknown-message path. Changed the
gate to clipboard OR active native record codec; status parsing remains bounded,
and clipboard requests still require independently verified appleClipboard.
No type33 clipboard capability or mutation introduced.
Actual owned-pattern run now completed61.061s without unsupported encoding,
reading verified8-byte native status records/command4 throughout. It failed all
three sustained-pattern assertions: states1/span0/last change age48.778s. This
is not push acceptance and does not establish command4 semantics or root cause.
Log: `/tmp/aetherscreens-srp-status-separated-pattern-live-20261008.log`.
Owned producer85ticks/85draws auto-exit0; binary/directory removed and absence
verified: `/tmp/aetherscreens-srp-pattern-status-producer-20261008.log`.
Clipboard transport regression run completed exit0; exact test count is in
`/tmp/aetherscreens-srp-status-regression-tests-20261008.log`.
Next inspect subscription/session control, not authentication alone. Physical
fluidity/full Screens parity remain unverified. No release.

## Type33 controlled-pattern encoding failure (2026-10-08)

Internal SRP RFBClient generic iOS build completed BUILD SUCCEEDED/exit0:
`/tmp/aetherscreens-srp-client-ios-build-20261008.log` (session57695 completed).
Extended stream QA with the existing owned-region matcher: require>=3 states,
>=30s changed-state span, last change<20s after60s. Unchanged pixels/metadata
cannot count. Shared test-only matcher visibility changed; no public app API.
Actual controlled fixture ran100s/100ticks/100draw passes and auto-exited0,
logical1920x1080/backing2/contentrect120,40,360,160:
`/tmp/aetherscreens-srp-pattern-producer-20261008.log`.
Both clients failed before the60s gate, so no sustained acceptance: initial
18.061s, diagnostic17.789s, one failure/zero skips each. Diagnostic reported
Unsupported framebuffer encoding16778260. This may be unsupported encoding or
parser offset; do not infer either without wire evidence. Logs:
`/tmp/aetherscreens-srp-controlled-pattern-live-20261008.log`,
`/tmp/aetherscreens-srp-controlled-pattern-diagnostic-live-20261008.log`.
No input/clipboard/capture performed. Producer exited and owned binary/directory
removed; remote absence verified. Next inspect real record/rectangle boundaries.
Earlier first-frame pass does not establish continuous push. No release.

## Internal RFBClient type33 first-pixel acceptance (2026-10-08)

Added internal-only experimentalAppleSRPKey to the fixed-target client. Public
initializer/default type30 behavior unchanged. Requires native Apple banner,
cursor/encryption profile, offered33 and configured account; no silent fallback.
Validates RSA SPKI, sends encrypted identity, bounds challenge, runs PBKDF2/SRP
on serial decode worker, discards results if captured socket/state was replaced,
verifies actual stage2 M2, then reads SecurityResult. Wrap key feeds existing
native record layer; clipboard type33 capability deliberately not inferred.

Actual QA discovers the target key then creates RFBClient on a fresh socket.
It uses RGB565 and requires genuine frame callback with changed pixel regions.
Initial passed1/1 (12.829s); after replacing non-Sendable XCTest self capture
with a lock-protected client owner, final actual rerun passed1/1, zero skips /
failures,12.137s: `/tmp/aetherscreens-srp-client-owned-first-pixel-live-20261008.log`.
Related nine SRP tests passed15.258s:
`/tmp/aetherscreens-srp-client-integration-tests-20261008.log`.
No raw desktop pixels/name/credentials logged. All clients closed by defer.
This proves authentication through native record/pixel decode, not sustained
push, cursor correctness, rendering FPS or physical UI smoothness. Key trust,
public configuration and full parity remain open. Latest iOS rebuild session57695
still live at launch, log `/tmp/aetherscreens-srp-client-ios-build-20261008.log`;
resume that handle, no terminal success claimed. No commit/push/release.

## Actual type33 ServerInit acceptance (2026-10-08)

Padded SRP generic iOS build completed with BUILD SUCCEEDED/terminal exit0:
`/tmp/aetherscreens-srp-padded-ios-build-20261008.log` (session50045 completed).
Added separate opt-in ServerInit gate after M2 and zero SecurityResult. Sends
shared ClientInit0xc1, bounds remote name to1...4096, parses all24+name bytes,
requires positive dimensions and never logs desktop name. Actual Mac mini
passed1/1, zero skips/failures,8.896s:
`/tmp/aetherscreens-srp-serverinit-live-20261008.log`.
Actual initialization3840x2160,32bpp/depth24. Connections closed by test defer.
No framebuffer requested, native rekey/push/cursor or rendered frame acceptance
in this gate. RFBClient type33 production integration remains pending, as do
key trust and physical fluidity. No commit/push/release.

## Padded SRP independent vector regression (2026-10-08)

Independent Python generator now emits both minimal-generator and group-width
M1/M2 vectors from the same synthetic client/server shared secret. Swift padded
M1 and M2-gated wrap key agree; all64 mutated M2 bytes and alternate-profile M2
reject key release. Nine proof/challenge/packet/final tests passed, zero failures,
15.629s (`/tmp/aetherscreens-srp-padded-vector-tests-20261008.log`).
Additional explicit stage2 fixture added after that run; final parser tests rerun
2/2, zero failures,0.003s (`/tmp/aetherscreens-srp-actual-stage-fixture-tests-20261008.log`).
Generic iOS build launched, session50045 remains live at last poll; log
`/tmp/aetherscreens-srp-padded-ios-build-20261008.log`. Resume that handle;
do not restart or claim build success before terminal result. No remote proof
attempt this phase. Production integration/native push/physical fluidity remain
open. No release.

## Actual type33 mutual authentication verified (2026-10-08)

Primary Apple corecrypto source shows M1 integer padding depends on variant:
https://github.com/apple/corecrypto/blob/main/ccsrp/src/ccsrp_generate_M.c
No Apple code copied or dependency added. Independently implemented QA-only
generator-token group-width padding while leaving the existing synthetic profile
unchanged. Actual response changed from body6 to body98. Its stage word is2,
not the assumed3. With explicit actual stage2, M2 matched the locally expected
proof and the subsequent SecurityResult was zero. Actual opt-in test passed1/1,
zero skips/failures: `/tmp/aetherscreens-srp-actual-mutual-verified-live-20261008.log`.
Minimal packet-2 without speculative tail therefore reached authenticated proof
acceptance on this host. Key trust/pinning is still absent; password never logged.
QA closes before ClientInit; no desktop/push/fluidity success follows from this.
Production remains type30. Padded variant still opt-in and needs independent
synthetic vectors, iOS rebuild and production transport integration before use.
Intermediate padded/stage failures retained:
`/tmp/aetherscreens-srp-padded-generator-live-20261008.log`,
`/tmp/aetherscreens-srp-padded-final-stage-live-20261008.log`.
No commit, push or release.

## Type33 short-response continuation evidence (2026-10-08)

Bounded diagnostic now reads one additional four-byte word after the short
u32=2/u16=0 response. Actual Mac mini returned word1, without an accepted M2.
One actual test failed, zero skips, 13.630s:
`/tmp/aetherscreens-srp-after-short-live-20261008.log`.
This disproves treating the short response as authenticated completion; the
following word is consistent with a nonzero SecurityResult but its placement
is not yet established. No key released or ClientInit sent. No further actual
password attempts in this phase. Next compare Apple corecrypto SRP options/hash
padding behavior and packet framing; do not infer bad credentials from this.
Primary source located: https://github.com/apple/corecrypto . No source copied
or added as a dependency. Production type30, native push and fluidity gaps remain.

## Type33 actual client-proof response (2026-10-08)

Corrected QA credential lookup: a device loaded from app-suite defaults must
resolve target bindings through that same DeviceStore, not the test's standard
defaults store. Earlier missing-credential skips were therefore inconclusive.
With the correction the authorized saved target/account credentials resolved.
Two actual proof attempts reached valid public-key/challenge stages and sent
minimal packet-2. Both failed the expected final-proof gate: announced body6,
not the provisional 98-byte final body. Second attempt read all six bytes and
recorded first u32=2, final u16=0; semantics remain unverified. No M2/security
result accepted, no wrap key released, no ClientInit/session entered.
Logs: `/tmp/aetherscreens-srp-mutual-store-live-20261008.log` (10.209s),
`/tmp/aetherscreens-srp-mutual-short-response-live-20261008.log` (9.948s), each
one failure, zero skips. Password remained in process memory, not CLI/source/log.
Minimal packet framing and/or proof compatibility need further wire evidence;
do not attribute failure to wrong credentials, a failed M1, or native push.
Production remains type30; no release.

## Type33 mutual-auth QA wiring and credential preflight (2026-10-08)

Generic iOS Simulator build for both packet helpers completed successfully:
`/tmp/aetherscreens-srp-packets-ios-build-20261008.log` (terminal exit 0).
Added explicit opt-in mutual-SRP QA: exact saved host/account credential binding,
encrypted identity, bounded challenge, worker-side proof computation, packet-2,
M2 verification followed by zero SecurityResult. No ClientInit/session entry.
The existing serial Network callback queue runs the synchronous proof computation.
No supplied password is written to source/CLI/logs. LAN alias is restricted to
the already authorized Mac mini mesh/LAN pair; no arbitrary credential alias.
Both LAN-binding and mesh-binding attempts skipped at credential preflight:
no saved credential matched exact target/account. Each was 1 skipped/0 failures,
not authentication success. Logs:
`/tmp/aetherscreens-srp-mutual-live-20261008.log`,
`/tmp/aetherscreens-srp-mutual-mesh-live-20261008.log`.
No real proof sent. Final envelope/step, mutual auth, key trust and native push
remain unverified. Mac test compilation passed; no production integration/release.

## Type33 provisional final-proof grammar (2026-10-08)

Added AppleSRPServerProof with an exact bounded 102-byte profile: challenge-like
14-byte outer envelope, 64-byte M2, 16-byte server random, empty string and zero
reserved word. expectedStep is explicit with no guessed production default.
This final envelope/step is provisional, not observed remotely. Parsing never
accepts authentication, releases a key or consumes SecurityResult; M2 verification
and subsequent SecurityResult remain separate required gates.
Every truncated prefix, trailing/oversized frame, header/length/reserved-byte
mutation and wrong expected stage is rejected. Combined proof math, challenge,
packet encoder and final parser tests passed 8/8, zero failures (7.815s):
`/tmp/aetherscreens-srp-server-proof-tests-20261008.log`.
No remote authentication/proof attempt in this phase. Production type30 remains;
native push and physical fluidity acceptance remain open. No release.

## Type33 client-proof packet encoder (2026-10-08)

Added production-unwired AppleSRPProofPacket: bounded RSA1 authtype2 packet-2,
512-byte A, 64-byte M1, exact supported options and secure 16-byte client random.
It emits only the meaningful nested body, with no invented captured tail.
Independent byte-offset/header expectations and malformed fixed-field cases
passed 2/2, zero failures, 0.003s; macOS test build completed in 8.39s:
`/tmp/aetherscreens-srp-proof-packet-tests-20261008.log`.
Framing comes from the experimental research memo, not official Apple docs:
https://raw.githubusercontent.com/renegadelink/iShareScreen/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md
No real proof was sent; minimal-tail interoperability, server-final-proof framing,
actual mutual authentication, iOS compilation of this new encoder and native
continuous updates remain unverified. No production selection change or release.

## Type33 SRP proof prototype and independent vectors (2026-10-08)

Added an internal, production-unwired AppleSRP6aProof prototype. It restricts
the challenge to the RFC5054 4096-bit group, generator 5, the observed SHA512 /
SALTED-SHA512-PBKDF2 / ChaCha20-Poly1305 option string, bounded iterations and
valid server public values. Server proof length and every byte must match before
the pending wrap key is returned. BigUInt arithmetic is variable-time; this is
not a hardened constant-time authentication implementation.

An independent Python generator uses synthetic credentials and checks agreement
between server and client shared-secret equations. Regenerated fixtures matched
all fields. Swift fixtures match client public value, M1 and the key released
after M2 verification; malformed parameters and all 64 single-byte M2 mutations
are rejected. Eight relevant proof/challenge/identity/envelope tests passed with
zero skips/failures in 9.221s:
`/tmp/aetherscreens-srp-proof-profile-final-tests-20261008.log`.
The actual Mac mini challenge matched the trusted group and option profile.
This live gate sent only encrypted identity; no real password or M1 was loaded
or sent. macOS build completed in 1.58s and generic iOS Simulator build succeeded:
`/tmp/aetherscreens-srp-proof-mac-build-20261008.log`,
`/tmp/aetherscreens-srp-proof-ios-build-20261008.log`.

Production remains type30. Packet encoding, actual mutual authentication,
server-key trust, native push/cursor and physical fluidity acceptance remain
open. The historical full 448-test run predates these helpers; eight targeted
tests are not a new full-suite result. No commit, push or release.

## Actual type33 encrypted identity and bounded SRP challenge (2026-10-08)

Added a separate explicit encrypted-identity challenge QA gate. It discovers
the server public key, then sends the target username encrypted in an RSA1
identity packet on a fresh authentication connection. No password, M1 proof,
SecurityResult acceptance or desktop session is attempted. Both sockets cancel
and clear state handlers on completion; no account-derived salt/public values
are stored or logged. Metadata only is retained in logs.

Same-socket continuations (without/with a repeated selector) failed before a
bounded challenge; exact socket error was not logged, so peer-close cause is
not proven. Fresh-socket identity reached a1165-byte challenge body but initially
failed a decoder based on the reference memo's outer layout. Actual metadata
established different framing: u32 total-body length, u32 stage2, u16 nested
length1159, u32 payload length1155. This is not the memo's u8-stage/u32-nested
description. Corrected the independent decoder using actual fields. Initial
positive actual gate passed1/1, zero skips/failures,8.989 seconds:
`/tmp/aetherscreens-srp-challenge-actual-layout-live-20261008.log`.
Actual fields: modulus512 bytes, generator1 byte, salt32 bytes, server public512
bytes, iterations131578, options80 bytes. Mathematical group/algorithms/proofs
still require SRP-engine validation; field counts are not authentication success.

Decoder caps frames at8192 bytes, individual atoms at their field bounds,
iterations at a configurable finite maximum (default1,000,000), rejects zero
cost/truncation/trailing bytes/incorrect stage and invalid UTF8/NUL options.
Field fixtures intentionally are opaque, not trusted SRP groups. Boundary/cost
tests plus RSA envelope/identity and real prelude/challenge gates passed6/6,
zero skips/failures,1.100 seconds:
`/tmp/aetherscreens-srp-challenge-final-source-tests-20261008.log`.
A final real rerun additionally asserts generator5/modulus512 in
`/tmp/aetherscreens-srp-challenge-verified-final-tests-20261008.log`.
Earlier failed probes are retained in `/tmp/aetherscreens-srp-challenge-live-20261008.log`,
`/tmp/aetherscreens-srp-challenge-selector-live-20261008.log`,
`/tmp/aetherscreens-srp-challenge-fresh-socket-live-20261008.log`,
`/tmp/aetherscreens-srp-challenge-envelope-live-20261008.log`, and
`/tmp/aetherscreens-srp-challenge-alternate-live-20261008.log`.
The first fixture-suite compilation had a test-expression formatting error;
it was corrected before the successful final suite.

Current iOS build: `/tmp/aetherscreens-srp-challenge-ios-build-20261008.log`.
It completed BUILD SUCCEEDED, terminal exit0. Final generator5/modulus512 real
rerun passed6/6, zero skips/failures,1.127 seconds. macOS build also passed,
terminal exit0: `/tmp/aetherscreens-srp-challenge-mac-build-20261008.log`.
Scoped whitespace checks passed; both test sockets were canceled/handlers cleared.
Production selection remains type30. Trusted group/algorithm checks, PBKDF2/SRP
math, mutual proofs, session/wrap keys and complete actual type33/native push/
cursor are still missing or unaccepted. Earlier448 full suite predates these
helpers. No commit/push/release; physical/full Screens fluidity remains open.

## RSA1 public-key validation and local identity encoding (2026-10-08)

Previous prelude iOS build completed successfully, terminal exit0:
`/tmp/aetherscreens-rsa1-prelude-ios-build-20261008.log`.
Added independent bounded/canonical DER parsing for rsaEncryption SPKI with
NULL parameters, zero-unused-bit RSA key wrapper, positive RSA-2048 modulus and
bounded odd exponent. Security.framework imports the extracted PKCS1 public
key and verifies RSA-PKCS1 encryption support. SHA256 fingerprint is available
in memory only; structural validity does not establish host trust.
Local identity encoding validates UTF8 byte length/nonempty/noNUL, encodes both
32-bit lengths, encrypts using RSA-PKCS1 and produces the bounded RSA1 packet
(256 ciphertext bytes plus384 zero tail,650-byte body). No password is in this
identity packet. No identity packet was sent to the remote host in this phase.

Independent decryption test uses a nonpersistent temporary RSA key, verifies
the decrypted UTF8 fixture/lengths, envelope/tail, length boundaries and rejects
malformed/oversized/unsupported-algorithm keys. Actual credential-free TCP gate
also imports the real Mac mini's294-byte SPKI through this validator.
Final targeted suite passed3/3, zero skips/failures,0.807 seconds:
`/tmp/aetherscreens-rsa1-identity-live-final-20261008.log`.
Initial source iOS build succeeded, exit0:
`/tmp/aetherscreens-rsa1-identity-ios-build-20261008.log`.
Final-source build reruns have separate logs
`/tmp/aetherscreens-rsa1-identity-mac-final-build-20261008.log` and
`/tmp/aetherscreens-rsa1-identity-ios-final-build-20261008.log`.
Both reached terminal exit0: macOS build0.83 seconds, iOS BUILD SUCCEEDED.
Scoped whitespace checks also passed.
Source remains unwired to production authentication; type30 defaults unchanged.
SRP challenge/cost validation, client/server proofs, wrap-key derivation and
actual complete type33 authentication/stream remain missing. Earlier448 full
regression predates these new helpers. No commit/push/release or physical/full
Screens acceptance claim.

## Credential-free RSA1/type33 prelude (2026-10-08)

Current client selects type30 for Mac accounts, including experimental native
sessions; RSA-SRP type33 is not implemented. Readonly actual type33 discovery
returned offers[30,33,36,31,32,2,35] and a301-byte public-key response containing
294 DER bytes; no username/password sent. This difference from the native
[reference transcript](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md#424-type-33-rsa1--rsa-srp)
is a missing authentication capability, not proof of the push-failure cause.

Added an independent credential-free RSA1 key-request/envelope helper, bounded
to8192 response bytes with lengths, mixed endianness, exact framing and trailing
byte validation; size is checked before making a copy. Extraction does not claim
RSA key validity/trust. Tests reject truncated, oversized and modified framing.
An actual Swift/NWConnection gate uses the same helper and closes after discovery,
never sending identity/password or entering a desktop session. First real suite
passed2/2, zero skips/failures,3.164 seconds:
`/tmp/aetherscreens-rsa1-prelude-live-tests-20261008.log`.
Final allocation-bound check rerun/build are recorded separately in
`/tmp/aetherscreens-rsa1-prelude-live-final-20261008.log` and
`/tmp/aetherscreens-rsa1-prelude-ios-build-20261008.log`.
Final allocation-bound source actual rerun passed2/2, zero skips/failures,
0.640 seconds. iOS build remains live/pending at this checkpoint (tool session
38057); previous builds are not new-source build acceptance. Scoped whitespace
checks passed. Existing type30 selection/defaults remain unchanged. RSA validation/trust,
identity encryption, bounded SRP challenge/cost, mutual proofs and full real
type33 authentication/stream acceptance remain unimplemented/unaccepted.
No commit/push/release; full Screens and physical fluidity remain open.

## Rejected post-first-pixel arming experiment (2026-10-08)

Tested a separately opted-in, one-time AutoFrameBufferUpdate re-arm after the
first genuine native pixel update; no periodic polling or extra full requests.
Actual controlled-pattern gate failed1 case/3 assertions, zero unexpected
failures,67.769 seconds: one genuine4K image at6.328 seconds, one owned state,
then no further pixel updates during60 seconds. The post-frame arm was queued
(not acknowledged). Log: `/tmp/aetherscreens-post-frame-arm-live-20261008.log`.
Local wire/deadline4/4 passed before the experiment, but this does not override
the actual negative result. The speculative flag/callback/arming branch were
removed after failure. No production behavior is promoted from this experiment.
The owned producer was stopped using a fresh exact-command PID lookup; its
binary/directory were removed and absence verified (exit0). Final restoration
check: `/tmp/aetherscreens-post-frame-arm-reverted-tests-20261008.log`.
Server-send prerequisites/negotiation remain unresolved; native push/cursor and
all full Screens/physical-fluidity requirements remain open. No commit/release.

## Controlled ordinary/native pixel-region comparison (2026-10-08)

Actual ordinary RGB565 pattern acceptance passed1/1, zero skips/failures,
67.741 seconds. First genuine4K image at6.658 seconds, seven distinct pattern
states and11 decoded updates intersecting the owned window; final pixel-update
counter75. Stdout/test-report interleaving split one callback line, so only74
complete frame log lines parse; this is not an image/FPS count. Owned-region
update intervals had median5.523 seconds/max9.188 seconds (includes source,
server, transport and decoding; not input lag or display FPS). The strict
30-second span/20-second freshness gate passed, but these sparse updates are
not smooth animation. Log:
`/tmp/aetherscreens-pattern-regions-live-20261008.log`.
Readonly Tailscale ping reported DERP132ms, direct route unavailable (exit1);
network differs from earlier probes, so these runs are not controlled performance
A/B. The exact owned first producer PID97393 was stopped after the test.

Native encrypted Observe pattern probe failed1 case/3 strict pattern assertions,
zero unexpected failures,68.009 seconds: first genuine4K image at6.606 seconds,
one full request, one pixel/owned-region update and one matched state, then no
further pixels during60 seconds. Control records continued to arrive. Log:
`/tmp/aetherscreens-pattern-regions-native-live-actual-20261008.log`.
An earlier invocation used an incorrect opt-in name and skipped1 case; that log
(`/tmp/aetherscreens-pattern-regions-native-live-20261008.log`) is not acceptance.
The correctly opted-in run above is the actual result. Its producer completed170
seconds/170 ticks/170 draws, exit0.

Added an internal metadata-only status-command observer with a source-connection
guard after callbacks. Actual status probe reproduced one pixel update/one
matched state (first image6.430 seconds), failed1 case/3 assertions,68.122 seconds
and logged28 commands, all4; no11 or12 observed. Command4 remains unknown in
the independent [protocol memo](https://github.com/renegadelink/iShareScreen/blob/9ab40d3a3151524f954cff9d6239d891197c1705/docs/apple_vnc_rfc.md#821-server-to-client-control-messages-non-encoding),
so no session-change/heartbeat/re-arm action is inferred from it. Log:
`/tmp/aetherscreens-native-status-pattern-live-20261008.log`.
The observer's transport/reconnect tests and local matcher passed15/15, zero
skips/failures,15.362 seconds:
`/tmp/aetherscreens-native-status-command-tests-final-20261008.log`.

Added a separately opt-in internal normal-control SetMode wire profile for native
experiments; it sends no keyboard/pointer events in this gate and leaves public
constructor/production defaults unchanged. Guard rejects this QA option unless
native cursor/encryption are explicitly opted in. Prelude/control/reconnect/
matcher tests passed17/17, zero skips/failures,15.442 seconds:
`/tmp/aetherscreens-native-control-mode-targeted-20261008.log`.
Actual normal-control pattern probe still failed1 case/3 assertions,68.261 seconds:
first genuine4K image6.590 seconds, one pixel/owned-region update and one state;
no subsequent pixels over60 seconds. Mode selection is not proof of remote input
permission or cursor acceptance. Log:
`/tmp/aetherscreens-native-control-pattern-live-20261008.log`.
Its producer automatically completed170 seconds/170 ticks/170 draws, exit0;
a later stop attempt found that exact old PID already absent. All owned remote
files/directory were removed and absence verified, exit0. Normal-control
generic iOS Simulator build succeeded, terminal exit0:
`/tmp/aetherscreens-native-control-mode-ios-build-20261008.log`.
The prior status-only iOS build also succeeded. Scoped whitespace check passed.
Final full core regression passed448 cases,12 explicit environment skips,
zero failures/unexpected failures,130.229 seconds:
`/tmp/aetherscreens-native-control-mode-full-core-20261008.log`.
Skipped live/device gates remain unaccepted.
Final macOS `swift build` passed, exit0,0.95 seconds:
`/tmp/aetherscreens-native-control-mode-mac-build-20261008.log`.
Startup arming timing, native control/input/cursor, layout and all physical/full Screens gates remain
open. No commit/push/release.

## Controlled-pattern geometry and phase correction (2026-10-08)

Ordinary controlled-pattern run after the transfer repair failed: 1 case,
4 assertions, zero unexpected failures, 121.777 seconds. It received its first
genuine 4K frame at 68.509 seconds after connect invocation and 9 callbacks,
but zero matched states. Log:
`/tmp/aetherscreens-standard-progress-pattern-live-20261008.log`.
The old QA waiter incorrectly included authentication in its 60-second pixel
window and continued into stability checks after timeout. QA now independently
waits for initialization, then a genuine frame; any timed-out waiter returns
immediately. The application's bounded transfer deadline is unchanged.

Owned-window metadata proved a coordinate mismatch: AppKit positioned the old
fixture content at x=118 rather than expected x=40, with the screen's visible
origin x=78 (side Dock). Geometry smoke exited 0:
`/tmp/aetherscreens-standard-pattern-geometry-smoke-20261008.log`.
The fixture now explicitly sets its screen origin to (120,40); a second actual
five-second smoke confirmed content rect {{120,40},{360,160}}, logical1920x1080,
backing2, 5 draws/5 ticks and clean automatic exit:
`/tmp/aetherscreens-positioned-pattern-geometry-smoke-20261008.log`.
Matcher sample coordinates moved accordingly; alpha, black border, known colors,
distinct-state count, 30-second change span and 20-second freshness gates stay
strict. Warning-as-error fixture compilation passed. Local positioned matcher
passed 1/1, zero skips/failures, 0.038 seconds.

Actual positioned ordinary run still failed the freshness gate: 1 case,
1 assertion, zero unexpected failures, 74.303 seconds. First genuine 4K frame
at 12.531 seconds; 48 callbacks; three distinct owned-pattern states, change
span at least 30 seconds, but last changed signature was 21.488 seconds old at
the end (must be less than20). Log:
`/tmp/aetherscreens-positioned-standard-pattern-live-20261008.log`.
The producer completed its bounded170-second lifetime, exit0, with170 ticks and
170 actual draw passes. Log:
`/tmp/aetherscreens-positioned-pattern-producer-20261008.log`.
This proves source drawing and received owned-state changes, not continuous
freshness or physical smoothness. Prior zero-match probes used invalid sampling
coordinates and cannot isolate native-push failure.

Added QA-only framebuffer revision/changed-region counts, including intersection
with the owned fixture rectangle, to distinguish empty callbacks from decoded
pixel updates in a future probe. No desktop content is retained or logged.
These diagnostics have not had a live run yet. Final local matcher compiled and
passed1/1, zero skips/failures:
`/tmp/aetherscreens-positioned-pattern-frame-evidence-tests-20261008.log`.
Owned remote binary files/directory removed and absence verified, exit0. Scoped
whitespace checks passed. Production app source/defaults are unchanged in this
QA-only phase; full447/build evidence above predates these harness edits.
Native controlled push/cursor, adaptive transport and physical/full Screens
acceptance remain open. No commit/push/release.

## Ordinary first-frame progress repair (2026-10-08)

Live ordinary RGB565 diagnostics showed 736,828 bytes in 269 receives at the
old deadline, last receive only 0.037 seconds earlier; total test 26.772 seconds,
one expected failure. Log:
`/tmp/aetherscreens-standard-transfer-evidence-20261008.log`.
Counts include handshake/metadata and alone do not prove pixel progress.

Ordinary RFB now shares the bounded first-frame transfer deadline: only explicit
pixel-body reads renew its 20-second stall allowance, with an absolute 60-second
limit after connected. Metadata/clipboard/handshake traffic cannot renew it.
Header-prefetched pixel bytes are counted once on entering the pixel body;
raw receive recursion cannot repeatedly renew old buffered bytes. Loading
progress callbacks are restricted to explicit pixel reads. Reconnect guards
remain around observer callbacks. Experimental native behavior/defaults remain
unchanged. The first delayed-pixel test exposed the prefetch edge and failed;
after repair the final targeted suite passed 6/6, zero skips/failures, 42.117
seconds, including a real TCP image completed at 22 seconds, no-pixel timeout,
reconnect progress and the absolute deadline. Log:
`/tmp/aetherscreens-standard-progress-deadline-tests-final-20261008.log`.

Actual ordinary RGB565 Mac mini acceptance passed 1/1, zero skips/failures,
89.399 seconds: first genuine 3840x2160 frame at 28.3379 seconds after connect
invocation, then 60-second connected observation and 23 frame callbacks total.
Subsequent callbacks can include empty updates, so this is not 23 distinct
images or measured FPS. No owned-pattern matcher was used in this run.
Log: `/tmp/aetherscreens-standard-progress-live-final-20261008.log`.
No claim of fast startup, continuous-pattern acceptance, native cursor/push,
visual quality or physical fluidity is justified. Final full core passed:
447 cases, 12 explicit environment skips, zero failures/unexpected failures,
150.185 seconds. Log:
`/tmp/aetherscreens-standard-progress-full-core-20261008.log`.
Generic iOS Simulator build succeeded, terminal exit 0:
`/tmp/aetherscreens-standard-progress-ios-build-20261008.log`.
macOS `swift build` also passed, terminal exit 0, 1.24 seconds:
`/tmp/aetherscreens-standard-progress-mac-build-20261008.log`. Scoped diff whitespace
check passed. No new host GUI or physical-device acceptance was performed.
Skipped live/device gates remain unaccepted; no commit/push/release.

## Ordinary-profile owned-pattern comparison (2026-10-08)

Added explicit `AETHERSCREENS_QA_STANDARD_PATTERN=1` acceptance without native
cursor/encryption opt-ins, using the same RGB565 pattern and strict freshness
matcher. Local matcher passed 1/1, zero skips/failures, 0.046 seconds:
`/tmp/aetherscreens-standard-pattern-matcher-tests-20261008.log`.
Actual ordinary RFB connection authenticated and reached connected, but failed
before receiving a desktop image within the existing first-frame deadline:
1 failure, zero unexpected failures, 29.883 seconds total. Log:
`/tmp/aetherscreens-standard-pattern-live-20261008.log`.
The pattern-continuity assertion was therefore not reached. This cannot isolate
native push behavior, geometry mismatch or sharing-surface identity; ordinary
first-frame delivery and transport latency require further diagnosis. The
deadline was not relaxed. No production profile/default changed and no fluidity
acceptance is claimed. Stopped the exact owned fixture PID 40441 (exit 0).
The first cleanup SSH banner timed out; retry with a bounded 15-second connection
timeout removed the owned binary/directory and verified absence (exit 0).

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

## Reentrant metrics publication corrected (2026-10-08)

Main-thread metric publications now drain serially. Combine @Published sends
before storing a value: a synchronous subscriber could previously publish a
newer latency or reset, then have the outer setter overwrite it. New regressions
cover both cases; all 15 PerformanceMetricsTests passed with zero failures.
Evidence: /tmp/aetherscreens-metrics-reentrant-tests-20261008.log.
This is model-level verification, not rendered FPS or physical-device acceptance.
Full alignment, native file transfer and real-device fluidity remain incomplete.
No application commit, push or release. Goal remains active.

## Native file-copy envelope located (2026-10-08)

Read-only Mac-mini static disassembly identifies client-to-server RFB type0x22
through its dispatch table and the six-byte prefix plus big-endian version,
command and session-ID fields. Receiver-helper framing is native-endian IPC;
it must not be mistaken for wire framing. Full evidence and instruction
addresses are recorded in native-file-transfer-research.md.
Internal offline envelope decoder added; 4 synthetic tests passed, zero failures:
/tmp/aetherscreens-file-copy-envelope-tests-20261008.log. Covers every partial
frame boundary, coalescing, sliced Data indices and bounded invalid lengths.
No packet sent, file transferred, helper launched or user file accessed.
Reverse-direction grammar, capability/drag negotiation and real transfer
integrity remain open. No app commit/push/release. Goal remains active.

## Native reverse transfer status located (2026-10-08)

Static server construction now verifies reverse type0x22, version1 status
commands300 (big-endian double fraction) and200 (signed error, bounded raw
name bytes and NUL). Receiver-helper arithmetic distinguishes fraction from
percentage; queued output follows the server's encrypted-record path. Details
and instruction addresses: native-file-transfer-research.md.
Offline envelope renamed AppleFileCopyMessage after verifying both directions;
AppleFileCopyServerStatus handles exact session/version and rejects malformed
status bodies. Progress1 is not completion; final result requires command200.
All8 envelope/status tests passed, zero failures:
/tmp/aetherscreens-file-copy-status-tests-20261008.log. Synthetic packets only.
No RFBClient integration, capability advertisement or live transfer enabled.
Real negotiation, metadata/data/forks/compression and byte-integrity gates remain
open. No user files read, remote changes, app commit/push/release. Goal active.

## Native file-data body validation (2026-10-08)

Static receiver/sender evidence identifies raw command102 and compressed
command103 body fields. Added offline AppleFileCopyDataBlock validation with
exact lengths, active-fork remainder and expanded-size bounds. Compressed
bytes stay opaque pending verified inflater lifecycle. Source instruction
addresses recorded in native-file-transfer-research.md.
All12 envelope/status/data tests passed, zero failures:
/tmp/aetherscreens-file-copy-data-tests-20261008.log. Synthetic framing only;
not real transfer acceptance. Native item/fork negotiation, decompression,
filesystem writing and drag/drop integration remain open. No user file access,
packet sending, remote change, app commit/push/release. Goal remains active.

## Experimental native file-copy inflater verified (2026-10-08)

Static sender/receiver evidence establishes persistent Z_SYNC_FLUSH block
state. Added an isolated bounded AppleFileCopyInflater without framebuffer
dictionary sharing or automatic mid-stream reset. Errors invalidate the
context; exact expansion and flush completion are required.
All16 AppleFileCopy tests passed, zero failures:
/tmp/aetherscreens-file-copy-inflater-tests-20261008.log. New tests expand
actual synthetic zlib across dictionary-dependent blocks and interleaved raw
data, reject truncation/corruption/trailing bytes/dishonest sizes, and verify
post-error rejection. No native captured packet or live file transfer verified.
Negotiated transfer/item/fork reset boundaries, actual writer and drag/drop
integration remain open. No remote change, user-file access, app commit/push
or release. Goal remains active.

## Native-transfer iOS compilation and item-name evidence (2026-10-08)

Current generic unsigned iOS build succeeded, including new file-copy codecs
and persistent inflater: /tmp/aetherscreens-file-copy-ios-build-20261008.log.
This is compilation only, not signed installation or physical-device QA.
Static sender new-item construction confirms UTF-8 name conversion and legacy
slash-to-colon translation, plus optional symlink handling. Recorded instruction
addresses and remaining receiver/hierarchy/reset questions in
native-file-transfer-research.md. No per-item inflater reset inferred or enabled.
Real native transfer, file writing/metadata/forks and drag/drop UI remain open.
No remote mutation, user-file read, app commit/push/release. Goal remains active.

## Native new-item framing parsed (2026-10-08)

Sender/receiver static offsets agree on command101 name/hierarchy/link framing.
Added AppleFileCopyItem to preserve catalog header, Unicode wire name, level,
optional link target and opaque extension bytes with strict boundary checks.
No name conversion, symlink creation or filesystem writing enabled. Complete
catalog/fork/attribute semantics and negotiated writer remain open.
All19 AppleFileCopy tests passed, zero failures:
/tmp/aetherscreens-file-copy-item-tests-20261008.log. Synthetic cases only,
not native transfer acceptance. No user-file access, remote changes, app
commit/push/release. Goal remains active.

- 2026-10-08: command-101 logical resource/data fork sizes and directory flags
  cross-checked against native sender and compiled SDK offsetof probe; exposed
  on AppleFileCopyItem. Item parser tests 4/4 passed. Native transfer is still
  experimental and not connected to session transport or real filesystem writes.

- 2026-10-08: verified name/link/extended-attribute append order in native sender.
  Added ext1 envelope decoding with malformed-length checks and opaque metadata
  preservation; combined AppleFileCopy tests 23/23 passed. Attribute table
  decoding, actual filesystem application and transport negotiation remain open.

- 2026-10-08: parsed offline native start commands 1/2 with raw path, flags,
  reserved bytes and length/NUL validation. Combined AppleFileCopy tests 26/26
  passed; generic unsigned iOS build passed (file-copy-start-ios-build log).
  Real capability negotiation and bidirectional transfer remain unverified.

- 2026-10-08: added bounded outbound Apple file-copy envelope encoding, verified
  against independent literal framing; AppleFileCopy tests 27/27 passed. Native
  server lazily initializes per-viewer sessions, but a verified capability
  advertisement is still missing; no live native-transfer support claim.

- 2026-10-08: decoded version-one extended-attribute tables using native receiver
  size/count/record/key/value evidence, preserving binary values and rejecting
  malformed bounds. AppleFileCopy tests 28/28 passed. Filesystem attribute writes,
  transport negotiation and actual file-integrity acceptance remain incomplete.

- 2026-10-08: fixed DeviceListViewModel discovery-status Combine retain cycle.
  The model owned a cancellable whose assign subscriber strongly retained the
  model, preventing library teardown. A lifecycle regression test reproduced
  the leak before the change and passed after a weak sink replaced assign.
  Identical discovery states no longer trigger redundant publication. Logs:
  /tmp/aetherscreens-library-lifetime-before-20261008.log (expected failure),
  /tmp/aetherscreens-library-lifetime-after-20261008.log (1/1 passed).
  This is lifecycle evidence, not measured device FPS or animation acceptance.

- 2026-10-08: session teardown now saves a final thumbnail only after an actual
  frame was received. Previously a failed/unopened attempt with an allocated
  framebuffer overwrote the last successful preview. A regression test proved
  an 8x8 prior preview was replaced by blank 2x2 data before the fix; it remains
  intact afterward. Preview lifecycle selection 3/3 passed (failed-attempt
  preservation, temporary-session exclusion, library-model release).
  Logs: /tmp/aetherscreens-empty-preview-before-20261008.log (expected failure),
  /tmp/aetherscreens-preview-lifecycle-after-20261008.log (passed).

- 2026-10-08: Performance HUD now displays unavailable FPS as an em dash until
  a valid drawable presentation exists in the current measurement generation.
  A measured idle screen can still show zero FPS. Simulator/fallback/initial
  state no longer imply a measured zero. All 15 PerformanceMetrics tests passed,
  including unavailable invalid/dropped presentations and reset/stale callbacks:
  /tmp/aetherscreens-fps-availability-tests-20261008.log. Physical presentation
  FPS and perceived UI fluidity still require device acceptance.
  Generic unsigned iOS build also succeeded with the recent library lifecycle,
  preview preservation and FPS availability changes:
  /tmp/aetherscreens-preview-fps-ios-build-20261008.log.

- 2026-10-08: refreshed the complete native Mac mini gate against the current
  compiled worktree: 536 tests, 16 explicit environment skips, three assertions
  failing in the single testMigratesLegacyKeychainPasswordOnRead case, 150.357s.
  The full gate remains FAILED; it must not be replaced by selected green tests.
  Current AppleFileCopy codecs, metrics (15/15), Metal renderer (5/5), library
  release and failed-attempt thumbnail preservation passed on that machine.
  Log: /tmp/aetherscreens-current-macmini-regression-20261008.log.
  No opt-in live clipboard/native transfer tests were enabled. The unique remote
  test directory was removed after checking its exact owned contents and test
  process completion. Physical iPhone/visual/presentation acceptance remains open.

- 2026-10-08: native ordinary-file data-before-resource ordering cross-checked
  against receiver fork-open/close paths. Added acknowledged-write fork accounting
  with zero-size handling, boundary rejection and UInt64 overflow avoidance.
  AppleFileCopy tests 31/31 passed; real writer and transfer acceptance remain open.

- 2026-10-08: ordinary-file receive staging now performs actual bounded disk
  writes through parsed blocks and transfer inflater, separately preserving data
  and resource bytes. Byte-exact raw/two-fork/compressed disk tests, cleanup,
  budget and overflow cases passed (AppleFileCopy selection 35/35). Generic
  unsigned iOS build succeeded: file-copy-staging-ios-build-20261008.log.
  Staging is not a final download; destination resource-fork/metadata commit,
  overwrite UI and real native transport negotiation still remain incomplete.

- 2026-10-08: Mac staging finish now restores the real resource fork using bounded
  streaming, validates its exact source length and rejects damaged staging.
  Actual data and named-resource-fork byte comparisons passed; AppleFileCopy
  selection 36/36 passed. iOS export, metadata and real transport still pending.

- 2026-10-08: Mac staging finish applies recognized extended attributes through
  its owned descriptor, with actual getxattr binary readback verification and
  unknown-format cleanup. AppleFileCopy tests 37/37 passed; final staging 6/6
  passed. Catalog Finder info/date/permissions, final destination and actual
  transport remain open; this does not establish full native transfer parity.

- 2026-10-08: Mac prepared-file commit uses an atomic exclusive rename. Existing
  files/symlinks are preserved and staging remains retryable on conflicts;
  successful cleanup preserves the committed data/resource forks. Initial
  AppleFileCopy selection passed 39/39. Cross-volume handling, catalog metadata,
  transport coordination, overwrite UI and real-device acceptance remain open.

- 2026-10-08: Added command-104 sender-end parsing with explicit missing-result,
  success and raw failure states. Malformed bodies cannot become success.
  AppleFileCopy selection passed 41/41. Live session coordination and physical
  transfer acceptance remain incomplete.

- 2026-10-08: FileTransferJob completion now requires explicit session success
  and destination finalization in addition to exact acknowledged bytes/current
  attempt. Its prior comment-only finalization requirement is enforced by the
  API. Missing either condition leaves the task active without consuming its
  token. Five job tests passed: transfer-completion-gate-tests-20261008.log.
  Transport and filesystem coordinator integration remains pending; callers
  must supply these facts from real acknowledgements and commit outcomes.

- 2026-10-08: Generic unsigned iOS build succeeded after end-session parsing,
  atomic Mac commit and the stricter task completion API:
  /tmp/aetherscreens-end-session-ios-build-20261008.log. This establishes build
  compatibility only, not iPhone installation or live transfer acceptance.
  RFBClient's message loop still has no file-copy dispatch; transport
  integration must preserve framed-message boundaries before enabling tasks.

- 2026-10-08: RFBClient recognizes native-banner type-0x22 messages, reads the
  five remaining prefix bytes, validates payload length 8...1 MiB before the
  payload read, decodes the exact frame and invokes an internal receive hook.
  No capability advertisement, outbound transfer or filesystem action is
  enabled. Invalid lengths fail the connection instead of swallowing later
  framebuffer bytes. Core compilation plus existing AppleFileCopy codec tests
  passed 41/41: file-copy-dispatch-build-tests-20261008.log. These codec tests
  do not yet exercise the new socket dispatch; a wire fixture remains required.

- 2026-10-08: Two local loopback TCP tests now exercise the actual RFBClient
  native file-copy dispatch. A command-104 frame followed by a standard
  clipboard frame in one TCP write delivers both callbacks with exact contents;
  a UInt32.max length prefix fails immediately without a payload. Tests use
  a synthetic server and callback text only, no native GUI or system clipboard.
  Both passed: /tmp/aetherscreens-file-copy-wire-tests-20261008.log. This proves
  framing and rejection on loopback, not Mac mini interoperability, fragmented
  delivery, negotiated capability or full file transfer.

- 2026-10-08: Native file-copy TCP coverage now includes deliberately delayed
  header/body fragments and a truncated body followed by server disconnect.
  Fragmented fields arrive byte-exact; incomplete bodies fail without invoking
  the file-copy callback. Four dispatch tests passed on loopback in
  /tmp/aetherscreens-file-copy-fragmented-wire-tests-20261008.log. These tests
  do not enable a live remote file-copy session or establish Screens parity.

- 2026-10-08: Current test bundle ran all 24 PointerTransportTests on the
  authorized Mac mini (macOS 27.0.1), including four native file-copy dispatch
  cases, mouse/keyboard chords, scroll cancellation, display switching and
  reconnect/close behavior. 24/24 passed in 41.444 seconds:
  /tmp/aetherscreens-macmini-file-wire-regression-20261008.log. The uniquely
  owned remote test bundle/archive directory was removed after terminal success.
  This is synthetic transport regression on the Mac mini, not a native server
  file transfer or iPhone UI acceptance. The earlier full-suite Keychain
  migration failure remains unresolved; no full-suite success is claimed.

- 2026-10-08: Added a DeviceStore-level deterministic denied-migration test.
  A failed write to the new credential service leaves the legacy credential
  usable, performs no deletion and allows repeated reads without repeated
  migration writes. It passed:
  /tmp/aetherscreens-device-migration-denied-tests-20261008.log. The original
  real Keychain integration test remains unchanged and failed at fixture
  persistence in the earlier Mac mini run; this additional test does not
  resolve or hide that full-suite/environment gate.

- 2026-10-08: Bonjour publishes resolved-device arrays only when contents
  change. DeviceListViewModel removes duplicate discovery emissions before
  scheduling them on the main queue and avoids assigning an equal view snapshot.
  This removes redundant device-library invalidations without suppressing
  changed hosts/ports/metadata. Core compilation and the existing model-release
  regression passed: /tmp/aetherscreens-discovery-refresh-tests-20261008.log.
  No measured frame-rate or physical-device animation acceptance is claimed.

- 2026-10-08: Saved-computer grid uses a scoped 0.22-second smooth animation
  for category changes and stored device identity changes, with opacity
  transitions for cards. Search text and live status/pixel updates are not
  animation triggers; search-in-progress and accessibility Reduce Motion
  disable this animation. Mac build passed:
  /tmp/aetherscreens-library-transition-build-20261008.log. Physical UI
  rendering/interaction acceptance remains pending; compilation does not
  establish perceived smoothness.

  Generic unsigned iOS build also succeeded for this change:
  /tmp/aetherscreens-library-transition-ios-build-20261008.log.

- 2026-10-08: Thumbnail JPEG encoding moved outside the shared storage lock.
  Persistence remains serialized against removal, with the removed-ID check
  after encoding, so a deleted computer cannot regain its preview. Existing
  save/downscale tests passed 2/2 and async-loading/snapshot lifecycle tests
  passed 9/9: thumbnail-encoding-lock-tests-20261008.log and
  thumbnail-encoding-lifecycle-tests-20261008.log. This shortens CPU work under
  the lock; atomic disk writes still serialize with removal. No measured UI
  latency reduction or physical-device smoothness is claimed.

- 2026-10-08: Computer search trims leading/trailing whitespace and newlines
  consistently before name/host matching. Pasted IPs and names no longer show
  false empty results, whitespace-only queries restore the original list, and
  search leaves stored order unchanged. The model-level regression passed:
  /tmp/aetherscreens-library-search-tests-20261008.log.

- 2026-10-08: Nearby Bonjour cards now follow the same normalized name/address
  query as saved computers. Visible counts and empty-state visibility use
  filtered nearby results; whitespace-only input uses the unsearched empty
  state and Add action. Search regression covers nearby names, addresses,
  whitespace and no-match preservation and passed:
  /tmp/aetherscreens-nearby-search-tests-20261008.log. Rendered/physical UI
  acceptance remains pending.

- 2026-10-08: Library error notices now offer dismissal. Error and success
  dismiss buttons use minimum 44-point hit areas, rectangular content shapes,
  localized accessibility labels and the existing Reduce Motion-aware press
  feedback. Mac build passed: /tmp/aetherscreens-library-notice-build-20261008.log.
  VoiceOver/touch and rendered banner layout acceptance remain pending.

- 2026-10-08: Unknown RFB server message types now fail explicitly instead
  of skipping the type byte and interpreting the unknown body as future
  messages. RFB has no universal length prefix, so continuation would lose
  frame boundaries. A TCP fixture with unknown type 255 and a body resembling
  a valid clipboard frame verifies failure and no false clipboard callback.
  It and four native file-copy framing tests passed 5/5:
  /tmp/aetherscreens-message-boundary-failure-tests-20261008.log. Supported
  vendor-message interoperability and rendered recovery acceptance remain open.

- 2026-10-08: Internal native file-copy sending now queues bounded encoded
  frames on the connection worker, checks connected/native-banner/control
  state and revalidates connection identity plus input generation before
  sending. Observe mode, disconnected state and oversized frames reject
  enqueueing; disabling/re-enabling control invalidates old queued messages.
  Exact TCP-wire and deterministic queued-cancellation fixtures passed with
  existing boundary cases, 7/7:
  /tmp/aetherscreens-file-copy-send-cancellation-tests-20261008.log. The method
  means queued only, not remote acknowledgement. There is no public transfer
  UI or capability advertisement; the coordinator must still negotiate its
  actual session/command before invoking it. No real native server transfer
  was attempted or accepted.

- 2026-10-08: Added ordinary-file receive-session coordination with aggregate
  byte/item quotas, real sequential fork staging, explicit sender-end success,
  owned cleanup and prepared-file ownership transfer. Actual disk/budget/failure
  tests passed with AppleFileCopy selection 44/44:
  /tmp/aetherscreens-file-copy-receive-session-tests-20261008.log. RFB/UI bridge,
  directories/symlinks, catalog metadata and native server acceptance remain
  open; this helper does not enable or complete full file transfer parity.

- 2026-10-08: Receive-session tests now verify a dictionary-dependent compressed
  second file across the first file's preparation boundary, with exact disk
  readback. Four session tests passed: cross-item-compression-tests-20261008.log.
  Static helpers use initialization flags with no named reset call found; real
  cross-item native compression compatibility remains unverified.

- 2026-10-08: Added a dedicated bounded receive worker (4 MiB pending wire
  budget by default), preserving message order and keeping staging/decompression
  off the connection worker when integrated. Cancel/overflow close admission
  and remove only owned staging; reentrant end cancellation prevents handoff.
  Worker/session tests passed 8/8:
  /tmp/aetherscreens-file-worker-cancellation-tests-20261008.log. Product
  coordinator installation and actual-server transfer remain incomplete.

- 2026-10-08: RFBClient now supports explicit negotiated receiver installation
  and identity-checked removal. Disconnect/failure cancels its owned receive
  worker. Matching item/data/end frames go to the file worker while final
  status/control remains on the owner hook. Loopback integration verifies
  control responsiveness during blocked file work, exact fork bytes, final
  result readability and disconnect cleanup. 12/12 selected tests passed:
  /tmp/aetherscreens-file-receiver-lifecycle-tests-20261008.log. Public UI,
  negotiation, full metadata and actual-server acceptance are still open.

- 2026-10-09: Current complete test bundle ran on the authorized Mac mini:
  569 tests, 16 explicit environment/opt-in skips, three assertion failures
  in the single test DeviceStoreTests.testMigratesLegacyKeychainPasswordOnRead,
  151.773 seconds. The initial legacy fixture save failed, followed by both
  expected password assertions. No other assertion failure occurred. This
  supersedes the earlier 536-test full run; the full gate remains FAILED.
  Evidence: /tmp/aetherscreens-full-current-regression-20261008.log. The owned
  remote test archive/bundle directory was removed after terminal exit 1.
  Generic unsigned iOS build with current receive worker/lifecycle and library
  changes succeeded: /tmp/aetherscreens-receive-worker-ios-build-20261008.log.
  Neither build nor synthetic regressions establish live file transfer,
  physical UI fluidity or complete Screens parity.

- 2026-10-09: A direct Security.framework probe in the authorized Mac mini SSH
  session returned SecItemAdd OSStatus -25308 (User interaction is not allowed)
  for a uniquely named synthetic fixture; no item was created. This explains
  the fixture write failure in the complete regression, but does not establish
  behavior in a signed interactive app session. The full test gate stays FAILED;
  the real migration test remains unchanged. KeychainStore now records only
  the numeric system status on failed writes, with no password, service or
  account identifiers. The eight injected KeychainWriteTests pass:
  /tmp/aetherscreens-keychain-diagnostics-tests-20261009.log. Interactive
  Keychain migration acceptance is still pending.

- 2026-10-09: RemoteDesktopView now animates first-frame loading HUD insertion
  and removal in its own overlay container (0.18-second ease-out), keyed only
  by waiting-for-first-frame state. Download progress, framebuffer rendering
  and pointer transport do not trigger that animation. Reduce Motion disables
  it. macOS build passed: /tmp/aetherscreens-first-frame-hud-build-20261009.log.
  Generic unsigned iOS build also passed:
  /tmp/aetherscreens-first-frame-hud-ios-build-20261009.log.
  Rendered transition and physical-device fluidity acceptance remain pending.

- 2026-10-09: First-frame HUD now fits within the available width with 16-point
  side margins (maximum width 360), uses Dynamic Type text styles and wraps
  progress labels. Retry/password/log recovery actions have at least 44-point
  label height. macOS build passed:
  /tmp/aetherscreens-recovery-layout-build-20261009.log. Narrow-window,
  landscape and accessibility-size rendered acceptance remains pending.
  Generic unsigned iOS build passed as well:
  /tmp/aetherscreens-recovery-layout-ios-build-20261009.log.

- 2026-10-09: File receive worker admission now limits queued/in-flight message
  count to 256 as well as wire bytes to 4 MiB. Tiny messages can no longer create
  hundreds of thousands of queued closures below the byte budget. Count overflow
  closes admission and cleans the owned session through the existing serial
  failure path. Five worker tests passed, including a suspended-queue count
  overflow below the byte budget:
  /tmp/aetherscreens-file-worker-count-budget-tests-20261009.log.
  Eight synthetic TCP file-copy integration tests also passed, including
  following-control responsiveness and disconnect cleanup:
  /tmp/aetherscreens-file-worker-count-wire-tests-20261009.log.
  Actual-server negotiation, public transfer UI and native acceptance remain open.

- 2026-10-09: Added a receive-worker regression proving a processed message
  releases its queue-count slot: with a one-message limit, an item followed by
  sender-end still completes and removes its staging files. Combined worker,
  relative-path and staging-file regression passed 17 tests, covering literal
  Unicode/percent filenames, traversal rejection, overwrite conflicts, resource
  forks, extended attributes and cancellation:
  /tmp/aetherscreens-file-receive-path-regression-20261009.log.
  This is local filesystem/synthetic coverage, not actual-server file-transfer
  acceptance or full Screens parity.

- 2026-10-09: Session viewport panning now publishes only changed offsets.
  Repeated outward movement against a clamped desktop boundary no longer
  invalidates SwiftUI through identical @Published values. The regression
  observes exactly one offset publication for the initial clamp plus 100
  outward samples, then confirms immediate inward movement. Seven session
  recovery/viewport tests passed:
  /tmp/aetherscreens-viewport-boundary-tests-20261009.log.
  Hardware pointer and physical iPhone gesture acceptance remain pending.

- 2026-10-09: Remote canvas now persists its clamped viewport offset when pan
  limits change (zoom, rotation, window size or display). Previously only the
  rendered offset was clamped, allowing a later zoom-in to restore stale pan.
  Regression verifies smaller limits, fit-to-window zeroing and later expansion
  preserving the centered position. Seven viewport/recovery tests passed:
  /tmp/aetherscreens-viewport-resize-tests-20261009.log.
  Rendered rotation/zoom and physical-device acceptance remain pending.

- 2026-10-09: Combined input/cursor/viewport/file-transfer regression passed
  101 tests with zero failures, covering recent viewport clamp/publication
  changes together with bounded file-receive work:
  /tmp/aetherscreens-input-transfer-regression-20261009.log.
  These are model, unattached input-view, filesystem and synthetic checks;
  they do not establish physical-device interaction or actual-server transfer.
  Current generic unsigned iOS build also passed:
  /tmp/aetherscreens-integrated-ios-build-20261009.log.

- 2026-10-09: Scroll accumulation clears fractional remainders when switching
  between precise trackpad and discrete mouse-wheel events. A mouse notch can
  no longer cancel against an unfinished trackpad tick. The added regression
  covers both axes and switching back while preserving subsequent precise
  accumulation. Thirteen native input logic tests passed:
  /tmp/aetherscreens-scroll-device-switch-tests-20261009.log.
  These tests use unattached input views; real device scroll feel remains pending.

- 2026-10-09: macOS scroll gesture begin/cancel clears fractional accumulation,
  matching the existing iOS gesture-begin behavior. Cancelled events emit no
  wheel clicks; gesture end does not reset, retaining the momentum handoff.
  Existing 13 native input logic tests and compilation passed:
  /tmp/aetherscreens-scroll-gesture-boundary-tests-20261009.log.
  These tests do not synthesize AppKit gesture phases; actual trackpad phase
  and momentum acceptance remains pending on the authorized Mac mini.

- 2026-10-09: Added synthetic CGEvent-to-NSEvent scroll-phase coverage through
  the unattached MacNativeInputView. It confirms new gesture remainder reset,
  cancelled-event suppression and ended-to-momentum remainder handoff. The
  fixture explicitly checks AppKit phases (their raw values differ from CG
  phase fields). Fourteen native input tests passed:
  /tmp/aetherscreens-scroll-phase-fixture-tests-20261009.log.
  This supersedes the missing synthetic phase coverage above; real trackpad
  and remote-server feel acceptance is still pending.

- 2026-10-09: Current compiled bundle ran selected input tests on the authorized
  Mac mini (100.64.0.3): 21 native-input/viewport/session-recovery tests passed,
  zero failures. This includes synthetic AppKit scroll phases and recent
  viewport publication/clamp changes. Terminal xctest exit was zero:
  /tmp/aetherscreens-macmini-input-qa-20261009.log.
  Owned remote test directory/archive were removed after verifying their exact
  contents. No native desktop interaction or physical iPhone acceptance is
  implied by these unattached-view/model tests.


## 2026-10-09 upload lifecycle checkpoint

- 文件总量编码、原生文件类型校验、单报文在途的后台上传发送器已实现；RFB 可显式安装发送器、分发对应会话回执，并在断线/失败时取消。
- 135 项文件传输及 TCP 回归通过，iOS unsigned generic 构建通过。
- Mac mini 原生接收辅助程序的直接启动被 AMFI launch constraint 阻止；正式服务认证后的启动/保存目录协商、真实文件接收、公开传输 UI 与 iPhone 流畅度仍未验收。完整回归的 Keychain SSH 失败仍未关闭。


## 2026-10-09 unchanged viewport update correction

MacNativeInputView no longer clears pending edge-follow pan when SwiftUI
resends unchanged viewport geometry during an unrelated frame/toolbar update.
Pending pointer correction is retained until actual viewport geometry changes.
The consecutive-edge-sample test now interleaves a stale geometry assignment;
it verifies one clamped pan and continuous corrected pointer mapping before
and after layout applies it. MacNativeInputTests + ViewportTrackingTests passed
19/19 on the host (/tmp/aetherscreens-stale-viewport-tests-20261009.log) and on
the authorized Mac mini (/tmp/aetherscreens-viewport-mini-tests-20261009.log).
These are CLI tests with unattached native views, not GUI automation or physical
pointer/perceived-animation acceptance. Exact owned remote QA bundle/archive
were validated and removed. git diff --check passed. This is macOS-only code;
no iOS behavior change or new physical-device acceptance is claimed.


## 2026-10-09 iOS projected canvas retention

RemoteTouchView now separates the last supplied SwiftUI layout from its immediate
locally panned canvas through ViewportProjection. Repeated unchanged layout
updates retain pending touch/hardware-pointer edge pan; changed geometry applies
normally after pan, resize or zoom. Both immediate edge-pan paths use this same
projection, avoiding rollback between touch samples and the SwiftUI update.
Shared geometry tests cover clamped-edge continuation across a stale layout,
actual layout acknowledgement, and reset after resize/zoom. The input/viewport
selection passed 21/21 (/tmp/aetherscreens-touch-projection-tests-20261009.log).
This tests the platform-independent projection and existing macOS input paths;
it does not execute UIKit gestures or establish iPhone perceived smoothness.

Generic unsigned iOS build passed with the UIKit integration
(/tmp/aetherscreens-touch-projection-ios-build-20261009.log); git diff --check
passed. Physical iPhone edge-follow/zoom/rotation acceptance remains pending.


## 2026-10-09 pinch anchor preservation

UIKit pinch now supplies its local gesture location to remoteCanvas. Zoom offset
preserves the remote point beneath that anchor across successive scale changes,
then clamps each axis to available desktop bounds. Fitting/letterboxed axes stay
centered and zooming out to fit clears excess offset. Unchanged scale/offset no
longer publishes duplicate updates. This local navigation does not emit remote
pointer events; holding-button release at pinch start is retained.
ViewportZoom/ViewportTracking selected tests passed 9/9
(/tmp/aetherscreens-pinch-anchor-tests-20261009.log), covering off-center anchor
invariance at successive zoom levels and zoom-out boundary/fit behavior. These
are geometry tests; UIKit recognizer timing, two-finger motion and physical
perceived smoothness remain pending on iPhone 12 Pro.

Generic unsigned iOS build passed with the anchored pinch callback
(/tmp/aetherscreens-pinch-anchor-ios-build-20261009.log). git diff --check passed.


## 2026-10-09 macOS native magnification entry

MacNativeInputView now handles NSEvent magnification through an optional
representable callback, converting AppKit's bottom-up local point into the
visible viewport anchor. remoteCanvas reuses anchored ViewportZoom calculation
and the existing fit/actual-size zoom bounds. A cancelled gesture or zero,
nonfinite or invalid magnification is ignored; a held remote mouse button takes
priority and suppresses local zoom until release. Magnification sends no remote
pointer events. No whole-canvas animation is added to interactive gesture samples.

MacNativeInput/ViewportTracking/ViewportZoom tests passed 25/25 on the host
(/tmp/aetherscreens-mac-pinch-final-tests-20261009.log) and authorized Mac mini
(/tmp/aetherscreens-mac-pinch-mini-tests-20261009.log). Tests exercise callback
anchor conversion and real synthetic NSEvent mouse down/up routing for drag
priority, plus shared geometry. Actual OS-delivered trackpad magnification and
perceived smoothness still require GUI acceptance. Mac swift build passed
(/tmp/aetherscreens-mac-pinch-build-20261009.log); git diff --check passed.
Owned remote bundle/archive were validated and removed.


## 2026-10-09 system Reduce Motion for model actions

SessionViewModel's fullscreen and double-tap zoom actions now read the current
system Reduce Motion preference on each invocation (UIKit UIAccessibility or
AppKit NSWorkspace). With Reduce Motion enabled, the explicit animation is nil;
otherwise the existing fullscreen ease-in-out and zoom spring remain. Layout
publication before input identity rebuild and held-button release ordering are
unchanged. Interactive pinch and edge-pan paths do not add an animation.
Mac swift build passed (/tmp/aetherscreens-motion-mac-build-20261009.log).
No system accessibility preference was changed for validation. Actual enabled/
disabled appearance and interruption behavior remain GUI acceptance items.

Generic unsigned iOS build passed (/tmp/aetherscreens-motion-ios-build-20261009.log)
and git diff --check passed. No new GUI/perceived-animation acceptance is claimed.


## 2026-10-09 cursor accessibility allocation path

RemoteTouchView.updateCursor no longer creates UIAccessibilityCustomAction or
localizes full-screen labels on each cursor movement. Accessibility content is
initialized immediately and refreshed by representable updates only when the
full-screen state or resolved language changes. The canvas accessibility label
also refreshes after an in-app language change. Cursor position, colors, hidden
state and disabled implicit layer actions remain in the cursor path. No measured
latency/FPS gain is claimed; physical VoiceOver and rapid pointer movement
acceptance remain pending.

The first iOS build caught a cache field name collision with UIKit
accessibilityLanguage; renamed it cachedAccessibilityLanguage. Final generic
unsigned iOS build passed
(/tmp/aetherscreens-cursor-accessibility-final-ios-build-20261009.log), and
git diff --check passed. Physical VoiceOver/pointer-flow acceptance remains open.


## 2026-10-09 default cursor rendering and physical-device readiness

Rendered the current PointerArrowShape.path through CoreGraphics using the
RemoteCursorLayer fallback's white fill, black 1.5-point stroke and rounded
joins. Inspected /tmp/aetherscreens-default-arrow-20261009.png: the fallback is
an arrow, not a circle. RemoteCursorLayer retains this fallback when shape/image
is absent and honors explicit server-hidden cursor states. No cursor shape code
was changed based on this check. Cursor decode/cache selected tests passed
12/12 (/tmp/aetherscreens-cursor-current-tests-20261009.log).

A current devicectl inventory distinguishes physical and simulated iPhone 12 Pro
entries. The paired physical device reports localNetwork transport with tunnel
state disconnected, so physical cursor/zoom/input acceptance cannot run now.
The user was asked whether to reconnect/unlock for acceptance or continue code
first. The render is source-level fallback evidence, not a screenshot from the
phone or proof that a server-provided bitmap cannot show a different cursor.
The live cursor complaint and full Screens parity remain unaccepted.


## 2026-10-09 UIKit system-pointer overlap handling

RemoteTouchView now installs UIPointerInteraction and supplies hidden style
when a remote trackpad engine is present and local-navigation mode is off.
RemoteCursorLayer remains responsible for the server cursor/default arrow;
local pan/Observe mode returns the system default style. Engine availability
and local-navigation changes invalidate the interaction so style can refresh
without requiring the hardware pointer to leave/re-enter the canvas. Other
controls do not install this hidden style. Existing UIHoverGestureRecognizer
still maps hardware motion independently of pointer presentation.

Apple documents hidden() as hiding the pointer over the current interaction
region: https://developer.apple.com/documentation/uikit/uipointerstyle/hidden()
This addresses a possible system-dot/custom-arrow overlap, not a confirmed root
cause from the offline iPhone. Physical iPhone/iPad mouse entry/exit, Observe,
pan, toolbar hover and AssistiveTouch behavior remain acceptance gates. No live
GUI or global cursor preference was changed for validation.

The custom pointer region is restricted to the visible intersection of canvas
and input-view bounds; letterbox/empty space keeps the system pointer. Supplied
canvas changes invalidate the interaction when its visible region changes.

Final generic unsigned iOS build passed with the region-scoped pointer
interaction (/tmp/aetherscreens-system-pointer-final-ios-build-20261009.log),
and git diff --check passed. Physical pointer/AssistiveTouch acceptance remains
open; compilation does not prove the offline phone complaint is resolved.


## 2026-10-09 pointer region after bounds updates

RemoteTouchView caches its visible pointer region and refreshes it both after
supplied canvas changes and in layoutSubviews. This covers SwiftUI supplying
new canvas coordinates before UIKit applies new bounds during rotation/resize.
Only a changed canvas/bounds intersection invalidates UIPointerInteraction;
unchanged layout passes do not trigger repeated pointer style recalculation.
The region delegate still computes current geometry on demand. This is a UIKit
layout-lifecycle correction; physical rotation, resize and pointer entry/exit
remain acceptance items while iPhone 12 Pro is disconnected.

Generic unsigned iOS build passed
(/tmp/aetherscreens-pointer-resize-ios-build-20261009.log), and git diff --check
passed. No live-device pointer/rotation acceptance is claimed.

### 2026-10-09 边缘跟随时同步系统鼠标区域

- `RemoteTouchView` 的触摸与硬件鼠标边缘跟随在立即更新 `canvasProjection` 后，立即刷新 `UIPointerInteraction` 的可见画布区域，不再等待 SwiftUI 下一次布局；区域未变化仍不触发 invalidate。
- 通用 unsigned iOS 构建通过：`/tmp/aetherscreens-edge-pointer-region-ios-20261009.log`。7 项 ViewportTracking 几何测试通过：`/tmp/aetherscreens-edge-region-geometry-20261009.log`；这些测试不执行 UIKit 指针交互。
- 真实系统鼠标圆点是否消失、边缘跟随的连续体验仍待 iPhone 12 Pro 真机验收。

### 2026-10-09 当前组合回归与设备检查

- 输入组合回归：ViewportZoom、ViewportTracking、TrackpadEngine、ExternalPointerGeometry、MacNativeInput、HardwareKeyboard、PointerTransport、RFBRemoteCursor、AppleCursorCache、SessionInputRecovery、KeyRepeatPress 共 90 项通过，无失败。日志 `/tmp/aetherscreens-input-combined-20261009.log`。
- AppleFileCopy、PointerTransport、FileTransferRelativePath、FileTransferJob 共 145 项通过，无失败；包含最终本地写入超时不能被提前到达的服务端成功掩盖的回归。日志 `/tmp/aetherscreens-transfer-current-combined-20261009.log`。这是内部与回环协议验证，不代表原生 Mac 真实文件收发验收。
- 02:05 重新检查 devicectl：physical iPhone 12 Pro 的 tunnelState 仍为 disconnected，传输为 localNetwork；没有运行真机 UI 或改变设备设置。

### 2026-10-09 iOS 双指缩放上限与原始像素显示一致

- `IOSRemoteInputView` 接收 `max(4, actualSizeZoomScale)` 作为 maximumZoom，双指缩放沿用工具栏上限。原始像素显示倍率超过 4 时，手势开始不再仅因旧硬编码上限跳回 4；最低倍率仍为 1。
- 通用 unsigned iOS 构建通过：`/tmp/aetherscreens-pinch-limit-ios-20261009.log`，`git diff --check` 通过。此变更未执行物理手势验收，仍需高分辨率远端画面在窄屏设备上验证。

### 2026-10-09 文件接收停滞超时

- ReceiveWorker 从构造开始等待首包，并在成功处理每个非结束消息后更新单个 monotonic timer；默认 60 秒，参数须有限且在 (0, 3600]。超时原子关闭 admission，取消接收 session/清理自有 staging，并仅报告一次失败。完成、取消、异常和队列预算溢出均停止 timer；同步文件操作不受该异步等待截止时间中断。
- admission 拒绝现在区分队列预算溢出与已终止任务。RFB 保持预算溢出断连的原有策略；超时、取消或完成后的迟到文件包不会仅因接收任务已关闭而断开桌面。仍需增加针对超时后迟到包且随后继续输入的独立回环场景，当前不能据此声称真实桌面持续连接验收通过。
- 40 项 receive-worker/PointerTransport 组合回归通过：`/tmp/aetherscreens-receive-inactivity-transport-20261009.log`。最终 worker 8 项通过（包括超时/溢出 transport 标志断言）：`/tmp/aetherscreens-receive-inactivity-final-tests-20261009.log`。iOS unsigned 构建通过：`/tmp/aetherscreens-receive-inactivity-ios-20261009.log`；diff check 通过。
- 默认阈值及 native-server 大文件接收尚未实际验收，文件传输仍为内部实现。

### 2026-10-09 接收超时后迟到包与鼠标传输专项

- 新增真实本地 TCP 回环测试：native-banner 客户端连接成功、安装短截止时间接收器、等待其超时；随后服务端发送同一 sessionID 的迟到 104 文件包，客户端消费完该包后发送鼠标坐标 (10,20)，服务端确实收到，客户端仍为 connected，临时根目录为空。
- 专项 1/1 通过：`/tmp/aetherscreens-receive-late-pointer-tests-20261009.log`；diff check 通过。该证据补齐上一检查点的独立回环缺口，仍不代表真实 Apple 服务端文件传输、物理 iPhone 体验或全部功能验收。

### 2026-10-09 有效进展延长接收期限，Mac mini 专项验证

- 新增接收进展续期测试：有效 item 在初始期限前到达，sender-end 在初始期限之后、续期内到达，任务成功完成；完成后继续等待超过超时阈值，不再触发失败。host receive-worker 9/9 通过：`/tmp/aetherscreens-receive-progress-tests-20261009.log`。
- 在授权 Mac mini 上通过 CLI xctest 运行当前 receive-worker 9 项加迟到包/后续鼠标 TCP 专项 1 项，10/10 通过：`/tmp/aetherscreens-receive-idle-mini-tests-20261009.log`。无 GUI/系统剪贴板交互。自建 QA 根目录 jHNC8Q 验证仅包含自己的 archive/bundle 且非链接后已删除。
- 该验证覆盖真实 macOS 文件系统、计时器与回环 socket，不代表 Apple 原生文件收发或 iPhone 实机验收。

### 2026-10-09 接收期限仅由有效文件进展续期

- ReceiveWorker 仅在 itemStarted、itemPrepared 或实际 bytesWritten > 0 时续期；ignored 控制消息不续期，senderFinished 终止 timer。当前 staging 已拒绝空数据块，本次未改变 wire codec 或空块语义。
- 新增 ignored-control 不续期专项：在原始期限前投递同 session 控制消息，仍在原始期限到期失败，拒绝后续消息且临时目录为空。当前 worker 10/10 通过：`/tmp/aetherscreens-receive-effective-progress-tests-20261009.log`，diff check 通过。未运行原生服务端或真机 UI 验收。

### 2026-10-09 Mac mini 局域网路径恢复

- 当前实际 TCP 探测 192.168.50.226:22 与 :5900 均成功，取代此前局域网不可达的判断。Tailscale SSH 仍成功，远端 macOS 27.0.1。
- 指定 AETHERSCREENS_LIVE_HOST=192.168.50.226 的真实 Screen Sharing 握手专项通过 1/1，0.073s：`/tmp/aetherscreens-lan-recovery-handshake-20261009.log`。此为握手证据，未认证、未取得画面，也不证明渲染流畅度。
- 后续可在同一测试配置下比较 LAN 与 Tailscale 的真实首帧/持续传输耗时，以排除历史 DERP 路径影响；不应再以 LAN 不可达作为当前阻塞。

### 2026-10-09 LAN 完整会话尝试未取得认证凭据

- 读取现有 live session 测试确认它不发送键盘或鼠标，不启动/操作远端测试图案；采用用户授权 Mac 账号和 LAN 地址运行 saved-password 会话测试。
- 当前测试进程没有获得 LAN 目标的已存密码，因此该用例明确跳过，未建立认证会话、未测得首帧，不能把 suite passed 视作流畅度通过。日志 `/tmp/aetherscreens-lan-full-session-20261009.log`，1 test / 1 skipped。
- LAN TCP/RFB 握手可达仍已证实；完整测量需通过不会输出明文的凭据注入方式提供此前授权账号密码，或在正式应用保存该目标后再测试。

### 2026-10-09 LAN 已认证 4K 会话与首帧

- 使用此前用户授权的 Mac 账号，通过关闭回显的终端输入向测试子进程环境注入密码；未保存密码文件、未修改应用存储、未将密码写入测试日志。测试结束后子进程退出并移除包装进程环境引用。
- LAN 192.168.50.226 的 fullColor 标准会话通过 1/1，无跳过，65.172s；实际认证与初始化成功、3840x2160 首帧在连接开始后 4.087s 到达，随后按测试要求保持 connected 60 秒。日志 `/tmp/aetherscreens-lan-authenticated-session-20261009.log`。本次不发送键盘/鼠标，不改变远端图案。
- 观察到后续帧回调不代表渲染 FPS，未执行高动态图案或物理呈现测量。LAN 首帧仍为数秒，不能把历史慢首帧仅归因于 Tailscale/DERP；后续需同配置 mesh 对照与初始化/首帧阶段分解。

### 2026-10-09 同配置 Tailscale 会话分阶段计时

- Live session 测试增加 monotonic state elapsed 输出，无凭据/画面内容记录；没有改变产品协议或输入行为。
- 100.64.0.3 fullColor 标准认证会话通过 1/1，无跳过，67.861s，4K 首帧 6.818s，随后稳定 60 秒。与本轮 LAN 4.087s 相比约多 2.73s；各为一次顺序观察，不代表重复样本均值或完全相同桌面内容。
- Mesh 阶段：negotiatingVersion 0.0047s，authenticating 0.0896s，initializing 3.0237s，connected 3.0873s，首帧 6.8177s。认证阶段约 2.934s，connected 后等待首帧约 3.730s。日志 `/tmp/aetherscreens-mesh-phase-session-20261009.log`。
- 同时 tailscale ping 两次确认 DERP(baizhiedu)，115ms / 227ms，命令最终报告 direct connection not established；这是当时路径证据，不证明稳定端到端输入或渲染延迟。后续补 LAN 同一分阶段计时，再定位认证及首帧传输的独立开销。

### 2026-10-09 LAN 同一分阶段配置复测

- fullColor 标准会话 1/1 通过，无跳过，65.194s，4K 首帧 4.146s，之后 60 秒 connected。日志 `/tmp/aetherscreens-lan-phase-session-20261009.log`。
- LAN authenticating 0.0808s、initializing 2.9370s、connected 2.9957s。认证窗口约 2.856s，connected 后首帧约 1.151s。
- 同一 debug 测试配置 mesh 认证窗口约 2.934s、首帧等待约 3.730s；LAN 对比认证窗口只差约 0.078s，首帧等待差约 2.58s。每条路径各一次分阶段样本，远端画面不受控制，不能据此推断稳定 FPS 或生产 Release 性能。
- 当前证据指向认证存在共同固定开销、mesh 增量主要落在首帧阶段。仍需本地 ARD 计算单独计时/Release 对照，不能直接归因于密码加密或网络。

### 2026-10-09 LAN Release 对照

- `swift test -c release` 同一 fullColor live session 1/1 通过，无跳过，62.878s，4K 首帧 1.803s；连接后保持 60 秒 connected。Release 编译 99.08s 不计入会话 elapsed。日志 `/tmp/aetherscreens-lan-release-phase-session-20261009.log`。
- authenticating 0.0655s、initializing 0.6417s、connected 0.6535s。认证窗口 0.576s，connected 后首帧等待 1.149s。
- 上轮 Debug LAN 认证窗口 2.856s，首帧等待 1.151s，总首帧 4.146s。因此本轮优化配置的主要差异落在认证阶段（约少 2.28s），首帧阶段几乎相同。这是不同配置的单次顺序对照，非正式生产安装/呈现/统计性能验收；还未把认证运算与服务端响应分开计时。
- 不能将 Debug 多秒认证直接作为发布版本性能结论。后续优先以 Release 配置测量，并继续确认大整数计算、网络/协议往返和实际绘制的独立耗时。

### 2026-10-09 Release Tailscale 对照完成

- 同一 fullColor 标准认证路径的 Release mesh 会话通过 1/1，无跳过，65.388s，4K 首帧 4.284s，随后保持 60 秒 connected。日志 `/tmp/aetherscreens-mesh-release-phase-session-20261009.log`。
- authenticating 0.2135s、initializing 0.8698s、connected 0.9004s。认证窗口约 0.656s，connected 后首帧约 3.383s。Release LAN 对照认证约 0.576s、首帧等待 1.149s、总首帧 1.803s。
- 当前单次样本 mesh 比 LAN 总首帧多约 2.48s，其中 connected 后首帧阶段多约 2.23s。局域网/中继区别在 Release 下仍存在，但不能将样本当成呈现 FPS 或动态输入延迟结论。
- 再次检查 physical iPhone 12 Pro 仍 disconnected，未执行手机 UI/输入验收。后续重点转向首帧负载/编码及 Release 解码成本；未改变路由或降低产品默认画质。

### 2026-10-09 Release 解码与 RGB565 解压阶段

- Release ZRLEDecoder + PerformanceBenchmarkScenario 20/20 通过：`/tmp/aetherscreens-release-decode-cost-20261009.log`。4K fullColor raw tile decode 8.84/9.65/8.95ms；RGB565 46.75/47.24/47.64ms；1080p CopyRect 0.430ms。这是本地 CPU/内存基准，排除 socket/Metal 呈现，不是 FPS 验收。
- RGB565 完整域测试新增独立同一连续 zlib 流解压计时，验证 expanded tiles 逐字节相等，保留最终 BGRA 全字节校验。专项通过 1/1：`/tmp/aetherscreens-release-rgb565-stages-20261009.log`。完整 decode 49.95/48.04/47.06ms，独立 inflate 40.19/40.13/41.00ms；各阶段是分别执行的测量，不能精确直接相减成独立转换耗时。
- 当前 evidence 指向 RGB565 基准的主要成本在解压而非查表颜色转换。ZlibDecompressor 逐 64KiB 分配/清零临时 Data 再追加到输出，后续可针对临时缓冲复用做窄改动并保持压缩炸弹界限/连续流字典/尾随数据拒绝等完整回归。

### 2026-10-09 解压 scratch 缓冲复用与实测限制

- ZlibDecompressor 在单个 payload 内复用一个至多 64KiB 临时 Data，输出仅预留至多 64KiB，保持每次剩余输出预算+1 检测、字典跨包连续、尾随数据拒绝及 zlib 状态处理。移除逐 chunk 新建/清零 Data；没有按远端声明最大值预分配整个输出。
- Debug 55 项 Zlib/ZRLE/file-inflater 回归通过：`/tmp/aetherscreens-inflate-buffer-regression-20261009.log`。Release 23 项 ZlibDecompressor/ZRLEDecoder/file-inflater 通过：`/tmp/aetherscreens-inflate-buffer-release-20261009.log`。diff check 通过。
- Release RGB565 total decode 47.75/47.05/47.54ms，独立 inflate 39.63/40.89/40.30ms；对比此前 47–50 / 40–41ms 未证实明显耗时提升。改动减少临时分配次数，但不能称为帧率提升或宣称解决 RGB565 CPU 开销。全彩 raw 9.28/8.58/8.18ms。
- 后续先定位 zlib 本身及输入分块开销；未改画质默认值、未新增依赖、未替换持续流解压协议。iOS/真实远端本次缓冲改动尚未独立验收。

### 2026-10-09 解压缓冲 iOS 构建及测量覆盖核查

- 当前解压 scratch 缓冲改动的通用 unsigned iOS 构建通过：`/tmp/aetherscreens-inflate-buffer-ios-20261009.log`，补齐上一检查点的 iOS 编译缺口。未安装手机或进行物理验收。
- 核查 RFBClient 现有 onNativePixelPayloadReady/onNativePixelDecodeCompleted，仅在 appleRecordCodec != nil 的内部原生加密 profile 触发；此前标准 fullColor LAN/mesh 会话并未启用该 profile，因此不能把合成 ZRLE 解码数值当作这些真实会话的解码阶段证据。
- 后续需为标准会话补充仅记录数字的传输/解码阶段测量，避免根据模拟压缩块直接替换算法或推断真实首帧瓶颈。

### 2026-10-09 标准 ZRLE 数字计时入口

- 增加内部可选 onZRLETiming：仅压缩包字节数、readExact payload 等待秒数与串行 decoder 的 CPU 执行秒数。标准和内部原生 ZRLE 均可启用；未设置时不增加时钟采样。原生专用回调语义保持原样，每个诊断回调后复核 connection 身份以容忍同步断连/重连。
- live session 测试启用该数字 hook；当前不会覆盖 Raw、Zlib、解码队列等待或 Metal 呈现时间，因此无 ZRLE 事件不能推断没有 CPU 成本。
- 大于 64KiB 标准 TCP 压缩包测试新增准确字节数、有限非负等待/解码值及回调触发检查，同时保留全部像素一致断言。ZRLETransport 全部 32 项通过：`/tmp/aetherscreens-standard-zrle-timing-tests-20261009.log`；diff check 通过。
- 当前仅验证诊断入口与协议回归；尚未用此入口完成最新 Release 真实会话计时，也未验证本次源代码的 iOS 构建。

### 2026-10-09 Release LAN 标准真实 ZRLE 分阶段测量

- 真实 4K fullColor 标准会话通过 1/1，无跳过，62.873s；首帧 1.784s，connected 0.681s。首个 ZRLE compressed payload 6,418,465 bytes，readExact payload 等待 0.2914s，CPU 解码 0.05435s。日志 `/tmp/aetherscreens-lan-release-zrle-timing-20261009.log`。
- 这次实际解码比 raw-tile 模拟基准约 9ms 更高，说明模拟数据不可替代服务端实际 subencoding。已记录 14 个 ZRLE timing 事件；后续小更新通常不到 1ms，但桌面未受控制，不能称为动态 FPS 或流畅度验收。
- connected 后首帧总等待约 1.103s，其中已测 payload 等待+decode 约 0.346s；剩余包含请求、服务端准备、更新头/矩形处理、队列与 framebuffer 更新等未分开阶段，不能简单归为服务端编码。
- 当前数字计时入口的通用 unsigned iOS 构建通过：`/tmp/aetherscreens-standard-zrle-timing-ios-20261009.log`。

### 2026-10-09 Release 标准 mesh 实际 ZRLE 成本

- 真实 fullColor mesh 会话通过 1/1，无跳过，65.022s，4K 首帧 3.940s，之后 60 秒 connected。首包 6,418,631 bytes，payload wait 2.1805s，CPU decode 43.38ms。日志 `/tmp/aetherscreens-mesh-release-zrle-timing-20261009.log`。
- LAN 上轮首包 6,418,465 bytes（仅差 166 bytes）、wait 0.2914s、decode 54.35ms、首帧 1.784s。本轮 mesh 多约 2.16s，其中 payload 等待多约 1.89s，CPU decode 未增加。近似同大小包对照支持当时中继传输是主要差异，不能推断所有桌面/动态场景。
- 应优先评估可选色深/更紧凑原生编码与实际直连路径，避免仅针对 40–50ms CPU decode 追求数秒首帧改善。产品默认全彩/协议未修改，未改变网络设置。

### 2026-10-09 可选 RGB565 Release 中继实测

- 仅测试进程设 AETHERSCREENS_LIVE_COLOR_DEPTH=rgb565，产品默认全彩和保存配置不变；真实标准 mesh 4K 会话通过 1/1，无跳过，63.102s，首帧 2.034s，之后保持 connected 60 秒。日志 `/tmp/aetherscreens-mesh-release-rgb565-timing-20261009.log`。
- 首包 1,734,968 bytes，payload wait 0.5775s，CPU decode 30.44ms。上轮 fullColor 同路径 6,418,631 bytes、2.1805s wait、43.38ms decode、3.940s 首帧。该顺序单次样本减少约 73% compressed bytes，总首帧少约 1.91s，表明现有可选低色深在本场景有传输收益。
- 尚未验证物理画面颜色/渐变或受控动态图案，不能将连接通过替代画质/流畅度验收；无需根据这次样本自动降低默认画质。设置页已有少色/色带/重连说明；下一步可将真实低带宽收益作为验收与用户选择依据。

### 2026-10-09 画质选择与重连代码核查

- selectDisplayColorDepth 先释放所有输入，失效 inputGeneration，取消密码提示并同步 disconnect 后配置新色深，再 startSession；SSH startSession 会先 cancelSSHSetup/旧 tunnel。当前未发现异步 disconnect 导致 configureColorDepth 被拒绝的路径，RFBClient.disconnect 同步清空 connection 并设置 disconnected。
- Release DisplayQualityStoreTests 3/3 通过：`/tmp/aetherscreens-quality-recovery-release-tests-20261009.log`。覆盖独立电脑保存/恢复、临时会话不继承保存选择、后台会话不能修改选择、未知保存值回退。这些测试不覆盖真实断网后的 UI 重试，不能将其当作画质切换失败恢复的完整验收。
- 本次没有修改画质实现；真实 UI 连续切换/失败恢复仍待物理设备或授权的独占 GUI 时间。

### 2026-10-09 当前完整 Release 核心门禁（Mac mini）

- 当前源码 Release bundle 在授权 Mac mini 上 CLI xctest 全量运行完成，641 tests / 16 explicit skips / 3 assertions failed in one test，121.766s，exit 1。日志 `/tmp/aetherscreens-full-release-mini-20261009.log`。取代此前 569 tests 的最新全量计数；不能标绿。
- 唯一失败用例仍为 DeviceStoreTests.testMigratesLegacyKeychainPasswordOnRead：第 501 行初始 fixture 保存 XCTAssertTrue 失败，第 505/511 行读取 nil；其余完成用例未报告失败。此前独立诊断为 SSH SecItemAdd -25308，本次 full log 没有打印该 numeric status，不能声称本次独立重新测得相同 OSStatus。
- 16 个环境 skip 不算真实功能验收；完整 suite 不替代 live RFB 的已认证专项、真机输入/呈现/原生传输验收。
- 自建 QA root AMDpdv 在验证仅含自己的 archive/bundle 且非 symlink 后已删除。未改变 Keychain 状态、未跳过失败用例、未修改用户设备配置。

### 2026-10-09 独立真实 QA Keychain 可行性

- 在 Mac mini SSH 进程内关闭该进程的 Security 用户交互，创建 UUID 命名临时目录/独立 keychain，只写入公开合成 fixture 数据。SecKeychainSetUserInteractionAllowed、SecKeychainCreate、指定 kSecUseKeychain 的 SecItemAdd、SecKeychainDelete 均返回 0。日志 `/tmp/aetherscreens-isolated-keychain-probe-20261009.log`。
- 临时 keychain 经 Security API 删除，临时目录由 defer 清理。未解锁登录 Keychain，未设 default keychain，未读写实际账号凭据。
- 该实测说明迁移用例可采用独立真实 Keychain，而不必 mock 系统读写或 skip 断言。尚未修改现有迁移测试，因此 641-test full gate 仍为失败；下一步隔离该 integration fixture，并保留默认登录 Keychain 的交互验收缺口。

### 2026-10-09 Keychain 迁移用例隔离后通过

- macOS 迁移 integration 用例使用 UUID 命名的独立真实 Security keychain，经已有 read/write/delete override 注入限定 search-list 查询与 kSecUseKeychain add；不使用假的存储实现，保留保存旧项、读取/迁移、新 service 实际可读、旧 service 实际已删除的断言。非 macOS 分支仍保留原系统 Keychain 路径。
- fixture close 通过 SecKeychainDelete 清理并删除自己的临时目录，清理失败明确 XCTFail；不设置 default keychain、不解锁登录 Keychain。生产存储代码未改。
- 首次编译出现 init 闭包捕获尚未完整初始化 self，改为 ownedRoot 局部值后通过；失败日志 `/tmp/aetherscreens-isolated-migration-host-20261009.log`，最终 host 专项 1/1：`/tmp/aetherscreens-isolated-migration-host-final-20261009.log`。
- Mac mini SSH 当前 Release DeviceStoreTests 22/22 通过，无失败：`/tmp/aetherscreens-isolated-migration-mini-20261009.log`。独立测试 keychain 清理断言通过；自建传输 root PgLieE 精确校验后已删除。diff check 通过。
- 此证据解决迁移测试对登录 Keychain 解锁环境的依赖，但不证明正式签名应用的默认登录 Keychain 权限/交互已验收。当前尚未重跑修改后的完整 641 项门禁，不将之前失败 full gate 改为通过。

### 2026-10-09 当前完整 Release 核心门禁通过

- 隔离真实 Keychain 迁移 fixture 后，当前 Mac mini CLI 全量 641 tests / 16 explicit skips / 0 failures，121.950s，exit 0。日志 `/tmp/aetherscreens-full-isolated-release-mini-20261009.log`。该完整结果取代此前 641/3 failures 的最新门禁状态；没有改成 skip 或删迁移断言。
- 旧服务迁移/实际读写/旧项删除/独立 Keychain 清理在全量上下文中通过。16 项环境跳过及真实签名应用登录 Keychain 交互仍未验收，核心通过不代表完整 Screens 对齐完成。
- 临时传输根目录 WvnxWd 精确检查仅自有 archive/bundle 且非链接后已删除。未新增发布、tag、应用 Git 提交/推送或生产配置变更。


## 2026-10-09 原生上传首次真实落盘

新增显式开启的 NativeFileUploadLiveTests，仅接受授权 LAN Mac 和短 UUID
独立测试目录。02:58 实测 1/1 通过，服务端返回 command200；随后独立 SSH
读取远端 fixture.bin，512 字节逐字节匹配 SHA256
110009dcee21620b166f3abfecb5eff7a873be729d1c2d53822e7acc5f34eb9b。
RFB 连接保持 connected，本地源文件未改变，唯一远端测试目录验证后已清理。
日志 /tmp/aetherscreens-native-upload-live-20261009.log。
仅证明普通单文件上传；下载、文件夹、资源分支、取消、冲突和产品 UI 仍待验收。
原 641 核心门禁结果不涵盖本次新增探针；默认未开启时该探针明确跳过。


## 2026-10-09 文件夹、空文件与多数据块原生上传实测

03:00 文件夹探针 1/1 通过，无跳过。服务端返回成功；独立 SSH 校验
2 层目录、空文件、131073 字节多数据块文件及返回上层后的 3 字节同级
文件，5 个条目全部匹配，源文件保持原样，RFB 连接仍正常。
测试树经完整核对后清理。日志 /tmp/aetherscreens-native-folder-live-20261009.log。
最终 Release 构建通过，默认两个探针明确跳过；差异检查通过。
下载、资源分支、冲突、取消与产品交互仍未验收。


## 2026-10-09 原生下载首次真实落盘

03:02 显式下载探针 1/1 通过，无跳过：从授权 Mac mini 的独立源文件收到
100/101、3 个 102 数据包与成功 104，现有接收 worker 完成本地 staging
和独占重命名落盘，131073 字节逐字节匹配；桌面连接仍正常。
独立 SSH 确认远端源内容未改，唯一远端/本地测试目录均清理。
日志 /tmp/aetherscreens-native-download-live-20261009.log；Release 构建及差异检查通过。
仍待验证最终接收确认与服务端 session 回收、目录下载、资源分支、取消、
冲突及公开产品 UI，不能把此次单文件双向通路视为全部对齐完成。


## 2026-10-09 同连接、同会话 ID 连续下载

03:04 真实下载探针 1/1 通过，同一个已认证桌面连接复用同一个传输 ID
连续完成两次下载，各自独立落盘并校验 131073 字节，全程无中途断连。
未发送臆测的额外确认命令；静态代码同时确认发送线程有移除 session
的收尾路径。日志 /tmp/aetherscreens-native-download-reuse-live-20261009.log。
源文件独立核对未变，测试目录已清理。此结果支持下一次传输可正常启动，
不代表长期资源泄漏或取消/冲突验收完成。


## 2026-10-09 停止空传输后继续上传

新增内部 AppleFileCopyControl 类型化 pause/resume/stop 报文，stop 字节
夹具与过滤测试 2/2 通过；文件复制回归 110/110 通过。
03:07 真实停止空传输后，同一个桌面连接使用新 ID 上传成功，服务端成功
结果和独立 SSH 的512字节一致性校验均通过，唯一测试树清理。
日志 /tmp/aetherscreens-native-stop-recovery-live-20261009.log。
仅证明停止空会话后的恢复；中途取消、残留清理和暂停恢复仍待实测。

iOS generic unsigned build also passed: /tmp/aetherscreens-control-ios-build-20261009.log. git diff --check passed.


## 2026-10-09 中途停止实测发现远端残留

03:09 探针实际发送512字节文件的前128字节再 stop5，随后同连接新上传
成功，源文件与桌面连接正常。但独立 SSH 发现 partial.bin 保留128字节，
内容确为源文件前缀：原生停止不会自动清理已写远端文件。
日志 /tmp/aetherscreens-native-partial-stop-live-20261009.log；Release 构建通过。
此测试通过仅表示恢复通路，清洁取消验收仍未通过。后续必须验证安全的
远端清理或提交机制，产品不能把已发送 stop 显示为已彻底撤销。
唯一测试目录含完整/残留两个已核对文件，均已清理；差异检查通过。


## 2026-10-09 同名冲突实测

03:10 独立目录中预先存在 fixture.bin（28 字节哨兵），原生上传512字节
同名文件成功；独立 SSH 确认原文件不变，新文件实际为 fixture 2.bin，
内容完全一致。默认 flags0 是自动改名行为，不是覆盖/拒绝。
日志 /tmp/aetherscreens-native-conflict-live-20261009.log。
产品必须显示服务端真实保存名称；替换授权、目录冲突和 Unicode 名称仍待验收。
精确核对两个文件后唯一测试树已清理；差异检查通过。


## 2026-10-09 实际保存名称进入任务状态模型

FileTransferJob.finish 新增可选 destinationNameBytes，只有当前 attempt、
传输成功、保存确认且字节进度完整时才记录；原 filename 保留请求名称。
名称按已验证 status 限制为最多1023字节且无 NUL，保留原始编码字节，
不可据此直接构造文件路径。未确认的结果、旧 attempt、取消后的结果和
非法名称均不更新状态或覆盖已保存结果。
FileTransferJobTests 7/7 通过，包含重命名、保存未确认、边界、旧回调与
取消隔离；日志 /tmp/aetherscreens-actual-destination-tests-20261009.log。
iOS unsigned 构建通过 /tmp/aetherscreens-actual-destination-ios-20261009.log；
差异检查通过。此为内部结果承载，公开拖放/进度 UI 尚未接入，不宣称
用户已能看到真实名称；下一阶段仍需实际 coordinator 与界面验收。


## 2026-10-09 资源分支真实上传

03:14 实际上传512字节 data fork +257字节 resource fork，探针1/1通过，
无跳过；独立 SSH 同时逐字节验证两个分支，本地源内容未改，桌面连接正常。
唯一测试树经过类型/内容核对后清理。日志
/tmp/aetherscreens-native-resource-live-20261009.log；Release构建与差异检查通过。
该结果只证明资源分支上传，资源分支下载、其他元数据、取消清理和公开UI
仍未验收。


## 2026-10-09 资源分支真实下载

03:15 资源分支下载探针1/1通过，同连接同sessionID两次接收，分别本地
落盘后逐字节核对512字节普通内容和257字节真实资源分支，全部一致。
独立SSH确认远端两个分支未改，唯一源/本地测试树清理；连接保持正常。
日志 /tmp/aetherscreens-native-resource-download-live-20261009.log。
Release构建、默认明确跳过和差异检查通过。此为双向资源分支验收，
不涵盖其他元数据、目录下载、取消清理与公开UI。


## 2026-10-09 目录下载真实组装落盘

03:17 目录下载探针1/1通过，同连接同ID连续下载两次，分别独立落盘。
两层目录、空文件、3字节同级文件及131073字节多数据块文件，递归条目
集合与全部内容均匹配；桌面连接正常。远端原树经独立SSH确认未变，
唯一远端与本地测试树均清理。日志
/tmp/aetherscreens-native-folder-download-live-20261009.log。
Release构建与差异检查通过；目录/空文件双向通路已有直接证据，但公开UI、
目录冲突、其他元数据与取消清理仍未完成。


## 2026-10-09 中文/emoji 上传名称与返回编码

03:19 上传 测试-屏幕😀.bin 的真实探针1/1通过，服务端成功结果中的
实际名称字节与原 UTF8 完全相等；独立SSH确认远端名称及512字节内容正确。
本地源与桌面连接正常，唯一测试树清理。日志
/tmp/aetherscreens-native-unicode-upload-live-20261009.log；Release构建/差异检查通过。
当前目标上的实际名称 UTF8 有直接证据；其他服务端、Unicode请求路径、
归一化与同名改名还未验证。


## 2026-10-09 实际名称显示适配

FileTransferJob.displayFilename 只在调用者提供已确立的编码时严格解码
实际结果名称；未知编码、无效字节或空名称返回请求名，原始字节不变，
不会用替换字符解码，也不据此构造文件路径。UTF8 的依据仍限定已验证
Mac 目标；其他目标不自动推断编码。
FileTransferJobTests 8/8 通过，新增中文/emoji名称、未知编码、空名称与
无效UTF8字节覆盖；日志 /tmp/aetherscreens-destination-display-tests-20261009.log。
iOS unsigned构建通过 /tmp/aetherscreens-destination-display-ios-20261009.log；
差异检查通过。SessionViewModel当前还未承载公开文件任务；此改动为
可供结果视图调用的模型适配，不能宣称进度/拖放UI已经接通。


## 2026-10-09 文件任务状态接入桌面会话生命周期

新增 MainActor FileTransferTaskStore，承载最多32个任务及当前 attempt，
以完整的已确认终态记录完成/真实名称；非法名称不会部分更新字节进度。
取消先公布失效token与终态，再调用可重入取消闭包；完成后移除闭包，
活动任务不能直接 dismiss，终态移除可释放历史列表容量。
SessionViewModel持有 store，并在所有显式 client断连/重连入口和服务端
停止状态回调中取消所持任务。未新增传输协议启动或拖放公开入口。
最终6项 store/SessionInputRecovery测试通过，包含真正 endSession 路径、
旧完成回调、重入取消、完成名称和容量边界；日志
/tmp/aetherscreens-transfer-session-state-final-tests-20261009.log。
最终iOS unsigned构建通过
/tmp/aetherscreens-transfer-session-state-final-ios-20261009.log；差异检查通过。
下一阶段仍需传输owner调用register/complete并接进度视图；此阶段只完成
会话持有状态和生命周期保护，不宣称公开文件传输功能完成，也不意味着
远端半截文件清理已解决。


## 2026-10-09 文件任务失败隔离

FileTransferTaskStore新增 fail(attempt,message)，仅当前attempt可失败，
先发布失败状态/失效token，再移除并调用该任务取消闭包以释放worker。
迟到成功、二次失败与取消不会覆盖原错误；其他任务保持独立。
5项 store测试通过，新增回调重入、单次资源释放、另一任务完成与终态
dismiss覆盖；日志 /tmp/aetherscreens-transfer-failure-isolation-20261009.log。
iOS unsigned构建通过 /tmp/aetherscreens-transfer-failure-ios-20261009.log，
差异检查通过。尚未接入公开进度面板和传输owner回调；不代表真实远端
异常/取消清理或整体Screens对齐已验收。


## 2026-10-09 条件传输面板与重复进度刷新抑制

桌面页接入 FileTransferProgressView，直接观察会话任务store，仅有任务
时显示有界滚动面板；提供状态、已确认进度、取消与终态dismiss。
零已确认字节使用不定进度，不把排队发送显示为已保存；上传取消文案
明确提醒检查远端半截文件。新增中英文资源。结果编码由完成owner提供，
未知编码保留请求名；有已确认编码时显示真实保存名。
store.recordProgress仅接收当前attempt的单调已确认进度，相同进度100次
不会重复发布。最终14项 store/job测试通过，包含重复发布抑制、界限与
取消后拒绝更新；日志 /tmp/aetherscreens-transfer-panel-final-state-20261009.log。
iOS unsigned构建通过 /tmp/aetherscreens-transfer-panel-ios-20261009.log；
差异检查通过。首轮构建时增量修改使新测试遇到旧模块API，冻结最终源码
重新构建已通过。没有运行原生GUI或真机布局验收；尚无公开传输启动owner
注册任务，不能将条件面板接入视为用户已经能开始拖放传输。
远端取消残留清理、完整拖放/导入导出流程仍需继续完成。


## 2026-10-09 多步传输启动连接绑定

RFBClient提供内部 fileCopyTransportGeneration，仅原生banner、已连接且
输入允许时可捕获；sendAppleFileCopy新增可选expectedGeneration，在现有
连接身份/队列代际校验之前拒绝已撤销标识，防止owner的后续启动/总量/
数据报文静默采用新连接。未绑定调用保留现有接口行为，公开功能未扩展。
真实loopback TCP测试捕获旧标识、撤销输入、恢复后验证旧发送立即拒绝
且无processed回调；新标识上传仍收到成功结果，断连取消replacement。
聚焦1/1通过 /tmp/aetherscreens-file-connection-binding-tests-20261009.log。
文件/任务/TCP回归157/157通过
/tmp/aetherscreens-file-binding-regression-20261009.log；iOS unsigned构建通过
/tmp/aetherscreens-file-connection-binding-ios-20261009.log；差异检查通过。
此为多步owner启动前的生命周期保护；尚未实现完整启动coordinator、
拖放入口与真机进度面板验收，不把内部绑定能力视为全部功能完成。

## 2026-10-09 启动报文与发送worker的串行衔接

新增 AppleFileCopyStartupTransport：首次文件报文前依次发送 start(2)、
总量(100)，每一步等待实际本地写回调；后续文件报文不重复启动前缀。
修复中间步骤 admission 拒绝被吞掉的问题，现在立即通知失败，不等超时。
取消后忽略迟到回调；重复回调不会重复发送下一步，拒绝跨会话及并行调用。
底层连接代际由调用方显式绑定，写超时由同一发送worker覆盖整个链。

原生上传 live probe 已改用该适配器并绑定捕获的连接代际。本轮没有运行
该版本的原生网络上传，不能沿用旧版本 live pass 作为新链的原生验收。
启动测试6/6通过；文件传输、任务store/job Release回归130/130通过，
日志 /tmp/aetherscreens-startup-regression-20261009.log。
iOS无签名构建通过，日志 /tmp/aetherscreens-startup-ios-20261009.log。
仍缺公开启动owner/文件选择入口、真机UI及流畅性验收；远端取消残留和
同名策略仍需按既有真实服务器证据处理，不能宣称全面Screens对齐完成。

## 2026-10-09 新启动链的原生服务器验收

03:40 已使用新的 AppleFileCopyStartupTransport + 捕获连接代际，在授权
Mac mini 192.168.50.226 上做两次独立真实上传，未操作原生GUI/系统剪贴板。
普通文件512字节，服务端返回command200/version1；SSH读取全部内容与源模式
相同，SHA256为110009dcee21620b166f3abfecb5eff7a873be729d1c2d53822e7acc5f34eb9b。
文件夹包含空文件、子目录、多块131073字节文件和3字节同级文件，共5项，
全部路径/内容验证通过，服务端返回200。各独立UUID测试根经精确清单、
非符号链接和内容检查后清理。两项live test分别1/1无失败、无环境skip。
日志：/tmp/aetherscreens-startup-native-live-20261009.log、
/tmp/aetherscreens-startup-folder-native-live-20261009.log。
此证据只证明新启动链在该Mac原生服务上的文件/目录上传；不证明用户
文件选择入口、同名覆盖策略、远端取消清理或iPhone交互流畅性完成。

## 2026-10-09 会话上传coordinator与任务store接合

新增 AppleFileCopyUploadCoordinator，SessionViewModel 持有延迟创建的实例。
调用方必须提供已准备的sources/start/totals和确定的远端目录，不在此推断
路径/编码。上传前核对源fork总字节数、job预算与totals逻辑字节一致。
安装worker后登记任务，首次报文使用前缀链，并绑定捕获连接代际。
本地写完不会发布完成/虚构进度；只有worker验证的最终服务端成功结果
才完成store。结果编码必须由调用方明确提供。失败/取消撤销store令牌、
清理startup和worker；停止指令限原连接，明确不承诺删除远端部分文件。
单coordinator同时只持有一个worker，与当前RFB传输owner约束一致。

三个owner测试证明：写完仍为transferring且0字节确认进度、成功200后
完成并移除owner；store取消在start未回调时阻断totals并发送stop5；
错误字节预算在安装/发送前拒绝。Release相关回归133/133通过，
/tmp/aetherscreens-upload-owner-regression-20261009.log。
iOS无签名构建通过，/tmp/aetherscreens-upload-owner-ios-20261009.log。
本轮未真实网络运行新coordinator，只验证测试backend的任务生命周期；
上一轮live只覆盖startup adapter。文件选择入口、递归源准备、实际
coordinator原生上传及真机传输面板验收仍待完成。

## 2026-10-09 文件选择后的完整树准备

新增macOS AppleFileCopyUploadPreparation，读取单个已选文件或整个目录。
Foundation递归枚举保持父目录在子项前，原生catalog收集器保留文件层级、
隐藏文件、空文件、资源fork与属性。结果包含可跨任务传递的Sendable
sources及准确logical/file/folder/nonempty-fork统计。不推断物理分配量。
默认限制1024项、64层、1GiB逻辑字节；可由调用方明确收紧。达到限制、
枚举读取错误或符号链接直接拒绝整个准备，不返回静默截断的成功结果。
取消检查在每个项目前以及结果返回前执行。调用方必须在后台执行，
并持有security-scoped文件访问至发送结束；本轮还没有接公开fileImporter。

四项准备测试覆盖含隐藏/空/中文emoji/资源fork的完整树、正确目录先序
层级和字节计数、数量/深度/字节限制、符号链接不读取目标及开始前取消。
Release相关回归137/137通过，
/tmp/aetherscreens-upload-preparation-regression-20261009.log；
iOS构建通过（macOS收集器不在iOS编译，Source的Sendable声明跨平台），
/tmp/aetherscreens-upload-preparation-ios-20261009.log。
没有宣称iOS源catalog准备、公开文件入口或真实coordinator上传已经完成。

## 2026-10-09 会话任务驱动的真实上传

新增显式opt-in异步live test：后台UploadPreparation读取512字节普通文件，
真实RFBClient绑定代际，UploadCoordinator登记FileTransferTaskStore并启动
前缀与worker，观察published jobs完成状态。发送开始后断言transferring/0
确认字节；服务端验证结果后断言completed/512字节、实际结果名fixture.bin，
桌面连接仍connected。physicalBytes来自源URL的实际allocated-size属性，
不是写入虚构进度。资源分配块字段4096沿用该已验证测试目标，不推广为
任意远端volume参数的证明。

03:47 Mac mini真实上传1/1、无skip、无失败，耗时1.696秒。
SSH独立读取远端完整内容与源512字节模式相同，SHA256
110009dcee21620b166f3abfecb5eff7a873be729d1c2d53822e7acc5f34eb9b。
精确检查独立UUID目录清单及非symlink后清理了所有本轮远端测试残留。
日志：/tmp/aetherscreens-coordinated-upload-native-live-20261009.log。
默认未opt-in的构建验证跳过live test，不算原生验收；本轮明确opt-in的
实际运行才是以上证据。文件选择UI、iOS源准备及真机面板体验仍未完成。

## 2026-10-09 macOS文件选择入口与后台准备

RemoteDesktopView会话菜单新增“发送文件或文件夹”，仅macOS显示；
当前连接必须原生Apple server、输入/前台有效且无活跃上传/准备任务。
FileUploadSheet使用系统fileImporter选择单个文件或目录，填写已存在的
远端目录（默认~/Desktop），显示同名可能改名、停止可能留部分文件以及
1GiB/1024项限制。无后台真实远端目录浏览或覆盖选项的虚构实现。

SessionViewModel.beginFileUpload持有security-scoped访问，Task.detached
执行完整树准备/分配字节统计，支持取消传递；返回后重新校验连接代际，
前台/Observe Only与准备身份。目录必须绝对路径或~/，UTF8少于200字节
且无NUL，防止已研究的native短路径缓冲风险。启动coordinator后将访问
持有到onReleased；该释放回调在成功/失败/取消owner卸载后触发。
断开/重连/结束原有cancelAll路径改为stopFileTransfers，一并取消准备。
真实远端写结果仍驱动store完成；不把queued bytes显示为已保存进度。
结果编码保持未知，不自动把任意目标返回字节当UTF8解码。

Release相关回归137/137通过（1.880秒），日志
/tmp/aetherscreens-file-picker-regression-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-file-picker-ios-20261009.log。
本轮没有操作host原生GUI；新sheet的原生文件选择器、sandbox访问保持、
布局及菜单体验未完成实机验收。iOS source准备/选择入口仍未实现。
allocationSize字段4096沿用已实际验证原生目标，其他卷配置尚未验证。

## 2026-10-09 仅观察/会话切换时撤销文件任务

isObserveOnly=true和setForegroundSession(false)现在在输入代际撤销前调用
stopFileTransfers，立即取消后台准备/任务store，并通过owner停止前缀、
worker及原连接stop5；不再依靠随后发送拒绝/超时才结束旧上传。保持
当前“只有前台输入连接可发送文件”的生命周期策略；不宣称实现跨会话
后台持续上传，这仍需独立传输代际/产品策略设计。

新增会话测试验证两条路径都会取消持有的准备Task、清空准备状态、更新
准备身份、取消任务一次且拒绝迟到完成。现有owner成功/取消测试扩展为
验证onReleased仅一次，包括结束后再次cancelAll/取消的情形；这是访问
保持释放回调次数的单元证据，未替代真实sandbox授权文件验收。
Release相关文件传输+任务+会话registry测试143/143通过，
/tmp/aetherscreens-file-lifecycle-regression-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-file-lifecycle-ios-20261009.log。
未进行原生GUI/物理iPhone交互验收。全面Screens对齐仍未完成。

## 2026-10-09 跨平台原生catalog编码

新增Foundation实现的AppleFileCopyCatalogMetadata.encode与UTCDateTime
构造器：明确传入已观测Finder wire bytes、权限、标志、时间和fork大小，
编码原生104字节字段；不依赖Carbon。拒绝错误Finder长度、目录携带fork、
类型/目录标志不一致及不能表示的日期。UTC时间为1904起48位秒+16位分数。
三个codec测试独立核对固定字节位置/BE数值、目录约束与时间纪元/边界。
Release相关回归141/141通过，iOS构建通过，日志
/tmp/aetherscreens-portable-catalog-regression-20261009.log、
/tmp/aetherscreens-portable-catalog-ios-20261009.log。

Opt-in原生coordinator上传probe现在用新encoder重新生成来源catalog，
规范化item framing后与原生Carbon来源的完整item相等，再发送至Mac mini。
03:55实际运行1/1、无skip/失败（1.768秒）；task-store完成与实际名字确认。
SSH独立读取远端512字节完全一致且权限0644，检查精确独立目录后已清理。
日志 /tmp/aetherscreens-portable-catalog-native-live-20261009.log。
该证据证明encoder在该来源/目标普通文件上的兼容性，不证明iOS文件
provider读取、Finder原始xattr到wire表示转换或iPhone UI已完成。
下一步仍需iOS来源收集器、沙盒持有和真机完整上传验收。

## 2026-10-09 非Carbon来源读取与实际服务器验证

新增AppleFileCopyPortableSourceCollector（Darwin/Foundation，iOS可编译）：
NOFOLLOW/O_NONBLOCK读取普通文件/目录，fstat的大小/权限/四个观测时间，
descriptor扩展属性、独立resource-fork大小与Finder信息。目录Finder前两个
UInt32按已知word交换逆转换；文件Finder原始属性直接对应wire。原生与
portable共用bounded AppleFileCopySourceAttributes，resourcefork不重复嵌入
属性表。读取后核对路径dev/ino/size/mode/mtime，拒绝叶symlink及读取变化。
无Carbon可观测的userAccess/textEncodingHint/backup字段使用0，不宣称
完整Carbon目录字段相等；未支持iOS file-provider协调读取/下载或snapshot。

新增两项测试：真实文件/目录的Finder、资源fork、权限、修改/创建时间与
Carbon比较；symlink/缺失源拒绝。初轮143测试有两项时间比较失败：
Carbon在受控0.5秒fixture把分数截到32767，POSIX观测编码为32768。
改按原生16位fraction精度（1/65536秒）比较日期，保留其余字节精确断言。
最终Release回归143/143通过，
/tmp/aetherscreens-portable-source-final-regression-20261009.log。
iOS无签名构建通过，/tmp/aetherscreens-portable-source-ios-20261009.log。

真实coordinator opt-in probe改为发送portable收集的来源。03:59实际运行
1/1无skip/失败（1.780秒），任务store完成、实际文件名以及连接保持验证。
SSH独立核对远端512字节全量相同且0644，精确清单检查后清理独立测试目录。
日志 /tmp/aetherscreens-portable-source-native-live-20261009.log。
不把Mac上portable收集器验收冒充iPhone本地provider或真机UI验收。

## 2026-10-09 iPhone文件选择入口与稳定副本

UploadPreparation开放跨平台编译：macOS保持Carbon收集器，iOS使用portable
收集器。FileUploadSheet与会话菜单不再限macOS；iOS使用自适应宽度与
medium/large sheet，系统fileImporter选择文件/文件夹。准备时禁止交互式
滑动dismiss，明确Cancel撤销仍可用。未进行真机或模拟器布局验收。

新增AppleFileCopyUploadSnapshot，在后台NSFileCoordinator读取许可范围内
创建仅自身UUID的0700临时根、验证源树限制、copyItem并重新验证副本，
比较完整层级/名称/类型/各fork大小。上传sources沿用原始catalog/属性，
仅把数据URL和resourceURL改到稳定副本，避免把staging ctime发到远端。
source权限保留至coordinator onReleased，副本在失败/取消/完成释放；
remove幂等且deinit兜底。非协作POSIX writer仍可能在复制中修改相同长度
内容；此机制不是任意写入者下的原子filesystem快照。复制峰值空间/中途
FileManager copyItem取消和provider长等待取消仍需真实环境进一步验收。

两个snapshot测试证明完整含空文件/resourcefork树复制、原item元数据
相等、改变原源后副本仍旧内容、remove重复调用不删除源，以及限额/取消
不返回部分成功。Release相关回归145/145通过，
/tmp/aetherscreens-ios-file-entry-final-regression-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-ios-file-entry-final-build-20261009.log。
未宣称iPhone file-provider授权、iCloud下载、完整上传或界面丝滑已验收。

## 2026-10-09 稳定副本真实上传与手机连接状态

Live coordinator probe改为后台UploadSnapshot.prepare，副本完成后将原源
512字节全部改为9，再以副本URLs及原始catalog进行真实上传。terminal
确认后断言原源仍为修改后的9、副本仍为旧模式、主动remove后副本不存在。
04:05 Mac mini真实运行1/1、无skip/失败（1.768秒）。SSH读取远端所有512
字节，确认是旧模式且不是新9数组，权限0644；独立UUID根精确检查后清理。
日志 /tmp/aetherscreens-snapshot-native-live-20261009.log。
此为完整snapshot+startup+worker+任务store的实际原生服务器证据；尚未
证明iOS文件提供商、系统文件选择器授权和真机UI已通过。

04:04左右只读devicectl list devices显示物理iPhone12Pro available(paired)，
不同于此前unavailable状态。已请求下一轮约15分钟独占真机验收窗口，
尚无答复；未占用/安装/启动手机app，不以paired状态替代解锁或UI验收。

## 2026-10-09 上传面板键盘/窄屏布局

FileUploadSheet改为滚动内容+safeAreaInset固定底部动作，内容超过可见
高度时可滚动，取消/发送从原来的内容尾部移出；macOS限定440×460窗口，
iOS保留medium/large detents。远端目录FocusState与iOS Done提交关闭键盘，
禁用自动大写/纠错；发送前关闭目录焦点。选择/目录/取消/发送补充稳定
accessibilityIdentifier供后续真正的界面验收定位。

macOS Release构建通过（65.66秒），
/tmp/aetherscreens-upload-sheet-layout-mac-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-upload-sheet-layout-ios-20261009.log。
本轮只做布局代码和编译检查，没有操作host原生GUI或未获独占窗口的手机，
不能以safe-area代码或成功构建证明实际键盘/大字体/横屏布局已验收。
底部动作在极大字体下的自适应与真机视觉核对仍待完成。

## 2026-10-09 上传操作的大字体自适应

FileUploadSheet actionBar使用ViewThatFits：水平剩余宽度足够时按原水平
布局，按钮原生字体尺寸不能适配时改成纵向布局，避免把Cancel/Send文本
压缩裁掉。iOS按钮label至少64×44pt，取消使用bordered、发送使用原生
borderedProminent；保留取消/默认键盘快捷键、identifier和发送禁用条件。
按钮使用原生DynamicType文字，并固定水平理想宽度供ViewThatFits选择；
未缩小或限制辅助字体来伪装适配。macOS不套用iOS触控label最小尺寸。

macOS Release构建通过（30.07秒），
/tmp/aetherscreens-upload-sheet-buttons-mac-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-upload-sheet-buttons-ios-20261009.log。
本轮属于可逆布局改动，未添加复刻实现的单元测试；编译不替代真实截图/
键盘/横屏/辅助大字体UI验收。极大字体与横屏键盘组合仍待实机证据。

## 2026-10-09 接收任务的未知大小状态

FileTransferJob新增明确unknown-size下载构造器；totalBytes可在下载活动
令牌下以已完整写入/保存的实际数据总量确认，原有已知大小任务禁止变更
总大小。unknown任务可以记录worker真实写入进度，但fraction保持0且
传输面板使用indeterminate，不把接收预算1GiB假装成远端文件大小。
finish要求isSizeKnown；TaskStore.complete仅在明确confirmedDownloadBytes
时确认unknown下载大小，确认量不能小于已写入量，失败不部分更新任务。
完成后的旧attempt不能再次改大小。已知上传行为保持原有terminal规则。

两项新增store测试覆盖未知大小无伪完成、错误/迟到大小拒绝且无部分
更新、已知大小不改变、空文件需要明确0字节确认。focused20/20通过。
相关文件传输回归147/147通过，
/tmp/aetherscreens-download-task-size-regression-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-download-task-size-ios-20261009.log。
此为下载coordinator接合前的数据/显示基础，尚未加入真实接收owner、
本地保存选择器或公共下载入口，不宣称接收UI已完成。

## 2026-10-09 macOS接收任务owner与完整保存

新增AppleFileCopyDownloadCoordinator（当前macOS）：显式start1/flags bit0
请求、绑定原连接代际、安装receiver后登记unknown-size任务；短本地写
deadline和receive inactivity期限分别覆盖启动/接收。重复启动回调忽略，
本地启动写未确认时即使已经保存接收结果也不能发布完成，超时后失败。
worker队列上的finalizer只接收单个文件/目录根，使用已验证RENAME_EXCL
保存，不覆盖既有目标。server104仅触发准备/保存；实际commit成功才确认
任务最终大小/名字。成功/失败/取消卸载owner、清理暂存和调用释放回调。

为receive worker添加默认no-op累计已写入字节回调，取session真实
acknowledgedBytes。原Event.bytesWritten在最后一个data块完成item时会
改发itemPrepared，因此不能靠累加事件统计最终大小。新owner使用完整
累计计数，包括最后块。未向UI高频投递每块百分比。
取消不持有UI锁跨filesystem操作；已开始的commit可能在取消后落盘，
迟到结果不能恢复取消任务，download停止/失败提示明确检查保存目录。
不删除已落盘文件冒充回滚或覆盖用户现有文件。

三项owner测试证明实际commit后complete与3字节最后块统计、现有文件
冲突保持内容且暂存清理、启动回调缺失时已保存数据仍不伪完成。首轮
测试fixture的102长度误设0而payload为3被正确拒绝；修正为3后3/3通过。
相关Release回归150/150通过，
/tmp/aetherscreens-download-owner-regression-20261009.log；
iOS构建通过（新owner受macOS条件限制，累计字节回调跨平台编译），
/tmp/aetherscreens-download-owner-ios-20261009.log。
本轮未跑新owner的原生网络下载；公开保存选择器、iOS目录树/metadata
finalize及iPhone接收UI仍未实现，不能以macOS owner宣称全面双向已完成。

## 2026-10-09 新接收owner真实下载/冲突验收

新增显式opt-in NativeFileUploadLiveTests.testOwnedNativeCoordinatedDownload：
连接授权Mac mini，单桌面连接/同一个native session ID下连续下载3次：
前两次各自独立本地目录保存131073字节完整文件，store由unknown大小
变成completed/131073真实字节，实际显示名fixture.bin，释放回调各一次，
目录没有额外incoming暂存；第三次预置2字节同名sentinel，native传输
完成后本地RENAME_EXCL拒绝保存，store为failed且原文件完整保持，所有
本轮暂存清理、桌面连接仍connected。没有用重连或人工等待掩盖owner复用。

04:21实际运行1/1无skip/失败（1.867秒），日志
/tmp/aetherscreens-download-owner-native-live-20261009.log。
SSH独立复查远端原始131073字节未修改，SHA256
59143c73fbc669c18bdeb36c7cfa13888c03a2d935b18d939c628692360c16ff；
精确清单/non-symlink检查后清理独立UUID远端根，本地根由test defer清理。
默认非opt-in构建skip不算上述真实验收证据。
仍缺公开下载保存选择器、新owner的文件夹/资源fork live组合验收以及
iOS metadata/tree保存实现，未宣称双向文件UI或真机体验全面完成。

## 2026-10-09 macOS接收文件/目录的选择入口

RemoteDesktopView会话菜单新增macOS“接收文件或文件夹”，FileDownloadSheet
填写远端绝对/~/路径并使用系统folder importer选择已有本地保存目录。
面板为滚动内容+固定底部取消/接收操作，窄宽使用ViewThatFits；明确不会
覆盖已有文件，冲突时需选其他目录。菜单受原生Apple连接、前台/仅观察
和接收owner忙闲条件限制；开始后使用已真实验证的DownloadCoordinator。

SessionViewModel.beginFileDownload保留所选目录security-scoped访问到
onReleased，早期失败/throw不漏掉访问释放。复用internal的幂等
FileTransferScopedAccess（原上传access类），未改变签名/沙盒发布配置。
上传与下载onReleased均显式发出ViewModel.objectWillChange，避免静止
画面没有其他发布事件时菜单持有旧isBusy禁用结果；弱引用不形成owner
与session循环持有。此为主动刷新代码，真正的菜单状态UI仍待实机检查。

最终相关Release回归150/150通过，
/tmp/aetherscreens-download-sheet-final-regression-20261009.log；
iOS无签名构建通过，/tmp/aetherscreens-download-sheet-final-ios-20261009.log。
新macOS保存选择器/权限和公开入口未原生GUI验收。iOS接收owner/保存仍未
实现；上传snapshot释放目前会在UI actor触发同步remove，下一步应将
较大目录的残留清理移至utility队列并验证，不以构建成功代替流畅性证明。

## 2026-10-09 上传副本后台清理与接收目录回归

上传成功释放以及未交接/取消路径改用snapshot.removeInBackground；utility
串行队列强持有snapshot至删除结束，防止UI最后引用释放时deinit再次同步
递归删除。可注入队列的测试阻塞清理队列，证明调用返回时副本仍在且被
保留，随后排队删除完成、引用释放、原始源文件保持。151项相关Release
测试通过，日志/tmp/aetherscreens-background-cleanup-regression-20261009.log；
iOS无签名构建成功，/tmp/aetherscreens-background-cleanup-ios-20261009.log。
这证明删除从UI调用路径移出，不代表已测得真机FPS/卡顿下降；复制期间
取消延迟、文件provider等待、临时空间峰值仍待处理/物理验收。

新增DownloadCoordinator目录组合测试：中文/emoji根名、嵌套中文文件、
空目录、3字节data+4字节resource fork经真实staging/commit保存，任务实际
总量7、保存名字一致、源文件不变且保存目录仅有预期根。4项owner测试
通过；相关最终Release回归152/152，0失败，
/tmp/aetherscreens-transfer-directory-final-20261009.log。
使用合成协议数据及真实本地文件系统，不能替代新owner的原生网络目录
组合验收或系统选择器UI验收。iOS接收metadata/tree/finalize仍未实现。

官网优先事项：发现后续部署覆盖旧修正后，从最新origin/main 039f668
隔离构建并仅修改首页卡片和详情页inset-icon匹配，提交并推送官网main
28fdcd7a6a126ae2479cd32497437f5e5587b375，部署c149327d。
正式中文/英文首页和详情页curl均确认inset-icon，详情页浏览器截图
/tmp/aetherscreens-official-logo-verified.png；官网167项测试/346页构建通过。
AetherScreens应用代码未提交/推送/发布，原有未完成范围保持。

## 2026-10-09 文件传输浮层触控操作

FileTransferProgressView取消/关闭按钮改用有contentShape的44×44 iOS触控
区域，macOS使用24×24，保留现有语义标签并添加按job ID区分的可访问性
标识。短任务列表启用basedOnSize滚动回弹策略；未改变传输状态判定。
iOS unsigned构建成功，/tmp/aetherscreens-transfer-touch-ios-20261009.log；
macOS Release构建成功，/tmp/aetherscreens-transfer-touch-mac-20261009.log。
这次为低影响视图修改，不新增镜像实现的测试；未做真机点击/渲染验收，
不能宣称按钮已实际验收或整体流畅性已达标。应用代码仍未发布。

## 2026-10-09 新接收owner目录+resource fork真实链路

扩展NativeFileUploadLiveTests coordinated helper，保留原普通文件测试并
添加testOwnedNativeCoordinatedDirectoryWithResourceForkDownload，仍需
显式opt-in和唯一UUID /tmp fixture，不输出凭据。新组合目录含5个条目：
根、nested、131073字节fixture.bin（257字节resource）、empty.bin、3字节
sibling.bin。真实Mac mini LAN RFB连接/同一native session ID连续3次：
前两次分别保存到独立本地目录，任务真实total/transferred=131333，所有
数据/资源和条目集合一致，显示名fixture-folder，释放一次且无额外暂存；
第三次预置同名目录/sentinel，拒绝覆盖并完整保留sentinel，未取消桌面。
04:37 live实际1/1通过无skip（1.957秒），日志
/tmp/aetherscreens-owner-directory-native-live-20261009.log。
SSH独立复查远端源完整，data SHA256
59143c73fbc669c18bdeb36c7cfa13888c03a2d935b18d939c628692360c16ff，
resource SHA256 e54984387fbd4ff16d36a4633e6e60072a29d7685d5ada5d39b5142ebc608be9。
精确清单和non-symlink校验后清理本轮UUID远端根，本地test defer清理。
相关最终回归152/152零失败，
/tmp/aetherscreens-directory-native-final-regression-20261009.log。
这是macOS公开接收owner的网络/保存组合验收；未验系统选择器、iOS保存、
大型目录空间峰值或真机帧率，全面对齐目标仍未完成。

## 2026-10-09 iOS暂存的资源分支/扩展属性保留

检查发现StagingFile.finish中materializeResourceFork/applyExtendedAttributes
全部包在macOS条件内，iOS准备完成前不会应用已收到的资源sidecar及属性。
将这两个不依赖Carbon的Darwin实现移到跨平台作用域，finish全平台调用；
仍使用owned staging描述符和64KiB流式fork复制，拒绝重复ResourceFork
扩展属性覆盖权威stream。文件系统不支持还原或设置失败时抛错并cancel
清理暂存，不静默当作成功。native Carbon catalog、权限、tree assembly及
final destination commit仍受macOS条件限制，不启用虚假的iOS接收入口。
iOS unsigned BUILD SUCCEEDED，/tmp/aetherscreens-ios-staging-forks-20261009.log；
Release staging/receive-session/download-owner回归22/22零失败，
/tmp/aetherscreens-staging-forks-regression-20261009.log。
macOS已有测试覆盖fork/扩展属性/冲突保存；此处iOS证据仅API编译兼容，
真实iPhone/APFS和文件provider支持、元数据/目录finalize及公开保存仍未验。

## 2026-10-09 iOS接收目录组装共用实现

StagingFile catalog identity记录、descriptor遍历校验、受限权限finalize、
RENAME_EXCL子项/目标移动及清理改为跨Darwin平台编译；只有调用Carbon
的restoreCatalogMetadata仍macOS限定。ReceiveSession.takePreparedTrees和
worker senderFinished后完整目录组装现在跨平台共用，不再iOS单独handoff
平铺files。目录记录依旧携带dev/ino，openat逐层NOFOLLOW验证，子项反序
组装，目标冲突拒绝覆盖。未提供iOS假的catalog restore或开启公共入口；
iOS的catalogRestored仍需真实便携还原方法设置，完整保存需继续实现。
iOS unsigned构建成功，/tmp/aetherscreens-ios-tree-staging-20261009.log；
staging/receive-session/worker/download-owner Release32/32零失败，
/tmp/aetherscreens-tree-staging-regression-20261009.log，git diff --check通过。
共用方法API已iOS编译，现有目录/冲突/身份/资源回归仍在macOS执行；
物理iPhone runtime、外部provider保存与便携日期/Finder元数据仍未完成。

## 2026-10-09 无Carbon的目录元数据还原

AppleFileCopyPortableCatalogRestore使用iOS SDK声明可用的fsetattrlist，按
Darwin属性排列（script、create/mod/change/backup timespec、Finder32）
构造四字节对齐packed缓冲；无getattrlist leading length，避免Swift struct
padding。fstat验证file/dir类型；描述符来自owner已核验dev/ino的逐层
NOFOLLOW打开。失败明确抛errno。日期由wire整秒/16bit fraction整数转换，
文件/目录Finder反转换复用已有decoder。Staging.restoreCatalogMetadata
改为跨平台方法：macOS保留Carbon原路径，其他平台调用便携helper，成功
后才允许权限finalize。便携路由不自行提交公共保存目标。
依据Apple getattrlist/setattrlist官方手册及当前iPhone SDK接口：
https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/getattrlist.2.html
https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/setattrlist.2.html

新测试直接调用同一portable helper在本机文件系统对文件/目录还原，
复查birth/mtime至wire精度、Finder原始xattr、payload未修改及类型拒绝。
1/1通过，/tmp/aetherscreens-portable-restore-tests-20261009.log；相关最终
Release153/153通过，/tmp/aetherscreens-portable-restore-final-regression-20261009.log。
iOS unsigned BUILD SUCCEEDED，/tmp/aetherscreens-ios-portable-restore-20261009.log。
当前测试未独立复查change/backup/encoding字段；iPhone存储/provider是否
支持全部attributes仍未物理验收，系统不支持时明确失败，不宣称兼容所有
provider。接收coordinator/UI的iOS公开入口及最终保存交接仍需推进。

## 2026-10-09 iOS公开接收入口与协调器元数据调用

DownloadCoordinator/SessionViewModel下载方法和owner改为跨平台，菜单及
FileDownloadSheet开放iOS“接收文件或文件夹”。iOS使用系统folder importer，
保存security-scope访问至owner释放，medium/large sheet、无自动大小写的
路径输入/Done收键盘、固定操作条和44pt触控按钮；macOS原窗口保持。
断线/仅观察/前台切换仍由同一store取消，代际绑定和迟到结果拒绝共用。
检查发现原download finalizer未调用catalog/permission restore；此次在
最终commit前显式调用两步，失败不宣布完成。macOS仍用Carbon，iOS使用
上一轮portable helper；最后根权限在原子rename后应用。
iOS unsigned BUILD SUCCEEDED，/tmp/aetherscreens-ios-download-entry-20261009.log；
153项相关Release回归零失败，/tmp/aetherscreens-download-entry-regression-20261009.log。
新增owner保存结果断言：fixture mode0640及历史modificationDate经真实
协调器保存后保持；4/4 owner测试通过，
/tmp/aetherscreens-download-metadata-owner-tests-20261009.log。

公开入口已代码接通，不代表物理验收：iPhone系统选择器、provider写入
协调/权限、rename/metadata支持和整个保存操作仍需真机。当前直接descriptor
写入选中folder，尚未增加NSFileCoordinator provider写协调，不能宣称
所有云盘兼容。第三方provider不支持metadata/atomic rename时可能失败；
未创建虚假成功或自动降级丢属性。修正元数据调用后的native网络组合应
再验收；整体性能、指针、缩放边缘跟随及其他Screens能力仍未完成。

## 2026-10-09 补齐metadata调用后的真实网络回归

Native coordinated目录测试增加显式QA_DOWNLOAD_METADATA opt-in断言；此次
独立UUID远端fixture设nested/file mode0640、历史mtime1700000100。
04:47实际同一LAN桌面连接/同一ID3次owner接收：两次完整内容/resource
并验证mode和mtime保持；第三次同名目录冲突preserve sentinel。store真实
131333bytes、owner释放和桌面连接正常。实际1/1通过无skip（1.929秒），
/tmp/aetherscreens-owner-metadata-native-live-20261009.log。
SSH独立复查精确条目集合、全部数据/resource、源权限和mtime未改变后，
清理本轮owned远端UUID根；本地fixture由test defer清理。
这验证新增metadata+permissions步骤没有破坏macOS真实链路；macOS走
Carbon路径，不能用此结果宣称iPhone portable helper已网络/runtime通过。
云盘provider写协调、iPhone公开保存UI和帧率验收仍未完成。

## 2026-10-09 接收最终保存的写入协调

DownloadFinalizer新增NSFileCoordinator实例，在utility receive worker执行
coordinate(writingItemAt:destination,options:forMerging)；accessor内再次
检查取消标记，然后metadata/permissions还原及RENAME_EXCL保存到协调器
返回的URL。协调错误或未执行accessor明确失败，取消等待不发新commit；
UI cancel在锁外调用coordinator.cancel，不把等待移入MainActor。已进入
commit时仍可能完成落盘，迟到完成被原owner/token保护拒绝。
14项download-owner/receive-worker回归通过，包含实际commit、权限/mtime、
目录fork、冲突保护、missing write和worker限流/超时，
/tmp/aetherscreens-download-write-coordination-tests-20261009.log。
iOS unsigned BUILD SUCCEEDED，
/tmp/aetherscreens-ios-download-write-coordination-20261009.log，diff check通过。
本轮未有真正第三方provider参与：测试证明本地coordination不破坏既有
结果，不能证明provider等待取消或iCloud/第三方驱动兼容。接收期间仍在
所选目录建立/写incoming暂存；最终协调不等于全程暂存写已协调，后续需
私有本地暂存+协调导出，且必须保留树/resource/metadata及非覆盖规则。
物理iPhone保存UI和桌面输入/流畅性整体目标仍未完成。

## 2026-10-09 接收队列停止后释放目录授权

发现download onReleased原来立即access.close；取消与正在执行的provider
协调/commit并发时可能在后台仍用目录期间停止security-scoped访问。
ReceiveWorker.cancel新增默认no-op onStopped回调，队列关闭admission后
在同一串行队列stopDeadline/session.cancel完成才调用。DownloadCoordinator
保留原onReleased同步菜单/owner释放语义，新增MainActor Sendable onStopped
负责目录access.close。后台排空期间闭包强持有scoped access；取消不阻塞
MainActor，旧任务完成/晚包仍不能恢复store。重复底层remove/cancel不重复
调用注册的scope callback。
15项receive-worker/download-owner回归通过，
/tmp/aetherscreens-download-scope-drain-tests-20261009.log；iOS unsigned构建
通过，/tmp/aetherscreens-ios-download-scope-drain-20261009.log。
新测试以信号量阻塞注入队列：cancel返回后cleanup信号未发、晚消息拒绝；
解除阻塞后清理callback完成、owned staging为空。整理后的focused测试1/1
通过，/tmp/aetherscreens-download-scope-drain-focused-20261009.log。
这验证队列完成时序，不等于真实provider授权计数或系统选择器真机验收。
本地私有暂存+协调导出尚未完成；不能把最终协调等同全部云盘写兼容。

## 2026-10-09 应用私有接收暂存与协调导出

DownloadCoordinator receive parent从用户destination改为应用temporaryDirectory，
每项仍独立UUID incoming0700，receiver/tree组装与取消清理现有owner规则
保持。网络接收期间不在选中provider目录写暂存。finalizer协调accessor内
新增copyPreparedTree，复制已assembled tree到目标侧自有incoming staging，
以NOFOLLOW openat逐项核验kind、data/resource fork长度，重建新dev/ino
catalog records；随后restore metadata/permissions并RENAME_EXCL提交public
名字。因此能处理跨volume复制，不依赖跨volume rename；复制失败只清理
自有incoming。copy后检查取消，取消时不继续metadata/commit；正在复制
不可中断，scope仍保留至worker停止。原私有树由defer清理。
首轮把header resource34/data42长度字段写反，回归正确拒绝保存并发现；
修正后25项接收/保存回归通过，
/tmp/aetherscreens-private-download-staging-final-tests-20261009.log。
相关最终Release154/154通过，
/tmp/aetherscreens-private-staging-full-regression-20261009.log；iOS unsigned
BUILD SUCCEEDED，/tmp/aetherscreens-ios-private-download-staging-final-20261009.log。
测试实际覆盖复制后的nested/empty/resource、mode/mtime、冲突及write
missing失败；未有物理provider/cross-volume挂载参与，不能据此宣称所有
云盘已兼容。copyItem依赖系统fork/xattr复制，长度校验会拒绝fork缺失；
逐个attribute值尚未独立再次核对。复制需额外临时磁盘空间、不能mid-copy
取消，仍需空间预算/真机验证。新增架构后native live尚需复验。

## 2026-10-09 导出复制支持中途取消

新增Darwin AppleFileCopyCancellableTreeCopy，使用copyfile ALL/RECURSIVE/
EXCL/NOFOLLOW与status callback，设置64KiB BSIZE，COPY_DATA PROGRESS可
观察已复制字节，并在callbacks检查owner取消；recurse/error明确QUIT。
state/context按C API实际传值规则设置（callback函数指针、ctx对象指针），
retained context在state free后释放。copyPreparedTree改为此helper，取消
由原catch清理自有export staging；scope仍到worker停止后释放。
参考Apple SDK copyfile.h及Apple开源实现，未引入新依赖：
https://github.com/apple-oss-distributions/copyfile/blob/main/copyfile.c

初轮新增测试发现copyfile取消会自行删除部分目标，因此用实际progress
计数证明中途停止，允许系统删除或留下正确前缀；另发现递归EXCL不能
单独拒绝已有目录，增加lstat目标存在检查（包括符号链接）再复制。
helper目标只用于自有0700 UUID目录下的新data名字，公共非覆盖仍由最后
RENAME_EXCL保证；不能把先检查路径当成任意共享目录的原子排他保证。
测试8MiB数据实际progress>0且<完整量时取消，源数据完整不变；正常tree
保留空目录/中文文件/resource/xattr，已存在目标拒绝；预取消不创建目标。
修正后focused7/7通过，/tmp/aetherscreens-cancellable-copy-repaired-tests-20261009.log；
最终相关157/157通过，/tmp/aetherscreens-cancellable-copy-full-regression-20261009.log。
iOS unsigned BUILD SUCCEEDED，/tmp/aetherscreens-ios-cancellable-copy-repaired-20261009.log。
取消粒度取决于系统callback与底层I/O，非实时取消保证；真实provider行为、
大型tree峰值空间及新导出架构native网络复验、物理iPhone UI仍待完成。

## 2026-10-09 导出副本空间预检查

copyPreparedTree在目标侧incoming创建前，遍历已验证dev/ino的catalog
记录，汇总data/resource及实际descriptor扩展属性名字/值长度；每条目
追加4096字节overhead及总1MiB余量。checked add/multiply拒绝溢出。
AppleFileCopyDiskSpace通过NOFOLLOW目录descriptor fstatvfs读取bavail和
frsize（无frsize则bsize），低于预算明确失败。估算与属性读取均在worker，
遍历期间检查取消。insufficientSpace独立进入store中文/英文提示“保存目录
空间不足，请释放空间或选择其他目录”，不再只显示一般下载失败。
不是空间reservation：块取整/FS元数据、竞争占用、provider quota仍可能
超出估计，最终I/O错误继续清理owned staging。接收初始private staging
未按未知总量预留最大1GiB，以免错误拒绝普通小文件；流中ENOSPC仍依赖
已有错误/清理路径，当前独立space消息主要覆盖导出preflight。
新增2测试检查预算边界、溢出/invalid item count、真实volume查询不创建
文件、缺失目录拒绝；owner4测试继续通过。最终相关Release159/159零失败，
/tmp/aetherscreens-download-space-final-regression-20261009.log。
iOS unsigned构建成功，/tmp/aetherscreens-ios-download-space-message-20261009.log；
两语言.strings plutil lint通过，diff check通过。未填满实际磁盘或使用真实
provider quota制造ENOSPC，错误提示UI/真机仍未验。新导出路径native live
和跨volume/云盘实际兼容仍需推进，整体Screens/指针/FPS目标未完成。

## 2026-10-09 新私有暂存/可取消导出/预算的网络验收及xattr缺口

05:06实际Mac mini LAN新版coordinated owner目录/资源组合1/1通过（1.933秒），
/tmp/aetherscreens-private-chain-native-live-20261009.log。同一ID桌面连接
连续3次：两次131333bytes完整保存，mode0640与mtime1700000100保持；
第三次目录冲突保留sentinel、无额外incoming、连接仍正常。此次覆盖新
private temporary staging→coordinated copyfile export→budget→metadata→
non-overwrite commit组合，并非沿用旧direct-rename网络结果。

进一步在owned fixture设置com.aethernative.qa=040506，新增独立opt-in
QA_DOWNLOAD_XATTR实际保存断言。05:07、05:09两次验收失败，存盘无该
attribute。新增仅owned opt-in wire观察，15条101 item均extensions.count=0，
/tmp/aetherscreens-private-chain-xattr-wire-live-20261009.log。因此该普通
属性未被当前原生version1发送路径送来；不能归因于copyfile丢已收到
属性，更不能把普通属性网络保留宣称完成。source该xattr由独立SSH xattr
命令复查仍040506，数据/resource/mode/mtime与精确清单均保持；复查后
清理此次UUID远端根，本地fixture test defer清理。Mac Python os.setxattr
不可用，改用系统xattr命令，没有改变生产文件或放宽权限。

真实xattr opt-in测试仍保留失败要求，默认skip不算验收通过。需要继续
检查原生发送协议版本/属性协商，不能把支持有ext1合成输入等同原生
sender能发送任意属性。应用代码未发布；真机、云盘/跨volume及其他
Screens范围仍未完成。


2026-10-09 05:13 — native WhereFroms acceptance
The separately opted-in coordinated folder download passed against the
actual Mac mini: 1 test, zero skips/failures, 1.965 seconds. Three requests
used the same native ID/connection: two complete saves and one protected
destination conflict. Each nested file emitted 137 extension bytes.
Both successful saves retained the binary-plist WhereFroms URL; data,
resource fork, mode and modification-time assertions also passed.
Log: /tmp/aetherscreens-wherefroms-native-live-20261009.log.
SSH independently verified the exact owned source tree, all bytes, resource
fork, mode, time and source plist before removing only that UUID fixture.
The arbitrary com.aethernative.qa attribute limitation remains; this test
does not replace its failed acceptance. Physical iOS/provider/UI acceptance
and the wider Screens alignment remain incomplete.


2026-10-09 05:15 — preserve newer edge-pan projection
ViewportProjection previously replaced its immediate canvas with every
changed SwiftUI layout. An acknowledgement of the first pan could therefore
undo a second pointer sample already applied locally. Keep a bounded history
of pending canvas positions and retire acknowledged samples while preserving
the newest projection. Unrecognized geometry (resize/zoom/layout change)
still replaces the projection and clears history; zero deltas add no work.
The new regression feeds two pans before the first acknowledgement, checks
the latest position through both acknowledgements, then verifies resize.
Release ViewportTrackingTests, ViewportZoomTests and RFBRemoteCursorTests:
16 tests, zero failures/skips. Log:
/tmp/aetherscreens-pointer-projection-regression-20261009.log.
git diff --check passed. No physical iPhone UI/FPS acceptance or app release
is implied; those remain pending.


2026-10-09 05:16 — iOS edge-follow integration build
The current projection fix builds successfully for generic/platform=iOS
with CODE_SIGNING_ALLOWED=NO, using the existing iOS application project.
Log: /tmp/aetherscreens-ios-pointer-projection-20261009.log.
Release input regression broadened to trackpad motion, absolute hardware
pointer mapping, held-button preservation, cursor decoding, viewport tracking
and zoom: 27 tests, zero failures/skips.
Log: /tmp/aetherscreens-input-integration-regression-20261009.log.
This is an unsigned build and core regression only. No phone installation,
UI automation, pointer appearance or frame-time acceptance occurred.


2026-10-09 05:18 — rounded pan acknowledgements
Pending canvas origins now accept rounding differences up to 0.000001
screen points, with exactly equal canvas dimensions. This reconciles
input-layer origin accumulation with SwiftUI centered-origin recomputation
without mistaking a zoom/resize for a pan acknowledgement. A regression
uses nextUp/nextDown on an earlier acknowledgement, verifies a newer
projection survives, then checks that a changed width resets it.
Release cursor/trackpad/tracking/zoom tests: 28, zero failures/skips.
Log: /tmp/aetherscreens-rounded-pan-regression-20261009.log.
git diff --check passed. This latest rounding adjustment has core compile
and tests; the previous exact-match adjustment passed unsigned iOS build.
A refreshed iOS build and physical UI/FPS acceptance remain pending.


2026-10-09 05:21 — refreshed iOS build and full local core gate
Latest rounded pan acknowledgement implementation compiled for generic iOS
with signing disabled. Log: /tmp/aetherscreens-ios-rounded-pan-20261009.log.
Full current Release core test suite completed locally: Executed 701 tests, with 28 tests skipped and 0 failures (0 unexpected) in 124.762 (124.878) seconds.
Log: /tmp/aetherscreens-full-core-refresh-20261009-0519.log.
Environment-gated live tests remain explicit skips; this local core gate
does not establish physical iPhone pointer appearance, animation/FPS,
provider file selection/save, live clipboard interoperability or remaining
Screens feature parity. No phone install or app publication occurred.


2026-10-09 — hardware pointer cancellation stops moving the desktop
IOSRemoteInputView.updateHardwareTouch previously called positionHardware
even for touchesCancelled, before releasing buttons. A terminal cancellation
location could therefore emit a held-button pointer move and pan the viewport.
Cancellation now clears the previous hardware location without positioning;
existing button transition logic still releases the hardware button chord.
Ordinary began/moved/ended positioning remains unchanged. Generic unsigned
iOS build succeeded; git diff --check passed.
Log: /tmp/aetherscreens-ios-pointer-cancel-20261009.log.
The previous full core gate (701 tests, 28 explicit skips, zero failures)
predates this UIKit-only change; it is not a physical cancellation/UI test.
Real indirect-pointer cancellation during app/focus transitions remains a
physical-device acceptance item, alongside arrow display and frame timing.


2026-10-09 05:24 — cancellation during upload snapshot copying
Replaced FileManager.copyItem in coordinated upload snapshot preparation
with the existing metadata-aware cancellable system tree copier. The caller's
Task.isCancelled closure is now retained for the synchronous copy callbacks;
copy cancellation maps to the existing upload preparation cancellation error.
Owned UUID staging cleanup and original-catalog reconciliation are preserved.
A new actual 8 MiB copy regression cancels on its first data-progress callback,
requires positive progress smaller than the full file, explicit cancellation
and an unchanged source. Snapshot/copier/preparation tests: 11 passed, no
skips/failures. Log: /tmp/aetherscreens-upload-copy-cancel-20261009.log.
Generic unsigned iOS build succeeded; log:
/tmp/aetherscreens-ios-upload-copy-cancel-20261009.log.
git diff --check passed. Cancellation waits for system copy callbacks;
file-provider download waits/coordination and blocking storage I/O are not
proved immediately interruptible. Physical picker/provider/UI acceptance
and native transfer after this snapshot implementation change remain pending.
The previous 701-test full gate predates this change.


2026-10-09 05:26 — upload temporary-volume space preflight
Upload snapshot preparation now estimates source data/resource forks plus
serialized attributes with checked arithmetic, then uses the owned temporary
root's actual volume free-space check before copying. Existing disk-space
helper adds per-item overhead and reserve. Insufficient space gets a dedicated
English/Chinese notice rather than the generic source-access/limits error.
Snapshot/copier/disk-space tests: 9 passed, zero failures/skips.
Log: /tmp/aetherscreens-upload-space-preflight-20261009.log.
Generic unsigned iOS build succeeded; log:
/tmp/aetherscreens-ios-upload-space-20261009.log. Both localization resources
passed plutil lint; git diff --check passed.
This estimate is not a reservation, actual provider quota or exhaustive
metadata allocation guarantee. No disk was intentionally filled and the
real low-space UI/provider acceptance remains pending. The latest full
701-test core gate predates this upload preparation change.


2026-10-09 — upload space error propagation
Snapshot copyfile ENOSPC now maps to the dedicated insufficient-space error,
so space consumed after the preflight uses the same accurate UI notice.
A narrow internal preflight hook retains the real production volume checker
by default. Its regression rejects space while the owned staging directory
is empty, requires the specific error, checks no copy progress occurs and
verifies source bytes unchanged. This is simulated space rejection, not
physical disk exhaustion. Snapshot/disk-space Release tests passed; log:
/tmp/aetherscreens-upload-space-error-tests-20261009.log.
git diff --check passed. Latest implementation has core compile/tests;
refreshed iOS build and real ENOSPC/provider/UI acceptance remain pending.


2026-10-09 — current audit refreshed
Latest upload space-error implementation passed generic unsigned iOS build:
/tmp/aetherscreens-ios-upload-space-errors-20261009.log.
Updated the audit summary to distinguish current native transfer evidence,
current targeted tests and historical full gates. Phone availability notes
are explicitly historical; physical workflows and remaining parity gaps
remain unaccepted. git diff --check passed.


2026-10-09 05:30 — refreshed actual native upload after snapshot changes
The current coordinated upload opt-in passed against the actual Mac mini:
1 test, no skips/failures, 1.835 seconds. The snapshot was prepared with
the current cancellable copy and space preflight; the original local source
was then overwritten before upload. The task completed with actual server
result, stable-copy bytes stayed original and changed source stayed unchanged.
Independent SSH verification compared all 512 remote bytes against the
original fixture, verified the exact owned non-symlink tree and removed only
that UUID directory. Log:
/tmp/aetherscreens-upload-snapshot-native-refresh-20261009.log.
This covers a small ordinary-file native upload; large files, folders,
provider waits, UI drag/drop and physical iOS acceptance remain outstanding.


2026-10-09 05:32 — current coordinated native folder upload
Extended the owned opt-in coordinated upload test with a folder fixture:
root/nested directories, 131073 data bytes, 257 resource bytes, empty file
and a three-byte sibling. The current snapshot/cancellable copy/preflight
produces a stable source, then the original data file is overwritten before
upload. Catalog normalization is compared against the original native
catalog for every item; file fork metadata is independently recollected.
Actual Mac mini gate: 1 test, no skips/failures, 1.703 seconds, authoritative
completion with 131333 transferred bytes. Independent SSH checked the exact
non-symlink remote tree, every data/resource/sibling byte and empty-file size
then removed only the owned UUID destination.
Log: /tmp/aetherscreens-coordinated-folder-upload-live-20261009.log.
Build-only default opt-in skip: /tmp/aetherscreens-coordinated-folder-upload-build-20261009.log.
This establishes this moderate owned folder upload, not large-file/provider
limits, physical iOS picker/drag/drop, cancellation or full Screens parity.


2026-10-09 05:33 — 8 MiB native coordinated folder upload
Added separate owned opt-in AETHERSCREENS_QA_UPLOAD_LARGE=1 to exercise
8 MiB data through the latest stable snapshot and bounded native coordinator,
with the same nested/empty/sibling/resource-fork fixture. The original data
is overwritten after snapshot creation, requiring upload from the stable copy.
Actual Mac mini result passed: 1 test, no skips/failures, 1.860 seconds,
8388868 completed bytes. Independent SSH verified every data/resource/sibling
byte, empty-file size and exact non-symlink tree before owned cleanup.
Log: /tmp/aetherscreens-coordinated-large-upload-live-20261009.log.
Build/default opt-in skip: /tmp/aetherscreens-coordinated-large-upload-build-20261009.log.
This is an 8 MiB acceptance sample, not the 1 GiB limit, throughput benchmark
or evidence of UI smoothness/provider/cancellation/drag-drop acceptance.


2026-10-09 — remote canvas file-URL drop entry
RemoteDesktopView now accepts a single local file URL dropped on its canvas
when native upload is available and no competing sheet is open. The drop
preselects FileUploadSheet; the user still confirms destination and Send.
Non-file URLs, multiple selections and busy/observe/disconnected sessions
are rejected. The selection is cleared on sheet dismissal and menu entry.
FileUploadSheet gained an optional initial selection, preserving the picker.
Mac core Release build and generic unsigned iOS application build succeeded:
/tmp/aetherscreens-mac-upload-drop-build-20261009.log and
/tmp/aetherscreens-ios-upload-drop-20261009.log. git diff --check passed.
This is implementation/build evidence only: actual Finder/Files URL delivery,
provider access lifetime, hover/animation and phone drag/drop still require
UI acceptance. Multiple-item drag, outgoing download drag and complete native
Screens drag/drop parity remain unimplemented or unaccepted. The actual
8 MiB native upload gate predates this UI entry; it proves the backend only.


2026-10-09 — scoped file-drop visual feedback
The remote canvas file-URL drop target now displays an accent border and
localized file/folder prompt while targeted and upload is available. The
feedback is noninteractive, clears on accepted drop, and uses a short opacity
animation confined to its overlay; Reduce Motion disables that animation.
The shared canAcceptFileDrop gate suppresses competing-sheet/busy states.
Final scoped feedback implementation passed Mac Release core build and
generic unsigned iOS application build:
/tmp/aetherscreens-mac-scoped-drop-feedback-20261009.log and
/tmp/aetherscreens-ios-scoped-drop-feedback-20261009.log.
Both language resources passed plutil lint; git diff --check passed.
This remains unrendered on an accepted test device. Actual hover behavior,
long localized text, device provider access and frame-time impact require
physical/UI acceptance; no complete drag/drop or fluidity claim is made.


2026-10-09 05:40 — snapshot failure cleanup verified
Strengthened the actual-copy cancellation and simulated preflight-rejection
regressions to record the exact owned staging root through the internal
preflight callback. Both now require that root to be absent after failure,
along with explicit error identity and unchanged source data. Cancellation
still occurs after positive actual data progress below the complete file.
All 5 snapshot tests passed, zero skips/failures.
Log: /tmp/aetherscreens-snapshot-failure-cleanup-20261009.log.
git diff --check passed. This turn changed tests only; no provider-wait,
physical GUI or crash/force-termination cleanup acceptance is implied.


2026-10-09 — current full local core regression
Executed 703 tests, with 28 tests skipped and 0 failures (0 unexpected) in 124.678 (124.793) seconds.
Log: /tmp/aetherscreens-full-core-current-20261009-0541.log.
This source includes current snapshot cancellation/space error handling,
canvas file-URL drop feedback, pointer projection and cleanup regressions.
Live opt-in tests remain explicit skips; actual native upload acceptance
is recorded separately for small file, folder and 8 MiB folder probes.
Read-only devicectl identified the paired iPhone 12 Pro with disconnected
tunnel over localNetwork; no device installation or UI run occurred.
Physical UI/FPS/provider workflows and remaining Screens parity stay open.


2026-10-09 — current native desktop connection refresh
Current Release client passed the explicitly authenticated Mac mini desktop
gate over LAN 192.168.50.226, without keyboard/pointer injection: connection
completed at 0.618 seconds, genuine 3840x2160 pixel frame at 1.735 seconds,
then remained connected for the test's 60-second stability window.
Log: /tmp/aetherscreens-current-live-desktop-stability-20261009.log.
This confirms current authentication/frame reception and sampled connection
stability. Fourteen pixel callbacks on this uncontrolled desktop are not FPS
or input/animation latency measurements. It does not replace 30-minute
physical iPhone interaction, cursor presentation or UI/provider acceptance.
No public release, device installation or remote system reconfiguration.


2026-10-09 — actual byte amounts in transfer presentation
FileTransferProgressView now shows formatted transferred byte amounts from
the existing task model. Known-size jobs show transferred / total; unknown
downloads show transferred alone until confirmed size arrives. This uses
system ByteCountFormatter and monospaced digits, no additional polling or
new progress counters. Existing indeterminate and completion logic remains.
Generic unsigned iOS application and Mac Release core builds passed:
/tmp/aetherscreens-ios-transfer-byte-progress-20261009.log and
/tmp/aetherscreens-mac-transfer-byte-progress-20261009.log.
git diff --check passed. This presentation addition has not been rendered
on an accepted physical device; readability and ongoing-transfer FPS remain
UI acceptance items. Completed-file reveal/share actions remain absent.


2026-10-09 — completed download file-location entry
The download finalizer now retains the actual committed URL and original
selected access root in its successful result. FileTransferTaskStore keeps
this session-only record solely for completed downloads; dismissing removes
it. Upload/non-file location records are rejected and old completion tokens
remain rejected. No result-name bytes are converted into a path.
Mac FileTransferProgressView offers Show in Finder for such results, briefly
reacquiring the selected folder security scope while handing the actual URL
to NSWorkspace. No Finder operation was executed by this turn.
Store lifecycle and download coordinator tests: 14 passed, zero skips/failures.
Log: /tmp/aetherscreens-saved-file-result-tests-20261009.log.
Generic unsigned iOS build succeeded; log:
/tmp/aetherscreens-ios-saved-file-result-20261009.log. Both localization files
passed plutil lint; git diff --check passed.
Actual Finder location, external-provider access and moved/deleted file
behavior remain UI acceptance items. iOS share/reveal is not implemented
by this Mac-only entry; no full Screens transfer parity claim is made.


2026-10-09 — iOS completed-download system share entry
Completed download tasks now offer a 44-point Share action on UIKit. The
selection retains the actual committed URL/access-root result and presents
UIActivityViewController through SwiftUI. A coordinator opens the selected
folder security scope; completion or representable dismantling closes the
existing idempotent scoped-access owner. This does not copy/delete the user's
saved file, reconstruct a filename path or automatically perform an activity.
Final localized generic unsigned iOS build passed:
/tmp/aetherscreens-ios-download-share-localized-20261009.log.
Mac Release core compatibility build passed:
/tmp/aetherscreens-mac-download-share-compat-20261009.log.
Both localization resources passed plutil lint; git diff --check passed.
System activity presentation, iPad presentation, external-provider access,
actual exporting and cancellation remain physical/UI acceptance items. No
share activity, device installation or release was performed this turn.
The 14-test saved-result lifecycle gate predates this UIKit share wrapper.


2026-10-09 05:57 — actual saved-file record lifecycle
Download coordinator regressions now verify that ordinary-file and directory
commits publish their actual saved location and original access root. A
conflict publishes no location. The store cancellation regression rejects a
late saved-file result and retains cancelled state without a reveal record.
An initial directory assertion compared URL representation, failing only
because the expected URL had a trailing slash. Corrected it to compare actual
filesystem paths, directory resource type and access root; no production
path/result behavior was changed. Final 15 tests passed, zero skips/failures.
Log: /tmp/aetherscreens-saved-file-commit-lifecycle-final-20261009.log.
Earlier failed assertion log remains:
/tmp/aetherscreens-saved-file-commit-lifecycle-20261009.log.
git diff --check passed. This tests real filesystem commit/result plumbing,
not Finder or UIActivityViewController physical presentation/provider access.


2026-10-09 05:59 — persisted download progress during reception
The receiver's acknowledged staging-byte counts now reach the task store
through an identity-guarded main-actor callback. The lock-protected finalizer
still records every exact count, while progress publication is limited to
one per 0.1 seconds on incoming data (no idle timer). Final completion always
uses the exact committed total, with saved location available only then.
A real worker regression delivers catalog and data without the terminal
command, waits for actual three-byte progress, requires unknown total and
transferring state, no saved-file record and an empty public destination;
it then cancels and drains worker cleanup. Coordinator/store tests: 16 passed,
zero skips/failures. Log:
/tmp/aetherscreens-download-live-progress-tests-20261009.log.
Generic unsigned iOS build succeeded; log:
/tmp/aetherscreens-ios-download-live-progress-20261009.log.
git diff --check passed. Uploaded bytes remain indeterminate until native
server save acknowledgement; local queued writes are not remote progress.
Physical UI/FPS and current live download interoperability remain unaccepted
for this latest progress change.


2026-10-09 06:00 — native download refresh after progress/result changes
Current opt-in coordinated directory download passed against the actual Mac
mini: one test, no skips/failures, 1.965 seconds. Two successful saves and
one protected local destination conflict share the same native connection
and session ID. Data/resource/sibling bytes, empty file, exact tree, mode,
modification time and binary-plist WhereFroms attribute assertions passed.
Log: /tmp/aetherscreens-download-progress-native-refresh-20261009.log.
Independent SSH verified the exact owned source tree, all data/fork bytes
and metadata remained unchanged, then removed only its UUID root.
The previous core result-record tests establish actual saved URLs; this
live gate verifies current backend interoperability, not share/Finder UI
presentation, progress frame rate or physical iPhone fluidity.


2026-10-09 06:02 — bounded progress cadence evidence
Extracted the production download presentation cadence into a small value
type owned under the finalizer lock. It keeps the 0.1-second interval and
also rejects unchanged/regressing byte counts and invalid timestamps before
creating main-actor progress tasks. Exact commit counts remain separate.
A synthetic one-second 1000-block stream requires only 9–10 publications,
and a later larger count resumes publication. Repeated/invalid/backward
samples are independently covered. Combined cadence/store/actual receiver
commit/cancel tests: 18 passed, zero skips/failures.
Log: /tmp/aetherscreens-download-progress-cadence-20261009.log.
Generic unsigned iOS build passed:
/tmp/aetherscreens-ios-download-progress-cadence-20261009.log.
git diff --check passed. This bounds callback scheduling in the tested
stream, not device FPS/hitches, main-thread latency or full Screens parity.
The current native download gate predates this unchanged-count suppression.


2026-10-09 06:04 — bounded terminal history no longer blocks new transfers
FileTransferTaskStore validates duplicate IDs and the incoming job before
admission. At its 32-record cap it now dismisses the oldest terminal record,
including only its encoding/saved-location metadata, and admits the new job.
If all records remain active it still refuses admission. Active jobs and
workers are never evicted or cancelled by history management.
The regression fills 32 completed records, rejects a duplicate without
eviction, admits a fresh job, verifies old result-token rejection/location
cleanup and checks a real saved fixture file remains unchanged. Existing
32-active-job refusal/dismissal protections still pass. Store tests: 12
passed, no skips/failures. Log:
/tmp/aetherscreens-transfer-history-admission-20261009.log.
Generic unsigned iOS build passed:
/tmp/aetherscreens-ios-transfer-history-admission-20261009.log.
git diff --check passed. This is session-history admission behavior, not
multi-transfer scheduling or physical long-session UI acceptance.


2026-10-09 — full current local core gate after download/UI/history work
Executed 709 tests, with 28 tests skipped and 0 failures (0 unexpected) in 124.823 (124.929) seconds.
Log: /tmp/aetherscreens-full-core-current-20261009-0605.log.
This supersedes the earlier 703-case full local gate. Current scope includes
saved-result lifecycle, receiver progress, cadence and bounded history.
UIKit sharing compiles separately but is not executed by this macOS suite.
Live opt-ins remain skipped; actual native upload/download/desktop gates
are recorded separately. Physical iPhone pointer/FPS/provider/drag/drop and
remaining native clipboard/Curtain/cloud/quality parity stay unaccepted.


2026-10-09 — active/newest transfer presentation
The transfer overlay now displays active jobs first, newest first within
each state group, followed by newest terminal history. Stable job UUIDs
remain the view identities; task-store order and ownership are unchanged.
Insert/remove opacity transitions use a short animation tied only to the
visible ID sequence, not per-block progress; Reduce Motion disables it.
Generic unsigned iOS application and Mac Release core builds passed:
/tmp/aetherscreens-ios-transfer-visible-order-20261009.log and
/tmp/aetherscreens-mac-transfer-visible-order-20261009.log.
git diff --check passed. This is UI implementation/build verification only;
rendered scrolling, accessibility, row movement and FPS remain unaccepted.
It does not automatically reposition an already scrolled history viewport.
The 709-case full gate predates this display-only ordering addition.


2026-10-09 — focus newly active transfer in scrolled history
The transfer overlay uses ScrollViewReader with stable explicit job row IDs.
It scrolls to the newest active row only when that row's identity changes
(or initial view presentation), not on byte progress updates. No active
job means no forced scroll, so completion/history browsing remains stable.
A short scroll animation respects Reduce Motion.
Generic unsigned iOS and Mac Release core builds passed:
/tmp/aetherscreens-ios-transfer-scroll-focus-20261009.log and
/tmp/aetherscreens-mac-transfer-scroll-focus-20261009.log.
git diff --check passed. This supersedes the preceding display-order note's
missing auto-focus implementation; actual layout-timing, touch/VoiceOver
scrolling and device frame-time behavior remain physical/UI acceptance.
The 709-case core gate predates these presentation-only additions.


2026-10-09 — scene-local anchored system share presenter
Replaced the SwiftUI sheet wrapping UIActivityViewController with a presenter
attached behind the selected task's Share button. It waits for attachment
and nonempty bounds, presents once, sets iPad popover source view/rect in
that same scene, and installs adaptive/popover dismissal delegates. Activity
completion, outside dismissal or representable teardown idempotently closes
security scope. Selection reset checks its original ID, preventing an old
completion from clearing a newer activity. No global scene/window lookup.
Apple UIActivityViewController documentation explicitly requires popover
presentation on iPad:
https://developer.apple.com/documentation/uikit/uiactivityviewcontroller
Final generic unsigned iOS build passed:
/tmp/aetherscreens-ios-anchored-download-share-final-20261009.log.
Mac Release core compatibility build passed:
/tmp/aetherscreens-mac-anchored-download-share-compat-20261009.log.
git diff --check passed. This is source/build evidence only; actual UIKit
attachment timing, iPad arrow/rotation, activity cancellation and provider
sharing access still need physical UI acceptance. No activity was performed.


### 2026-10-09 06:17 — SSH 私钥加密标记识别

- 将任意 ENCRYPTED 子串识别改为 PKCS#8 加密头或传统 PEM Proc-Type 元数据识别，避免损坏文本被误报为加密密钥。
- `swift test -c release --filter SSHPrivateKeyTests`：4 项通过、0 失败；包括系统 ssh-keygen 生成的 Ed25519、三种 ECDSA 曲线和带口令 OpenSSH 拒绝路径。日志：`/tmp/aetherscreens-ssh-key-header-regression-20261009.log`。
- 未新增加密私钥解密或 RSA 支持；尚未在 iPhone 真机执行导入验收。官网首页与详情页已再次确认使用 icon-v2 和 inset-icon。


### 2026-10-09 — 下载文件分享防重复触发

- 分享记录已经存在时禁用分享按钮，并在动作入口再次检查，避免快速连点替换 selection UUID 后，原 UIKit 分享回调不能清理当前选择。关闭分享后沿现有 onFinished 恢复按钮。
- generic iOS unsigned build 成功，日志 `/tmp/aetherscreens-ios-share-reentry-20261009.log`。此项只证明编译通过，未执行真机快速连点、系统分享取消或文件提供器验收。


### 2026-10-09 06:20 — 设备列表同步生命周期

- syncTailscale 入口拒绝重入和已取消任务；defer 恢复 busy 状态；网络完成后检查取消再合并，取消时不弹错误。
- Release 定向测试 6 项通过，0 失败：新增重入/预取消保护测试以及全部 SessionRegistryTests。日志 `/tmp/aetherscreens-library-sync-lifecycle-20261009.log`。尚未实测在途 API 取消与 iPhone 动画，不将该结果作为真机验收。


### 2026-10-09 06:22 — iPhone 会话顶部触控区域

- UIKit 顶部关闭按钮保留圆形视觉，点击区域扩大为 44 点；选项、输入模式和键盘按钮同为 44 点，标题可用宽度同步缩减 40 点。macOS 按钮尺寸不变。
- generic iOS unsigned build 成功：`/tmp/aetherscreens-ios-session-touch-targets-20261009.log`。ViewportTracking/ViewportZoom/RFBRemoteCursor/ExternalPointerGeometry 共 20 项测试通过、0 失败：`/tmp/aetherscreens-pointer-viewport-current-20261009.log`。
- 这些证据不证明真机顶部栏布局、鼠标箭头或边缘跟随已验收，尚需 iPhone 12 Pro 检查。


### 2026-10-09 06:24 — 当前完整核心回归

- 最新工作树 `swift test -c release` 退出 0：711 项，28 项明确跳过，0 失败，124.925 秒。日志 `/tmp/aetherscreens-full-core-current-20261009-0623.log`。覆盖最近 SSH 加密头识别、同步重入/预取消保护及现有传输、输入、渲染和无画面超时路径。
- 真实 Apple bootstrap/SRP/原生文件传输等 opt-in 项未在这次普通全量测试执行，不能将跳过计入通过。UIKit 分享和顶部栏真机体验也不由该套件证明。
- 只读 devicectl 检查：物理 iPhone 12 Pro 的 localNetwork 记录已配对但 tunnel disconnected，未安装/启动或占用设备。设备 JSON `/tmp/aetherscreens-device-availability-20261009-0623.json`。


### 2026-10-09 06:26 — 延迟采样零值

- PerformanceMetrics 使用独立 hasLatencySample 记录是否初始化，零值不再被当作缺失样本；reset 同时清除该状态。
- PerformanceMetricsTests 16 项通过、0 失败，包括重入/代际防护、静止桌面采样与新增零值/重置测试。日志 `/tmp/aetherscreens-metrics-zero-sample-20261009.log`。前一轮完整 711 项测试早于本次修改；该结果不代表真实远程输入延迟或流畅度测量。


### 2026-10-09 06:27 — 性能面板采样可用状态

- 新增主线程发布的 hasLatencyMeasurements；HUD 数值和状态灯依据该状态，区分有效零值与尚未测量。reset 清除可用状态，发布前再次检查 latency revision，避免回调重入旧样本污染。
- PerformanceMetricsTests 全部 16 项通过、0 失败，日志 `/tmp/aetherscreens-metrics-availability-20261009.log`；Release 编译覆盖 HUD。未执行真实 RTT 或界面自动化验收。


### 2026-10-09 — 传输面板避让顶部操作栏

- UIKit 传输面板普通模式的顶部 inset 从 44 调为 76 点，与扩大后的操作栏留开空间；全屏模式无顶部操作栏时不再预留该 inset。macOS 保持原布局。
- iOS unsigned generic build 成功，日志 `/tmp/aetherscreens-ios-transfer-toolbar-clearance-20261009.log`，同时覆盖最新指标可用状态修改。尚未完成真机横竖屏和全屏截图验收。


### 2026-10-09 06:30 — 自动重连策略基础（未接入）

- 重查官方 https://support.edovia.com/en-GB/screens-5/faq/release-notes ，自动重连为 Screens 行为要求。当前 SessionViewModel 尚无自动重连 task，仅有手动 reconnectSession。
- 新建 SessionReconnectPolicy：初始失败不重试；成功桌面后预算 5 次，1/2/4/8/16 秒退避；成功恢复重置预算；主动 stop 后迟到画面不能重启。策略测试 2 项通过、0 失败，日志 `/tmp/aetherscreens-reconnect-policy-20261009.log`。
- 尚未接入产品，不宣称自动重连实现。后续必须接入代际保护、前后台状态、显式关闭和手动重连取消，并通过真实 TCP 断线/恢复/预算耗尽测试。SSH 信任拒绝和认证失败不得无限重试。


### 2026-10-09 06:32 — 自动重连首次接入（运行验收未完成）

- SessionViewModel 成功首帧后启用有限退避；断开/失败回调排队重试，task UUID/foreground/lifecycle/close 检查防止旧等待恢复连接。显式 start/reset 与自动 start 保留预算分离；endSession 停止策略，隐藏会话取消等待，激活时可重新排队。
- Release 策略/InputRecovery/SessionRegistry 9 项通过、0 失败，日志 `/tmp/aetherscreens-reconnect-lifecycle-20261009.log`。现有测试尚未运行实际定时重连路径，不作为功能完成证据。
- 必须追加真实本地 TCP 断线恢复、关闭等待、后台等待、预算耗尽与重连后输入验证；SSH transient failure 进入剩余预算的路径及认证提示策略仍需核对。尚未完成 iOS 编译与真机验收。


### 2026-10-09 06:34 — 自动重连实际本地 TCP 验证

- 新增真实 NWListener/RFB 握手/1024²像素流会话测试：服务端取消首个 socket 后自动收到第二连接的新桌面，保留 zoom 2.5 和 offset(20,30)，清除 Cmd/拖动，替换输入代际。恢复后显式关闭未再次连接。
- 第二测试覆盖等待期间显式关闭和隐藏：1.3 秒后 listener 仍只有首个连接；重新激活隐藏会话后按剩余退避收到第二连接和新画面。两项测试均通过、0 失败，7.216 秒，日志 `/tmp/aetherscreens-automatic-reconnect-cancel-tcp-20261009.log`。
- generic unsigned iOS build 成功：`/tmp/aetherscreens-ios-auto-reconnect-20261009.log`。
- 上述为真实本地 TCP、合成 RFB 服务端证据，不是 Mac mini/物理 iPhone 验收。预算耗尽、SSH 瞬时故障/认证错误策略和真实网络中断仍待补齐。


### 2026-10-09 06:36 — SSH 自动重连错误分类

- SSH setup catch 对 typed closed/timedOut 调用剩余重连预算；cancelled、认证失败、hostKeyRejected、缺失/不支持密钥、invalidForward/invalidData 与未知错误停止策略和等待任务。避免未知协议/身份问题进入自动循环。
- 分类与真实本地 RFB 恢复/关闭/隐藏测试共 5 项通过、0 失败，7.286 秒：`/tmp/aetherscreens-reconnect-ssh-classification-20261009.log`。
- 尚未验证真实 SSH 网络故障；原始 NIO 未分类错误目前保守停止，后续须基于真实错误类型补充网络可恢复映射。尚未重新编译 iOS。


### 2026-10-09 06:38 — 自动重连预算实际 TCP 验证

- 本地 RFB listener 首次完成握手并发送桌面，后续连接接受后立即关闭；实际执行 1/2/4/8/16 秒退避，server 记录首连接加五次重试共六连接，末次失败后再观察两秒无第七连接。测试通过、0 失败，33.238 秒：`/tmp/aetherscreens-reconnect-budget-tcp-20261009.log`。
- 最新 SSH 分类实现 generic unsigned iOS build 成功：`/tmp/aetherscreens-ios-ssh-reconnect-classification-20261009.log`。
- 该证据不代表真实 Mac mini/SSH/iPhone 网络中断验收；未知 NIO 错误分类与重连提示 UI 仍待处理。


### 2026-10-09 06:40 — 自动重连等待提示

- SessionViewModel 发布 isAwaitingAutomaticReconnect，排队后开启，取消/开始连接/收到新桌面后清除；连接状态页中英文提示“连接已中断，正在等待自动重连…”并显示等待指示，仍允许手动重试。
- 实际本地 TCP 等待关闭/隐藏与自动恢复测试新增状态断言，2 项通过、0 失败，7.315 秒：`/tmp/aetherscreens-reconnect-status-20261009.log`。
- 两语言 strings plutil lint 成功，generic unsigned iOS build 成功：`/tmp/aetherscreens-ios-reconnect-status-20261009.log`。未执行真机或截图布局验收。


### 2026-10-09 06:41 — 认证提示等待保护

- VNC/Mac 账户提示进入时取消自动重连等待；schedule 入口拒绝密码提示和 SSH prompt 未结束的会话，避免等待任务打断交互。
- 已结束会话拒绝旧密码提示、账户凭据保存和两个实际本地 TCP 重连/取消测试，共 4 项通过、0 失败，7.336 秒：`/tmp/aetherscreens-reconnect-auth-prompt-20261009.log`。
- 尚未构造成功会话重连后服务端要求重新认证的真实 TCP 场景；该行为仍须专项验证，不将现有认证单测视为该路径验收。


### 2026-10-09 06:42 — 重连后实际 TCP 重新认证等待

- 本地 RFB 服务首个连接允许 None 并发送桌面；socket 中断后的第二连接仅提供 VNC authentication 和 16 字节 challenge。会话自动恢复到密码提示，等待 2.2 秒后提示仍保持且 server connectionCount 为 2，无第三连接；显式关闭清除提示。
- 专项测试通过、0 失败，3.327 秒：`/tmp/aetherscreens-reconnect-reauth-tcp-20261009.log`。测试未输入密码/完成第二次认证，不宣称真实认证成功或 iPhone UI 验收。


### 2026-10-09 06:43 — 重连后重新认证完整本地 TCP 流程

- 扩展前一项实际 TCP 测试：密码提示稳定等待后，提交 QA-only（temporary/不保存钥匙串）；服务端比对固定 challenge 的 VNCAuthCrypto 响应后才发送 SecurityResult 成功和新桌面。第二连接恢复 connected/hasReceivedFirstFrame，提示关闭，连接总数仍为 2。
- 专项测试通过、0 失败，3.410 秒：`/tmp/aetherscreens-reconnect-reauth-complete-20261009.log`。响应比较共享已有 VNC 编码器，仅验证流程与传输；不作为独立密码算法 oracle，不代表真实 Mac/SSH/物理 iPhone 认证验收。


### 2026-10-09 06:45 — 用户取消认证终止自动重试

- cancelPasswordPrompt 先停止策略/计时器，再清理认证和断开；自动重连内部改为非用户取消的清理路径，保留预算。
- 新真实本地 TCP 场景：首帧→中断→第二连接要求密码→取消→2.2 秒没有第三连接/提示→手动重连产生第三连接和新密码提示。与正常恢复、完整认证和隐藏/关闭共 4 项通过，0 失败，14.096 秒：`/tmp/aetherscreens-reconnect-user-cancel-20261009.log`。
- generic unsigned iOS build 成功：`/tmp/aetherscreens-ios-auth-cancel-20261009.log`。仍不是物理 iPhone/真实 Mac 的 UI 和认证验收。


### 2026-10-09 06:49 — 自动重连接入后完整核心回归

- 当前 `swift test -c release` 退出 0，720 项、28 明确跳过、0 失败，172.858 秒。日志 `/tmp/aetherscreens-full-core-current-20261009-0646.log`。包含新增自动重连实际本地 TCP 测试和所有已有核心门禁。
- git diff --check 通过；更新对齐清单顶部当前 gate 和自动重连接入范围。真实 Apple/SSH/iPhone 门禁及 UIKit 流畅性仍不能由此套件证明，不宣称完整 Screens 对齐。


### 2026-10-09 06:52 — SwiftNIO SSH 网络错误分类

- 依据当前依赖源码 IOError/ChannelError/NIOConnectionError，增加 socket refused/reset/timeout/unreachable/down/broken-pipe 和已关闭/EOF 允许有限重试；bootstrap 聚合仅所有连接错误均为可恢复 IOError 才重试。认证/主机身份/未知错误仍停止。
- 新真实本地 SSH refusal 测试先关闭 SSH fixture listener，再执行 tunnel.start；返回错误被识别可重试且未发布 forwarding port。与三项策略测试共 4 项通过，0 失败：`/tmp/aetherscreens-ssh-refused-retry-final-20261009.log`。
- 第一轮夹具在 stop 后访问 echoServer.localAddress 强解包，xctest signal 5；改为 stop 前保存 remotePort 后通过。原失败日志保留 `/tmp/aetherscreens-ssh-refused-retry-20261009.log`。
- 此项为本地真实 socket 错误和策略映射证据，尚未完成整条 SSH+RFB 会话断线自动恢复或真实 Mac/iPhone 验收；最近完整 720 项 gate 早于这次映射修改。


### 2026-10-09 06:53 — SSH+RFB 整条链路自动恢复

- 新实际本地 TCP 测试完成 SSH 认证/host approval/direct-TCP forwarding/RFB 桌面后，关闭 active channels（保留监听器）；自动重建 SSH 并第二次认证/forwarding，收到新桌面，已信任同主机身份无再次提示，zoom 2.5/offset(15,20) 保留，临时 vault 未写入。
- 专项测试通过、0 失败，1.105 秒：`/tmp/aetherscreens-ssh-rfb-reconnect-tcp-20261009.log`。仅证明本地 NIOSSH 测试服务和 RFB fixture 的实际加密转发路径，不等于真实 Mac mini/物理 iPhone 验收。
- 监听端口短暂消失后重新出现的恢复路径和主机身份变化仍需专项验证；当前完整 gate 早于网络错误映射和本测试。


### 2026-10-09 06:55 — 自动重连后的 SSH 主机身份变更

- cancelSSHPrompt 现在停止重试策略/等待，避免断开回调重新发起连接。
- 实际本地 SSH+RFB 会话首帧后停旧 server，同地址/端口启动新 key server；自动重连请求 changed(previous: oldKey) 确认，未发送凭据/未转发。取消后观察 2.2 秒没有新提示，信任仍为 changed，auth/forward 计数为 0。
- 与同身份隧道自动恢复测试共 2 项通过，0 失败，4.419 秒：`/tmp/aetherscreens-ssh-changed-host-reconnect-20261009.log`。不代表真实 Mac/iPhone 验收；本轮修改尚未重新 iOS 编译。


### 2026-10-09 06:57 — SSH 端口短暂不可用后恢复

- 本地 SSH+RFB 成功首帧后停止 listener；保留 1.5 秒空窗，断言首次自动 retry 失败但剩余退避仍启用；同端口/原 host key/原测试密码启动 replacement，后续 retry 自动完成认证/forwarding/新桌面，无再次身份提示。
- 同身份 transient/直接断线恢复/变更身份取消共 3 项通过、0 失败，7.575 秒：`/tmp/aetherscreens-ssh-transient-reconnect-tcp-final-20261009.log`。
- 第一轮夹具新增可选 password 参数遮蔽已初始化 String，引起编译失败；捕获 self.password 修正。原失败日志保留 `/tmp/aetherscreens-ssh-transient-reconnect-tcp-20261009.log`。不宣称真实 Mac/iPhone 网络故障验收。


### 2026-10-09 — UIKit 后台场景接入输入/重连生命周期

- RemoteDesktopView 监听 scenePhase：background 调用 setForegroundSession(false)，释放输入并取消重连等待，active 恢复；inactive 不处理，避免短暂系统覆盖层影响会话。macOS 不接入该规则。
- generic unsigned iOS build 成功：`/tmp/aetherscreens-ios-background-reconnect-20261009.log`，同时覆盖近期网络错误分类和 SSH 身份取消逻辑。
- 已有核心隐藏会话/恢复测试不等于真实 UIKit 场景通知，物理 iPhone 后台/前台验收仍待执行。当前 foreground=false 也会停止会话文件传输；未新增后台传输保证。


### 2026-10-09 07:00 — 网络错误映射边界

- 新边界测试通过：IOError refusal/Channel connectTimeout/eof 可恢复；EACCES/EINVAL、unsupported operation、认证/host identity/协议错误和 CancellationError 不可自动重试。
- 与真实 SSH refusal 和策略测试共 5 项通过、0 失败：`/tmp/aetherscreens-reconnect-error-boundaries-20261009.log`。为策略边界证据，不代表真实 iPhone UI 验收；整体对齐仍未完成。


### 2026-10-09 07:01 — 物理 iPhone 实际连接状态复核

- devicectl device info details 针对指定物理 UDID 成功，transport localNetwork/tunnel connected/developer mode enabled。此前列表 tunnel disconnected 不足以判断设备不可访问，此处修正该推断。
- lockState 实际成功返回 passcodeRequired=true/unlockedSinceBoot=true；当前需要解锁。日志和 JSON：`/tmp/aetherscreens-iphone-details-20261009-0701.*`、`/tmp/aetherscreens-iphone-lock-20261009-0701.*`。未安装/启动或操作手机。
- 已请求解锁并确认约 15 分钟独占窗口，避免 AetherRoute 任务切换应用；用户可选继续代码、真机稍后。


### 2026-10-09 07:04 — 最新完整核心门禁

- `swift test -c release` 退出 0：725 项、28 明确跳过、0 失败，179.045 秒。日志 `/tmp/aetherscreens-full-core-current-20261009-0702.log`。包含近期 SSH refusal/端口恢复/主机密钥变更取消/整链路重连和策略边界测试。
- 更新对齐清单当前 gate；物理 iPhone 网络详情读取成功但 passcodeRequired=true，独占窗口问题尚待用户答复。未占用手机；仍不宣称完整 Screens 功能/UI/流畅性验收。


### 2026-10-09 — 自适应显示质量实现边界核对

- 已查当前质量 UI/store/session 和 RFB 编码协商，只有手动色深，无 Tight 像素解码或自适应协商。核对 RFB 主协议确认 JPEG quality 为 server hint，不能用反复切色深重连冒充压缩自适应。
- 新增 `docs/adaptive-quality-implementation.md`，记录解码完整性、四 zlib stream/filter、协商边界、抗抖采样、真实 TCP/Apple server/物理验收要求。当前未启用自动模式，后续先实现完整 decoder。
