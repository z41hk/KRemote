use ssh2::{Channel, Session};
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream, ToSocketAddrs};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use super::models::Connection;
use crate::frb_generated::StreamSink;

/// Resolve `host:port` to a single `SocketAddr` and connect with a timeout.
/// `TcpStream::connect_timeout` requires a single resolved address (unlike
/// `TcpStream::connect`, which accepts anything implementing `ToSocketAddrs`
/// and tries each candidate in turn), so we resolve here and use the first
/// address DNS returns.
fn connect_with_timeout(address: &str, timeout_seconds: u64) -> Result<TcpStream, String> {
    let addr = address
        .to_socket_addrs()
        .map_err(|e| format!("Failed to resolve {}: {}", address, e))?
        .next()
        .ok_or_else(|| format!("No addresses found for {}", address))?;

    TcpStream::connect_timeout(&addr, Duration::from_secs(timeout_seconds))
        .map_err(|e| format!("Failed to connect to {} (timeout {}s): {}", address, timeout_seconds, e))
}

#[flutter_rust_bridge::frb(opaque)]
pub struct SshConnection {
    session: Option<Session>,
    /// Kept alive so the tunneled TCP connection through the jump host
    /// isn't dropped while `session` (the target session) is in use.
    _jump_session: Option<Session>,
    /// Interactive shell channel, once opened via `open_shell`.
    /// `Channel` is `Clone` and internally `Arc<Mutex<..>>`-guarded, so we
    /// can hand out clones to a background reader thread while keeping one
    /// here for writing input / resizing / closing.
    shell_channel: Arc<Mutex<Option<Channel>>>,
}

impl SshConnection {
    pub fn new() -> Self {
        Self {
            session: None,
            _jump_session: None,
            shell_channel: Arc::new(Mutex::new(None)),
        }
    }

    /// Connect directly to `connection`'s host:port and authenticate.
    /// If `connection.jump_host_id` is set, automatically routes through
    /// `connect_via_jump_host` instead.
    pub fn connect(&mut self, connection: &Connection) -> Result<(), String> {
        // If a jump host is configured, retrieve it and tunnel through it
        if let Some(ref jump_host_id) = connection.jump_host_id {
            let jump_host = super::app::vault()
                .get_connection(jump_host_id)
                .map_err(|e| format!("Failed to retrieve jump host: {}", e))?;
            return self.connect_via_jump_host(connection, &jump_host);
        }

        // Otherwise, connect directly
        let address = format!("{}:{}", connection.host, connection.port);

        let tcp = connect_with_timeout(&address, connection.timeout_seconds)?;

        let mut session = Session::new()
            .map_err(|e| format!("Failed to create SSH session: {}", e))?;

        session.set_tcp_stream(tcp);
        session
            .handshake()
            .map_err(|e| format!("SSH handshake failed: {}", e))?;

        Self::authenticate(&session, connection)?;

        self.session = Some(session);
        Ok(())
    }

