# Contributing to Remote Manager

Thank you for your interest in contributing! This document provides guidelines and information for contributors.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork locally
3. Set up the development environment (see README.md)
4. Create a **feature branch** from `main`
5. Make your changes
6. **Test** thoroughly
7. Submit a **Pull Request**

## Development Setup

### Prerequisites
- Flutter SDK 3.13+
- Rust stable toolchain
- flutter_rust_bridge_codegen
- Platform-specific build tools (see README.md)

### First-time Setup
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Install flutter_rust_bridge codegen
cargo install flutter_rust_bridge_codegen

# Get Flutter dependencies
flutter pub get

# Generate FFI bindings
flutter_rust_bridge_codegen generate
```

## Code Style

### Rust
- Run `cargo fmt` before committing
- Run `cargo clippy` and fix all warnings
- Use `Result<T, String>` for error handling in public APIs
- Document public functions with `///` doc comments
- Keep FFI-exposed functions simple (avoid complex lifetimes)

Example:
```rust
/// Test SSH connection to a remote host
///
/// Returns success message on successful connection, error message otherwise
pub fn test_ssh_connection(conn: Connection) -> Result<String, String> {
    // implementation
}
```

### Dart/Flutter
- Run `dart format .` before committing
- Run `flutter analyze` and fix all issues
- Use meaningful variable names
- Follow Flutter widget composition patterns
- Use `const` constructors where possible

Example:
```dart
class ConnectionCard extends StatelessWidget {
  const ConnectionCard({
    super.key,
    required this.connection,
    required this.onTap,
    required this.onTest,
  });
  
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onTest;
  
  @override
  Widget build(BuildContext context) {
    // implementation
  }
}
```

## Project Structure

```
remote_manager/
├── lib/                  # Flutter UI code
│   ├── screens/          # UI screens
│   ├── widgets/          # Reusable widgets (TODO)
│   └── src/rust/         # Generated Rust bindings (don't edit manually)
├── rust/                 # Rust core
│   └── src/
│       ├── api/          # Public API exposed to Flutter
│       │   ├── app.rs    # App-level functions
│       │   ├── vault.rs  # Vault operations
│       │   ├── models.rs # Data models
│       │   └── ssh.rs    # SSH protocol
│       └── lib.rs        # Entry point
└── tests/                # Integration tests (TODO)
```

## Making Changes

### Adding a New Protocol

1. **Rust side** (`rust/src/api/`):
   - Add protocol enum variant to `models.rs`
   - Create new module (e.g., `rdp.rs`)
   - Implement connection logic using appropriate library (FreeRDP, etc.)
   - Expose public functions with `#[flutter_rust_bridge::frb]` attribute

2. **Generate bindings**:
   ```bash
   flutter_rust_bridge_codegen generate
   ```

3. **Flutter side** (`lib/screens/`):
   - Add protocol to UI dropdowns
   - Create detail screen if needed
   - Wire up test/connect buttons

### Adding a New Screen

1. Create file in `lib/screens/` (e.g., `settings_screen.dart`)
2. Follow existing screen patterns (AppBar, body, error handling)
3. Use `Navigator.push()` for navigation
4. Call Rust API functions via generated bindings

### Modifying the Vault Format

⚠️ **Breaking change** - requires migration strategy!

1. Increment `version` field in vault file format
2. Add migration logic in `vault.rs`
3. Test with existing vault files
4. Document migration in CHANGELOG

## Testing

### Rust Tests
```bash
cd rust
cargo test
```

### Flutter Tests
```bash
flutter test  # Unit tests (TODO)
flutter test integration_test  # Integration tests (TODO)
```

### Manual Testing Checklist
- [ ] Create new vault with strong password
- [ ] Unlock vault with correct password
- [ ] Fail to unlock with wrong password
- [ ] Add connection (all protocol types)
- [ ] Edit connection
- [ ] Delete connection
- [ ] Test SSH connection (success + failure cases)
- [ ] Lock vault - verify memory cleared
- [ ] Restart app - verify persistence
- [ ] Delete vault file - verify create new vault flow

## Pull Request Process

1. **Branch naming**: `feature/add-rdp-support`, `fix/vault-unlock-crash`, `docs/update-readme`
2. **Commit messages**: Use conventional commits
   - `feat: add RDP protocol support`
   - `fix: crash on empty password field`
   - `docs: update installation instructions`
   - `refactor: extract connection card widget`
3. **PR title**: Clear, concise description (< 70 chars)
4. **PR description**: Include:
   - What changed and why
   - How to test
   - Screenshots (for UI changes)
   - Breaking changes (if any)
5. **Testing**: Verify your changes work on at least one platform
6. **Review**: Address reviewer feedback promptly

## Areas Needing Help

### High Priority
- [ ] RDP protocol integration (FreeRDP)
- [ ] VNC protocol integration
- [ ] Full SSH terminal emulator (not just connection test)
- [ ] Connection folders/groups
- [ ] Linux build testing and fixes
- [ ] Unit tests for Rust modules
- [ ] Integration tests for Flutter UI

### Medium Priority
- [ ] Jump host SSH tunneling
- [ ] Session recording
- [ ] Import from mRemoteNG XML format
- [ ] Export connections to JSON
- [ ] Backup/restore vault
- [ ] Settings screen (theme, auto-lock timeout, etc.)

### Future / Ideas
- [ ] Mobile UI adaptation (Android/iOS)
- [ ] Plugin system architecture
- [ ] Team vault sync server
- [ ] LDAP/AD integration
- [ ] MFA/hardware key support

## Security

### Reporting Vulnerabilities
**Do not open public issues for security vulnerabilities.**

Email security concerns to: [your-email@example.com]

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

### Security Best Practices
- Never commit secrets or credentials
- Use `cargo audit` to check for vulnerable dependencies
- Keep cryptography operations in Rust (not Dart)
- Clear sensitive data from memory on vault lock
- Validate all user input
- Use parameterized queries (when we add database support)

## Code of Conduct

### Be Respectful
- Use welcoming and inclusive language
- Respect differing viewpoints and experiences
- Accept constructive criticism gracefully
- Focus on what's best for the project

### Be Professional
- Provide helpful, constructive feedback in reviews
- Explain *why* changes are needed
- Offer alternatives when rejecting ideas
- Assume good intent

### Unacceptable Behavior
- Harassment, insults, or discriminatory comments
- Trolling or sustained disruption
- Publishing others' private information
- Spam or off-topic discussions

Violations may result in temporary or permanent ban from the project.

## Questions?

- **General questions**: [GitHub Discussions](https://github.com/yourusername/remote_manager/discussions)
- **Bug reports**: [GitHub Issues](https://github.com/yourusername/remote_manager/issues)
- **Feature requests**: [GitHub Issues](https://github.com/yourusername/remote_manager/issues) with `enhancement` label

---

Thank you for contributing to Remote Manager!
