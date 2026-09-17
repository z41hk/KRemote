import 'package:flutter/material.dart';
import 'package:kremote/src/rust/api/app.dart';
import 'package:kremote/src/rust/api/models.dart';
import 'package:kremote/src/rust/api/ssh.dart';
import 'package:kremote/widgets/passphrase_dialog.dart';
import 'vault_screen.dart';
import 'connection_detail_screen.dart';
import 'tabbed_terminal_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Connection> _connections = [];
  List<Folder> _folders = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  Protocol? _filterProtocol;
  String? _filterFolderId;
  final Set<String> _expandedFolderIds = {};
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _checkVaultStatus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.toLowerCase();
    });
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
      final folders = await getFolders();
      setState(() {
        _connections = connections;
        _folders = folders;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<Connection> _getFilteredConnections() {
    var filtered = _connections.where((conn) {
      // Search filter
      if (_searchQuery.isNotEmpty) {
        final matchesSearch = 
          conn.name.toLowerCase().contains(_searchQuery) ||
          conn.host.toLowerCase().contains(_searchQuery) ||
          (conn.username?.toLowerCase().contains(_searchQuery) ?? false) ||
          conn.tags.any((tag) => tag.toLowerCase().contains(_searchQuery));
        if (!matchesSearch) return false;
      }
      
      // Protocol filter
      if (_filterProtocol != null && conn.protocol != _filterProtocol) {
        return false;
      }
      
      // Folder filter
      if (_filterFolderId != null && conn.folderId != _filterFolderId) {
        return false;
      }
      
      return true;
    }).toList();
    
    return filtered;
  }

  Map<String?, List<Connection>> _groupConnectionsByFolder(List<Connection> connections) {
    final Map<String?, List<Connection>> grouped = {};
    for (final conn in connections) {
      if (!grouped.containsKey(conn.folderId)) {
        grouped[conn.folderId] = [];
      }
      grouped[conn.folderId]!.add(conn);
    }
    return grouped;
  }

  void _toggleFolder(String folderId) {
    setState(() {
      if (_expandedFolderIds.contains(folderId)) {
        _expandedFolderIds.remove(folderId);
      } else {
        _expandedFolderIds.add(folderId);
      }
    });
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _filterProtocol = null;
      _filterFolderId = null;
    });
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
      // Check if connection uses an encrypted private key
      Connection connectionToUse = connection;
      if (connection.privateKeyPath != null && 
          connection.privateKeyPath!.isNotEmpty) {
        // Try connecting without passphrase first
        try {
          final testSsh = await SshConnection.newInstance();
          await testSsh.connect(connection: connection);
          testSsh.disconnect();
        } catch (e) {
          // If error suggests encrypted key, prompt for passphrase
          if (e.toString().contains('passphrase') || 
              e.toString().contains('encrypted') ||
              e.toString().contains('decrypt')) {
            if (!mounted) return;
            Navigator.pop(context); // Close loading dialog
            
            final passphrase = await showPassphraseDialog(
              context, 
              connection.privateKeyPath!,
            );
            
            if (passphrase == null) {
              // User cancelled
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Test cancelled'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            
            // Create connection with passphrase
            connectionToUse = Connection(
              id: connection.id,
              name: connection.name,
              protocol: connection.protocol,
              host: connection.host,
              port: connection.port,
              username: connection.username,
              password: connection.password,
              privateKeyPath: connection.privateKeyPath,
              privateKeyPassphrase: passphrase,
              folderId: connection.folderId,
              tags: connection.tags,
              notes: connection.notes,
              jumpHostId: connection.jumpHostId,
            );
            
            // Show loading dialog again
            if (!mounted) return;
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => const Center(child: CircularProgressIndicator()),
            );
          }
        }
      }

      // Actually test the connection
      final ssh = await SshConnection.newInstance();
      await ssh.connect(connection: connectionToUse);
      final result = await ssh.testConnection();
      ssh.disconnect();
      
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
            builder: (_) => TabbedTerminalScreen(initialConnection: connection),
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

  Future<void> _cloneConnection(Connection connection) async {
    try {
      // Clone by creating new connection with same properties but new ID
      await addConnection(
        name: '${connection.name} (Copy)',
        protocol: connection.protocol,
        host: connection.host,
        port: connection.port,
        username: connection.username,
        password: connection.password,
        privateKeyPath: connection.privateKeyPath,
        folderId: connection.folderId,
        tags: connection.tags,
        path: defaultVaultPath(),
        jumpHostId: connection.jumpHostId,
      );
      await _loadConnections();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection cloned successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to clone: $e')),
      );
    }
  }

  void _showFolderManagement() {
    showDialog(
      context: context,
      builder: (context) => _FolderManagementDialog(
        folders: _folders,
        onChanged: _loadConnections,
      ),
    );
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (context) => _ImportDialog(onImported: _loadConnections),
    );
  }

  Future<void> _exportVault() async {
    try {
      final json = await exportVaultJson();
      if (!mounted) return;
      
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export Vault'),
          content: SingleChildScrollView(
            child: SelectableText(json),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
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

    final filteredConnections = _getFilteredConnections();
    final groupedConnections = _groupConnectionsByFolder(filteredConnections);
    final hasActiveFilters = _searchQuery.isNotEmpty || _filterProtocol != null || _filterFolderId != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Remote Manager'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            tooltip: 'Manage Folders',
            onPressed: _showFolderManagement,
          ),
          IconButton(
            icon: const Icon(Icons.upload_file),
            tooltip: 'Import',
            onPressed: _showImportDialog,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onPressed: _exportVault,
          ),
          IconButton(
            icon: const Icon(Icons.lock),
            tooltip: 'Lock Vault',
            onPressed: _lockVault,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search connections...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1E293B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          
          // Filter chips
          if (_filterProtocol != null || _filterFolderId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (_filterProtocol != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('Protocol: ${_filterProtocol!.name.toUpperCase()}'),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _filterProtocol = null),
                        backgroundColor: const Color(0xFF22D3EE),
                        labelStyle: const TextStyle(color: Color(0xFF0F172A)),
                      ),
                    ),
                  if (_filterFolderId != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        label: Text('Folder: ${_folders.firstWhere((f) => f.id == _filterFolderId, orElse: () => Folder(id: '', name: 'Unknown', parentId: null)).name}'),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _filterFolderId = null),
                        backgroundColor: const Color(0xFFF97316),
                        labelStyle: const TextStyle(color: Color(0xFF0F172A)),
                      ),
                    ),
                  if (hasActiveFilters)
                    TextButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Clear All'),
                    ),
                ],
              ),
            ),
          
          const SizedBox(height: 8),
          
          // Connection list
          Expanded(
            child: _connections.isEmpty
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
                : filteredConnections.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: Colors.white.withValues(alpha: 0.3),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No matches found',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _clearFilters,
                              icon: const Icon(Icons.clear),
                              label: const Text('Clear Filters'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadConnections,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: _buildConnectionTree(groupedConnections),
                        ),
                      ),
          ),
        ],
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

  List<Widget> _buildConnectionTree(Map<String?, List<Connection>> groupedConnections) {
    final widgets = <Widget>[];
    
    // Build folder hierarchy
    final rootFolders = _folders.where((f) => f.parentId == null).toList();
    
    // Add root-level connections first (no folder)
    if (groupedConnections.containsKey(null)) {
      for (final conn in groupedConnections[null]!) {
        widgets.add(_ConnectionCard(
          connection: conn,
          onTap: () => _editConnection(conn),
          onConnect: () => _connectToSession(conn),
          onTest: () => _testConnection(conn),
          onDelete: () => _deleteConnection(conn),
          onClone: () => _cloneConnection(conn),
        ));
      }
    }
    
    // Add folders and their connections
    for (final folder in rootFolders) {
      widgets.addAll(_buildFolderWidget(folder, groupedConnections, 0));
    }
    
    return widgets;
  }

  List<Widget> _buildFolderWidget(Folder folder, Map<String?, List<Connection>> groupedConnections, int depth) {
    final widgets = <Widget>[];
    final isExpanded = _expandedFolderIds.contains(folder.id);
    final folderConnections = groupedConnections[folder.id] ?? [];
    final childFolders = _folders.where((f) => f.parentId == folder.id).toList();
    
    // Folder header
    widgets.add(
      Padding(
        padding: EdgeInsets.only(left: depth * 24.0, top: 8, bottom: 4),
        child: InkWell(
          onTap: () => _toggleFolder(folder.id),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isExpanded ? Icons.folder_open : Icons.folder,
                  color: const Color(0xFFF59E0B),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    folder.name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF8FAFC),
                    ),
                  ),
                ),
                Text(
                  '${folderConnections.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    // Folder contents (if expanded)
    if (isExpanded) {
      // Add connections in this folder
      for (final conn in folderConnections) {
        widgets.add(
          Padding(
            padding: EdgeInsets.only(left: (depth + 1) * 24.0),
            child: _ConnectionCard(
              connection: conn,
              onTap: () => _editConnection(conn),
              onConnect: () => _connectToSession(conn),
              onTest: () => _testConnection(conn),
              onDelete: () => _deleteConnection(conn),
              onClone: () => _cloneConnection(conn),
            ),
          ),
        );
      }
      
      // Recursively add child folders
      for (final childFolder in childFolders) {
        widgets.addAll(_buildFolderWidget(childFolder, groupedConnections, depth + 1));
      }
    }
    
    return widgets;
  }
}

