# Priorities after the first public release

The first public download targets Apple silicon macOS 14+. iOS/iPadOS remain
source-install clients until physical acceptance and separate distribution are
complete. Shipping this version does not establish parity with Screens.

1. Measure real interaction latency and recovery on the same Mac/network used
   for Screens comparisons. Cover 4K, scrolling, dragging, Chinese IME, Wi-Fi
   interruption and long sessions. Decoder timings and local FPS are separate
   measurements and must not stand in for perceived responsiveness.
2. Investigate server-side scaled framebuffer/adaptive-quality negotiation with
   Apple Screen Sharing. Verify actual negotiated frames and input coordinates
   before exposing a quality setting.
3. Improve connection diagnosis: distinguish device reachability, RFB service,
   authentication and first-frame delivery. Test actionable errors rather than
   inferring that a Tailscale online device has Screen Sharing available.
4. Accept bidirectional plain-text clipboard against real Mac servers, including
   Chinese text and reconnection. Rich text and images need separate support.
5. Add file upload/download with progress, cancellation, integrity verification
   and a documented server/transport requirement.
6. Add device synchronization and native Shortcuts after defining credential
   storage and conflict behavior. URL handling alone is not Shortcuts support.
7. Treat real curtain privacy, SSH tunnelling, remote assistance and additional
   platforms as separate projects. Lock Screen is not curtain mode.

UI automation runs only in the existing Tart `macos27` environment. Physical
iPhone and Apple-server checks remain independent acceptance requirements.