    /// Connect to `connection`'s host:port by first establishing an SSH
    /// session to `jump_host`, then using SSH port forwarding to tunnel
    /// a local connection through it. This is the standard "jump host" /
    /// "bastion host" pattern.
    ///
    /// Implementation: We create a local TCP proxy that bridges between
    /// a loopback TcpStream (which satisfies Session::set_tcp_stream's
    /// AsRawSocket requirement) and the SSH channel opened via
    /// channel_direct_tcpip on the jump host.
    pub fn connect_via_jump_host(
        &mut self,
        connection: &Connection,
        jump_host: &Connection,
    ) -> Result<(), String> {
        // Connect and authenticate to the jump host
        let jump_address = format!("{}:{}", jump_host.host, jump_host.port);
        let jump_tcp = connect_with_timeout(&jump_address, jump_host.timeout_seconds)?;

        let mut jump_session = Session::new()
            .map_err(|e| format!("Failed to create jump host session: {}", e))?;
        jump_session.set_tcp_stream(jump_tcp);
        jump_session
            .handshake()
            .map_err(|e| format!("Jump host handshake failed: {}", e))?;

        Self::authenticate(&jump_session, jump_host)?;

        // Open a direct-tcpip channel from the jump host to the target host.
        // This creates a tunnel: jump_host -> target_host:target_port
        let mut channel = jump_session
            .channel_direct_tcpip(&connection.host, connection.port, None)
            .map_err(|e| format!("Failed to open direct-tcpip channel to {}:{}: {}", 
                connection.host, connection.port, e))?;

        // Bind a local TCP listener on an ephemeral port (127.0.0.1:0)
        // that will act as a proxy between the target SSH session and the
        // jump host's direct-tcpip channel.
        let listener = TcpListener::bind("127.0.0.1:0")
            .map_err(|e| format!("Failed to bind local proxy listener: {}", e))?;
        
        let local_addr = listener.local_addr()
            .map_err(|e| format!("Failed to get local address: {}", e))?;

        // Spawn a background thread that accepts one connection and shuttles
        // bytes bidirectionally between the local TcpStream and the SSH channel.
        thread::spawn(move || {
            // Accept exactly one connection (the target SSH session below)
            let Ok((mut local_stream, _)) = listener.accept() else {
                return;
            };

            // Shuttle bytes in both directions until either side closes
            let mut buf = vec![0u8; 8192];
            local_stream.set_nonblocking(true).ok();
            
            loop {
                let mut progress = false;

                // Local -> Channel
                match local_stream.read(&mut buf) {
                    Ok(0) => break, // EOF
                    Ok(n) => {
                        if channel.write_all(&buf[..n]).is_err() {
                            break;
                        }
                        let _ = channel.flush();
                        progress = true;
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(_) => break,
                }

                // Channel -> Local
                match channel.read(&mut buf) {
                    Ok(0) => break, // EOF
                    Ok(n) => {
                        if local_stream.write_all(&buf[..n]).is_err() {
                            break;
                        }
                        let _ = local_stream.flush();
                        progress = true;
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {}
                    Err(_) => break,
                }

                if !progress {
                    thread::sleep(std::time::Duration::from_millis(5));
                }
            }
        });

        // Give the proxy thread a moment to start listening
        thread::sleep(std::time::Duration::from_millis(50));

        // Connect to the local proxy as if it were the target SSH server.
        // This TcpStream satisfies Session::set_tcp_stream's AsRawSocket bound.
        let proxy_tcp = TcpStream::connect(local_addr)
            .map_err(|e| format!("Failed to connect to local proxy: {}", e))?;

        // Create a new SSH session using the proxied connection
        let mut target_session = Session::new()
            .map_err(|e| format!("Failed to create target session: {}", e))?;

        target_session.set_tcp_stream(proxy_tcp);
        target_session
            .handshake()
            .map_err(|e| format!("Target SSH handshake failed: {}", e))?;

        Self::authenticate(&target_session, connection)?;

        // Store both sessions so the jump session stays alive
        self._jump_session = Some(jump_session);
        self.session = Some(target_session);

        Ok(())
    }

    fn authenticate(session: &Session, connection: &Connection) -> Result<(), String> {
        let username = connection
            .username
            .as_ref()
            .ok_or("Username is required for SSH")?;

        if let Some(private_key_path) = &connection.private_key_path {
            session
                .userauth_pubkey_file(
                    username,
                    None,
                    std::path::Path::new(private_key_path),
                    connection.private_key_passphrase.as_deref(),
                )
                .map_err(|e| format!("SSH key authentication failed: {}", e))?;
        } else if let Some(password) = &connection.password {
            session
                .userauth_password(username, password)
                .map_err(|e| format!("SSH password authentication failed: {}", e))?;
        } else {
            return Err("Either password or private key is required".to_string());
        }

        if !session.authenticated() {
            return Err("SSH authentication failed".to_string());
        }

        Ok(())
    }

    /// Execute a command on the remote server
    pub fn execute_command(&self, command: &str) -> Result<String, String> {
        let session = self.session.as_ref().ok_or("Not connected")?;

        let mut channel = session
            .channel_session()
            .map_err(|e| format!("Failed to open channel: {}", e))?;

        channel
            .exec(command)
            .map_err(|e| format!("Failed to execute command: {}", e))?;

        let mut output = String::new();
        channel
            .read_to_string(&mut output)
            .map_err(|e| format!("Failed to read output: {}", e))?;

        channel
            .wait_close()
            .map_err(|e| format!("Failed to close channel: {}", e))?;

        let exit_status = channel
            .exit_status()
            .map_err(|e| format!("Failed to get exit status: {}", e))?;

        if exit_status != 0 {
            return Err(format!(
                "Command failed with exit code {}: {}",
                exit_status, output
            ));
        }

        Ok(output)
    }

    /// Test connection
    pub fn test_connection(&self) -> Result<String, String> {
        self.execute_command("echo 'Connection successful'")
    }

    /// Disconnect
    pub fn disconnect(&mut self) -> Result<(), String> {
        // Close shell channel first if open
        if let Ok(mut guard) = self.shell_channel.lock() {
            if let Some(mut channel) = guard.take() {
                let _ = channel.close();
                let _ = channel.wait_close();
            }
        }
        
        if let Some(session) = self.session.take() {
            session
                .disconnect(None, "Goodbye", None)
                .map_err(|e| format!("Failed to disconnect: {}", e))?;
        }
        if let Some(jump_session) = self._jump_session.take() {
            let _ = jump_session.disconnect(None, "Goodbye", None);
        }
        Ok(())
    }

    /// Open an interactive shell (PTY) and start streaming output to Flutter.
    /// This spawns a background thread that continuously reads from the channel
    /// and sends data chunks via the `output_sink`.
    ///
    /// Call `send_input` to write data to the shell, and `resize_pty` to update
    /// terminal dimensions.
    pub fn open_shell(
        &self,
        term_type: String,
        cols: u32,
        rows: u32,
        output_sink: StreamSink<Vec<u8>>,
    ) -> Result<(), String> {
        let session = self.session.as_ref().ok_or("Not connected")?;

        // Request a PTY and start the shell
        let mut channel = session
            .channel_session()
            .map_err(|e| format!("Failed to open channel: {}", e))?;

        channel
            .request_pty(&term_type, None, Some((cols, rows, 0, 0)))
            .map_err(|e| format!("Failed to request PTY: {}", e))?;

        channel
            .shell()
            .map_err(|e| format!("Failed to start shell: {}", e))?;

        // CRITICAL: Switch to non-blocking mode to prevent deadlock.
        // The reader thread would otherwise block indefinitely while holding
        // the session lock, preventing send_input from writing.
        session.set_blocking(false);

        // Store the channel for later write/resize/close operations
        {
            let mut guard = self.shell_channel.lock().unwrap();
            *guard = Some(channel.clone());
        }

        // Spawn a background thread to continuously read output and stream to Flutter
        thread::spawn(move || {
            let mut buf = [0u8; 4096];
            loop {
                match channel.read(&mut buf) {
                    Ok(0) => {
                        // EOF reached
                        break;
                    }
                    Ok(n) => {
                        let data = buf[..n].to_vec();
                        if output_sink.add(data).is_err() {
                            // Flutter side closed the stream
                            break;
                        }
                    }
                    Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                        // No data available yet in non-blocking mode, sleep briefly
                        thread::sleep(std::time::Duration::from_millis(10));
                    }
                    Err(e) => {
                        // Real read error (connection dropped, etc.)
                        eprintln!("SSH shell read error: {}", e);
                        break;
                    }
                }
            }
            // Stream will be automatically closed when output_sink is dropped
        });

        Ok(())
    }

    /// Send input (keystrokes) to the interactive shell.
    pub fn send_input(&self, data: Vec<u8>) -> Result<(), String> {
        let guard = self.shell_channel.lock().unwrap();
        let channel = guard.as_ref().ok_or("Shell not opened")?;

        let mut ch = channel.clone();
        
        // In non-blocking mode, retry WouldBlock errors briefly
        let mut written = 0;
        let timeout = std::time::Duration::from_secs(2);
        let start = std::time::Instant::now();
        
        while written < data.len() {
            match ch.write(&data[written..]) {
                Ok(n) => written += n,
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                    if start.elapsed() > timeout {
                        return Err("Write timeout: shell not ready".to_string());
                    }
                    thread::sleep(std::time::Duration::from_millis(10));
                }
                Err(e) => return Err(format!("Failed to write to shell: {}", e)),
            }
        }
        
        ch.flush()
            .map_err(|e| format!("Failed to flush shell: {}", e))?;

        Ok(())
    }

