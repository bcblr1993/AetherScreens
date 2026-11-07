# AetherScreens Release 1.4.1 Notes

**Release Version:** 1.4.1  
**Build Number:** 2026110701  
**Date:** 2026-11-07  

---

### Key Performance Optimizations & Reliability Fixes

#### 1. Zero-Allocation Framebuffer & Metal Rendering Pipeline
- **Direct `CVPixelBuffer` Dirty-Region Blit (`Framebuffer` & `RDPClient`)**:
  - Replaced the per-frame full-screen `CIContext.render` and 8–33 MB intermediate `Data` allocation on software-composited BGRA frames with a direct read-only `CVPixelBuffer` base-address copy limited to the frame's `regionRects` dirty rectangles.
  - Added contiguous single-`memcpy` fast paths in both `Framebuffer.updateRect` and `MetalScreenRenderer.encodeFramebufferUpload` whenever dirty regions span the full framebuffer width.
- **Metal Hardware Lossless Compression & Pixel Compositor Speedups**:
  - Enabled `MTKView.framebufferOnly = true` on macOS and iOS and enforced opaque `1.0` fragment alpha on `BGRX` textures.
  - Vectorized 32-bit pixel fills, palette lookups, alpha plane updates, and surface scaling across `TightPixels`, `TightPalette`, `FrameDecodePipeline`, and `RDPGFXSurfaceCompositor` using `UInt32` pointer operations instead of per-byte `Data` subscripting.

#### 2. Windows RDP Remote Cursor Shapes, Audio & Network Low-Latency
- **Native Windows RDP Cursor Shapes (`RDPRemotePointerUpdate` -> `RFBRemoteCursor`)**:
  - Decoded 32-bit alpha and 24-bit masked/XOR bottom-up Windows pointer bitmaps (arrow, text I-beam, resize handles, hand pointer, hidden cursor) into hardware `NSCursor` / iOS cursor shapes.
- **Low-Latency Audio Queue & Route-Change Recovery (`RDPAudioPlayer`)**:
  - Added generation-guarded buffer completion tracking so `reset()` / `configure()` never corrupts `queuedFrameCount`.
  - Reduced audio latency cap to 350 ms with automatic queue flush on overrun and added `AVAudioEngineConfigurationChange` route recovery (e.g., AirPods switching).
- **RDP Socket `TCP_NODELAY` & Keepalive (`ConnectionPreflight`) + Smart Display Resize**:
  - Enabled `TCP_NODELAY` and TCP keepalive (`SO_KEEPALIVE`, 15s idle / 5s interval / 3 probes) on RDP sockets for lower interactive input latency and fast dead-connection detection.
  - Preserved early `DisplayControl` resize requests issued before DVC readiness and aspect-proportionally clamped monitor layouts exceeding server `maximumMonitorArea`.

#### 3. Input Handling, File Transfer & UI Polish
- **Window Focus & Keyboard Mapping (`SessionWindowManager`, `MacNativeInputHandler`, `TrackpadEngine`)**:
  - Released sticky modifiers and held toolbar keys automatically when a macOS session window resigns key or the app deactivates.
  - Added `Home`, `End`, `PageUp`, `PageDown`, and numpad `Enter` keyCode mappings, guarded non-finite pointer coordinates, and prevented unmapped Command shortcuts from swallowing system menu equivalents.
- **RFB File Upload Live Progress & Complete Batch Validation**:
  - Wired live byte progress callbacks in `AppleFileCopySendWorker` and `AppleFileCopyUploadCoordinator`.
  - Rejected partial multi-file RDP clipboard directory downloads on chunk failure and cleaned up temporary staging directories.
- **Diagnostic Log & Localization Completeness**:
  - Cached static locked `DateFormatter` in `AppLogger.LogEntry` and added missing localization keys (`OK`, `Server`, `Username`, `Cmd`, `Ctrl`, `Opt`, `Shift`) in English and Simplified Chinese.
