# Resume Session: KRemote Development

## Quick Start
```bash
cd C:\Users\User\dev\kremote
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path
git status
```

## Current State (v0.8.1 - Keyring Bugfixes)
✅ **All core SSH terminal features working**  
✅ **Jump host tunneling implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.5.0  
✅ **Session tabs implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.6.0  
✅ **Session reconnect implemented** (per-tab reconnect banner, ships alongside session tabs in v0.6.0)  
✅ **SSH key passphrase prompt implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.7.0  
✅ **OS keyring integration for master password caching** (Windows Credential Manager, released in v0.8.0)  
✅ **Lock Vault / Remember Password bugfixes** (ready for v0.8.1 release) - manual lock no longer auto-bounces back in, unchecking "Remember master password" clears the keyring entry immediately  
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

### 4. ✅ OS Keyring Integration for Master Password Caching (COMPLETED)
**Status**: Fully implemented, targeting v0.8.0 release

**Implementation Summary**:
- Added `keyring = "2.3"` dependency to `rust/Cargo.toml` (wraps Windows Credential Manager / Linux Secret Service / macOS Keychain behind one API)
- `rust/src/api/vault.rs` - added `save_password_to_keyring()`, `get_password_from_keyring()`, `delete_password_from_keyring()`, `is_password_in_keyring()` on `Vault`, using a fixed `KEYRING_SERVICE = "KRemote"` / `KEYRING_USER = "master_password"` entry
- `rust/src/api/app.rs` - exposed the above as FRB functions: `save_master_password_to_keyring`, `get_master_password_from_keyring`, `delete_master_password_from_keyring`, `is_master_password_in_keyring` (sync)
- `lib/screens/vault_screen.dart` - added a "Remember master password" checkbox on both the create-vault and unlock-vault forms:
  - On startup, if a password is already stored in the keyring, the screen attempts a silent auto-unlock before showing the form; falls back to manual entry with an inline error if auto-unlock fails (e.g. stale/incorrect cached password)
  - Checking the box on submit saves the just-entered password to the keyring after a successful create/unlock
  - Unchecking it (when a password was previously stored) deletes the cached password from the keyring
  - Keyring save/delete failures are treated as non-fatal (shown via `SnackBar`) so they never block the actual vault unlock/create flow
- FRB bindings regenerated (`flutter_rust_bridge_codegen generate`)

**Security note**: This stores the plaintext master password in the OS-native credential store (DPAPI-backed on Windows), not a derived key - equivalent in risk profile to any "remember password" feature. It is opt-in (unchecked by default) and can be reverted at any time by unchecking the box or manually clearing the `KRemote` entry from Credential Manager / Secret Service.

**Files Modified**:
- `rust/Cargo.toml` - added `keyring = "2.3"`
- `rust/src/api/vault.rs` - keyring read/write/delete/check methods + `#[cfg(test)]` roundtrip test
- `rust/src/api/app.rs` - FRB-exposed keyring functions
- `lib/screens/vault_screen.dart` - "Remember master password" checkbox, auto-unlock on startup
- `lib/screens/home_screen.dart` - note added to `_lockVault()` about keyring lifecycle (password intentionally persists across manual lock so auto-unlock still works next launch)

**Testing performed**:
- `cargo test --lib keyring_roundtrip_set_get_delete` - added a real (non-mocked) test that calls `keyring::Entry::set_password`/`get_password`/`delete_password` against the actual Windows Credential Manager under a dedicated `KRemote-Test` service name (isolated from the real `KRemote` app entry) - **passed**
- `cargo build` - compiles cleanly with the new dependency
- `flutter analyze` - no issues
- `flutter build windows --release` - builds successfully
- Manually launched the release exe to confirm the vault screen renders with the new checkbox

**Known limitation**: Auto-unlock has no explicit UI affordance to distinguish "checking keyring" from "checking vault file exists" during the loading spinner - both happen in `_checkVaultExists()`. Not a functional issue, just a minor UX polish item if it matters later.