class _ConnectionCard extends StatelessWidget {
  final Connection connection;
  final VoidCallback onTap;
  final VoidCallback onConnect;
  final VoidCallback onTest;
  final VoidCallback onDelete;
  final VoidCallback onClone;

  const _ConnectionCard({
    required this.connection,
    required this.onTap,
    required this.onConnect,
    required this.onTest,
    required this.onDelete,
    required this.onClone,
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    tooltip: 'More Options',
                    onSelected: (value) {
                      switch (value) {
                        case 'clone':
                          onClone();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'clone',
                        child: Row(
                          children: [
                            Icon(Icons.copy, size: 18),
                            SizedBox(width: 12),
                            Text('Clone'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Tags display
              if (connection.tags.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: connection.tags.map((tag) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4FD1C5).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: const Color(0xFF4FD1C5).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF4FD1C5),
                      ),
                    ),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderManagementDialog extends StatefulWidget {
  final List<Folder> folders;
  final VoidCallback onChanged;

  const _FolderManagementDialog({
    required this.folders,
    required this.onChanged,
  });

  @override
  State<_FolderManagementDialog> createState() => _FolderManagementDialogState();
}

class _FolderManagementDialogState extends State<_FolderManagementDialog> {
  final _nameController = TextEditingController();
  String? _selectedParentId;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Folder name cannot be empty')),
      );
      return;
    }

    try {
      await addFolder(
        name: name,
        parentId: _selectedParentId,
        path: defaultVaultPath(),
      );
      _nameController.clear();
      setState(() => _selectedParentId = null);
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder added successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add folder: $e')),
      );
    }
  }

  Future<void> _deleteFolder(Folder folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text('Delete "${folder.name}"? Connections in this folder will be moved to root.'),
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
      await deleteFolder(id: folder.id, path: defaultVaultPath());
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Folder deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete folder: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Folders'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Folder Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _selectedParentId,
              decoration: const InputDecoration(
                labelText: 'Parent Folder (Optional)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('None (Root Level)'),
                ),
                ...widget.folders.map((folder) => DropdownMenuItem<String?>(
                  value: folder.id,
                  child: Text(folder.name),
                )),
              ],
              onChanged: (value) => setState(() => _selectedParentId = value),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _addFolder,
              icon: const Icon(Icons.add),
              label: const Text('Add Folder'),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Existing Folders:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Flexible(
              child: widget.folders.isEmpty
                  ? const Text('No folders yet')
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.folders.length,
                      itemBuilder: (context, index) {
                        final folder = widget.folders[index];
                        return ListTile(
                          leading: const Icon(Icons.folder, color: Color(0xFFF59E0B)),
                          title: Text(folder.name),
                          subtitle: folder.parentId != null
                              ? Text('Parent: ${widget.folders.firstWhere((f) => f.id == folder.parentId, orElse: () => Folder(id: '', name: 'Unknown', parentId: null)).name}')
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteFolder(folder),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ImportDialog extends StatefulWidget {
  final VoidCallback onImported;

  const _ImportDialog({required this.onImported});

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _xmlController = TextEditingController();
  bool _isImporting = false;

  @override
  void dispose() {
    _xmlController.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final xml = _xmlController.text.trim();
    if (xml.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('XML content cannot be empty')),
      );
      return;
    }

    setState(() => _isImporting = true);

    try {
      final result = await importMremotengXml(
        xmlContent: xml,
        path: defaultVaultPath(),
      );
      widget.onImported();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${result.$1} connections and ${result.$2} folders'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import mRemoteNG XML'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _xmlController,
              decoration: const InputDecoration(
                labelText: 'Paste XML Content',
                border: OutlineInputBorder(),
              ),
              maxLines: 10,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isImporting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isImporting ? null : _import,
          child: _isImporting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Import'),
        ),
      ],
    );
  }
}
