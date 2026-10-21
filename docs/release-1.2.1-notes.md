# AetherScreens 1.2.1 Release Notes

Build: 2026101602. Official Patch Release.

## Key Fixes & Improvements

### 1. Windows RDP Direct Drag-and-Drop File Transfer
- Dragging files or folders directly from macOS Finder into an active Windows RDP session now seamlessly stages and publishes files via the Microsoft RDP Clipboard Virtual Channel (`MS-RDPECLIP`).
- Automatically sends an active paste shortcut (`Ctrl+V`) to the remote Windows session upon file publication, enabling direct drop-to-desktop or drop-to-folder workflow in Windows Explorer.
- The File Transfer sheet now provides specialized Windows RDP transfer guidance and a dedicated "Send to Windows" action.
- File transfer history recording logs every RDP file transfer with timestamped destinations.

### 2. High-Definition Desktop Resolution & Dynamic Aspect Ratio
- Upgraded the default Windows RDP desktop framebuffer resolution from blurry 1280×720 to crisp 1920×1080 (Full HD).
- Added configurable desktop resolution selection in both `AddDeviceSheet` and `EditDeviceSheet`:
  - 1920 × 1080 (1080p Full HD) [Default]
  - 2560 × 1440 (2K QHD)
  - 1680 × 1050 (16:10)
  - 1280 × 720 (720p HD)
  - 3840 × 2160 (4K UHD)
- Wired dynamic display control updates through `RDPDisplayControlSession` (`sendSingleMonitorLayout`).

### 3. Pixel-Perfect Remote Desktop Mouse Coordinate Mapping
- Fixed a critical aspect ratio distortion bug in `RemoteDesktopView.swift`: the canvas previously defaulted to the RFB framebuffer size (1024×768) when calculating aspect ratios and scaling mouse coordinates, which caused severe non-linear coordinate shifts in 16:9 RDP sessions.
- Updated mouse coordinate transformation to use `viewModel.remoteDesktopSize` (and fallback to active framebuffer), guaranteeing 100% pixel-perfect click and double-click accuracy on remote Windows icons and windows.

### 4. Localization Parity & Test Suite Expansion
- Added complete English and Simplified Chinese localization strings across all newly added resolution choices, file transfer banners, and button titles.
- Added comprehensive unit tests in `SessionViewModelRDPTests` and `RDPClientSessionTests` covering:
  - RDP desktop resolution preferences and remote size calculation.
  - RDP file upload and direct drop staging.
  - RDP mouse coordinate accuracy without aspect ratio distortion.
  - Safe handling of file publication in disconnected states.
  - Backward-compatible JSON and keychain serialization of desktop resolution properties.

## Verification & Test Results
- Full test suite: **819 tests passed, 30 skipped, 0 failures** in 235 seconds.
- Localization parity test (`LocalizationTests`): 5/5 tests passed with zero catalog omissions.
- Clean build and test environment cleanup verified with `scripts/cleanup_test_artifacts.sh`.
