import 'package:flutter/material.dart';
import 'package:kremote/src/rust/api/app.dart';
import 'package:kremote/src/rust/api/models.dart';

/// Screen for adding a new connection or editing an existing one.
class ConnectionDetailScreen extends StatefulWidget {
  final Connection? connection;

  const ConnectionDetailScreen({super.key, this.connection});

  @override
  State<ConnectionDetailScreen> createState() => _ConnectionDetailScreenState();
}

class _ConnectionDetailScreenState extends State<ConnectionDetailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _hostController = TextEditingController();
  final _portController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _privateKeyController = TextEditingController();
  final _tagInputController = TextEditingController();

  Protocol _selectedProtocol = Protocol.ssh;
  bool _obscurePassword = true;
  bool _isSubmitting = false;
  String? _selectedFolderId;
  List<String> _tags = [];
  List<Folder> _folders = [];
  bool _isLoadingFolders = true;

  @override
  void initState() {
    super.initState();
    if (widget.connection != null) {
      final conn = widget.connection!;
      _nameController.text = conn.name;
      _hostController.text = conn.host;
      _portController.text = conn.port.toString();
      _usernameController.text = conn.username ?? '';
      _passwordController.text = conn.password ?? '';
      _privateKeyController.text = conn.privateKeyPath ?? '';
      _selectedProtocol = conn.protocol;
      _selectedFolderId = conn.folderId;
      _tags = List<String>.from(conn.tags);
    } else {
      _portController.text = '22'; // default SSH port
    }
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await getFolders();
      setState(() {
        _folders = folders;
        _isLoadingFolders = false;
      });
    } catch (e) {
      setState(() => _isLoadingFolders = false);
    }
  }

  void _addTag(String rawTag) {
    final tag = rawTag.trim();
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() {
      _tags.add(tag);
      _tagInputController.clear();
    });
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _privateKeyController.dispose();
    _tagInputController.dispose();
    super.dispose();
  }

  int _defaultPortForProtocol(Protocol protocol) {
    switch (protocol) {
      case Protocol.ssh:
        return 22;
      case Protocol.rdp:
        return 3389;
      case Protocol.vnc:
        return 5900;
      case Protocol.http:
        return 80;
      case Protocol.https:
        return 443;
      case Protocol.vpn:
        return 1194;
    }
  }

  void _onProtocolChanged(Protocol? protocol) {
    if (protocol == null) return;
    setState(() {
      _selectedProtocol = protocol;
      if (_portController.text.isEmpty ||
          _portController.text == _defaultPortForProtocol(_selectedProtocol).toString()) {
        _portController.text = _defaultPortForProtocol(protocol).toString();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    final path = defaultVaultPath();

    try {
      if (widget.connection == null) {
        // Add new connection
        await addConnection(
          name: _nameController.text.trim(),
          protocol: _selectedProtocol,
          host: _hostController.text.trim(),
          port: int.parse(_portController.text),
          username: _usernameController.text.isEmpty ? null : _usernameController.text,
          password: _passwordController.text.isEmpty ? null : _passwordController.text,
          privateKeyPath: _privateKeyController.text.isEmpty ? null : _privateKeyController.text,
          folderId: _selectedFolderId,
          tags: _tags,
          path: path,
        );
      } else {
        // Update existing connection
        final updated = Connection(
          id: widget.connection!.id,
          name: _nameController.text.trim(),
          protocol: _selectedProtocol,
          host: _hostController.text.trim(),
          port: int.parse(_portController.text),
          username: _usernameController.text.isEmpty ? null : _usernameController.text,
          password: _passwordController.text.isEmpty ? null : _passwordController.text,
          privateKeyPath: _privateKeyController.text.isEmpty ? null : _privateKeyController.text,
          folderId: _selectedFolderId,
          tags: _tags,
          notes: widget.connection!.notes,
        );
        await updateConnection(connection: updated, path: path);
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.connection != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Connection' : 'New Connection'),
        actions: [
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !isEditing,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Connection Name',
                hintText: 'My Server',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Name required' : null,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Protocol>(
              initialValue: _selectedProtocol,
              dropdownColor: const Color(0xFF1E293B),
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Protocol',
                prefixIcon: const Icon(Icons.settings_ethernet),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: Protocol.values.map((p) {
                return DropdownMenuItem(
                  value: p,
                  child: Text(p.name.toUpperCase()),
                );
              }).toList(),
              onChanged: _onProtocolChanged,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _hostController,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Host',
                hintText: 'example.com or 192.168.1.100',
                prefixIcon: const Icon(Icons.dns_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Host required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _portController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Port',
                prefixIcon: const Icon(Icons.power_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Port required';
                final port = int.tryParse(v);
                if (port == null || port < 1 || port > 65535) {
                  return 'Enter a valid port (1-65535)';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Credentials (Optional)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _usernameController,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Username',
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (_selectedProtocol == Protocol.ssh) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _privateKeyController,
                style: const TextStyle(color: Color(0xFFF8FAFC)),
                decoration: InputDecoration(
                  labelText: 'Private Key Path',
                  hintText: '/home/user/.ssh/id_rsa',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Text(
              'Organization',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingFolders)
              const Center(child: CircularProgressIndicator())
            else
              DropdownButtonFormField<String?>(
                initialValue: _selectedFolderId,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(color: Color(0xFFF8FAFC)),
                decoration: InputDecoration(
                  labelText: 'Folder (Optional)',
                  prefixIcon: const Icon(Icons.folder_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (Root Level)'),
                  ),
                  ..._folders.map((folder) => DropdownMenuItem<String?>(
                    value: folder.id,
                    child: Text(folder.name),
                  )),
                ],
                onChanged: (value) => setState(() => _selectedFolderId = value),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _tagInputController,
              style: const TextStyle(color: Color(0xFFF8FAFC)),
              decoration: InputDecoration(
                labelText: 'Add Tags',
                hintText: 'Press Enter to add',
                prefixIcon: const Icon(Icons.label_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onSubmitted: _addTag,
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((tag) => Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => _removeTag(tag),
                  backgroundColor: const Color(0xFF4FD1C5).withValues(alpha: 0.2),
                  side: BorderSide(
                    color: const Color(0xFF4FD1C5).withValues(alpha: 0.4),
                  ),
                  labelStyle: const TextStyle(color: Color(0xFF4FD1C5)),
                  deleteIconColor: const Color(0xFF4FD1C5),
                )).toList(),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _isSubmitting ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22D3EE),
              foregroundColor: const Color(0xFF0F172A),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              isEditing ? 'Save Changes' : 'Add Connection',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
