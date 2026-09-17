# Resume Session: KRemote Development

## Quick Start
```bash
cd C:\Users\User\dev\kremote
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path
git status
```

## Current State (v0.4.0 Released)
✅ **All core SSH terminal features working**  
✅ **Windows + Linux builds released**: https://github.com/z41hk/KRemote/releases/tag/v0.4.0  
✅ **Keyboard input bug fixed** (removed outer GestureDetector wrapper)  
✅ **Organization features complete** (folders, tags, filtering, import/export)

## Priority Tasks (Next Session)

### 1. Jump Host/Bastion Support (HIGH PRIORITY)
**File**: `rust/src/api/ssh.rs` line 64-131  
**Status**: Skeleton exists but incomplete

**Current Problem**:
- `connect_via_jump_host()` authenticates to jump host but doesn't tunnel traffic
- Need to use `session.channel_direct_tcpip()` to forward connections
- `ssh2::Channel` doesn't implement `AsRawSocket`, blocking simple tunneling

**Implementation Options**:
```rust
// Option A: Custom Read+Write wrapper around Channel
struct ChannelStream(ssh2::Channel);
impl Read for ChannelStream { /* forward to channel.read() */ }
impl Write for ChannelStream { /* forward to channel.write() */ }

// Option B: ProxyCommand-style approach
// Spawn external SSH process with ProxyCommand
// Connect through that tunnel

// Option C: Async bridge layer
// Use tokio/async-std to multiplex channel I/O
```

**Recommended Approach**: Option A (custom wrapper)
1. Create `ChannelStream` wrapper implementing `Read + Write`
2. Use `jump_session.channel_direct_tcpip(target_host, target_port, None, None)`
3. Wrap channel in `ChannelStream`
4. Pass to `Session::new()` via custom handshake

**Files to Modify**:
- `rust/src/api/ssh.rs` - implement `ChannelStream` and complete `connect_via_jump_host()`
- `lib/screens/connection_detail_screen.dart` - add jump host selection dropdown
- `rust/src/api/models.rs` - add `jump_host_id: Option<i64>` to `Connection` struct
- `rust/src/api/storage.rs` - update SQL schema and queries

### 2. Session Tabs (MEDIUM PRIORITY)
**Goal**: Multiple SSH sessions in one window

**Implementation Steps**:
1. Add `TabBar` + `TabBarView` to main window
2. Store `List<SshConnection>` in state
3. Each tab holds one terminal widget
4. Add close button on tabs
5. Preserve terminal state when switching tabs

**Files to Create/Modify**:
- `lib/screens/tabbed_terminal_screen.dart` (new file)
- `lib/main.dart` - route to tabbed screen instead of single terminal

**UI Reference**: VS Code terminal tabs, Windows Terminal

### 3. Session Reconnect (MEDIUM PRIORITY)
**Goal**: Recover from connection loss without closing window

**Implementation Steps**:
1. Detect disconnect: reader thread exits → set flag in state
2. Show banner: "Connection lost. [Reconnect]"
3. Reconnect button: call `SshConnection::connect()` again
4. Preserve terminal history: keep `Terminal` instance, append new output

**Files to Modify**:
- `lib/screens/ssh_terminal_screen.dart` - add disconnect detection + reconnect button
- `rust/src/api/ssh.rs` - ensure `connect()` can be called multiple times

### 4. Encrypted Credential Storage (CRITICAL - SECURITY)
⚠️ **CURRENT RISK**: Passwords stored in plaintext SQLite!

**Options**:
- **Windows**: Use DPAPI via `winapi` crate
- **Linux**: Use Secret Service API via `secret-service` crate
- **Cross-platform**: `age` encryption + OS keyring for master key

**Recommended**: Cross-platform `age` approach
1. Generate master key on first run
2. Store master key in OS keyring (Windows Credential Manager / Linux Secret Service)
3. Encrypt connection passwords with master key before SQLite insert
4. Decrypt on load

**Files to Modify**:
- `rust/src/api/storage.rs` - add encryption/decryption layer
- `rust/Cargo.toml` - add dependencies: `age = "0.10"`, `keyring = "2.3"`

## Less Critical Tasks (Phase 6B)

### 5. SSH Key Passphrase Prompt
- Detect encrypted PEM keys (header check)
- Show Flutter password dialog
- Pass passphrase to `session.userauth_pubkey_file()`

### 6. Connection Timeout Configuration
- Add `timeout_seconds` field to `Connection` model
- Use `TcpStream::connect_timeout(Duration::from_secs(timeout))`

### 7. Delete Confirmation Dialog
- Show "Are you sure?" before deleting connections/folders

### 8. Window Title Updates
- Set window title to active connection name
- Update on connect/disconnect

## Architecture Overview

### Stack
- **Frontend**: Flutter (Dart) - UI
- **Backend**: Rust via `flutter_rust_bridge` - SSH protocol (`ssh2` crate)
- **Terminal**: `xterm` v4.0.0 package (Dart)

### Data Flow
```
User types → Terminal.onOutput → Rust send_input() → SSH channel write
SSH channel read → Rust background thread → StreamSink<Vec<u8>> → Terminal widget
```

### Key Files
| File | Purpose |
|------|---------|
| `rust/src/api/ssh.rs` | SSH connection, shell, I/O (10 public functions) |
| `rust/src/api/storage.rs` | SQLite persistence (⚠️ needs encryption) |
| `rust/src/api/models.rs` | Data models (Connection, Protocol) |
| `lib/screens/ssh_terminal_screen.dart` | xterm integration, autofocus |
| `lib/screens/home_screen.dart` | Connection list, folders, filtering |
| `lib/screens/connection_detail_screen.dart` | Add/edit connections |

## Build Commands

### Windows Release
```bash
flutter build windows --release
./build/windows/x64/runner/Release/kremote.exe
```

### Linux Release (GitHub Actions)
```bash
gh workflow run "Build and Release"
gh run watch
```

### Package Windows for Release
```bash
Compress-Archive -Path "build\windows\x64\runner\Release\*" -DestinationPath "KRemote-v0.4.1-windows-x64.zip"
gh release create v0.4.1 KRemote-v0.4.1-windows-x64.zip --notes "..."
```

## Git Workflow
```bash
git status
git add -A
git commit -m "feat: implement jump host tunneling"
git push origin main
git tag v0.4.1
git push origin v0.4.1
```

## Testing Checklist
- [ ] App launches, connection list loads
- [ ] Add/edit/delete connections
- [ ] Folder assignment and filtering
- [ ] SSH connection establishes
- [ ] All keyboard input works (letters, Enter, Ctrl+C, arrows)
- [ ] Terminal output streams correctly
- [ ] Window resize triggers PTY resize
- [ ] Jump host tunneling works (new feature)
- [ ] Session tabs work (new feature)
- [ ] Reconnect after disconnect works (new feature)

## Known Issues
- ⚠️ **CRITICAL**: Credentials in plaintext SQLite (security risk)
- ⚠️ Jump host support incomplete (connects directly, no tunnel)
- ⚠️ No session reconnect (must close window)
- ⚠️ No SSH key passphrase prompt

## Reference Documentation
- **ssh2-rs docs**: https://docs.rs/ssh2/latest/ssh2/
- **xterm package**: https://pub.dev/packages/xterm
- **flutter_rust_bridge**: https://cjycode.com/flutter_rust_bridge/
- **PROGRESS.md**: Full technical history and architecture notes

---

**Last Updated**: 2026-09-17 (v0.4.0 release)  
**Next Priority**: Jump host tunneling implementation
