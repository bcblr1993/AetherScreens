# Priorities after the first public release

The first public download targets Apple silicon macOS 14+. iOS/iPadOS remain
source-install clients until physical acceptance and separate distribution are
complete. Shipping this version does not establish parity with Screens.

1. Align the core iPhone/iPad interaction flow before adding large features:
   arrow pointer, zoomed trackpad edge-follow (including held-button dragging),
   accurate clicks after pan/zoom, two-finger scrolling, pinch zoom, and
   fullscreen/keyboard transitions. Edge-follow uses a 32-point safety margin,
   clamps to the desktop bounds, and stays disabled in Pan/Observe modes.
   Screens' device-edge swipes and Hot Corner gestures are a separate remaining
   gap; they are not the same behavior as following a zoomed pointer.
2. Measure real interaction latency and recovery on the same Mac/network used
   for Screens comparisons. Cover 4K, scrolling, dragging, Chinese IME, Wi-Fi
   interruption and long sessions. Decoder timings and local FPS are separate
   measurements and must not stand in for perceived responsiveness.
3. Investigate server-side scaled framebuffer/adaptive-quality negotiation with
   Apple Screen Sharing. Verify actual negotiated frames and input coordinates
   before exposing a quality setting.
4. Improve connection diagnosis: distinguish device reachability, RFB service,
   authentication and first-frame delivery. Test actionable errors rather than
   inferring that a Tailscale online device has Screen Sharing available.
5. Accept bidirectional plain-text clipboard against real Mac servers, including
   Chinese text and reconnection. Rich text and images need separate support.
6. Add file upload/download with progress, cancellation, integrity verification
   and a documented server/transport requirement.
7. Add device synchronization and native Shortcuts after defining credential
   storage and conflict behavior. URL handling alone is not Shortcuts support.
8. Treat real curtain privacy, SSH tunnelling, remote assistance and additional
   platforms as separate projects. Lock Screen is not curtain mode.

The user replaced the removed Tart `macos27` environment with the physical
Mac mini on 2026-10-06. Mac UI tests can explicitly select
that host with `run_macos_vm_ui_qa.py --host`. Physical iPhone and Apple-server
checks remain independent acceptance requirements.

Reference: [Screens 5 cursor and gesture documentation](https://help.edovia.com/en/screens-5/features/cursor-control-modes-and-other-gestures).