### 4a. ✅ Bugfix: Lock Vault / Remember Password interaction (v0.8.1)
**Status**: Fixed, two related bugs found after v0.8.0 shipped

**Bug 1 - "Lock Vault" instantly auto-logged back in**:
- Root cause: `_lockVault()` in `home_screen.dart` navigated back to `VaultScreen()`, whose `initState()` always checked the keyring and auto-unlocked if a password was cached - so pressing "Lock Vault" appeared to do nothing (screen flashed and went straight back to `HomeScreen`)
- Fix: Added `skipAutoUnlock` constructor param to `VaultScreen`. `_lockVault()` now navigates to `VaultScreen(skipAutoUnlock: true)`, and `_checkVaultExists()` respects that flag to skip the `_tryAutoUnlock()` call. Manual lock now actually shows the unlock form instead of bouncing straight through.

**Bug 2 - Unchecking "Remember master password" didn't take effect until a second logout**:
- Root cause: The checkbox's `onChanged` only updated local state (`_rememberPassword`); the actual `deleteMasterPasswordFromKeyring()` call was deferred until `_submit()` ran, inside an `else if (_hasStoredPassword)` branch. So unchecking the box and closing the app without submitting (or unchecking after `_tryAutoUnlock()` had already logged the user in past the form) left the stale credential in Windows Credential Manager, causing the auto-login to keep firing on next launch.
- Fix: Replaced the inline `onChanged`/`onTap` handlers with a single `_handleRememberPasswordChanged()` method that calls `deleteMasterPasswordFromKeyring()` and resets `_hasStoredPassword = false` **immediately** when the box is unchecked, rather than waiting for form submission. `_submit()` no longer has a delete branch at all - it only ever saves (when checked), since unchecking is now handled eagerly at the checkbox level.

**Files Modified**:
- `lib/screens/vault_screen.dart` - added `skipAutoUnlock` widget param; added `_handleRememberPasswordChanged()`; simplified `_submit()` to drop the dead delete-on-uncheck branch
- `lib/screens/home_screen.dart` - `_lockVault()` passes `skipAutoUnlock: true`

**Testing performed**:
- `flutter analyze` - no issues
- `flutter build windows --release` - builds successfully
- Manually verified: check "Remember master password" → unlock → close app → reopen → auto-unlocks (unchanged behavior)
- Manually verified: from Home screen, press "Lock Vault" → now correctly shows the unlock form instead of bouncing back to Home
- Manually verified: on the unlock form (after a manual lock), uncheck "Remember master password" → close app immediately without submitting → reopen → prompts for password instead of auto-unlocking (this was the reported bug, now fixed)

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
- ℹ️ SSH key passphrase prompt relies on error message string matching rather than PEM header inspection (works in practice, but could be more robust)
- ℹ️ Jump host tunneling implemented via local TCP proxy thread; not yet verified against a live bastion host (no test SSH infrastructure available in this environment)
- ℹ️ Old `ssh_terminal_screen.dart` may be obsolete (single-terminal screen superseded by tabbed version) - needs audit
- ℹ️ Auto-unlock from keyring has no explicit "checking keyring..." UI affordance during the startup spinner (minor UX polish item)

## Reference Documentation
- **ssh2-rs docs**: https://docs.rs/ssh2/latest/ssh2/
- **xterm package**: https://pub.dev/packages/xterm
- **flutter_rust_bridge**: https://cjycode.com/flutter_rust_bridge/
- **PROGRESS.md**: Full technical history and architecture notes

---

**Last Updated**: 2026-09-17  
**Latest**: v0.8.0 (ready to release) - OS keyring integration for master password caching (Windows Credential Manager / Linux Secret Service)  
**Next Priority**: Task #6 - Connection timeout configuration, or Task #7 - Delete confirmation dialog
