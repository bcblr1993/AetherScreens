# Screens alignment and full acceptance audit

Audit date: 2026-10-01. Existing notarized candidate: `2eea898`. Reference: [Screens 5 official feature index](https://help.edovia.com/en/screens-5/features/).
This is a completion checklist, not a claim of parity. Unit tests, simulator
screenshots and signed builds do not replace physical input/gesture acceptance.
The release remains a draft until the user has reviewed the completed acceptance.

| Requirement | Current implementation and evidence | Remaining work |
| --- | --- | --- |
| Mac account / VNC connections | ARD type 30 and VNC implemented; real Mac authentication, frame and 60-second session passed | Physical iPhone account session |
| Interactive shortcut toolbar | Sticky modifiers, common shortcuts, F1-F12; Mac F8 observed remotely | Physical iPhone modifier/shortcut delivery and narrow layouts |
| Touch / trackpad gestures | TrackpadEngine tests and synthetic simulator session | Physical tap, secondary click, drag, pinch, scroll and mode changes |
| Hardware pointing devices | Mac native mouse, drag, context menu and wheel passed | iPad pointer and hardware keyboard acceptance |
| International keyboards / dictation | UTF-8 text drawer and Chinese keysyms passed; NSTextInputClient composition tests | Real IME; supplementary-plane characters; dictation workflow |
| Clipboard transfers | Local clipboard insertion passed; extended protocol parser tests | Actual bidirectional clipboard and rich content transfer; insertion is not parity |
| Curtain privacy mode | System lock shortcut and password restoration passed | Actual remote display blackout while remaining unlocked; lock is not parity |
| Display selection | Framebuffer-derived regions and crop selection | Actual server monitor enumeration and per-display acceptance |
| Adaptive image quality | Raw, Zlib and CopyRect decoding; Metal rendering | Network-dependent quality/compression selection and measured responsiveness |
| Observe / control modes | Explicit Observe Only mode; real Mac frames continue while text, clicks, wheel and clipboard writes are blocked; held modifiers released and control restored | Physical iPhone toggle and input suppression acceptance |
| Reconnect / session recovery | In-session reconnect clears input and restores remote typing | Physical iPhone recovery; network interruption regression |
| Quick connect / session selection | Temporary account/VNC requests and optional saving; installed Mac account connection and received typing passed; iPhone simulator validation, save toggle and error/disconnect flow passed | Physical iPhone quick connection; explicit active/background session choice |
| Secure connections / SSH keys | External Tailscale transport, device import client and Keychain | Real Tailnet route/import acceptance; integrated SSH tunnel/key handling |
| File transfers | No transfer implementation | Bidirectional transfer and received-file verification |
| Data / credential synchronization | Local persistence and Keychain migration | Cross-device synchronization and conflict handling |
| Toolbar customization / keyboard options | Fixed toolbar | Per-device button size, keyboard position, visible buttons/spacers and reordering; keyboard mapping preferences and cross-device persistence |
| On-disconnect actions | Disconnect only | Per-connection Mac hot-corner, lock and logout actions before disconnect; proof on an isolated acceptance desktop |
| URL schemes / automation | No app URL handler | Saved and temporary connection URLs, account/VNC parameters and Observe selection; SSH-key URL support with real tunnel implementation; applicable shortcuts/widgets |
| AirPlay / external display / Pencil | Not implemented | iOS display routing and peripheral acceptance |
| Mac multi-window sessions | A single active sheet | Independent concurrent session windows |
| Wake-on-LAN | Packet construction tests and send-success notice | Real wake verification on an appropriately configured sleeping Mac |
| Discovery / device library / diagnostics | Bonjour discovery visible; add/edit and diagnostics UI covered | Saved devices now use a neutral Saved badge; Tailnet status is distinguished from screen-sharing reachability. Remote API error/recovery acceptance remains. |
| UI consistency / branding | App icon assets on Mac/iOS/site, grouped account forms and readable input bar | Full narrow / empty / loading / error / modal audit on physical devices |
| English / Simplified Chinese | Implemented; core/catalog tests and iOS simulator language switch/persistence pass, Mac switch passes | Physical iPhone acceptance; iPhone 17 and mini switch/persistence and narrow layouts passed |
| Release readiness | 87 latest-source tests (4 environment skips) pass under both package build systems; resource fix passed CI; the earlier 73-test candidate passed notarization, mounted DMG and installed input | Complete functional gates and user review; no public release yet |

Vision Pro, Windows/Linux server support and Screens Connect infrastructure are
listed by the reference product but were not in the requested iPhone/iPad and
Apple-silicon Mac platform scope. Their absence must not be described as supported.

The iOS live test now accepts the Mac username and selects the account password
field. Previously it could only exercise the VNC-password path. The updated account form
simulator test passed. Connection attempts no longer stamp successful-connection
history; a regression test verifies this boundary. Physical iPhone
launch on iPhone 12 Pro was denied because it requires its passcode.
iPhone 16 Pro Max installed and launched; Wi-Fi XCTest failed during IDE
connection bootstrapping, and the USB run currently waits for unlock.

Reference detail checked on 2026-10-01: [Toolbar customization](https://help.edovia.com/en/screens-5/features/toolbar-customization),
[on-disconnect actions](https://help.edovia.com/en/screens-5/features/on-disconnect-actions),
and [URL schemes](https://help.edovia.com/en/screens-5/features/url-schemes).
The remaining-work cells retain these concrete behaviors; existence of a
settings sheet or parser alone is not completion of the corresponding feature.
