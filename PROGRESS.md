# KRemote Development Progress

## Project Overview
Cross-platform SSH connection manager built with Flutter (frontend) + Rust (SSH/protocol backend) via flutter_rust_bridge. Goal: replicate mRemoteNG functionality but cross-platform (Windows/Linux/iOS/Android).

---

## Architecture

### Tech Stack
- **Frontend**: Flutter (Dart) - cross-platform UI
- **Backend**: Rust via `flutter_rust_bridge` - SSH protocol handling using `ssh2` crate
- **Terminal**: `xterm` package (Dart) for VT100/xterm emulation
- **Bridge**: `flutter_rust_bridge` auto-generates FFI bindings between Dart ↔ Rust

### Key Files
- `lib/main.dart` - App entry point
- `lib/screens/connection_list_screen.dart` - Main connection manager UI
- `lib/screens/ssh_terminal_screen.dart` - Interactive SSH terminal widget
- `rust/src/api/ssh.rs` - Rust SSH implementation (ssh2 library wrapper)
- `rust/src/api/models.rs` - Shared data models (Connection struct, Protocol enum)
- `rust/src/api/storage.rs` - SQLite persistence for connections

### Data Flow
1. User creates/edits connections in Flutter UI
2. Connections stored in SQLite via Rust (`storage.rs`)
3. On connect: Flutter calls `SshConnection::new()` → `connect()` → `open_shell()`
4. Rust spawns background thread streaming SSH output to Flutter via `StreamSink<Vec<u8>>`
5. Flutter renders output in `xterm::Terminal` widget
6. User keystrokes: `Terminal.onOutput` → Rust `send_input()` → SSH channel write

---

## What's Implemented (Working)

### Phase 1-5 Complete
1. ✅ Basic Flutter + Rust FFI bridge setup
2. ✅ Connection CRUD (create/read/update/delete) with SQLite
3. ✅ SSH connection (password + public key auth)
4. ✅ Interactive SSH shell with PTY (xterm terminal emulation)
5. ✅ Terminal output streaming (Rust background thread → Flutter)
6. ✅ Terminal resize handling (`Terminal.onResize` → `SshConnection::resize_pty`)
7. ✅ Connection list UI with folders/tags/search
8. ✅ Dark mode design (slate/cyan theme, production-grade UI)
9. ✅ **Keyboard input fixed** (commit 4b784b2 - prior session)
10. ✅ Folder assignment in connection editor
11. ✅ Tag assignment in connection editor (add/remove tags with chips)
12. ✅ Advanced filtering (search, protocol, folder filters)
13. ✅ Folder expand/collapse in home screen
14. ✅ Connection import/export functionality

### Key Working Features
- Add/edit/delete SSH connections
- Assign connections to folders
- Add/remove tags with visual chip UI
- Filter by folder, protocol, and search query
- Expand/collapse folder groups
- Import/export connections (CSV, JSON formats)
- Store credentials in SQLite
- Launch SSH sessions in embedded xterm terminal
- Full keyboard input working (all characters, special keys, control sequences)
- Real-time terminal output streaming
- Window resize propagates to remote PTY

---

## Bug Status: KEYBOARD INPUT FIXED ✅

### Issue: Keyboard Input Only Partially Working
**Status**: ✅ **FIXED** - All keyboard input now works correctly.

**Root Cause**:
The outer `GestureDetector` wrapper in `ssh_terminal_screen.dart` was intercepting tap gestures before they reached xterm 4.0.0's internal `TerminalGestureHandler`. The `TerminalView` widget has built-in tap-to-focus logic that always calls `onTapDown` to bring the terminal into focus, but the outer wrapper prevented this from executing.

**What Actually Fixed It**:
Removed the redundant `GestureDetector` wrapper entirely. The `TerminalView` widget already handles:
- Tap-to-focus through its internal `TerminalGestureHandler` (gesture_handler.dart:128-137)
- Text input connection through `CustomTextEdit` widget when `hardwareKeyboardOnly: false`
- Autofocus on mount when `autofocus: true` is passed

**How It Works Now**:
1. `TerminalView` with `autofocus: true` wraps itself in `CustomTextEdit`
2. `CustomTextEdit` creates a `Focus` widget with `autofocus: true` that requests focus on mount
3. When focused, `CustomTextEdit` opens a text input connection for all keyboard input
4. Taps are handled by `TerminalGestureHandler` which maintains focus via `onTapDown`

