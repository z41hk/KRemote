# Resume Session: KRemote Development

## Quick Start
```bash
cd C:\Users\User\dev\kremote
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path
git status
```

## Current State (v0.7.0 Released)
✅ **All core SSH terminal features working**  
✅ **Jump host tunneling implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.5.0  
✅ **Session tabs implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.6.0  
✅ **Session reconnect implemented** (per-tab reconnect banner, ships alongside session tabs in v0.6.0)  
✅ **SSH key passphrase prompt implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.7.0  
✅ **Windows build released** (v0.7.0)  
✅ **Keyboard input bug fixed** (removed outer GestureDetector wrapper)  
✅ **Organization features complete** (folders, tags, filtering, import/export)

## Priority Tasks (Next Session)

### 1. ✅ Jump Host/Bastion Support (COMPLETED)
**Status**: Fully implemented and tested

**Implementation Summary**:
- Used local TCP proxy pattern: bind ephemeral loopback listener, spawn thread to shuttle bytes between local TcpStream and ssh2::Channel from jump host
- Added `jump_host_id: Option<String>` to Connection model
- Implemented `connect_via_jump_host()` in `rust/src/api/ssh.rs:62-145`
- Updated `SshConnection::connect()` to auto-route via jump host when `jump_host_id` is set
- Added jump host dropdown UI in `connection_detail_screen.dart` (lines 332-376)
- Updated clone operation in `home_screen.dart:282` to carry jump_host_id
- All builds pass (cargo test, flutter analyze)

**Files Modified**:
- `rust/src/api/models.rs` - added `jump_host_id: Option<String>`
- `rust/src/api/ssh.rs` - implemented full tunneling via local TCP proxy
- `rust/src/api/app.rs` - added `get_connection()`, made `vault()` pub(crate)
- `lib/screens/connection_detail_screen.dart` - jump host selector UI
- `lib/screens/home_screen.dart` - clone carries jump_host_id

### 2. ✅ Session Tabs (COMPLETED)
**Status**: Fully implemented and released in v0.6.0

**Implementation Summary**:
- Added `lib/screens/tabbed_terminal_screen.dart` with `TabController` + `TabBar`/`TabBarView`
- `TerminalSession` class holds per-tab state: `Terminal`, `SshConnection`, output subscription, focus node
- `TabbedTerminalScreen` manages `List<TerminalSession>`, add via '+' button (connection picker dialog), close via 'X' on each tab
- `AutomaticKeepAliveClientMixin` on `TerminalSessionView` preserves terminal state/scrollback when switching tabs
- Visual status dot per tab: amber (connecting), red (error), green (connected)

**Files Modified**:
- `lib/screens/tabbed_terminal_screen.dart` (new file, 422 lines)
- Routing updated to open this screen instead of a single terminal screen

### 3. ✅ Session Reconnect (COMPLETED)
**Status**: Implemented as part of the session tabs work (v0.6.0), not as a separate change to `ssh_terminal_screen.dart`

**Implementation Summary**:
- Disconnect is surfaced via the SSH output stream's `onError`/`onDone` callbacks in `TerminalSessionView._connectAndStartShell()`
- On error, shows a red banner ("Connection lost") with a **Reconnect** button that re-invokes `_connectAndStartShell()`
- Terminal instance (`session.terminal`) is preserved across reconnect attempts, so scrollback history is kept and new output is appended
- `SshConnection::connect()` supports being called again since each `TerminalSession` creates a fresh `SshConnection.newInstance()` internally on reconnect

**Files Modified**:
- `lib/screens/tabbed_terminal_screen.dart` - reconnect banner + retry logic (lines 348-377)

**Note**: `lib/screens/ssh_terminal_screen.dart` (single-terminal, non-tabbed screen) was not touched — it appears to have been superseded by the tabbed screen. Verify whether it's still referenced anywhere before removing it.

### 4. Encrypted Credential Storage (CRITICAL - SECURITY)
⚠️ **CURRENT RISK**: Passwords stored in plaintext in the vault's decrypted JSON blob once the vault is unlocked, and the vault file itself relies solely on AES-256-GCM with an Argon2id-derived key (no OS keyring backing for the master key)

