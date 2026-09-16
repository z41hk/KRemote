# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Changed
- N/A (initial release)

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- Navigator assertion error during vault status check (deferred navigation to post-frame callback)
- Unused mut warning in SSH disconnect function

### Security
- Vault encryption using industry-standard Argon2id + AES-256-GCM
- Password hash verification without timing attacks
- Sensitive data cleared from memory on vault lock

## [0.1.0] - 2026-09-16

### Added
- Initial MVP release
- Basic vault and connection management
- SSH connection testing
- Windows build support

---

## Version History

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
