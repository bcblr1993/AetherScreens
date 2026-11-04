# AetherScreens Release 1.4.0 Notes

**Release Version:** 1.4.0  
**Build Number:** 2026110401  
**Date:** 2026-11-04  

---

### Key Improvements & Fixes

#### 1. Windows RDP Bidirectional File Transfer & Clipboard Reliability
- **Drag-and-Drop & File Transfer HUD**:
  - Dragging files or folders onto a Windows RDP session now positions and focuses the remote target window, waits for `FormatListResponse` acknowledgement before sending `Ctrl+V`, and displays live chunk-by-chunk transfer progress in the unified HUD.
  - Added a top floating badge and toolbar panel for files received from Windows (`Ctrl+C`), supporting direct drag-to-Finder and one-click "Show in Finder".
  - Fixed a regression where copying plain text after transferring a file was ignored by automatic clipboard sync.
  - Fixed a bug where cancelling an active RDP file download disconnected the entire remote desktop session instead of only cancelling the file transfer.
- **Virtual Channel Chunking & Security Hardening**:
  - Implemented multi-chunk reassembly and fragmentation for `MS-RDPECLIP` (`CLIPRDR`) payloads exceeding 1,592 bytes, enabling large file chunk transfers (64 KB blocks) and multi-file directory trees.
  - Added a 64 MB reassembly cap on static virtual channels, a 1 GB / 1,024-file limit on clipboard downloads, and bounded diagnostic packet retention (max 32 entries) during long-running RDP sessions to prevent memory growth.

#### 2. Keyboard Shortcuts, Window Lifecycle & Protocol Stability
- **Clean Mac-to-Windows Shortcut Mapping (`⌘C` / `⌘V` / `⌘X` / `⌘A` / `⌘Z` / `⌘S` / `⌘F`)**:
  - Intercepted Command shortcuts in RDP sessions now release the remote Windows/Super modifier before synthesizing `Ctrl+<Key>`, preventing accidental `Win+Ctrl+<Key>` combinations on Windows.
- **Redesigned Display Quality & Resolution Sheet**:
  - Protocol-aware settings modal for both Windows RDP (32-bit True Color hardware-accelerated status, live resolution badge, Fit-to-Window vs. 1:1 scaling) and macOS Screen Sharing / VNC (adaptive compression and 32-bit / 16-bit color depth).
- **CloudKit Sync & Security**:
  - Preserved Windows RDP protocol selection, custom resolution, audio settings, favorites, and tags across iCloud Sync merges.
  - Enforced App Lock hit-testing and accessibility protection across the main device library and active remote sessions.
  - Guarded RFB buffered read recursion depth and ServerInit/DesktopSize bounds to prevent stack overflow or out-of-bounds allocations.
