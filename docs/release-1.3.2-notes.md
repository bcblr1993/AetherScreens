# AetherScreens 1.3.2 Release Notes

Build: 2026102103. Patch release for the Windows RDP features added in 1.3.0 and 1.3.1.

## Fixes

### 1. Windows → Mac file clipboard no longer hangs
- A lost `FileContentsResponse` previously suspended the download forever: the 8-second per-chunk
  timeout could not fire because the waiting task ignored cancellation. Each chunk request now
  resolves exactly once — by response, timeout or cancel — and the remaining files still complete.
- Disconnecting or starting a new copy cancels any in-flight request immediately.

### 2. Remote file paths are confined to the download directory
- File names announced by the Windows host are now sanitized. Components such as `..` are
  rejected, so a hostile server can no longer write outside the temporary clipboard folder.

### 3. Large files are streamed to disk
- Downloaded files are written chunk by chunk instead of being held fully in memory.
- Clipboard download folders older than 24 hours are removed at the next download.

### 4. Auto-Fit Resolution works for every window width
- MS-RDPEDISP requires an even width between 200 and 8192 pixels. Odd window widths were silently
  dropped, so roughly half of all resizes had no effect. Sizes are now rounded and clamped.

### 5. Clipboard and drag-and-drop correctness
- Files received from Windows are no longer echoed back when the pasteboard returns the same paths
  with a trailing slash or `/private` prefix.
- Folders under symlinked locations (for example `/tmp`) keep the correct relative structure when
  sent to Windows.
- Drop targeting includes the selected display's origin.
- Muting from the session menu now flushes already-queued audio, matching the toolbar button.

## Verification
- New `RDPClipboardFileDownloaderTests` / `RDPClipboardFilePathTests` cover timeout recovery,
  cancellation, path traversal, multi-chunk streaming, stale-folder cleanup, display-size rounding,
  pasteboard path comparison and symlinked folder enumeration.
- Full suite run twice: **836 tests, 30 skipped (live-host only), 0 failures** each run.
