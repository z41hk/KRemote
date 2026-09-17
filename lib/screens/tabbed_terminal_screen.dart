import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:window_manager/window_manager.dart';
import 'package:kremote/src/rust/api/app.dart';
import 'package:kremote/src/rust/api/models.dart';
import 'package:kremote/src/rust/api/ssh.dart';
import 'package:kremote/widgets/passphrase_dialog.dart';

/// Session tabs - multiple SSH terminals in one window
class TabbedTerminalScreen extends StatefulWidget {
  final Connection initialConnection;

  const TabbedTerminalScreen({super.key, required this.initialConnection});

  @override
  State<TabbedTerminalScreen> createState() => _TabbedTerminalScreenState();
}

class _TabbedTerminalScreenState extends State<TabbedTerminalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<TerminalSession> _sessions = [];
  int _sessionCounter = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _tabController.addListener(_updateWindowTitle);
    _addSession(widget.initialConnection);
  }

  void _updateWindowTitle() {
    if (_sessions.isEmpty) return;
    final activeSession = _sessions[_tabController.index];
    windowManager.setTitle('KRemote - ${activeSession.connection.name}');
  }

  void _addSession(Connection connection) {
    setState(() {
      final session = TerminalSession(
        id: _sessionCounter++,
        connection: connection,
        onClose: _closeSession,
      );
      _sessions.add(session);
      _tabController.dispose();
      _tabController = TabController(
        length: _sessions.length,
        vsync: this,
        initialIndex: _sessions.length - 1,
      );
      _tabController.addListener(_updateWindowTitle);
    });
    _updateWindowTitle();
  }

  void _closeSession(int sessionId) {
    final index = _sessions.indexWhere((s) => s.id == sessionId);
    if (index == -1) return;

    setState(() {
      _sessions[index].dispose();
      _sessions.removeAt(index);

      if (_sessions.isEmpty) {
        Navigator.of(context).pop();
        return;
      }

      final newIndex = index >= _sessions.length ? _sessions.length - 1 : index;
      _tabController.dispose();
      _tabController = TabController(
        length: _sessions.length,
        vsync: this,
        initialIndex: newIndex,
      );
      _tabController.addListener(_updateWindowTitle);
    });
    _updateWindowTitle();
  }

  Future<void> _showConnectionPicker() async {
    final connections = await getConnections();
    if (!mounted) return;

    final selected = await showDialog<Connection>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Open Connection'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: connections.length,
            itemBuilder: (context, index) {
              final conn = connections[index];
              return ListTile(
                leading: Icon(
                  conn.protocol == Protocol.ssh
                      ? Icons.terminal
                      : Icons.computer,
                  color: const Color(0xFF22D3EE),
                ),
                title: Text(conn.name),
                subtitle: Text('${conn.host}:${conn.port}'),
                onTap: () => Navigator.of(context).pop(conn),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (selected != null) {
      _addSession(selected);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        toolbarHeight: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: const Color(0xFF1E293B),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    indicatorColor: const Color(0xFF22D3EE),
                    indicatorWeight: 2,
                    labelColor: const Color(0xFFF8FAFC),
                    unselectedLabelColor: const Color(0xFF94A3B8),
                    dividerColor: Colors.transparent,
                    tabs: _sessions.map((session) {
                      return Tab(
                        height: 48,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Connection status indicator
                            Container(
                              width: 6,
                              height: 6,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: session.isConnecting
                                    ? const Color(0xFFFBBF24)
                                    : session.error != null
                                        ? const Color(0xFFEF4444)
                                        : const Color(0xFF4ADE80),
                              ),
                            ),
                            // Tab title
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                session.connection.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Close button
                            InkWell(
                              onTap: () => _closeSession(session.id),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                // Add new tab button
                Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    tooltip: 'Open connection in new tab',
                    color: const Color(0xFF94A3B8),
                    onPressed: _showConnectionPicker,
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _sessions.map((session) {
          return TerminalSessionView(session: session);
        }).toList(),
      ),
    );
  }
}

/// Represents a single SSH terminal session with its own terminal state
class TerminalSession {
  final int id;
  final Connection connection;
  final void Function(int) onClose;
  late Terminal terminal;
  bool isConnecting = true;
  String? error;
  SshConnection? sshConnection;
  StreamSubscription<Uint8List>? outputSubscription;
  final FocusNode focusNode;

  TerminalSession({
    required this.id,
    required this.connection,
    required this.onClose,
  }) : focusNode = FocusNode(debugLabel: 'terminal_$id') {
    terminal = Terminal(maxLines: 10000);
  }

  void dispose() {
    outputSubscription?.cancel();
    sshConnection?.closeShell();
    sshConnection?.disconnect();
    focusNode.dispose();
  }
}

/// Widget that displays a single terminal session
class TerminalSessionView extends StatefulWidget {
  final TerminalSession session;

  const TerminalSessionView({super.key, required this.session});

  @override
  State<TerminalSessionView> createState() => _TerminalSessionViewState();
}

class _TerminalSessionViewState extends State<TerminalSessionView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true; // Preserve terminal state when switching tabs

  @override
  void initState() {
    super.initState();
    _connectAndStartShell();
  }

  void _requestTerminalFocus() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.session.focusNode.requestFocus();
    });
  }

  Future<void> _connectAndStartShell() async {
    if (!mounted) return;
    
    setState(() {
      widget.session.isConnecting = true;
      widget.session.error = null;
    });

    try {
      widget.session.terminal.write(
          'Connecting to ${widget.session.connection.host}:${widget.session.connection.port}...\r\n');

      // Check if the connection uses an encrypted private key and prompt for passphrase
      Connection connectionToUse = widget.session.connection;
      if (connectionToUse.privateKeyPath != null && 
          connectionToUse.privateKeyPath!.isNotEmpty) {
        // Try connecting without passphrase first
        try {
          final testSsh = await SshConnection.newInstance();
          await testSsh.connect(connection: connectionToUse);
          testSsh.disconnect();
        } catch (e) {
          // If connection fails and error suggests encrypted key, prompt for passphrase
          if (e.toString().contains('passphrase') || 
              e.toString().contains('encrypted') ||
              e.toString().contains('decrypt')) {
            if (!mounted) return;
            final passphrase = await showPassphraseDialog(
              context, 
              connectionToUse.privateKeyPath!,
            );
            
            if (passphrase == null) {
              // User cancelled
              if (!mounted) return;
              setState(() {
                widget.session.error = 'Connection cancelled';
                widget.session.isConnecting = false;
              });
              widget.session.terminal.write('Connection cancelled by user.\r\n');
              return;
            }
            
            // Create new connection instance with passphrase
            connectionToUse = Connection(
              id: connectionToUse.id,
              name: connectionToUse.name,
              protocol: connectionToUse.protocol,
              host: connectionToUse.host,
              port: connectionToUse.port,
              username: connectionToUse.username,
              password: connectionToUse.password,
              privateKeyPath: connectionToUse.privateKeyPath,
              privateKeyPassphrase: passphrase,
              folderId: connectionToUse.folderId,
              tags: connectionToUse.tags,
              notes: connectionToUse.notes,
              jumpHostId: connectionToUse.jumpHostId,
              timeoutSeconds: connectionToUse.timeoutSeconds,
            );
          }
        }
      }

      final ssh = await SshConnection.newInstance();
      await ssh.connect(connection: connectionToUse);
      widget.session.sshConnection = ssh;

      widget.session.terminal.write('Connected. Starting shell...\r\n\r\n');

      final outputStream = ssh.openShell(
        termType: 'xterm-256color',
        cols: widget.session.terminal.viewWidth,
        rows: widget.session.terminal.viewHeight,
      );

      widget.session.outputSubscription = outputStream.listen(
        (data) {
          widget.session.terminal.write(String.fromCharCodes(data));
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => widget.session.error = e.toString());
          widget.session.terminal.write('\r\n[Connection error: $e]\r\n');
        },
        onDone: () {
          if (!mounted) return;
          widget.session.terminal.write('\r\n[Session closed]\r\n');
        },
      );

      // Forward terminal keystrokes to the SSH shell
      widget.session.terminal.onOutput = (data) {
        widget.session.sshConnection?.sendInput(data: data.codeUnits);
      };

      // Forward terminal resize events to the PTY
      widget.session.terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        widget.session.sshConnection?.resizePty(cols: width, rows: height);
      };

      setState(() => widget.session.isConnecting = false);
      _requestTerminalFocus();
    } catch (e) {
      setState(() {
        widget.session.error = e.toString();
        widget.session.isConnecting = false;
      });
      widget.session.terminal.write('Error: $e\r\n');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Column(
      children: [
        // Error/reconnect banner
        if (widget.session.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFF7F1D1D),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFFECACA), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Connection lost',
                    style: TextStyle(
                      color: const Color(0xFFFECACA),
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _connectAndStartShell,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reconnect'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFFECACA),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                ),
              ],
            ),
          ),
        // Terminal
        Expanded(
          child: TerminalView(
            widget.session.terminal,
            focusNode: widget.session.focusNode,
            theme: TerminalTheme(
              cursor: const Color(0xFF22D3EE),
              selection: const Color(0xFF4FD1C5),
              foreground: const Color(0xFFF8FAFC),
              background: const Color(0xFF0F172A),
              black: const Color(0xFF1E293B),
              red: const Color(0xFFF87171),
              green: const Color(0xFF4ADE80),
              yellow: const Color(0xFFFBBF24),
              blue: const Color(0xFF60A5FA),
              magenta: const Color(0xFFA78BFA),
              cyan: const Color(0xFF22D3EE),
              white: const Color(0xFFF8FAFC),
              brightBlack: const Color(0xFF475569),
              brightRed: const Color(0xFFEF4444),
              brightGreen: const Color(0xFF22C55E),
              brightYellow: const Color(0xFFF59E0B),
              brightBlue: const Color(0xFF3B82F6),
              brightMagenta: const Color(0xFF9333EA),
              brightCyan: const Color(0xFF06B6D4),
              brightWhite: const Color(0xFFFFFFFF),
              searchHitBackground: const Color(0xFFFBBF24),
              searchHitBackgroundCurrent: const Color(0xFFF97316),
              searchHitForeground: const Color(0xFF0F172A),
            ),
            textStyle: const TerminalStyle(
              fontFamily: 'Cascadia Code',
              fontFamilyFallback: ['Consolas', 'monospace'],
              fontSize: 14,
            ),
            autofocus: true,
            backgroundOpacity: 1.0,
            hardwareKeyboardOnly: true,
            readOnly: false,
          ),
        ),
      ],
    );
  }
}