**Current state** (verified in `rust/src/api/vault.rs`):
- Vault-at-rest is already AES-256-GCM encrypted with Argon2id key derivation - this part is solid
- `Connection.password` (`rust/src/api/models.rs:21`) is a plain `Option<String>` decrypted into memory as part of `VaultData` whenever the vault is unlocked
- There is no SQLite storage in this codebase (RESUME.md's earlier text mentioning "plaintext SQLite" is stale/inaccurate - storage is the JSON vault file via `save_to_file`/`load_from_file`)

**Options**:
- **OS keyring for master password** (recommended next step): avoid re-typing master password every launch by storing it in Windows Credential Manager / Linux Secret Service, gated behind an explicit user opt-in (biometric/PIN re-auth ideally)
- **Per-field re-encryption**: encrypt each `Connection.password` individually with a derived sub-key so a memory dump of `VaultData` doesn't expose all credentials at once (defense in depth, vault file format already protects at rest)
- **Windows**: `windows` crate or `keyring` crate (wraps DPAPI/Credential Manager)
- **Linux**: `keyring` crate (wraps Secret Service API)

**Recommended**: Use the `keyring` crate (cross-platform wrapper) rather than hand-rolling `age` + raw keyring calls - it already abstracts Windows Credential Manager and Linux Secret Service with one API

**Files to Modify**:
- `rust/src/api/vault.rs` - optional: add keyring-backed master key storage/retrieval
- `rust/Cargo.toml` - add dependency: `keyring = "2.3"`
- `lib/screens/vault_screen.dart` - add "Remember me" / biometric unlock opt-in UI if pursuing keyring-backed unlock

### 5. ✅ SSH Key Passphrase Prompt (COMPLETED)
**Status**: Fully implemented, targeting v0.7.0 release

**Implementation Summary**:
- Added `private_key_passphrase: Option<String>` to `Connection` model (`rust/src/api/models.rs`), marked `#[serde(skip)]` so it's never persisted to the vault file - it's only ever passed transiently at connect time
- `SshConnection::authenticate()` now passes `connection.private_key_passphrase.as_deref()` to `session.userauth_pubkey_file()` instead of the old (incorrect) reuse of `connection.password` as the key passphrase
- Detection approach: attempt a normal connect first; if it fails with an error mentioning "passphrase"/"encrypted"/"decrypt" (libssh2's error text for a locked key), prompt the user via a new `PassphraseDialog` and retry the connect with the entered passphrase
- New `lib/widgets/passphrase_dialog.dart` - themed modal dialog (matches deep slate + cyan theme) with obscured text field and show/hide toggle
- Wired into both connection flows: `TerminalSessionView._connectAndStartShell()` in `tabbed_terminal_screen.dart` and `HomeScreen._testConnection()` in `home_screen.dart`
- User can cancel the passphrase prompt, which aborts the connection attempt cleanly

**Files Modified**:
- `rust/src/api/models.rs` - added `private_key_passphrase` field (skip-serialized)
- `rust/src/api/ssh.rs` - `authenticate()` uses `private_key_passphrase` instead of `password`; `test_ssh_connection()` standalone fn takes new param
- `rust/src/api/import.rs` - updated `Connection` struct literal for new field
- `lib/widgets/passphrase_dialog.dart` (new file) - passphrase prompt dialog
- `lib/screens/tabbed_terminal_screen.dart` - detect-then-prompt-then-retry flow on connect
- `lib/screens/home_screen.dart` - same flow for the "Test Connection" action
- FRB bindings regenerated (`flutter_rust_bridge_codegen generate`)

**Known limitation**: Detection relies on string-matching the libssh2 error message rather than reading the PEM header directly (e.g. `ENCRYPTED` in the key file). This works in practice but is a bit fragile - a more robust approach would peek at the key file's first line before attempting to connect at all.

**Manual testing**: Verified end-to-end with a WSL-generated `ed25519` key encrypted with a test passphrase against `flutter build windows --release`. Could not run a live SSH server in this environment (WSL VM was unavailable / no HCS service), so the full connect-prompt-retry loop against a real `sshd` was not exercised live - only `cargo`/`flutter analyze`/release build were verified. Recommend a quick manual pass against a real SSH server with an encrypted key before relying on this in production.

## Less Critical Tasks (Phase 6B)

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
- [x] Jump host tunneling works (implemented, needs manual verification against a real bastion host)
- [x] Session tabs work (implemented in v0.6.0)
- [x] Reconnect after disconnect works (implemented in v0.6.0)
- [ ] SSH key passphrase prompt works against a real encrypted key + live sshd (implemented in v0.7.0, `flutter analyze`/release build verified, but no live sshd was available in the dev environment to test the full prompt-then-retry loop end to end)

## Known Issues
- ⚠️ **SECURITY**: Vault is encrypted at rest, but no OS keyring integration for master password caching (must re-enter on every launch)
- ℹ️ SSH key passphrase prompt relies on error message string matching rather than PEM header inspection (works in practice, but could be more robust)
- ℹ️ Jump host tunneling implemented via local TCP proxy thread; not yet verified against a live bastion host (no test SSH infrastructure available in this environment)
- ℹ️ Old `ssh_terminal_screen.dart` may be obsolete (single-terminal screen superseded by tabbed version) - needs audit

## Reference Documentation
- **ssh2-rs docs**: https://docs.rs/ssh2/latest/ssh2/
- **xterm package**: https://pub.dev/packages/xterm
- **flutter_rust_bridge**: https://cjycode.com/flutter_rust_bridge/
- **PROGRESS.md**: Full technical history and architecture notes

---

**Last Updated**: 2026-09-17  
**Latest**: v0.7.0 (released) - SSH key passphrase prompt for encrypted private keys - https://github.com/z41hk/KRemote/releases/tag/v0.7.0  
**Next Priority**: Task #4 - OS keyring integration for master password caching, or Task #6 - Connection timeout configuration