**Files Modified**:
- `lib/screens/ssh_terminal_screen.dart` - removed outer `GestureDetector` wrapper (was at line 135)
- `rust/src/api/ssh.rs` - session-level non-blocking mode (line 224) + retry logic for `WouldBlock` (verified correct)

---

## Previous SSH Deadlock Bug (FIXED)

### The Problem
SSH session was in **blocking mode** by default. Background reader thread would call `channel.read()`, which blocks *while holding the shared session lock* (`Arc<Mutex<SessionInner>>` inside `ssh2::Channel`). When user typed, `send_input()` tried to acquire the same lock to write, but couldn't because reader was blocked waiting for data that would never come (the keystroke that triggers output couldn't get through). Classic deadlock.

### The Fix (Committed in rust/src/api/ssh.rs)
1. Called `session.set_blocking(false)` after opening shell (line 224)
2. Reader thread treats `WouldBlock` as "sleep 10ms, retry" instead of blocking (lines 248-251)
3. `send_input` retries `WouldBlock` writes with 2-second timeout (lines 277-288)
4. `resize_pty` retries `WouldBlock` errors with 1-second timeout (lines 305-318)

This fixed the deadlock but didn't fix keyboard input because that's a separate Flutter IME issue.

---

## Technical Decisions & Lessons Learned

### Why Non-Blocking SSH Mode is Critical
- `ssh2::Channel` clones share one session-level lock
- Blocking reads in background thread = lock held indefinitely
- Any write from main thread deadlocks
- Solution: non-blocking mode + explicit retry/sleep loops

### Why FocusNode Alone Isn't Enough (Desktop)
- Mobile: touch events automatically open text input connection
- Desktop: need explicit `Focus` widget with `autofocus: true` to open IME
- Without IME connection: hardware keys work (RawKeyboard events), software text input doesn't

### Flutter + Rust FFI Gotchas
- `flutter_rust_bridge` can't auto-generate `Clone` traits; had to clone `Channel` manually
- `StreamSink<Vec<u8>>` is the only way to stream data continuously from Rust → Flutter
- Background threads must be `'static` lifetime (no borrowed refs)

---

## Build & Test Commands

### Build Windows Release
```bash
cd C:\Users\User\dev\kremote
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path
flutter build windows --release
```

### Run Executable
```
C:\Users\User\dev\kremote\build\windows\x64\runner\Release\kremote.exe
```

### Test SSH Connection
1. Click "Add Connection" in UI
2. Fill in SSH details (host/port/username/password or key path)
3. Save, then click connection card
4. Terminal screen opens, shows connection progress
5. ✅ Full keyboard input works (typing, Enter, Ctrl+C, etc.)

---

## Next Steps (Priority Order)

### Immediate (Phase 6A)
1. Add jump host/bastion support (SSH tunnel chaining) - skeleton code exists in `connect_via_jump_host` but not fully implemented
2. Add session tabs (multiple SSH sessions in one window)
3. Implement session reconnect on disconnect

### Short Term (Phase 6B)
4. Add SSH key passphrase prompt for encrypted keys
5. Connection timeout configuration UI
6. Implement "are you sure?" confirmation on connection delete
7. Update window title with active connection name

### Medium Term (Phase 6C)
8. VNC protocol support (use `libvncclient` or similar Rust crate)
9. RDP protocol support (use `FreeRDP` via FFI or find Rust RDP library)
10. Encrypted credential storage (currently plaintext in SQLite - security risk!)

### Long Term (Phase 7+)
11. Mobile apps (Android/iOS) - requires touch input → keyboard/mouse translation
12. HTTP/HTTPS viewer (embedded browser)
13. VPN integration (WireGuard config management)
14. Remote desktop "AnyDesk-style" unattended access (huge project, consider integrating RustDesk instead of building from scratch)

---

## Known Issues & Limitations

### Critical
- ✅ **Keyboard input fixed** - all keys now work correctly
- ⚠️ Credentials stored in plaintext SQLite (no encryption) - security risk for production use

