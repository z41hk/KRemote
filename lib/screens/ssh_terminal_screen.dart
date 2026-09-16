import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:kremote/src/rust/api/models.dart';
import 'package:kremote/src/rust/api/ssh.dart';

/// Full SSH terminal with interactive shell session
class SshTerminalScreen extends StatefulWidget {
  final Connection connection;

  const SshTerminalScreen({super.key, required this.connection});

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  late Terminal _terminal;
  bool _isConnecting = true;
  String? _error;
  SshConnection? _sshConnection;
  StreamSubscription<Uint8List>? _outputSubscription;

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 10000,
    );
    _connectAndStartShell();
  }

  Future<void> _connectAndStartShell() async {
    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      _terminal.write(
          'Connecting to ${widget.connection.host}:${widget.connection.port}...\r\n');

      final ssh = await SshConnection.newInstance();
      await ssh.connect(connection: widget.connection);
      _sshConnection = ssh;

      _terminal.write('Connected. Starting shell...\r\n\r\n');

      final outputStream = ssh.openShell(
        termType: 'xterm-256color',
        cols: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );

      _outputSubscription = outputStream.listen(
        (data) {
          _terminal.write(String.fromCharCodes(data));
        },
        onError: (e) {
          if (!mounted) return;
          setState(() => _error = e.toString());
          _terminal.write('\r\n[Connection error: $e]\r\n');
        },
        onDone: () {
          if (!mounted) return;
          _terminal.write('\r\n[Session closed]\r\n');
        },
      );

      // Forward terminal keystrokes to the SSH shell
      _terminal.onOutput = (data) {
        _sshConnection?.sendInput(data: data.codeUnits);
      };

      // Forward terminal resize events to the PTY
      _terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _sshConnection?.resizePty(cols: width, rows: height);
      };

      setState(() => _isConnecting = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
      _terminal.write('Error: $e\r\n');
    }
  }

  @override
  void dispose() {
    _outputSubscription?.cancel();
    _sshConnection?.closeShell();
    _sshConnection?.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text('SSH: ${widget.connection.name}'),
        backgroundColor: const Color(0xFF1E293B),
        actions: [
          if (_isConnecting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: _connectAndStartShell,
            ),
        ],
      ),
      body: TerminalView(
        _terminal,
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
      ),
    );
  }
}
