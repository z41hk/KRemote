# Getting Started

## What You Have Now

A fully functional **cross-platform remote connection manager** with:

### Core Features
- **Multi-protocol support**: SSH, RDP, VNC, HTTP/HTTPS (more protocols planned)
- **Encrypted credential vault**: AES-256-GCM encryption with master password
- **Cross-platform**: Currently running on Windows, designed for Linux, macOS, iOS, Android
- **Native performance**: Rust core + Flutter UI
- **Modern UI**: Dark theme with protocol-specific color coding

### Architecture
```
┌─────────────────────────────────────┐
│   Flutter UI (Dart)                 │
│   - Home screen, vault, connection  │
│   - Cross-platform (iOS/Android/etc)│
└──────────────┬──────────────────────┘
               │ FFI
┌──────────────┴──────────────────────┐
│   Rust Core (native performance)    │
│   - SSH client (russh)               │
│   - RDP stub (ready for freerdp)    │
│   - VNC stub (ready for libvnc)     │
│   - Encrypted storage (AES-256-GCM) │
└─────────────────────────────────────┘
```

## What Works Right Now

### ✅ Fully Implemented
- Create/edit/delete connections
- Master password vault (encryption at rest)
- Protocol selection (SSH, RDP, VNC, HTTP, VPN)
- Connection metadata (host, port, credentials, tags)
- Persistent storage (SQLite + encrypted credentials)
- SSH connection launching (terminal opens in new process)

### 🚧 Stub/Planned
- **RDP**: Rust function exists, needs FreeRDP C library integration
- **VNC**: Rust function exists, needs LibVNC integration  
- **HTTP/HTTPS**: Should open system browser (not yet wired)
- **VPN**: Needs WireGuard integration
- **In-app session view**: Currently opens external terminal for SSH

## Quick Start

### Running the App
```powershell
cd C:\Users\User\dev\remote_manager
flutter run -d windows
```

### First Launch
1. App opens to vault screen
2. Choose a **master password** (this encrypts all credentials)
3. Add your first connection via the **+** button
4. Click "Connect" to launch a session

### Adding a Connection
1. Click the **+** floating action button
2. Fill in:
   - Name (e.g., "Production Server")
   - Protocol (SSH/RDP/VNC/HTTP/VPN)
   - Host (IP or domain)
   - Port (auto-fills based on protocol)
   - Username (optional)
   - Password (optional, stored encrypted)
3. Save

### Connecting
- Click **Connect** on any connection card
- SSH: Opens in Windows Terminal (or default terminal)
- RDP/VNC: Currently shows "not implemented" (next phase)

## Next Development Steps

### Phase 1: Complete SSH (In Progress)
- [x] SSH client in Rust core
- [x] Launch external terminal
- [ ] **In-app terminal emulator** (embed xterm.js or write native Flutter terminal widget)
- [ ] Session recording/audit trail

### Phase 2: Add RDP + VNC
- [ ] Integrate FreeRDP C library via Rust FFI
- [ ] Integrate LibVNC via Rust FFI
- [ ] Implement session view widget in Flutter
- [ ] Handle mouse/keyboard input properly

### Phase 3: Mobile Support
- [ ] Test on Android/iOS
- [ ] Touch gesture → mouse/keyboard translation
- [ ] Responsive UI for small screens

### Phase 4: Advanced Features
- [ ] Jump host / bastion chaining (SSH → SSH)
- [ ] Connection folders/groups
- [ ] Search/filter
- [ ] Import from mRemoteNG XML
- [ ] Export/backup vault
- [ ] Team sync (end-to-end encrypted cloud sync)

### Phase 5: Remote Control (AnyDesk-style)
- [ ] Integrate RustDesk or build custom
- [ ] NAT traversal + relay server
- [ ] Unattended access agent

## Project Structure

```
remote_manager/
├── lib/                    # Flutter (Dart) UI code
│   ├── main.dart           # Entry point
│   ├── models/             # Data models (Connection, Protocol)
│   ├── screens/            # UI screens (home, vault, detail)
│   ├── services/           # Business logic (vault, storage)
│   └── ffi_bridge.dart     # Calls into Rust
├── rust/                   # Native Rust core
│   ├── src/
│   │   ├── lib.rs          # FFI exports
│   │   ├── ssh.rs          # SSH client (russh)
│   │   ├── rdp.rs          # RDP stub
│   │   ├── vnc.rs          # VNC stub
│   │   └── storage.rs      # Encrypted vault
│   └── Cargo.toml          # Rust dependencies
├── README.md               # Project overview
├── ARCHITECTURE.md         # Technical deep-dive
├── ROADMAP.md              # Long-term feature plan
└── GETTING_STARTED.md      # This file
```

## Building for Other Platforms

### Linux
```bash
flutter build linux
```
Requires: `libssh-dev`, `libssl-dev`, `sqlite3-dev`

### Android
```bash
flutter build apk
```
Rust toolchain needs `aarch64-linux-android` target.

### iOS
```bash
flutter build ios
```
Requires macOS + Xcode. Rust needs `aarch64-apple-ios` target.

### macOS
```bash
flutter build macos
```

## Security Notes

- **Master password never leaves your device**
- Credentials encrypted with AES-256-GCM
- Encryption key derived via Argon2id (memory-hard KDF)
- SQLite database stores only encrypted blobs
- No telemetry, no cloud sync (yet — when added, it'll be E2E encrypted)

## Contributing Ideas

Since this is fully open source, here's what would help most:

1. **Protocol integration**: Wire up FreeRDP, LibVNC via Rust FFI
2. **In-app terminal**: Flutter terminal widget for SSH sessions
3. **Mobile testing**: Run on Android/iOS, fix touch input issues
4. **Import/Export**: mRemoteNG XML parser, CSV export
5. **Documentation**: More examples, video walkthrough
6. **Testing**: Unit tests for Rust core, widget tests for Flutter

## Troubleshooting

### "Master password incorrect"
The vault is encrypted. If you forget the password, you must delete `vault.db` and start over (credentials are unrecoverable by design).

### SSH connection fails
- Check host/port are correct
- Ensure SSH server is running
- Try manually: `ssh user@host -p port`

### Build errors on Linux
Install dependencies:
```bash
sudo apt install libssl-dev libsqlite3-dev libssh-dev clang cmake ninja-build
```

### Flutter not found
Add Flutter to PATH or use full path:
```powershell
$env:PATH = "C:\Users\User\dev\flutter\bin;" + $env:PATH
```

## Learn More

- [README.md](README.md) — Project overview
- [ARCHITECTURE.md](ARCHITECTURE.md) — How it all works
- [ROADMAP.md](ROADMAP.md) — Feature plan and timeline

---

**Built with Rust 🦀 + Flutter 💙 + Zero Compromises on Security 🔒**