### Medium Priority
- ⚠️ Jump host support incomplete (connects directly, ignoring tunnel)
- ⚠️ No session reconnect on disconnect (must close window and reopen)
- ⚠️ No SSH key passphrase prompt (assumes unencrypted keys or password provided)
- ⚠️ No connection timeout configuration (hardcoded TCP connect timeout)

### Low Priority
- Minor: Window title doesn't update with connection name
- Minor: No "are you sure?" prompt on connection delete

---

## Dependencies & Versions

### Rust Crates
- `ssh2 = "0.9"` - SSH protocol implementation
- `rusqlite = { version = "0.32", features = ["bundled"] }` - SQLite storage
- `flutter_rust_bridge = "2.0"` - Dart ↔ Rust FFI bridge

### Flutter Packages
- `xterm = "3.5.0"` - Terminal emulator widget
- `flutter_rust_bridge = "2.0.0"` - FFI bridge (Dart side)
- `sqflite` - (not used; using Rust SQLite instead)

### System Requirements
- Flutter SDK 3.x
- Rust toolchain (stable)
- Visual Studio 2019+ (Windows) or clang (Linux/macOS)

---

## Testing Notes

### Last Manual Test (v0.4.0)
- ✅ App launches, connection list loads
- ✅ Add connection form works
- ✅ Folder assignment works in connection editor
- ✅ Folder filtering and expansion works in home screen
- ✅ SQLite persistence works (connections survive app restart)
- ✅ SSH connection establishes successfully
- ✅ Terminal output streams correctly
- ✅ Window resize triggers PTY resize
- ✅ **Keyboard input works** - all characters, Enter, Ctrl sequences

