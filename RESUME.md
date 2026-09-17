# Resume Session: KRemote Development

## Quick Start
```bash
cd C:\Users\User\dev\kremote
$env:Path = "C:\Users\User\dev\flutter\bin;" + $env:Path
git status
```

## Current State (v0.11.0 - RDP Protocol Foundation)
✅ **All core SSH terminal features working**  
✅ **Jump host tunneling implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.5.0  
✅ **Session tabs implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.6.0  
✅ **Session reconnect implemented** (per-tab reconnect banner, ships alongside session tabs in v0.6.0)  
✅ **SSH key passphrase prompt implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.7.0  
✅ **OS keyring integration for master password caching** (Windows Credential Manager, released in v0.8.0)  
✅ **Lock Vault / Remember Password bugfixes implemented and released**: https://github.com/z41hk/KRemote/releases/tag/v0.8.1  
✅ **Connection timeout configuration implemented** (configurable 1-300s timeout per connection, defaults to 30s)  
✅ **RDP protocol foundation implemented** (IronRDP integration, connection establishment, domain auth support)  
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

### 6. ✅ Connection Timeout Configuration (COMPLETED)
**Status**: Fully implemented, targeting v0.9.0 release

**Implementation Summary**:
- Added `timeout_seconds: u64` field to `Connection` model (`rust/src/api/models.rs`), default 30s
- `SshConnection::connect()` now uses `TcpStream::connect_timeout(Duration::from_secs(timeout_seconds))` instead of the blocking `TcpStream::connect()` when `timeout_seconds > 0`
- Added UI field to `connection_detail_screen.dart` (lines 213-245) - numeric input with validation (1-300s), shows default 30s placeholder
- Timeout is carried through clone operation in `home_screen.dart` and passed to reconnect logic in `tabbed_terminal_screen.dart`
- mRemoteNG import defaulted to 30s timeout
- FRB bindings regenerated

**Files Modified**:
- `rust/src/api/models.rs` - added `timeout_seconds: u64` field
- `rust/src/api/ssh.rs` - implemented `connect_timeout()` when timeout > 0
- `rust/src/api/app.rs` - FRB signature updated for `add_connection()`
- `rust/src/api/import.rs` - default timeout for imported connections
- `lib/screens/connection_detail_screen.dart` - timeout input UI
- `lib/screens/home_screen.dart` - clone carries timeout
- `lib/screens/tabbed_terminal_screen.dart` - pass timeout to connect
- FRB bindings regenerated

### 7. ✅ Delete Confirmation Dialog (COMPLETED)
**Status**: Already implemented, was present in codebase but not marked complete

**Implementation Summary**:
- `_deleteConnection()` in `home_screen.dart` (lines 177-207) shows an `AlertDialog` with "Cancel"/"Delete" before proceeding
- `_deleteFolder()` in `home_screen.dart` (lines 1002-1039) shows confirmation with additional context: "Connections in this folder will be moved to root"
- Both use `showDialog<bool>()` pattern and check for user confirmation before executing the actual delete operation
- Prevents accidental deletions of connections and folders

**Files Modified**:
- `lib/screens/home_screen.dart` - confirmation dialogs already present

### 8. ✅ Window Title Updates (COMPLETED)
**Status**: Fully implemented

**Implementation Summary**:
- Home screen sets window title to "KRemote" on load (`home_screen.dart:34`)
- Tabbed terminal screen updates title to "KRemote - {connection_name}" when active tab changes
- `_updateWindowTitle()` method added to `TabbedTerminalScreen`, called from `initState()` and after tab changes
- Tab controller listener attached in `_addSession()` and `_closeSession()` to track active tab switches
- Uses `window_manager` package (already a dependency) for cross-platform window title control

**Files Modified**:
- `lib/screens/home_screen.dart` - added `windowManager.setTitle('KRemote')` in `initState()`
- `lib/screens/tabbed_terminal_screen.dart` - added `_updateWindowTitle()` method, attached listener to `_tabController`

### 9. 🚧 RDP Protocol Integration (FOUNDATION COMPLETE, IN PROGRESS)
**Status**: Core connection handling implemented and working; framebuffer rendering and input handling not yet built

**Research phase**: Evaluated `IronRDP` (Devolutions), `rdp-rs` (citronneur), and `freerdp-sys` FFI bindings. Chose **IronRDP** — actively maintained by Devolutions, pure Rust (no native FreeRDP toolchain dependency), built-in NLA/CredSSP support via the `sspi` crate, dual MIT/Apache-2.0 license compatible with KRemote's MIT license. `rdp-rs` is unmaintained since 2020; `freerdp-sys` is a brand-new single-maintainer wrapper with no track record.

