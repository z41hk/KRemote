import 'package:flutter/material.dart';
import 'package:kremote/src/rust/api/app.dart';
import 'home_screen.dart';

/// Shown at app startup when no vault exists yet (create flow) or when
/// an existing vault needs to be unlocked with the master password.
class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _isLoading = true;
  bool _vaultExists = false;
  bool _isSubmitting = false;
  bool _rememberPassword = false;
  bool _hasStoredPassword = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkVaultExists();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultExists() async {
    final path = defaultVaultPath();
    final hasStored = isMasterPasswordInKeyring();
    
    setState(() {
      _vaultExists = vaultExists(path: path);
      _hasStoredPassword = hasStored;
      _isLoading = false;
    });

    // If we have a stored password and the vault exists, try auto-unlock
    if (_vaultExists && _hasStoredPassword) {
      await _tryAutoUnlock();
    }
  }

  Future<void> _tryAutoUnlock() async {
    try {
      final storedPassword = await getMasterPasswordFromKeyring();
      if (storedPassword != null) {
        final path = defaultVaultPath();
        await unlockVault(masterPassword: storedPassword, path: path);
        
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      // Auto-unlock failed - show the form so user can enter password manually
      setState(() {
        _error = 'Auto-unlock failed: ${e.toString()}';
        _hasStoredPassword = false; // Clear the stored password indicator
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final path = defaultVaultPath();
    final password = _passwordController.text;

    try {
      if (_vaultExists) {
        await unlockVault(masterPassword: password, path: path);
      } else {
        await createVault(masterPassword: password, path: path);
      }

      // If "Remember me" is checked, save password to keyring
      if (_rememberPassword) {
        try {
          await saveMasterPasswordToKeyring(password: password);
        } catch (e) {
          // Non-fatal: just log the error, don't block the unlock
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save password: $e')),
          );
        }
      } else if (_hasStoredPassword) {
        // User unchecked "Remember me", so delete the stored password
        try {
          await deleteMasterPasswordFromKeyring();
        } catch (e) {
          // Non-fatal
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    size: 56,
                    color: const Color(0xFF22D3EE),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _vaultExists ? 'Unlock Vault' : 'Create Your Vault',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _vaultExists
                        ? 'Enter your master password to unlock stored connections.'
                        : 'Choose a strong master password. It encrypts every credential you store here and is never sent anywhere.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    autofocus: true,
                    style: const TextStyle(color: Color(0xFFF8FAFC)),
                    decoration: InputDecoration(
                      labelText: 'Master Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (!_vaultExists && value.length < 8) {
                        return 'Use at least 8 characters';
                      }
                      return null;
                    },
                    onFieldSubmitted: (_) {
                      if (_vaultExists) _submit();
                    },
                  ),
                  if (!_vaultExists) ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Color(0xFFF8FAFC)),
                      decoration: InputDecoration(
                        labelText: 'Confirm Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: _rememberPassword || _hasStoredPassword,
                        onChanged: (value) {
                          setState(() {
                            _rememberPassword = value ?? false;
                          });
                        },
                        activeColor: const Color(0xFF22D3EE),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _rememberPassword = !(_rememberPassword || _hasStoredPassword);
                            });
                          },
                          child: Text(
                            'Remember master password',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Saves password in Windows Credential Manager for auto-unlock',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22D3EE),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0F172A),
                            ),
                          )
                        : Text(
                            _vaultExists ? 'Unlock' : 'Create Vault',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