### Test SSH Server Used
- Host: (user's server, not documented in this session)
- Port: 22
- Auth: password

---

## Future Architecture Considerations

### When Adding Mobile Support
- Touch gestures → mouse events mapping is hard (see RustDesk/Guacamole implementations)
- Virtual keyboard will cover terminal; need collapsible toolbar
- PTY resize on keyboard show/hide is fiddly

### When Adding VNC/RDP
- Consider web-based approach (Guacamole-style gateway) vs native client libs
- Video decoding performance critical (hardware acceleration needed)
- Mobile: touch → mouse translation even harder with graphical protocols

### When Adding Team/Enterprise Features
- Need user authentication system
- Shared credential vaults with RBAC
- Audit logs for compliance (session recordings)
- End-to-end encrypted sync (zero-knowledge architecture)

---

## Licensing Notes
- `ssh2` crate: Apache 2.0 / MIT
- `xterm` package: MIT
- `flutter_rust_bridge`: Apache 2.0 / MIT
- **Project license**: Not yet decided (currently unreleased)

---

## Git Status (Ready to Commit)
```
M lib/screens/ssh_terminal_screen.dart  (removed outer GestureDetector wrapper)
M lib/screens/home_screen.dart          (folder filtering UI improvements)
M lib/screens/connection_detail_screen.dart (folder assignment in editor)
M rust/src/api/ssh.rs                   (non-blocking mode + retry logic - verified working)
```

**Status**: ✅ Keyboard input fix verified working. Ready to commit as v0.4.0.

---

## Latest Release (v0.4.0)

**Released**: 2026-09-17  
**Release URL**: https://github.com/z41hk/KRemote/releases/tag/v0.4.0

### Downloads
- **Windows**: KRemote-v0.4.0-windows-x64.zip  
- **Linux**: KRemote-v0.4.0-linux-x64.tar.gz

### Changelog
- ✅ **SSH terminal keyboard input fixed**: Removed outer GestureDetector wrapper blocking xterm's internal focus handling
- ✅ Advanced organization features: tag assignment UI, folder assignment, filtering, folder tree view
- ✅ Connection management: cloning, import/export (mRemoteNG XML, JSON), enhanced cards with tags
- ✅ SSH session deadlock fixed: Non-blocking mode with retry logic for WouldBlock errors

---

## Contact / Handoff Notes for Next Session

### What Was Completed This Session (v0.4.0 Release)
1. ✅ **Keyboard input bug fix verified and released**
2. ✅ **Released v0.4.0 with both Windows and Linux builds**
   - Windows: KRemote-v0.4.0-windows-x64.zip (12.2 MB)
   - Linux: KRemote-v0.4.0-linux-x64.tar.gz (built via GitHub Actions)
   - Release notes updated with full changelog
3. ✅ **PROGRESS.md updated with handoff instructions**

### Priority Roadmap for Next Sessions

#### Phase 6A: Enhanced Connectivity (High Priority)
1. **Jump host/bastion support** - Skeleton exists at `ssh.rs:64-131` but incomplete
   - Current: `connect_via_jump_host()` authenticates jump host but doesn't tunnel
   - Need: Use `session.channel_direct_tcpip()` to forward traffic through jump host
   - Challenge: `ssh2::Channel` doesn't implement `AsRawSocket`, need custom Read+Write wrapper
   - Alternative: ProxyCommand-style approach or async bridge layer

2. **Session tabs** - Multiple SSH connections in one window
   - Add tab bar widget to main window
   - Store multiple `SshConnection` instances
   - Switch between active terminals
   - Close individual tabs without closing app

3. **Session reconnect on disconnect**
   - Detect connection loss (reader thread exits)
   - Show "Disconnected" banner in terminal
   - Add "Reconnect" button
   - Preserve terminal history after reconnect

#### Phase 6B: Security & UX (Medium Priority)
4. **SSH key passphrase prompt**
   - Detect encrypted private keys (PEM headers)
   - Show password dialog for passphrase
   - Pass passphrase to `session.userauth_pubkey_file()`

5. **Connection timeout configuration**
   - Add timeout field to Connection model
   - Configure `TcpStream::connect_timeout()`
   - Show countdown in connection dialog

6. **Delete confirmation dialog**
   - Add "Are you sure?" before deleting connections/folders
   - Prevent accidental data loss

7. **Window title updates**
   - Set window title to active connection name
   - Show connection status (connecting/connected/disconnected)

#### Phase 6C: Credential Security (Critical for Production)
8. **Encrypted credential storage**
   - ⚠️ **SECURITY RISK**: Credentials currently stored in plaintext SQLite
   - Options:
     - Windows: DPAPI (Windows Data Protection API)
     - Linux: Secret Service API (libsecret)
     - Cross-platform: age encryption with OS keyring for master key
   - Migrate existing plaintext credentials to encrypted vault

#### Phase 7: Additional Protocols (Long Term)
9. **VNC protocol support**
   - Evaluate Rust VNC client crates (`vnc-rs`, `rfb`)
   - Implement VNC viewer widget (bitmap rendering)
   - Add VNC connection type to UI

10. **RDP protocol support**
    - Evaluate RDP libraries (`rdp-rs` or FFI to FreeRDP)
    - Windows RemoteApp support
    - RDP connection type in UI

11. **HTTP/HTTPS viewer**
    - Embedded webview widget
    - Browser-like navigation for web-based management consoles

#### Phase 8: Mobile & Enterprise (Future)
12. **Mobile apps** (Android/iOS)
    - Touch gesture → keyboard/mouse translation
    - Virtual keyboard handling
    - Mobile-optimized connection list

13. **Team features**
    - User authentication system
    - Shared credential vaults with RBAC
    - Audit logs & session recordings
    - E2E encrypted sync (zero-knowledge)

### Commands to Resume Work
```bash
# Navigate to project
cd C:\Users\User\dev\kremote

# Set Flutter path
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path

# Check status
git status
git log --oneline -5

# Analyze code
flutter analyze

# Build and test
flutter build windows --release
./build/windows/x64/runner/Release/kremote.exe

# Run GitHub Actions build
gh workflow run "Build and Release"
gh run list --limit 5
```

### Key Files Reference
- **SSH implementation**: `rust/src/api/ssh.rs` (10 public functions, jump host skeleton at line 64)
- **Terminal screen**: `lib/screens/ssh_terminal_screen.dart` (xterm integration, autofocus fixed)
- **Connection UI**: `lib/screens/connection_detail_screen.dart` (folder/tag assignment)
- **Home screen**: `lib/screens/home_screen.dart` (filtering, folder tree)
- **Data models**: `rust/src/api/models.rs` (Connection struct, Protocol enum)
- **Storage**: `rust/src/api/storage.rs` (SQLite persistence - needs encryption!)

All core SSH terminal functionality is now working. Next focus: jump host tunneling, session tabs, and encrypted credential storage.