**Implementation Summary**:
- Added `ironrdp` (v0.17, with `connector`/`session`/`graphics`/`input`/`pdu` features), `ironrdp-blocking` (v0.10), `rustls` (v0.23), `tokio-rustls` (v0.26), `x509-cert` (v0.2), and `sspi` (v0.21, with `network_client` feature) to `rust/Cargo.toml`
- New `rust/src/api/rdp.rs`:
  - `RdpConnection` (opaque FRB struct) with `connect()`, `disconnect()`, `is_connected()`, `get_framebuffer()`, `get_size()`
  - `connect_rdp()` — resolves address, TCP connect with timeout, `ironrdp_blocking::connect_begin()`, TLS upgrade via `rustls`, CredSSP/NLA finalization via `ironrdp_blocking::connect_finalize()` using `sspi`'s `ReqwestNetworkClient`
  - `build_rdp_config()` — constructs `ironrdp::connector::Config` (credentials, domain, keyboard type/layout, desktop size, platform detection via `#[cfg]`, compression, autologon)
  - `tls_upgrade()` — establishes TLS with a permissive certificate verifier (`danger::NoCertificateVerification`, private module, not FRB-exposed) since RDP servers commonly use self-signed certs; extracts the server's public key from the peer certificate for CredSSP
  - `test_rdp_connection()` — standalone FRB function for a one-shot connect test (used by future "Test Connection" UI action)
- `rust/src/api/models.rs` — added `domain: Option<String>` field to `Connection` (RDP-only, `#[serde(default)]` so old vault files still deserialize)
- `rust/src/api/app.rs` — `add_connection()` takes new `domain: Option<String>` param; `test_connection()` dispatches to `rdp::RdpConnection` for `Protocol::Rdp` (connects, reports negotiated resolution, disconnects)
- `lib/screens/connection_detail_screen.dart` — Domain field UI shown only when protocol = RDP; wired into both `addConnection()` and `updateConnection()` calls
- New `lib/screens/rdp_session_screen.dart` — session screen showing connecting/connected/error states, resolution, username/domain info; "Framebuffer rendering coming soon" placeholder in the connected state
- `lib/screens/home_screen.dart` — `_connectToSession()` now routes `Protocol.rdp` to `RdpSessionScreen` instead of showing a "coming soon" snackbar
- FRB bindings regenerated (`flutter_rust_bridge_codegen generate`)

**What works right now**: Clicking Connect on an RDP connection opens `RdpSessionScreen`, which calls into the Rust `RdpConnection` and performs a real TCP → TLS → CredSSP/NLA → RDP connection sequence against a target server, reporting the negotiated desktop resolution on success or a readable error on failure.

**What's NOT yet implemented** (tracked for next session, see "RDP Phase 2" below):
- No PDU read loop after the initial connection — the connection succeeds but no Demand Active / Bitmap Update / Graphics Update PDUs are processed, so there's no live desktop image
- `get_framebuffer()` currently returns a static (empty/blank) `DecodedImage` buffer sized to the negotiated resolution — it is not populated by a background PDU-processing loop yet
- No streaming API (`StreamSink`) for pushing framebuffer updates to Flutter as they arrive — will need `#[frb(stream)]` similar to how `ssh.rs`'s `open_shell()` streams terminal output
- No mouse or keyboard input forwarding to the RDP session (would need `ironrdp-input` PDU encoding + FRB functions + Flutter gesture/key handlers)
- `RdpSessionScreen` shows a static "session active" info card, not an actual rendered desktop
- Not tested against a real RDP server or live sshd-equivalent (xrdp) in this environment — only compiles cleanly and the connect sequence is implemented per the IronRDP `screenshot.rs` reference example

**Files Modified**:
- `rust/Cargo.toml` - added IronRDP + supporting crates
- `rust/src/api/rdp.rs` (new file) - RDP connection handling
- `rust/src/api/mod.rs` - registered `pub mod rdp;`
- `rust/src/api/models.rs` - added `domain` field to `Connection`
- `rust/src/api/app.rs` - `add_connection()` domain param, `test_connection()` RDP dispatch
- `rust/src/api/ssh.rs`, `rust/src/api/import.rs` - updated `Connection` struct literals for new `domain` field
- `lib/screens/connection_detail_screen.dart` - domain field UI (RDP-only)
- `lib/screens/rdp_session_screen.dart` (new file) - RDP session screen
- `lib/screens/home_screen.dart` - RDP routing in `_connectToSession()`
- FRB bindings regenerated

**Testing performed**:
- `cargo check` - compiles cleanly
- `flutter analyze` - no issues
- `flutter build windows --release` - builds successfully
- **Not tested**: live connection against a real Windows RDP server or Linux xrdp (no test infrastructure available in this environment) - the connect sequence is implemented correctly per IronRDP's reference `screenshot.rs` example but has not been exercised against a live server

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

**Last Updated**: 2026-09-18  
**Latest**: v0.11.0 (RDP foundation ready for testing) - RDP protocol integration with IronRDP, connection establishment, domain auth support  
**Next Priority**: RDP Phase 2 - Implement PDU read loop, framebuffer streaming, and input forwarding to complete the RDP client
