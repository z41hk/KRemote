import 'package:flutter/material.dart';
import 'package:kremote/src/rust/api/app.dart';
import 'package:kremote/src/rust/api/models.dart';
import 'vault_screen.dart';
import 'connection_detail_screen.dart';
import 'ssh_terminal_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Connection> _connections = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  Future<void> _checkVaultStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final vaultPath = defaultVaultPath();
      final exists = vaultExists(path: vaultPath);
      final unlocked = isVaultUnlocked();

      if (!exists || !unlocked) {
        if (!mounted) return;
        // Defer navigation until after the current frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const VaultScreen()),
          );
        });
        return;
      }

      await _loadConnections();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadConnections() async {
    try {
      final connections = await getConnections();
      setState(() {
        _connections = connections;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _addConnection() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ConnectionDetailScreen(),
      ),
    );

    if (result == true) {
      await _loadConnections();
    }
  }

  Future<void> _editConnection(Connection connection) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConnectionDetailScreen(connection: connection),
      ),
    );

    if (result == true) {
      await _loadConnections();
    }
  }

  Future<void> _deleteConnection(Connection connection) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Connection'),
        content: Text('Delete "${connection.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await deleteConnection(id: connection.id, path: defaultVaultPath());
      await _loadConnections();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete: $e')),
      );
    }
  }

  Future<void> _testConnection(Connection connection) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await testConnection(connectionId: connection.id);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Test failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _connectToSession(Connection connection) async {
    switch (connection.protocol) {
      case Protocol.ssh:
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SshTerminalScreen(connection: connection),
          ),
        );
        break;
      case Protocol.rdp:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('RDP support coming soon')),
        );
        break;
      case Protocol.vnc:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VNC support coming soon')),
        );
        break;
      case Protocol.http:
      case Protocol.https:
        try {
          final url = '${connection.protocol.name}://${connection.host}:${connection.port}';
          await openUrl(url: url);
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to open URL: $e')),
          );
        }
        break;
      case Protocol.vpn:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VPN support coming soon')),
        );
        break;
    }
  }

  void _lockVault() {
    lockVault();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VaultScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _checkVaultStatus,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock Vault',
            onPressed: _lockVault,
          ),
        ],
      ),
      body: _connections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.link_off,
                    size: 64,
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No connections yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add your first connection to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadConnections,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _connections.length,
                itemBuilder: (context, index) {
                  final conn = _connections[index];
                  return _ConnectionCard(
                    connection: conn,
                    onTap: () => _editConnection(conn),
                    onConnect: () => _connectToSession(conn),
                    onTest: () => _testConnection(conn),
                    onDelete: () => _deleteConnection(conn),
                  );
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addConnection,
        icon: const Icon(Icons.add),
        label: const Text('Add Connection'),
        backgroundColor: const Color(0xFF22D3EE),
        foregroundColor: const Color(0xFF0F172A),
      ),
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  const _ConnectionCard({
    required this.connection,
    required this.onTap,
    required this.onConnect,
    required this.onTest,
    required this.onDelete,
  });

  IconData _getProtocolIcon() {
    switch (connection.protocol) {
      case Protocol.ssh:
        return Icons.terminal;
      case Protocol.rdp:
        return Icons.desktop_windows;
      case Protocol.vnc:
        return Icons.screen_share;
      case Protocol.http:
      case Protocol.https:
        return Icons.language;
      case Protocol.vpn:
        return Icons.vpn_lock;
    }
  }

  Color _getProtocolColor() {
    switch (connection.protocol) {
      case Protocol.ssh:
        return const Color(0xFF22D3EE);
      case Protocol.rdp:
        return const Color(0xFF4FD1C5);
      case Protocol.vnc:
        return const Color(0xFFF97316);
      case Protocol.http:
      case Protocol.https:
        return const Color(0xFFF59E0B);
      case Protocol.vpn:
        return const Color(0xFFA78BFA);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _getProtocolColor().withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _getProtocolIcon(),
                  color: _getProtocolColor(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      connection.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFF8FAFC),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${connection.host}:${connection.port}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                    if (connection.username != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        connection.username!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cable),
                tooltip: 'Connect',
                onPressed: onConnect,
                color: const Color(0xFF4ADE80),
              ),
              IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: 'Test Connection',
                onPressed: onTest,
                color: const Color(0xFF22D3EE),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete',
                onPressed: onDelete,
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
