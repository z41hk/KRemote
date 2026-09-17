import 'package:flutter/material.dart';

/// Dialog for prompting SSH private key passphrase when connecting
/// to a server with an encrypted key file.
class PassphraseDialog extends StatefulWidget {
  final String keyPath;

  const PassphraseDialog({super.key, required this.keyPath});

  @override
  State<PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<PassphraseDialog> {
  final _passphraseController = TextEditingController();
  bool _obscurePassphrase = true;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      title: const Text(
        'Private Key Passphrase',
        style: TextStyle(color: Color(0xFFF8FAFC)),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The private key is encrypted:',
            style: TextStyle(
              color: const Color(0xFFF8FAFC).withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.keyPath,
            style: const TextStyle(
              color: Color(0xFF22D3EE),
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _passphraseController,
            obscureText: _obscurePassphrase,
            autofocus: true,
            style: const TextStyle(color: Color(0xFFF8FAFC)),
            decoration: InputDecoration(
              labelText: 'Passphrase',
              labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF94A3B8)),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassphrase
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF94A3B8),
                ),
                onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF475569)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF475569)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF22D3EE)),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text(
            'Cancel',
            style: TextStyle(color: Color(0xFF94A3B8)),
          ),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22D3EE),
            foregroundColor: const Color(0xFF0F172A),
          ),
          child: const Text('Connect'),
        ),
      ],
    );
  }

  void _submit() {
    final passphrase = _passphraseController.text;
    Navigator.of(context).pop(passphrase.isEmpty ? null : passphrase);
  }
}

/// Show passphrase dialog and return the entered passphrase or null if cancelled
Future<String?> showPassphraseDialog(BuildContext context, String keyPath) {
  return showDialog<String?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => PassphraseDialog(keyPath: keyPath),
  );
}
