# AetherScreens 1.2.0 Candidate Release Notes

Build: 2026101601. Release Candidate.

## Key Features & Enhancements

### 1. Seamless Bidirectional Clipboard Synchronization
- Automatically synchronizes clipboard text between local device (macOS/iOS) and remote computer (macOS Screen Sharing & Windows RDP) during active sessions.
- Windows RDP integration: automatic CRLF (`\r\n`) / LF (`\n`) line ending normalization ensuring clean line breaks in Windows Notepad, CMD, PowerShell, and Office.
- Windows RDP shortcut fidelity: hardware scancode translation for standard shortcut combinations (`Ctrl+C`, `Ctrl+V`, `Ctrl+A`, `Ctrl+Z`, `Ctrl+X`), overcoming Windows RDP Unicode event limitations under active modifier keys.
- Instant pre-paste synchronization: `Cmd+V` / `Ctrl+V` keypresses immediately trigger local-to-remote clipboard synchronization before the paste key event is dispatched to the host.
- Built-in loopback/echo suppression preventing recursive clipboard bounce-backs across both single-line and multi-line text.
- Dedicated in-session Clipboard menu featuring Auto Clipboard Sync toggle, "Send to Remote Clipboard", and "Type Clipboard as Keystrokes".
- Observe Only mode integration: clipboard transmission is strictly suppressed in view-only sessions while allowing server clipboard reception.
- Configurable via in-session menu toggle and Settings preferences.

### 2. In-Session Quick Actions & Hot Corners
- Direct Hot Corner triggers: Top Left, Top Right, Bottom Left, and Bottom Right for invoking Mission Control, Notification Center, Launchpad, and Desktop.
- Native System Shortcuts menu:
  - macOS: Mission Control (⌃↑), Show Desktop (⌘F3), App Switcher (⌘Tab), App Exposé (⌃↓), Spotlight (⌘Space), Force Quit (⌥⌘Esc), and Log Out Remote User.
  - Windows/Linux: Send Ctrl-Alt-Delete, Lock Screen.

### 3. iCloud Library Synchronization
- Automatic and on-demand synchronization of saved computers across Apple Silicon Mac, iPhone, and iPad using CloudKit private database.
- Zero-knowledge credential isolation: connection metadata is synced securely while passwords and private keys remain encrypted in the local Keychain.
- Real-time sync status reporting and conflict resolution.

### 4. Native File Transfer UI & Historical Presets
- Redesigned File Upload and Download sheets conforming to Apple Human Interface Guidelines.
- Interactive drag-and-drop target styling with visual feedback.
- Preset directory chips for standard macOS locations (`~/Desktop`, `~/Downloads`, `~/Documents`, `~`, `/Applications`).
- LRU recent transfer history tracking with quick-select menus.

### 5. Biometric Security & App Lock
- LocalAuthentication support for Face ID, Touch ID, Optic ID (visionOS), and device passcode.
- Configurable auto-lock intervals: Immediately, 1 minute, 5 minutes, 15 minutes, or Never.
- Ultra-thin frosted glass privacy overlay (`AppLockOverlayView`) protecting credential and session contents from app switcher previews.

### 6. Device Organization: Favorites & Tags
- Starred Favorites category with sidebar counts and quick filter.
- Multi-tag classification and pill badges on computer cards.
- Quick toggle context menus and organization editing in Add/Edit Computer sheets.

### 7. Complete Localization & Concurrency Hardening
- 100% synchronization of English and Simplified Chinese catalogs (over 640 entries verified with zero omissions).
- Modern Swift 6 concurrency isolation hardening with zero actor-boundary warnings.
- Updated third-party dependency notice compilation (`ThirdPartyNotices.txt`).

## Verification & Test Results
- Complete test suite: **814 tests passed, 30 skipped, 0 failures** in 237 seconds.
- Bidirectional clipboard test suite (10 tests) passed with 0 failures.
- Localization consistency tests passed with 0 failures across all catalogs.
- Dependency notice verification (`python3 scripts/generate_dependency_notices.py --check`) verified cleanly.
- Release compilation (`swift build -c release --arch arm64`) passed with code 0 in 106 seconds.
- iOS project generation (`xcodegen generate --spec ios/project.yml`) generated cleanly.