    /// Resize the PTY when terminal window size changes.
    pub fn resize_pty(&self, cols: u32, rows: u32) -> Result<(), String> {
        let guard = self.shell_channel.lock().unwrap();
        let channel = guard.as_ref().ok_or("Shell not opened")?;

        let mut ch = channel.clone();

        // request_pty_size can also return WouldBlock in non-blocking mode;
        // retry briefly rather than failing the resize outright.
        let timeout = std::time::Duration::from_secs(1);
        let start = std::time::Instant::now();
        loop {
            match ch.request_pty_size(cols, rows, None, None) {
                Ok(()) => break,
                Err(e) if e.to_string().contains("EAGAIN") || format!("{:?}", e).contains("WouldBlock") => {
                    if start.elapsed() > timeout {
                        return Err("Resize timeout: shell not ready".to_string());
                    }
                    thread::sleep(std::time::Duration::from_millis(10));
                }
                Err(e) => return Err(format!("Failed to resize PTY: {}", e)),
            }
        }

        Ok(())
    }

    /// Close the interactive shell.
    pub fn close_shell(&self) -> Result<(), String> {
        let mut guard = self.shell_channel.lock().unwrap();
        if let Some(mut channel) = guard.take() {
            // Best-effort close; non-blocking mode may return WouldBlock here,
            // which is fine to ignore since we're tearing the channel down anyway.
            let _ = channel.close();
            let _ = channel.wait_close();
        }
        Ok(())
    }
}

impl Drop for SshConnection {
    fn drop(&mut self) {
        let _ = self.disconnect();
    }
}

/// Test SSH connection (standalone function for FFI), optionally tunneled
/// through a jump host.
pub fn test_ssh_connection(
    host: String,
    port: u16,
    username: String,
    password: Option<String>,
    private_key_path: Option<String>,
    private_key_passphrase: Option<String>,
) -> Result<String, String> {
    let connection = Connection {
        id: "test".to_string(),
        name: "test".to_string(),
        protocol: super::models::Protocol::Ssh,
        host,
        port,
        username: Some(username),
        password,
        private_key_path,
        private_key_passphrase,
        folder_id: None,
        tags: Vec::new(),
        notes: None,
        jump_host_id: None,
        timeout_seconds: 10,
        domain: None,
    };

    let mut ssh = SshConnection::new();
    ssh.connect(&connection)?;
    ssh.test_connection()
}
