# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-09-17

### Added
- Tag assignment UI with chip-based add/remove in connection editor
- Folder assignment dropdown with hierarchical folder support in connection editor
- Advanced filtering on home screen: search by name/host/username/tags, filter by protocol and folder
- Folder tree view with expand/collapse in home screen
- Connection cloning feature for quick duplication
- Folder management dialog for creating/deleting folders
- Import mRemoteNG XML functionality
- Export vault to JSON for backup
- Tag display chips on connection cards
- Context menu (clone/delete) on connection cards
- Pull-to-refresh on connection list
- Empty state handling for search results with "no matches" message

### Fixed
- SSH terminal keyboard input: removed outer `GestureDetector` wrapper that blocked xterm's internal focus/gesture handling; all keys now work (previously only Enter/Ctrl+C worked)
- SSH session deadlock: switched to non-blocking mode with retry logic for `WouldBlock` errors on read/write/resize

## [0.1.0] - 2026-09-16

### Added
- Initial project structure with Flutter + Rust architecture
- Encrypted credential vault with AES-256-GCM and Argon2id password hashing
- Connection management (CRUD operations)
- SSH connection testing via libssh2
- Multi-protocol support foundation (SSH, RDP, VNC, HTTP, HTTPS, VPN)
- Vault operations: create, unlock, lock, auto-save
- Modern dark slate UI theme with protocol-specific colors
- Cross-platform vault file storage (AppData on Windows, ~/.config on Linux)
- Master password validation (minimum 8 characters)
- Connection detail screen with edit/delete capabilities
- Protocol-specific icons and color coding
- Connection test functionality (SSH working, others stubbed)

### Fixed
- Navigator assertion error during vault status check (deferred navigation to post-frame callback)
- Unused mut warning in SSH disconnect function

### Security
- Vault encryption using industry-standard Argon2id + AES-256-GCM
- Password hash verification without timing attacks
- Sensitive data cleared from memory on vault lock

### Added
- Initial MVP release
- Basic vault and connection management
- SSH connection testing
- Windows build support

---

## Version History

- **0.4.0** (2026-09-17): Advanced UI features - tags, folders, import/export, fixed SSH keyboard input
- **0.3.2** (2026-09-17): SSH terminal keyboard input fix
- **0.3.1** (2026-09-17): Documentation update
- **0.3.0** (2026-09-17): SSH interactive terminal with xterm 4.0.0
- **0.2.0** (2026-09-16): Early alpha improvements
- **0.1.0** (2026-09-16): Initial MVP with vault, connection management, and SSH testing
- **Unreleased**: Active development

## Upgrade Notes

### From mRemoteNG
This project does not yet support importing mRemoteNG connection files. Migration tools are planned for a future release.

### Future Breaking Changes
- Vault file format may change before 1.0.0 (migration path will be provided)
- Public Rust API is not yet stable

## Roadmap

See [README.md](README.md#roadmap) for the detailed project roadmap.
